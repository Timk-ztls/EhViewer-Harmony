/*
 * 上游：app/src/main/res/layout/item_excluded_languages.xml（inventory S0610，上游 39 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_excluded_languages.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                        ArkUI
 * LinearLayout(horizontal)                        Row
 * TextView（0dp, weight=1, textColorPrimary）      Text().layoutWeight(1)
 * com.hippo.widget.SensitiveCheckBox × 3          SensitiveCheckBox × 3（ui-widget 已交付）
 *   （各自 0dp, weight=1）                          .layoutWeight(1)
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `com.hippo.widget.SensitiveCheckBox` 已由 ui-widget 交付
 *    （`hippo/widget/SensitiveCheckBox.ets`），直接 import，不重写；
 *    其"敏感手势保护"逻辑（长按才生效，防误触）属该控件内部，布局层不复制。
 * 2. 四个子项都是 `layout_width=0dp + layout_weight=1` → ArkUI 的 `.layoutWeight(1)`；
 *    高度都是 wrap_content → 不设 height，由内容撑开。
 * 3. 上游未设 padding / 间距：Row 不带 space（勾选框字号与文案之间无额外间隔），保持一致。
 * 4. 三个 CheckBox 的选中态由使用方绑定：`SensitiveCheckBox` 用 `@Link checked` 表达上游
 *    的 getChecked()/setChecked()，**且该属性是必填**（ArkTS 编译器强制）。
 *    父组件因此必须传 `@State` 变量；本布局照 ArkUI 的单向数据流把它收成 3 个 `@Prop`，
 *    由使用方（Adapter 等价层）持有 @State 并回写 —— 见下方 `checked1/2/3`。
 * 5. `?android:attr/textColorPrimary` 无 attr → @Prop 注入，默认 '#DE000000'。
 */

import { SensitiveCheckBox } from '../../widget/SensitiveCheckBox';

@Component
export struct ExcludedLanguagesItemLayout {
  @Prop label: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  /** 三个勾选框的选中态（上游由 Adapter 通过 setChecked 注入；这里单向下发） */
  @Prop checked1: boolean = false;
  @Prop checked2: boolean = false;
  @Prop checked3: boolean = false;

  build() {
    Row() {
      Text(this.label)
        .fontColor(this.textColor)
        .fontSize(16)
        .layoutWeight(1)

      SensitiveCheckBox({ checked: this.checked1 }).layoutWeight(1)

      SensitiveCheckBox({ checked: this.checked2 }).layoutWeight(1)

      SensitiveCheckBox({ checked: this.checked3 }).layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

