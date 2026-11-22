/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/MyTagsActivity.java
 *       （inventory S0213，上游 145 行；清单登记 102 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/MyTagsActivity.ets
 *
 * 背景：**"我的标签"页** —— 本质是一个**只为这一个 URL 服务的 WebView**：
 * 把 okhttp 的 cookie 灌进 WebView 的 CookieManager，然后只允许加载 `my_tags` 这一个地址，
 * 每次进入都**先清空所有 cookie** 再重新灌（避免用户手动登出后残留）。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 字段：`webView` / `progress` / `url`（三处 `try` 内赋值）
 * `onCreate`（**整段包在 `try { ... } catch (Throwable t)` 里**）：
 *   ① `cookieManager.flush()` → **`removeAllCookies(null)`** → **`removeSessionCookies(null)`**
 *      （先清空，不是"合并"）
 *   ② `url = EhUrl.getMyTagsUrl()`
 *   ③ 遍历 `EhCookieStore.getCookies(HttpUrl.parse(url))` → `cookieManager.setCookie(url, cookie.toString())`
 *   ④ 布局 `activity_my_tags` + 返回图标；取 `webview` / `progress`
 *   ⑤ `settings.setJavaScriptEnabled(true)`；`setWebViewClient(new MyTagsWebViewClient())`；
 *      `setWebChromeClient(new DialogWebChromeClient(this))`；**`loadUrl(url)`**
 *   · **`catch (Throwable)`** → `Log.e(TAG, "WebView/CookieManager init failed", t)` +
 *     弹 AlertDialog（title `webview_unavailable_title` / message `webview_unavailable_message` /
 *     正按钮 OK → `finish()`；**`setOnCancelListener` 也 → `finish()`**）
 * `onOptionsItemSelected(home)` → `finish()` + true
 *
 * `MyTagsWebViewClient`：
 *   · `shouldOverrideUrlLoading(view, url)` → **`return !url.equals(MyTagsActivity.this.url)`**
 *     —— **只允许加载那一个 URL，其它一律拦截**（返回 true = 拦截）
 *   · `onPageStarted` → `progress.VISIBLE`
 *   · `onPageFinished` → `progress.GONE`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **进入时先 `removeAllCookies` + `removeSessionCookies`**，再灌 cookie —— 顺序反了会把刚灌的删掉。
 * 2. **URL 白名单是"完全相等"**：`!url.equals(this.url)`，不是 `startsWith`、不是"同域"。
 *    任何跳转（包括站点内的）都被拦截 —— 因为这是"只能看自己标签"的一次性页面。
 * 3. **整个初始化包在 `catch (Throwable)`** 里 —— WebView 在部分设备上构造即崩，
 *    此时弹"WebView 不可用"并退出（**正按钮与取消都 finish**）。
 * 4. **`progress` 是"页面级"进度**（onPageStarted/Finished 两个回调），不是加载百分比。
 * 5. **`loadUrl` 在 try 内**，所以 loadUrl 抛错也走同一个降级路径。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. Android `WebView` → ArkUI `Web({ src })`（`@ohos.web.webview`）：
 *    cookie 用 `@ohos.web.webview` 的 `WebCookieManager.configCookieSync/ saveCookieSync`。
 *    本文件**不直接调平台 API**，全部走 `MyTagsHost`（便于单测不依赖 WebView）。
 * 2. `CookieManager` 三步（flush / removeAll / removeSession）→ 宿主三个方法。
 * 3. `Cookie.toString()`（okhttp 的 `name=value; path=...` 形式）→ `cookieString` 由宿主提供，
 *    本文件只负责"把宿主给的 cookie 串按顺序灌进去"。
 * 4. `DialogWebChromeClient`（JS alert/confirm 走原生对话框）→ 宿主 `enableDialogs()`。
 * 5. `AlertDialog` → `WebViewUnavailableSpec`（纯数据）。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `EhUrl.getMyTagsUrl()`、字符串 `webview_unavailable_title` / `webview_unavailable_message`、
 * `hippo/ui/layout/activity_my_tags.ets`。
 */

/** 上游字符串键 */
export const STR_WEBVIEW_UNAVAILABLE_TITLE: string = 'app.string.webview_unavailable_title';
export const STR_WEBVIEW_UNAVAILABLE_MESSAGE: string = 'app.string.webview_unavailable_message';
/** 上游 `R.layout.activity_my_tags` / 返回图标 */
export const LAYOUT_ACTIVITY_MY_TAGS: string = 'activity_my_tags';
export const DRAWABLE_BACK: string = 'v_arrow_left_dark_x24';
/** 上游 `TAG = "MyTagsActivity"`（日志标签） */
export const LOG_TAG: string = 'MyTagsActivity';

/** "WebView 不可用"对话框（纯数据） */
export class WebViewUnavailableSpec {
  title: string = STR_WEBVIEW_UNAVAILABLE_TITLE;
  message: string = STR_WEBVIEW_UNAVAILABLE_MESSAGE;
  /** 上游 `android.R.string.ok` */
  positiveText: string = 'android.R.string.ok';
  /** **正按钮与取消都 finish**（见「关键行为」3） */
  cancelFinishes: boolean = true;
}

