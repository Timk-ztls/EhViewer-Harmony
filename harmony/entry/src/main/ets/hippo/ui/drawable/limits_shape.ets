/**
 * 重绘自 app/src/main/res/drawable/limits_shape.xml  （inventory S0763，上游 8 行）
 * 上游节点：<shape android:shape="rectangle">
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="?attr/limits_shape_color"> → .backgroundColor(DrawablePalette.LIMITS_SHAPE_LIGHT)
 *   <corners radius="6dp"> → .borderRadius(6)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct LimitsShape {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(DrawablePalette.LIMITS_SHAPE_LIGHT)
    .borderRadius(6)
  }
}