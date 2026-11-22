/**
 * 重绘自 app/src/main/res/drawable/divider_gallery_detail_dark.xml  （inventory S0726，上游 23 行）
 * 上游节点：<shape>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <solid color="@color/divider_dark"> → .backgroundColor(DrawablePalette.DIVIDER_DARK)
 *   <size width="" height="1dp"> → .width('100%').height(1)
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct DividerGalleryDetailDark {
  @Prop boxWidth: Length = '100%';
  @Prop boxHeight: Length = 1;
  build() {
    Column() {
    }
    .width(this.boxWidth)
    .height(this.boxHeight)
        .backgroundColor(DrawablePalette.DIVIDER_DARK)
    .borderRadius(0)
  }
}