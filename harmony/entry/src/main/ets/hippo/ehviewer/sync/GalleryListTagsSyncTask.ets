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
 * 移植自 app/src/main/java/com/hippo/ehviewer/sync/GalleryListTagsSyncTask.java（105 行）。
 *
 * **重要行为事实（1:1 保留）**：上游 `executeFunction()` 的循环体整段被注释掉了，
 * 也就是说 `execute()` 实际是**空操作**——只调度一个什么都不做的任务，不写库。
 * 这是上游当前的真实行为，重构不能"顺手修好"它（改了就不是 1:1，且会让列表页
 * 在没被要求的情况下产生额外的库写入）。`executeFunction` 里保留一句显式说明。
 *
 * 其余保留的部分：
 *   1. `getTags(info)`：把 `GalleryInfo.tgList`（形如 `"artist:xxx"` 的扁平字符串）
 *      解析成 `GalleryTags`；`tgList == null || isEmpty()` 返回 null。
 *   2. `parserData(tags, tag)`：`split(":")` 后 `length < 2` 直接返回（注意：上游用
 *      `split(":")` 无 limit，因此 `"group:a:b"` 会丢 `:b` 之后的部分——这是上游行为，
 *      保留；用 `rest` 语义会改变结果）。
 *   3. `getTagString(tagContent, newTag)`：空/ null 直接返回 newTag，否则 `content + "," + newTag`
 *      （与 `GalleryDetailTagsSyncTask` 先收集再拼不同：这里是逐个追加，前导顺序一致）。
 *   4. 未知分组走 `default:` 空分支。
 *   5. 单线程串行：上游 `Executors.newSingleThreadExecutor()`；这里 `execute()` 返回 Promise，
 *      内部串行执行（当前实现为空，因此立即 resolve）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

import { GalleryInfo } from '../client/data/GalleryInfo';
import { GalleryTags } from '../dao/GalleryTags';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'GalleryListTagsSyncTask';

export class GalleryListTagsSyncTask {
  private readonly galleryInfoList: GalleryInfo[];

  private executed: boolean = false;
  private pending: Promise<void> | null = null;

  constructor(galleryInfoList: GalleryInfo[]) {
    this.galleryInfoList = galleryInfoList;
  }

  /**
   * 对应上游 `execute()`：投递到单线程执行器。
   * 返回 Promise 让调用方可选择等待（上游无返回值）。
   */
  public execute(): Promise<void> {
    if (this.pending !== null) {
      return this.pending;
    }
    this.executed = true;
    this.pending = this.executeFunction();
    return this.pending;
  }

  public isExecuted(): boolean {
    return this.executed;
  }

  /**
   * 对应上游 `executeFunction()`。
   *
   * 上游源码里这段循环被整段注释：
   * ```
   * //        for (GalleryInfo info : galleryInfoList) {
   * //            GalleryTags galleryTags = getTags(info);
   * //            ...
   * ```
   * 因此这里同样**不写库**，只保留一个空实现 + 显式日志，方便日后定位
   * "为什么列表页的 tag 没进库"这类问题（答案：上游就是没做）。
   */
  private async executeFunction(): Promise<void> {
    if (this.galleryInfoList.length > 0) {
      hilog.debug(DOMAIN, TAG, 'executeFunction: upstream body is commented out, nothing written, size=%{public}d',
        this.galleryInfoList.length);
    }
    // 上游被注释的写入逻辑（保留原样，不启用）：
    // for (info of this.galleryInfoList) {
    //   const galleryTags = this.getTags(info);
    //   if (galleryTags !== null) {
    //     if (!await EhDB.inGalleryTags(info.gid)) {
    //       await EhDB.insertGalleryTags(galleryTags);
    //     }
    //   }
    // }
    return;
  }

  /**
   * 对应上游 `getTags(info)`：`tgList` 为空返回 null。
   * 当前未被 executeFunction 调用（上游同样未被调用），保留为公开 API 以便后续启用。
   */
  public getTags(info: GalleryInfo): GalleryTags | null {
    const tags: GalleryTags = new GalleryTags(info.gid);

    const groups: string[] | null = info.tgList;
    if (groups === null || groups.length === 0) {
      return null;
    }
    for (let i = 0; i < groups.length; i++) {
      this.parserData(tags, groups[i]);
    }
    return tags;
  }

  /**
   * 对应上游 `parserData(tags, tag)`。
   */
  private parserData(tags: GalleryTags, tag: string): void {
    const tagArr: string[] = tag.split(':');
    if (tagArr.length < 2) {
      return;
    }
    switch (tagArr[0]) {
      case 'rows':
        tags.rows = this.getTagString(tags.rows, tagArr[1]);
        break;
      case 'artist':
        tags.artist = this.getTagString(tags.artist, tagArr[1]);
        break;
      case 'cosplayer':
        tags.cosplayer = this.getTagString(tags.cosplayer, tagArr[1]);
        break;
      case 'character':
        tags.character = this.getTagString(tags.character, tagArr[1]);
        break;
      case 'female':
        tags.female = this.getTagString(tags.female, tagArr[1]);
        break;
      case 'group':
        tags.group = this.getTagString(tags.group, tagArr[1]);
        break;
      case 'language':
        tags.language = this.getTagString(tags.language, tagArr[1]);
        break;
      case 'male':
        tags.male = this.getTagString(tags.male, tagArr[1]);
        break;
      case 'misc':
        tags.misc = this.getTagString(tags.misc, tagArr[1]);
        break;
      case 'mixed':
        tags.mixed = this.getTagString(tags.mixed, tagArr[1]);
        break;
      case 'other':
        tags.other = this.getTagString(tags.other, tagArr[1]);
        break;
      case 'parody':
        tags.parody = this.getTagString(tags.parody, tagArr[1]);
        break;
      case 'reclass':
        tags.reclass = this.getTagString(tags.reclass, tagArr[1]);
        break;
      case 'location':
        tags.location = this.getTagString(tags.location, tagArr[1]);
        break;
      default:
        break;
    }
  }

  /**
   * 对应上游 `getTagString(tagContent, newTag)`：空值直接返回新值，否则逗号追加。
   */
  private getTagString(tagContent: string | null, newTag: string): string {
    if (tagContent === null || tagContent === undefined || tagContent.length === 0) {
      return newTag;
    }
    return tagContent + ',' + newTag;
  }
}
