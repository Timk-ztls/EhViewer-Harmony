/*
 * Copyright 2016 Hippo Seven
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

import {
  TopListInfo,
  TopListItem,
  TopListItemArray,
  TopListType
} from '../../../client/data/TopList';

/** 两个布局的语义键名（上游用 `findViewById(R.id.*)`；ArkTS 无资源 id，保留字符串常量）。 */
export class EhTopListViewHolderKeys {
  /** `gallery_top_list_table_item` 里的榜单标题（上游 `R.id.list_of_time`）。 */
  static readonly LIST_OF_TIME: string = 'list_of_time';

  /** `gallery_top_list_table_item` 里的条目容器（上游 `R.id.list_items_table_view`）。 */
  static readonly LIST_ITEMS_TABLE_VIEW: string = 'list_items_table_view';

  /** `gallery_top_list_item` 里的条目文本（上游 `R.id.list_item`）。 */
  static readonly LIST_ITEM: string = 'list_item';
}

/**
 * 一行（一个时间段）的渲染数据 —— 对位上游 `onBindViewHolder` 里对 holder 的两次写：
 * `holder.textView.setText(timeInfoId(position))` + 逐条 `dataSetChanged` 的子项。
 */
export class EhTopListRow {
  /** 时间段标题的资源键（`EhTopListAdapter.timeInfoId()` 的结果）。 */
  timeInfoId: string;
  /** 该时间段的条目（可为空数组，上游 `TopListItemArray` 可能为 null）。 */
  items: TopListItem[];
  /** 是否可点标题（仅 `GALLERY` 类型；上游同时给标题加下划线）。 */
  titleClickable: boolean;
  /** 标题点击时的 follow 参数（`tl=11` 等），不可点时为空串。 */
  urlFollow: string;

  constructor(timeInfoId: string, items: TopListItem[], titleClickable: boolean,
    urlFollow: string) {
    this.timeInfoId = timeInfoId;
    this.items = items;
    this.titleClickable = titleClickable;
    this.urlFollow = urlFollow;
  }
}

/**
 * `com.hippo.ehviewer.ui.scene.topList.EhTopListAdapter` 的 ArkTS 等价实现（94 行）。
 *
 * 排行榜的"榜单表"适配器：一行 = 一个时间段（昨天/上月/去年/全部），
 * 行内再横向排 10 个条目（`TopListItemArray`）。
 *
 * ## RecyclerView → ArkUI 的映射（三条判据，援引 `DownloadLabelAdapter.ets` 既有先例）
 * | 上游 | ArkUI | 处置 |
 * |---|---|---|
 * | `RecyclerView.ViewHolder` + `convertView` + `setTag/getTag` | `List`/`ForEach`（`LazyForEach`）**自带复用** | **不移植**（"没有对应物"，不是遗漏） |
 * | `inflate(R.layout.gallery_top_list_table_item)` | 布局已生成 → `@Builder` | 适配器只提供行数据 |
 * | `onBindViewHolder` 里的 `setText` 与逐条 `inflate` | `toRow(position)` + 内层 `ForEach` | 保留数据映射；**键名保留成常量**（见 `EhTopListViewHolderKeys`） |
 * | `getItemCount()` | `size()` | 直译 |
 *
 * ## ⚠️ 上游一个"环境产物的缺陷"，我们**不复制症状**
 * 上游 `onBindViewHolder` 每次都：
 * ```java
 * View view = View.inflate(context, R.layout.gallery_top_list_item, null);
 * holder.tableLayout.addView(view);          // ← 从不清理旧的
 * ```
 * 它在 **RecyclerView 的 holder 复用**下才不出问题（每次复用前 `tableLayout` 内容已随 holder 重建），
 * 但一旦某次绑定发生在同一个 holder 上，行就会**越叠越多**。
 *
 * **我们的环境里 `ForEach` 每次重建子项，累加不会发生** —— 所以本实现：
 * - **照搬本体**：数据映射（`toRow`）、纯函数（`timeInfoId`/`urlFollow`）、抽象方法（三个）
 * - **不复制症状**：不保留"向容器累加子视图"的语义
 *
 * 记录在此，避免下一轮审计把它当成"遗漏了 `addView`"。
 */
export abstract class EhTopListAdapter {
  private readonly mEhTopListInfo: TopListInfo;
  private readonly mSearchType: number;

