/**
 * 重绘自 app/src/main/res/drawable/v_slider_bubble.xml  （inventory S0841，上游 26 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pd_slider_bubble" fillColor="@android:color/black"> → Path().commands(PathData.pd_slider_bubble).fill('#FF000000')
 */
import { PathData } from '../../drawable/PathData';

@Component
export struct VSliderBubble {
  /** 上游矢量尺寸 26dp×32dp，viewport 26×32；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 26;
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_slider_bubble)
        .fill('#FF000000')
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '26px', height: '32px' })
    .width(this.iconSize)
    .height(this.iconSize * 32 / 26)
    .antiAlias(true)
  }
}