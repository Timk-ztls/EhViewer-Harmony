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
 * Stage B Track P4 — Same-LAN HTTP Transfer Server Page (DEVIATIONS.md D-002).
 *
 * Starts a local HTTP/1.1 service on the device's existing Wi-Fi LAN (`0.0.0.0:54321`),
 * renders the LAN address + built-in ArkUI `QRCode`, allows copying the URL, inspecting
 * available migration categories, and monitoring active connections & transfer logs.
 * Strictly zero hotspot / SoftAP / Wi-Fi scan APIs.
 */

import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { AppConfig } from '../hippo/ehviewer/AppConfig';
import { GetText } from '../hippo/ehviewer/GetText';
import { Settings } from '../hippo/ehviewer/Settings';
import {
  StatusButtonState,
  WiFiServerActivity,
  WiFiServerMenu
} from '../hippo/ehviewer/ui/wifi/WiFiServerActivity';
import { GalleryInfo } from '../hippo/ehviewer/client/data/GalleryInfo';
import { DownloadInfo } from '../hippo/ehviewer/dao/DownloadInfo';
import { QuickSearch } from '../hippo/ehviewer/dao/QuickSearch';
import { GalleryDirEntry } from '../hippo/ehviewer/client/wifi/MigrationTypes';
import { WiFiDownloadMigrationHelper } from '../hippo/ehviewer/client/wifi/WiFiDownloadMigrationHelper';
import {
  LanEndpointCodec,
  LanHttpTransferRouter,
  LanTextFormatter,
  LanTransferEvent
} from '../hippo/ehviewer/client/wifi/LanHttpProtocol';
import {
  LanNetworkHelper,
  LanNetworkInfo,
  LanStorageBridge,
  LanTcpHttpServer
} from '../hippo/ehviewer/client/wifi/LanSocketHttpRuntime';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'WiFiServerPage';
const MAX_LOG_ITEMS: number = 60;

class ServerLogItem {
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
export struct WiFiServerPage {
  @State ready: boolean = false;
  @State serverRunning: boolean = false;
  @State starting: boolean = false;
  @State localIp: string = '';
  @State localSsid: string = '';
  @State serverUrl: string = '';
  @State selectedCategory: number = WiFiServerMenu.BOOKMARK;
  @State activeClients: number = 0;
  @State totalRequests: number = 0;
  @State totalBytesSent: number = 0;
  @State bookmarkCount: number = 0;
  @State favoriteCount: number = 0;
  @State downloadCount: number = 0;
  @State downloadDirCount: number = 0;
  @State statusMessage: string = '';
  @State logs: ServerLogItem[] = [];

