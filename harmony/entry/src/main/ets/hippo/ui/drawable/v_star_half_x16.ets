/**
 * 重绘自 app/src/main/res/drawable/v_star_half_x16.xml  （inventory S0842，上游 26 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pd_star_half" fillColor="@color/yellow_800"> → Path().commands(PathData.pd_star_half).fill(DrawablePalette.YELLOW_800)
 */
import { PathData } from '../../drawable/PathData';
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct VStarHalfX16 {
  /** 上游矢量尺寸 16dp×16dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 16;
  @Prop fillColor: ResourceColor = DrawablePalette.YELLOW_800;
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_star_half)
        .fill(this.fillColor)
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize * 16 / 16)
    .antiAlias(true)
  }
}