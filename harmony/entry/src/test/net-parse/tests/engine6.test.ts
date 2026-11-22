// EhEngine 第 5b 批测试：fillGalleryListByApi + 6 个收尾 API
//
// 重点：
//   - fillGalleryListByApi 的 **25 条一批**切分（30 条 → 2 次请求，第二批 5 条）
//   - 登录门：getWatchedList / addTag / deleteWatchedTag 未登录 → null（**不发请求**）
//   - addTag / deleteWatchedTag 失败 → 返回 null（上游把 throw e 注释掉了）
//   - getEhNews：body null → null；成功 → EhNewsDetail；IOException → 空 EhNewsDetail（不抛）
//   - resetLimit 的表单字段 reset_imagelimit

import {
  EhEngine, EhEngineConfig, EngineCall, EngineHeaders, EngineResponse, EngineTask, HttpCaller
} from '../EhEngine';
import { Request } from '../../../okhttp/Request';
import { FormBody } from '../../../okhttp/FormBody';
import { GalleryInfo } from './GalleryInfo';
import { TagPushParam, UserTag } from './UserTag';
import { EhNewsDetail } from './EhNewsDetail';

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

class LoginConfig extends EhEngineConfig {
  isLogin(): boolean {
    return true;
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

function textBody(req: Request): string {
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
  // ---------- fillGalleryListByApi：25 条一批 ----------
  {
    const list: GalleryInfo[] = [];
    for (let i = 0; i < 30; i++) {
      const gi = new GalleryInfo();
      gi.gid = 1000 + i;
      gi.token = 'tok' + i;
      list.push(gi);
    }
    const caller = new FakeCaller(() => new FakeResponse(200, '{"gmetadata":[]}'));
    const out = await EhEngine.fillGalleryListByApi(task(), caller, list, 'https://e-hentai.org/');
    eq('30 条 → 2 次请求', caller.requests.length, 2);
    eq('返回同一列表', out.length, 30);
    const first = jsonBody(caller.requests[0]);
    ok('第一批 method=gdata', first.indexOf('"method":"gdata"') >= 0);
    ok('第一批 namespace=1', first.indexOf('"namespace":1') >= 0);
    eq('第一批 25 个 gidlist 项', (first.match(/\[1000,"tok0"\]/g) || []).length, 1);
    eq('第一批含第 25 个 gid', first.indexOf('[1024,"tok24"]') >= 0, true);
    eq('第一批不含第 26 个 gid', first.indexOf('[1025,"tok25"]') >= 0, false);
    const second = jsonBody(caller.requests[1]);
    eq('第二批含第 26 个 gid', second.indexOf('[1025,"tok25"]') >= 0, true);
    eq('第二批含第 30 个 gid', second.indexOf('[1029,"tok29"]') >= 0, true);
    eq('api.php URL', caller.requests[0].url().toString(), 'https://e-hentai.org/api.php');
    eq('Referer 透传', caller.requests[0].headers().get('Referer'), 'https://e-hentai.org/');

    // 空列表 → 一次请求都不发
    const caller2 = new FakeCaller(() => new FakeResponse(200, '{"gmetadata":[]}'));
    await EhEngine.fillGalleryListByApi(null, caller2, [], 'https://e-hentai.org/');
    eq('空列表不发请求', caller2.requests.length, 0);

    // 刚好 25 条 → 1 次请求
    const list25: GalleryInfo[] = [];
    for (let i = 0; i < 25; i++) {
      const gi = new GalleryInfo();
      gi.gid = i;
      gi.token = 't';
      list25.push(gi);
    }
    const caller3 = new FakeCaller(() => new FakeResponse(200, '{"gmetadata":[]}'));
    await EhEngine.fillGalleryListByApi(null, caller3, list25, 'https://e-hentai.org/');
    eq('刚好 25 条 → 1 次请求', caller3.requests.length, 1);
  }

  // ---------- 未登录门：三个接口都直接 null 且不发请求 ----------
  {
    EhEngine.setConfig(new EhEngineConfig()); // 默认 isLogin() = false
    const caller = new FakeCaller(() => new FakeResponse(200, '<html></html>'));
    eq('未登录 getWatchedList → null',
      await EhEngine.getWatchedList(task(), caller, 'https://e-hentai.org/mytags'), null);
    eq('未登录 addTag → null',
      await EhEngine.addTag(task(), caller, 'https://e-hentai.org/mytags', new TagPushParam()), null);
    const ut = new UserTag();
    ut.userTagId = 'usertag_123';
    ut.tagWeight = 10;
    eq('未登录 deleteWatchedTag → null',
      await EhEngine.deleteWatchedTag(task(), caller, 'https://e-hentai.org/mytags', ut), null);
    eq('未登录三个接口都不发请求', caller.requests.length, 0);
  }

  // ---------- 已登录：addTag 的参数串 ----------
  {
    EhEngine.setConfig(new LoginConfig());
    const caller = new FakeCaller(() => new FakeResponse(200, '<html></html>'));
    const param = new TagPushParam();
    param.tagNameNew = 'language:chinese';
    param.tagColorNew = '#ff0000';
    param.tagHiddenNew = 'on';
    const r = await EhEngine.addTag(task(), caller, 'https://e-hentai.org/mytags', param);
    ok('addTag 有返回（解析结果或空列表）', r !== null);
    const body = textBody(caller.requests[0]);
    ok('addTag body 含 usertag_action=add', body.indexOf('usertag_action=add') >= 0);
    // 上游 replace 结果被丢弃 → 标签名里的 ':' 不编码
    ok('addTag 标签名未编码（上游 replace 结果被丢弃）',
      body.indexOf('tagname_new=language:chinese') >= 0);
    ok('addTag 隐藏标记', body.indexOf('&taghide_new=on') >= 0);
    ok('addTag 权重与 target 固定值',
      body.indexOf('&tagweight_new=10&usertag_target=0') >= 0);
    eq('addTag 是 POST', caller.requests[0].method(), 'POST');
    eq('addTag 无 Referer（上游 EhRequestBuilder(url) 单参）',
      caller.requests[0].headers().get('Referer'), null);

    // hidden 与 watch 同时开 → watch 覆盖（状态位只有一个）
    const p2 = new TagPushParam();
    p2.tagNameNew = 'x';
    p2.tagHiddenNew = 'on';
    p2.tagWatchNew = 'on';
    const caller2 = new FakeCaller(() => new FakeResponse(200, '<html></html>'));
    await EhEngine.addTag(task(), caller2, 'https://e-hentai.org/mytags', p2);
    const b2 = textBody(caller2.requests[0]);
    ok('hidden+watch 同时开 → 只剩 watch', b2.indexOf('tagwatch_new=on') >= 0 &&
      b2.indexOf('taghide_new=on') < 0);
  }

  // ---------- 已登录：addTag 失败 → 返回 null（不抛） ----------
  {
    const caller = new FakeCaller(() => new Error('boom') as unknown as FakeResponse);
    const param = new TagPushParam();
    param.tagNameNew = 'x';
    eq('addTag 失败 → null（上游吞异常）',
      await EhEngine.addTag(task(), caller, 'https://e-hentai.org/mytags', param), null);
  }

  // ---------- 已登录：deleteWatchedTag ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, '<html></html>'));
    const ut = new UserTag();
    ut.userTagId = 'usertag_777';
    ut.tagWeight = 5;
    await EhEngine.deleteWatchedTag(task(), caller, 'https://e-hentai.org/mytags', ut);
    const body = textBody(caller.requests[0]);
    ok('delete body 含 usertag_action=mass', body.indexOf('usertag_action=mass') >= 0);
    ok('delete body 含 modify_usertags%5B%5D=777', body.indexOf('modify_usertags%5B%5D=777') >= 0);
    ok('delete body 含 tagweight_new=5', body.indexOf('tagweight_new=5') >= 0);
  }

  // ---------- getEhNews ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200,
      '<html><body>news <b>here</b></body></html>'));
    const news = await EhEngine.getEhNews(task(), caller);
    ok('getEhNews 返回 EhNewsDetail', news instanceof EhNewsDetail);
    ok('getEhNews 内容非空（webData 已填）',
      news !== null && ((news as EhNewsDetail).webData as string).length > 0);
    eq('getEhNews 无 Referer', caller.requests[0].headers().get('Referer'), null);

    // 上游 catch 里先 throwException 再 return new EhNewsDetail()；throwException 必抛 →
    // 那个 return 实际不可达。照搬：IOException 会**抛出**（不是返回空对象）
    const caller2 = new FakeCaller(() => new Error('io') as unknown as FakeResponse);
    let threw = false;
    try {
      await EhEngine.getEhNews(task(), caller2);
    } catch (e) {
      threw = (e as Error).message === 'io';
    }
    ok('getEhNews 异常 → 抛出（上游 return 空对象不可达，照搬）', threw);
  }

  // ---------- getHomeDetail / resetLimit ----------
  {
    const homeHtml = '<html><body><div class="ido">Home</div></body></html>';
    const caller = new FakeCaller(() => new FakeResponse(200, homeHtml));
    const d = await EhEngine.getHomeDetail(task(), caller);
    ok('getHomeDetail 有返回', d !== null);
    eq('getHomeDetail URL = home.php', caller.requests[0].url().toString(),
      'https://e-hentai.org/home.php');
    eq('getHomeDetail Referer', caller.requests[0].headers().get('Referer'), 'https://e-hentai.org');

    const caller2 = new FakeCaller(() => new FakeResponse(200, homeHtml));
    await EhEngine.resetLimit(task(), caller2);
    const req = caller2.requests[0];
    eq('resetLimit 是 POST', req.method(), 'POST');
    const form = req.body() as FormBody;
    eq('resetLimit 表单字段名', form.name(0), 'reset_imagelimit');
    eq('resetLimit 表单值', form.value(0), 'Reset+Limit');
    eq('resetLimit 字段数', form.size(), 1);
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhEngine batch5b 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
