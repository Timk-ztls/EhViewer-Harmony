/**
 * Material SearchLayout aligned with Android SearchLayout.java & search_*.xml.
 */

import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';
import { SearchActionLayout } from '../../ui/layout/search_action';
import { SearchCategoryLayout } from '../../ui/layout/search_category';
import { SearchNormalLayout } from '../../ui/layout/search_normal';
import { AdvanceSearchState, AdvanceSearchTable } from './AdvanceSearchTable';
import { CategoryTable, CategoryTableState } from './CategoryTable';
import { HelperImpl, ImageSearchBuilder, ImageSearchLayout, ImageSearchLayoutState } from './ImageSearchLayout';

export interface SearchLayoutBuilder extends ImageSearchBuilder {
  setCategory(category: number): void;

  setAdvanceSearch(advanceSearch: number): void;

  setMinRating(minRating: number): void;

  setPageFrom(pageFrom: number): void;

  setPageTo(pageTo: number): void;
}

export class SearchLayoutSavedState {
  searchMode: number = 0;
  enableAdvance: boolean = false;
}

export class SearchLayoutState {
  static readonly SEARCH_MODE_NORMAL: number = 0;
  static readonly SEARCH_MODE_IMAGE: number = 1;

  searchMode: number = SearchLayoutState.SEARCH_MODE_NORMAL;
  normalSearchMode: number = 0;
  enableAdvance: boolean = false;

  category: CategoryTableState = new CategoryTableState();
  advance: AdvanceSearchState = new AdvanceSearchState();
  image: ImageSearchLayoutState = new ImageSearchLayoutState();

  setSearchMode(searchMode: number): void {
    if (searchMode === SearchLayoutState.SEARCH_MODE_NORMAL || searchMode === SearchLayoutState.SEARCH_MODE_IMAGE) {
      this.searchMode = searchMode;
    }
  }

  toggleSearchMode(): void {
    const next: number = this.searchMode === SearchLayoutState.SEARCH_MODE_NORMAL
      ? SearchLayoutState.SEARCH_MODE_IMAGE
      : SearchLayoutState.SEARCH_MODE_NORMAL;
    this.setSearchMode(next);
  }

  itemCount(): number {
    if (this.searchMode === SearchLayoutState.SEARCH_MODE_NORMAL) {
      return this.enableAdvance ? 3 : 2;
    }
    return 2;
  }

  formatListUrlBuilder(urlBuilder: SearchLayoutBuilder): void {
    urlBuilder.setCategory(this.category.getCategory());
    urlBuilder.setAdvanceSearch(this.advance.getAdvanceSearch());
    urlBuilder.setMinRating(this.advance.getMinRating());
    urlBuilder.setPageFrom(this.advance.getPageFrom());
    urlBuilder.setPageTo(this.advance.getPageTo());
    this.image.formatListUrlBuilder(urlBuilder);
  }

  saveState(): SearchLayoutSavedState {
    const s: SearchLayoutSavedState = new SearchLayoutSavedState();
    s.searchMode = this.searchMode;
    s.enableAdvance = this.enableAdvance;
    return s;
  }

  restoreState(s: SearchLayoutSavedState): void {
    this.searchMode = s.searchMode;
    this.enableAdvance = s.enableAdvance;
  }
}

@Component
export struct SearchLayout {
  state: SearchLayoutState = new SearchLayoutState();
  @State rev: number = 0;
  @State private showHelpDialog: boolean = false;
  @Prop themeId: number = -1;
  @Prop labelNormalMode: ResourceStr = $r('app.string.search_normal_search');
  @Prop labelImageMode: ResourceStr = $r('app.string.image_search');
  @Prop labelEnableAdvance: ResourceStr = $r('app.string.search_enable_advance');
  onOpenTagSelector: () => void = (): void => {
  };
  onSelectImage?: () => void;
  onHelpClick?: () => void;

