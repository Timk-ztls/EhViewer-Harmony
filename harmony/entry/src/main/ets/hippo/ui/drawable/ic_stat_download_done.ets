/**
 * 重绘自 app/src/main/res/drawable/ic_stat_download_done.xml  （inventory S0757，上游 11 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M9,16.17L4.83,12L3.41,13.41L9,19L21,7L19.59,5.59L9,16.17Z" fillColor="#FFFFFFFF"> → Path().commands('M9,16.17L4.83,12L3.41,13.41L9,19L21,7L19.59,5.59L9,16.17Z').fill('#FFFFFFFF')
 */


@Component
export struct IcStatDownloadDone {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  build() {
    Shape() {
      Path()
        .commands('M9,16.17L4.83,12L3.41,13.41L9,19L21,7L19.59,5.59L9,16.17Z')
        .fill('#FFFFFFFF')
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize * 24 / 24)
    .antiAlias(true)
  }
}