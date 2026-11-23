// EhEngine 第 1 批（骨架 + 4 个 API）测试
//
// 重点在**参数拼装**与**容错链顺序**——这是 EhEngine 1472 行的主要风险面。
// 用假 HttpCaller 捕获 Request（URL/headers/body/method），不需要真网络。

import {
  EhEngine, EhEngineConfig, EngineCall, EngineHeaders, EngineResponse, EngineTask, HttpCaller
} from '../EhEngine';
import { Request } from '../../../okhttp/Request';
import { FormBody } from '../../../okhttp/FormBody';
import { EhException } from '../exception/EhException';
import { CancelledException } from '../exception/MarkerExceptions';
import { ParseException } from '../exception/ParseException';
import { StatusCodeException } from '../../../network/StatusCodeException';
import { GalleryInfo } from './GalleryInfo';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

async function rejects(name: string, fn: () => Promise<unknown>, ctor: Function): Promise<void> {
  try {
    await fn();
    fail++;
    failures.push(name + '（未抛异常）');
  } catch (e) {
    if (e instanceof ctor) {
      pass++;
    } else {
      fail++;
      failures.push(name + `（抛的是 ${(e as Error).name}: ${(e as Error).message}）`);
    }
  }
}

// ---------- 假基础设施 ----------
class FakeHeaders implements EngineHeaders {
  private map = new Map<string, string>();

  constructor(init?: Record<string, string>) {
    if (init) {
      for (const k of Object.keys(init)) {
        this.map.set(k, init[k]);
      }
    }
  }

  get(name: string): string | null {
    const v = this.map.get(name);
    return v === undefined ? null : v;
  }
}

class FakeCall implements EngineCall {
  canceled = false;
  constructor(private response: EngineResponse | Error, public request: Request) { }

  async execute(): Promise<EngineResponse> {
    if (this.response instanceof Error) {
      throw this.response;
    }
    return this.response;
  }

  isCanceled(): boolean {
    return this.canceled;
  }

  cancel(): void {
    this.canceled = true;
  }
}

class FakeResponse implements EngineResponse {
  constructor(private _code: number, private _headers: EngineHeaders, private _body: string) { }

  code(): number {
    return this._code;
  }

  headers(): EngineHeaders {
    return this._headers;
  }

  body(): string {
    return this._body;
  }
}

class FakeCaller implements HttpCaller {
  requests: Request[] = [];
  lastCall: FakeCall | null = null;

  constructor(private responder: (req: Request) => FakeResponse | Error) { }

  newCall(request: Request): EngineCall {
    this.requests.push(request);
    const call = new FakeCall(this.responder(request), request);
    this.lastCall = call;
    return call;
  }
}

function task(): EngineTask {
  return {
    setCall: (): void => { /* 记录用 */ }
  };
}

function headerOf(req: Request, name: string): string | null {
  return req.headers().get(name);
}

function formOf(req: Request): FormBody {
  return req.body() as FormBody;
}

function formValue(req: Request, name: string): string | null {
  const f = formOf(req);
  for (let i = 0; i < f.size(); i++) {
    if (f.name(i) === name) {
      return f.value(i);
    }
  }
  return null;
}

