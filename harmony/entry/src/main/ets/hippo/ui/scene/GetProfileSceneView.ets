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
 * Phase B Track P1: GetProfileSceneView (@Component V1).
 *
 * Uses `@kit.ArkWeb` (`webview`) `Web` component loading `GetProfileScene.START_URL`.
 * Syncs existing app cookies into `WebCookieManager`, wires `onPageEnd` →
 * `GetProfileScene.planPageFinished(...)` → `controller.runJavaScript(READ_CONTENT_JS)` →
 * `GetProfileSceneShell.handlePageContent(...)`, and shows explicit loading/error states.
 */

import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppWiring } from '../../AppWiring';
import { EhCookieStore } from '../../ehviewer/client/EhCookieStore';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { HttpUrl } from '../../okhttp/HttpUrl';
import { Cookie } from '../../okhttp/Cookie';
import {
  GetProfileScene,
  PageFinishedAction,
  ProfileResult
} from '../../ehviewer/ui/scene/sign/GetProfileScene';
import { GetProfileSceneShell } from '../../ehviewer/ui/scene/sign/GetProfileSceneShell';
import { ArkWebProxyManager } from '../ArkWebProxyManager';

const DOMAIN: number = 0x0000;
const TAG: string = 'GetProfileSceneView';
const TEXT_PRIMARY: string = '#DE000000';

@Component
export struct GetProfileSceneView {
  shell: GetProfileSceneShell | null = null;

  @State webReady: boolean = false;
  @State initFailed: boolean = false;
  @State loading: boolean = true;
  @State loadProgress: number = 0;
  @State errorMessage: string = '';
  @State parseFailedTip: boolean = false;

