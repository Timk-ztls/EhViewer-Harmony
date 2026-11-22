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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/sign/GetProfileScene.kt（517 行）。
 *
 * ============================================================================
 * 一、上游是什么（"从论坛页取个人资料"）
 * ============================================================================
 * 本质是**一个被拦截的 WebView**：加载论坛首页 → 所有 http(s) 子请求不走 WebView 默认网络栈，
 * 而是转成 OkHttp 发出去（这样才带上 App 的 Cookie/UA），拿到响应再包回 `WebResourceResponse`；
 * 页面加载完成后注入 JS 取 `document.documentElement.outerHTML`，交给 `ProfileParser.parseNew()`
 * 解析出 `displayName` / `avatar`，`setResult` 后结束。
 *
 *   ```kotlin
 *   shouldInterceptRequest(view, request):
 *     !http(s) → null                                    // file:// / data: 交给 WebView
 *     method = getRequestMethod(request)                  // X-HTTP-Method-Override > FORM→POST > 有表单参数→POST > GET
 *     Range 头原样带上
 *     type: FETCH/HTML/XML_HTTP → handleRequestWithBody
 *           FORM               → buildForm → POST
 *           其它               → handleRequestWithBody
 *     3xx 且有 Location → close + return null            // 让 WebView 自己跟跳转
 *     body == null      → close + IOException
 *     syncCookiesFromResponse(response, url)             // Set-Cookie 回写 CookieManager
 *     return convertOkHttpResponse(response)
 *     任何异常 → recordException + return null           // 回退 WebView 默认网络栈
 *   ```
 *
 * 逐行对照时最容易丢/写反的**六条**（本文件逐条保留并断言）：
 *   1. **非 http(s) 一律放行**（返回 null），否则 App 的 Cookie 注入会连 `data:`/`file:` 一起拦，
 *      页面里的内联资源会全白；
 *   2. `getRequestMethod` 的优先级是 **override 头 > FORM→POST > 有表单参数→POST > GET**
 *      —— 顺序反了会把"带参数的 GET"误判成 POST；
 *   3. **3xx + 有 Location → 返回 null**（把跳转交还 WebView），不是自己跟；
 *   4. `convertOkHttpResponse` 的 `mimeType` 取 `contentType.split(";")[0]`，编码从 `charset=` 取、
 *      **缺省 UTF-8**；`reasonPhrase` 为空时要用 `defaultReasonPhrase(statusCode)` **补**；
 *   5. `onPageFinished` 里两道前置判空（context / `HttpUrl.parse(url)`），任一为空**不取页面内容**；
 *   6. `readPageContent` 的 JS **只取 `document.documentElement.outerHTML`**（上游有一大段
 *      被注释掉的"结构化 JSON"方案），解析失败只记录、不改变流程。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * 上游 517 行里约 300 行是 Android WebView 框架胶水（`WebViewClient` / `RequestInspector` /
 * `WebResourceResponse` / 反射取请求体）。鸿蒙用 `Web` 组件 + `onInterceptRequest`，
 * 语义相近但 API 完全不同，所以：
 *
 *   - **判据**（本文件纯函数）：要不要拦截、方法推断、重定向交还、响应头/编码/原因短语转换、
 *     页面完成时的前置判空、JS 片段、结果 bundle 的键；
 *   - **真正发请求** → 注入 `ProfileHttpExecutor`（生产实现包 `@ohos.net.http`）；
 *   - **Cookie 读写** → 注入 `ProfileCookieJar`（生产实现包 `@ohos.web.webview` 的
 *     `WebCookieManager`）；
 *   - **页面跳转/结束** → 由 ArkUI 页面驱动，本文件只给判据。
 *
 * 依赖现状：`ProfileParser`（net-parse 已交）、`EhUrl.URL_FORUMS` / `EhUrl.HOST_E`（已交）。
 * `Settings.getDF()`（SNI 开关）/ `AppHelper.checkVPN` 未导出 → 作为入参传入
 * （"依赖做成入参"的同一口径），调用方拿到值即可，本文件不 import Settings。
 */

import { EhUrl } from '../../../client/EhUrl';
import { ProfileParser } from '../../../client/parser/ProfileParser';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'GetProfileScene';

/** 结果键与请求码（上游 `SignInScene` 的三个常量，逐字对齐）。 */
export const REQUEST_CODE_PROFILE: number = 0x000F;
export const DISPLAY_NAME: string = 'displayName';
export const AVATAR: string = 'avatar';

