/**
 * 重绘自 app/src/main/res/drawable/v_top_lists_x24.xml  （inventory S0846，上游 10 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M9,17L7,17v-7h2v7zM13,17h-2L11,7h2v10zM17,17h-2v-4h2v4zM19.5,19.1h-15L4.5,5h15v14.1zM19.5,3h-15c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h15c1.1,0 2,-0.9 2,-2L21.5,5c0,-1.1 -0.9,-2 -2,-2z" fillColor="@android:color/black"> → Path().commands('M9,17L7,17v-7h2v7zM13,17h-2L11,7h2v10zM17,17h-2v-4h2v4zM19.5,19.1h-15L4.5,5h15v14.1zM19.5,3h-15c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h15c1.1,0 2,-0.9 2,-2L21.5,5c0,-1.1 -0.9,-2 -2,-2z').fill('#FF000000')
 */
import { PathData } from '../../drawable/PathData';

@Component
export struct VTopListsX24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  @Prop fillColor: ResourceColor = '#FF000000';
  build() {
    Shape() {
      Path()
        .commands(PathData.pd_top_lists)
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