/**
 * 重绘自 app/src/main/res/drawable/top_list_item_bg.xml  （inventory S0774，上游 8 行）
 * 上游节点：<shape>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <stroke width="1"dp color="?android:attr/textColorSecondary"> → .border({ width: 1, color: DrawablePalette.TEXT_COLOR_SECONDARY_LIGHT })
 *   <corners radius="@dimen/top_list_item_radius"> → .borderRadius(5)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct TopListItemBg {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = '100%';
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: DrawablePalette.TEXT_COLOR_SECONDARY_LIGHT })
    .borderRadius(5)
  }
}