/**
 * 重绘自 app/src/main/res/drawable/home_item_shape.xml  （inventory S0731，上游 5 行）
 * 上游节点：<shape>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="?attr/tagBackgroundColor"> → .backgroundColor(DrawablePalette.TAG_BACKGROUND_LIGHT)
 *   <corners radius="6dp"> → .borderRadius(6)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct HomeItemShape {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(DrawablePalette.TAG_BACKGROUND_LIGHT)
    .borderRadius(6)
  }
}