/** 上游用到的 WebView 请求类型（只保留真正区分处理的三类 + 其它）。 */
export enum WebRequestType {
  /** 上游 `WebViewRequestType.FETCH` */
  FETCH = 0,
  /** 上游 `WebViewRequestType.HTML` */
  HTML = 1,
  /** 上游 `WebViewRequestType.XML_HTTP` */
  XML_HTTP = 2,
  /** 上游 `WebViewRequestType.FORM`（表单提交） */
  FORM = 3,
  /** 其它（RESOURCE / IMAGE / STYLESHEET / SCRIPT / FONT / 未知） */
  OTHER = 99
}

/** 拦截决策。 */
export enum InterceptDecision {
  /** 交给 WebView 自己处理（非 http(s) / 3xx 有 Location / 出错回退） */
  PASS_THROUGH = 0,
  /** 由我们发请求并回填响应 */
  INTERCEPT = 1
}

/** 页面完成后的动作。 */
export enum PageFinishedAction {
  /** 不读页面内容（context 失效 / url 解析失败） */
  NONE = 0,
  /** 注入 JS 取 outerHTML 并解析资料 */
  READ_CONTENT = 1
}

/** 一次请求的形态（从上游 `WebViewRequest` 投影出来的最小集）。 */
export class WebRequestLike {
  url: string = '';
  headers: Map<string, string> = new Map<string, string>();
  type: WebRequestType = WebRequestType.OTHER;
  /** 表单参数（上游 `request.formParameters`）；非表单请求为空表。 */
  formParameters: Map<string, string> = new Map<string, string>();

  constructor(url: string, headers: Map<string, string>, type: WebRequestType,
    formParameters: Map<string, string>) {
    this.url = url;
    this.headers = headers;
    this.type = type;
    this.formParameters = formParameters;
  }
}

/** 响应投影（上游 `okhttp3.Response` 的最小可移植面）。 */
export class HttpResponseLike {
  code: number = 0;
  message: string = '';
  /** 头名 → 值（同名多值用换行拼，与上游 `headers().names()` + `header()` 的取法一致）。 */
  headers: Map<string, string> = new Map<string, string>();
  contentType: string = '';
  body: ArrayBuffer | null = null;

  constructor(code: number, message: string, headers: Map<string, string>, contentType: string,
    body: ArrayBuffer | null) {
    this.code = code;
    this.message = message;
    this.headers = headers;
    this.contentType = contentType;
    this.body = body;
  }
}

/** 转换后的响应（对应上游 `WebResourceResponse` 的五个构造参数）。 */
export class WebResponsePlan {
  mimeType: string = 'text/html';
  encoding: string = 'UTF-8';
  statusCode: number = 0;
  reasonPhrase: string = '';
  headers: Map<string, string> = new Map<string, string>();
  body: ArrayBuffer | null = null;

  constructor(mimeType: string, encoding: string, statusCode: number, reasonPhrase: string,
    headers: Map<string, string>, body: ArrayBuffer | null) {
    this.mimeType = mimeType;
    this.encoding = encoding;
    this.statusCode = statusCode;
    this.reasonPhrase = reasonPhrase;
    this.headers = headers;
    this.body = body;
  }
}

/** 解析结果（上游 `setResult(REQUEST_CODE_PROFILE, bundle)` 的内容）。 */
export class ProfileResult {
  displayName: string = '';
  /** 上游 `ProfileParser.Result.avatar` 是 `String?`（解析不到时为 null）—— 保持可空。 */
  avatar: string | null = null;

  constructor(displayName: string, avatar: string | null) {
    this.displayName = displayName;
    this.avatar = avatar;
  }
}

/** 请求执行器（生产实现包 `@ohos.net.http`）。 */
export interface ProfileHttpExecutor {
  execute(method: string, url: string, headers: Map<string, string>,
    form: Map<string, string> | null): HttpResponseLike;
}

/** Cookie 读写（生产实现包 `@ohos.web.webview` 的 WebCookieManager）。 */
export interface ProfileCookieJar {
  /** 回写 Set-Cookie（上游 `syncCookiesFromResponse`）。 */
  setCookie(url: string, cookie: string): void;
  /** 读域名下的 cookie（上游 `manager.getCookie(HOST_E)`）。 */
  getCookie(host: string): string;
}

/**
 * 取个人资料的场景（对位上游 `GetProfileScene`）。
 */
