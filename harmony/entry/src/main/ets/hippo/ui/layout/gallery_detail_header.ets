/*
 * 上游：app/src/main/res/layout/gallery_detail_header.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_header.ets（inventory S0590）
 */

import {
  CategoryColors,
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { VArrowLeftDarkX24 } from '../drawable/v_arrow_left_dark_x24';
import { VDotsVerticalSecondaryDarkX24 } from '../drawable/v_dots_vertical_secondary_dark_x24';

@Component
export struct GalleryDetailHeaderLayout {
  @Prop category: string = '';
  @Prop categoryColor: string = CategoryColors.UNKNOWN;
  @Prop newVersion: ResourceStr = $r('app.string.have_new_version');
  @Prop title: string = '';
  @Prop titleJpn: string = '';
  @Prop uploader: string = '';
  @Prop downloadText: ResourceStr = $r('app.string.download');
  @Prop downloadEnabled: boolean = true;
  @Prop showBackButton: boolean = true;
  @Prop showOverflowMenu: boolean = true;
  @Prop archiverProgressVisibility: Visibility = Visibility.None;
  @Prop newVersionVisibility: Visibility = Visibility.None;
  @Prop themeId: number = ThemeMode.LIGHT;

  onBackClick: () => void = (): void => {};
  onMenuClick: () => void = (): void => {};
  onThumbClick: () => void = (): void => {};
  onTitleClick: () => void = (): void => {};
  onUploaderClick: () => void = (): void => {};
  onUploaderLongClick: () => void = (): void => {};
  onCategoryClick: () => void = (): void => {};
  onNewVersionClick: () => void = (): void => {};
  onDownloadClick: () => void = (): void => {};
  onDownloadLongClick: () => void = (): void => {};
  onReadClick: () => void = (): void => {};

  @BuilderParam actionCardBuilder: () => void = this.defaultActionCard;
  @BuilderParam archiverDownloadProgressBuilder: () => void = this.emptySlot;
  @BuilderParam thumbBuilder: () => void = this.emptySlot;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  @Builder
  defaultActionCard() {
    Row() {
      Button(this.downloadText, { type: ButtonType.Normal })
        .id('download')
        .layoutWeight(1)
        .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
        .borderRadius(ThemeRadius.NONE)
        .backgroundColor(this.palette().galleryDetailButtonBackground)
        .fontColor(this.palette().textThemePrimary)
        .fontSize(ThemeTypography.BUTTON)
        .fontWeight(FontWeight.Bold)
        .padding(8)
        .enabled(this.downloadEnabled)
        .onClick((): void => {
          this.onDownloadClick();
        })
        .gesture(
          LongPressGesture()
            .onAction((): void => {
              this.onDownloadLongClick();
            })
        )

      Column()
        .width(ThemeDimens.DIVIDER_HEIGHT)
        .height(32)
        .margin({ top: 8, bottom: 8 })
        .backgroundColor(this.palette().divider)

      Button($r('app.string.read'), { type: ButtonType.Normal })
        .id('read')
        .layoutWeight(1)
        .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
        .borderRadius(ThemeRadius.NONE)
        .backgroundColor(this.palette().galleryDetailButtonBackground)
        .fontColor(this.palette().textThemeAccent)
        .fontSize(ThemeTypography.BUTTON)
        .fontWeight(FontWeight.Bold)
        .padding(8)
        .onClick((): void => {
          this.onReadClick();
        })
    }
    .width('100%')
    .backgroundColor(this.palette().cardWhiteSurface)
    .borderRadius(ThemeRadius.CARD)
    .clip(true)
    .shadow(ThemeElevation.card())
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Column() {
        if (this.showBackButton || this.showOverflowMenu) {
          Row() {
            if (this.showBackButton) {
              Row() {
                VArrowLeftDarkX24({
                  iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                  fillColor: this.palette().toolbarIconColor
                })
              }
              .width(ThemeDimens.TOUCH_TARGET_MIN)
              .height(ThemeDimens.TOUCH_TARGET_MIN)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .onClick((): void => {
                this.onBackClick();
              })
            }

            Blank().layoutWeight(1)

            if (this.showOverflowMenu) {
              Row() {
                VDotsVerticalSecondaryDarkX24({
                  iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                  fillColor: this.themeId === ThemeMode.BLACK
                    ? ThemeTokens.BLACK.drawableSecondary
                    : ThemeTokens.DARK.drawableSecondary
                })
              }
              .id('otherActions')
              .width(48)
              .height(56)
              .padding({ left: 12, top: 16, right: 12, bottom: 16 })
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .onClick((): void => {
                this.onMenuClick();
              })
            }
          }
          .width('100%')
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .padding({ left: 4, right: 4 })
          .alignItems(VerticalAlign.Center)
        }

        Row() {
          Stack() {
            this.thumbBuilder()
          }
          .id('detail_header_thumb')
          .width(ThemeDimens.GALLERY_DETAIL_THUMB_WIDTH)
          .height(ThemeDimens.GALLERY_DETAIL_THUMB_HEIGHT)
          .margin({
            left: ThemeDimens.KEYLINE_MARGIN,
            top: 8,
            bottom: ThemeDimens.KEYLINE_MARGIN
          })
          .borderRadius(ThemeRadius.CARD)
          .clip(true)
          .backgroundColor(this.palette().thumbPlaceholder)
          .shadow(ThemeElevation.card())
          .onClick((): void => {
            this.onThumbClick();
          })

          Column() {
            Text(this.title)
              .id('detail_header_title')
              .fontSize(ThemeTypography.TEXT_LITTLE_LARGE)
              .fontColor(this.palette().galleryDetailHeaderTitle)
              .maxLines(5)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick((): void => {
                this.onTitleClick();
              })

            if (this.uploader.length > 0) {
              Text(this.uploader)
                .id('detail_header_uploader')
                .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                .fontColor(this.palette().galleryDetailHeaderTitle)
                .opacity(0.85)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 8 })
                .onClick((): void => {
                  this.onUploaderClick();
                })
                .gesture(
                  LongPressGesture()
                    .onAction((): void => {
                      this.onUploaderLongClick();
                    })
                )
            }

            if (this.category.length > 0) {
              Text(this.category.toUpperCase())
                .id('detail_header_category')
                .fontSize(ThemeTypography.TEXT_SMALL)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette().white)
                .backgroundColor(this.categoryColor)
                .borderRadius(ThemeRadius.CATEGORY_BADGE)
                .padding({ left: 8, top: 2, right: 8, bottom: 2 })
                .margin({ top: 12 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick((): void => {
                  this.onCategoryClick();
                })
            }
          }
          .layoutWeight(1)
          .margin({
            left: ThemeDimens.KEYLINE_MARGIN,
            top: 8,
            right: ThemeDimens.KEYLINE_MARGIN,
            bottom: ThemeDimens.KEYLINE_MARGIN
          })
          .alignItems(HorizontalAlign.Start)
        }
        .id('viewHead')
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (this.archiverProgressVisibility === Visibility.Visible) {
          Column() {
            this.archiverDownloadProgressBuilder()
          }
          .id('archiverDownloadProgress')
          .width('100%')
        }

        if (this.newVersionVisibility === Visibility.Visible) {
          Text(this.newVersion)
            .id('newVersion')
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().textThemePrimary2)
            .backgroundColor(this.palette().newVersionBg)
            .borderRadius(9)
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            .margin({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN, bottom: 8 })
            .onClick((): void => {
              this.onNewVersionClick();
            })
        }
      }
      .id('colorBg')
      .width('100%')
      .padding({ bottom: 24 })
      .backgroundColor(this.palette().galleryDetailHeaderBackground)
      .shadow(ThemeElevation.toolbar())
      .alignItems(HorizontalAlign.Center)

      Column() {
        this.actionCardBuilder()
      }
      .id('actionCard')
      .width('100%')
      .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
      .margin({ top: -24 })
      .zIndex(2)
    }
    .id('header')
    .width('100%')
  }
}
