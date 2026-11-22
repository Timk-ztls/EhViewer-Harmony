/**
 * 重绘自 app/src/main/res/drawable/fingerprint_error.xml  （inventory S0729，上游 28 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M20.0,0.0C8.96,0.0 0.0,8.95 0.0,20.0s8.96,20.0 20.0,20.0c11.04,0.0 20.0,-8.95 20.0,-20.0S31.04,0.0 20.0,0.0z" fillColor="#F4511E"> → Path().commands('M20.0,0.0C8.96,0.0 0.0,8.95 0.0,20.0s8.96,20.0 20.0,20.0c11.04,0.0 20.0,-8.95 20.0,-20.0S31.04,0.0 20.0,0.0z').fill('#FFF4511E')
 *   <path pathData="M21.33,29.33l-2.67,0.0l0.0,-2.67l2.67,0.0L21.33,29.33zM21.33,22.67l-2.67,0.0l0.0,-12.0l2.67,0.0L21.33,22.67z" fillColor="#FFFFFF"> → Path().commands('M21.33,29.33l-2.67,0.0l0.0,-2.67l2.67,0.0L21.33,29.33zM21.33,22.67l-2.67,0.0l0.0,-12.0l2.67,0.0L21.33,22.67z').fill('#FFFFFFFF')
 */


@Component
export struct FingerprintError {
  /** 上游矢量尺寸 40dp×40dp，viewport 40×40；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 40;
  build() {
    Shape() {
      Path()
        .commands('M20.0,0.0C8.96,0.0 0.0,8.95 0.0,20.0s8.96,20.0 20.0,20.0c11.04,0.0 20.0,-8.95 20.0,-20.0S31.04,0.0 20.0,0.0z')
        .fill('#FFF4511E')
        .stroke(Color.Transparent)
        .strokeWidth(0)
      Path()
        .commands('M21.33,29.33l-2.67,0.0l0.0,-2.67l2.67,0.0L21.33,29.33zM21.33,22.67l-2.67,0.0l0.0,-12.0l2.67,0.0L21.33,22.67z')
        .fill('#FFFFFFFF')
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '40px', height: '40px' })
    .width(this.iconSize)
    .height(this.iconSize * 40 / 40)
    .antiAlias(true)
  }
}