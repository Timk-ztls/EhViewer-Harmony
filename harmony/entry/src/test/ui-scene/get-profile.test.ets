/*
 * download-sync 接手批单测：GetProfileScene（S0259，517 行）的纯逻辑
 *
 * 钉住六条"写错也能编译、但页面会白/会卡"的语义：
 *   1. 只拦 http(s)；file:// / data: 一律放行（否则页面内联资源全白）
 *   2. 方法推断优先级：override 头 > FORM→POST > 有表单参数→POST > GET
 *   3. 3xx + 有 Location → 交还 WebView（不自己跟跳转）
 *   4. mimeType 取 contentType 分号前；编码缺省 UTF-8；reasonPhrase 为空要补
 *   5. onPageFinished 两道前置判空（context / 合法 URL）
 *   6. 解析失败只记录、不改流程
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  GetProfileScene, WebRequestLike, WebRequestType, HttpResponseLike, InterceptPlan,
  PageFinishedAction, ProfileCookieJar, ProfileHttpExecutor, WebResponsePlan, ProfileResult,
  REQUEST_CODE_PROFILE, DISPLAY_NAME, AVATAR
} from '../../main/ets/hippo/ehviewer/ui/scene/sign/GetProfileScene';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}  (want true)`);
  }
}

// ---------------------------------------------------------------- 假实现

class FakeJar implements ProfileCookieJar {
  set: string[] = [];
  setCookie(url: string, cookie: string): void {
    this.set.push(`${url}|${cookie}`);
  }
  getCookie(host: string): string {
    return `cookie_for_${host}`;
  }
}

class FakeExecutor implements ProfileHttpExecutor {
  calls: string[] = [];
  /** 下一次返回的响应 */
  next: HttpResponseLike | null = null;
  throwOnExecute: boolean = false;

  execute(method: string, url: string, headers: Map<string, string>,
    form: Map<string, string> | null): HttpResponseLike {
    this.calls.push(`${method} ${url} form=${form === null ? 0 : form.size}`);
    if (this.throwOnExecute) {
      throw new Error('network down');
    }
    return this.next as HttpResponseLike;
  }
}

function headersOf(map: Map<string, string>, key: string, value: string): Map<string, string> {
  map.set(key, value);
  return map;
}

function req(url: string, type: WebRequestType, headers: Map<string, string>,
  form: Map<string, string>): WebRequestLike {
  return new WebRequestLike(url, headers, type, form);
}

function response(code: number, message: string, contentType: string, setCookie: string | null,
  location: string | null): HttpResponseLike {
  const h: Map<string, string> = new Map<string, string>();
  if (setCookie !== null) {
    h.set('Set-Cookie', setCookie);
  }
  if (location !== null) {
    h.set('Location', location);
  }
  return new HttpResponseLike(code, message, h, contentType, new ArrayBuffer(4));
}

// ---------------------------------------------------------------- 常量

function testConstants(): void {
  eq('REQUEST_CODE_PROFILE 与上游一致（0x000F）', REQUEST_CODE_PROFILE, 0x000F);
  eq('DISPLAY_NAME 键', DISPLAY_NAME, 'displayName');
  eq('AVATAR 键', AVATAR, 'avatar');
  eq('本场景不显示左侧抽屉', GetProfileScene.NEED_SHOW_LEFT_DRAWER, false);
  eq('起始页是论坛首页', GetProfileScene.START_URL, 'https://forums.e-hentai.org/');
  ok('JS 只返回 outerHTML（不含被注释掉的结构化方案）',
    GetProfileScene.READ_CONTENT_JS.includes('document.documentElement.outerHTML'));
  ok('JS 里不含 title/links 那些被注释掉的字段',
    !GetProfileScene.READ_CONTENT_JS.includes('metaDescription'));
}

// ---------------------------------------------------------------- 拦截范围

function testInterceptScope(): void {
  eq('https 拦', GetProfileScene.shouldInterceptUrl('https://e-hentai.org/x'), true);
  eq('http 拦', GetProfileScene.shouldInterceptUrl('http://e-hentai.org/x'), true);
  eq('file:// 放行', GetProfileScene.shouldInterceptUrl('file:///android_asset/a.html'), false);
  eq('data: 放行', GetProfileScene.shouldInterceptUrl('data:text/html,<b>x</b>'), false);
  eq('blob: 放行', GetProfileScene.shouldInterceptUrl('blob:https://x/y'), false);

  const jar: FakeJar = new FakeJar();
  const ex: FakeExecutor = new FakeExecutor();
  eq('非 http(s) 请求不进执行器',
    GetProfileScene.intercept(req('file:///a', WebRequestType.OTHER, new Map(), new Map()), ex, jar),
    null);
  eq('执行器没被调用', ex.calls.length, 0);
}

// ---------------------------------------------------------------- 方法推断

