/*
 * 上游：app/src/main/res/layout/item_gallery_list.xml（inventory S0622）
 *
 * 对位要点：
 * - CardView.Reactive: margin 2dp, contentPadding 0dp, cornerRadius 2dp, elevation 2dp, ?attr/contentColorReactive
 * - FixedThumb#thumb: 80x120vp, minAspect 0.333, maxAspect 1.333, retryType click
 * - TextView#title: @style/CardTitle (16fp, textPrimary, maxLines 2, Ellipsis)
 * - TextView#uploader: @style/CardMessage (14fp, textSecondary, maxLines 1, Ellipsis)
 * - SimpleRatingView#rating: 16vp stars, 1vp interval, above category
 * - TextView#category: @style/CardMessage, white, allCaps, padding 8/2, marginBottom 8, borderRadius 2vp
 * - LinearLayout info_row: VDownloadX16 / VHeartX16 (16x16) / simple_language / pages, space 6vp, above posted
 * - TextView#posted: @style/CardMessage (14fp, textSecondary), bottom-right
 */

import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { FixedThumb } from '../../ehviewer/widget/FixedThumb';
import { SimpleRatingView } from '../../ehviewer/widget/SimpleRatingView';
import { LoadImageController } from '../../widget/LoadImageView';
import { VDownloadX16 } from '../drawable/v_download_x16';
import { VHeartX16 } from '../drawable/v_heart_x16';

@Reusable
@Component
export struct GalleryListItemLayout {
  // ---- 数据（保留全部既有 @Prop 名，兼容 FavoritesSceneView / HistorySceneView / GalleryListHostPage） ----
  @Prop title: string = '';
  @Prop uploader: string = '';
  @Prop category: string = '';
  @Prop categoryTextColor: ResourceColor = ThemeTokens.current().white;
  @Prop categoryBgColor: ResourceColor = '#FF607D8B';
  @Prop posted: string = '';
  @Prop simpleLanguage: string = '';
  @Prop pages: string = '';
  @Prop downloaded: boolean = false;
  @Prop favourited: boolean = false;
  @Prop rating: number = -1;
  @Prop @Watch('onThumbChanged') thumbUrl: string = '';
  @Prop @Watch('onThumbChanged') thumbKey: string = '';
  @Prop showRating: boolean = true;
  @Prop activated: boolean = false;
  @Prop themeId: number = -1;
  /** 卡片底色：上游 CardView.Reactive → ?attr/contentColorReactive */
  @Prop cardColor: ResourceColor = ThemeTokens.current().cardBackground;
  @Prop titleColor: ResourceColor = ThemeTokens.current().textPrimary;
  @Prop messageColor: ResourceColor = ThemeTokens.current().textSecondary;

