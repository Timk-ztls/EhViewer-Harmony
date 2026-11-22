// getGalleryPage / getGalleryPageApi 测试（storage-db 的 SpiderQueen 依赖）
//
// 两条最容易被写错的契约：
//   1. getGalleryPageApi 的 JSON 里 page = index + 1
//   2. Referer 只在 index > 0 && previousPToken != null 时才加，且指向 index-1 那一页

import {
  EhEngine, EngineCall, EngineHeaders, EngineResponse, EngineTask, HttpCaller
} from '../EhEngine';
import { Request } from '../../../okhttp/Request';
import { ParseException } from '../exception/ParseException';

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

class FakeHeaders implements EngineHeaders {
  get(): string | null {
    return null;
  }
}

class FakeResponse implements EngineResponse {
  constructor(private _code: number, private _body: string) { }
  code(): number {
    return this._code;
  }
  headers(): EngineHeaders {
    return new FakeHeaders();
  }
  body(): string {
    return this._body;
  }
}

class FakeCall implements EngineCall {
  canceled = false;
  constructor(private response: FakeResponse | Error) { }
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

class FakeCaller implements HttpCaller {
  requests: Request[] = [];
  constructor(private responder: (req: Request) => FakeResponse | Error) { }
  newCall(request: Request): EngineCall {
    this.requests.push(request);
    return new FakeCall(this.responder(request));
  }
}

const task = (): EngineTask => ({ setCall: (): void => { } });

function jsonBody(req: Request): string {
  const b = req.body();
  if (b === null) {
    return '';
  }
  const bytes = new Uint8Array(b.bytes());
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    s += String.fromCharCode(bytes[i]);
  }
  return s;
}

async function main(): Promise<void> {
  // ---------- getGalleryPage ----------
  {
    const html = '<img src="https://x/1.jpg" style="x">' +
      '<a href="#" onclick="return nl(\'hk1\')">s</a>' +
      '<a href="https://x/pfullimgs">o</a>' +
      '<script>var showkey="abc123";</script>';
    const caller = new FakeCaller(() => new FakeResponse(200, html));
    const r = await EhEngine.getGalleryPage(task(), caller,
      'https://e-hentai.org/s/aaaaaaaaaa/42-1', 42, 'bbbbbbbbbb');
    eq('page.imageUrl', r.imageUrl, 'https://x/1.jpg');
    eq('page.skipHathKey', r.skipHathKey, 'hk1');
    eq('page.originImageUrl', r.originImageUrl, 'https://x/pfullimgs');
    eq('page.showKey', r.showKey, 'abc123');
    eq('page Referer = 详情页', caller.requests[0].headers().get('Referer'),
      'https://e-hentai.org/g/42/bbbbbbbbbb/');

    // 缺 showKey → ParseException → 容错链（body 有 '<' → "Parse error"）
    const caller2 = new FakeCaller(() => new FakeResponse(200,
      '<img src="https://x/1.jpg" style="x">'));
    let msg = '';
    try {
      await EhEngine.getGalleryPage(null, caller2, 'https://e-hentai.org/s/x', 1, 't');
    } catch (e) {
      msg = (e as Error).message;
    }
    eq('缺 showKey → 容错链翻译成 Parse error', msg, 'Parse error');
  }

  // ---------- getGalleryPageApi：首页（index=0，不加 Referer）----------
  {
    const payload = JSON.stringify({
      i3: '<img src="https://x/p1.jpg" style="s">',
      i6: '<a href="#" onclick="return nl(\'hk\')">s</a>',
      i7: null
    });
    const caller = new FakeCaller(() => new FakeResponse(200, payload));
    const r = await EhEngine.getGalleryPageApi(task(), caller, 42, 0, 'ptoken', 'showkey', null);
    eq('pageApi.imageUrl', r.imageUrl, 'https://x/p1.jpg');
    eq('pageApi.skipHathKey', r.skipHathKey, 'hk');
    const req = caller.requests[0];
    eq('pageApi URL = api.php', req.url().toString(), 'https://e-hentai.org/api.php');
    ok('pageApi JSON method showpage', jsonBody(req).indexOf('"method":"showpage"') >= 0);
    ok('pageApi JSON page = index+1（0 → 1）', jsonBody(req).indexOf('"page":1') >= 0);
    ok('pageApi JSON imgkey', jsonBody(req).indexOf('"imgkey":"ptoken"') >= 0);
    ok('pageApi JSON showkey', jsonBody(req).indexOf('"showkey":"showkey"') >= 0);
    eq('index=0 → 不加 Referer', req.headers().get('Referer'), null);
    eq('pageApi Origin 仍在', req.headers().get('Origin'), 'https://e-hentai.org');
  }

  // ---------- getGalleryPageApi：index>0 且给 previousPToken → Referer 指上一页 ----------
  {
    const payload = JSON.stringify({ i3: '<img src="https://x/p2.jpg" style="s">', i6: '', i7: null });
    const caller = new FakeCaller(() => new FakeResponse(200, payload));
    await EhEngine.getGalleryPageApi(null, caller, 42, 3, 'cur', 'sk', 'prevptoken');
    const req = caller.requests[0];
    ok('pageApi JSON page = 4', jsonBody(req).indexOf('"page":4') >= 0);
    eq('Referer 指 index-1 页（page=3 因为是 0 基 +1）',
      req.headers().get('Referer'), 'https://e-hentai.org/s/prevptoken/42-3');
  }

  // ---------- getGalleryPageApi：index>0 但 previousPToken=null → 仍不加 Referer ----------
  {
    const payload = JSON.stringify({ i3: '<img src="https://x/p3.jpg" style="s">', i6: '', i7: null });
    const caller = new FakeCaller(() => new FakeResponse(200, payload));
    await EhEngine.getGalleryPageApi(null, caller, 42, 5, 'cur', 'sk', null);
    eq('previousPToken=null → 不加 Referer', caller.requests[0].headers().get('Referer'), null);
  }

  // ---------- getGalleryPageApi：i3 缺 imageUrl → ParseException ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, '{"i3":"","i6":"","i7":null}'));
    let isParse = false;
    try {
      await EhEngine.getGalleryPageApi(null, caller, 1, 0, 'p', 's', null);
    } catch (e) {
      isParse = e instanceof ParseException || (e as Error).message.length > 0;
    }
    ok('i3 无 imageUrl → 抛错（ParseException 或经容错链）', isParse);
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhEngine page 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
