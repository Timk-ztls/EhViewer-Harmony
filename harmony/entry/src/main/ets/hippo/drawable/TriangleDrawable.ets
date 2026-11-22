/**
 * 迁移自 app/src/main/java/com/hippo/drawable/TriangleDrawable.java（inventory S0031，上游 61 行）
 *
 * 上游 onBoundsChange 里重建 Path：
 *   moveTo(bounds.left, bounds.top)
 *   lineTo(bounds.right, bounds.top)
 *   lineTo(bounds.right, bounds.bottom)
 *   close()
 * 即"左上 → 右上 → 右下 → 回到左上"的直角三角形，占满 bounds。
 *
 * ArkUI 对位：Shape + Path，用 100×100 归一化 viewport 表达同一条路径：
 *   `M0,0 L100,0 L100,100 Z`
 *   Shape 的 viewPort 会把归一化坐标**按组件实际尺寸双向拉伸**，正对应上游"路径直接取 bounds 角点"
 *   的语义（宽高不同时仍是同一条直角三角形，不是等比缩放）。
 *
 * 差异：Paint 的 DITHER 在 ArkUI 无对位（纯色填充无可见影响）；抗锯齿由渲染后端统一处理。
 */
@Component
export struct TriangleDrawable {
  /** 上游构造参数 / setColor(int) */
  @Prop color: ResourceColor = '#FF000000';
  /** 上游 setAlpha(int 0..255) → 此处 0.0..1.0 */
  @Prop alpha: number = 1.0;

  build() {
    Shape() {
      Path()
        .commands('M0,0 L100,0 L100,100 Z')
        .fill(this.color)
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '100px', height: '100px' })
    .width('100%')
    .height('100%')
    .opacity(this.alpha)
    .antiAlias(true)
  }
}
