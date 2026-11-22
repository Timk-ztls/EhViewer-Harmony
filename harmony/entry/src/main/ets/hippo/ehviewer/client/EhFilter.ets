/*
 * Copyright 2016 Hippo Seven
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

import { GalleryInfo } from './data/GalleryInfo';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhFilter.java
 * （inventory S0074，281 行）
 *
 * 本地过滤器：四类（标题/上传者/标签/标签命名空间），每条可单独 enable/disable。
 *
 * **返回值语义容易搞反**（上游如此，照搬）：这四个 `filterXxx(info)` 返回的是
 *   **true = 「这条画廊要保留」**，false = 「被过滤掉」。
 * 也就是 `if (!filter.filterTitle(info)) continue;` 的用法。
 *
 * 逐条照搬的细节：
 *   - 标题/标签/命名空间过滤器的 text 在入库与加载时**转小写**；上传者**不转**（区分大小写！）
 *   - 标题匹配用 `contains`；上传者用 `equals`（全等）
 *   - 标签匹配：`ns:name` 拆两段；**两侧都有 namespace 才比较**，只有一侧有就不比较 namespace；
 *     name 必须全等（区分大小写，因为 tag 文本未转小写）
 *   - 命名空间匹配：tag 无 ':' → 不匹配
 *   - `needTags()` = 标签或命名空间过滤器非空（决定是否要请求 tags）
 *
 * 依赖：`com.hippo.ehviewer.dao.Filter`（storage-db 的 dao 实体）+ `EhDB` 的增删查
 * → 用 `FilterLike` + `FilterStore` 注入（C-16 候选）。
 */
export class EhFilter {
  static readonly MODE_TITLE: number = 0;
  static readonly MODE_UPLOADER: number = 1;
  static readonly MODE_TAG: number = 2;
  static readonly MODE_TAG_NAMESPACE: number = 3;

  private _titleFilterList: FilterLike[] = [];
  private _uploaderFilterList: FilterLike[] = [];
  private _tagFilterList: FilterLike[] = [];
  private _tagNamespaceFilterList: FilterLike[] = [];


  constructor(store: FilterStore) {
    const list: FilterLike[] = store.getAllFilter();
    for (let i = 0; i < list.length; i++) {
      const filter: FilterLike = list[i];
      switch (filter.getMode()) {
        case EhFilter.MODE_TITLE:
          filter.setText(filter.getText().toLowerCase());
          this._titleFilterList.push(filter);
          break;
        case EhFilter.MODE_UPLOADER:
          this._uploaderFilterList.push(filter);
          break;
        case EhFilter.MODE_TAG:
          filter.setText(filter.getText().toLowerCase());
          this._tagFilterList.push(filter);
          break;
        case EhFilter.MODE_TAG_NAMESPACE:
          filter.setText(filter.getText().toLowerCase());
          this._tagNamespaceFilterList.push(filter);
          break;
        default:
          break; // 上游 Log.d "Unknown mode"
      }
    }
  }

  getTitleFilterList(): FilterLike[] {
    return this._titleFilterList;
  }

  getUploaderFilterList(): FilterLike[] {
    return this._uploaderFilterList;
  }

  getTagFilterList(): FilterLike[] {
    return this._tagFilterList;
  }

  getTagNamespaceFilterList(): FilterLike[] {
    return this._tagNamespaceFilterList;
  }

  /** 对齐 addFilter：先写库，再转小写入内存表（顺序照搬：写库在前）。 */
  addFilter(filter: FilterLike, store: FilterStore): void {
    filter.setEnable(true);
    store.addFilter(filter);
    switch (filter.getMode()) {
      case EhFilter.MODE_TITLE:
        filter.setText(filter.getText().toLowerCase());
        this._titleFilterList.push(filter);
        break;
      case EhFilter.MODE_UPLOADER:
        this._uploaderFilterList.push(filter);
        break;
      case EhFilter.MODE_TAG:
        filter.setText(filter.getText().toLowerCase());
        this._tagFilterList.push(filter);
        break;
      case EhFilter.MODE_TAG_NAMESPACE:
        filter.setText(filter.getText().toLowerCase());
        this._tagNamespaceFilterList.push(filter);
        break;
      default:
        break;
    }
  }

  triggerFilter(filter: FilterLike, store: FilterStore): void {
    store.triggerFilter(filter);
  }

  deleteFilter(filter: FilterLike, store: FilterStore): void {
    store.deleteFilter(filter);
    switch (filter.getMode()) {
      case EhFilter.MODE_TITLE:
        this.removeFrom(this._titleFilterList, filter);
        break;
      case EhFilter.MODE_UPLOADER:
        this.removeFrom(this._uploaderFilterList, filter);
        break;
      case EhFilter.MODE_TAG:
        this.removeFrom(this._tagFilterList, filter);
        break;
      case EhFilter.MODE_TAG_NAMESPACE:
        this.removeFrom(this._tagNamespaceFilterList, filter);
        break;
      default:
        break;
    }
  }

  private removeFrom(list: FilterLike[], filter: FilterLike): void {
    const idx: number = list.indexOf(filter);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
  }

