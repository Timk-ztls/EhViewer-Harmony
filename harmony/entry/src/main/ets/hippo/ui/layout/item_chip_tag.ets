/*
 * 上游：app/src/main/res/layout/item_chip_tag.xml（inventory S0603，上游 8 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_chip_tag.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                          ArkUI
 * com.google.android.material.chip.Chip             ChipTagItemLayout（见「无法等价」1）
 *   style=@style/CustomChipChoice                    选择态外观（勾选/未勾选）
 *     （parent=Widget.MaterialComponents.Chip.Action）  见 2
 *   layout_width/height=wrap_content                 内容撑开
 *   textAppearance=?android:textAppearanceSmall       .fontSize(14)（text_small）
 *   android:theme=@style/ClipTheme                   clipToOutline 圆角裁剪，见 3
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. Material `Chip` 是**行为控件**（checkable + closeIcon + 状态动画 + 触摸涟漪），
 *    不是纯布局。ui-widget 未交付 Chip 等价物 → 本文件只落"视觉壳"
 *    （圆角 + 背景 + 文本），交互（选择切换）留 TODO(ui-widget)。
 *    铁律：不写假实现 —— 因此本组件**不**伪造 chip 的 checkable 状态机，
 *    `selected` 只是透传的视觉态（由使用方持有真实状态）。
 * 2. `@style/CustomChipChoice` 继承 `Widget.MaterialComponents.Chip.Action`：
 *    默认圆角 16dp、最小高度 32dp、水平 padding 12dp、未选中描边 1dp #BDBDBD /
 *    选中填充 colorPrimary 且文字反色。这些是从上游 styles.xml 的 parent 推得的
 *    Material 默认值，鸿蒙侧全部做成 @Prop，默认取未选中态。
 * 3. `@style/ClipTheme` 只做 `android:clipToOutline=true`（把子 View 裁到圆角）。
 *    ArkUI 的 `.borderRadius()` 本身即裁剪，无需额外主题。
 * 4. Chip 真正的布局属性里没有 include/引用，故本项不依赖其他布局。
 */

@Component
export struct ChipTagItemLayout {
  @Prop text: string = '';
  /** 视觉选中态（真实状态由使用方持有；TODO(ui-widget) 交付 Chip 后接其状态机） */
  @Prop selected: boolean = false;
  @Prop selectedColor: ResourceColor = '#FF6200EE';
  @Prop unselectedStrokeColor: ResourceColor = '#FFBDBDBD';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop selectedTextColor: ResourceColor = Color.White;

  build() {
    // TODO(ui-widget): 上游 com.google.android.material.chip.Chip 的等价控件（checkable 状态机）
    Text(this.text)
      .fontSize($r('app.float.text_small'))
      .fontColor(this.selected ? this.selectedTextColor : this.textColor)
      .constraintSize({ minHeight: 32 })
      .padding({ left: 12, right: 12 })
      .borderRadius(16)
      .backgroundColor(this.selected ? this.selectedColor : Color.Transparent)
      .border({ width: this.selected ? 0 : 1, color: this.unselectedStrokeColor })
  }
}
