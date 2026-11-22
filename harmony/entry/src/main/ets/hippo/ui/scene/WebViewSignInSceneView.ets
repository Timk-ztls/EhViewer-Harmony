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
 * Phase B Track P1: WebViewSignInSceneView (@Component V1).
 *
 * Uses `@kit.ArkWeb` (`webview`) `Web` component + `ArkWebCookieManagerAdapter`
 * backed by `webview.WebCookieManager`. Runs `scene.prepareCookies()` before loading
 * `EhUrl.URL_SIGN_IN`, handles init-failed fallback dialog (`onInitFailedDialogDismissed`),
 * detects login completion automatically on `onPageEnd`, and exposes manual cookie harvesting
 * via `scene.finishWithCookies()` syncing into `RdbCookieStore` / `EhCookieStore`.
 */

import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppWiring } from '../../AppWiring';
import { EhCookieStore } from '../../ehviewer/client/EhCookieStore';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { WebViewSignInScene } from '../../ehviewer/ui/scene/sign/WebViewSignInScene';
import {
  ArkWebCookieManagerAdapter,
  EhCookieStoreProfileJar,
  RawWebCookieBackend,
  WebViewSignInCoordinator
} from './AuthSecurityAdapters';

const DOMAIN: number = 0x0000;
const TAG: string = 'WebViewSignInSceneView';
const TEXT_PRIMARY: string = '#DE000000';

class ArkWebCookieBackend implements RawWebCookieBackend {
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

  fetchCookieSync(url: string): string {
    return webview.WebCookieManager.fetchCookieSync(url);
  }

  configCookieSync(url: string, value: string): void {
    webview.WebCookieManager.configCookieSync(url, value);
  }
}

@Component
export struct WebViewSignInSceneView {
  scene: WebViewSignInScene | null = null;

  @State cookiesPrepared: boolean = false;
  @State initFailed: boolean = false;
  @State loadProgress: number = 0;
  @State errorMessage: string = '';
  @State statusNoticeRes: Resource | null = null;
  @State signInUrl: string = EhUrl.URL_SIGN_IN;

  private webController: webview.WebviewController = new webview.WebviewController();
  private coordinator: WebViewSignInCoordinator | null = null;

  aboutToAppear(): void {
    this.setupScene();
  }

  private setupScene(): void {
    this.cookiesPrepared = false;
    this.initFailed = false;
    this.loadProgress = 0;
    this.errorMessage = '';
    this.statusNoticeRes = null;
    this.signInUrl = EhUrl.URL_SIGN_IN;

    const currentScene: WebViewSignInScene | null = this.scene;
    if (currentScene === null) {
      hilog.warn(DOMAIN, TAG, 'WebViewSignInSceneView mounted with null scene');
      return;
    }

    const cookieAdapter: ArkWebCookieManagerAdapter = new ArkWebCookieManagerAdapter(new ArkWebCookieBackend());
    const store: EhCookieStore | null = AppWiring.getCookieStore();
    const jar: EhCookieStoreProfileJar | null = store !== null ? new EhCookieStoreProfileJar(store) : null;
    if (jar === null) {
      hilog.warn(DOMAIN, TAG, 'AppWiring.getCookieStore() is null; harvested cookies will rely on scene cookieJar');
    }

    const coord: WebViewSignInCoordinator = new WebViewSignInCoordinator(
      currentScene,
      cookieAdapter,
      jar,
      EhUrl.URL_SIGN_IN
    );
    this.coordinator = coord;
    this.signInUrl = coord.getSignInUrl();

    const ok: boolean = coord.init();
    if (!ok || currentScene.isInitFailed()) {
      this.initFailed = true;
      this.cookiesPrepared = false;
      hilog.error(DOMAIN, TAG, 'WebView/CookieManager init failed; showing unavailable fallback');
      return;
    }
    this.cookiesPrepared = true;
  }

  private onReloadClick(): void {
    this.errorMessage = '';
    this.statusNoticeRes = null;
    try {
      this.webController.refresh();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.errorMessage = msg;
      hilog.warn(DOMAIN, TAG, 'webController.refresh failed: %{public}s', msg);
    }
  }

  private onHarvestCookiesClick(): void {
    const coord: WebViewSignInCoordinator | null = this.coordinator;
    if (coord === null) {
      return;
    }
    const ok: boolean = coord.harvestCookiesManually();
    if (ok) {
      this.statusNoticeRes = $r('app.string.found_cookies');
    } else {
      this.statusNoticeRes = $r('app.string.wrong_cookie_warning');
    }
  }

  private onDismissInitFailed(): void {
    const coord: WebViewSignInCoordinator | null = this.coordinator;
    if (coord !== null) {
      coord.dismissInitFailedDialog();
    } else if (this.scene !== null) {
      this.scene.onInitFailedDialogDismissed();
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
      } else if (this.cookiesPrepared) {
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
                this.onReloadClick();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#FFFFEBEE')
        }

        if (this.statusNoticeRes !== null) {
          Text(this.statusNoticeRes)
            .fontSize(12)
            .fontColor($r('app.color.colorPrimary'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        }

        Web({ src: this.signInUrl, controller: this.webController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageBegin((_event: OnPageBeginEvent): void => {
            this.errorMessage = '';
          })
          .onProgressChange((event: OnProgressChangeEvent): void => {
            this.loadProgress = event.newProgress;
          })
          .onPageEnd((event: OnPageEndEvent): void => {
            this.loadProgress = 100;
            const coord: WebViewSignInCoordinator | null = this.coordinator;
            if (coord !== null) {
              const completed: boolean = coord.onPageEnd(event.url);
              if (completed) {
                this.statusNoticeRes = $r('app.string.found_cookies');
              }
            }
          })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            const errInfo: string = event.error.getErrorInfo();
            const errCode: number = event.error.getErrorCode();
            this.errorMessage = `${errInfo} (${errCode})`;
            hilog.warn(DOMAIN, TAG, 'Web onErrorReceive: code=%{public}d info=%{public}s url=%{public}s',
              errCode, errInfo, event.request.getRequestUrl());
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
            const code: number = event.response.getResponseCode();
            const url: string = event.request.getRequestUrl();
            hilog.warn(DOMAIN, TAG, 'Web onHttpErrorReceive: code=%{public}d url=%{public}s', code, url);
            if (event.request.isMainFrame()) {
              this.errorMessage = `HTTP ${code}`;
            }
          })
          .width('100%')
          .layoutWeight(1)

        Row({ space: 12 }) {
          Button($r('app.string.refresh'))
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.colorAccent'))
            .fontWeight(FontWeight.Bold)
            .onClick((): void => {
              this.onReloadClick();
            })

          Button($r('app.string.ok'))
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.colorPrimary'))
            .fontWeight(FontWeight.Bold)
            .onClick((): void => {
              this.onHarvestCookiesClick();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 8 })
        .backgroundColor($r('app.color.white'))
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
