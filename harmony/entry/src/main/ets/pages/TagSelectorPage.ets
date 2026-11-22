/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Phase B Track P3: TagSelectorPage (@Entry @Component V1, PageRoutes.TAG_SELECTOR).
 *
 * Mirrors upstream TagSelectorActivity: awaits AppWiring.whenReady(), initializes
 * TagSelectorPageCoordinator over EhTagDatabaseSuggester (with graceful fallback when
 * tag DB is not downloaded), renders toolbar, search filter input, selected tags card
 * (grouped by namespace with removable chips + count + empty state), grouped 3-column
 * tag grid with More/Collapse/End footers, and confirm Search button delivering
 * selectedQueryText() via TagSelectorResultBus before router.back().
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { GetText } from '../hippo/ehviewer/GetText';
import { Settings } from '../hippo/ehviewer/Settings';
import {
  FooterState,
  SelectedTagGroup,
  TagItem,
  TagPair,
  TagSelectorColors
} from '../hippo/ehviewer/ui/TagSelectorActivity';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VCloseDarkX24 } from '../hippo/ui/drawable/v_close_dark_x24';
import {
  EhTagDatabaseSuggester,
  P3TextFormatter,
  TagSelectorGroupSnapshot,
  TagSelectorPageCoordinator
} from '../hippo/ui/p3/P3PageAdapters';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'TagSelectorPage';
const GRID_COLUMNS: number = 3;

class TagChipTripleRow {
  readonly rowKey: string;
  readonly items: TagItem[];

  constructor(rowKey: string, items: TagItem[]) {
    this.rowKey = rowKey;
    this.items = items;
  }
}

@Entry
@Component
export struct TagSelectorPage {
  @State ready: boolean = false;
  @State isDarkMode: boolean = false;
  @State isChineseSystem: boolean = true;
  @State searchKeyword: string = '';
  @State selectedCount: number = 0;
  @State selectedGroups: SelectedTagGroup[] = [];
  @State selectedKeys: string[] = [];
  @State groupSnapshots: TagSelectorGroupSnapshot[] = [];

