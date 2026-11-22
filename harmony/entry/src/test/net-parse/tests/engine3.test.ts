// EhEngine 第 3 批（5 个 API）测试
//
// getFavorites / addFavorites / addFavoritesRange / modifyFavorites / getTorrentList
// 重点：dstCat 的三种编码（favdel / 分类号 / delete / favN）、
//       表单字段（favcat/favnote/submit/update、ddact/modifygids[]/apply）、
//       addFavoritesRange 的「长度不等即失败」与「串行逐条」、成功路径也走容错链。

import {
  EhEngine, EngineCall, EngineHeaders, EngineResponse, EngineTask, HttpCaller
} from '../EhEngine';
import { Request } from '../../../okhttp/Request';
import { FormBody } from '../../../okhttp/FormBody';
import { EhException } from '../exception/EhException';
import { StatusCodeException } from '../../../network/StatusCodeException';

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

class FakeCall implements EngineCall {
  canceled = false;
  constructor(private response: EngineResponse | Error) { }
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

class FakeCaller implements HttpCaller {
  requests: Request[] = [];
  constructor(private responder: (req: Request) => FakeResponse | Error) { }
  newCall(request: Request): EngineCall {
    this.requests.push(request);
    return new FakeCall(this.responder(request));
  }
}

const task = (): EngineTask => ({ setCall: (): void => { } });

function formValue(req: Request, name: string): string | null {
  const f = req.body() as FormBody;
  for (let i = 0; i < f.size(); i++) {
    if (f.name(i) === name) {
      return f.value(i);
    }
  }
  return null;
}

function formValues(req: Request, name: string): string[] {
  const f = req.body() as FormBody;
  const out: string[] = [];
  for (let i = 0; i < f.size(); i++) {
    if (f.name(i) === name) {
      out.push(f.value(i));
    }
  }
  return out;
}

async function main(): Promise<void> {
  const favHtml = '<html><body><div class="ido">' +
    Array.from({ length: 11 }, (_v, i) =>
      `<div class="fp"><div>${i}</div><div>x</div><div>cat${i}</div></div>`).join('') +
    '</div><table class="ptt"><tbody><tr><td><div>1</div></td><td>1</td><td><a href="?page=1">n</a></td></tr></tbody></table>' +
    '<div class="itg gld"><div class="gl1e"><div class="glink glname">' +
    '<a href="https://e-hentai.org/g/1234567/abcdef0123/">Fav Item</a></div></div></div>' +
    '</body></html>';

  // ---------- getFavorites ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, favHtml));
    const r = await EhEngine.getFavorites(task(), caller, 'https://e-hentai.org/favorites.php', true);
    eq('getFavorites catArray[2]', r.catArray[2], 'cat2');
    eq('getFavorites pages', r.pages, 1);
    eq('getFavorites Referer', caller.requests[0].headers().get('Referer'), 'https://e-hentai.org');
  }

  // ---------- addFavorites：分类 / 删除 / 非法 ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, '<html></html>'));
    await EhEngine.addFavorites(task(), caller, 42, 'aaaaaaaaaa', 3, 'my note');
    const req = caller.requests[0];
    eq('addFavorites URL', req.url().toString(),
      'https://e-hentai.org/gallerypopups.php?gid=42&t=aaaaaaaaaa&act=addfav');
    eq('addFavorites Referer = 自身', req.headers().get('Referer'), req.url().toString());
    eq('addFavorites Origin', req.headers().get('Origin'), 'https://e-hentai.org');
    eq('favcat = 3', formValue(req, 'favcat'), '3');
    eq('favnote', formValue(req, 'favnote'), 'my+note');
    eq('submit = Apply Changes', formValue(req, 'submit'), 'Apply+Changes');
    eq('update = 1', formValue(req, 'update'), '1');

    const callerDel = new FakeCaller(() => new FakeResponse(200, '<html></html>'));
    await EhEngine.addFavorites(null, callerDel, 1, 't', -1, null);
    eq('dstCat=-1 → favdel', formValue(callerDel.requests[0], 'favcat'), 'favdel');
    eq('note=null → 空串', formValue(callerDel.requests[0], 'favnote'), '');

