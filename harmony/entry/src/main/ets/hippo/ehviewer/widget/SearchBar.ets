/**
 * Material SearchBar aligned with Android SearchBar.java & widget_search_bar.xml.
 */

import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography,
} from '../../../common/theme/ThemeTokens';
import { PathData } from '../../drawable/PathData';
import { SearchSuggestionItemLayout } from '../../ui/layout/search_suggestion_item';
import { SearchEditText, SearchEditTextListenerImpl } from './SearchEditText';

export interface Suggestion {
  text: string;
}

export interface SuggestionProvider {
  providerSuggestions(text: string): Suggestion[];
}

export interface OnStateChangeListener {
  onStateChange(state: number): void;
}

export class SuggestionProviderImpl implements SuggestionProvider {
  private readonly fn: (text: string) => Suggestion[];

  constructor(fn: (text: string) => Suggestion[]) {
    this.fn = fn;
  }

  providerSuggestions(text: string): Suggestion[] {
    return this.fn(text);
  }
}

export class OnStateChangeListenerImpl implements OnStateChangeListener {
  private readonly fn: (state: number) => void;

  constructor(fn: (state: number) => void) {
    this.fn = fn;
  }

  onStateChange(state: number): void {
    this.fn(state);
  }
}

export class SearchBarState {
  static readonly STATE_NORMAL: number = 0;
  static readonly STATE_SEARCH: number = 1;
  static readonly STATE_SEARCH_LIST: number = 2;
  static readonly ANIMATE_TIME: number = 300;

  state: number = SearchBarState.STATE_NORMAL;
  allowEmptySearch: boolean = true;
  search: string = '';
  listener: OnStateChangeListener | null = null;
  internalSync: (() => void) | null = null;

  getState(): number {
    return this.state;
  }

  setState(state: number, animation: boolean = true): void {
    if (this.state === state) {
      return;
    }
    this.state = state;
    if (this.listener !== null) {
      this.listener.onStateChange(state);
    }
    if (this.internalSync !== null) {
      this.internalSync();
    }
    const _anim: boolean = animation;
  }

  onBackPressed(): void {
    if (this.state !== SearchBarState.STATE_NORMAL) {
      this.setState(SearchBarState.STATE_NORMAL, true);
    }
  }

  setAllowEmptySearch(allowEmptySearch: boolean): void {
    this.allowEmptySearch = allowEmptySearch;
  }

  setSearch(search: string): void {
    this.search = search;
    if (this.internalSync !== null) {
      this.internalSync();
    }
  }

  canSubmit(): boolean {
    return this.allowEmptySearch || this.search.length > 0;
  }
}

@Component
export struct SearchBar {
  state: SearchBarState = new SearchBarState();
  provider: SuggestionProvider | null = null;
  @Prop title: string = '';
  @Prop placeholder: string = '';
  @Prop cardColor: ResourceColor = '';
  @Prop actionIcon: ResourceColor = '';
  @Prop themeId: number = -1;
  @State suggestions: Suggestion[] = [];
  @State expanded: boolean = false;
  @State private modeState: number = SearchBarState.STATE_NORMAL;
  @State private searchText: string = '';
  onSubmit: (search: string) => void = (): void => {
  };
  onMenuClick: () => void = (): void => {
  };
  onActionClick?: () => void;
  onTitleClick?: () => void;

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

  private effectiveIconColor(palette: ThemePalette): ResourceColor {
    if (this.actionIcon !== '') {
      return this.actionIcon;
    }
    return palette.drawablePrimary;
  }

  aboutToAppear(): void {
    this.state.internalSync = (): void => {
      this.syncFromState();
    };
    this.syncFromState();
  }

  aboutToDisappear(): void {
    if (this.state.internalSync !== null) {
      this.state.internalSync = null;
    }
  }

  private syncFromState(): void {
    this.modeState = this.state.getState();
    this.searchText = this.state.search;
    this.expanded = this.modeState === SearchBarState.STATE_SEARCH_LIST;
    if (this.expanded) {
      this.refreshSuggestions(this.searchText);
    } else {
      this.suggestions = [];
    }
  }

  private refreshSuggestions(text: string): void {
    if (this.provider !== null) {
      this.suggestions = this.provider.providerSuggestions(text);
    } else {
      this.suggestions = [];
    }
  }

  private applyMode(nextMode: number, animate: boolean): void {
    const update = (): void => {
      this.state.setState(nextMode, animate);
      this.modeState = this.state.getState();
      this.expanded = nextMode === SearchBarState.STATE_SEARCH_LIST;
      if (this.expanded) {
        this.refreshSuggestions(this.searchText);
      } else {
        this.suggestions = [];
      }
    };
    if (animate) {
      this.getUIContext().animateTo({ duration: SearchBarState.ANIMATE_TIME, curve: Curve.FastOutSlowIn }, update);
    } else {
      update();
    }
  }

