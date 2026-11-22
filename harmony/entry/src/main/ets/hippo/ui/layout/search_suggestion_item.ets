/**
 * Material SearchSuggestionItemLayout aligned with Android res/layout/search_suggestion_item.xml.
 */

import {
  ThemeDimens,
  ThemePalette,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';

@Component
export struct SearchSuggestionItemLayout {
  @Prop hintview: string = '';
  @Prop textview: string = '';
  @Prop themeId: number = -1;
  onItemClick: () => void = (): void => {
  };

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  build(): void {
    this.buildRow();
  }

  @Builder
  private buildRow(): void {
    Column() {
      Text(this.hintview)
        .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
        .fontColor(this.resolvePalette().textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: this.textview.length > 0 ? ThemeDimens.SPACING_XS : 0 })

      if (this.textview.length > 0) {
        Text(this.textview)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.resolvePalette().textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
    .padding({
      left: ThemeDimens.KEYLINE_MARGIN,
      right: ThemeDimens.KEYLINE_MARGIN,
      top: ThemeDimens.SPACING,
      bottom: ThemeDimens.SPACING,
    })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.resolvePalette().transparent)
    .onClick((): void => {
      this.onItemClick();
    })
  }
}
