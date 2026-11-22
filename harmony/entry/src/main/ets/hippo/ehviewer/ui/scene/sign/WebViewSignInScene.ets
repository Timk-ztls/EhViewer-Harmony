/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/sign/WebViewSignInScene.kt（328 行，Kotlin）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/sign/WebViewSignInScene.ets（S0261）
 *
 * 上游事实（读源码确认）：
 *   1. class WebViewSignInScene : SolidScene()；needShowLeftDrawer() 被覆盖（登录页无侧栏）
 *   2. onCreateView2 的顺序：CookieManager.flush() → removeAllCookies(null) → removeSessionCookies(null)
 *      → setAcceptCookie(true) → setAcceptFileSchemeCookies(true) → WebView settings → loadUrl(EhUrl.URL_SIGN_IN)
 *      初始化失败 catch：Log.e(TAG, "WebView/CookieManager init failed") + AlertDialog(ok → finish, cancel → finish)
 *   3. 复用 App 的 OkHttpClient（okHttpClient 字段，与 GetProfileScene 的"被拦截的 WebView"同一套路）
 *   4. 收尾：parseCookies(url, cookieStrings) 逐段 Cookie.parse → addCookie(domain, cookie) 写入 EhCookieStore
 *
 * ⚠ 关于 REQUEST_CODE 同值问题（Lead 提问）：
 *   本场景是 **请求的发出方**（SignInScene 用 REQUEST_CODE_WEBVIEW=0 启动它），它自己是叶子，
 *   上游 **没有** 覆盖 onSceneResult —— 也就是说它不接收任何场景结果，只 finish 回传自己的 cookie 结果。
 *   因此"这个结果是谁的"这个问题在本页不存在；歧义只发生在 SignInScene 侧（它同时是 Cookie 页的接收方，
 *   两者 requestCode 同为 0），已在那里按"两条一起判"处理。
 *
 * Part 1（本批）：cookie 清空/接受策略、cookie 解析与写入、初始化失败兜底、finish 回传。
 * Part 2 待补：WebView 拦截器接线（复用 GetProfileScene 的 InterceptPlan）、加载进度 UI。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../../../scene/SceneTypes';
import { SceneFragment } from '../../../../scene/SceneFragment';
import { SceneResultCode } from '../../../../scene/SceneTypes';
import { ProfileCookieJar } from './GetProfileScene';

/** WebView cookie 管理器（生产实现包 @ohos.web.webview 的 WebCookieManager） */
export interface WebCookieManagerLike {
  flush(): void;
  removeAllCookies(): void;
  removeSessionCookies(): void;
  setAcceptCookie(accept: boolean): void;
  setAcceptFileSchemeCookies(accept: boolean): void;
  getCookie(url: string): string;
}

/** 一条已解析的 cookie（上游 okhttp3.Cookie 的最小投影） */
export class WebCookie {
  readonly name: string;
  readonly value: string;
  readonly domain: string;
  constructor(name: string, value: string, domain: string) {
    this.name = name;
    this.value = value;
    this.domain = domain;
  }
}

export class UnavailableWebCookieManager implements WebCookieManagerLike {
  flush(): void {}
  removeAllCookies(): void {}
  removeSessionCookies(): void {}
  setAcceptCookie(accept: boolean): void {}
  setAcceptFileSchemeCookies(accept: boolean): void {}
  getCookie(url: string): string {
    hilog.warn(0x0000, 'WebViewSignInScene', 'WebCookieManager 未接线: getCookie(url=%{public}s)；后果：登录 cookie 为空', url);
    return '';
  }
}

export abstract class WebViewSignInScene extends SceneFragment {
  static readonly TAG: string = 'WebViewSignInScene';
  /** 上游 `mWebView.loadUrl(EhUrl.URL_SIGN_IN)`；路径常量由 EhUrl 提供 */
  static readonly URL_SIGN_IN_KEY: string = 'url_sign_in';

  protected cookieManager: WebCookieManagerLike = new UnavailableWebCookieManager();
  protected cookieJar: ProfileCookieJar | null = null;
  protected signInUrl: string = '';
  protected initFailed: boolean = false;

