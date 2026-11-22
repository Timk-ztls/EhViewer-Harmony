/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/sync/DownloadListInfosExecutor.java（530 行）。
 *
 * 职责：下载页的「搜索 / 过滤 / 排序」后台执行器。全部是纯调度逻辑，不碰网络。
 *
 * 行为等价说明：
 *   1. 上游 `Executors.newSingleThreadExecutor()` + `handler.post(...)` 回主线程：
 *      这里 `executeSearching()` / `executeFilterAndSort()` 返回 Promise，串行队列由
 *      调用方或内部 `lastTask` 链保证（`enqueue` 把新任务接到上一个任务尾部，
 *      等价于单线程执行器的串行语义）。
 *   2. `R.id.*` 在 ArkTS 不存在。上游用 `switch (id)` 分派 30 多个菜单项，这里改成
 *      `DownloadListFilterId` 常量表（**只保留身份语义**，具体数值由本文件定义，
 *      与 Android 生成值无关；ui-scene 侧应 import 这些常量，不要硬编码数字）。
 *   3. 两个同名构造器（`(List, String)` 与 `(List, DownloadManager)`）在 ArkTS 不允许重载，
 *      保留前者的构造器 + `forDownloadManager(list)` 静态工厂；后者上游本来就把 searchKey
 *      置空并**完全忽略** downloadManager 参数，行为一致。
 *   4. 归并排序 `sortByType` 的**手写二路归并**逐行保留（不用 `Array.sort`：
 *      上游比较器对 null / -1（未计算大小）有特殊落位规则，换成 `sort` 会改变稳定性和落位）。
 *   5. `searchingInBackground()` 有一个上游细节：`mDownloadSearchCallback == null` 时返回空列表
 *      （而不是 mList）。这个"奇怪但真实"的行为保留，不加修正。
 *   6. `getSearchableTags` 有副作用：把算出来的 tagList **写回** `info.tgList`（缓存）。
 *      保留。因此同一 info 二次搜索会走 tgList 快路径。
 *   7. `matchSingleTag` 的匹配规则（namespace 必须相等、tagName 相等或 contains）保留；
 *      `splitSearchTags` 用 `\s{2,}`（连续两个以上空白才分多标签）保留。
 *   8. `calculateDownloadDirSize` / `calculateFolderSize` 递归求目录大小，异常返回 -1；
 *      结果写回 `info.fileSize`（-1 表示未计算，排序时排最后）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

import { DownloadSearchCallback } from '../callBack/DownloadSearchCallback';
import { EhConfig } from '../client/EhConfig';
import { EhUtils } from '../client/EhUtils';
import { DownloadManager } from '../download/DownloadManager';
import { DownloadInfo } from '../dao/DownloadInfo';
import { GalleryTags } from '../dao/GalleryTags';
import { EhDB } from '../EhDB';
import { SpiderDen } from '../spider/SpiderDen';
import { UniFile } from '../../unifile/UniFile';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'DownloadSearchingExecutor';

/**
 * 上游 `R.id.*` 的身份常量。
 *
 * 数值本身无意义（只要互不相同、且与 ui-scene 侧引用同一份即可）；
 * 顺序按上游 `executeFilterAndSort` 的 switch 分支排列，便于逐行对照。
 */