  private coordinator: TagSelectorPageCoordinator = new TagSelectorPageCoordinator(
    EhTagDatabaseSuggester.fromAppFiles()
  );

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.initializeSelector().catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'TagSelectorPage init failed: %{public}s', msg);
      this.coordinator.init('en-US', false, '');
      this.syncViewState();
      this.ready = true;
    });
  }

  private async initializeSelector(): Promise<void> {
    await AppWiring.whenReady();
    let initialQuery: string = '';
    try {
      const rawParams: Object = this.getUIContext().getRouter().getParams();
      if (rawParams !== undefined && rawParams !== null) {
        const record: Record<string, Object> = rawParams as Record<string, Object>;
        const selectedParam: Object | undefined = record['selected_tags'];
        const queryParam: Object | undefined = record['initial_query'];
        if (typeof selectedParam === 'string' && selectedParam.length > 0) {
          initialQuery = selectedParam;
        } else if (typeof queryParam === 'string' && queryParam.length > 0) {
          initialQuery = queryParam;
        }
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to read TagSelectorPage params: %{public}s', JSON.stringify(err));
    }

    const appLang: string = Settings.getAppLanguage();
    const dark: boolean = Settings.getDarkModeStatus();
    this.isDarkMode = dark;
    this.coordinator.init(appLang, dark, initialQuery);
    this.isChineseSystem = this.coordinator.isChineseSystem();
    this.syncViewState();
    this.ready = true;
  }

  private syncViewState(): void {
    this.selectedCount = this.coordinator.getSelectedCount();
    this.selectedGroups = this.coordinator.getSelectedGroups();
    const nextKeys: string[] = [];
    this.coordinator.getActivity().selectedTags.forEach((_show: string, key: string): void => {
      nextKeys.push(key);
    });
    this.selectedKeys = nextKeys;
    this.groupSnapshots = this.coordinator.getGroupSnapshots();
  }

  private isTagSelected(key: string): boolean {
    return this.selectedKeys.indexOf(key) >= 0;
  }

  private navigateBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Router back failed: %{public}s', JSON.stringify(err));
    }
  }

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  private colors(): TagSelectorColors {
    return TagSelectorColors.of(this.isDarkMode);
  }

  private pageBackgroundColor(): ResourceColor {
    const c: TagSelectorColors = this.colors();
    return c.gridBackground.length > 0 ? c.gridBackground : $r('app.color.start_window_background');
  }

  private cardBackgroundColor(): ResourceColor {
    const c: TagSelectorColors = this.colors();
    return c.cardBackground.length > 0 ? c.cardBackground : '#FFFFFFFF';
  }

  private formatSelectedCountLabel(): string {
    const formatted: string = GetText.getStringFormat('tag_selector_selected_count', [this.selectedCount]);
    if (formatted.length > 0) {
      return formatted;
    }
    const tpl: string = GetText.getString('tag_selector_selected_count');
    return P3TextFormatter.formatCount(tpl, this.selectedCount);
  }

  private resolveSelectedGroupTitle(title: string): ResourceStr {
    if (title === 'tag_selector_other_group') {
      return $r('app.string.tag_selector_other_group');
    }
    return title;
  }

  private footerMoreLabel(): string {
    return TagSelectorPageCoordinator.footerMoreText(
      this.isChineseSystem,
      GetText.getString('tag_selector_more')
    );
  }

  private footerCollapseLabel(): string {
    return TagSelectorPageCoordinator.footerCollapseText(
      this.isChineseSystem,
      GetText.getString('tag_selector_collapse')
    );
  }

  private footerEndLabel(): string {
    return TagSelectorPageCoordinator.footerEndText(
      this.isChineseSystem,
      GetText.getString('tag_selector_end')
    );
  }

  private chunkIntoThreeColumnRows(namespace: string, items: TagItem[]): TagChipTripleRow[] {
    const rows: TagChipTripleRow[] = [];
    for (let i = 0; i < items.length; i += GRID_COLUMNS) {
      const slice: TagItem[] = items.slice(i, i + GRID_COLUMNS);
      const firstKey: string = slice.length > 0 ? slice[0].key : `${i}`;
      rows.push(new TagChipTripleRow(`${namespace}:${firstKey}`, slice));
    }
    return rows;
  }

  private onToggleTag(item: TagItem): void {
    this.coordinator.toggleTag(item.key, item.show);
    this.syncViewState();
  }

  private onRemoveSelectedTag(key: string): void {
    this.coordinator.removeSelected(key);
    this.syncViewState();
  }

  private onClearAllSelected(): void {
    this.coordinator.clearSelected();
    this.syncViewState();
  }

  private onLoadMoreGroup(namespace: string): void {
    this.coordinator.loadNextBatch(namespace);
    this.syncViewState();
  }

  private onCollapseGroup(namespace: string): void {
    this.coordinator.collapseGroup(namespace);
    this.syncViewState();
  }

  private onConfirmSearch(): void {
    this.coordinator.confirmSelection();
    this.navigateBack();
  }

  @Builder
  selectedTagsCard(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text($r('app.string.tag_selector_selected_section_title'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors().selectedSectionTitle)
          .layoutWeight(1)

        Text(this.formatSelectedCountLabel())
          .fontSize(12)
          .fontColor(this.colors().selectedEmptyText)
      }
      .width('100%')

      if (this.selectedCount === 0) {
        Text($r('app.string.tag_selector_empty_selected'))
          .fontSize(13)
          .fontColor(this.colors().selectedEmptyText)
          .width('100%')
          .padding({ top: 2, bottom: 2 })
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.selectedGroups, (selGroup: SelectedTagGroup) => {
              Column({ space: 4 }) {
                Text(this.resolveSelectedGroupTitle(selGroup.title))
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.colors().selectedGroupHeader)
                  .width('100%')

                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(selGroup.entries, (entry: TagPair) => {
                    Row({ space: 4 }) {
                      Text(entry.second !== null && entry.second.length > 0
                        ? entry.second
                        : (entry.first !== null ? entry.first : ''))
                        .fontSize(12)
                        .fontColor(this.colors().selectedChipText)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Text('×')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.colors().selectedChipText)
                    }
                    .padding({ left: 10, right: 8, top: 5, bottom: 5 })
                    .margin({ right: 6, bottom: 6 })
                    .borderRadius(14)
                    .backgroundColor(this.colors().selectedChipBg)
                    .onClick((): void => {
                      if (entry.first !== null) {
                        this.onRemoveSelectedTag(entry.first);
                      }
                    })
                  }, (entry: TagPair) => entry.first !== null ? entry.first : '')
                }
                .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (selGroup: SelectedTagGroup) => selGroup.title)
          }
          .width('100%')
        }
        .align(Alignment.TopStart)
        .constraintSize({ maxHeight: 140 })
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor(this.cardBackgroundColor())
    .shadow({ radius: 3, color: '#1F000000', offsetY: 1 })
  }

  @Builder
  tagGroupSection(group: TagSelectorGroupSnapshot): void {
    Column({ space: 8 }) {
      Text(group.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors().headerColor)
        .width('100%')
        .padding({ left: 4, top: 10, bottom: 2 })

      ForEach(this.chunkIntoThreeColumnRows(group.namespace, group.visibleItems), (triple: TagChipTripleRow) => {
        Row({ space: 8 }) {
          ForEach(triple.items, (item: TagItem) => {
            Column() {
              Text(item.show)
                .fontSize(13)
                .fontColor(this.isTagSelected(item.key)
                  ? this.colors().selectedChipText
                  : this.colors().unselectedText)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .layoutWeight(1)
            .padding({ left: 6, right: 6, top: 9, bottom: 9 })
            .borderRadius(8)
            .backgroundColor(this.isTagSelected(item.key)
              ? this.colors().selectedBg
              : this.colors().unselectedBg)
            .border({
              width: this.isTagSelected(item.key) ? 0 : 1,
              color: this.colors().unselectedBorder
            })
            .onClick((): void => {
              this.onToggleTag(item);
            })
          }, (item: TagItem) => item.key)

          if (triple.items.length < GRID_COLUMNS) {
            Blank().layoutWeight(GRID_COLUMNS - triple.items.length)
          }
        }
        .width('100%')
      }, (triple: TagChipTripleRow) => triple.rowKey)

      if (!group.hasSearchFilter) {
        Row() {
          Blank().layoutWeight(1)

          if (group.footerState === FooterState.END) {
            Text(this.footerEndLabel())
              .fontSize(13)
              .fontColor(this.colors().footerColor)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          } else {
            Button(this.footerMoreLabel())
              .type(ButtonType.Normal)
              .height(32)
              .fontSize(13)
              .fontColor(this.colors().footerColor)
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.onLoadMoreGroup(group.namespace);
              })
          }

          Row() {
            Blank()
            if (group.showCollapse) {
              Button(this.footerCollapseLabel())
                .type(ButtonType.Normal)
                .height(30)
                .fontSize(12)
                .fontColor(this.colors().footerColor)
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.onCollapseGroup(group.namespace);
                })
            }
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 2, bottom: 6 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.navigateBack();
        })

        Text($r('app.string.tag_search_entrance'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.selectedCount > 0) {
          Button($r('app.string.clear_all'))
            .type(ButtonType.Normal)
            .height(36)
            .fontSize(13)
            .fontColor('#FFFFFFFF')
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.onClearAllSelected();
            })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 10 })
      .backgroundColor($r('app.color.teal_500'))

      if (!this.ready) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.teal_500'))

          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor('#FF616161')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            TextInput({ text: this.searchKeyword, placeholder: $r('app.string.tag_selector_search_hint') })
              .type(InputType.Normal)
              .enterKeyType(EnterKeyType.Search)
              .maxLines(1)
              .fontColor(this.isDarkMode ? '#FFE0E0E0' : '#DE000000')
              .backgroundColor(this.cardBackgroundColor())
              .borderRadius(8)
              .layoutWeight(1)
              .onChange((value: string): void => {
                this.searchKeyword = value;
                this.coordinator.setSearchKeyword(value);
                this.syncViewState();
              })

            if (this.searchKeyword.length > 0) {
              Button({ type: ButtonType.Normal }) {
                VCloseDarkX24({
                  iconSize: 20,
                  fillColor: this.isDarkMode ? ThemeTokens.DARK.drawablePrimary : ThemeTokens.LIGHT.drawablePrimary
                })
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.searchKeyword = '';
                this.coordinator.setSearchKeyword('');
                this.syncViewState();
              })
            }
          }
          .width('100%')

          this.selectedTagsCard()
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })

        if (this.groupSnapshots.length === 0) {
          Column() {
            Text($r('app.string.empty_result'))
              .fontSize(14)
              .fontColor(this.colors().selectedEmptyText)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List() {
            ForEach(this.groupSnapshots, (group: TagSelectorGroupSnapshot) => {
              ListItem() {
                this.tagGroupSection(group)
              }
            }, (group: TagSelectorGroupSnapshot) => group.namespace)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 8 })
        }

        Column() {
          Button($r('app.string.search'))
            .type(ButtonType.Normal)
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFFFF')
            .backgroundColor($r('app.color.teal_500'))
            .borderRadius(8)
            .onClick((): void => {
              this.onConfirmSearch();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 14 })
        .backgroundColor(this.cardBackgroundColor())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBackgroundColor())
  }
}
