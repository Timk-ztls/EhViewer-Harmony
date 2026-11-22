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

/**
 * Stage B Track P4 — Same-LAN HTTP Transfer Client Page (DEVIATIONS.md D-002).
 *
 * Connects to a peer `WiFiServerPage` on the same Wi-Fi LAN via manual IP:port input or
 * pasted QR/LAN URL text, inspects available data counts, pulls Bookmarks / Favorites /
 * Downloads / Download Directory over HTTP/1.1 with incremental MD5 diff + live progress +
 * cancellation, and persists locally to `EhDB` / `DownloadManager` / filesystem.
 * Strictly zero Wi-Fi scan / auto-connect / HMS ScanKit APIs.
 */

import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { AppConfig } from '../hippo/ehviewer/AppConfig';
import { GetText } from '../hippo/ehviewer/GetText';
import { Settings } from '../hippo/ehviewer/Settings';
import { WiFiServerMenu } from '../hippo/ehviewer/ui/wifi/WiFiServerActivity';
import {
  LanEndpoint,
  LanEndpointCodec,
  LanHttpTransferClient,
  LanPullProgress,
  LanPullSummary,
  LanServerInfo,
  LanTextFormatter
} from '../hippo/ehviewer/client/wifi/LanHttpProtocol';
import {
  LanHttpClientTransport,
  LanNetworkHelper,
  LanNetworkInfo,
  LanStorageBridge
} from '../hippo/ehviewer/client/wifi/LanSocketHttpRuntime';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'WiFiClientPage';
const MAX_LOG_ITEMS: number = 80;

class ClientLogItem {
  readonly id: string;
  readonly text: string;
  readonly isError: boolean;

  constructor(id: string, text: string, isError: boolean) {
    this.id = id;
    this.text = text;
    this.isError = isError;
  }
}

@Entry
@Component
export struct WiFiClientPage {
  @State ready: boolean = false;
  @State localIp: string = '';
  @State localSsid: string = '';
  @State serverInput: string = '';
  @State connecting: boolean = false;
  @State connected: boolean = false;
  @State connectedUrl: string = '';
  @State remoteBookmarks: number = 0;
  @State remoteFavorites: number = 0;
  @State remoteDownloads: number = 0;
  @State remoteDownloadDirs: number = 0;
  @State connectionStatusText: string = '';
  @State transferring: boolean = false;
  @State progressPercent: number = 0;
  @State progressStatusText: string = '';
  @State progressCounterText: string = '';
  @State receiveLogs: ClientLogItem[] = [];

