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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/download/DownloadLabelAdapter.java（43 行）。
 *
 * ============================================================================
 * 一、上游做什么
 * ============================================================================
 *   `ArrayAdapter<DownloadLabelItem>` 的 `getView`：两行布局（`item_download_label_list`），
 *   `text1` = 标签名、`text2` = 条数（`item.count()`，**String**）。
 *
 *   样板部分：`convertView` 复用 + `ViewHolder` 缓存（`setTag`/`getTag`）——
 *   这是 ListView 的性能技巧，**只在 ListView 里有意义**。
 *
 * ============================================================================
 * 二、ArkTS 侧：三件事的对应关系
 * ============================================================================
 *   1. `convertView` 复用 + ViewHolder → **ArkUI 的 `ListItem`/`ForEach` 自带复用**，
 *      没有"自己缓存子 View 引用"的概念；照搬会造出一个没人用的缓存对象。
 *      → 本文件不移植 ViewHolder（不是遗漏，是没有对应物）。
 *   2. `getView` 的两个 setText → 保留为**行数据映射**（`toRow(item)`）：这次渲染要显示什么。
 *   3. `getItem(position)` → `itemAt(position)`：越界返回 null（上游 `getItem` 越界返回 null，
 *      `ArrayAdapter` 内部就是这样），调用方判空。
 *
 * `item_download_label_list` 布局的两行文本键名（`text1`/`text2`）保留成常量，
 * 供 ArkUI 侧 `@Builder` 逐字对位 —— 避免"文本1/文本2 到底是标题还是计数"靠猜。
 *
 * 依赖：`DownloadLabelItem`（S0218，**已 land**：`ui/scene/download/DownloadLabelItem.ets`）。
 */

import { DownloadLabelItem } from './DownloadLabelItem';

/** 一行的渲染数据（对位上游 `viewHolder.textView1/2.setText(...)` 的两个值）。 */
export interface DownloadLabelRow {
  /** 第一行文本 = 标签名（上游 `text1`）。 */
  label: string;
  /** 第二行文本 = 条数（上游 `text2`，来自 `item.count()`，**字符串**）。 */
  countText: string;
}

/**
 * 下载标签列表的适配器（对位上游 `DownloadLabelAdapter`）。
 */
export class DownloadLabelAdapter {
  /** 布局里两个文本控件的 id（上游 `R.id.text1` / `R.id.text2`）。 */
  public static readonly ID_TEXT1: string = 'text1';
  public static readonly ID_TEXT2: string = 'text2';

  /** 数据源（上游构造器里的 `List<DownloadLabelItem> objects`）。 */
  private readonly objects: DownloadLabelItem[];

  constructor(objects: DownloadLabelItem[]) {
    this.objects = objects;
  }

  /** 条目数（上游 `ArrayAdapter.getCount()`）。 */
  public count(): number {
    return this.objects.length;
  }

  /**
   * 取指定位置的数据对象（上游 `getItem(position)`）。
   *
   * 上游 `ArrayAdapter.getItem` 越界返回 `null`（不抛异常），这里保持一致。
   */
  public itemAt(position: number): DownloadLabelItem | null {
    if (position < 0 || position >= this.objects.length) {
      return null;
    }
    return this.objects[position];
  }

  /**
   * 第 position 行该显示的两个文本（上游 `getView` 里两次 `setText`）。
   *
   * 上游对 `getItem(position)` 的结果**直接解引用**（`item.label` / `item.count()`）；
   * 这里保留"越界 → null"的返回，让调用方能显式处理（ArkUI 的 `ForEach` 不会给越界下标，
   * 所以正常路径永远非 null；这个分支只是防御）。
   */
  public toRow(position: number): DownloadLabelRow | null {
    const item: DownloadLabelItem | null = this.itemAt(position);
    if (item === null) {
      return null;
    }
    return { label: item.label, countText: item.count() };
  }

  /** 数据源快照（上游 `ArrayAdapter` 内部持有 List；这里只读暴露，供计数/调试）。 */
  public items(): DownloadLabelItem[] {
    return this.objects;
  }
}