export class GetProfileScene {
  /** 上游 `needShowLeftDrawer() = false`（本场景不显示左侧抽屉）。 */
  static readonly NEED_SHOW_LEFT_DRAWER: boolean = false;

  /** 要加载的起始页（上游 `EhUrl.URL_FORUMS`）。 */
  static readonly START_URL: string = EhUrl.URL_FORUMS;

  /** 取 cookie 用的 host（上游 `EhUrl.HOST_E`）。 */
  static readonly COOKIE_HOST: string = EhUrl.HOST_E;

  /**
   * 注入的 JS（上游 `readPageContent` 里 `evaluateJavascript` 的那段）。
   *
   * 上游有一大段被注释掉的"结构化 JSON"方案（title/url/html/text/metaDescription/links），
   * **实际生效的只有返回 outerHTML**。这里逐字保留生效版本 —— 改成结构化 JSON 会让
   * `ProfileParser.parseNew` 收到非 HTML 文本。
   */
  static readonly READ_CONTENT_JS: string =
    '(function() { return document.documentElement.outerHTML; })();';

  /** 是否用 SNI 版 WebViewClient（上游 `Settings.getDF() && AppHelper.checkVPN(context)`）。 */
  static useSniClient(dfEnabled: boolean, vpnConnected: boolean): boolean {
    return dfEnabled && vpnConnected;
  }

  /**
   * 要不要拦截这个请求（上游 `shouldInterceptRequest` 的第一段）。
   *
   * 只拦 `http://` / `https://`：`file://`、`data:`、`blob:` 等一律放行。
   */
  static shouldInterceptUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /**
   * 推断请求方法（上游 `getRequestMethod`）。
   *
   * 优先级：`X-HTTP-Method-Override` > `X-Method-Override` > FORM 类型 → POST >
   * 有表单参数 → POST > GET。**override 头会 upperCase**。
   */
  static inferMethod(request: WebRequestLike): string {
    const override: string | undefined = request.headers.get('X-HTTP-Method-Override');
    if (override !== undefined && override.length > 0) {
      return override.toUpperCase();
    }
    const override2: string | undefined = request.headers.get('X-Method-Override');
    if (override2 !== undefined && override2.length > 0) {
      return override2.toUpperCase();
    }
    if (request.type === WebRequestType.FORM) {
      return 'POST';
    }
    return request.formParameters.size > 0 ? 'POST' : 'GET';
  }

  /**
   * 3xx + 有 `Location` → 把跳转交还 WebView（返回 true = 我们不处理）。
   *
   * 上游还要求 `body() == null` 时抛 `IOException("请求结果为空")` —— 这里一并建模：
   * `planInterception` 会先判重定向，再判空 body。
   */
  static isRedirectToPassThrough(statusCode: number, location: string | null): boolean {
    if (statusCode < 300 || statusCode > 399) {
      return false;
    }
    return location !== null && location.length > 0;
  }

  /**
   * 整体拦截决策 + 方法/表单（把上游 `shouldInterceptRequest` 的控制流压成纯函数）。
   *
   * @returns `null` 表示放行给 WebView；否则给出要发的请求参数
   */
  static planInterception(request: WebRequestLike): InterceptPlan | null {
    if (!GetProfileScene.shouldInterceptUrl(request.url)) {
      return null;
    }
    const method: string = GetProfileScene.inferMethod(request);
    // 上游 `handleRequestWithBody`：有表单参数就按表单发（不论 type）
    const form: Map<string, string> | null =
      request.formParameters.size > 0 ? request.formParameters : null;
    return new InterceptPlan(method, request.url, request.headers, form);
  }

  /**
   * 把 OkHttp 响应的形态转成"WebView 响应计划"（上游 `convertOkHttpResponse`）。
   *
   * 三处细节全部保留：
   *   ① `mimeType` = `contentType.split(";")[0]`（含 charset 时只取前半）；
   *   ② 编码从 `contentType` 的 `charset=` 取，**缺省 UTF-8**；
   *   ③ `reasonPhrase` 为空 → 用 `defaultReasonPhrase(statusCode)` 补。
   */
  static toWebResponse(response: HttpResponseLike): WebResponsePlan {
    const contentType: string = response.contentType.length > 0 ? response.contentType : 'text/html';
    const mimeType: string = contentType.split(';')[0].trim();
    const encoding: string = GetProfileScene.encodingOf(contentType);
    const reason: string = response.message.length > 0
      ? response.message
      : GetProfileScene.defaultReasonPhrase(response.code);
    return new WebResponsePlan(mimeType, encoding, response.code, reason, response.headers,
      response.body);
  }