  private hostContext: common.Context | undefined = undefined;
  private readonly storageBridge: LanStorageBridge = new LanStorageBridge();
  private readonly httpTransport: LanHttpClientTransport = new LanHttpClientTransport();
  private transferClient: LanHttpTransferClient | null = null;
  private logSeq: number = 0;

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    this.hostContext = ctx;
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.initializeClientPage(ctx).catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'initializeClientPage failed: %{public}s', err.message);
      this.connectionStatusText = this.str('wifi_server_connection_fail');
      this.ready = true;
    });
  }

  aboutToDisappear(): void {
    if (this.transferClient !== null) {
      this.transferClient.destroy();
    }
  }

  private async initializeClientPage(ctx: common.Context | undefined): Promise<void> {
    if (ctx !== undefined && !AppConfig.isInitialized()) {
      AppConfig.initialize(ctx);
    }
    if (AppWiring.isWired()) {
      await AppWiring.whenReady();
    } else if (ctx !== undefined && !Settings.isAttached()) {
      await Settings.attach(ctx);
    }

    this.transferClient = new LanHttpTransferClient(
      this.httpTransport,
      this.storageBridge,
      this.storageBridge,
      this.storageBridge,
      (): Promise<void> => this.storageBridge.flushPersistence()
    );

    await this.refreshLocalNetwork();
    this.ready = true;
  }

  private async refreshLocalNetwork(): Promise<void> {
    const info: LanNetworkInfo = await LanNetworkHelper.queryLocalLanInfo();
    this.localIp = info.ipv4 !== null ? info.ipv4 : '';
    this.localSsid = info.ssid;
  }

  private pasteFromClipboard(): void {
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = board.getDataSync();
      const primaryText: string = data.getPrimaryText();
      const text: string = primaryText !== undefined && primaryText !== null ? primaryText.trim() : '';
      if (text.length === 0) {
        this.showToast($r('app.string.error_invalid_url'));
        return;
      }
      const parsed: LanEndpoint | null = LanEndpointCodec.parseEndpoint(text);
      if (parsed !== null) {
        this.serverInput = parsed.baseUrl;
      } else {
        this.serverInput = text;
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'pasteFromClipboard failed: %{public}s', msg);
      this.showToast($r('app.string.error_invalid_url'));
    }
  }

  private onConnectClicked(): void {
    if (this.connecting || this.transferring || this.transferClient === null) {
      return;
    }
    const parsed: LanEndpoint | null = LanEndpointCodec.parseEndpoint(this.serverInput);
    if (parsed === null) {
      this.showToast($r('app.string.invalid_ip'));
      this.connectionStatusText = this.str('invalid_ip');
      return;
    }
    this.serverInput = parsed.baseUrl;
    this.connecting = true;
    this.connectionStatusText = this.str('loading');

    const client: LanHttpTransferClient = this.transferClient;
    client.connectAndInspect(parsed.baseUrl).then((info: LanServerInfo): void => {
      this.connected = true;
      this.connectedUrl = parsed.baseUrl;
      this.remoteBookmarks = info.bookmarkCount;
      this.remoteFavorites = info.favoriteCount;
      this.remoteDownloads = info.downloadCount;
      this.remoteDownloadDirs = info.downloadDirCount;
      this.connectionStatusText = this.str('wifi_server_connection_succeeded');
      this.appendLog(this.formatRes('wifi_server_receive_message', [parsed.baseUrl]), false);
      this.connecting = false;
    }).catch((err: Error): void => {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'connectAndInspect failed: %{public}s', msg);
      this.connected = false;
      this.connectedUrl = '';
      this.connectionStatusText = this.str('wifi_server_connection_fail');
      this.appendLog(this.formatRes('wifi_server_send_fail', [msg]), true);
      this.showToast($r('app.string.wifi_server_connection_fail'));
      this.connecting = false;
    });
  }

  private onPullCategory(menu: WiFiServerMenu): void {
    if (this.transferring || !this.connected || this.transferClient === null) {
      return;
    }
    this.transferring = true;
    this.progressPercent = 0;
    this.progressStatusText = this.str('wifi_sending');
    this.progressCounterText = '';

    const client: LanHttpTransferClient = this.transferClient;
    const onProgress = (prog: LanPullProgress): void => {
      this.applyProgress(prog);
    };

    let task: Promise<LanPullSummary>;
    switch (menu) {
      case WiFiServerMenu.BOOKMARK:
        task = client.pullBookmarks(onProgress);
        break;
      case WiFiServerMenu.FAVORITE:
        task = client.pullFavorites(onProgress);
        break;
      case WiFiServerMenu.DOWNLOAD:
        task = client.pullDownloads(onProgress);
        break;
      case WiFiServerMenu.DOWNLOAD_DIR:
      default:
        task = client.pullDownloadDirs(onProgress);
        break;
    }

    task.then((summary: LanPullSummary): void => {
      this.transferring = false;
      this.handlePullSummary(summary);
    }).catch((err: Error): void => {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'onPullCategory failed: %{public}s', msg);
      this.transferring = false;
      this.progressStatusText = this.str('wifi_server_connection_fail');
      this.appendLog(this.formatRes('wifi_server_send_fail', [msg]), true);
    });
  }

  private onCancelTransfer(): void {
    if (this.transferClient !== null) {
      this.transferClient.cancel();
    }
    this.transferring = false;
    this.progressStatusText = this.str('wifi_server_disconnect');
    this.appendLog(this.str('wifi_server_disconnect'), false);
  }

  private applyProgress(prog: LanPullProgress): void {
    if (prog.resKey.length > 0) {
      const formatted: string = this.formatRes(prog.resKey, prog.resArgs);
      this.progressStatusText = formatted;
      if (prog.phase === 'manifest' || prog.phase === 'file' || prog.phase === 'done') {
        this.appendLog(formatted, prog.resKey === 'wifi_download_dir_file_failed');
      }
    }
    if (prog.total > 0) {
      const pct: number = Math.min(100, Math.max(0, Math.round((prog.current * 100) / prog.total)));
      this.progressPercent = pct;
      this.progressCounterText = `${prog.current}/${prog.total}`;
    } else if (prog.phase === 'done') {
      this.progressPercent = 100;
    }
  }

  private handlePullSummary(summary: LanPullSummary): void {
    if (summary.cancelled) {
      this.progressStatusText = this.str('wifi_server_disconnect');
      this.appendLog(this.str('wifi_server_disconnect'), false);
      return;
    }
    if (summary.ok) {
      this.progressPercent = 100;
      const doneKey: string = summary.errorResKey.length > 0 ? summary.errorResKey : 'wifi_send_done';
      const doneText: string = this.str(doneKey);
      this.progressStatusText = doneText;
      const detail: string = summary.category === WiFiServerMenu.DOWNLOAD_DIR
        ? `${doneText} (${summary.dirsProcessed}/${summary.filesTransferred}/${summary.filesSkipped})`
        : `${doneText} (${summary.itemsImported})`;
      this.appendLog(this.formatRes('wifi_server_receive_message', [detail]), false);
      this.showToast(doneText);
    } else {
      const errKey: string = summary.errorResKey.length > 0
        ? summary.errorResKey
        : 'wifi_server_connection_fail';
      const errText: string = this.str(errKey);
      this.progressStatusText = errText;
      const detail: string = summary.errorMessage.length > 0
        ? `${errText}: ${summary.errorMessage}`
        : errText;
      this.appendLog(detail, true);
      this.showToast(errText);
    }
  }

  private appendLog(text: string, isError: boolean): void {
    this.logSeq++;
    const item: ClientLogItem = new ClientLogItem(`cli-${this.logSeq}`, text, isError);
    const next: ClientLogItem[] = [item];
    const cap: number = Math.min(this.receiveLogs.length, MAX_LOG_ITEMS - 1);
    for (let i = 0; i < cap; i++) {
      next.push(this.receiveLogs[i]);
    }
    this.receiveLogs = next;
  }

  private localStatusLine(): string {
    if (this.localIp.length === 0) {
      return this.str('wifi_server_connect_unable');
    }
    if (this.localSsid.length > 0) {
      return `${this.localSsid} / ${this.localIp}`;
    }
    return this.localIp;
  }

  private str(key: string): string {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        return ctx.resourceManager.getStringByNameSync(key);
      } catch (err) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'getStringByNameSync failed for %{public}s: %{public}s',
          key, JSON.stringify(err));
      }
    }
    return GetText.getString(key);
  }

  private formatRes(key: string, args: Array<string | number>): string {
    return LanTextFormatter.format(this.str(key), args);
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

  @Builder
  pullCategoryButton(label: Resource, count: number, menu: WiFiServerMenu): void {
    Row({ space: 10 }) {
      Text(label)
        .fontColor('#DE000000')
        .fontSize(14)
        .layoutWeight(1)

      Text(`${count}`)
        .fontColor($r('app.color.teal_700'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)

      Button($r('app.string.download'))
        .type(ButtonType.Normal)
        .fontSize(13)
        .fontColor('#FFFFFFFF')
        .backgroundColor($r('app.color.teal_500'))
        .borderRadius(6)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .enabled(!this.transferring)
        .onClick(() => {
          this.onPullCategory(menu);
        })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Column() {
      // Toolbar
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.navigateBack();
        })

        Text($r('app.string.wifi_client'))
          .fontColor('#FFFFFFFF')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)

        Button($r('app.string.refresh'))
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor('#FFFFFFFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.refreshLocalNetwork().catch((err: Error): void => {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'refreshLocalNetwork failed: %{public}s', err.message);
            });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 12 })
      .backgroundColor($r('app.color.teal_500'))

      if (!this.ready) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.teal_500'))

          Text($r('app.string.loading'))
            .fontColor('#8A000000')
            .fontSize(14)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            // Local Wi-Fi status card
            Column({ space: 4 }) {
              Text($r('app.string.hosts_ip'))
                .fontColor('#8A000000')
                .fontSize(12)
                .width('100%')

              Text(this.localStatusLine())
                .fontColor('#DE000000')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius(8)
            .backgroundColor($r('app.color.content_light'))

            // Server endpoint input + paste + connect card
            Column({ space: 10 }) {
              Text($r('app.string.proxy_host_or_ip'))
                .fontColor('#DE000000')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .width('100%')

              TextInput({
                text: this.serverInput,
                placeholder: $r('app.string.proxy_host_or_ip')
              })
                .width('100%')
                .height(44)
                .fontSize(15)
                .fontColor('#DE000000')
                .placeholderColor('#61000000')
                .backgroundColor($r('app.color.content_light'))
                .borderRadius(6)
                .padding({ left: 12, right: 12 })
                .enabled(!this.transferring)
                .onChange((val: string): void => {
                  this.serverInput = val;
                })

              Row({ space: 10 }) {
                Button($r('app.string.cookie_login_import_in_clipboard'))
                  .type(ButtonType.Normal)
                  .fontSize(13)
                  .fontColor($r('app.color.teal_500'))
                  .backgroundColor($r('app.color.content_light'))
                  .borderRadius(6)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .enabled(!this.transferring)
                  .onClick(() => {
                    this.pasteFromClipboard();
                  })

                Blank()

                Button($r('app.string.wifi_server_connect'))
                  .type(ButtonType.Normal)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFFFF')
                  .backgroundColor($r('app.color.teal_500'))
                  .borderRadius(6)
                  .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                  .enabled(!this.connecting && !this.transferring)
                  .onClick(() => {
                    this.onConnectClicked();
                  })
              }
              .width('100%')

              if (this.connectionStatusText.length > 0) {
                Text(this.connectionStatusText)
                  .fontColor(this.connected ? $r('app.color.teal_700') : $r('app.color.red_500'))
                  .fontSize(13)
                  .width('100%')
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(8)
            .backgroundColor($r('app.color.white'))

            // Connected server pull actions card
            if (this.connected) {
              Column({ space: 6 }) {
                Text(this.connectedUrl)
                  .fontColor($r('app.color.teal_700'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .width('100%')
                  .margin({ bottom: 4 })

                this.pullCategoryButton(
                  $r('app.string.wifi_send_bookmark'),
                  this.remoteBookmarks,
                  WiFiServerMenu.BOOKMARK
                )
                this.pullCategoryButton(
                  $r('app.string.wifi_send_favorite'),
                  this.remoteFavorites,
                  WiFiServerMenu.FAVORITE
                )
                this.pullCategoryButton(
                  $r('app.string.wifi_send_download'),
                  this.remoteDownloads,
                  WiFiServerMenu.DOWNLOAD
                )
                this.pullCategoryButton(
                  $r('app.string.wifi_send_download_location'),
                  this.remoteDownloadDirs,
                  WiFiServerMenu.DOWNLOAD_DIR
                )
              }
              .width('100%')
              .padding(14)
              .borderRadius(8)
              .backgroundColor($r('app.color.content_light'))
            }

            // Live progress & cancel card
            if (this.transferring || this.progressStatusText.length > 0) {
              Column({ space: 8 }) {
                Row() {
                  Text(this.progressStatusText)
                    .fontColor('#DE000000')
                    .fontSize(13)
                    .layoutWeight(1)

                  if (this.progressCounterText.length > 0) {
                    Text(this.progressCounterText)
                      .fontColor($r('app.color.teal_700'))
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                  }
                }
                .width('100%')

                Progress({ value: this.progressPercent, total: 100, type: ProgressType.Linear })
                  .width('100%')
                  .color($r('app.color.teal_500'))

                if (this.transferring) {
                  Button($r('app.string.cancel'))
                    .type(ButtonType.Normal)
                    .width('100%')
                    .height(40)
                    .fontSize(14)
                    .fontColor('#FFFFFFFF')
                    .backgroundColor($r('app.color.red_500'))
                    .borderRadius(6)
                    .onClick(() => {
                      this.onCancelTransfer();
                    })
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(8)
              .backgroundColor($r('app.color.white'))
            }

            // Transfer status log panel
            Column({ space: 8 }) {
              Row() {
                Text($r('app.string.wifi_send_text'))
                  .fontColor('#DE000000')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                Button($r('app.string.download_service_clear'))
                  .type(ButtonType.Normal)
                  .fontSize(13)
                  .fontColor($r('app.color.teal_500'))
                  .backgroundColor(Color.Transparent)
                  .onClick(() => {
                    this.receiveLogs = [];
                  })
              }
              .width('100%')

              if (this.receiveLogs.length === 0) {
                Text($r('app.string.empty_result'))
                  .fontColor('#8A000000')
                  .fontSize(13)
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
              } else {
                Column({ space: 6 }) {
                  ForEach(this.receiveLogs, (item: ClientLogItem) => {
                    Text(item.text)
                      .fontColor(item.isError ? $r('app.color.red_500') : '#DE000000')
                      .fontSize(12)
                      .width('100%')
                  }, (item: ClientLogItem) => item.id)
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(8)
            .backgroundColor($r('app.color.white'))
          }
          .width('100%')
          .padding(14)
        }
        .align(Alignment.TopStart)
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
