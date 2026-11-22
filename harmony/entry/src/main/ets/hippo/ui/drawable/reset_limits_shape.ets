/**
 * 重绘自 app/src/main/res/drawable/reset_limits_shape.xml  （inventory S0768，上游 5 行）
 * 上游节点：<shape>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <stroke width="1"dp color="?attr/tagBackgroundColor"> → .border({ width: 1, color: DrawablePalette.TAG_BACKGROUND_LIGHT })
 *   <corners radius="6dp"> → .borderRadius(6)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct ResetLimitsShape {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: DrawablePalette.TAG_BACKGROUND_LIGHT })
    .borderRadius(6)
  }
}