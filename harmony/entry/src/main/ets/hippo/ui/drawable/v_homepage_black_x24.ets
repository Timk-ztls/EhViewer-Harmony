/**
 * 重绘自 app/src/main/res/drawable/v_homepage_black_x24.xml  （inventory S0816，上游 26 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pd_homepage" fillColor="@android:color/black"> → Path().commands(PathData.pd_homepage).fill('#FF000000')
 */
import { PathData } from '../../drawable/PathData';

@Component
export struct VHomepageBlackX24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  @Prop fillColor: ResourceColor = '#FF000000';
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_homepage)
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