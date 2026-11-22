/**
 * 重绘自 app/src/main/res/drawable/ic_baseline_filter_9_plus_24.xml  （inventory S0743，上游 10 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/filter_much_more" fillColor="@color/primary_drawable_dark"> → Path().commands(PathData.filter_much_more).fill('#FFFFFFFF')
 */
import { PathData } from '../../drawable/PathData';

@Component
export struct IcBaselineFilter9Plus24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  build() {
    Shape() {
      Path()
        .commands(PathData.filter_much_more)
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