export class DownloadListFilterId {
  // 状态过滤
  public static readonly DOWNLOAD_DONE: number = 1;
  public static readonly NOT_STARTED: number = 2;
  public static readonly WAITING: number = 3;
  public static readonly DOWNLOADING: number = 4;
  public static readonly FAILED: number = 5;
  // 排序
  public static readonly SORT_BY_GALLERY_ID_ASC: number = 11;
  public static readonly SORT_BY_GALLERY_ID_DESC: number = 12;
  public static readonly SORT_BY_CREATE_TIME_ASC: number = 13;
  public static readonly SORT_BY_CREATE_TIME_DESC: number = 14;
  public static readonly SORT_BY_RATING_ASC: number = 15;
  public static readonly SORT_BY_RATING_DESC: number = 16;
  public static readonly SORT_BY_NAME_ASC: number = 17;
  public static readonly SORT_BY_NAME_DESC: number = 18;
  public static readonly SORT_BY_FILE_SIZE_ASC: number = 19;
  public static readonly SORT_BY_FILE_SIZE_DESC: number = 20;
  // 分类过滤
  public static readonly ALL_KIND: number = 31;
  public static readonly MISC: number = 32;
  public static readonly DOUJINSHI: number = 33;
  public static readonly MANGA: number = 34;
  public static readonly ARTIST_CG: number = 35;
  public static readonly GAME_CG: number = 36;
  public static readonly IMAGE_SET: number = 37;
  public static readonly COSPLAY: number = 38;
  public static readonly ASIAN_PORN: number = 39;
  public static readonly NON_H: number = 40;
  public static readonly WESTERN: number = 41;
  public static readonly UNKNOWN: number = 42;
  // 其他
  public static readonly LOCAL_IMPORT: number = 51;
  public static readonly ALL: number = 61;
  public static readonly SORT_BY_DEFAULT: number = 62;
}

export class DownloadListInfosExecutor {
  private readonly list: DownloadInfo[] | null;
  private readonly searchKey: string;

  private downloadSearchCallback: DownloadSearchCallback | null = null;

  private resultList: DownloadInfo[] | null = null;

  /** 串行执行链：等价于上游 `newSingleThreadExecutor()` 的排队语义。 */
  private tail: Promise<void> = Promise.resolve();

  constructor(list: DownloadInfo[] | null, searchKey: string) {
    this.list = list;
    this.searchKey = searchKey;
  }

  /**
   * 上游第二个构造器 `(List, DownloadManager)` —— 只保留签名形状，
   * 上游实现里同样把 searchKey 置空且不使用 downloadManager 参数。
   */
  public static forDownloadManager(list: DownloadInfo[] | null,
    downloadManager: DownloadManager | null): DownloadListInfosExecutor {
    if (downloadManager === null) {
      hilog.debug(DOMAIN, TAG, 'forDownloadManager: downloadManager is null, ignored (same as upstream)');
    }
    return new DownloadListInfosExecutor(list, '');
  }

  public setDownloadSearchingListener(downloadSearchCallback: DownloadSearchCallback | null): void {
    this.downloadSearchCallback = downloadSearchCallback;
  }

  public getResultList(): DownloadInfo[] | null {
    return this.resultList;
  }

