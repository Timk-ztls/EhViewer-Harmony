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
 * Phase B Track P3: BlackListPage (@Entry @Component V1, PageRoutes.BLACK_LIST).
 *
 * Mirrors upstream BlackListActivity: awaits AppWiring.whenReady(), loads comment
 * blacklist entries from EhDB, renders toolbar (back + title + help tip + add),
 * empty state (no_blicklist), list showing badgayname + angrywith/reason metadata,
 * delete confirmation dialog, add sheet with validation + deduplication, and tip dialog.
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { GetText } from '../hippo/ehviewer/GetText';
import { BlackListActivityState, BlackListItem } from '../hippo/ehviewer/ui/BlackListActivity';
import { BigFilter } from '../hippo/ui/drawable/big_filter';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VDeleteX24 } from '../hippo/ui/drawable/v_delete_x24';
import { VInfoOutlineDarkX24 } from '../hippo/ui/drawable/v_info_outline_dark_x24';
import { VPlusDarkX24 } from '../hippo/ui/drawable/v_plus_dark_x24';
import {
  BlackListOperationResult,
  BlackListPageAdapter,
  BlackListRecord,
  BlackListStatePort,
  EhDbBlackListPersistencePort,
  P3TextFormatter
} from '../hippo/ui/p3/P3PageAdapters';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'BlackListPage';

class BlackListActivityStateBridge implements BlackListStatePort {
  private readonly state: BlackListActivityState;

  constructor(state: BlackListActivityState) {
    this.state = state;
  }

  syncFromRecords(records: BlackListRecord[]): void {
    const next: BlackListItem[] = [];
    for (let i = 0; i < records.length; i++) {
      const r: BlackListRecord = records[i];
      const item: BlackListItem = new BlackListItem();
      item.badgayname = r.badgayname;
      item.angrywith = r.angrywith;
      item.mode = r.mode;
      next.push(item);
    }
    this.state.items = next;
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
struct BlackListPage {
  @State ready: boolean = false;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State records: BlackListRecord[] = [];
  @State addSheetOpen: boolean = false;
  @State tipDialogOpen: boolean = false;
  @State pendingDelete: BlackListRecord | null = null;
  @State inputName: string = '';
  @State inputReason: string = '';
  @State inputHasEmptyError: boolean = false;
  @State saving: boolean = false;

  private readonly activityState: BlackListActivityState = new BlackListActivityState();
  private adapter: BlackListPageAdapter | null = null;

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.adapter = new BlackListPageAdapter(
      new EhDbBlackListPersistencePort(),
      new BlackListActivityStateBridge(this.activityState)
    );
    this.initializeAndLoad().catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'BlackListPage initialize failed: %{public}s', msg);
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
    await this.reloadBlackList();
  }

  private async reloadBlackList(): Promise<void> {
    const current: BlackListPageAdapter | null = this.adapter;
    if (current === null) {
      this.loading = false;
      return;
    }
    try {
      this.records = await current.load();
      this.loadError = '';
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to load blacklist: %{public}s', msg);
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

  private formatDeleteMessage(name: string): string {
    const formatted: string = GetText.getStringFormat('delete_blacklist', [name]);
    if (formatted.length > 0) {
      return formatted;
    }
    const raw: string = GetText.getString('delete_blacklist');
    return P3TextFormatter.formatString(raw, name);
  }

  private formatSubtitle(record: BlackListRecord): string {
    const parts: string[] = [];
    if (record.angrywith.length > 0) {
      parts.push(record.angrywith);
    }
    if (record.reason.length > 0) {
      parts.push(record.reason);
    }
    if (record.addTime.length > 0) {
      parts.push(record.addTime);
    }
    return parts.join(' · ');
  }

  private openAddSheet(): void {
    this.inputName = '';
    this.inputReason = '';
    this.inputHasEmptyError = false;
    this.addSheetOpen = true;
  }

  private onConfirmAdd(): void {
    const current: BlackListPageAdapter | null = this.adapter;
    if (this.saving || current === null) {
      return;
    }
    this.saving = true;
    current.addItem(this.inputName, this.inputReason, Date.now()).then((result: BlackListOperationResult): void => {
      if (!result.ok) {
        if (result.duplicate) {
          this.addSheetOpen = false;
          this.saving = false;
          this.showToast($r('app.string.blacklist'));
          return;
        }
        this.inputHasEmptyError = result.errorResKey === 'text_is_empty';
        this.saving = false;
        return;
      }
      this.records = current.getRecords();
      this.inputName = '';
      this.inputReason = '';
      this.inputHasEmptyError = false;
      this.addSheetOpen = false;
      this.saving = false;
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'addItem failed: %{public}s', msg);
      this.saving = false;
      this.showToast($r('app.string.error_write_failed'));
    });
  }

  private onConfirmDelete(): void {
    const current: BlackListPageAdapter | null = this.adapter;
    const target: BlackListRecord | null = this.pendingDelete;
    if (this.saving || current === null || target === null) {
      return;
    }
    this.saving = true;
    current.deleteItem(target).then((deleted: boolean): void => {
      if (deleted) {
        this.records = current.getRecords();
      }
      this.pendingDelete = null;
      this.saving = false;
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'deleteItem failed: %{public}s', msg);
      this.pendingDelete = null;
      this.saving = false;
      this.showToast($r('app.string.error_write_failed'));
    });
  }

