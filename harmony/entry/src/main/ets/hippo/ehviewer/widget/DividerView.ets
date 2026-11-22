/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/DividerView.java（inventory S0288，上游 71 行）
 *
 * 上游：
 *   属性 dividerColor（默认黑）/ dividerWidth / dividerHeight（默认 0，单位 px）
 *   getSuggestedMinimumWidth  = max(paddingL+paddingR+dividerWidth, super)
 *   getSuggestedMinimumHeight = max(paddingT+paddingB+dividerHeight, super)
 *   onDraw：rect = (paddingLeft, paddingTop, w-paddingRight, h-paddingBottom)，非空则填色
 *
 * ArkUI 对位：
 *   填充矩形 → `Column().backgroundColor(color)`，内容区由 `.padding(...)` 内缩，
 *   恰好等价于上游"减去 padding 后填充"的矩形
 *   最小尺寸 → `.constraintSize({ minWidth: dividerWidth, minHeight: dividerHeight })`
 *   （ArkUI 的 minWidth 已是"含内边距"口径，故与上游 padding+divider 的表达一致）
 *
 * 差异：上游未设 padding 时 dividerWidth/Height 只是"最小建议尺寸"，实际尺寸由父布局决定；
 *      ArkUI 的 constraintSize 同为约束语义，行为一致。
 */
@Component
export struct DividerView {
  /** 上游 R.styleable.DividerView_dividerColor（默认 Color.BLACK） */
  @Prop dividerColor: ResourceColor = '#FF000000';
  /** 上游 dividerWidth（默认 0） */
  @Prop dividerWidth: number = 0;
  /** 上游 dividerHeight（默认 0） */
  @Prop dividerHeight: number = 0;
  @Prop paddingValue: Padding = {};

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(this.dividerColor)
      .padding(this.paddingValue)
      .constraintSize({ minWidth: this.dividerWidth, minHeight: this.dividerHeight })
  }
}
