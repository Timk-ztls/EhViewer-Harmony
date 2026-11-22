/*
 * 上游：app/src/main/res/layout/item_history.xml（inventory S0625，上游 24 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_history.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                   ArkUI
 * FrameLayout（单子元素）                     Stack
 *   <include layout="@layout/item_gallery_list" android:id="@+id/card"/>
 *                                             GalleryListItemLayout（S0622 已 ported，直接 import）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游用 `<include>` 展开 item_gallery_list，`android:id="@+id/card"` 只是给被 include 的
 *    根节点挂 id 供 `findViewById(R.id.card)` 取用；ArkUI 无 id 反射查找，
 *    使用方通过本组件对外暴露的 @Prop/@BuilderParam 槽位直接配置卡片（槽位一一透传，见下）。
 * 2. FrameLayout 单子元素 → Stack 是最贴近的对位（上游无 gravity，子元素按 MATCH_PARENT 铺满）。
 * 3. 本布局自身不设 padding/margin（上游也没有），间距由列表侧 item 装饰承担。
 */

import { ThemeDimens, ThemePalette, ThemeTokens } from '../../../common/theme/ThemeTokens';
import { SimpleRatingView } from '../../ehviewer/widget/SimpleRatingView';
import { VDownloadX16 } from '../drawable/v_download_x16';
import { VHeartX16 } from '../drawable/v_heart_x16';
import { GalleryListItemLayout } from './item_gallery_list';

@Component
export struct HistoryItemLayout {
  // ---- 透传给 item_gallery_list 的数据（字段名与 S0622 保持一致） ----
  @Prop title: string = '';
  @Prop uploader: string = '';
  @Prop category: string = '';
  @Prop categoryTextColor: ResourceColor = Color.White;
  @Prop categoryBgColor: ResourceColor = '#FF607D8B';
  @Prop posted: string = '';
  @Prop simpleLanguage: string = '';
  @Prop pages: string = '';
  @Prop downloaded: boolean = false;
  @Prop favourited: boolean = false;
  @Prop rating: number = -1;
  @Prop thumbUrl: string = '';
  @Prop thumbKey: string = '';
  @Prop themeId: number = -1;
  @Prop cardColor: ResourceColor = '';
  @Prop titleColor: ResourceColor = '';
  @Prop messageColor: ResourceColor = '';

  // ---- 控件槽位（ui-widget 提供） ----
  @BuilderParam thumbBuilder: () => void = this.emptyThumb;
  @BuilderParam ratingBuilder: () => void = this.emptyRating;
  @BuilderParam downloadedIconBuilder: () => void = this.defaultDownloadedIcon;
  @BuilderParam favouritedIconBuilder: () => void = this.defaultFavouritedIcon;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private effectiveCardColor(): ResourceColor {
    return this.cardColor !== '' ? this.cardColor : this.palette().cardBackground;
  }

  private effectiveTitleColor(): ResourceColor {
    return this.titleColor !== '' ? this.titleColor : this.palette().textPrimary;
  }

  private effectiveMessageColor(): ResourceColor {
    return this.messageColor !== '' ? this.messageColor : this.palette().textSecondary;
  }

  @Builder
  emptyThumb() {
    Column()
      .width(ThemeDimens.GALLERY_LIST_THUMB_WIDTH)
      .height(ThemeDimens.GALLERY_LIST_THUMB_HEIGHT)
      .backgroundColor(this.palette().thumbPlaceholder)
  }

  @Builder
  emptyRating() {
    if (this.rating >= 0) {
      SimpleRatingView({
        rating: this.rating,
        ratingSize: 16,
        ratingInterval: 1
      })
    } else {
      Row().width(0).height(0)
    }
  }

  @Builder
  defaultDownloadedIcon() {
    VDownloadX16({
      iconSize: 16,
      fillColor: this.palette().drawablePrimary
    })
  }

  @Builder
  defaultFavouritedIcon() {
    VHeartX16({
      iconSize: 16,
      fillColor: this.palette().drawablePrimary
    })
  }

  build() {
    Stack() {
      GalleryListItemLayout({
        title: this.title,
        uploader: this.uploader,
        category: this.category,
        categoryTextColor: this.categoryTextColor,
        categoryBgColor: this.categoryBgColor,
        posted: this.posted,
        simpleLanguage: this.simpleLanguage,
        pages: this.pages,
        downloaded: this.downloaded,
        favourited: this.favourited,
        rating: this.rating,
        thumbUrl: this.thumbUrl,
        thumbKey: this.thumbKey,
        cardColor: this.effectiveCardColor(),
        titleColor: this.effectiveTitleColor(),
        messageColor: this.effectiveMessageColor(),
        thumbBuilder: this.thumbBuilder,
        ratingBuilder: this.ratingBuilder,
        downloadedIconBuilder: this.downloadedIconBuilder,
        favouritedIconBuilder: this.favouritedIconBuilder
      })
    }
    .width('100%')
    .alignContent(Alignment.TopStart)
  }
}
