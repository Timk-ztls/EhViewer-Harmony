/**
 * Material SearchActionLayout aligned with Android res/layout/search_action.xml.
 */

import {
  ThemeDimens,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';

@Component
export struct SearchActionLayout {
  @Prop searchImageToggle: ResourceStr = $r('app.string.image_search');
  @Prop tvTagSearchEntrance: ResourceStr = $r('app.string.tag_search_entrance');
  @Prop themeId: number = -1;
  onToggleSearchMode: () => void = (): void => {
  };
  onOpenTagSearch: () => void = (): void => {
  };

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  build(): void {
    this.buildActions();
  }

  @Builder
  private buildActions(): void {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Text(this.searchImageToggle)
          .fontSize(ThemeTypography.BUTTON)
          .fontColor(this.resolvePalette().colorAccent)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .id('searchImageToggle')
      .layoutWeight(1)
      .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
      .padding(ThemeDimens.SPACING_MD)
      .backgroundColor(this.resolvePalette().transparent)
      .borderRadius(ThemeRadius.BUTTON)
      .onClick((): void => {
        this.onToggleSearchMode();
      })

      Column()
        .width(1)
        .height(ThemeDimens.ICON_SIZE_STANDARD)
        .backgroundColor(this.resolvePalette().divider)

      Button({ type: ButtonType.Normal }) {
        Text(this.tvTagSearchEntrance)
          .fontSize(ThemeTypography.BUTTON)
          .fontColor(this.resolvePalette().colorAccent)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .id('tvTagSearchEntrance')
      .layoutWeight(1)
      .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
      .padding(ThemeDimens.SPACING_MD)
      .backgroundColor(this.resolvePalette().transparent)
      .borderRadius(ThemeRadius.BUTTON)
      .onClick((): void => {
        this.onOpenTagSearch();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
