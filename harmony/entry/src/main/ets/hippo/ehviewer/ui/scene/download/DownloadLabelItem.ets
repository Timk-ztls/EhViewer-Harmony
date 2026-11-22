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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/download/DownloadLabelItem.java（14 行）。
 *
 * ============================================================================
 * 一、这是一个**纯数据载体**，没有行为分支
 * ============================================================================
 * 上游字段（package-private，同包可见）：
 *   ```java
 *   String label;          // 标签名（默认标签是 settings 里的那个空串对应的"默认"）
 *   private long count;    // 该标签下的下载条数
 *   ```
 * 上游方法只有两个构造器 + `count()`；`count()` 返回 `count + ""`（**String**，不是 long）
 * —— 因为它只被 `DownloadLabelAdapter` 直接塞进 TextView，不需要数值语义。
 *
 * 移植取舍：
 *   1. `label` 上游是 package-private（同包 `DownloadLabelDraw` 直接赋值访问），
 *      ArkTS 没有包级可见性 → 改为 `public` 字段 + 文档说明「对应上游 package-private」。
 *   2. `count()` 保留为方法（不改成 getter）：调用点 `holder.mCount.setText(item.count())`
 *      逐字对位，改成 `getCount()` 会让后续 review 每次都要做一次心算。
 *   3. `long` → `number`：`count` 只是下载条数（远小于 2^53），符合 ArkTS 无 long 的约定。
 *
 * ============================================================================
 * 二、与 DownloadLabelAdapter 的关系
 * ============================================================================
 * 上游 `DownloadLabelAdapter extends ArrayAdapter<DownloadLabelItem>`（S0216）：
 *   - `getView(position)` 里取 `getItem(position)`，把 `label` 填进标题、`count()` 填进计数；
 *   - 数据由 `DownloadLabelDraw`（S0xxx）构造：
 *       `new DownloadLabelItem(label, downloadManager.getLabelCount(label))`
 *       `new DownloadLabelItem(默认标签, downloadManager.getDefaultDownloadInfoList().size())`
 * 本条只负责数据结构本身；计数从哪来由调用方决定（本类不持有 DownloadManager）。
 */
export class DownloadLabelItem {
  /** 标签名（对应上游 package-private 字段 `label`）。 */
  public label: string;

  /**
   * 该标签下的下载条数（对应上游 `private long count`）。
   *
   * **命名偏离**：上游同名字段 `count` 与方法 `count()` 可以共存（Java 允许），
   * 但 TS/ArkTS 的类成员命名空间是同一套 —— 字段与方法同名会 `Duplicate identifier`。
   * 因此字段改名为 `labelCount`，**方法名 `count()` 保持不变**（调用点逐字对位）。
   */
  private labelCount: number;

  constructor(label: string, count: number) {
    this.label = label;
    this.labelCount = count;
  }

  /**
   * 计数的**字符串**形式（对应上游 `public String count()`：`return count + "";`）。
   *
   * 注意上游返回的是 String 而不是数值 —— 调用方直接塞进文本控件，
   * 保留 String 返回类型才不会在调用点引入多余的类型转换。
   */
  public count(): string {
    return `${this.labelCount}`;
  }
}