  /**
   * 对应上游 `executeSearching()`。
   */
  public executeSearching(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      this.resultList = await this.searchingInBackground();
      this.post(this.resultList);
    });
  }

  /**
   * 对应上游 `executeFilterAndSort(int id)`。
   */
  public executeFilterAndSort(id: number): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      let result: DownloadInfo[] | null;
      switch (id) {
        case DownloadListFilterId.DOWNLOAD_DONE:
          result = this.filterDownloadState(DownloadInfo.STATE_FINISH);
          break;
        case DownloadListFilterId.NOT_STARTED:
          result = this.filterDownloadState(DownloadInfo.STATE_NONE);
          break;
        case DownloadListFilterId.WAITING:
          result = this.filterDownloadState(DownloadInfo.STATE_WAIT);
          break;
        case DownloadListFilterId.DOWNLOADING:
          result = this.filterDownloadState(DownloadInfo.STATE_DOWNLOAD);
          break;
        case DownloadListFilterId.FAILED:
          result = this.filterDownloadState(DownloadInfo.STATE_FAILED);
          break;
        case DownloadListFilterId.SORT_BY_GALLERY_ID_ASC:
        case DownloadListFilterId.SORT_BY_GALLERY_ID_DESC:
        case DownloadListFilterId.SORT_BY_CREATE_TIME_ASC:
        case DownloadListFilterId.SORT_BY_CREATE_TIME_DESC:
        case DownloadListFilterId.SORT_BY_RATING_ASC:
        case DownloadListFilterId.SORT_BY_RATING_DESC:
        case DownloadListFilterId.SORT_BY_NAME_ASC:
        case DownloadListFilterId.SORT_BY_NAME_DESC:
        case DownloadListFilterId.SORT_BY_FILE_SIZE_ASC:
        case DownloadListFilterId.SORT_BY_FILE_SIZE_DESC:
          result = await this.sortByType(id);
          break;
        case DownloadListFilterId.ALL_KIND:
        case DownloadListFilterId.MISC:
        case DownloadListFilterId.DOUJINSHI:
        case DownloadListFilterId.MANGA:
        case DownloadListFilterId.ARTIST_CG:
        case DownloadListFilterId.GAME_CG:
        case DownloadListFilterId.IMAGE_SET:
        case DownloadListFilterId.COSPLAY:
        case DownloadListFilterId.ASIAN_PORN:
        case DownloadListFilterId.NON_H:
        case DownloadListFilterId.WESTERN:
        case DownloadListFilterId.UNKNOWN:
          result = this.filterDownloadKind(id);
          break;
        case DownloadListFilterId.LOCAL_IMPORT:
          result = this.filterLocalImport();
          break;
        case DownloadListFilterId.ALL:
        case DownloadListFilterId.SORT_BY_DEFAULT:
        default:
          result = this.list;
          break;
      }
      this.resultList = result;
      this.post(result);
    });
  }

  private enqueue(body: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.tail.then(body).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'task failed: %{public}s', this.errorToString(e as Object));
    });
    this.tail = next;
    return next;
  }

  private post(result: DownloadInfo[] | null): void {
    const callback: DownloadSearchCallback | null = this.downloadSearchCallback;
    if (callback === null) {
      return;
    }
    callback.onDownloadSearchSuccess(result);
  }

  /**
   * 对应上游 `sortByType(type)`：手写自底向上二路归并，逐行保留。
   */
  private async sortByType(type: number): Promise<DownloadInfo[]> {
    if (this.list === null) {
      return [];
    }
    const arr: DownloadInfo[] = this.list.slice();

    // 按文件大小排序前，先补齐未计算过的大小（-1 表示未计算）
    if (type === DownloadListFilterId.SORT_BY_FILE_SIZE_ASC ||
      type === DownloadListFilterId.SORT_BY_FILE_SIZE_DESC) {
      for (let i = 0; i < arr.length; i++) {
        const info: DownloadInfo = arr[i];
        if (info.fileSize < 0) {
          info.fileSize = await this.calculateDownloadDirSize(info);
        }
      }
    }

    const n: number = arr.length;
    for (let i = 1; i < n; i += i) {
      let left: number = 0;
      let mid: number = left + i - 1;
      let right: number = mid + i;
      while (right < n) {
        this.merge(arr, left, mid, right, type);
        left = right + 1;
        mid = left + i - 1;
        right = mid + i;
      }
      if (left < n && mid < n) {
        this.merge(arr, left, mid, n - 1, type);
      }
    }
    return arr;
  }

  /**
   * 对应上游静态 `merge(arr, left, mid, right, sortType)`。
   * 注意比较语义逐分支保留（含 null 标题与 fileSize = -1 落最后）。
   */
  private merge(arr: DownloadInfo[], left: number, mid: number, right: number, sortType: number): void {
    const a: DownloadInfo[] = new Array<DownloadInfo>(right - left + 1);
    let i: number = left;
    let j: number = mid + 1;
    let k: number = 0;
    while (i <= mid && j <= right) {
      switch (sortType) {
        case DownloadListFilterId.SORT_BY_GALLERY_ID_ASC:
          if (arr[i].gid < arr[j].gid) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        case DownloadListFilterId.SORT_BY_GALLERY_ID_DESC:
          if (arr[i].gid > arr[j].gid) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        case DownloadListFilterId.SORT_BY_CREATE_TIME_ASC:
          if (arr[i].time < arr[j].time) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        case DownloadListFilterId.SORT_BY_CREATE_TIME_DESC:
          if (arr[i].time > arr[j].time) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        case DownloadListFilterId.SORT_BY_RATING_ASC:
          if (arr[i].rating < arr[j].rating) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        case DownloadListFilterId.SORT_BY_RATING_DESC:
          if (arr[i].rating > arr[j].rating) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        case DownloadListFilterId.SORT_BY_NAME_ASC: {
          const titleI: string | null = arr[i].title;
          const titleJ: string | null = arr[j].title;
          if (titleI === null && titleJ === null) {
            a[k++] = arr[i++];
          } else if (titleI === null) {
            a[k++] = arr[j++];
          } else if (titleJ === null) {
            a[k++] = arr[i++];
          } else if (this.compareToIgnoreCase(titleI, titleJ) < 0) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        }
        case DownloadListFilterId.SORT_BY_NAME_DESC: {
          const titleI: string | null = arr[i].title;
          const titleJ: string | null = arr[j].title;
          if (titleI === null && titleJ === null) {
            a[k++] = arr[i++];
          } else if (titleI === null) {
            a[k++] = arr[j++];
          } else if (titleJ === null) {
            a[k++] = arr[i++];
          } else if (this.compareToIgnoreCase(titleI, titleJ) > 0) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        }
        case DownloadListFilterId.SORT_BY_FILE_SIZE_ASC:
          if (arr[i].fileSize < 0 && arr[j].fileSize < 0) {
            a[k++] = arr[i++];
          } else if (arr[i].fileSize < 0) {
            a[k++] = arr[j++];
          } else if (arr[j].fileSize < 0) {
            a[k++] = arr[i++];
          } else if (arr[i].fileSize < arr[j].fileSize) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        case DownloadListFilterId.SORT_BY_FILE_SIZE_DESC:
          if (arr[i].fileSize < 0 && arr[j].fileSize < 0) {
            a[k++] = arr[i++];
          } else if (arr[i].fileSize < 0) {
            a[k++] = arr[j++];
          } else if (arr[j].fileSize < 0) {
            a[k++] = arr[i++];
          } else if (arr[i].fileSize > arr[j].fileSize) {
            a[k++] = arr[i++];
          } else {
            a[k++] = arr[j++];
          }
          break;
        default:
          // 上游此时 switch 无 default 分支，比较结果未定义（`a[k++]` 未赋值）——
          // 调用点保证只有排序类 id 会进来，这里退化为直接取左侧，避免写出 undefined。
          a[k++] = arr[i++];
          break;
      }
    }
    while (i <= mid) {
      a[k++] = arr[i++];
    }
    while (j <= right) {
      a[k++] = arr[j++];
    }
    for (i = 0; i < k; i++) {
      arr[left++] = a[i];
    }
  }

  /**
   * `String.compareToIgnoreCase` 的等价实现（逐 UTF-16 码元、大小写折叠后比较）。
   * 不能用 `localeCompare`：行为随 locale 变化，上游是不受 locale 影响的大小写无关比较。
   */
  private compareToIgnoreCase(lhs: string, rhs: string): number {
    const n1: number = lhs.length;
    const n2: number = rhs.length;
    const min: number = Math.min(n1, n2);
    for (let i = 0; i < min; i++) {
      let c1: number = lhs.charCodeAt(i);
      let c2: number = rhs.charCodeAt(i);
      if (c1 !== c2) {
        c1 = this.toUpperCaseCode(c1);
        c2 = this.toUpperCaseCode(c2);
        if (c1 !== c2) {
          return c1 - c2;
        }
      }
    }
    return n1 - n2;
  }

  private toUpperCaseCode(c: number): number {
    const s: string = String.fromCharCode(c).toUpperCase();
    if (s.length === 1) {
      return s.charCodeAt(0);
    }
    return c;
  }

  private filterDownloadState(state: number): DownloadInfo[] {
    const list: DownloadInfo[] = [];
    if (this.list === null) {
      return list;
    }
    for (let i = 0; i < this.list.length; i++) {
      const info: DownloadInfo = this.list[i];
      if (info.state === state) {
        list.push(info);
      }
    }
    return list;
  }

  /**
   * 注意上游细节：`mList == null` 时返回 **null**（不是空列表），
   * 而 `filterDownloadState` 返回空列表。保持这种不对称。
   */
  private filterDownloadKind(state: number): DownloadInfo[] | null {
    const kind: number = this.kindValue(state);
    const list: DownloadInfo[] = [];
    if (this.list === null) {
      return null;
    }
    if (kind === EhUtils.ALL_CATEGORY) {
      return this.list;
    }
    for (let i = 0; i < this.list.length; i++) {
      const info: DownloadInfo = this.list[i];
      if (info.category === kind) {
        list.push(info);
      }
    }
    return list;
  }

  private filterLocalImport(): DownloadInfo[] {
    const list: DownloadInfo[] = [];
    if (this.list === null) {
      return list;
    }
    for (let i = 0; i < this.list.length; i++) {
      const info: DownloadInfo = this.list[i];
      if (info.archiveUri !== null && info.archiveUri.length > 0) {
        list.push(info);
      }
    }
    return list;
  }

  /**
   * 对应上游 `searchingInBackground()`。
   */
  protected async searchingInBackground(): Promise<DownloadInfo[] | null> {
    if (this.downloadSearchCallback === null) {
      return [];
    }
    // 只判空串：`searchKey` 在 ArkTS 侧声明为 `string`（构造器形参类型也是 string），
    // 上游 `if (mSearchKey == null || mSearchKey.isEmpty())` 的前半句在 Java 里非死代码
    // （形参无 @NonNull），但在严格类型化之后**恒为 false** —— 保留会变成死判空（CI 闸门会报）。
    // 上游的 null 分支由 `splitSearchTags(searchKey: string | null)` 保留（那里确实可能收到 null）。
    if (this.searchKey.length === 0) {
      return this.list;
    }
    if (this.list === null) {
      return [];
    }
    const cache: DownloadInfo[] = [];
    for (let i = 0; i < this.list.length; i++) {
      const info: DownloadInfo = this.list[i];
      if (EhUtils.judgeSuitableTitle(info, this.searchKey)) {
        cache.push(info);
      } else if (await this.matchTag(this.searchKey, info)) {
        cache.push(info);
      }
    }
    return cache;
  }

  private async matchTag(searchKey: string, info: DownloadInfo): Promise<boolean> {
    const searchableTags: string[] = await this.getSearchableTags(info);
    if (searchableTags.length === 0) {
      return false;
    }
    const searchTags: string[] = DownloadListInfosExecutor.splitSearchTags(searchKey);
    if (searchTags.length === 0) {
      return false;
    }
    for (let i = 0; i < searchTags.length; i++) {
      const searchTag: string = searchTags[i];
      let matched: boolean = false;
      for (let j = 0; j < searchableTags.length; j++) {
        if (DownloadListInfosExecutor.matchSingleTag(searchableTags[j], searchTag)) {
          matched = true;
          break;
        }
      }
      if (!matched) {
        return false;
      }
    }
    return true;
  }

  /**
   * 对应上游 `getSearchableTags(info)`：有 tgList 直接用，否则由 simpleTags 构造，
   * 再否则查库；**结果写回 info.tgList 作为缓存**（上游副作用，保留）。
   */
  private async getSearchableTags(info: DownloadInfo): Promise<string[]> {
    if (info.tgList !== null && info.tgList.length > 0) {
      return info.tgList;
    }
    const tagList: string[] = [];
    if (info.simpleTags !== null) {
      for (let i = 0; i < info.simpleTags.length; i++) {
        const tag: string | null = info.simpleTags[i];
        if (tag !== null && tag.length > 0) {
          tagList.push(tag);
        }
      }
    }
    if (tagList.length === 0) {
      const dbTags: string[] | null = await this.searchTagList(info.gid);
      if (dbTags !== null && dbTags.length > 0) {
        for (let i = 0; i < dbTags.length; i++) {
          tagList.push(dbTags[i]);
        }
      }
    }
    info.tgList = tagList;
    return tagList;
  }

  /**
   * 对应上游静态 `splitSearchTags(searchKey)`：连续两个以上空白才切成多个标签。
   */
  private static splitSearchTags(searchKey: string | null): string[] {
    if (searchKey === null) {
      return [];
    }
    const normalized: string = searchKey.trim();
    if (normalized.length === 0) {
      return [];
    }
    const rawTags: string[] = normalized.split(/\s{2,}/);
    const tags: string[] = [];
    for (let i = 0; i < rawTags.length; i++) {
      const rawTag: string | null = rawTags[i];
      if (rawTag === null) {
        continue;
      }
      const tag: string = rawTag.trim();
      if (tag.length > 0) {
        tags.push(tag);
      }
    }
    return tags;
  }

  /**
   * 对应上游静态 `matchSingleTag(tag, searchTag)`。
   */
  private static matchSingleTag(tag: string | null, searchTag: string | null): boolean {
    if (tag === null || searchTag === null) {
      return false;
    }
    const normalizedTag: string = tag.trim().toLowerCase();
    const normalizedSearchTag: string = searchTag.trim().toLowerCase();
    if (normalizedTag.length === 0 || normalizedSearchTag.length === 0) {
      return false;
    }
    const tagIndex: number = normalizedTag.indexOf(':');
    const tagNamespace: string | null = tagIndex >= 0 ? normalizedTag.substring(0, tagIndex) : null;
    const tagName: string = tagIndex >= 0 ? normalizedTag.substring(tagIndex + 1) : normalizedTag;

    const searchTagIndex: number = normalizedSearchTag.indexOf(':');
    const searchNamespace: string | null =
      searchTagIndex >= 0 ? normalizedSearchTag.substring(0, searchTagIndex) : null;
    const searchName: string = searchTagIndex >= 0 ?
      normalizedSearchTag.substring(searchTagIndex + 1) : normalizedSearchTag;

    if (searchNamespace !== null && (tagNamespace === null || tagNamespace !== searchNamespace)) {
      return false;
    }
    if (searchName.length === 0) {
      return false;
    }
    if (tagName === searchName) {
      return true;
    }
    return tagName.indexOf(searchName) >= 0;
  }

  /**
   * 对应上游 `searchTagList(gid)`：查库拿 GalleryTags，再按 "分组:标签" 摊平。
   * 上游返回类型是可空 ArrayList —— 保留 null。
   */
  private async searchTagList(gid: number): Promise<string[] | null> {
    const tags: GalleryTags | null = await this.queryGalleryTags(gid);
    if (tags === null) {
      return null;
    }
    const tagList: string[] = [];
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('artist', tags.artist));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('rows', tags.rows));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('cosplayer', tags.cosplayer));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('character', tags.character));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('female', tags.female));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('group', tags.group));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('language', tags.language));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('male', tags.male));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('misc', tags.misc));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('mixed', tags.mixed));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('other', tags.other));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('parody', tags.parody));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('reclass', tags.reclass));
    DownloadListInfosExecutor.appendAll(tagList, DownloadListInfosExecutor.parserList('location', tags.location));
    return tagList;
  }

  /**
   * 上游 `EhDB.queryGalleryTags(long)` 是**同步**的；D-012（RDB 全层 async）之后它返回 Promise。
   *
   * 早先这里自造过一个 `queryGalleryTagsSync` "同步快照入口" —— 那是发明 API，core-runtime 不会写，
   * 依赖到位必然编译失败。已删除，改回**同名同语义**的 `queryGalleryTags`。
   * 代价：搜索链路多一层 await（`searchingInBackground` / `matchTag` / `getSearchableTags` /
   * `searchTagList` 一并改 async），收益：依赖一落地即可编译，且不必要求别人加非上游 API。
   * 调用点本来就在 async body 内（`executeSearching` 的 `enqueue(async …)`），无额外延迟。
   */
  private async queryGalleryTags(gid: number): Promise<GalleryTags | null> {
    try {
      return await EhDB.queryGalleryTags(gid);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'queryGalleryTags failed, gid=%{public}d, error=%{public}s',
        gid, this.errorToString(e as Object));
      return null;
    }
  }

  private static appendAll(dst: string[], src: string[]): void {
    for (let i = 0; i < src.length; i++) {
      dst.push(src[i]);
    }
  }

  /**
   * 对应上游 `parserList(name, content)`：按逗号拆，trim 后拼成 `name:tag`。
   */
  private static parserList(name: string | null, content: string | null): string[] {
    if (name === null || content === null) {
      return [];
    }
    const list: string[] = [];
    const tagNames: string[] = content.split(',');
    for (let i = 0; i < tagNames.length; i++) {
      const raw: string | null = tagNames[i];
      if (raw === null) {
        continue;
      }
      const normalized: string = raw.trim();
      if (normalized.length === 0) {
        continue;
      }
      list.push(name + ':' + normalized);
    }
    return list;
  }

  /**
   * 对应上游 `calculateDownloadDirSize(info)`：目录不存在或异常返回 -1。
   */
  private async calculateDownloadDirSize(info: DownloadInfo): Promise<number> {
    try {
      const downloadDir: UniFile | null = await SpiderDen.getGalleryDownloadDir(info);
      if (downloadDir === null || !await downloadDir.isDirectory()) {
        return -1;
      }
      return await this.calculateFolderSize(downloadDir);
    } catch (e) {
      return -1;
    }
  }

  /**
   * 对应上游 `calculateFolderSize(folder)`：递归累加文件大小。
   * 上游对 `files == null` 返回 0（不是 -1），保留。
   */
  private async calculateFolderSize(folder: UniFile): Promise<number> {
    let totalSize: number = 0;
    const files: UniFile[] | null = await folder.listFiles();
    if (files === null) {
      return 0;
    }
    for (let i = 0; i < files.length; i++) {
      const file: UniFile = files[i];
      if (await file.isFile()) {
        const fileSize: number = await file.length();
        if (fileSize > 0) {
          totalSize += fileSize;
        }
      } else if (await file.isDirectory()) {
        totalSize += await this.calculateFolderSize(file);
      }
    }
    return totalSize;
  }

  /**
   * 对应上游 `kindValue(id)`。
   */
  private kindValue(id: number): number {
    switch (id) {
      case DownloadListFilterId.DOUJINSHI:
        return EhConfig.DOUJINSHI;
      case DownloadListFilterId.MANGA:
        return EhConfig.MANGA;
      case DownloadListFilterId.ARTIST_CG:
        return EhConfig.ARTIST_CG;
      case DownloadListFilterId.GAME_CG:
        return EhConfig.GAME_CG;
      case DownloadListFilterId.WESTERN:
        return EhConfig.WESTERN;
      case DownloadListFilterId.NON_H:
        return EhConfig.NON_H;
      case DownloadListFilterId.IMAGE_SET:
        return EhConfig.IMAGE_SET;
      case DownloadListFilterId.COSPLAY:
        return EhConfig.COSPLAY;
      case DownloadListFilterId.ASIAN_PORN:
        return EhConfig.ASIAN_PORN;
      case DownloadListFilterId.MISC:
        return EhConfig.MISC;
      default:
        return EhUtils.ALL_CATEGORY;
    }
  }

  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }
}