  getSceneName(): string {
    return 'WebViewSignInScene';
  }

  /** 上游 needShowLeftDrawer() = false */
  needShowLeftDrawer(): boolean {
    return false;
  }

  setCookieManager(m: WebCookieManagerLike): void { this.cookieManager = m; }
  setCookieJar(jar: ProfileCookieJar): void { this.cookieJar = jar; }
  setSignInUrl(url: string): void { this.signInUrl = url; }

  /**
   * 上游 onCreateView2 里 cookie 相关的五步，逐字保序。
   * 顺序有意义：先 flush 把内存 cookie 落盘，再清两种 cookie，最后才允许接受。
   */
  prepareCookies(): boolean {
    try {
      this.cookieManager.flush();
      this.cookieManager.removeAllCookies();
      this.cookieManager.removeSessionCookies();
      this.cookieManager.setAcceptCookie(true);
      this.cookieManager.setAcceptFileSchemeCookies(true);
      return true;
    } catch (e) {
      this.initFailed = true;
      hilog.error(0x0000, 'WebViewSignInScene',
        'WebView/CookieManager init failed: err=%{public}s；后果：登录页无法加载，将直接关闭并返回失败',
        (e as Error).message !== undefined ? (e as Error).message : String(e));
      return false;
    }
  }

  /** 初始化失败时的上游兜底：弹一个只有 OK 的对话框，点掉或取消都 finish */
  onInitFailedDialogDismissed(): void {
    this.result = null;
    this.resultCode = SceneResultCode.CANCELED;
    this.finish();
  }

  /**
   * 上游 parseCookies(url, cookieStrings)：按 ';' 切段，每段 Cookie.parse，
   * 解析失败的段**跳过**（上游 `?: continue`），不整体失败。
   */
  static parseCookies(cookieStrings: string, domain: string): WebCookie[] {
    const out: WebCookie[] = [];
    if (cookieStrings.length === 0) {
      return out;
    }
    const pieces: string[] = cookieStrings.split(';');
    for (let i = 0; i < pieces.length; i++) {
      const piece: string = pieces[i].trim();
      if (piece.length === 0) {
        continue;
      }
      const eq: number = piece.indexOf('=');
      if (eq <= 0) {
        // 上游 Cookie.parse 返回 null → continue
        hilog.info(0x0000, 'WebViewSignInScene', 'cookie 段无法解析，已跳过: %{public}s', piece);
        continue;
      }
      out.push(new WebCookie(piece.substring(0, eq).trim(), piece.substring(eq + 1).trim(), domain));
    }
    return out;
  }

  /** 上游 loadFinished 之后的收尾：读 cookie → 逐条写入 jar → finish（成功） */
  finishWithCookies(): void {
    const raw: string = this.cookieManager.getCookie(this.signInUrl);
    const cookies: WebCookie[] = WebViewSignInScene.parseCookies(raw, this.signInUrl);
    if (cookies.length === 0) {
      hilog.warn(0x0000, 'WebViewSignInScene', '登录完成但没取到 cookie: url=%{public}s；后果：登录状态未建立，返回失败',
        this.signInUrl);
      this.result = null;
      this.resultCode = SceneResultCode.CANCELED;
      this.finish();
      return;
    }
    if (this.cookieJar !== null) {
      for (let i = 0; i < cookies.length; i++) {
        const c: WebCookie = cookies[i];
        this.cookieJar.setCookie(this.signInUrl, c.name + '=' + c.value);
      }
    } else {
      hilog.warn(0x0000, 'WebViewSignInScene', 'cookieJar 未注入: 写入 0 条；后果：本次登录的 cookie 不会生效');
    }
    const result: SceneArgs = new Map<string, Object>();
    result.set('cookie_count', cookies.length);
    this.result = result;
    this.resultCode = SceneResultCode.OK;
    this.finish();
  }

  isInitFailed(): boolean {
    return this.initFailed;
  }
}
