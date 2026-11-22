/**
 * 重绘自 app/src/main/res/drawable-v21/app_widget_inner_view_background.xml  （inventory S0861，上游 10 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: v21）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="?android:attr/colorAccent"> → .backgroundColor(DrawablePalette.COLOR_ACCENT_LIGHT)
 *   <corners radius="?attr/appWidgetInnerRadius"> → .borderRadius(DrawablePalette.APP_WIDGET_INNER_RADIUS)
 */
import { DrawablePalette } from '../../../drawable/DrawablePalette';

@Component
export struct AppWidgetInnerViewBackground {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(DrawablePalette.COLOR_ACCENT_LIGHT)
    .borderRadius(DrawablePalette.APP_WIDGET_INNER_RADIUS)
  }
}