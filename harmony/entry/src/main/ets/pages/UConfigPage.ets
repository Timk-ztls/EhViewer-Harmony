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
 * Phase B Track P3: UConfigPage (@Entry @Component V1, PageRoutes.U_CONFIG).
 *
 * Mirrors upstream UConfigActivity: awaits AppWiring.whenReady(), seeds App cookies
 * from AppWiring.getCookieStore() into ArkWeb before loading EhUrl.getUConfigUrl(),
 * syncs updated cookies (uconfig/sk/igneous/ipb_member_id/ipb_pass_hash) back into
 * EhCookieStore on onPageEnd and aboutToDisappear, respects webController.accessBackward()
 * before router.back(), and provides toolbar apply/refresh + progress + error retry.
 */

import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { Settings } from '../hippo/ehviewer/Settings';
import { EhCookieStore } from '../hippo/ehviewer/client/EhCookieStore';
import { WebViewUnavailableSpec } from '../hippo/ehviewer/ui/MyTagsActivity';
import { syncAppShowJpnTitleStorage } from '../hippo/ui/ThemeSystemBar';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VCheckDarkX24 } from '../hippo/ui/drawable/v_check_dark_x24';
import { VRefreshDarkX24 } from '../hippo/ui/drawable/v_refresh_dark_x24';
import {
  UConfigBackAction,
  UConfigCookieSyncResult,
  UConfigPageCoordinator,
  UConfigPageListener,
  WebCookieBackendPort
} from '../hippo/ui/p3/P3PageAdapters';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'UConfigPage';

class UConfigArkWebCookieBackend implements WebCookieBackendPort {
  saveCookieSync(): void {
    webview.WebCookieManager.saveCookieSync();
  }

  clearAllCookiesSync(): void {
    webview.WebCookieManager.clearAllCookiesSync();
  }

  clearSessionCookieSync(): void {
    webview.WebCookieManager.clearSessionCookieSync();
  }

  putAcceptCookieEnabled(accept: boolean): void {
    webview.WebCookieManager.putAcceptCookieEnabled(accept);
  }

  putAcceptThirdPartyCookieEnabled(accept: boolean): void {
    webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(accept);
  }

  configCookieSync(url: string, value: string): void {
    webview.WebCookieManager.configCookieSync(url, value);
  }

  fetchCookieSync(url: string): string {
    return webview.WebCookieManager.fetchCookieSync(url);
  }
}

class UConfigPageListenerImpl implements UConfigPageListener {
  private readonly onLoadFn: (url: string) => void;
  private readonly onProgressVisFn: (visible: boolean) => void;
  private readonly onProgressValFn: (progress: number) => void;
  private readonly onLoadedFn: (loaded: boolean) => void;
  private readonly onErrorFn: (error: string) => void;
  private readonly onUnavailableFn: (spec: WebViewUnavailableSpec) => void;
  private readonly onFinishFn: () => void;

  constructor(
    onLoadFn: (url: string) => void,
    onProgressVisFn: (visible: boolean) => void,
    onProgressValFn: (progress: number) => void,
    onLoadedFn: (loaded: boolean) => void,
    onErrorFn: (error: string) => void,
    onUnavailableFn: (spec: WebViewUnavailableSpec) => void,
    onFinishFn: () => void
  ) {
    this.onLoadFn = onLoadFn;
    this.onProgressVisFn = onProgressVisFn;
    this.onProgressValFn = onProgressValFn;
    this.onLoadedFn = onLoadedFn;
    this.onErrorFn = onErrorFn;
    this.onUnavailableFn = onUnavailableFn;
    this.onFinishFn = onFinishFn;
  }

  onLoadUrl(url: string): void {
    this.onLoadFn(url);
  }

  onProgressVisibleChanged(visible: boolean): void {
    this.onProgressVisFn(visible);
  }

  onProgressValueChanged(progress: number): void {
    this.onProgressValFn(progress);
  }

