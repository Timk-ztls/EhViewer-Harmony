/**
 * 重绘自 app/src/main/res/drawable/ic_baseline_filter_24.xml  （inventory S0735，上游 10 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M15.96,10.29l-2.75,3.54 -1.96,-2.36L8.5,15h11l-3.54,-4.71zM3,5L1,5v16c0,1.1 0.9,2 2,2h16v-2L3,21L3,5zM21,1L7,1c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2L23,3c0,-1.1 -0.9,-2 -2,-2zM21,17L7,17L7,3h14v14z" fillColor="@color/primary_drawable_dark"> → Path().commands('M15.96,10.29l-2.75,3.54 -1.96,-2.36L8.5,15h11l-3.54,-4.71zM3,5L1,5v16c0,1.1 0.9,2 2,2h16v-2L3,21L3,5zM21,1L7,1c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2L23,3c0,-1.1 -0.9,-2 -2,-2zM21,17L7,17L7,3h14v14z').fill('#FFFFFFFF')
 */


@Component
export struct IcBaselineFilter24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  build() {
    Shape() {
      Path()
        .commands('M15.96,10.29l-2.75,3.54 -1.96,-2.36L8.5,15h11l-3.54,-4.71zM3,5L1,5v16c0,1.1 0.9,2 2,2h16v-2L3,21L3,5zM21,1L7,1c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2L23,3c0,-1.1 -0.9,-2 -2,-2zM21,17L7,17L7,3h14v14z')
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