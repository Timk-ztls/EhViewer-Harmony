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
 * Phase B Track P1: GetProfileScene SolidScene/SceneFragment shell.
 *
 * Bridges the pure-logic `GetProfileScene` helpers with `SolidScene` lifecycle,
 * result passing (`DISPLAY_NAME` / `AVATAR` for `REQUEST_CODE_PROFILE`),
 * and injectable `ProfileHttpExecutor` / `ProfileCookieJar` slots.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs, SceneResultCode } from '../../../../scene/SceneTypes';
import { SolidScene } from '../SolidScene';
import {
  AVATAR,
  DISPLAY_NAME,
  GetProfileScene,
  HttpResponseLike,
  PageFinishedAction,
  ProfileCookieJar,
  ProfileHttpExecutor,
  ProfileResult,
  REQUEST_CODE_PROFILE,
  WebRequestLike,
  WebResponsePlan
} from './GetProfileScene';

const DOMAIN: number = 0x0000;
const TAG: string = 'GetProfileSceneShell';

export class UnavailableProfileHttpExecutor implements ProfileHttpExecutor {
  private warned: boolean = false;

  execute(method: string, url: string, headers: Map<string, string>,
    form: Map<string, string> | null): HttpResponseLike {
    if (!this.warned) {
      this.warned = true;
      hilog.warn(DOMAIN, TAG,
        'ProfileHttpExecutor 未接线: method=%{public}s url=%{public}s；后果：回退 WebView 默认网络栈',
        method, url);
    }
    throw new Error('ProfileHttpExecutor not wired');
  }
}

export class UnavailableProfileCookieJar implements ProfileCookieJar {
  private warnedSet: boolean = false;
  private warnedGet: boolean = false;

  setCookie(url: string, cookie: string): void {
    if (!this.warnedSet) {
      this.warnedSet = true;
      hilog.warn(DOMAIN, TAG,
        'ProfileCookieJar 未接线: setCookie(url=%{public}s)；后果：响应 Cookie 不会同步到持久存储', url);
    }
  }

  getCookie(host: string): string {
    if (!this.warnedGet) {
      this.warnedGet = true;
      hilog.warn(DOMAIN, TAG,
        'ProfileCookieJar 未接线: getCookie(host=%{public}s)；后果：返回空 Cookie', host);
    }
    return '';
  }
}

/**
 * `GetProfileScene` 的 `SolidScene` 外壳。
 */
export class GetProfileSceneShell extends SolidScene {
  static readonly REQUEST_CODE: number = REQUEST_CODE_PROFILE;
  static readonly KEY_DISPLAY_NAME: string = DISPLAY_NAME;
  static readonly KEY_AVATAR: string = AVATAR;

  private httpExecutor: ProfileHttpExecutor | null;
  private cookieJar: ProfileCookieJar | null;
  private useSniProvider: (() => boolean) | null = null;
  private onProfileLoadedListener: ((profile: ProfileResult) => void) | null = null;
  private fallbackCookieJar: UnavailableProfileCookieJar = new UnavailableProfileCookieJar();
  private warnedMissingExecutor: boolean = false;
  private completed: boolean = false;
  private initFailed: boolean = false;
  private lastProfile: ProfileResult | null = null;
  private lastError: string = '';

  constructor(executor: ProfileHttpExecutor | null = null, cookieJar: ProfileCookieJar | null = null) {
    super();
    this.httpExecutor = executor;
    this.cookieJar = cookieJar;
  }

  getSceneName(): string {
    return 'GetProfileScene';
  }

  needShowLeftDrawer(): boolean {
    return GetProfileScene.NEED_SHOW_LEFT_DRAWER;
  }

  getStartUrl(): string {
    return GetProfileScene.START_URL;
  }

  getCookieHost(): string {
    return GetProfileScene.COOKIE_HOST;
  }

  getReadContentJs(): string {
    return GetProfileScene.READ_CONTENT_JS;
  }

  setHttpExecutor(executor: ProfileHttpExecutor | null): void {
    this.httpExecutor = executor;
  }

  getHttpExecutor(): ProfileHttpExecutor | null {
    return this.httpExecutor;
  }

  hasHttpExecutor(): boolean {
    return this.httpExecutor !== null;
  }

  setCookieJar(jar: ProfileCookieJar | null): void {
    this.cookieJar = jar;
  }

  getCookieJar(): ProfileCookieJar {
    if (this.cookieJar !== null) {
      return this.cookieJar;
    }
    return this.fallbackCookieJar;
  }

  setUseSniProvider(provider: (() => boolean) | null): void {
    this.useSniProvider = provider;
  }