  private hostContext: common.Context | undefined = undefined;
  private readonly serverController: WiFiServerActivity = new WiFiServerActivity();
  private readonly storageBridge: LanStorageBridge = new LanStorageBridge();
  private tcpServer: LanTcpHttpServer | null = null;
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
    this.initializeServerPage(ctx).catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'initializeServerPage failed: %{public}s', err.message);
      this.statusMessage = this.str('wifi_server_connection_fail');
      this.ready = true;
    });
  }

  aboutToDisappear(): void {
    this.stopServer().catch((err: Error): void => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'stopServer on disappear failed: %{public}s', err.message);
    });
    this.serverController.destroy();
  }

  private async initializeServerPage(ctx: common.Context | undefined): Promise<void> {
    if (ctx !== undefined && !AppConfig.isInitialized()) {
      AppConfig.initialize(ctx);
    }
    if (AppWiring.isWired()) {
      await AppWiring.whenReady();
    } else if (ctx !== undefined && !Settings.isAttached()) {
      await Settings.attach(ctx);
    }

    const router: LanHttpTransferRouter = new LanHttpTransferRouter(
      this.storageBridge,
      this.storageBridge,
      this.storageBridge,
      (ev: LanTransferEvent): void => {
        this.onTransferEvent(ev);
      }
    );
    this.tcpServer = new LanTcpHttpServer(
      router,
      (count: number): void => {
        this.activeClients = count;
      },
      (errMsg: string): void => {
        this.appendLog(this.formatRes('wifi_server_send_fail', [errMsg]), true);
      }
    );

    await this.refreshLocalState();
    this.ready = true;
    await this.startServer();
  }

  private async refreshLocalState(): Promise<void> {
    const netInfo: LanNetworkInfo = await LanNetworkHelper.queryLocalLanInfo();
    this.localIp = netInfo.ipv4 !== null ? netInfo.ipv4 : '';
    this.localSsid = netInfo.ssid;
    this.serverUrl = this.localIp.length > 0
      ? LanEndpointCodec.buildServerUrl(this.localIp, WiFiServerActivity.PORT)
      : '';

    try {
      const bookmarks: QuickSearch[] = await this.storageBridge.getQuickSearches();
      const favorites: GalleryInfo[] = await this.storageBridge.getLocalFavorites();
      const downloads: DownloadInfo[] = await this.storageBridge.getDownloadInfos();
      const root: string | null = this.storageBridge.getDownloadRoot();
      const dirs: GalleryDirEntry[] = root !== null
        ? WiFiDownloadMigrationHelper.scanGalleryDirs(this.storageBridge, root)
        : [];
      this.bookmarkCount = bookmarks.length;
      this.favoriteCount = favorites.length;
      this.downloadCount = downloads.length;
      this.downloadDirCount = dirs.length;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'refreshLocalState counts failed: %{public}s', msg);
    }

    if (this.serverRunning) {
      this.updateRunningStatusText();
    } else if (this.localIp.length === 0) {
      this.statusMessage = this.str('wifi_server_connect_unable');
    } else {
      this.statusMessage = this.str('wifi_server_closed');
    }
  }

  private async startServer(): Promise<void> {
    if (this.starting || this.serverRunning || this.tcpServer === null) {
      return;
    }
    this.starting = true;
    try {
      await this.tcpServer.start(WiFiServerActivity.PORT);
      this.serverRunning = true;
      this.serverController.onItemSelected(this.selectedCategory);
      if (!this.serverController.isSending()) {
        this.serverController.onStatusChange();
      }
      this.updateRunningStatusText();
      this.appendLog(this.statusMessage, false);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'startServer failed: %{public}s', msg);
      this.serverRunning = false;
      this.statusMessage = this.str('wifi_server_connection_fail');
      this.appendLog(this.formatRes('wifi_server_send_fail', [msg]), true);
      this.showToast($r('app.string.wifi_server_connection_fail'));
    } finally {
      this.starting = false;
    }
  }

  private async stopServer(): Promise<void> {
    if (this.tcpServer !== null) {
      await this.tcpServer.stop();
    }
    this.serverController.stopMigration();
    this.serverRunning = false;
    this.activeClients = 0;
    this.statusMessage = this.str('wifi_server_closed');
    this.appendLog(this.statusMessage, false);
  }

  private toggleServer(): void {
    if (this.starting) {
      return;
    }
    if (this.serverRunning) {
      this.stopServer().catch((err: Error): void => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'toggle stopServer failed: %{public}s', err.message);
      });
    } else {
      this.refreshLocalState().then((): Promise<void> => this.startServer()).catch((err: Error): void => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'toggle startServer failed: %{public}s', err.message);
      });
    }
  }

  private onTransferEvent(ev: LanTransferEvent): void {
    this.totalRequests++;
    this.totalBytesSent += ev.bytes;
    const summary: string = `${ev.path} (${ev.detail}, ${ev.bytes}B)`;
    if (ev.statusCode >= 400) {
      this.appendLog(this.formatRes('wifi_server_send_fail', [summary]), true);
    } else {
      this.appendLog(this.formatRes('wifi_server_send_success', [summary]), false);
    }
  }

  private appendLog(text: string, isError: boolean): void {
    this.logSeq++;
    const item: ServerLogItem = new ServerLogItem(`srv-${this.logSeq}`, text, isError);
    const next: ServerLogItem[] = [item];
    const cap: number = Math.min(this.logs.length, MAX_LOG_ITEMS - 1);
    for (let i = 0; i < cap; i++) {
      next.push(this.logs[i]);
    }
    this.logs = next;
  }

  private updateRunningStatusText(): void {
    const ssidLabel: string = this.localSsid.length > 0 ? this.localSsid : this.str('wifi_server');
    const addrLabel: string = this.serverUrl.length > 0
      ? this.serverUrl
      : `0.0.0.0:${WiFiServerActivity.PORT}`;
    this.statusMessage = this.formatRes('wifi_server_opened', [ssidLabel, addrLabel]);
  }

  private copyServerUrl(): void {
    if (this.serverUrl.length === 0) {
      this.showToast($r('app.string.wifi_server_connect_unable'));
      return;
    }
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        this.serverUrl
      );
      board.setDataSync(data);
      this.showToast($r('app.string.copied_to_clipboard'));
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'copyServerUrl failed: %{public}s', msg);
      this.showToast($r('app.string.wifi_server_send_fail'));
    }
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

  private buildCategoryOptions(): SelectOption[] {
    const o0: SelectOption = { value: this.str('wifi_send_bookmark') };
    const o1: SelectOption = { value: this.str('wifi_send_favorite') };
    const o2: SelectOption = { value: this.str('wifi_send_download') };
    const o3: SelectOption = { value: this.str('wifi_send_download_location') };
    return [o0, o1, o2, o3];
  }

  private selectedCategoryLabel(): string {
    switch (this.selectedCategory) {
      case WiFiServerMenu.FAVORITE:
        return this.str('wifi_send_favorite');
      case WiFiServerMenu.DOWNLOAD:
        return this.str('wifi_send_download');
      case WiFiServerMenu.DOWNLOAD_DIR:
        return this.str('wifi_send_download_location');
      case WiFiServerMenu.BOOKMARK:
      default:
        return this.str('wifi_send_bookmark');
    }
  }

  private selectedCategoryCount(): number {
    switch (this.selectedCategory) {
      case WiFiServerMenu.FAVORITE:
        return this.favoriteCount;
      case WiFiServerMenu.DOWNLOAD:
        return this.downloadCount;
      case WiFiServerMenu.DOWNLOAD_DIR:
        return this.downloadDirCount;
      case WiFiServerMenu.BOOKMARK:
      default:
        return this.bookmarkCount;
    }
  }

  private statusButtonText(): string {
    const st: StatusButtonState = WiFiServerActivity.statusButtonState(this.serverRunning, this.activeClients);
    return this.formatRes(st.resKey, [st.suffix]);
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
  countRow(label: Resource, count: number): void {
    Row() {
      Text(label)
        .fontColor('#DE000000')
        .fontSize(14)
        .layoutWeight(1)

      Text(`${count}`)
        .fontColor($r('app.color.teal_500'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
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

        Text($r('app.string.wifi_server'))
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
            this.refreshLocalState().catch((err: Error): void => {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'refreshLocalState failed: %{public}s', err.message);
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
            // Instructions & live status card
            Column({ space: 8 }) {
              Text($r('app.string.wifi_server_illustrate'))
                .fontColor($r('app.color.colorPrimaryDark'))
                .fontSize(13)
                .width('100%')

              Text(this.statusMessage.length > 0 ? this.statusMessage : this.str('wifi_server_closed'))
                .fontColor(this.serverRunning ? $r('app.color.teal_700') : '#8A000000')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius(8)
            .backgroundColor($r('app.color.content_light'))

            // LAN HTTP address & QR Code card
            Column({ space: 12 }) {
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  Text($r('app.string.key_url'))
                    .fontColor('#8A000000')
                    .fontSize(12)
                    .width('100%')

                  Text(this.serverUrl.length > 0 ? this.serverUrl : this.str('wifi_server_connect_unable'))
                    .fontColor('#DE000000')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .width('100%')
                }
                .layoutWeight(1)

                Button($r('app.string.copy_tag'))
                  .type(ButtonType.Normal)
                  .fontSize(14)
                  .fontColor('#FFFFFFFF')
                  .backgroundColor($r('app.color.teal_500'))
                  .borderRadius(6)
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .enabled(this.serverUrl.length > 0)
                  .onClick(() => {
                    this.copyServerUrl();
                  })
              }
              .width('100%')

              if (this.serverRunning && this.serverUrl.length > 0) {
                Column() {
                  QRCode(this.serverUrl)
                    .width(180)
                    .height(180)
                    .color('#FF000000')
                    .backgroundColor('#FFFFFFFF')
                }
                .width('100%')
                .alignItems(HorizontalAlign.Center)
                .padding({ top: 6, bottom: 6 })
              }
            }
            .width('100%')
            .padding(14)
            .borderRadius(8)
            .backgroundColor($r('app.color.white'))

            // Category selector, data summary & start/stop control
            Column({ space: 10 }) {
              Row({ space: 10 }) {
                Select(this.buildCategoryOptions())
                  .selected(this.selectedCategory)
                  .value(this.selectedCategoryLabel())
                  .font({ size: 14 })
                  .selectedOptionFont({ size: 14 })
                  .optionFont({ size: 14 })
                  .layoutWeight(1)
                  .onSelect((index: number, _value: string): void => {
                    this.selectedCategory = index;
                    this.serverController.onItemSelected(index);
                  })

                Text(`${this.selectedCategoryCount()}`)
                  .fontColor($r('app.color.teal_500'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')

              this.countRow($r('app.string.wifi_send_bookmark'), this.bookmarkCount)
              this.countRow($r('app.string.wifi_send_favorite'), this.favoriteCount)
              this.countRow($r('app.string.wifi_send_download'), this.downloadCount)
              this.countRow($r('app.string.wifi_send_download_location'), this.downloadDirCount)

              Button(this.statusButtonText())
                .type(ButtonType.Normal)
                .width('100%')
                .height(44)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFFFF')
                .backgroundColor(this.serverRunning ? $r('app.color.red_500') : $r('app.color.teal_500'))
                .borderRadius(8)
                .enabled(!this.starting)
                .onClick(() => {
                  this.toggleServer();
                })
            }
            .width('100%')
            .padding(14)
            .borderRadius(8)
            .backgroundColor($r('app.color.content_light'))

            // Transfer status & request log panel
            Column({ space: 8 }) {
              Row() {
                Text($r('app.string.wifi_send_text'))
                  .fontColor('#DE000000')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                Text(`${this.totalRequests}`)
                  .fontColor($r('app.color.teal_500'))
                  .fontSize(13)
                  .margin({ right: 8 })

                Button($r('app.string.download_service_clear'))
                  .type(ButtonType.Normal)
                  .fontSize(13)
                  .fontColor($r('app.color.teal_500'))
                  .backgroundColor(Color.Transparent)
                  .onClick(() => {
                    this.logs = [];
                  })
              }
              .width('100%')

              if (this.logs.length === 0) {
                Text($r('app.string.empty_result'))
                  .fontColor('#8A000000')
                  .fontSize(13)
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
              } else {
                Column({ space: 6 }) {
                  ForEach(this.logs, (item: ServerLogItem) => {
                    Text(item.text)
                      .fontColor(item.isError ? $r('app.color.red_500') : '#DE000000')
                      .fontSize(12)
                      .width('100%')
                  }, (item: ServerLogItem) => item.id)
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
