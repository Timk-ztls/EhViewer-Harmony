/**
 * 重绘自 app/src/main/res/drawable/fingerprint_success.xml  （inventory S0730，上游 28 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M20.0,20.0m-20.0,0.0a20.0,20.0 0.0,1.0 1.0,40.0 0.0a20.0,20.0 0.0,1.0 1.0,-40.0 0.0" fillColor="#009688"> → Path().commands('M20.0,20.0m-20.0,0.0a20.0,20.0 0.0,1.0 1.0,40.0 0.0a20.0,20.0 0.0,1.0 1.0,-40.0 0.0').fill('#FF009688')
 *   <path pathData="M11.2,21.41l1.63,-1.619999 4.17,4.169998 10.59,-10.589999 1.619999,1.63 -12.209999,12.209999z" fillColor="#FFFFFF"> → Path().commands('M11.2,21.41l1.63,-1.619999 4.17,4.169998 10.59,-10.589999 1.619999,1.63 -12.209999,12.209999z').fill('#FFFFFFFF')
 */


@Component
export struct FingerprintSuccess {
  /** 上游矢量尺寸 40dp×40dp，viewport 40×40；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 40;
  build() {
    Shape() {
      Path()
        .commands('M20.0,20.0m-20.0,0.0a20.0,20.0 0.0,1.0 1.0,40.0 0.0a20.0,20.0 0.0,1.0 1.0,-40.0 0.0')
        .fill('#FF009688')
        .stroke(Color.Transparent)
        .strokeWidth(0)
      Path()
        .commands('M11.2,21.41l1.63,-1.619999 4.17,4.169998 10.59,-10.589999 1.619999,1.63 -12.209999,12.209999z')
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