  onLoadedChanged(loaded: boolean): void {
    this.onLoadedFn(loaded);
  }

  onErrorChanged(error: string): void {
    this.onErrorFn(error);
  }

  onShowUnavailableDialog(spec: WebViewUnavailableSpec): void {
    this.onUnavailableFn(spec);
  }

  onFinish(): void {
    this.onFinishFn();
  }
}

@Entry
@Component
struct UConfigPage {
  @State ready: boolean = false;
  @State targetUrl: string = '';
  @State progressVisible: boolean = false;
  @State loadProgress: number = 0;
  @State loaded: boolean = false;
  @State errorMessage: string = '';
  @State unavailableVisible: boolean = false;
  @State jsDialogVisible: boolean = false;
  @State jsDialogMessage: string = '';
  @State jsDialogIsConfirm: boolean = false;

  private webController: webview.WebviewController = new webview.WebviewController();
  private coordinator: UConfigPageCoordinator | null = null;
  private activeJsResult: JsResult | null = null;
  private applyTipShown: boolean = false;

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  aboutToAppear(): void {
    this.initializePage().catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'UConfigPage init failed: %{public}s', msg);
      this.unavailableVisible = true;
      this.ready = true;
    });
  }

  aboutToDisappear(): void {
    this.dismissPendingJsDialog();
    if (this.coordinator !== null) {
      const res: UConfigCookieSyncResult = this.coordinator.onDestroy();
      if (res.syncedShowJpnTitle !== null) {
        syncAppShowJpnTitleStorage(res.syncedShowJpnTitle);
      } else {
        syncAppShowJpnTitleStorage(Settings.getShowJpnTitle());
      }
    }
    this.stopWebSafely();
  }

  onBackPress(): boolean {
    if (this.jsDialogVisible) {
      this.onJsDialogCancel();
      return true;
    }
    if (this.unavailableVisible) {
      this.onUnavailableCancel();
      return true;
    }
    return this.handleBackAction();
  }

  private async initializePage(): Promise<void> {
    await AppWiring.whenReady();
    const store: EhCookieStore | null = AppWiring.getCookieStore();
    const listener: UConfigPageListener = new UConfigPageListenerImpl(
      (url: string): void => {
        this.targetUrl = url;
      },
      (visible: boolean): void => {
        this.progressVisible = visible;
      },
      (progress: number): void => {
        this.loadProgress = progress;
      },
      (isLoaded: boolean): void => {
        this.loaded = isLoaded;
      },
      (error: string): void => {
        this.errorMessage = error;
      },
      (_spec: WebViewUnavailableSpec): void => {
        this.unavailableVisible = true;
      },
      (): void => {
        this.navigateBack();
      }
    );
    const coord: UConfigPageCoordinator = new UConfigPageCoordinator(
      new UConfigArkWebCookieBackend(),
      store,
      listener
    );
    this.coordinator = coord;
    coord.init();
    this.ready = true;
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
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Toast failed: %{public}s', JSON.stringify(err));
    }
  }

  private stopWebSafely(): void {
    try {
      this.webController.stop();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'WebviewController.stop failed: %{public}s', JSON.stringify(err));
    }
  }

  private safeCanGoBack(): boolean {
    if (this.unavailableVisible || this.targetUrl.length === 0) {
      return false;
    }
    try {
      return this.webController.accessBackward();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'webController.accessBackward failed: %{public}s', msg);
      return false;
    }
  }

  private handleBackAction(): boolean {
    const canGoBack: boolean = this.safeCanGoBack();
    const coord: UConfigPageCoordinator | null = this.coordinator;
    const action: UConfigBackAction = coord !== null
      ? coord.handleBack(canGoBack)
      : (canGoBack ? UConfigBackAction.WEB_GO_BACK : UConfigBackAction.EXIT_PAGE);

    if (action === UConfigBackAction.WEB_GO_BACK) {
      try {
        this.webController.backward();
        return true;
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'webController.backward failed: %{public}s', msg);
      }
    }
    syncAppShowJpnTitleStorage(Settings.getShowJpnTitle());
    this.navigateBack();
    return true;
  }

  private onRefreshClick(): void {
    if (this.unavailableVisible || this.targetUrl.length === 0) {
      return;
    }
    if (this.coordinator !== null) {
      this.coordinator.onRefresh();
    }
    try {
      this.webController.refresh();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      if (this.coordinator !== null) {
        this.coordinator.onLoadError(msg);
      } else {
        this.errorMessage = msg;
      }
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'webController.refresh failed: %{public}s', msg);
    }
  }

  private onApplyClick(): void {
    if (!this.loaded || this.unavailableVisible) {
      return;
    }
    this.webController.runJavaScript(UConfigPageCoordinator.APPLY_JS).then((_res: string): void => {
      if (this.coordinator !== null) {
        const res: UConfigCookieSyncResult = this.coordinator.syncCookiesToStore();
        syncAppShowJpnTitleStorage(res.syncedShowJpnTitle !== null ? res.syncedShowJpnTitle : Settings.getShowJpnTitle());
      }
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'UConfig APPLY_JS failed: %{public}s', msg);
      this.errorMessage = msg;
    });
  }

  private onUnavailableConfirm(): void {
    this.unavailableVisible = false;
    if (this.coordinator !== null) {
      this.coordinator.onUnavailableDialogConfirm();
    } else {
      this.navigateBack();
    }
  }

  private onUnavailableCancel(): void {
    this.unavailableVisible = false;
    if (this.coordinator !== null) {
      this.coordinator.onUnavailableDialogCancel();
    } else {
      this.navigateBack();
    }
  }

  private dismissPendingJsDialog(): void {
    if (this.activeJsResult !== null) {
      try {
        this.activeJsResult.handleCancel();
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'JsResult.handleCancel failed: %{public}s', msg);
      }
      this.activeJsResult = null;
    }
    this.jsDialogVisible = false;
  }

  private onJsDialogConfirm(): void {
    const res: JsResult | null = this.activeJsResult;
    this.activeJsResult = null;
    this.jsDialogVisible = false;
    if (res !== null) {
      try {
        res.handleConfirm();
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'JsResult.handleConfirm failed: %{public}s', msg);
      }
    }
  }

  private onJsDialogCancel(): void {
    const res: JsResult | null = this.activeJsResult;
    this.activeJsResult = null;
    this.jsDialogVisible = false;
    if (res !== null) {
      try {
        res.handleCancel();
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'JsResult.handleCancel failed: %{public}s', msg);
      }
    }
  }

  @Builder
  unavailableModalOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.onUnavailableCancel();
        })

      Column({ space: 14 }) {
        Text($r('app.string.webview_unavailable_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#DE000000')
          .width('100%')

        Text($r('app.string.webview_unavailable_message'))
          .fontSize(14)
          .fontColor('#FF424242')
          .lineHeight(20)
          .width('100%')

        Row() {
          Blank()

          Button($r('app.string.ok'))
            .type(ButtonType.Normal)
            .fontColor($r('app.color.teal_500'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.onUnavailableConfirm();
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
  jsDialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.onJsDialogCancel();
        })

      Column({ space: 16 }) {
        Text(this.jsDialogMessage)
          .fontSize(15)
          .fontColor('#DE000000')
          .lineHeight(22)
          .width('100%')

        Row({ space: 8 }) {
          Blank()

          if (this.jsDialogIsConfirm) {
            Button($r('app.string.cancel'))
              .type(ButtonType.Normal)
              .fontColor('#FF616161')
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.onJsDialogCancel();
              })
          }

          Button($r('app.string.ok'))
            .type(ButtonType.Normal)
            .fontColor($r('app.color.teal_500'))
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.onJsDialogConfirm();
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
            this.handleBackAction();
          })

          Text($r('app.string.settings_u_config'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.loaded && !this.unavailableVisible) {
            Button({ type: ButtonType.Normal }) {
              VCheckDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
            }
            .width(44)
            .height(44)
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.onApplyClick();
            })
          }

          Button({ type: ButtonType.Normal }) {
            VRefreshDarkX24({ iconSize: 22, fillColor: this.palette().toolbarIconColor })
          }
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.onRefreshClick();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })
        .backgroundColor($r('app.color.teal_500'))

        if (this.progressVisible || (this.loadProgress > 0 && this.loadProgress < 100)) {
          Progress({ value: this.loadProgress > 0 ? this.loadProgress : 10, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(3)
            .color($r('app.color.colorAccent'))
        }

        if (this.errorMessage.length > 0) {
          Row({ space: 8 }) {
            Text(this.errorMessage)
              .fontSize(12)
              .fontColor($r('app.color.red_500'))
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Button($r('app.string.retry'))
              .height(30)
              .fontSize(12)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.teal_500'))
              .onClick((): void => {
                this.onRefreshClick();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#FFFFEBEE')
        }

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
        } else if (this.targetUrl.length > 0 && !this.unavailableVisible) {
          Web({ src: this.targetUrl, controller: this.webController })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .zoomAccess(true)
            .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
              const reqUrl: string = event.data.getRequestUrl();
              if (this.coordinator !== null) {
                return this.coordinator.shouldOverrideUrlLoading(reqUrl);
              }
              return false;
            })
            .onPageBegin((_event: OnPageBeginEvent): void => {
              if (this.coordinator !== null) {
                this.coordinator.onPageStarted();
              }
            })
            .onProgressChange((event: OnProgressChangeEvent): void => {
              if (this.coordinator !== null) {
                this.coordinator.onProgressChanged(event.newProgress);
              } else {
                this.loadProgress = event.newProgress;
              }
            })
            .onPageEnd((_event: OnPageEndEvent): void => {
              if (this.coordinator !== null) {
                const res: UConfigCookieSyncResult = this.coordinator.onPageFinished();
                if (res.syncedShowJpnTitle !== null) {
                  syncAppShowJpnTitleStorage(res.syncedShowJpnTitle);
                }
              }
              if (!this.applyTipShown) {
                this.applyTipShown = true;
                this.showToast($r('app.string.apply_tip'));
              }
            })
            .onAlert((event: OnAlertEvent): boolean => {
              this.activeJsResult = event.result;
              this.jsDialogMessage = event.message;
              this.jsDialogIsConfirm = false;
              this.jsDialogVisible = true;
              return true;
            })
            .onConfirm((event: OnConfirmEvent): boolean => {
              this.activeJsResult = event.result;
              this.jsDialogMessage = event.message;
              this.jsDialogIsConfirm = true;
              this.jsDialogVisible = true;
              return true;
            })
            .onErrorReceive((event: OnErrorReceiveEvent): void => {
              const errInfo: string = event.error.getErrorInfo();
              const errCode: number = event.error.getErrorCode();
              const desc: string = `${errInfo} (${errCode})`;
              if (this.coordinator !== null) {
                this.coordinator.onLoadError(desc);
              } else {
                this.errorMessage = desc;
              }
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'UConfig Web onErrorReceive: code=%{public}d info=%{public}s url=%{public}s',
                errCode, errInfo, event.request.getRequestUrl());
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
              const code: number = event.response.getResponseCode();
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'UConfig Web onHttpErrorReceive: code=%{public}d url=%{public}s',
                code, event.request.getRequestUrl());
              if (event.request.isMainFrame()) {
                const desc: string = `HTTP ${code}`;
                if (this.coordinator !== null) {
                  this.coordinator.onLoadError(desc);
                } else {
                  this.errorMessage = desc;
                }
              }
            })
            .width('100%')
            .layoutWeight(1)
        } else {
          Column()
            .width('100%')
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.start_window_background'))

      if (this.jsDialogVisible) {
        this.jsDialogOverlay()
      }

      if (this.unavailableVisible) {
        this.unavailableModalOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
