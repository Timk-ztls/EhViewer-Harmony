/*
 * 上游：app/src/main/res/layout/gallery_detail_info.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_info.ets（inventory S0591）
 */

import {
  ThemeDimens,
  ThemeMode,
  ThemePalette,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';

@Component
export struct GalleryDetailInfoLayout {
  @Prop language: string = '';
  @Prop pages: string = '';
  @Prop sizeText: string = '';
  @Prop favoredTimes: string = '';
  @Prop posted: string = '';
  @Prop themeId: number = ThemeMode.LIGHT;
  onInfoClick: () => void = (): void => {};

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  build() {
    Column() {
      Column() {
        Row() {
          Text(this.language)
            .id('language')
            .layoutWeight(1)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textPrimary)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.pages)
            .id('pages')
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textPrimary)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .margin({ left: 8, right: 8 })

          Text(this.sizeText)
            .id('size')
            .layoutWeight(1)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textPrimary)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row() {
          Text(this.favoredTimes)
            .id('favoredTimes')
            .layoutWeight(1)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textPrimary)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.posted)
            .id('posted')
            .layoutWeight(1)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textPrimary)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: ThemeDimens.KEYLINE_MARGIN,
        right: ThemeDimens.KEYLINE_MARGIN
      })

      Text($r('app.string.more_information'))
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.palette().textThemeAccent)
        .margin({ top: 16 })
    }
    .id('info')
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .padding(ThemeDimens.KEYLINE_MARGIN)
    .onClick((): void => {
      this.onInfoClick();
    })
  }
}
