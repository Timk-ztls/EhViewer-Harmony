/**
 * 重绘自 app/src/main/res/drawable/v_dots_vertical_secondary_dark_x24.xml  （inventory S0793，上游 26 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pd_dots_vertical" fillColor="@color/secondary_drawable_dark"> → Path().commands(PathData.pd_dots_vertical).fill('#4DFFFFFF')
 */
import { PathData } from '../../drawable/PathData';

@Component
export struct VDotsVerticalSecondaryDarkX24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  @Prop fillColor: ResourceColor = '#4DFFFFFF';
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_dots_vertical)
        .fill(this.fillColor)
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize * 24 / 24)
    .antiAlias(true)
  }
}