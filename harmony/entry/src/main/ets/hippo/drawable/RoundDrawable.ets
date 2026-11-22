/**
 * 迁移自 app/src/main/java/com/hippo/drawable/RoundDrawable.java（inventory S0029，上游 57 行）
 *
 * 上游：Paint(ANTI_ALIAS|DITHER) + drawOval(mRectF) → 在 bounds 内填充一个椭圆
 *       setColor() invalidateSelf()；setAlpha() 改 Paint alpha；getOpacity() = OPAQUE
 *
 * ArkUI 对位：bounds 恒等于组件自身盒 → `Column().backgroundColor(color).borderRadius('50%')`
 *   borderRadius 50% 使矩形圆角化到极限，即内切椭圆，与 drawOval(bounds) 等价。
 *   setAlpha → @Prop alpha（0..1，上游是 0..255 的 Paint alpha）→ `.opacity(alpha)`
 *   getOpacity 恒 OPAQUE → 不透明语义由颜色 alpha 通道决定，ArkUI 无需单独表达。
 *
 * 差异：Android 用 DITHER 抖动提升渐变/低色深表现；ArkUI 渲染管线为 32 位色，无抖动开关，
 *      对纯色填充无可见影响（已登记 MR）。
 */
@Component
export struct RoundDrawable {
  /** 上游构造参数 / setColor(int) */
  @Prop color: ResourceColor = '#FF000000';
  /** 上游 setAlpha(int 0..255) → 此处 0.0..1.0 */
  @Prop alpha: number = 1.0;

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(this.color)
      .borderRadius('50%')
      .opacity(this.alpha)
  }
}
