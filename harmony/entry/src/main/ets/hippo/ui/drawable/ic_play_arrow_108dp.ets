/**
 * 重绘自 app/src/main/res/drawable/ic_play_arrow_108dp.xml  （inventory S0752，上游 10 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M46,40V68L68,54Z" fillColor="@color/colorPrimary"> → Path().commands('M46,40V68L68,54Z').fill(DrawablePalette.TEAL_500)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct IcPlayArrow108dp {
  /** 上游矢量尺寸 108dp×108dp，viewport 108×108；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 108;
  build() {
    Shape() {
      Path()
        .commands('M46,40V68L68,54Z')
        .fill(DrawablePalette.TEAL_500)
        .stroke(Color.Transparent)
        .strokeWidth(0)
        .fillOpacity(1)
    }
    .viewPort({ x: 0, y: 0, width: '108px', height: '108px' })
    .width(this.iconSize)
    .height(this.iconSize * 108 / 108)
    .antiAlias(true)
  }
}