  /** 对齐 needTags()：有标签或命名空间过滤器就需要 tags。 */
  needTags(): boolean {
    return this._tagFilterList.length !== 0 || this._tagNamespaceFilterList.length !== 0;
  }

  /** 对齐 filterTitle：true = 保留。标题匹配用 contains（大小写不敏感，两边都小写）。 */
  filterTitle(info: GalleryInfo | null): boolean {
    if (info === null) {
      return false;
    }
    const title: string = info.title;
    // 上游是 `null != title`（列表页某些项**真的没有** title）→ 为 null 时**跳过过滤、保留该项**。
    // C-7 起 `title` 恒为 string（缺省 ''），所以判据改成长度：空串按「没有 title」处理，
    // 否则「过滤词为空串」时 `''.indexOf('') === 0` 会把所有空 title 的项误过滤（上游不会）。
    if (title.length > 0 && this._titleFilterList.length > 0) {
      const lower: string = title.toLowerCase();
      for (let i = 0; i < this._titleFilterList.length; i++) {
        const f: FilterLike = this._titleFilterList[i];
        if (f.isEnable() && lower.indexOf(f.getText()) >= 0) {
          return false;
        }
      }
    }
    return true;
  }

  /** 对齐 filterUploader：true = 保留。上传者用 equals，**区分大小写**（上游不转小写）。 */
  filterUploader(info: GalleryInfo | null): boolean {
    if (info === null) {
      return false;
    }
    const uploader: string = info.uploader;
    // 同上：上游 `null != uploader` 时跳过；空串视为「没有上传者」，避免 `'' === ''` 误过滤
    if (uploader.length > 0 && this._uploaderFilterList.length > 0) {
      for (let i = 0; i < this._uploaderFilterList.length; i++) {
        const f: FilterLike = this._uploaderFilterList[i];
        if (f.isEnable() && uploader === f.getText()) {
          return false;
        }
      }
    }
    return true;
  }

  /** 对齐 matchTag(String tag, String filter)。 */
  static matchTag(tag: string | null, filter: string | null): boolean {
    if (tag === null || filter === null) {
      return false;
    }
    let tagNamespace: string | null;
    let tagName: string;
    let filterNamespace: string | null;
    let filterName: string;
    let index: number = tag.indexOf(':');
    if (index < 0) {
      tagNamespace = null;
      tagName = tag;
    } else {
      tagNamespace = tag.substring(0, index);
      tagName = tag.substring(index + 1);
    }
    index = filter.indexOf(':');
    if (index < 0) {
      filterNamespace = null;
      filterName = filter;
    } else {
      filterNamespace = filter.substring(0, index);
      filterName = filter.substring(index + 1);
    }
    if (tagNamespace !== null && filterNamespace !== null && tagNamespace !== filterNamespace) {
      return false;
    }
    return tagName === filterName;
  }

  /** 对齐 filterTag：true = 保留。 */
  filterTag(info: GalleryInfo | null): boolean {
    if (info === null) {
      return false;
    }
    const tags: string[] | null = info.simpleTags;
    if (tags !== null && this._tagFilterList.length > 0) {
      for (let t = 0; t < tags.length; t++) {
        for (let i = 0; i < this._tagFilterList.length; i++) {
          const f: FilterLike = this._tagFilterList[i];
          if (f.isEnable() && EhFilter.matchTag(tags[t], f.getText())) {
            return false;
          }
        }
      }
    }
    return true;
  }

  /** 对齐 matchTagNamespace：tag 无 ':' → false。 */
  static matchTagNamespace(tag: string | null, filter: string | null): boolean {
    if (tag === null || filter === null) {
      return false;
    }
    const index: number = tag.indexOf(':');
    if (index >= 0) {
      return tag.substring(0, index) === filter;
    }
    return false;
  }

  /** 对齐 filterTagNamespace：true = 保留。 */
  filterTagNamespace(info: GalleryInfo | null): boolean {
    if (info === null) {
      return false;
    }
    const tags: string[] | null = info.simpleTags;
    if (tags !== null && this._tagNamespaceFilterList.length > 0) {
      for (let t = 0; t < tags.length; t++) {
        for (let i = 0; i < this._tagNamespaceFilterList.length; i++) {
          const f: FilterLike = this._tagNamespaceFilterList[i];
          if (f.isEnable() && EhFilter.matchTagNamespace(tags[t], f.getText())) {
            return false;
          }
        }
      }
    }
    return true;
  }
}

/** 跨模块契约 C-16 候选：storage-db 的 `com.hippo.ehviewer.dao.Filter` 实现本接口。 */
export interface FilterLike {
  getMode(): number;

  getText(): string;

  setText(text: string): void;

  isEnable(): boolean;

  setEnable(enable: boolean): void;

  getId(): number;
}

/** storage-db 的 `EhDB.addFilter/deleteFilter/triggerFilter/getAllFilter` 注入点。 */
export interface FilterStore {
  getAllFilter(): FilterLike[];

  addFilter(filter: FilterLike): void;

  deleteFilter(filter: FilterLike): void;

  triggerFilter(filter: FilterLike): void;
}