  /**
   * @param ehTopListInfo 一个榜单的四个时间段
   * @param searchType    搜索类型（透传给 `onItemClick`，上游原样保存）
   */
  constructor(ehTopListInfo: TopListInfo, searchType: number) {
    this.mEhTopListInfo = ehTopListInfo;
    this.mSearchType = searchType;
  }

  // ---------- 上游三个抽象方法 ----------

  /** 点击榜单标题（`GALLERY` 类型时才有标题点击）。 */
  abstract clickTitle(urlFollow: string): void;

  /** 条目的背景色（上游 `getRandomColor(i)`，由子类给调色板）。 */
  abstract getRandomColor(position: number): number;

  /** 点击某个条目。 */
  abstract onItemClick(topListItem: TopListItem, searchType: number): void;

  // ---------- 数据映射 ----------

  /** 等价上游 `getItemCount()`。 */
  size(): number {
    return this.mEhTopListInfo.size();
  }

  /** 该行的条目数（上游 `topListItemArray.length()`；数组为 null 时 0）。 */
  itemCount(position: number): number {
    const array = this.mEhTopListInfo.get(position);
    return array === null ? 0 : array.length();
  }

  /** 取某个条目（越界/null 返回 null）。 */
  itemAt(position: number, index: number): TopListItem | null {
    const array: TopListItemArray | null = this.mEhTopListInfo.get(position);
    if (array === null || index < 0 || index >= array.length()) {
      return null;
    }
    return array.get(index);
  }

  /**
   * 一行的渲染数据（对位上游 `onBindViewHolder`）。
   * @return null 表示该位置没有数据（上传/显示层应跳过）
   */
  toRow(position: number): EhTopListRow | null {
    const array = this.mEhTopListInfo.get(position);
    if (array === null) {
      return null;
    }
    const items: TopListItem[] = [];
    for (let i = 0; i < array.length(); i++) {
      items.push(array.get(i));
    }
    const gallery = this.mEhTopListInfo.type === TopListType.GALLERY;
    return new EhTopListRow(EhTopListAdapter.timeInfoId(position), items, gallery,
      gallery ? EhTopListAdapter.urlFollow(position) : '');
  }

  /** 所有行（`ForEach` 数据源）。 */
  toRows(): EhTopListRow[] {
    const rows: EhTopListRow[] = [];
    for (let i = 0; i < this.size(); i++) {
      const row = this.toRow(i);
      if (row !== null) {
        rows.push(row);
      }
    }
    return rows;
  }

  /** 上游 `searchType` 原样保存并透传给 `onItemClick`。 */
  getSearchType(): number {
    return this.mSearchType;
  }

  getTopListInfo(): TopListInfo {
    return this.mEhTopListInfo;
  }

  // ---------- 两个纯函数（上游 private，提为 static 以便单测） ----------

  /**
   * 时间段标题（上游 `timeInfoId(int index)`）。
   *
   * 返回资源**键**而不是资源 id：ArkTS 侧资源由 `$r('app.string.xxx')` 取，
   * 所以这里给 `app.string.<key>` 的最后一段，由 `@Builder` 拼成 `Resource`。
   *
   * **`default` 与 `case 3` 合并**（上游 `default: case 3:` 一起返回 `all_time`）：
   * 也就是说 `index >= 4` 或负数都落到"全部时间" —— 这是上游行为，照搬。
   */
  static timeInfoId(index: number): string {
    switch (index) {
      case 0:
        return 'yesterday_top_list';
      case 1:
        return 'past_month_top_list';
      case 2:
        return 'past_year_top_list';
      case 3:
      default:
        return 'all_time_top_list';
    }
  }

  /**
   * 标题点击的 follow 参数（上游 `urlFollow(int index)`）。
   *
   * 注意 `tl` 的取值**不是按索引递增**：`0→15, 1→13, 2→12, 3→11`（越早的时间段数字越大）。
   * 这是上游硬编码，不要"顺手整理成递增"。
   * `default` 与 `case 3` 合并（同 `timeInfoId`）。
   */
  static urlFollow(index: number): string {
    switch (index) {
      case 0:
        return 'tl=15';
      case 1:
        return 'tl=13';
      case 2:
        return 'tl=12';
      case 3:
      default:
        return 'tl=11';
    }
  }
}
