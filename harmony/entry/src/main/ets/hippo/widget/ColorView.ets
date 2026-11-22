/**
 * 迁移自 app/src/main/java/com/hippo/widget/ColorView.java（inventory S0514，上游 42 行）
 *
 * 对照：
 *   extends View + onDraw(canvas.drawColor(mColor)) → Column().backgroundColor(color) 铺满自身
 *   setColor(int) 变了才 invalidate()               → @Prop color（状态驱动，赋值即重绘）
 *
 * 差异：上游 `canvas.drawColor` 会连 padding 区域一并填满；ArkUI 的背景同样覆盖整个组件区域，
 *      故两者一致。上游是 int 颜色；鸿蒙侧用 ResourceColor（字符串/资源皆可），调用方传 0xAARRGGBB
 *      对应值即可，不做任何透明度换算。
 */
@Component
export struct ColorView {
  /** 上游 mColor（默认 0 = 全透明） */
  @Prop color: ResourceColor = '#00000000';

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(this.color)
  }
}