    let threw = false;
    try {
      await EhEngine.addFavorites(null, callerDel, 1, 't', 10, null);
    } catch (e) {
      threw = e instanceof EhException && (e as Error).message === 'Invalid dstCat: 10';
    }
    ok('dstCat=10 → EhException("Invalid dstCat: 10")', threw);

    // 成功路径也走容错链：code=500 时即便页面正常也要抛
    const caller500 = new FakeCaller(() => new FakeResponse(500, '<html>ok</html>'));
    let threw500 = false;
    try {
      await EhEngine.addFavorites(null, caller500, 1, 't', 1, null);
    } catch (e) {
      threw500 = e instanceof StatusCodeException;
    }
    ok('addFavorites 成功路径 code=500 → StatusCodeException', threw500);
  }

  // ---------- addFavoritesRange ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, '<html></html>'));
    await EhEngine.addFavoritesRange(null, caller, [1, 2, 3], ['a', 'b', 'c'], 5);
    eq('range 发起 3 次请求（串行逐条）', caller.requests.length, 3);
    eq('range 第 2 条的 favcat', formValue(caller.requests[1], 'favcat'), '5');
    eq('range 第 3 条的 URL 含 gid=3',
      caller.requests[2].url().toString().indexOf('gid=3') > 0, true);

    let threw = false;
    try {
      await EhEngine.addFavoritesRange(null, caller, [1, 2], ['a'], 0);
    } catch (e) {
      threw = e instanceof EhException;
    }
    ok('长度不等 → 抛错（对齐 AssertUtils.assertEquals）', threw);
  }

  // ---------- modifyFavorites ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, favHtml));
    const r = await EhEngine.modifyFavorites(task(), caller,
      'https://e-hentai.org/favorites.php', [11, 22, 33], 7, true);
    const req = caller.requests[0];
    eq('modify ddact = fav7', formValue(req, 'ddact'), 'fav7');
    // 契约：字段名里的 [] 会被 URL 编码成 %5B%5D（okhttp FormBody 同样如此，传的就是编码后的名字）
    eq('modify 三个 gid（名字编码为 modifygids%5B%5D）',
      formValues(req, 'modifygids%5B%5D'), ['11', '22', '33']);
    eq('modify apply', formValue(req, 'apply'), 'Apply');
    eq('modify 返回解析结果', r.catArray[0], 'cat0');

    const callerDel = new FakeCaller(() => new FakeResponse(200, favHtml));
    await EhEngine.modifyFavorites(null, callerDel, 'https://e-hentai.org/favorites.php', [1], -1, false);
    eq('modify dstCat=-1 → delete', formValue(callerDel.requests[0], 'ddact'), 'delete');

    let threw = false;
    try {
      await EhEngine.modifyFavorites(null, callerDel, 'https://e-hentai.org/favorites.php', [1], 99, false);
    } catch (e) {
      threw = (e as Error).message === 'Invalid dstCat: 99';
    }
    ok('modify dstCat=99 → 抛错', threw);
  }

  // ---------- getTorrentList ----------
  {
    const torrentHtml = '<form><span>Posted: </span><span>2020-01-02 03:04</span>' +
      '<table><tr><td colspan="5">&nbsp;<a href="https://e-hentai.org/torrent/1.torrent?p=9">N</a></td></tr></table></form>';
    const caller = new FakeCaller(() => new FakeResponse(200, torrentHtml));
    const list = await EhEngine.getTorrentList(task(), caller,
      'https://e-hentai.org/torrents.php?id=1', 42, 'aaaaaaaaaa');
    eq('torrent 1 条', list.length, 1);
    eq('torrent url 去掉 ?p=', list[0].url, 'https://e-hentai.org/torrent/1.torrent');
    eq('torrent Referer = 详情页',
      caller.requests[0].headers().get('Referer'), 'https://e-hentai.org/g/42/aaaaaaaaaa/');
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhEngine batch3 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
