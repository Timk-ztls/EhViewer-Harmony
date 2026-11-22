/**
 * 重绘自 app/src/main/res/drawable/ic_eh_news_24.xml  （inventory S0748，上游 10 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="@string/pd_news" fillColor="@android:color/black"> → Path().commands(PathData.pd_news).fill('#FF000000')
 */
import { PathData } from '../../drawable/PathData';

@Component
export struct IcEhNews24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_news)
        .fill('#FF000000')
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize * 24 / 24)
    .antiAlias(true)
  }
}