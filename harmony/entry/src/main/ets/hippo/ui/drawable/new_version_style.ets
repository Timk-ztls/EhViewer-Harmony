/**
 * 重绘自 app/src/main/res/drawable/new_version_style.xml  （inventory S0764，上游 5 行）
 * 上游节点：<shape>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="@color/new_version_bg_color"> → .backgroundColor(DrawablePalette.NEW_VERSION_BG_COLOR)
 *   <corners radius="9dp"> → .borderRadius(9)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct NewVersionStyle {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(DrawablePalette.NEW_VERSION_BG_COLOR)
    .borderRadius(9)
  }
}