  private thumbController: LoadImageController = new LoadImageController();
  private loadedSig: string = '';

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    this.thumbController.setRetryType(LoadImageController.RETRY_TYPE_CLICK);
    this.loadThumb();
  }

  aboutToReuse(_params: Record<string, Object>): void {
    this.thumbController.onAttached();
    this.loadThumb();
  }

  aboutToRecycle(): void {
    this.loadedSig = '';
    this.thumbController.onDetached();
  }

  aboutToDisappear(): void {
    this.loadedSig = '';
    this.thumbController.onDetached();
  }

  private onThumbChanged(): void {
    this.loadThumb();
  }

  private loadThumb(): void {
    if (this.thumbUrl.length > 0) {
      const key: string = this.thumbKey.length > 0 ? this.thumbKey : this.thumbUrl;
      const sig: string = key + '|' + this.thumbUrl;
      if (this.loadedSig === sig) {
        return;
      }
      this.loadedSig = sig;
      this.thumbController.resetClip();
      this.thumbController.load(key, this.thumbUrl);
    } else {
      this.loadedSig = '';
      this.thumbController.unload();
    }
  }

  // ---- 控件槽位（默认注入真实控件，同时保留 @BuilderParam 覆盖能力） ----
  @BuilderParam thumbBuilder: () => void = this.emptyThumb;
  @BuilderParam ratingBuilder: () => void = this.emptyRating;
  @BuilderParam downloadedIconBuilder: () => void = this.defaultDownloadedIcon;
  @BuilderParam favouritedIconBuilder: () => void = this.defaultFavouritedIcon;

  @Builder
  emptyThumb() {
    FixedThumb({
      controller: this.thumbController,
      minAspect: 0.333,
      maxAspect: 1.333
    })
  }

  @Builder
  emptyRating() {
    if (this.showRating && this.rating >= 0) {
      SimpleRatingView({
        rating: this.rating,
        ratingSize: ThemeDimens.RATING_SIZE,
        ratingInterval: ThemeDimens.RATING_INTERVAL
      })
    } else {
      Row().width(0).height(ThemeDimens.RATING_SIZE)
    }
  }

  @Builder
  defaultDownloadedIcon() {
    VDownloadX16({
      iconSize: ThemeDimens.ICON_SIZE_SMALL,
      fillColor: this.messageColor
    })
  }

  @Builder
  defaultFavouritedIcon() {
    VHeartX16({
      iconSize: ThemeDimens.ICON_SIZE_SMALL,
      fillColor: this.messageColor
    })
  }

  build() {
    // 外层 2vp 边距对应 android:layout_margin="2dp"，避免 width('100%') + margin 溢出
    Column() {
      Row() {
        // thumb（FixedThumb：80x120vp，contentPadding=0 直接贴卡片左上角）
        Column() {
          this.thumbBuilder();
        }
        .id('thumb')
        .width($r('app.float.gallery_list_thumb_width'))
        .height($r('app.float.gallery_list_thumb_height'))
        .backgroundColor(this.palette().thumbPlaceholder)
        .clip(true)

        Column() {
          Column() {
            // title（@style/CardTitle：16fp / maxLines 2 / Ellipsis）
            Text(this.title)
              .id('title')
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontColor(this.titleColor)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            // uploader（@style/CardMessage：14fp / textColorSecondary / 单行）
            Text(this.uploader)
              .id('uploader')
              .fontSize(ThemeTypography.CARD_MESSAGE)
              .fontColor(this.messageColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 2 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Row() {
            Column({ space: 4 }) {
              // rating（SimpleRatingView，位于 category 之上、与 title 左对齐）
              Column() {
                this.ratingBuilder();
              }
              .id('rating')
              .visibility(this.showRating && this.rating >= 0 ? Visibility.Visible : Visibility.Hidden)

              // category（14fp / allCaps / 白字 / 8/2 padding / 贴 thumb 底 + marginBottom 4）
              Text(this.category.toUpperCase())
                .id('category')
                .fontSize(ThemeTypography.CARD_MESSAGE)
                .fontColor(this.categoryTextColor)
                .backgroundColor(this.category.length > 0 ? this.categoryBgColor : Color.Transparent)
                .borderRadius(ThemeRadius.CATEGORY_BADGE)
                .maxLines(1)
                .padding({ left: 8, top: 2, right: 8, bottom: 2 })
                .margin({ bottom: 4 })
                .visibility(this.category.length > 0 ? Visibility.Visible : Visibility.Hidden)
            }
            .alignItems(HorizontalAlign.Start)

            Column({ space: 2 }) {
              // 右侧信息行（downloaded / favourited / simpleLanguage / pages），位于 posted 之上
              Row({ space: 6 }) {
                if (this.downloaded) {
                  this.downloadedIconBuilder();
                }
                if (this.favourited) {
                  this.favouritedIconBuilder();
                }
                if (this.simpleLanguage.length > 0) {
                  Text(this.simpleLanguage)
                    .fontSize(ThemeTypography.CARD_MESSAGE)
                    .fontColor(this.messageColor)
                    .maxLines(1)
                }
                if (this.pages.length > 0) {
                  Text(this.pages)
                    .fontSize(ThemeTypography.CARD_MESSAGE)
                    .fontColor(this.messageColor)
                    .maxLines(1)
                }
              }
              .id('info_row')
              .alignItems(VerticalAlign.Center)

              // posted（@style/CardMessage：14fp / 贴 thumb 底 + 父右）
              Text(this.posted)
                .id('posted')
                .fontSize(ThemeTypography.CARD_MESSAGE)
                .fontColor(this.messageColor)
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Bottom)
        }
        .layoutWeight(1)
        .height('100%')
        .padding({ left: 8, top: 4, right: 6, bottom: 4 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height($r('app.float.gallery_list_thumb_height'))
      .borderRadius(ThemeRadius.CARD)
      .backgroundColor(this.activated ? this.palette().cardActivatedBackground : this.cardColor)
      .shadow(ThemeElevation.card())
      .clip(true)
    }
    .width('100%')
    .padding(2)
  }
}