/** 宿主能力（WebView / CookieManager / 对话框 / 日志） */
export interface MyTagsHost {
  /** 上游 `CookieManager.flush()` */
  cookieFlush(): void;
  /** 上游 `CookieManager.removeAllCookies(null)` */
  cookieRemoveAll(): void;
  /** 上游 `CookieManager.removeSessionCookies(null)` */
  cookieRemoveSession(): void;
  /** 上游 `for (Cookie c : store.getCookies(url)) cm.setCookie(url, c.toString())` */
  cookieSet(url: string, cookie: string): void;
  /** 上游 `EhCookieStore.getCookies(HttpUrl.parse(url))`（返回已格式化串） */
  getCookiesFor(url: string): string[];
  /** 上游 `EhUrl.getMyTagsUrl()` */
  getMyTagsUrl(): string;
  /** 上游 WebView 装配四项 */
  setJavaScriptEnabled(enabled: boolean): void;
  enableDialogs(): void;
  loadUrl(url: string): void;
  /** 上游 `progress.setVisibility(VISIBLE/GONE)` */
  setProgressVisible(visible: boolean): void;
  /** 上游 `setNavigationIcon(...)` */
  setNavigationIcon(icon: string): void;
  /** 上游 `finish()` */
  finish(): void;
  /** 上游 `Log.e(TAG, msg, t)` */
  logError(msg: string): void;
  /** 页面层"弹对话框"（本文件只产出描述） */
  showUnavailableDialog(spec: WebViewUnavailableSpec): void;
}

/** `onCreate` 的产物（便于断言走了哪条路） */
export class MyTagsInitResult {
  /** 是否成功装起 WebView（false = 走了 catch 降级） */
  ok: boolean = false;
  /** 目标 URL（成功时有值） */
  url: string = '';
  /** 灌进去的 cookie 条数 */
  cookiesSet: number = 0;
  /** 降级对话框（仅失败时） */
  dialog: WebViewUnavailableSpec | null = null;
}

export class MyTagsActivity {
  private host: MyTagsHost;
  /** 上游 `url` 字段（`shouldOverrideUrlLoading` 白名单用） */
  private url: string = '';
  private created: boolean = false;

  constructor(host: MyTagsHost) {
    this.host = host;
  }

  /** 白名单 URL（测试观测） */
  getUrl(): string {
    return this.url;
  }

  /**
   * 上游 `onCreate`（**整段包在 `catch (Throwable)` 里**，见「关键行为」3）：
   * ① flush → **removeAll** → **removeSession**（顺序不可换，见「关键行为」1）
   * ② 取 my_tags URL ③ 逐个 setCookie ④ 装配 WebView ⑤ loadUrl
   */
  onCreate(): MyTagsInitResult {
    const result: MyTagsInitResult = new MyTagsInitResult();
    try {
      // ① 先清空（顺序不可换：先删再灌）
      this.host.cookieFlush();
      this.host.cookieRemoveAll();
      this.host.cookieRemoveSession();

      // ② URL
      this.url = this.host.getMyTagsUrl();

      // ③ 灌 cookie
      const cookies: string[] = this.host.getCookiesFor(this.url);
      for (let i = 0; i < cookies.length; i++) {
        this.host.cookieSet(this.url, cookies[i]);
      }
      result.cookiesSet = cookies.length;

      // ④ 装配
      this.host.setNavigationIcon(DRAWABLE_BACK);
      this.host.setJavaScriptEnabled(true);
      this.host.enableDialogs();

      // ⑤ 加载
      this.host.loadUrl(this.url);

      this.created = true;
      result.ok = true;
      result.url = this.url;
      return result;
    } catch (e) {
      // 上游：Log.e(TAG, "WebView/CookieManager init failed", t) + 弹框 + finish
      this.host.logError('WebView/CookieManager init failed: ' + (e as Error).message);
      const spec: WebViewUnavailableSpec = new WebViewUnavailableSpec();
      result.dialog = spec;
      this.host.showUnavailableDialog(spec);
      return result;
    }
  }

  /** 上游 `onOptionsItemSelected(home)` → finish + true */
  onOptionsItemSelected(itemId: string): boolean {
    if (itemId === 'android.R.id.home') {
      this.host.finish();
      return true;
    }
    return false;
  }

  /**
   * 上游 `MyTagsWebViewClient.shouldOverrideUrlLoading`：
   * **`return !url.equals(this.url)`** —— true = 拦截（见「关键行为」2）。
   * @returns true 表示"拦截这次跳转"
   */
  shouldOverrideUrlLoading(targetUrl: string): boolean {
    return targetUrl !== this.url;
  }

  /** 上游 `onPageStarted` → 进度可见 */
  onPageStarted(): void {
    this.host.setProgressVisible(true);
  }

  /** 上游 `onPageFinished` → 进度隐藏 */
  onPageFinished(): void {
    this.host.setProgressVisible(false);
  }

  /** 上游 `catch` 分支的"取消也 finish"（见「关键行为」3） */
  onUnavailableDialogCancel(): void {
    this.host.finish();
  }

  /** 上游 `catch` 分支的正按钮 OK → finish */
  onUnavailableDialogConfirm(): void {
    this.host.finish();
  }

  /** 是否已成功装起（测试观测） */
  isCreated(): boolean {
    return this.created;
  }
}
