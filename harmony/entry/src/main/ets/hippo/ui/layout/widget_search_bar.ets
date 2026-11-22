/**
 * Material SearchBarWidgetLayout aligned with Android res/layout/widget_search_bar.xml.
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
export struct SearchBarWidgetLayout {
  @Prop title: string = '';
  @Prop text: string = '';
  @Prop placeholder: string = '';
  @Prop editing: boolean = false;
  @Prop showSuggestions: boolean = false;
  @Prop textColorSecondary: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop cardColor: ResourceColor = '';
  @Prop themeId: number = -1;
  onTextChange: (value: string) => void = (_value: string): void => {
  };
  onSubmitAction: (value: string) => void = (_value: string): void => {
  };
  onTitleClick: () => void = (): void => {
  };
  onMenuClick: () => void = (): void => {
  };
  onActionClick: () => void = (): void => {
  };
  @BuilderParam menuIconBuilder: () => void = this.emptyIcon;
  @BuilderParam actionIconBuilder: () => void = this.emptyIcon;
  @BuilderParam suggestionsBuilder: () => void = this.emptySuggestions;

  @Builder
  private emptyIcon(): void {
  }

  @Builder
  private emptySuggestions(): void {
  }

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  private effectiveCardColor(palette: ThemePalette): ResourceColor {
    if (this.cardColor !== '') {
      return this.cardColor;
    }
    return palette.cardWhiteSurface;
  }

  private effectiveTextSecondary(palette: ThemePalette): ResourceColor {
    if (this.textColorSecondary !== '') {
      return this.textColorSecondary;
    }
    return palette.textSecondary;
  }

  private effectiveDividerColor(palette: ThemePalette): ResourceColor {
    if (this.dividerColor !== '') {
      return this.dividerColor;
    }
    return palette.divider;
  }

  build(): void {
    this.buildCard();
  }

  @Builder
  private buildCard(): void {
    Column() {
      Row() {
        Stack() {
          this.menuIconBuilder()
        }
        .id('searchMenu')
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .padding(ThemeDimens.SPACING_MD)
        .alignContent(Alignment.Center)
        .onClick((): void => {
          this.onMenuClick();
        })

        Stack() {
          if (this.editing) {
            TextInput({ text: this.text, placeholder: this.placeholder })
              .id('searchEditText')
              .width('100%')
              .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
              .padding(0)
              .backgroundColor(this.resolvePalette().transparent)
              .borderRadius(ThemeRadius.NONE)
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontColor(this.resolvePalette().textPrimary)
              .placeholderColor(this.resolvePalette().textHint)
              .placeholderFont({ size: ThemeTypography.TEXT_LITTLE_SMALL })
              .caretColor(this.resolvePalette().controlActivated)
              .enterKeyType(EnterKeyType.Search)
              .maxLines(1)
              .onChange((value: string): void => {
                this.onTextChange(value);
              })
              .onSubmit((): void => {
                this.onSubmitAction(this.text);
              })
          } else {
            Text(this.title)
              .id('searchTitle')
              .width('100%')
              .fontSize(ThemeTypography.TEXT_LITTLE_LARGE)
              .fontColor(this.effectiveTextSecondary(this.resolvePalette()))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .onClick((): void => {
                this.onTitleClick();
              })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .alignContent(Alignment.Start)

        Stack() {
          this.actionIconBuilder()
        }
        .id('searchAction')
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .padding(ThemeDimens.SPACING_MD)
        .alignContent(Alignment.Center)
        .onClick((): void => {
          this.onActionClick();
        })
      }
      .width('100%')
      .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      if (this.showSuggestions) {
        Column() {
          Divider()
            .id('listHeader')
            .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
            .color(this.effectiveDividerColor(this.resolvePalette()))

          Column() {
            this.suggestionsBuilder()
          }
          .id('searchBarList')
          .width('100%')
          .constraintSize({ maxHeight: 280 })
        }
        .id('listContainer')
        .width('100%')
      }
    }
    .width('100%')
    .backgroundColor(this.effectiveCardColor(this.resolvePalette()))
    .borderRadius(ThemeRadius.SEARCH_BAR)
    .shadow(ThemeElevation.searchBar())
    .clip(true)
  }
}
