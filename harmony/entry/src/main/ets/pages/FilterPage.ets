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
 * Phase B Track P3: FilterPage (@Entry @Component V1, PageRoutes.FILTER).
 *
 * Mirrors upstream FilterActivity: awaits AppWiring.whenReady(), loads grouped
 * Title/Uploader/Tag/TagNamespace filters from EhDB, supports toggling enabled state
 * (strikethrough), delete confirmation dialog, add sheet with mode picker + validation
 * keeping sheet open on empty input, and help tip dialog.
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { GetText } from '../hippo/ehviewer/GetText';
import { FilterActivityState, FilterItem } from '../hippo/ehviewer/ui/FilterActivity';
import { BigFilter } from '../hippo/ui/drawable/big_filter';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VDeleteX24 } from '../hippo/ui/drawable/v_delete_x24';
import { VInfoOutlineDarkX24 } from '../hippo/ui/drawable/v_info_outline_dark_x24';
import { VPlusDarkX24 } from '../hippo/ui/drawable/v_plus_dark_x24';
import {
  EhDbFilterPersistencePort,
  FILTER_MODE_TAG,
  FILTER_MODE_TAG_NAMESPACE,
  FILTER_MODE_TITLE,
  FILTER_MODE_UPLOADER,
  FilterDisplayRow,
  FilterOperationResult,
  FilterPageAdapter,
  FilterRecord,
  FilterStatePort,
  P3TextFormatter
} from '../hippo/ui/p3/P3PageAdapters';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'FilterPage';

class FilterActivityStateBridge implements FilterStatePort {
  private readonly state: FilterActivityState;

  constructor(state: FilterActivityState) {
    this.state = state;
  }

  syncFromRecords(records: FilterRecord[]): void {
    const next: FilterItem[] = [];
    for (let i = 0; i < records.length; i++) {
      const r: FilterRecord = records[i];
      const item: FilterItem = new FilterItem();
      item.mode = r.mode;
      item.text = r.text;
      item.enabled = r.enabled;
      next.push(item);
    }
    this.state.filters = next;
  }

  isEmpty(): boolean {
    return this.state.isEmpty();
  }

  visibleView(): number {
    return this.state.visibleView();
  }
}

@Entry
@Component
export struct FilterPage {
  @State ready: boolean = false;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State rows: FilterDisplayRow[] = [];
  @State addSheetOpen: boolean = false;
  @State tipDialogOpen: boolean = false;
  @State pendingDelete: FilterDisplayRow | null = null;
  @State selectedMode: number = FILTER_MODE_TITLE;
  @State inputText: string = '';
  @State inputHasEmptyError: boolean = false;
  @State saving: boolean = false;

