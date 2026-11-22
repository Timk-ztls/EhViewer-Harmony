/*
 * 上游：app/src/main/res/layout/item_gallery_preview.xml（inventory S0623）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_preview.ets
 */

import {
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';

@Component
export struct GalleryPreviewItemLayout {
  @Prop text: string = '';
  @Prop aspect: number = 0.667;
  @Prop themeId: number = ThemeMode.LIGHT;

  @BuilderParam thumbBuilder: () => void = this.defaultThumb;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  @Builder
  defaultThumb() {
    Column()
      .width('100%')
      .aspectRatio(this.aspect)
      .backgroundColor(this.palette().thumbPlaceholder)
      .borderRadius(ThemeRadius.CARD)
  }

  build() {
    Column({ space: 4 }) {
      Column() {
        this.thumbBuilder()
      }
      .width('100%')

      Text(this.text)
        .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
        .fontColor(this.palette().textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
