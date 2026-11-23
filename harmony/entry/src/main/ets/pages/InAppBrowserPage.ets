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

import { common, Want } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { EhCookieStore } from '../hippo/ehviewer/client/EhCookieStore';
import { Cookie } from '../hippo/okhttp/Cookie';
import { HttpUrl } from '../hippo/okhttp/HttpUrl';
import { ArkWebProxyManager } from '../hippo/ui/ArkWebProxyManager';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VRefreshDarkX24 } from '../hippo/ui/drawable/v_refresh_dark_x24';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'InAppBrowserPage';

@Entry
@Component
struct InAppBrowserPage {
  @State proxyReady: boolean = false;
  @State targetUrl: string = '';
  @State currentUrl: string = '';
  @State pageTitle: string = '';
  @State loadProgress: number = 0;
  @State errorMessage: string = '';

  private webController: webview.WebviewController = new webview.WebviewController();

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  aboutToAppear(): void {
    try {
      const rawParams: Object | undefined = this.getUIContext().getRouter().getParams() as Object | undefined;
      if (rawParams !== undefined && rawParams !== null) {
        const rec: Record<string, Object> = rawParams as Record<string, Object>;
        const rawUrl: Object | undefined = rec['url'];
        const rawTitle: Object | undefined = rec['title'];
        if (typeof rawUrl === 'string') {
          this.targetUrl = rawUrl as string;
          this.currentUrl = rawUrl as string;
        }
        if (typeof rawTitle === 'string') {
          this.pageTitle = rawTitle as string;
        }
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'read router params failed: %{public}s', msg);
    }
    this.initializeBrowser().catch((e: Error): void => {
      const msg: string = e.message !== undefined ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'initializeBrowser failed: %{public}s', msg);
      this.errorMessage = msg;
      this.proxyReady = true;
    });
  }

  aboutToDisappear(): void {
    try {
      this.webController.stop();
    } catch (e) {
      hilog.debug(LOG_DOMAIN, LOG_TAG, 'webController.stop skipped: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  onBackPress(): boolean {
    try {
      if (this.proxyReady && this.webController.accessBackward()) {
        this.webController.backward();
        return true;
      }
    } catch (e) {
      hilog.debug(LOG_DOMAIN, LOG_TAG, 'accessBackward check failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    return false;
  }

  private async initializeBrowser(): Promise<void> {
    try {
      await AppWiring.whenReady();
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'AppWiring.whenReady failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    await ArkWebProxyManager.syncFromSettings();
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(true);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
      this.syncCookiesIfNeeded(this.targetUrl);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'cookie setup warning: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    this.proxyReady = true;
  }

  private syncCookiesIfNeeded(urlStr: string): void {
    const httpUrl: HttpUrl | null = HttpUrl.parse(urlStr);
    if (httpUrl === null) {
      return;
    }
    const host: string = httpUrl.host().toLowerCase();
    if (!host.endsWith('e-hentai.org') && !host.endsWith('exhentai.org')) {
      return;
    }
    const store: EhCookieStore | null = AppWiring.getCookieStore();
    if (store === null) {
      return;
    }
    const cookies: Cookie[] = store.getCookies(httpUrl);
    for (let i = 0; i < cookies.length; i++) {
      const c: Cookie = cookies[i];
      webview.WebCookieManager.configCookieSync(urlStr, `${c.name()}=${c.value()}`);
    }
  }

  private navigateBack(): void {
    if (this.onBackPress()) {
      return;
    }
    try {
      this.getUIContext().getRouter().back();
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'router.back failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private reloadPage(): void {
    this.errorMessage = '';
    try {
      this.webController.refresh();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.errorMessage = msg;
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'refresh failed: %{public}s', msg);
    }
  }

  private openInExternalBrowser(): void {
    const uri: string = this.currentUrl.length > 0 ? this.currentUrl : this.targetUrl;
    if (uri.length === 0) {
      return;
    }
    try {
      const ctx: common.UIAbilityContext | undefined =
        this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (ctx === undefined) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'openInExternalBrowser: hostContext unavailable');
        return;
      }
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: uri
      };
      ctx.startAbility(want).catch((e: Error): void => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'openInExternalBrowser failed: %{public}s', e.message);
      });
    } catch (e) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'openInExternalBrowser threw: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({
            fillColor: '#FFFFFFFF',
            iconSize: 22
          })
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.navigateBack();
        })

        Text(this.pageTitle.length > 0 ? this.pageTitle : this.targetUrl)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Button({ type: ButtonType.Normal }) {
          VRefreshDarkX24({
            fillColor: '#FFFFFFFF',
            iconSize: 20
          })
        }
        .width(38)
        .height(38)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.reloadPage();
        })

        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.in_app_browser_open_external'))
            .fontSize(12)
            .fontColor('#FFFFFFFF')
        }
        .height(34)
        .padding({ left: 8, right: 8 })
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.openInExternalBrowser();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor(this.palette().colorPrimary)
      .alignItems(VerticalAlign.Center)

      if (this.loadProgress > 0 && this.loadProgress < 100) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color($r('app.color.colorAccent'))
      }

      if (this.errorMessage.length > 0) {
        Row({ space: 8 }) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor('#FFB71C1C')
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Button($r('app.string.retry'))
            .height(30)
            .fontSize(12)
            .backgroundColor(Color.Transparent)
            .fontColor(this.palette().colorPrimary)
            .onClick((): void => {
              this.reloadPage();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor('#FFFFEBEE')
      }

      if (!this.proxyReady) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.teal_500'))

          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor(this.palette().textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.targetUrl.length > 0) {
        Web({ src: this.targetUrl, controller: this.webController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .zoomAccess(true)
          .onPageBegin((event: OnPageBeginEvent): void => {
            this.errorMessage = '';
            if (event.url.length > 0) {
              this.currentUrl = event.url;
            }
          })
          .onProgressChange((event: OnProgressChangeEvent): void => {
            this.loadProgress = event.newProgress;
          })
          .onTitleReceive((event: OnTitleReceiveEvent): void => {
            if (event.title.length > 0 && this.pageTitle.length === 0) {
              this.pageTitle = event.title;
            }
          })
          .onPageEnd((event: OnPageEndEvent): void => {
            this.loadProgress = 100;
            if (event.url.length > 0) {
              this.currentUrl = event.url;
            }
          })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            const errInfo: string = event.error.getErrorInfo();
            const errCode: number = event.error.getErrorCode();
            this.errorMessage = `${errInfo} (${errCode})`;
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Web onErrorReceive: code=%{public}d info=%{public}s url=%{public}s',
              errCode, errInfo, event.request.getRequestUrl());
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
            const code: number = event.response.getResponseCode();
            if (event.request.isMainFrame()) {
              this.errorMessage = `HTTP ${code}`;
            }
          })
          .width('100%')
          .layoutWeight(1)
      } else {
        Column() {
          Text($r('app.string.error_invalid_url'))
            .fontSize(14)
            .fontColor(this.palette().textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