  private readonly activityState: FilterActivityState = new FilterActivityState();
  private adapter: FilterPageAdapter | null = null;

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.adapter = new FilterPageAdapter(
      new EhDbFilterPersistencePort(),
      new FilterActivityStateBridge(this.activityState)
    );
    this.initializeAndLoad().catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'FilterPage initialize failed: %{public}s', msg);
      this.loadError = msg;
      this.loading = false;
      this.ready = true;
    });
  }

  onBackPress(): boolean {
    if (this.pendingDelete !== null) {
      this.pendingDelete = null;
      return true;
    }
    if (this.tipDialogOpen) {
      this.tipDialogOpen = false;
      return true;
    }
    if (this.addSheetOpen) {
      this.addSheetOpen = false;
      return true;
    }
    return false;
  }

  private async initializeAndLoad(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    await AppWiring.whenReady();
    this.ready = true;
    await this.reloadFilters();
  }

  private async reloadFilters(): Promise<void> {
    const current: FilterPageAdapter | null = this.adapter;
    if (current === null) {
      this.loading = false;
      return;
    }
    try {
      this.rows = await current.load();
      this.loadError = '';
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load filters: %{public}s', msg);
      this.loadError = msg;
    } finally {
      this.loading = false;
    }
  }

  private navigateBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Router back failed: %{public}s', JSON.stringify(err));
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Toast failed: %{public}s', JSON.stringify(err));
    }
  }

  private headerLabelResource(headerResKey: string): Resource {
    if (headerResKey === 'filter_uploader') {
      return $r('app.string.filter_uploader');
    }
    if (headerResKey === 'filter_tag') {
      return $r('app.string.filter_tag');
    }
    if (headerResKey === 'filter_tag_namespace') {
      return $r('app.string.filter_tag_namespace');
    }
    return $r('app.string.filter_title');
  }

  private modeLabelResource(mode: number): Resource {
    if (mode === FILTER_MODE_UPLOADER) {
      return $r('app.string.filter_uploader');
    }
    if (mode === FILTER_MODE_TAG) {
      return $r('app.string.filter_tag');
    }
    if (mode === FILTER_MODE_TAG_NAMESPACE) {
      return $r('app.string.filter_tag_namespace');
    }
    return $r('app.string.filter_title');
  }

  private formatDeleteMessage(text: string): string {
    const formatted: string = GetText.getStringFormat('delete_filter', [text]);
    if (formatted.length > 0) {
      return formatted;
    }
    const raw: string = GetText.getString('delete_filter');
    return P3TextFormatter.formatString(raw, text);
  }

  private openAddSheet(): void {
    this.selectedMode = FILTER_MODE_TITLE;
    this.inputText = '';
    this.inputHasEmptyError = false;
    this.addSheetOpen = true;
  }

  private onConfirmAdd(): void {
    const current: FilterPageAdapter | null = this.adapter;
    if (this.saving || current === null) {
      return;
    }
    this.saving = true;
    current.addFilter(this.selectedMode, this.inputText).then((result: FilterOperationResult): void => {
      if (!result.ok) {
        this.inputHasEmptyError = result.errorResKey === 'text_is_empty';
        this.saving = false;
        return;
      }
      this.rows = current.buildDisplayRows();
      this.inputText = '';
      this.inputHasEmptyError = false;
      this.addSheetOpen = false;
      this.saving = false;
      this.showToast($r('app.string.filter_added'));
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'addFilter failed: %{public}s', msg);
      this.saving = false;
      this.showToast($r('app.string.error_write_failed'));
    });
  }

  private onToggleRow(row: FilterDisplayRow): void {
    const current: FilterPageAdapter | null = this.adapter;
    if (this.saving || current === null || !FilterPageAdapter.canTrigger(row)) {
      return;
    }
    this.saving = true;
    current.toggleFilter(row).then((toggled: boolean): void => {
      if (toggled) {
        this.rows = current.buildDisplayRows();
      }
      this.saving = false;
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'toggleFilter failed: %{public}s', msg);
      this.saving = false;
      this.showToast($r('app.string.error_write_failed'));
    });
  }

  private onConfirmDelete(): void {
    const current: FilterPageAdapter | null = this.adapter;
    const target: FilterDisplayRow | null = this.pendingDelete;
    if (this.saving || current === null || target === null) {
      return;
    }
    this.saving = true;
    current.deleteFilter(target).then((deleted: boolean): void => {
      if (deleted) {
        this.rows = current.buildDisplayRows();
      }
      this.pendingDelete = null;
      this.saving = false;
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'deleteFilter failed: %{public}s', msg);
      this.pendingDelete = null;
      this.saving = false;
      this.showToast($r('app.string.error_write_failed'));
    });
  }

  @Builder
  modeChip(mode: number): void {
    Button(this.modeLabelResource(mode))
      .type(ButtonType.Normal)
      .height(34)
      .fontSize(13)
      .borderRadius(17)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.selectedMode === mode ? $r('app.color.teal_500') : '#FFEEEEEE')
      .fontColor(this.selectedMode === mode ? '#FFFFFFFF' : '#DE000000')
      .onClick((): void => {
        this.selectedMode = mode;
      })
  }

  @Builder
  addFilterSheet(): void {
    Column({ space: 14 }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        Column() {
          this.modeChip(FILTER_MODE_TITLE)
        }.margin({ right: 8, bottom: 8 })

        Column() {
          this.modeChip(FILTER_MODE_UPLOADER)
        }.margin({ right: 8, bottom: 8 })

        Column() {
          this.modeChip(FILTER_MODE_TAG)
        }.margin({ right: 8, bottom: 8 })

        Column() {
          this.modeChip(FILTER_MODE_TAG_NAMESPACE)
        }.margin({ right: 8, bottom: 8 })
      }
      .width('100%')

      TextInput({ text: this.inputText, placeholder: $r('app.string.filter_text') })
        .type(InputType.Normal)
        .enterKeyType(EnterKeyType.Done)
        .maxLines(1)
        .fontColor('#DE000000')
        .width('100%')
        .onChange((value: string): void => {
          this.inputText = value;
          if (this.inputHasEmptyError && value.trim().length > 0) {
            this.inputHasEmptyError = false;
          }
        })
        .onSubmit((): void => {
          this.onConfirmAdd();
        })

      if (this.inputHasEmptyError) {
        Text($r('app.string.text_is_empty'))
          .fontSize(12)
          .fontColor($r('app.color.red_500'))
          .width('100%')
      }

      Row({ space: 12 }) {
        Blank()

        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .fontColor('#FF616161')
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.addSheetOpen = false;
          })

        Button($r('app.string.add'))
          .type(ButtonType.Normal)
          .fontColor('#FFFFFFFF')
          .backgroundColor($r('app.color.teal_500'))
          .borderRadius(6)
          .padding({ left: 18, right: 18, top: 8, bottom: 8 })
          .enabled(!this.saving)
          .onClick((): void => {
            this.onConfirmAdd();
          })
      }
      .width('100%')
      .padding({ top: 4, bottom: 8 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 16 })
  }

  @Builder
  tipModalOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.tipDialogOpen = false;
        })

      Column({ space: 14 }) {
        Text($r('app.string.filter'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#DE000000')
          .width('100%')

        Scroll() {
          Text($r('app.string.filter_tip'))
            .fontSize(14)
            .fontColor('#FF424242')
            .lineHeight(22)
            .width('100%')
        }
        .align(Alignment.TopStart)
        .constraintSize({ maxHeight: 320 })
        .width('100%')

        Row() {
          Blank()

          Button($r('app.string.ok'))
            .type(ButtonType.Normal)
            .fontColor($r('app.color.teal_500'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.tipDialogOpen = false;
            })
        }
        .width('100%')
      }
      .width('86%')
      .constraintSize({ maxWidth: 420 })
      .padding(20)
      .borderRadius(12)
      .backgroundColor('#FFFFFFFF')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  deleteConfirmOverlay(target: FilterDisplayRow): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.pendingDelete = null;
        })

      Column({ space: 16 }) {
        Text(this.formatDeleteMessage(target.text))
          .fontSize(15)
          .fontColor('#DE000000')
          .lineHeight(22)
          .width('100%')

        Row({ space: 8 }) {
          Blank()

          Button($r('app.string.cancel'))
            .type(ButtonType.Normal)
            .fontColor('#FF616161')
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.pendingDelete = null;
            })

          Button($r('app.string.delete'))
            .type(ButtonType.Normal)
            .fontColor($r('app.color.red_500'))
            .backgroundColor(Color.Transparent)
            .enabled(!this.saving)
            .onClick((): void => {
              this.onConfirmDelete();
            })
        }
        .width('100%')
      }
      .width('84%')
      .constraintSize({ maxWidth: 400 })
      .padding(20)
      .borderRadius(12)
      .backgroundColor('#FFFFFFFF')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
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

          Text($r('app.string.filter'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Button({ type: ButtonType.Normal }) {
            VInfoOutlineDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.tipDialogOpen = true;
          })

          Button({ type: ButtonType.Normal }) {
            VPlusDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.openAddSheet();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.teal_500'))

        if (this.loading) {
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
        } else if (this.loadError.length > 0 && this.rows.length === 0) {
          Column({ space: 12 }) {
            Text(this.loadError)
              .fontSize(14)
              .fontColor($r('app.color.red_500'))
              .textAlign(TextAlign.Center)

            Button($r('app.string.retry'))
              .type(ButtonType.Normal)
              .fontColor('#FFFFFFFF')
              .backgroundColor($r('app.color.teal_500'))
              .borderRadius(6)
              .padding({ left: 18, right: 18, top: 8, bottom: 8 })
              .onClick((): void => {
                this.initializeAndLoad().catch((err: Error): void => {
                  const msg: string = err.message !== undefined ? err.message : String(err);
                  hilog.error(LOG_DOMAIN, LOG_TAG, 'FilterPage retry failed: %{public}s', msg);
                  this.loadError = msg;
                });
              })
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.rows.length === 0) {
          Column({ space: 16 }) {
            BigFilter({ iconSize: 96, fillColor: '#1F000000' })

            Text($r('app.string.no_filter'))
              .fontSize(15)
              .fontColor('#8A000000')
              .textAlign(TextAlign.Center)
              .width(240)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List() {
            ForEach(this.rows, (row: FilterDisplayRow) => {
              ListItem() {
                if (row.isHeader) {
                  Row() {
                    Text(this.headerLabelResource(row.headerResKey))
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.teal_500'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 14, bottom: 6 })
                  .backgroundColor($r('app.color.start_window_background'))
                } else {
                  Column() {
                    Row({ space: 4 }) {
                      Button({ type: ButtonType.Normal }) {
                        VDeleteX24({ iconSize: 22, fillColor: '#FF757575' })
                      }
                      .width(48)
                      .height(48)
                      .backgroundColor(Color.Transparent)
                      .onClick((): void => {
                        if (FilterPageAdapter.canDelete(row)) {
                          this.pendingDelete = row;
                        }
                      })

                      Text(row.text)
                        .fontSize(16)
                        .fontColor(row.enabled ? '#DE000000' : '#FF9E9E9E')
                        .decoration({
                          type: row.enabled ? TextDecorationType.None : TextDecorationType.LineThrough
                        })
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .padding({ left: 8, right: 16, top: 12, bottom: 12 })
                        .onClick((): void => {
                          this.onToggleRow(row);
                        })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                    .backgroundColor('#FFFFFFFF')

                    Divider()
                      .strokeWidth(1)
                      .color('#14000000')
                      .width('100%')
                  }
                  .width('100%')
                }
              }
            }, (row: FilterDisplayRow) => row.rowKey)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.start_window_background'))
      .bindSheet($$this.addSheetOpen, this.addFilterSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        title: {
          title: $r('app.string.add_filter')
        }
      })

      if (this.tipDialogOpen) {
        this.tipModalOverlay()
      }

      if (this.pendingDelete !== null) {
        this.deleteConfirmOverlay(this.pendingDelete)
      }
    }
    .width('100%')
    .height('100%')
  }
}