  private submitSearch(query: string): void {
    this.searchText = query;
    this.state.search = query;
    if (!this.state.canSubmit()) {
      return;
    }
    this.onSubmit(query);
    this.applyMode(SearchBarState.STATE_NORMAL, true);
  }

  private handleLeftClick(): void {
    if (this.modeState === SearchBarState.STATE_NORMAL) {
      this.onMenuClick();
      return;
    }
    this.applyMode(SearchBarState.STATE_NORMAL, true);
  }

  private handleActionClick(): void {
    if (this.modeState === SearchBarState.STATE_NORMAL) {
      if (this.onActionClick !== undefined) {
        this.onActionClick();
      } else {
        this.applyMode(SearchBarState.STATE_SEARCH, true);
      }
      return;
    }
    if (this.searchText.length > 0) {
      this.searchText = '';
      this.state.search = '';
      if (this.expanded) {
        this.refreshSuggestions('');
      }
      return;
    }
    if (this.state.canSubmit()) {
      this.submitSearch('');
    } else if (this.onActionClick !== undefined) {
      this.onActionClick();
    }
  }

  build(): void {
    this.buildSearchBar();
  }

  @Builder
  private buildSearchBar(): void {
    Column() {
      Row() {
        Stack() {
          if (this.modeState === SearchBarState.STATE_NORMAL) {
            Column({ space: 3 }) {
              Row()
                .width(18)
                .height(2)
                .backgroundColor(this.effectiveIconColor(this.resolvePalette()))
              Row()
                .width(18)
                .height(2)
                .backgroundColor(this.effectiveIconColor(this.resolvePalette()))
              Row()
                .width(18)
                .height(2)
                .backgroundColor(this.effectiveIconColor(this.resolvePalette()))
            }
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Shape() {
              Path()
                .commands(PathData.pd_arrow_left)
                .fill(this.effectiveIconColor(this.resolvePalette()))
                .stroke(Color.Transparent)
                .strokeWidth(0)
            }
            .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .antiAlias(true)
          }
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .padding(ThemeDimens.SPACING_MD)
        .alignContent(Alignment.Center)
        .onClick((): void => {
          this.handleLeftClick();
        })

        Stack() {
          if (this.modeState === SearchBarState.STATE_NORMAL) {
            Text(this.title)
              .width('100%')
              .fontSize(ThemeTypography.TEXT_LITTLE_LARGE)
              .fontColor(this.resolvePalette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
              .onClick((): void => {
                if (this.onTitleClick !== undefined) {
                  this.onTitleClick();
                }
                this.applyMode(SearchBarState.STATE_SEARCH, true);
              })
          } else {
            SearchEditText({
              text: this.searchText,
              placeholder: this.placeholder,
              themeId: this.themeId,
              listener: new SearchEditTextListenerImpl(
                (): void => {
                  this.applyMode(SearchBarState.STATE_SEARCH_LIST, true);
                },
                (): void => {
                  this.applyMode(SearchBarState.STATE_NORMAL, true);
                }
              ),
              onTextChange: (value: string): void => {
                this.searchText = value;
                this.state.search = value;
                if (!this.expanded && value.length > 0 && this.provider !== null) {
                  this.applyMode(SearchBarState.STATE_SEARCH_LIST, true);
                } else if (this.expanded) {
                  this.refreshSuggestions(value);
                }
              },
              onSubmitAction: (value: string): void => {
                this.submitSearch(value);
              },
            })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .alignContent(Alignment.Start)

        Stack() {
          if (this.modeState !== SearchBarState.STATE_NORMAL && this.searchText.length > 0) {
            Shape() {
              Path()
                .commands(PathData.pd_close)
                .fill(this.effectiveIconColor(this.resolvePalette()))
                .stroke(Color.Transparent)
                .strokeWidth(0)
            }
            .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .antiAlias(true)
          } else {
            Shape() {
              Path()
                .commands(PathData.pd_magnify)
                .fill(this.effectiveIconColor(this.resolvePalette()))
                .stroke(Color.Transparent)
                .strokeWidth(0)
            }
            .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .antiAlias(true)
          }
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .padding(ThemeDimens.SPACING_MD)
        .alignContent(Alignment.Center)
        .onClick((): void => {
          this.handleActionClick();
        })
      }
      .width('100%')
      .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      if (this.expanded && this.suggestions.length > 0) {
        Column() {
          Divider()
            .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
            .color(this.resolvePalette().divider)

          List() {
            ForEach(this.suggestions, (item: Suggestion, _index: number): void => {
              ListItem() {
                SearchSuggestionItemLayout({
                  hintview: item.text,
                  textview: '',
                  themeId: this.themeId,
                  onItemClick: (): void => {
                    this.submitSearch(item.text);
                  },
                })
              }
            }, (item: Suggestion, index: number): string => `${index}_${item.text}`)
          }
          .width('100%')
          .constraintSize({ maxHeight: 280 })
        }
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