  shouldUseSniClient(): boolean {
    if (this.useSniProvider === null) {
      return false;
    }
    try {
      return this.useSniProvider();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'useSniProvider failed: %{public}s', msg);
      return false;
    }
  }

  setOnProfileLoadedListener(listener: ((profile: ProfileResult) => void) | null): void {
    this.onProfileLoadedListener = listener;
  }

  isCompleted(): boolean {
    return this.completed;
  }

  isInitFailed(): boolean {
    return this.initFailed;
  }

  getLastProfile(): ProfileResult | null {
    return this.lastProfile;
  }

  getLastError(): string {
    return this.lastError;
  }

  /**
   * ArkWeb `runJavaScript` 与 Android `evaluateJavascript` 返回字符串结果时会包一层 JSON 引号与转义。
   * 本方法安全解包 JSON 字符串，若本身已是原始 HTML 则原样返回。
   */
  static normalizeJavaScriptStringResult(raw: string | null): string | null {
    if (raw === null) {
      return null;
    }
    const trimmed: string = raw.trim();
    if (trimmed.length === 0 || trimmed === 'null' || trimmed === 'undefined') {
      return null;
    }
    if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        const parsed: Object | null = JSON.parse(trimmed) as Object | null;
        if (typeof parsed === 'string') {
          return parsed;
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'normalizeJavaScriptStringResult JSON.parse failed: %{public}s', msg);
      }
    }
    return raw;
  }

  /** 页面加载完成时的动作决策（委托给 `GetProfileScene.planPageFinished`）。 */
  planPageFinished(url: string): PageFinishedAction {
    return GetProfileScene.planPageFinished(!this.viewDestroyed, url);
  }

  /**
   * 拦截子请求（上游 `shouldInterceptRequest`）。
   * 未注入 `ProfileHttpExecutor` 时打一次 warn 并返回 `null` 放行给 WebView 默认网络栈。
   */
  interceptRequest(request: WebRequestLike): WebResponsePlan | null {
    const exec: ProfileHttpExecutor | null = this.httpExecutor;
    if (exec === null) {
      if (!this.warnedMissingExecutor) {
        this.warnedMissingExecutor = true;
        hilog.warn(DOMAIN, TAG,
          'interceptRequest: ProfileHttpExecutor 未注入，放行给 WebView 默认网络栈: %{public}s',
          request.url);
      }
      return null;
    }
    return GetProfileScene.intercept(request, exec, this.getCookieJar());
  }

  /**
   * 解析 `READ_CONTENT_JS` 返回的 HTML 并在成功时回传结果并 finish。
   * 解析失败时只记录日志、不结束页面（严格对齐上游行为）。
   */
  handlePageContent(rawContent: string | null): ProfileResult | null {
    if (this.completed) {
      return this.lastProfile;
    }
    const normalized: string | null = GetProfileSceneShell.normalizeJavaScriptStringResult(rawContent);
    const parsed: ProfileResult | null = GetProfileScene.parsePageContent(normalized);
    if (parsed === null) {
      hilog.warn(DOMAIN, TAG, 'handlePageContent: 未解析出个人资料，保持当前页面等待重试');
      return null;
    }
    return this.completeWithProfile(parsed);
  }

  /** 写入个人资料结果（`DISPLAY_NAME` / `AVATAR`）并结束场景。 */
  completeWithProfile(profile: ProfileResult): ProfileResult {
    const args: SceneArgs = new Map<string, Object>();
    args.set(DISPLAY_NAME, profile.displayName);
    if (profile.avatar !== null) {
      args.set(AVATAR, profile.avatar);
    }
    this.lastProfile = profile;
    this.lastError = '';
    this.completed = true;
    this.setResult(SceneResultCode.OK, args);
    if (this.onProfileLoadedListener !== null) {
      try {
        this.onProfileLoadedListener(profile);
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'onProfileLoadedListener threw: %{public}s', msg);
      }
    }
    this.finish();
    return profile;
  }

  /** 记录 WebView / CookieManager 初始化失败。 */
  onInitFailed(reason: string): void {
    this.initFailed = true;
    this.lastError = reason;
    hilog.error(DOMAIN, TAG, 'WebView/CookieManager init failed: %{public}s', reason);
  }

  /** 上游初始化失败兜底弹窗关闭回调：返回 CANCELED 并 finish。 */
  onInitFailedDialogDismissed(): void {
    this.setResult(SceneResultCode.CANCELED, null);
    this.finish();
  }

  /** 显式取消并记录错误原因。 */
  cancelWithError(reason: string): void {
    this.lastError = reason;
    hilog.warn(DOMAIN, TAG, 'GetProfileScene canceled: %{public}s', reason);
    this.setResult(SceneResultCode.CANCELED, null);
    this.finish();
  }
}
