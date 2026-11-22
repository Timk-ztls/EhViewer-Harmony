/**
 * 重绘自 app/src/main/res/drawable-v25/ic_shortcut_stop.xml  （inventory S0864，上游 15 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: v25）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M46,24A22,22 0,0 1,24 46,22 22,0 0,1 2,24 22,22 0,0 1,24 2,22 22,0 0,1 46,24Z" fillColor="@color/shortcut_bg"> → Path().commands('M46,24A22,22 0,0 1,24 46,22 22,0 0,1 2,24 22,22 0,0 1,24 2,22 22,0 0,1 46,24Z').fill(DrawablePalette.SHORTCUT_BG)
 *   <path pathData="m18,31h4L22,17h-4zM26,17v14h4L30,17Z" fillColor="@color/colorPrimary"> → Path().commands('m18,31h4L22,17h-4zM26,17v14h4L30,17Z').fill(DrawablePalette.TEAL_500)
 */
import { DrawablePalette } from '../../../drawable/DrawablePalette';

@Component
export struct IcShortcutStop {
  /** 上游矢量尺寸 48dp×48dp，viewport 48×48；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 48;
  build() {
    Shape() {
      Path()
        .commands('M46,24A22,22 0,0 1,24 46,22 22,0 0,1 2,24 22,22 0,0 1,24 2,22 22,0 0,1 46,24Z')
        .fill(DrawablePalette.SHORTCUT_BG)
        .stroke(Color.Transparent)
        .strokeWidth(0)
        .fillOpacity(1)
      Path()
        .commands('m18,31h4L22,17h-4zM26,17v14h4L30,17Z')
        .fill(DrawablePalette.TEAL_500)
        .stroke(Color.Transparent)
        .strokeWidth(0)
        .fillOpacity(1)
    }
    .viewPort({ x: 0, y: 0, width: '48px', height: '48px' })
    .width(this.iconSize)
    .height(this.iconSize * 48 / 48)
    .antiAlias(true)
  }
}