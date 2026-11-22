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

/**
 * 排行榜数据结构，three 个文件对位上游（都是 Parcelable POJO，本层无 Parcelable）：
 *   topList/TopListItem.java       (S0xxx) —— 单个条目（gid/href/token/tag/value）
 *   topList/TopListItemArray.java  —— 定长 10 的条目数组
 *   topList/TopListInfo.java       —— 一个榜单的四个时间段 + 标题 + 类型
 *
 * 合并进一个文件的原因：三者互相引用且都只有字段+两三个访问器；
 * 分开会形成 3 个 30 行的循环 import 文件。类名、字段名、方法名与上游一致。
 */

/** 1:1 对位 `topList/TopListItem.java`。 */
export class TopListItem {
  gid: string = '';
  href: string = '';
  token: string = '';
  tag: string = '';
  value: string = '';
}

/** 1:1 对位 `topList/TopListItemArray.java`：`itemArray` 固定长度 10（上游 `new TopListItem[10]`）。 */
export class TopListItemArray {
  itemArray: TopListItem[] = [];

  length(): number {
    return this.itemArray.length;
  }

  get(index: number): TopListItem {
    return this.itemArray[index];
  }
}

/**
 * 1:1 对位 `topList/TopListInfo.java`。
 * `get(index)` 的顺序是 **yesterday → pastMonth → pastYear → allTime**（上游如此，别按字段声明顺序改）。
 */
export class TopListInfo {
  allTimeTopList: TopListItemArray | null = null;
  pastYearTopList: TopListItemArray | null = null;
  pastMonthTopList: TopListItemArray | null = null;
  yesterdayTopList: TopListItemArray | null = null;
  title: string = '';
  /** 对齐 EhTopListDetail.ListType（数值 = 上游枚举 ordinal）。 */
  type: number = 0;

  get(index: number): TopListItemArray | null {
    switch (index) {
      case 0:
        return this.yesterdayTopList;
      case 1:
        return this.pastMonthTopList;
      case 2:
        return this.pastYearTopList;
      case 3:
        return this.allTimeTopList;
      default:
        return null;
    }
  }

  size(): number {
    return 4;
  }
}

/** 1:1 对位 `EhTopListDetail.ListType`（顺序即 ordinal，TopListInfo.type 存的就是它）。 */
export class TopListType {
  static readonly GALLERY: number = 0;
  static readonly UPLOADER: number = 1;
  static readonly TAGGING: number = 2;
  static readonly HENTAI_HOME: number = 3;
  static readonly EH_TRACKER: number = 4;
  static readonly CLEANUP: number = 5;
  static readonly RATING_AND_REVIEWING: number = 6;
}

/** 1:1 对位 `EhTopListDetail.java`。 */
export class EhTopListDetail {
  title: string = '';
  galleryTopListInfo: TopListInfo | null = null;
  uploaderTopListInfo: TopListInfo | null = null;
  taggingTopListInfo: TopListInfo | null = null;
  hentaiHomeTopListInfo: TopListInfo | null = null;
  ehTrackerTopListInfo: TopListInfo | null = null;
  cleanUpTopListInfo: TopListInfo | null = null;
  ratingAndReviewingTopListInfo: TopListInfo | null = null;

  get(index: number): TopListInfo | null {
    switch (index) {
      case 0:
        return this.galleryTopListInfo;
      case 1:
        return this.uploaderTopListInfo;
      case 2:
        return this.taggingTopListInfo;
      case 3:
        return this.hentaiHomeTopListInfo;
      case 4:
        return this.ehTrackerTopListInfo;
      case 5:
        return this.cleanUpTopListInfo;
      case 6:
        return this.ratingAndReviewingTopListInfo;
      default:
        return null;
    }
  }
}
