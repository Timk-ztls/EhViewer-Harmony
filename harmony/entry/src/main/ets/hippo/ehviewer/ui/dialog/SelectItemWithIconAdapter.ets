/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/dialog/SelectItemWithIconAdapter.kt（inventory S0193，60 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/dialog/SelectItemWithIconAdapter.ets
 *
 * 背景：带图标的选择项列表 adapter（弹窗里选一项）。条目布局 `dialog_item_select_with_icon`
 * 由我此前移植（`dialog_item_select_with_icon.ets`，S0578）。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class SelectItemWithIconAdapter(context, texts: Array<CharSequence?>, icons: IntArray) : BaseAdapter()`
 *   `require(texts.size == icons.size) { "Length conflict" }`  → 构造期长度校验（见 1）
 *   `getCount()`        → texts.size                              → `getCount()`
 *   `getItem(pos)`      → texts[pos]                              → `getTextAt(pos)`
 *   `getItemId(pos)`    → pos.toLong()                            → `getItemId(pos)`（ArkTS number）
 *   `getView(pos, convertView, parent)`:
 *     convertView 为空则 inflate `dialog_item_select_with_icon`    → ArkUI 每行由 @Component 渲染（见 2）
 *     `view.text = texts[pos]`                                    → 文本来源
 *     `AppCompatResources.getDrawable(context, icons[pos])`
 *       + `setBounds(0,0,intrinsicWidth,intrinsicHeight)`
 *       + `setCompoundDrawables(icon, null, null, null)`          → 左侧图标槽（见 3）
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. **`require(...) { "Length conflict" }`** 是**构造期**断言（IllegalArgumentException）。
 *    ArkTS 保留等价行为：构造时长度不等 → `throw new Error('Length conflict')`
 *    （消息文本逐字一致，便于与上游日志对照）。
 * 2. **`BaseAdapter` + `convertView` 复用**在 ArkUI 不存在：`List`/`LazyForEach` 按数据渲染，
 *    没有"转换视图"概念。故本类退化成**数据源**（count + 逐项文本/图标），
 *    由 `dialog_item_select_with_icon.ets` 的 `iconBuilder` 槽位渲染图标。
 * 3. **`icons: IntArray`（R.drawable 资源 id）→ `iconNames: string[]`**：
 *    本仓库的 drawable 已迁成 ArkUI **组件**（`hippo/ui/drawable/<name>.ets`），
 *    `app.media.*` 多数不存在（生成假 `$r()` 会编译失败，见菜单移植经验）。
 *    所以这里存**资源名**，由渲染方查组件表；`setBounds(intrinsic…)` 无对位（组件自带尺寸）。
 * 4. `getItemId` 上游返回 `long`；ArkTS 用 `number`（位置索引远小于 2^53，等价）。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 布局：`dialog_item_select_with_icon.ets`（S0578，已移植）
 * - 同类：`SubscriptionItemAdapter`（S0246）、`GalleryHolder`（S0250）—— 同一批"adapter 载体变化"
 */

export class SelectItemWithIconAdapter {
  private texts: ResourceStr[];
  private iconNames: string[];

  /**
   * @param texts 每项文本（**允许 null**：上游是 `Array<CharSequence?>`，null 表示空文本）
   * @param iconNames 每项的 drawable **资源名**（对应 `hippo/ui/drawable/<name>.ets` 组件）
   * @throws Error('Length conflict') 当 texts 与 iconNames 长度不一致（对应上游 `require`）
   */
  constructor(texts: ResourceStr[], iconNames: string[]) {
    // 上游：require(count == icons.size) { "Length conflict" } —— 消息逐字保留
    if (texts.length !== iconNames.length) {
      throw new Error('Length conflict');
    }
    this.texts = texts;
    this.iconNames = iconNames;
  }

  /** 上游 `getCount()` */
  getCount(): number {
    return this.texts.length;
  }

  /** 上游 `getItem(position)`：返回该位置文本（越界时返回空串，与上游 Array 越界抛异常不同，见下） */
  getTextAt(position: number): ResourceStr {
    if (position < 0 || position >= this.texts.length) {
      // 上游 Kotlin 的 Array 越界会抛 IndexOutOfBoundsException；这里显式抛同类错误，
      // 避免"静默返回空串"掩盖调用方错误。
      throw new Error(`Index ${position} out of bounds for length ${this.texts.length}`);
    }
    return this.texts[position];
  }

  /** 上游 `getItemId(position)`：`position.toLong()` → ArkTS number（位置索引，等价） */
  getItemId(position: number): number {
    return position;
  }

  /** 该位置图标资源名（上游 `icons[position]`，见文件头 3） */
  getIconNameAt(position: number): string {
    if (position < 0 || position >= this.iconNames.length) {
      throw new Error(`Index ${position} out of bounds for length ${this.iconNames.length}`);
    }
    return this.iconNames[position];
  }
}