async function main(): Promise<void> {
  // ---------- 1. doThrowException 容错链 ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, new FakeHeaders(), ''));
    const call = caller.newCall(null as unknown as Request) as FakeCall;

    // ① 已取消优先于一切
    call.canceled = true;
    try {
      EhEngine.doThrowException(call, 500, null, 'x', new Error('boom'));
      ok('cancel 应抛', false);
    } catch (e) {
      ok('已取消 → CancelledException（优先于 code>=400）', e instanceof CancelledException);
    }
    call.canceled = false;

    // ② sad panda 三头同时匹配
    const sadHeaders = new FakeHeaders({
      'Content-Disposition': 'inline; filename="sadpanda.jpg"',
      'Content-Type': 'image/gif',
      'Content-Length': '9615'
    });
    try {
      EhEngine.doThrowException(call, 200, sadHeaders, null, null);
      ok('sad panda 应抛', false);
    } catch (e) {
      ok('sad panda → EhException("Sad Panda")',
        e instanceof EhException && (e as Error).message === 'Sad Panda');
    }

    // 三头只匹配两个 → 不算 sad panda
    const partial = new FakeHeaders({
      'Content-Disposition': 'inline; filename="sadpanda.jpg"',
      'Content-Type': 'image/gif'
    });
    try {
      EhEngine.doThrowException(call, 200, partial, 'ok', null);
      ok('三头不齐不算 sad panda', true);
    } catch (e) {
      ok('三头不齐不算 sad panda', false);
    }

    // ③ kokomade
    try {
      EhEngine.doThrowException(call, 200, null, 'xx https://exhentai.org/img/kokomade.jpg yy', null);
      ok('kokomade 应抛', false);
    } catch (e) {
      ok('kokomade → 消息含「今回はここまで」',
        (e as Error).message.indexOf('今回はここまで') === 0);
    }

    // ④ ParseException 三分支
    try {
      EhEngine.doThrowException(call, 200, null, 'plain text no html', new ParseException('pf', 'b'));
      ok('ParseException 应抛', false);
    } catch (e) {
      ok('ParseException + body 无 < → 用 body 当消息', (e as Error).message === 'plain text no html');
    }
    try {
      EhEngine.doThrowException(call, 200, null, '', new ParseException('pf', 'b'));
      ok('ParseException 应抛', false);
    } catch (e) {
      // 上游判定顺序：body != null && !contains('<') 在前，空串也满足 → 消息为空串（不是 Empty html）
      ok('ParseException + body 空 → 消息为空串（顺序照搬）', (e as Error).message === '');
    }
    try {
      EhEngine.doThrowException(call, 200, null, '<html></html>', new ParseException('pf', 'b'));
      ok('ParseException 应抛', false);
    } catch (e) {
      ok('ParseException + 有 html → parse error', (e as Error).message === 'Parse error');
    }

    // ⑤ EhException 原样抛
    try {
      EhEngine.doThrowException(call, 200, null, null, new EhException('custom'));
      ok('EhException 应抛', false);
    } catch (e) {
      ok('EhException 原样抛', (e as Error).message === 'custom');
    }

    // ⑥ code >= 400
    try {
      EhEngine.doThrowException(call, 503, null, null, new Error('net'));
      ok('>=400 应抛', false);
    } catch (e) {
      ok('code>=400 → StatusCodeException(503)',
        e instanceof StatusCodeException && (e as StatusCodeException).getResponseCode() === 503);
    }

    // ⑦ 其它异常原样抛
    try {
      EhEngine.doThrowException(call, 200, null, null, new Error('raw'));
      ok('其它应抛', false);
    } catch (e) {
      ok('其它 Error 原样抛', (e as Error).message === 'raw');
    }
  }

  // ---------- 2. signIn 参数拼装 ----------
  {
    const caller = new FakeCaller(() =>
      new FakeResponse(200, new FakeHeaders(), '<p>You are now logged in as: someone<'));
    const result = await EhEngine.signIn(task(), caller, 'user name', 'p@ss');
    eq('signIn 返回用户名', result, 'someone');

    const req = caller.requests[0];
    eq('signIn URL', req.url().toString(), 'https://forums.e-hentai.org/index.php?act=Login&CODE=01');
    eq('signIn Referer', headerOf(req, 'Referer'), 'https://forums.e-hentai.org/index.php?act=Login&CODE=00');
    eq('signIn Origin', headerOf(req, 'Origin'), 'https://forums.e-hentai.org');
    eq('signIn method', req.method(), 'POST');
    eq('signIn form UserName（空格→+）', formValue(req, 'UserName'), 'user+name');
    eq('signIn form CookieDate', formValue(req, 'CookieDate'), '1');
    eq('signIn form submit', formValue(req, 'submit'), 'Log+me+in');
    eq('signIn form temporary_https', formValue(req, 'temporary_https'), 'off');
    eq('signIn form 字段数', formOf(req).size(), 5);
  }

  // ---------- 3. getGalleryList 参数 + 容错 ----------
  {
    const listHtml = '<html><body><div class="itg gld">' +
      '<div class="gl1e"><div class="glink glname">' +
      '<a href="https://e-hentai.org/g/1234567/abcdef0123/">T</a></div></div></div></body></html>';
    const caller = new FakeCaller(() => new FakeResponse(200, new FakeHeaders(), listHtml));
    const r = await EhEngine.getGalleryList(null, caller, 'https://e-hentai.org/', 0);
    eq('list 解析出 1 项', r.galleryInfoList.length, 1);
    eq('list Referer', headerOf(caller.requests[0], 'Referer'), 'https://e-hentai.org');
    eq('list gid', r.galleryInfoList[0].gid, 1234567);

    // 200 + 空 body + exhentai 首页 → customErrorString（igneous 失效提示）
    const caller2 = new FakeCaller(() => new FakeResponse(200, new FakeHeaders(), ''));
    const r2 = await EhEngine.getGalleryList(null, caller2, 'https://exhentai.org/', 0);
    eq('exhentai 空 body → customErrorString', r2.customErrorString, 'Igneous wrong');

    // 403：GalleryListParser.parse(String) 会吞异常 → 返回空列表且**不抛**（StatusCodeException 只在
    // 「解析抛异常 → throwException 里 code>=400」这条路径出现，已在容错链测试覆盖）
    const caller3 = new FakeCaller(() => new FakeResponse(403, new FakeHeaders(), 'forbidden'));
    const r3 = await EhEngine.getGalleryList(null, caller3, 'https://e-hentai.org/', 0);
    eq('403 → 空列表且不抛', r3.galleryInfoList.length, 0);
  }

  // ---------- 4. getGalleryDetail ----------
  {
    const detailHtml = '<div class="gm"><script>var gid = 42;var token = "aaaaaaaaaa";' +
      'var apiuid = -1;var apikey = "abc";</script></div>';
    const caller = new FakeCaller(() => new FakeResponse(200, new FakeHeaders(), detailHtml));
    await rejects('detail 缺 gdd 结构 → 解析失败（预期）',
      () => EhEngine.getGalleryDetail(null, caller, 'https://e-hentai.org/g/42/aaaaaaaaaa/'), Error);
    eq('detail Referer', headerOf(caller.requests[0], 'Referer'), 'https://e-hentai.org');
  }

  // ---------- 5. getAllFavorites ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, new FakeHeaders(),
      '<p>This page requires you to log on.</p>'));
    await rejects('getAllFavorites 未登录 → EhException',
      () => EhEngine.getAllFavorites(caller, 'https://e-hentai.org/favorites.php'), EhException);
  }

  // ---------- 6. fillGalleryList 的过滤与 API 补齐判定 ----------
  {
    // 没有过滤器 + 无 tags → 不需要 API（filter=false 且 ShowGalleryPages 默认 false）
    const list: GalleryInfo[] = [new GalleryInfo(), new GalleryInfo()];
    list[0].title = 'a'; list[0].thumb = 'https://e-hentai.org/t/aa/bb/aabbccc-250.jpg';
    list[1].title = 'b'; list[1].thumb = 'https://e-hentai.org/t/aa/bb/aabbccc-250.jpg';
    const caller = new FakeCaller(() => new FakeResponse(200, new FakeHeaders(), '{}'));
    await EhEngine.fillGalleryList(null, caller, list, 'https://e-hentai.org/', false);
    eq('filter=false 不删项', list.length, 2);
    eq('不需要 API 补齐 → 不发请求', caller.requests.length, 0);
    ok('缩略图被 getFixedPreviewThumbUrl 修正',
      list[0].thumb.indexOf('https://ehgt.org/') === 0);
  }

  // ---------- 7. fillGalleryListByApiBestEffort（上游 9cbb77f7） ----------
  {
    const list: GalleryInfo[] = [];
    for (let i = 1; i <= 26; i++) {
      const gi = new GalleryInfo();
      gi.gid = i;
      gi.token = `${i}`.padStart(10, '0');
      list.push(gi);
    }
    let callIdx = 0;
    const caller = new FakeCaller((_req) => {
      callIdx++;
      if (callIdx === 1) {
        return new Error('simulated network failure on batch 1');
      }
      return new FakeResponse(200, new FakeHeaders(), JSON.stringify({
        gmetadata: [{
          gid: 26,
          title: 'Batch 2 Gallery',
          title_jpn: '',
          category: 'Doujinshi',
          thumb: 'https://ehgt.org/t/aa.jpg',
          uploader: 'u26',
          posted: '1700000000',
          rating: '4.5',
          tags: ['language:chinese'],
          filecount: '12'
        }]
      }));
    });
    const out = await EhEngine.fillGalleryListByApiBestEffort(null, caller, list, 'https://e-hentai.org/');
    eq('bestEffort 返回原列表', out.length, 26);
    eq('bestEffort 分 2 批发送（25 + 1）', caller.requests.length, 2);
    eq('bestEffort 第 1 批失败不中断第 2 批回填', list[25].title, 'Batch 2 Gallery');
    eq('bestEffort 第 1 批失败项保持原空 title', list[0].title, '');

    const fatalCaller = new FakeCaller((_req) => new RangeError('fatal stack overflow'));
    await rejects('bestEffort 遇到致命错误仍重抛',
      () => EhEngine.fillGalleryListByApiBestEffort(null, fatalCaller, [list[0]], 'https://e-hentai.org/'),
      RangeError);
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhEngine 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
