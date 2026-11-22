/*
 * 上游：app/src/main/res/layout/gallery_detail_actions.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_actions.ets（inventory S0587）
 */

import {
  ThemeDimens,
  ThemeMode,
  ThemePalette,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { DrawablePalette } from '../../drawable/DrawablePalette';
import { SimpleRatingView } from '../../ehviewer/widget/SimpleRatingView';
import { VHeartPrimaryX48 } from '../drawable/v_heart_primary_x48';
import { VHeartOutlinePrimaryX48 } from '../drawable/v_heart_outline_primary_x48';
import { VThumbUpPrimaryX48 } from '../drawable/v_thumb_up_primary_x48';
import { VSharePrimaryX48 } from '../drawable/v_share_primary_x48';
import { VUtorrentPrimaryX48 } from '../drawable/v_utorrent_primary_x48';
import { VArchiverPrimaryX48 } from '../drawable/v_archiver_primary_x48';
import { VArchiveHhPrimaryX48 } from '../drawable/v_archive_hh_primary_x48';
import { VSimilarPrimaryX48 } from '../drawable/v_similar_primary_x48';
import { VFileFindPrimaryX48 } from '../drawable/v_file_find_primary_x48';

@Component
export struct GalleryDetailActionsLayout {
  @Prop favorited: boolean = false;
  @Prop favoriteLabel: string = '';
  @Prop rating: number = 0;
  @Prop rated: boolean = false;
  @Prop ratingText: string = '';
  @Prop showRating: boolean = true;
  @Prop torrentText: string = '';
  @Prop showTorrent: boolean = true;
  @Prop themeId: number = ThemeMode.LIGHT;

  onHeartClick: () => void = (): void => {};
  onHeartLongClick: () => void = (): void => {};
  onRateClick: () => void = (): void => {};
  onShareClick: () => void = (): void => {};
  onTorrentClick: () => void = (): void => {};
  onArchiverClick: () => void = (): void => {};
  onHhClick: () => void = (): void => {};
  onSimilarClick: () => void = (): void => {};
  onSearchCoverClick: () => void = (): void => {};

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  build() {
    Column() {
      Scroll() {
        Row({ space: ThemeDimens.KEYLINE_MARGIN }) {
          Stack() {
            if (this.favorited) {
              Column({ space: 8 }) {
                VHeartPrimaryX48({
                  iconSize: ThemeDimens.ICON_SIZE_LARGE,
                  fillColor: this.palette().drawableThemePrimary
                })
                Text(this.favoriteLabel.length > 0 ? this.favoriteLabel : $r('app.string.favorited'))
                  .id('heart')
                  .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                  .fontColor(this.palette().textPrimary)
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Center)
            } else {
              Column({ space: 8 }) {
                VHeartOutlinePrimaryX48({
                  iconSize: ThemeDimens.ICON_SIZE_LARGE,
                  fillColor: this.palette().drawableThemePrimary
                })
                Text($r('app.string.not_favorited'))
                  .id('heart_outline')
                  .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                  .fontColor(this.palette().textPrimary)
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Center)
            }
          }
          .id('heart_group')
          .constraintSize({ minWidth: 52 })
          .onClick((): void => {
            this.onHeartClick();
          })
          .gesture(
            LongPressGesture()
              .onAction((): void => {
                this.onHeartLongClick();
              })
          )

          Column({ space: 8 }) {
            VThumbUpPrimaryX48({
              iconSize: ThemeDimens.ICON_SIZE_LARGE,
              fillColor: this.rated ? this.palette().colorAccent : this.palette().drawableThemePrimary
            })
            Text($r('app.string.rate'))
              .id('rate')
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontWeight(this.rated ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.rated ? this.palette().colorAccent : this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }
          .constraintSize({ minWidth: 52 })
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.onRateClick();
          })

          Column({ space: 8 }) {
            VSharePrimaryX48({
              iconSize: ThemeDimens.ICON_SIZE_LARGE,
              fillColor: this.palette().drawableThemePrimary
            })
            Text($r('app.string.share'))
              .id('share')
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }
          .constraintSize({ minWidth: 52 })
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.onShareClick();
          })

          if (this.showTorrent) {
            Column({ space: 8 }) {
              VUtorrentPrimaryX48({
                iconSize: ThemeDimens.ICON_SIZE_LARGE,
                fillColor: this.palette().drawableThemePrimary
              })
              Text(this.torrentText)
                .id('torrent')
                .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                .fontColor(this.palette().textPrimary)
                .textAlign(TextAlign.Center)
                .maxLines(1)
            }
            .constraintSize({ minWidth: 52 })
            .alignItems(HorizontalAlign.Center)
            .onClick((): void => {
              this.onTorrentClick();
            })
          }

          Column({ space: 8 }) {
            VArchiverPrimaryX48({
              iconSize: ThemeDimens.ICON_SIZE_LARGE,
              fillColor: this.palette().drawableThemePrimary
            })
            Text($r('app.string.archiver'))
              .id('archiver')
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }
          .constraintSize({ minWidth: 52 })
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.onArchiverClick();
          })

          Column({ space: 8 }) {
            VArchiveHhPrimaryX48({
              iconSize: ThemeDimens.ICON_SIZE_LARGE,
              fillColor: this.palette().drawableThemePrimary
            })
            Text($r('app.string.h_h'))
              .id('h_h')
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }
          .constraintSize({ minWidth: 52 })
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.onHhClick();
          })

          Column({ space: 8 }) {
            VSimilarPrimaryX48({
              iconSize: ThemeDimens.ICON_SIZE_LARGE,
              fillColor: this.palette().drawableThemePrimary
            })
            Text($r('app.string.similar_gallery'))
              .id('similar')
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }
          .constraintSize({ minWidth: 52 })
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.onSimilarClick();
          })

          Column({ space: 8 }) {
            VFileFindPrimaryX48({
              iconSize: ThemeDimens.ICON_SIZE_LARGE,
              fillColor: this.palette().drawableThemePrimary
            })
            Text($r('app.string.search_cover'))
              .id('search_cover')
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .maxLines(1)
          }
          .constraintSize({ minWidth: 52 })
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.onSearchCoverClick();
          })
        }
        .constraintSize({ minWidth: '100%' })
        .justifyContent(FlexAlign.Center)
        .padding({
          left: ThemeDimens.KEYLINE_MARGIN,
          right: ThemeDimens.KEYLINE_MARGIN
        })
      }
      .id('actions_scroll_view')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.showRating) {
        Column({ space: 4 }) {
          SimpleRatingView({
            rating: this.rating,
            ratingSize: 20,
            ratingInterval: 2,
            starColor: this.rated ? this.palette().colorAccent : DrawablePalette.YELLOW_800
          })
            .id('rating')

          Text(this.ratingText)
            .id('rating_text')
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontWeight(this.rated ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.rated ? this.palette().colorAccent : this.palette().textPrimary)
        }
        .margin({ top: 12 })
        .alignItems(HorizontalAlign.Center)
        .onClick((): void => {
          this.onRateClick();
        })
      }
    }
    .id('actions')
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .padding({ top: ThemeDimens.KEYLINE_MARGIN, bottom: ThemeDimens.KEYLINE_MARGIN })
  }
}