function testInferMethod(): void {
  const empty: Map<string, string> = new Map<string, string>();
  const form: Map<string, string> = new Map<string, string>([['a', '1']]);

  eq('X-HTTP-Method-Override 优先且大写',
    GetProfileScene.inferMethod(req('https://x', WebRequestType.OTHER,
      headersOf(new Map(), 'X-HTTP-Method-Override', 'put'), empty)), 'PUT');
  eq('X-Method-Override 次之',
    GetProfileScene.inferMethod(req('https://x', WebRequestType.OTHER,
      headersOf(new Map(), 'X-Method-Override', 'delete'), empty)), 'DELETE');
  eq('FORM 类型 → POST',
    GetProfileScene.inferMethod(req('https://x', WebRequestType.FORM, empty, empty)), 'POST');
  eq('有表单参数 → POST（即使类型是 OTHER）',
    GetProfileScene.inferMethod(req('https://x', WebRequestType.OTHER, empty, form)), 'POST');
  eq('都没有 → GET',
    GetProfileScene.inferMethod(req('https://x', WebRequestType.HTML, empty, empty)), 'GET');
  eq('override 头压过 FORM 类型',
    GetProfileScene.inferMethod(req('https://x', WebRequestType.FORM,
      headersOf(new Map(), 'X-HTTP-Method-Override', 'patch'), form)), 'PATCH');
}

// ---------------------------------------------------------------- 拦截计划

function testInterceptPlan(): void {
  const empty: Map<string, string> = new Map<string, string>();
  const form: Map<string, string> = new Map<string, string>([['username', 'u'], ['password', 'p']]);
  const plan: InterceptPlan | null = GetProfileScene.planInterception(
    req('https://forums.e-hentai.org/login', WebRequestType.FORM,
      headersOf(new Map(), 'Range', 'bytes=0-99'), form));
  ok('http(s) 表单请求会被拦截', plan !== null);
  eq('方法 POST', plan === null ? null : plan.method, 'POST');
  eq('表单参数带过去', plan === null ? null : (plan.form === null ? 0 : plan.form.size), 2);
  eq('Range 头保留（断点续传）',
    plan === null ? null : plan.headers.get('Range'), 'bytes=0-99');

  const getPlan: InterceptPlan | null = GetProfileScene.planInterception(
    req('https://forums.e-hentai.org/index', WebRequestType.HTML, new Map(), empty));
  eq('无表单的 GET 请求 form 为 null', getPlan === null ? 'null' : getPlan.form, null);
  eq('GET 方法', getPlan === null ? null : getPlan.method, 'GET');
}

// ---------------------------------------------------------------- 重定向与响应转换

function testRedirectAndConvert(): void {
  eq('302 + Location → 交还 WebView', GetProfileScene.isRedirectToPassThrough(302, 'https://y'), true);
  eq('301 + Location → 交还', GetProfileScene.isRedirectToPassThrough(301, 'https://y'), true);
  eq('302 无 Location → 不交还', GetProfileScene.isRedirectToPassThrough(302, null), false);
  eq('200 + Location → 不交还（不是 3xx）',
    GetProfileScene.isRedirectToPassThrough(200, 'https://y'), false);
  eq('399 边界算 3xx', GetProfileScene.isRedirectToPassThrough(399, 'x'), true);
  eq('400 不算', GetProfileScene.isRedirectToPassThrough(400, 'x'), false);

  // mimeType / encoding / reasonPhrase
  const r1: WebResponsePlan = GetProfileScene.toWebResponse(
    response(200, 'OK', 'text/html; charset=utf-8', null, null));
  eq('mimeType 取分号前', r1.mimeType, 'text/html');
  eq('编码取 charset', r1.encoding, 'UTF-8');
  eq('状态码', r1.statusCode, 200);
  eq('有 message 时用 message', r1.reasonPhrase, 'OK');

  const r2: WebResponsePlan = GetProfileScene.toWebResponse(
    response(404, '', 'application/json', null, null));
  eq('空 message → 用默认短语', r2.reasonPhrase, 'Not Found');
  eq('无 charset → 缺省 UTF-8', r2.encoding, 'UTF-8');
  eq('mimeType 取 application/json', r2.mimeType, 'application/json');

  const r3: WebResponsePlan = GetProfileScene.toWebResponse(
    response(200, 'OK', '', null, null));
  eq('contentType 为空 → 缺省 text/html', r3.mimeType, 'text/html');

  // encoding 细节
  eq('charset 带引号', GetProfileScene.encodingOf('text/html; charset="gbk"'), 'GBK');
  eq('charset 后面还有参数', GetProfileScene.encodingOf('text/html; charset=Shift_JIS; x=1'),
    'SHIFT_JIS');
  eq('charset 大小写不敏感', GetProfileScene.encodingOf('text/html; CHARSET=Big5'), 'BIG5');
  eq('没有 charset', GetProfileScene.encodingOf('text/plain'), 'UTF-8');

  // 默认原因短语表
  eq('100', GetProfileScene.defaultReasonPhrase(100), 'Continue');
  eq('206', GetProfileScene.defaultReasonPhrase(206), 'Partial Content');
  eq('418', GetProfileScene.defaultReasonPhrase(418), 'I\'m a teapot');
  eq('503', GetProfileScene.defaultReasonPhrase(503), 'Service Unavailable');
  eq('未列出的码 → 空串', GetProfileScene.defaultReasonPhrase(299), '');
}

