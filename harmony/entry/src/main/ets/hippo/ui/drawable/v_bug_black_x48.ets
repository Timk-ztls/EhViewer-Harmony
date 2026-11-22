/**
 * 重绘自 app/src/main/res/drawable/v_bug_black_x48.xml  （inventory S0782，上游 26 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pd_bug" fillColor="@android:color/black"> → Path().commands(PathData.pd_bug).fill('#FF000000')
 */
import { PathData } from '../../drawable/PathData';

@Component
export struct VBugBlackX48 {
  /** 上游矢量尺寸 48dp×48dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 48;
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_bug)
        .fill('#FF000000')
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize * 48 / 48)
    .antiAlias(true)
  }
}