  private webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.prepareWebView().catch((e: Error): void => {
      const msg: string = e.message !== undefined ? e.message : String(e);
      this.initFailed = true;
      this.loading = false;
      this.errorMessage = msg;
      hilog.error(DOMAIN, TAG, 'prepareWebView async failed: %{public}s', msg);
    });
  }

  private async prepareWebView(): Promise<void> {
    this.webReady = false;
    this.initFailed = false;
    this.loading = true;
    this.loadProgress = 0;
    this.errorMessage = '';
    this.parseFailedTip = false;

    await ArkWebProxyManager.syncFromSettings();
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
      this.syncStoreCookiesToWebView();
      this.webReady = true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.initFailed = true;
      this.loading = false;
      this.errorMessage = msg;
      hilog.error(DOMAIN, TAG, 'WebView/CookieManager init failed: %{public}s', msg);
      if (this.shell !== null) {
        this.shell.onInitFailed(msg);
      }
    }
  }

  private syncStoreCookiesToWebView(): void {
    const store: EhCookieStore | null = AppWiring.getCookieStore();
    if (store === null) {
      hilog.warn(DOMAIN, TAG, 'AppWiring.getCookieStore() is null; profile page may load unauthenticated');
      return;
    }
    const targetUrls: string[] = [GetProfileScene.START_URL, EhUrl.HOST_E];
    for (let u = 0; u < targetUrls.length; u++) {
      const urlStr: string = targetUrls[u];
      const httpUrl: HttpUrl | null = HttpUrl.parse(urlStr);
      if (httpUrl === null) {
        continue;
      }
      const cookies: Cookie[] = store.getCookies(httpUrl);
      for (let i = 0; i < cookies.length; i++) {
        const c: Cookie = cookies[i];
        try {
          webview.WebCookieManager.configCookieSync(urlStr, c.name() + '=' + c.value());
        } catch (e) {
          const msg: string = e instanceof Error ? e.message : String(e);
          hilog.warn(DOMAIN, TAG, 'configCookieSync failed for %{public}s: %{public}s', c.name(), msg);
        }
      }
    }
  }

  private handlePageEnd(url: string): void {
    this.loading = false;
    this.loadProgress = 100;
    const currentShell: GetProfileSceneShell | null = this.shell;
    if (currentShell === null) {
      hilog.warn(DOMAIN, TAG, 'onPageEnd with null shell: url=%{public}s', url);
      return;
    }
    const action: PageFinishedAction = currentShell.planPageFinished(url);
    if (action !== PageFinishedAction.READ_CONTENT) {
      return;
    }
    this.webController.runJavaScript(GetProfileScene.READ_CONTENT_JS).then((rawHtml: string): void => {
      const parsed: ProfileResult | null = currentShell.handlePageContent(rawHtml);
      if (parsed === null) {
        this.parseFailedTip = true;
      } else {
        this.parseFailedTip = false;
      }
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      this.errorMessage = msg;
      hilog.error(DOMAIN, TAG, 'runJavaScript(READ_CONTENT_JS) failed: %{public}s', msg);
    });
  }

  private onRetryClick(): void {
    this.errorMessage = '';
    this.parseFailedTip = false;
    this.loading = true;
    try {
      this.webController.loadUrl(GetProfileScene.START_URL);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.loading = false;
      this.errorMessage = msg;
      hilog.warn(DOMAIN, TAG, 'webController.loadUrl retry failed: %{public}s', msg);
    }
  }

  private onCancelClick(): void {
    if (this.shell !== null) {
      this.shell.cancelWithError(this.errorMessage.length > 0 ? this.errorMessage : 'user_canceled');
    }
  }

  private onDismissInitFailed(): void {
    if (this.shell !== null) {
      this.shell.onInitFailedDialogDismissed();
    }
  }

  build() {
    Column() {
      if (this.initFailed) {
        Column({ space: 16 }) {
          Text($r('app.string.webview_unavailable_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_PRIMARY)
            .textAlign(TextAlign.Center)

          Text($r('app.string.webview_unavailable_message'))
            .fontSize(14)
            .fontColor('#FF616161')
            .textAlign(TextAlign.Center)

          Button($r('app.string.ok'))
            .backgroundColor($r('app.color.colorPrimary'))
            .fontColor('#FFFFFFFF')
            .onClick((): void => {
              this.onDismissInitFailed();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .padding(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.webReady) {
        if (this.loading && this.loadProgress < 100) {
          Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(3)
            .color($r('app.color.colorAccent'))
        }

        if (this.errorMessage.length > 0 || this.parseFailedTip) {
          Row({ space: 8 }) {
            Text(this.errorMessage.length > 0 ? this.errorMessage : $r('app.string.error_empty_html'))
              .fontSize(12)
              .fontColor($r('app.color.red_500'))
              .layoutWeight(1)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Button($r('app.string.retry'))
              .height(30)
              .fontSize(12)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.colorPrimary'))
              .onClick((): void => {
                this.onRetryClick();
              })

            Button($r('app.string.cancel'))
              .height(30)
              .fontSize(12)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.colorAccent'))
              .onClick((): void => {
                this.onCancelClick();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#FFFFEBEE')
        }

        Stack({ alignContent: Alignment.Center }) {
          Web({ src: GetProfileScene.START_URL, controller: this.webController })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onPageBegin((_event: OnPageBeginEvent): void => {
              this.loading = true;
              this.errorMessage = '';
              this.parseFailedTip = false;
            })
            .onProgressChange((event: OnProgressChangeEvent): void => {
              this.loadProgress = event.newProgress;
            })
            .onPageEnd((event: OnPageEndEvent): void => {
              this.handlePageEnd(event.url);
            })
            .onErrorReceive((event: OnErrorReceiveEvent): void => {
              const errInfo: string = event.error.getErrorInfo();
              const errCode: number = event.error.getErrorCode();
              this.loading = false;
              this.errorMessage = `${errInfo} (${errCode})`;
              hilog.warn(DOMAIN, TAG, 'Web onErrorReceive: code=%{public}d info=%{public}s url=%{public}s',
                errCode, errInfo, event.request.getRequestUrl());
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
              const code: number = event.response.getResponseCode();
              hilog.warn(DOMAIN, TAG, 'Web onHttpErrorReceive: code=%{public}d url=%{public}s',
                code, event.request.getRequestUrl());
              if (event.request.isMainFrame()) {
                this.loading = false;
                this.errorMessage = `HTTP ${code}`;
              }
            })
            .width('100%')
            .height('100%')

          if (this.loading) {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(40)
                .height(40)
                .color($r('app.color.colorPrimary'))

              Text($r('app.string.loading'))
                .fontSize(13)
                .fontColor('#FF616161')
            }
            .padding(16)
            .borderRadius(8)
            .backgroundColor('#E6FFFFFF')
          }
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.colorPrimary'))

          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor('#FF616161')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_light'))
  }
}