// ---------------------------------------------------------------- 完整拦截流程

function testInterceptFlow(): void {
  const jar: FakeJar = new FakeJar();
  const ex: FakeExecutor = new FakeExecutor();

  // ① 正常 200 + Set-Cookie → 回填响应并同步 cookie
  ex.next = response(200, 'OK', 'text/html; charset=utf-8',
    'sid=abc; Path=/\nuid=42; Path=/', null);
  const plan: WebResponsePlan | null = GetProfileScene.intercept(
    req('https://forums.e-hentai.org/x', WebRequestType.HTML, new Map(), new Map()), ex, jar);
  ok('200 被拦截并转换', plan !== null);
  eq('cookie 回写两条', jar.set.length, 2);
  ok('cookie 带着 url', jar.set[0].startsWith('https://forums.e-hentai.org/x|'));
  eq('响应码传到响应计划', plan === null ? null : plan.statusCode, 200);

  // ② 302 + Location → 放行
  const jar2: FakeJar = new FakeJar();
  const ex2: FakeExecutor = new FakeExecutor();
  ex2.next = response(302, 'Found', 'text/html', 'a=1', 'https://forums.e-hentai.org/next');
  eq('302 有 Location → 放行（不自己跟跳转）',
    GetProfileScene.intercept(req('https://x/y', WebRequestType.HTML, new Map(), new Map()),
      ex2, jar2), null);
  eq('放行时不写 cookie', jar2.set.length, 0);

  // ③ 空 body → 视为失败并放行
  const ex3: FakeExecutor = new FakeExecutor();
  ex3.next = new HttpResponseLike(200, 'OK', new Map(), 'text/html', null);
  eq('空 body → 放行（上游抛 IOException 后回退）',
    GetProfileScene.intercept(req('https://x/y', WebRequestType.HTML, new Map(), new Map()),
      ex3, new FakeJar()), null);

  // ④ 执行器抛错 → 放行
  const ex4: FakeExecutor = new FakeExecutor();
  ex4.throwOnExecute = true;
  eq('请求抛错 → 放行（回退 WebView 默认网络栈）',
    GetProfileScene.intercept(req('https://x/y', WebRequestType.HTML, new Map(), new Map()),
      ex4, new FakeJar()), null);
}

// ---------------------------------------------------------------- 页面完成

function testPageFinished(): void {
  eq('context 失效 → 不动',
    GetProfileScene.planPageFinished(false, 'https://forums.e-hentai.org/'),
    PageFinishedAction.NONE);
  eq('url 非法（非 http）→ 不动',
    GetProfileScene.planPageFinished(true, 'about:blank'), PageFinishedAction.NONE);
  eq('http 但无 host → 不动',
    GetProfileScene.planPageFinished(true, 'http:///path'), PageFinishedAction.NONE);
  eq('正常 → 读页面内容',
    GetProfileScene.planPageFinished(true, 'https://forums.e-hentai.org/index.php'),
    PageFinishedAction.READ_CONTENT);

  eq('合法 url 判定：带端口也算', GetProfileScene.isParsableHttpUrl('http://host:8080/a'), true);
  eq('合法 url 判定：带 query', GetProfileScene.isParsableHttpUrl('https://h/p?q=1'), true);
  eq('非法：只有scheme', GetProfileScene.isParsableHttpUrl('https://'), false);
}

// ---------------------------------------------------------------- 内容解析

function testParseContent(): void {
  eq('null → null', GetProfileScene.parsePageContent(null), null);
  eq('空串 → null', GetProfileScene.parsePageContent(''), null);
  // 缺少 `#userlinks` 时 ProfileParser 抛 ParseException → 本层捕获后返回 null，
  // **流程不变**（上游 `catch (_: ParseException) {}` 就是这样：页面停在那里，不 setResult）
  eq('缺 #userlinks → 解析失败返回 null（上游 catch ParseException 后什么都不做）',
    GetProfileScene.parsePageContent('<html><body>no profile</body></html>'), null);

  // 有 #userlinks 时能解析出 displayName；没有头像兄弟节点 → avatar 保持 null
  // 注意：局部变量不能叫 ok —— 会遮蔽上面的 ok() 断言函数（第一次就踩了，tsc 报 "not callable"）
  const parsed: ProfileResult | null = GetProfileScene.parsePageContent(
    '<html><body><div id="userlinks"><div><div><b>Alice</b></div></div></div></body></html>');
  ok('有 #userlinks → 解析成功', parsed !== null);
  eq('displayName 取深层 child 的文本', parsed === null ? null : parsed.displayName, 'Alice');
  eq('avatar 缺失时为 null（可空字段）', parsed === null ? null : parsed.avatar, null);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testConstants();
  testInterceptScope();
  testInferMethod();
  testInterceptPlan();
  testRedirectAndConvert();
  testInterceptFlow();
  testPageFinished();
  testParseContent();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync get profile test failed');
  }
  console.log(`✓ download-sync 资料页批: ${pass} 条断言全部通过`);
}

main();