  aboutToAppear(): void {
    if (this.onSelectImage !== undefined && this.state.image.helper === null) {
      const cb: () => void = this.onSelectImage;
      this.state.image.setHelper(new HelperImpl(cb));
    }
  }

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  @Builder
  private radioModeItem(modeIndex: number, label: ResourceStr, valueKey: string): void {
    Row({ space: ThemeDimens.SPACING_XS }) {
      Radio({ value: valueKey, group: 'normal_search_mode' })
        .checked(this.rev >= 0 && this.state.normalSearchMode === modeIndex)
        .radioStyle({
          checkedBackgroundColor: this.resolvePalette().controlActivated,
          uncheckedBorderColor: this.resolvePalette().textSecondary,
        })
        .width(20)
        .height(20)
        .onChange((isChecked: boolean): void => {
          if (isChecked) {
            this.state.normalSearchMode = modeIndex;
            this.rev++;
          }
        })

      Text(label)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.resolvePalette().textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 36 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.state.normalSearchMode = modeIndex;
      this.rev++;
    })
  }

  @Builder
  private normalCategoryBuilder(): void {
    CategoryTable({
      state: this.state.category,
      themeId: this.themeId,
      onChange: (_category: number): void => {
        this.rev++;
      },
    })
  }

  @Builder
  private normalModeGridBuilder(): void {
    Column({ space: ThemeDimens.SPACING_XS }) {
      Row({ space: ThemeDimens.SPACING }) {
        this.radioModeItem(0, this.labelNormalMode, 'normal')
        this.radioModeItem(1, $r('app.string.search_subscription_search'), 'subscription')
      }.width('100%')

      Row({ space: ThemeDimens.SPACING }) {
        this.radioModeItem(2, $r('app.string.search_specify_uploader'), 'uploader')
        this.radioModeItem(3, $r('app.string.search_specify_tag'), 'tag')
      }.width('100%')
    }
    .width('100%')
  }

  @Builder
  private normalSectionContent(): void {
    SearchNormalLayout({
      enableAdvance: this.rev >= 0 && this.state.enableAdvance,
      labelEnableAdvance: this.labelEnableAdvance,
      themeId: this.themeId,
      onHelpClick: (): void => {
        if (this.onHelpClick !== undefined) {
          this.onHelpClick();
        } else {
          this.showHelpDialog = true;
        }
      },
      onToggleAdvance: (isOn: boolean): void => {
        this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
          this.state.enableAdvance = isOn;
          this.rev++;
        });
      },
      searchCategoryTableBuilder: (): void => {
        this.normalCategoryBuilder();
      },
      normalSearchModeBuilder: (): void => {
        this.normalModeGridBuilder();
      },
    })
  }

  @Builder
  private advanceSectionContent(): void {
    AdvanceSearchTable({
      state: this.state.advance,
      themeId: this.themeId,
    })
  }

  @Builder
  private imageSectionContent(): void {
    ImageSearchLayout({
      state: this.state.image,
      themeId: this.themeId,
    })
  }

  build(): void {
    this.buildRoot();
  }

  @Builder
  private buildRoot(): void {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: ThemeDimens.SPACING_XS }) {
          if (this.rev >= 0 && this.state.searchMode === SearchLayoutState.SEARCH_MODE_NORMAL) {
            SearchCategoryLayout({
              categoryTitle: $r('app.string.search_normal'),
              themeId: this.themeId,
              categoryContentBuilder: (): void => {
                this.normalSectionContent();
              },
            })

            if (this.state.enableAdvance) {
              SearchCategoryLayout({
                categoryTitle: $r('app.string.search_advance'),
                themeId: this.themeId,
                categoryContentBuilder: (): void => {
                  this.advanceSectionContent();
                },
              })
            }
          } else {
            SearchCategoryLayout({
              categoryTitle: $r('app.string.search_image'),
              themeId: this.themeId,
              categoryContentBuilder: (): void => {
                this.imageSectionContent();
              },
            })
          }

          Column() {
            SearchActionLayout({
              searchImageToggle: (this.rev >= 0 && this.state.searchMode === SearchLayoutState.SEARCH_MODE_NORMAL)
                ? this.labelImageMode
                : $r('app.string.keyword_search'),
              tvTagSearchEntrance: $r('app.string.tag_search_entrance'),
              themeId: this.themeId,
              onToggleSearchMode: (): void => {
                this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
                  this.state.toggleSearchMode();
                  this.rev++;
                });
              },
              onOpenTagSearch: (): void => {
                this.onOpenTagSelector();
              },
            })
          }
          .width('100%')
          .margin(ThemeDimens.SPACING_XS)
          .backgroundColor(this.resolvePalette().cardBackground)
          .borderRadius(ThemeRadius.CARD)
          .shadow(ThemeElevation.card())
        }
        .width('100%')
        .padding({
          left: ThemeDimens.SPACING_XS,
          right: ThemeDimens.SPACING_XS,
          top: ThemeDimens.SPACING_XS,
          bottom: ThemeDimens.SPACING_XS,
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)

      if (this.showHelpDialog) {
        Column() {
          Column() {
            Text($r('app.string.search_tip'))
              .fontSize(ThemeTypography.CARD_MESSAGE)
              .fontColor(this.resolvePalette().textSecondary)
              .lineHeight(20)
              .width('100%')

            Row() {
              Blank().layoutWeight(1)
              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.ok'))
                  .fontSize(ThemeTypography.BUTTON)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.resolvePalette().colorPrimary)
              }
              .backgroundColor(this.resolvePalette().transparent)
              .borderRadius(ThemeRadius.BUTTON)
              .constraintSize({ minWidth: 64, minHeight: 36 })
              .padding({ left: 12, right: 12 })
              .onClick((): void => {
                this.showHelpDialog = false;
              })
            }
            .width('100%')
            .margin({ top: ThemeDimens.KEYLINE_MARGIN })
          }
          .width('100%')
          .constraintSize({ maxWidth: 360 })
          .backgroundColor(this.resolvePalette().popupBackground)
          .borderRadius(ThemeRadius.DIALOG)
          .shadow(ThemeElevation.dialog())
          .padding({
            top: 20,
            left: 24,
            right: 24,
            bottom: 8,
          })
          .onClick((): void => {
          })
        }
        .width('100%')
        .height('100%')
        .padding(24)
        .backgroundColor(this.resolvePalette().drawerScrim)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick((): void => {
          this.showHelpDialog = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolvePalette().windowBackground)
  }
}
