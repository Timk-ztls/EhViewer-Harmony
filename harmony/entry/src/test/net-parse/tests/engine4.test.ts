// EhEngine 第 4 批（4 个 API：getTopList / getProfile / voteComment / getArchiveList）测试
//
// imageSearch 需要文件 IO + multipart + 302 跟随，放到第 5 批与 downloadArchive 一起做。

import {
  EhEngine, EngineCall, EngineHeaders, EngineResponse, EngineTask, HttpCaller
} from '../EhEngine';
import { Request } from '../../../okhttp/Request';
import { EhUrl } from '../EhUrl';

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
  constructor(private responder: (req: Request, index: number) => FakeResponse | Error) { }
  newCall(request: Request): EngineCall {
    this.requests.push(request);
    return new FakeCall(this.responder(request, this.requests.length - 1));
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
  // ---------- getTopList ----------
  {
    const item = (v: string): string => `<div class="tun"><a href="/g/${v}">${v}</a></div>`;
    const seg = (): string => `<div><span>t</span><div><div class="tunbox">${item('a')}${item('b')}</div></div></div>`;
    const info = (): string => `<div><div>x</div>${seg()}${seg()}${seg()}${seg()}</div>`;
    const sep = (): string => `<div class="sep"></div>`;
    const body7 = Array.from({ length: 7 }, () => `${info()}${sep()}`).join('');
    const html = `<html><body><div class="ido"><div>Top Title</div>${body7}</div></body></html>`;

    const caller = new FakeCaller(() => new FakeResponse(200, html));
    const d = await EhEngine.getTopList(task(), caller, 'https://e-hentai.org/toplist.php');
    eq('toplist title', d.title, 'Top Title');
    ok('toplist 7 个榜单', d.get(0) !== null && d.get(6) !== null && d.get(7) === null);
    eq('toplist Referer = EhUrl.getTopListUrl()（恒 E 站）',
      caller.requests[0].headers().get('Referer'), EhUrl.getTopListUrl());
  }

  // ---------- getProfile（两步）----------
  {
    const forumsHtml = '<html><body><div id="userlinks"><div><div>' +
      '<a href="https://forums.e-hentai.org/index.php?showuser=1">me</a></div></div></div></body></html>';
    const profileHtml = '<html><body><div id="profilename"><b>Someone</b></div>' +
      '<div>x</div><div><img src="https://forums.e-hentai.org/a.png"></div></body></html>';

    const caller = new FakeCaller((_req: Request, index: number) =>
      index === 0 ? new FakeResponse(200, forumsHtml) : new FakeResponse(200, profileHtml));
    const r = await EhEngine.getProfile(task(), caller);
    eq('profile 两步请求', caller.requests.length, 2);
    eq('① 论坛首页 URL', caller.requests[0].url().toString(), EhUrl.URL_FORUMS);
    eq('① 不带 Referer', caller.requests[0].headers().get('Referer'), null);
    eq('② 用户页 URL', caller.requests[1].url().toString(),
      'https://forums.e-hentai.org/index.php?showuser=1');
    eq('② Referer = 论坛首页', caller.requests[1].headers().get('Referer'), EhUrl.URL_FORUMS);
    eq('profile.displayName', r.displayName, 'Someone');
    eq('profile.avatar（绝对 URL 原样）', r.avatar, 'https://forums.e-hentai.org/a.png');
  }

  // ---------- voteComment ----------
  {
    const caller = new FakeCaller(() =>
      new FakeResponse(200, '{"comment_id":7,"comment_score":-3,"comment_vote":1}'));
    const r = await EhEngine.voteComment(task(), caller, -1, 'deadbeef', 42, 'aaaaaaaaaa', 7, 1);
    eq('vote.id', r.id, 7);
    eq('vote.score', r.score, -3);
    eq('vote.vote', r.vote, 1);
    eq('vote.expectVote（回填入参）', r.expectVote, 1);

    const req = caller.requests[0];
    eq('vote URL api.php', req.url().toString(), 'https://e-hentai.org/api.php');
    ok('vote JSON method', jsonBody(req).indexOf('"method":"votecomment"') >= 0);
    ok('vote JSON comment_id', jsonBody(req).indexOf('"comment_id":7') >= 0);
    ok('vote JSON comment_vote', jsonBody(req).indexOf('"comment_vote":1') >= 0);
    eq('vote Referer = E 站', req.headers().get('Referer'), 'https://e-hentai.org');
  }

  // ---------- getArchiveList ----------
  {
    const archiveHtml = '<form id="hathdl_form" action="/archiver.php?gid=42&token=t&or=resample" method="post">' +
      '<a href="#" onclick="return do_hathdl(\'org\')">Original</a></form>';
    const caller = new FakeCaller(() => new FakeResponse(200, archiveHtml));
    const r = await EhEngine.getArchiveList(task(), caller,
      'https://e-hentai.org/archiver.php?gid=42', 42, 'aaaaaaaaaa');
    eq('archive paramOr', r.paramOr, 'resample');
    eq('archive 条目数', r.archiveList.length, 1);
    eq('archive Referer = 详情页',
      caller.requests[0].headers().get('Referer'), 'https://e-hentai.org/g/42/aaaaaaaaaa/');
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhEngine batch4 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
