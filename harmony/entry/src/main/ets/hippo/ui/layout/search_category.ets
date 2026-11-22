/**
 * Material CardView.Normal wrapper aligned with Android res/layout/search_category.xml.
 */

import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';

@Component
export struct SearchCategoryLayout {
  @Prop categoryTitle: ResourceStr = '';
  @Prop themeId: number = -1;
  @BuilderParam categoryContentBuilder: () => void = this.emptySlot;

  @Builder
  private emptySlot(): void {
  }

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  private hasTitle(): boolean {
    if (typeof this.categoryTitle === 'string') {
      return this.categoryTitle.length > 0;
    }
    return true;
  }

  build(): void {
    this.buildCard();
  }

  @Builder
  private buildCard(): void {
    Column() {
      if (this.hasTitle()) {
        Text(this.categoryTitle)
          .fontColor(this.resolvePalette().textThemeAccent)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontWeight(FontWeight.Bold)
          .id('categoryTitle')
          .width('100%')
          .height(ThemeDimens.SEARCH_CATEGORY_TITLE_HEIGHT)
          .textAlign(TextAlign.Start)
      }

      Column() {
        this.categoryContentBuilder()
      }
      .id('categoryContent')
      .width('100%')
    }
    .width('100%')
    .margin(ThemeDimens.SPACING_XS)
    .padding({
      left: ThemeDimens.KEYLINE_MARGIN,
      right: ThemeDimens.KEYLINE_MARGIN,
      bottom: ThemeDimens.KEYLINE_MARGIN,
      top: this.hasTitle() ? 0 : ThemeDimens.KEYLINE_MARGIN,
    })
    .backgroundColor(this.resolvePalette().cardBackground)
    .borderRadius(ThemeRadius.CARD)
    .shadow(ThemeElevation.card())
  }
}
