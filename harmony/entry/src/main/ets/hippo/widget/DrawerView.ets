/**
 * 迁移自 app/src/main/java/com/hippo/widget/DrawerView.java（inventory S0519，上游 62 行）
 *
 * 上游逻辑（onMeasure）：
 *   widthSpec EXACTLY   → 原样交给 super
 *   widthSpec AT_MOST   → min(specSize, mMaxWidth)，按 EXACTLY 重新量
 *   widthSpec UNSPECIFIED → mMaxWidth，按 EXACTLY 重新量
 *   高度交给 super
 *   mMaxWidth 默认 280dp（LayoutUtils.dp2pix），可被 android:maxWidth 覆盖
 *
 * ArkUI 对位：声明式布局里没有 MeasureSpec 三分支，等价物是约束：
 *   `.constraintSize({ maxWidth: this.maxWidth })`
 *   —— 父给"恰好"时父尺寸 ≤ maxWidth 由父决定；父给"至多"时被 maxWidth 截断（= AT_MOST 分支）；
 *      父给"不限"时按内容/百分比展开，再由 maxWidth 兜底（= UNSPECIFIED 分支）。
 *   这三种情形与上游 onMeasure 的三种分支一一对应，故不再手写 onMeasure。
 * 单位：上游 dp → vp，1:1 换数值（DEFAULT_MAX_WIDTH = 280）。
 */
@Component
export struct DrawerView {
  /** 上游 DEFAULT_MAX_WIDTH = 280dp / android:maxWidth */
  @Prop maxWidth: number = 280;
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty(): void {
  }

  build() {
    Column() {
      this.content()
    }
    .constraintSize({ maxWidth: this.maxWidth })
    .height('100%')
  }
}
