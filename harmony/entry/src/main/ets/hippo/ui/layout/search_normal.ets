/**
 * SearchNormalLayout aligned with Android res/layout/search_normal.xml.
 */

import {
  ThemeDimens,
  ThemePalette,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';
import { VHelpCircleX24 } from '../drawable/v_help_circle_x24';

@Component
export struct SearchNormalLayout {
  @Prop enableAdvance: boolean = false;
  @Prop labelEnableAdvance: ResourceStr = $r('app.string.search_enable_advance');
  @Prop themeId: number = -1;
  onHelpClick: () => void = (): void => {
  };
  onToggleAdvance: (isOn: boolean) => void = (_isOn: boolean): void => {
  };
  @BuilderParam normalSearchModeBuilder: () => void = this.emptySlot;
  @BuilderParam searchCategoryTableBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot(): void {
    Column().width(0).height(0)
  }

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  build(): void {
    this.buildLayout();
  }

  @Builder
  private buildLayout(): void {
    Column() {
      Column() {
        this.searchCategoryTableBuilder()
      }
      .id('searchCategoryTable')
      .width('100%')
      .margin({ bottom: ThemeDimens.SEARCH_ITEM_INTERVAL })

      Column() {
        this.normalSearchModeBuilder()
      }
      .id('normalSearchMode')
      .width('100%')
      .padding({ top: ThemeDimens.SEARCH_ITEM_INTERVAL })

      Row() {
        Stack() {
          VHelpCircleX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.resolvePalette().drawablePrimary,
          })
        }
        .id('normalSearchModeHelp')
        .width(36)
        .height(36)
        .padding(ThemeDimens.SPACING_SM)
        .alignContent(Alignment.Center)
        .onClick((): void => {
          this.onHelpClick();
        })

        Blank().layoutWeight(1)

        Row({ space: ThemeDimens.SPACING }) {
          Text(this.labelEnableAdvance)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.resolvePalette().textPrimary)

          Toggle({ type: ToggleType.Switch, isOn: this.enableAdvance })
            .id('searchEnableAdvance')
            .selectedColor(this.resolvePalette().controlActivated)
            .switchPointColor(this.resolvePalette().white)
            .onChange((isOn: boolean): void => {
              this.onToggleAdvance(isOn);
            })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ top: ThemeDimens.SPACING_XS })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}
