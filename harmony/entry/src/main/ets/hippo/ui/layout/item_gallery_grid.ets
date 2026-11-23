/*
 * 上游：app/src/main/res/layout/item_gallery_grid.xml（inventory S0617）
 *
 * 对位要点：
 * - CardView.Normal: margin 2dp, cornerRadius 2dp, elevation 2dp, cardBackgroundColor=?attr/contentColorPrimary
 * - TileThumb#thumb: match_parent x wrap_content, aspect=clamp(w/h, 0.33, 1.5), centerCrop, retryType=none
 * - #category: 32x24vp top|right 直角三角形 (0,0)->(32,0)->(32,24) 填充分类色 (TriangleDrawable)
 * - #simple_language: 10fp bold white top|right margin(right: 2, top: 1)
 */

import {
  CategoryColors,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { TileThumb } from '../../ehviewer/widget/TileThumb';
import { LoadImageController } from '../../widget/LoadImageView';
import { TileBackground } from '../drawable/tile_background';

@Reusable
@Component
export struct ItemGalleryGridLayout {
  @Prop category: string = '';
  @Prop categoryColor: ResourceColor = CategoryColors.UNKNOWN;
  @Prop simpleLanguage: string = '';
  @Prop simpleLanguageColor: ResourceColor = ThemeTokens.current().white;
  @Prop @Watch('onThumbChanged') thumbUrl: string = '';
  @Prop @Watch('onThumbChanged') thumbKey: string = '';
  @Prop thumbWidth: number = 0;
  @Prop thumbHeight: number = 0;
  @Prop themeId: number = -1;
  @Prop cardColor: ResourceColor = ThemeTokens.current().cardBackground;
  @Prop activated: boolean = false;

  private thumbController: LoadImageController = new LoadImageController();
  private loadedSig: string = '';

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  @BuilderParam thumbBuilder: () => void = this.defaultThumb;

  aboutToAppear(): void {
    this.thumbController.setRetryType(LoadImageController.RETRY_TYPE_NONE);
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

  @Builder
  defaultThumb() {
    TileThumb({
      controller: this.thumbController,
      thumbWidth: this.thumbWidth,
      thumbHeight: this.thumbHeight,
      imageFit: ImageFit.Cover
    })
  }

  @Builder
  activatedOverlay() {
    TileBackground({ activated: true })
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          this.thumbBuilder()
        }
        .id('grid_thumb')
        .width('100%')
        .backgroundColor(this.palette().thumbPlaceholder)
        .overlay(this.activated ? this.activatedOverlay() : undefined)

        // 右上角 32x24vp 分类三角角标（对齐 Android TriangleDrawable）
        Polygon({ width: 32, height: 24 })
          .points([[0, 0], [32, 0], [32, 24]])
          .fill(this.categoryColor)
          .stroke(Color.Transparent)
          .strokeWidth(0)
          .antiAlias(true)
          .id('grid_category')

        if (this.simpleLanguage.length > 0) {
          Text(this.simpleLanguage)
            .id('simpleLanguage')
            .fontSize(ThemeTypography.TEXT_GRID_LANG)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.simpleLanguageColor)
            .maxLines(1)
            .margin({ right: 2, top: 1 })
        }
      }
      .width('100%')
      .borderRadius(ThemeRadius.CARD)
      .backgroundColor(this.cardColor)
      .shadow(ThemeElevation.card())
      .clip(true)
    }
    .width('100%')
    .padding(2)
  }
}
