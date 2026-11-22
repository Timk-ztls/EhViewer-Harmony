/**
 * 重绘自 app/src/main/res/drawable/v_mobile_hand_left_x24.xml  （inventory S0823，上游 11 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/ic_mobile_hand_left" fillColor="?attr/iconColor"> → Path().commands(PathData.ic_mobile_hand_left).fill(this.fillColor)
 */
import { PathData } from '../../drawable/PathData';
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct VMobileHandLeftX24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 960×960；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  /** 上游 fillColor 取自主题属性，三态值见 DrawablePalette（light/dark/black）；此处默认 light */
  @Prop fillColor: ResourceColor = DrawablePalette.DRAWABLE_PRIMARY_LIGHT;
  build() {
    Shape() {
      Path()
        .commands(PathData.ic_mobile_hand_left)
        .fill(this.fillColor)
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '960px', height: '960px' })
    .width(this.iconSize)
    .height(this.iconSize * 24 / 24)
    .antiAlias(true)
  }
}