/*
 * 上游：app/src/main/res/layout/gallery_detail_previews.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_previews.ets（inventory S0592）
 */

import {
  ThemeDimens,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';

@Component
export struct GalleryDetailPreviewsLayout {
  @Prop previewText: ResourceStr = $r('app.string.no_previews');
  @Prop hasPreviews: boolean = false;
  @Prop themeId: number = ThemeMode.LIGHT;
  onMoreClick: () => void = (): void => {};

  @BuilderParam gridLayoutBuilder: () => void = this.emptySlot;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column({ space: ThemeDimens.KEYLINE_MARGIN }) {
      if (this.hasPreviews) {
        Column() {
          this.gridLayoutBuilder()
        }
        .id('gridLayout')
        .width('100%')
      }

      Button(this.previewText, { type: ButtonType.Normal })
        .id('previewText')
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(this.palette().transparent)
        .fontColor(this.palette().textThemeAccent)
        .fontSize(ThemeTypography.BUTTON)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
        .padding({ left: 16, right: 16 })
        .onClick((): void => {
          this.onMoreClick();
        })
    }
    .id('previews')
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(ThemeDimens.KEYLINE_MARGIN)
  }
}