  @Builder
  addBlackListSheet(): void {
    Column({ space: 14 }) {
      Text($r('app.string.blacklist_id'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.teal_500'))
        .width('100%')

      TextInput({ text: this.inputName, placeholder: $r('app.string.blacklist_text') })
        .type(InputType.Normal)
        .enterKeyType(EnterKeyType.Next)
        .maxLines(1)
        .fontColor('#DE000000')
        .width('100%')
        .onChange((value: string): void => {
          this.inputName = value;
          if (this.inputHasEmptyError && value.trim().length > 0) {
            this.inputHasEmptyError = false;
          }
        })

      TextInput({ text: this.inputReason, placeholder: $r('app.string.blacklist_reason_text') })
        .type(InputType.Normal)
        .enterKeyType(EnterKeyType.Done)
        .maxLines(1)
        .fontColor('#DE000000')
        .width('100%')
        .onChange((value: string): void => {
          this.inputReason = value;
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
        Text($r('app.string.blacklist'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#DE000000')
          .width('100%')

        Scroll() {
          Text($r('app.string.blacklist_tip'))
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
  deleteConfirmOverlay(target: BlackListRecord): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.pendingDelete = null;
        })

      Column({ space: 16 }) {
        Text(this.formatDeleteMessage(target.badgayname))
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

          Text($r('app.string.blacklist'))
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
        } else if (this.loadError.length > 0 && this.records.length === 0) {
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
                  hilog.error(LOG_DOMAIN, LOG_TAG, 'BlackListPage retry failed: %{public}s', msg);
                  this.loadError = msg;
                });
              })
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.records.length === 0) {
          Column({ space: 16 }) {
            BigFilter({ iconSize: 96, fillColor: '#1F000000' })

            // Upstream key name intentionally spelled `no_blicklist`
            Text($r('app.string.no_blicklist'))
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
            ListItem() {
              Row() {
                Text($r('app.string.blacklist_id'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.teal_500'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 6 })
              .backgroundColor($r('app.color.start_window_background'))
            }

            ForEach(this.records, (record: BlackListRecord) => {
              ListItem() {
                Column() {
                  Row({ space: 4 }) {
                    Button({ type: ButtonType.Normal }) {
                      VDeleteX24({ iconSize: 22, fillColor: '#FF757575' })
                    }
                    .width(48)
                    .height(48)
                    .backgroundColor(Color.Transparent)
                    .onClick((): void => {
                      this.pendingDelete = record;
                    })

                    Column({ space: 4 }) {
                      Text(record.badgayname)
                        .fontSize(16)
                        .fontColor('#DE000000')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')

                      if (this.formatSubtitle(record).length > 0) {
                        Text(this.formatSubtitle(record))
                          .fontSize(12)
                          .fontColor('#FF757575')
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                      }
                    }
                    .layoutWeight(1)
                    .padding({ left: 8, right: 16, top: 10, bottom: 10 })
                    .alignItems(HorizontalAlign.Start)
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
            }, (record: BlackListRecord) => record.rowKey)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.start_window_background'))
      .bindSheet($$this.addSheetOpen, this.addBlackListSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        title: {
          title: $r('app.string.add_blacklist')
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
