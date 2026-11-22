/**
 * 重绘自 app/src/main/res/drawable/v_sec_primary_x24.xml  （inventory S0835，上游 9 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M12,1L3,5v6c0,5.55 3.84,10.74 9,12 5.16,-1.26 9,-6.45 9,-12L21,5l-9,-4zM12,11.99h7c-0.53,4.12 -3.28,7.79 -7,8.94L12,12L5,12L5,6.3l7,-3.11v8.8z" fillColor="?attr/drawableColorThemePrimary"> → Path().commands('M12,1L3,5v6c0,5.55 3.84,10.74 9,12 5.16,-1.26 9,-6.45 9,-12L21,5l-9,-4zM12,11.99h7c-0.53,4.12 -3.28,7.79 -7,8.94L12,12L5,12L5,6.3l7,-3.11v8.8z').fill(this.fillColor)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct VSecPrimaryX24 {
  /** 上游矢量尺寸 24dp×24dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 24;
  /** 上游 fillColor 取自主题属性，三态值见 DrawablePalette（light/dark/black）；此处默认 light */
  @Prop fillColor: ResourceColor = DrawablePalette.DRAWABLE_PRIMARY_LIGHT;
  build() {
    Shape() {
      Path()
        .commands('M12,1L3,5v6c0,5.55 3.84,10.74 9,12 5.16,-1.26 9,-6.45 9,-12L21,5l-9,-4zM12,11.99h7c-0.53,4.12 -3.28,7.79 -7,8.94L12,12L5,12L5,6.3l7,-3.11v8.8z')
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