  /**
   * 从 `Content-Type` 里取编码（上游：`encoding` 缺省 `UTF-8`，出现 `charset=` 时取它）。
   *
   * 上游还处理了 `text/plain` 无 charset 的情形 —— 同样落到 UTF-8。
   */
  static encodingOf(contentType: string): string {
    const lower: string = contentType.toLowerCase();
    const idx: number = lower.indexOf('charset=');
    if (idx < 0) {
      return 'UTF-8';
    }
    let value: string = contentType.substring(idx + 'charset='.length).trim();
    const semi: number = value.indexOf(';');
    if (semi >= 0) {
      value = value.substring(0, semi).trim();
    }
    // 去掉可能的引号
    if (value.length >= 2 && (value.startsWith('"') || value.startsWith('\''))) {
      value = value.substring(1, value.length - 1);
    }
    return value.length > 0 ? value.toUpperCase() : 'UTF-8';
  }

  /**
   * 页面加载完成后的动作（上游 `onPageFinished`）。
   *
   * 两道前置判空：context 失效 → 不动；`HttpUrl.parse(url)` 失败（非合法 http(s) URL）→ 不动。
   * 上游还用 `HttpUrl.parse` 的返回值做了"必须是合法 URL"的判定，所以这里用同样的规则。
   */
  static planPageFinished(contextAlive: boolean, url: string): PageFinishedAction {
    if (!contextAlive) {
      return PageFinishedAction.NONE;
    }
    if (!GetProfileScene.isParsableHttpUrl(url)) {
      return PageFinishedAction.NONE;
    }
    return PageFinishedAction.READ_CONTENT;
  }

  /** `HttpUrl.parse(url) != null` 的等价判定（必须是 http/https 且带 host）。 */
  static isParsableHttpUrl(url: string): boolean {
    if (!GetProfileScene.shouldInterceptUrl(url)) {
      return false;
    }
    const schemeEnd: number = url.indexOf('://');
    if (schemeEnd < 0) {
      return false;
    }
    const rest: string = url.substring(schemeEnd + 3);
    const hostEnd: number = rest.search('[/?#]');
    const host: string = hostEnd < 0 ? rest : rest.substring(0, hostEnd);
    return host.length > 0;
  }

