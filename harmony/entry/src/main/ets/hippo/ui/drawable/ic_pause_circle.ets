/**
 * 重绘自 app/src/main/res/drawable/ic_pause_circle.xml  （inventory S0750，上游 9 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pause_circle" fillColor="?attr/textColorThemePrimary"> → Path().commands(PathData.pause_circle).fill(this.fillColor)
 */
import { PathData } from '../../drawable/PathData';
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct IcPauseCircle {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  /** 上游 fillColor 取自主题属性，三态值见 DrawablePalette（light/dark/black）；此处默认 light */
  @Prop fillColor: ResourceColor = DrawablePalette.DRAWABLE_PRIMARY_LIGHT;
  build() {
    Shape() {
      Path()
        .commands(PathData.pause_circle)
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