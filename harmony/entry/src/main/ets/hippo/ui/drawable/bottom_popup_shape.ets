/**
 * 重绘自 app/src/main/res/drawable/bottom_popup_shape.xml  （inventory S0724，上游 6 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="?attr/popupWindowStyle"> → .backgroundColor(DrawablePalette.POPUP_WINDOW_LIGHT)
 *   <corners radius="@dimen/popup_text_padding"> → .borderRadius(4)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct BottomPopupShape {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(DrawablePalette.POPUP_WINDOW_LIGHT)
    .borderRadius(4)
  }
}