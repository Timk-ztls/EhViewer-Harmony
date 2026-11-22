/**
 * 迁移自 app/src/main/java/com/hippo/widget/MaxSizeContainer.java（inventory S0531，上游 78 行）
 *
 * 上游逻辑：
 *   getMeasureSpec(spec, max)：max<0 ⇒ 原样返回；AT_MOST ⇒ size=min(size,max)；
 *                              UNSPECIFIED ⇒ size=max 且 mode 改 AT_MOST
 *   onMeasure：断言子 View 恰好 1 个 → 用上面的 spec 量它 → 自身尺寸 = 子尺寸（GONE ⇒ 0,0）
 *   onLayout ：子 View 铺满 (0,0,r-l,b-t)
 *   属性：maxWidth / maxHeight，默认 -1（不限）
 *
 * ArkUI 对位：
 *   1) "恰好一个子"：用单个 @BuilderParam 槽位在结构上保证（ArkUI 没有 getChildCount 断言，
 *      单槽位等价于上游 AssertUtils.assertEquals(1, getChildCount()) 的约束目的）
 *   2) 测量：`.constraintSize({ maxWidth, maxHeight })` 即上游两个分支的组合语义
 *      （AT_MOST 截断 / UNSPECIFIED 取 max / EXACTLY 不动），max<0 时不传该维度
 *   3) 铺满：子内容 width/height '100%'
 */
@Component
export struct MaxSizeContainer {
  /** 上游 R.styleable.MaxSizeContainer_maxWidth，默认 -1 表示不限 */
  @Prop maxWidth: number = -1;
  /** 上游 R.styleable.MaxSizeContainer_maxHeight，默认 -1 表示不限 */
  @Prop maxHeight: number = -1;
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty(): void {
  }

  private constraint(): ConstraintSizeOptions {
    const o: ConstraintSizeOptions = {};
    if (this.maxWidth >= 0) {
      o.maxWidth = this.maxWidth;
    }
    if (this.maxHeight >= 0) {
      o.maxHeight = this.maxHeight;
    }
    return o;
  }

  build() {
    Column() {
      this.content()
    }
    .constraintSize(this.constraint())
  }
}