  /**
   * 解析注入 JS 取回的 HTML（上游 `readPageContent` 的回调）。
   *
   * 上游：`ProfileParser.parseNew(json)` → `displayName` / `avatar` → setResult；
   * 失败（JSONException / ParseException）**只记录，不改变流程**（页面停在那里）。
   *
   * @param json `evaluateJavascript` 的原始回调值（注意：上游把 outerHTML 当"json"传进来，
   *             变量名叫 json 但内容是 HTML —— 保留这个事实，别改名成 html 以免误以为要 JSON.parse）
   * @returns 解析成功的结果；失败返回 null
   */
  static parsePageContent(json: string | null): ProfileResult | null {
    if (json === null || json.length === 0) {
      return null;
    }
    try {
      const result = ProfileParser.parseNew(json);
      return new ProfileResult(result.displayName, result.avatar);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'profile parse failed: %{public}s', `${e}`);
      return null;
    }
  }

  /**
   * 回写 Set-Cookie（上游 `syncCookiesFromResponse`）。
   *
   * @returns 实际回写的 cookie 条数（便于调用方/测试断言）
   */
  static syncCookies(response: HttpResponseLike, jar: ProfileCookieJar, url: string): number {
    const raw: string | undefined = response.headers.get('Set-Cookie');
    if (raw === undefined || raw.length === 0) {
      return 0;
    }
    // 上游遍历 `headers("Set-Cookie")` 的每一条；这里用换行分隔建模多值
    const parts: string[] = raw.split('\n');
    let count: number = 0;
    for (let i = 0; i < parts.length; i++) {
      const cookie: string = parts[i].trim();
      if (cookie.length > 0) {
        jar.setCookie(url, cookie);
        count++;
      }
    }
    return count;
  }

  /**
   * 完整的一次拦截执行（上游 `shouldInterceptRequest` 的全部控制流）。
   *
   * 顺序照上游：非 http(s) 放行 → 建请求 → 3xx 有 Location 放行 → 空 body 视为失败 →
   * 同步 cookie → 转响应。任何异常 → 放行（回退 WebView 默认网络栈）。
   *
   * @returns `null` = 交给 WebView；否则是要回填的响应计划
   */
  static intercept(request: WebRequestLike, executor: ProfileHttpExecutor,
    jar: ProfileCookieJar): WebResponsePlan | null {
    const plan: InterceptPlan | null = GetProfileScene.planInterception(request);
    if (plan === null) {
      return null;
    }
    let response: HttpResponseLike;
    try {
      response = executor.execute(plan.method, plan.url, plan.headers, plan.form);
    } catch (e) {
      // 上游：IOException → recordException + return null（回退默认网络栈）
      hilog.error(DOMAIN, TAG, 'request failed for %{public}s: %{public}s', request.url, `${e}`);
      return null;
    }
    const location: string | undefined = response.headers.get('Location');
    if (GetProfileScene.isRedirectToPassThrough(response.code,
      location === undefined ? null : location)) {
      // 上游：close() 后 return null，让 WebView 自己跟跳转
      return null;
    }
    if (response.body === null) {
      hilog.error(DOMAIN, TAG, 'empty body for %{public}s (code=%{public}d)',
        request.url, response.code);
      return null;
    }
    GetProfileScene.syncCookies(response, jar, request.url);
    return GetProfileScene.toWebResponse(response);
  }

  /**
   * HTTP 状态码的默认原因短语（上游 `defaultReasonPhrase`，逐条照搬）。
   *
   * 未列出的码返回 `""`（上游 `when` 的 else 分支）。
   */
  static defaultReasonPhrase(statusCode: number): string {
    switch (statusCode) {
      case 100: return 'Continue';
      case 101: return 'Switching Protocols';
      case 102: return 'Processing';
      case 200: return 'OK';
      case 201: return 'Created';
      case 202: return 'Accepted';
      case 203: return 'Non-Authoritative Information';
      case 204: return 'No Content';
      case 205: return 'Reset Content';
      case 206: return 'Partial Content';
      case 300: return 'Multiple Choices';
      case 301: return 'Moved Permanently';
      case 302: return 'Found';
      case 303: return 'See Other';
      case 304: return 'Not Modified';
      case 305: return 'Use Proxy';
      case 307: return 'Temporary Redirect';
      case 308: return 'Permanent Redirect';
      case 400: return 'Bad Request';
      case 401: return 'Unauthorized';
      case 402: return 'Payment Required';
      case 403: return 'Forbidden';
      case 404: return 'Not Found';
      case 405: return 'Method Not Allowed';
      case 406: return 'Not Acceptable';
      case 407: return 'Proxy Authentication Required';
      case 408: return 'Request Timeout';
      case 409: return 'Conflict';
      case 410: return 'Gone';
      case 411: return 'Length Required';
      case 412: return 'Precondition Failed';
      case 413: return 'Payload Too Large';
      case 414: return 'URI Too Long';
      case 415: return 'Unsupported Media Type';
      case 416: return 'Range Not Satisfiable';
      case 417: return 'Expectation Failed';
      case 418: return 'I\'m a teapot';
      case 421: return 'Misdirected Request';
      case 422: return 'Unprocessable Entity';
      case 423: return 'Locked';
      case 424: return 'Failed Dependency';
      case 426: return 'Upgrade Required';
      case 428: return 'Precondition Required';
      case 429: return 'Too Many Requests';
      case 431: return 'Request Header Fields Too Large';
      case 451: return 'Unavailable For Legal Reasons';
      case 500: return 'Internal Server Error';
      case 501: return 'Not Implemented';
      case 502: return 'Bad Gateway';
      case 503: return 'Service Unavailable';
      case 504: return 'Gateway Timeout';
      case 505: return 'HTTP Version Not Supported';
      case 506: return 'Variant Also Negotiates';
      case 507: return 'Insufficient Storage';
      case 508: return 'Loop Detected';
      case 510: return 'Not Extended';
      case 511: return 'Network Authentication Required';
      default: return '';
    }
  }
}

/** 一次拦截要发的请求（`planInterception` 的结果）。 */
export class InterceptPlan {
  method: string;
  url: string;
  headers: Map<string, string>;
  /** 表单参数；非表单请求为 null（上游 `RequestBody? = null`）。 */
  form: Map<string, string> | null;

  constructor(method: string, url: string, headers: Map<string, string>,
    form: Map<string, string> | null) {
    this.method = method;
    this.url = url;
    this.headers = headers;
    this.form = form;
  }
}
