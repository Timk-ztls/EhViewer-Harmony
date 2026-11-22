/**
 * 重绘自 app/src/main/res/drawable/v_share_primary_x48.xml  （inventory S0839，上游 26 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pd_share" fillColor="?attr/drawableColorThemePrimary"> → Path().commands(PathData.pd_share).fill(this.fillColor)
 */
import { PathData } from '../../drawable/PathData';
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct VSharePrimaryX48 {
  /** 上游矢量尺寸 48dp×48dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 48;
  /** 上游 fillColor 取自主题属性，三态值见 DrawablePalette（light/dark/black）；此处默认 light */
  @Prop fillColor: ResourceColor = DrawablePalette.DRAWABLE_PRIMARY_LIGHT;
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_share)
        .fill(this.fillColor)
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize * 48 / 48)
    .antiAlias(true)
  }
}