// EhEngine 第 2 批（5 个 API）测试：参数拼装为主
//
// getPreviewSet / rateGallery / commentGallery / getEditComment / getGalleryToken
// 每个都断言 URL / Referer / Origin / method / body（JSON 或表单）

import {
  EhEngine, EngineCall, EngineHeaders, EngineResponse, EngineTask, HttpCaller
} from '../EhEngine';
import { Request } from '../../../okhttp/Request';
import { FormBody } from '../../../okhttp/FormBody';
import { EhException } from '../exception/EhException';
import { ParseException } from '../exception/ParseException';
import { GalleryCommentList } from './GalleryCommentList';
import { NormalPreviewSet } from './NormalPreviewSet';

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
  get(name: string): string | null {
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
const headerOf = (req: Request, name: string): string | null => req.headers().get(name);

/** JSON 请求体内容（RequestBody.create 的 bytes → UTF-8 文本）。 */
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

function formValue(req: Request, name: string): string | null {
  const f = req.body() as FormBody;
  for (let i = 0; i < f.size(); i++) {
    if (f.name(i) === name) {
      return f.value(i);
    }
  }
  return null;
}

async function main(): Promise<void> {
  // ---------- getPreviewSet ----------
  {
    const body = '<a href="https://e-hentai.org/s/aaaaaaaaaa/1-1">' +
      '<div title="Page 1: https://x/t.jpg width:250 height:350 (t.jpg) -250px"></div></a>' +
      '<td class="ptdd"><a href="?p=0">1</a></td><td class="ptdd2">&gt;</td>';
    const caller = new FakeCaller(() => new FakeResponse(200, body));
    const r = await EhEngine.getPreviewSet(null, caller, 'https://e-hentai.org/s/x');
    eq('previewSet 类型', r.previewSet instanceof NormalPreviewSet, true);
    eq('previewSet.size', (r.previewSet as NormalPreviewSet).size(), 1);
    eq('previewPages', r.previewPages, 1);
    eq('previewSet Referer', headerOf(caller.requests[0], 'Referer'), 'https://e-hentai.org');
  }

  // ---------- rateGallery ----------
  {
    const caller = new FakeCaller(() =>
      new FakeResponse(200, '{"rating_avg":4.5,"rating_cnt":9}'));
    const r = await EhEngine.rateGallery(task(), caller, -1, 'deadbeef', 42, 'aaaaaaaaaa', 4.5);
    eq('rate 返回 avg', r.rating, 4.5);
    eq('rate 返回 cnt', r.ratingCount, 9);
    const req = caller.requests[0];
    eq('rate URL = api.php', req.url().toString(), 'https://e-hentai.org/api.php');
    eq('rate method', req.method(), 'POST');
    eq('rate Referer = 详情页', headerOf(req, 'Referer'), 'https://e-hentai.org/g/42/aaaaaaaaaa/');
    eq('rate Origin', headerOf(req, 'Origin'), 'https://e-hentai.org');
    ok('rate JSON 含 method', jsonBody(req).indexOf('"method":"rategallery"') >= 0);
    ok('rate JSON 含 apiuid=-1', jsonBody(req).indexOf('"apiuid":-1') >= 0);
    // 4.5 * 2 = 9（ceil 后仍是 9）
    ok('rate rating 转 9（ceil(rating*2)）', jsonBody(req).indexOf('"rating":9') >= 0);
    ok('rate Content-Type 是 json',
      (req.body() as unknown as { contentType(): { toString(): string } })
        .contentType().toString().indexOf('application/json') >= 0);
  }

  // rateGallery 的 ceil 边界
  {
    const caller = new FakeCaller(() => new FakeResponse(200, '{"rating_avg":1,"rating_cnt":1}'));
    await EhEngine.rateGallery(null, caller, 1, 'k', 1, 't', 0.4);
    ok('0.4 → 1（ceil(0.8)）', jsonBody(caller.requests[0]).indexOf('"rating":1') >= 0);
    const caller2 = new FakeCaller(() => new FakeResponse(200, '{"rating_avg":1,"rating_cnt":1}'));
    await EhEngine.rateGallery(null, caller2, 1, 'k', 1, 't', 5);
    ok('5 → 10', jsonBody(caller2.requests[0]).indexOf('"rating":10') >= 0);
  }

  // ---------- commentGallery（新增评论）----------
  {
    const caller = new FakeCaller(() =>
      new FakeResponse(200, '<html><body><div id="cdiv"></div></body></html>'));
    const r = await EhEngine.commentGallery(task(), caller,
      'https://e-hentai.org/g/42/aaaaaaaaaa/', 'hello world', null);
    ok('commentGallery 返回 GalleryCommentList', r instanceof GalleryCommentList);
    const req = caller.requests[0];
    eq('comment Referer = 同 URL', headerOf(req, 'Referer'), 'https://e-hentai.org/g/42/aaaaaaaaaa/');
    eq('comment Origin', headerOf(req, 'Origin'), 'https://e-hentai.org');
    eq('comment 新评论字段', formValue(req, 'commenttext_new'), 'hello+world');
    eq('新评论不带 edit_comment', formValue(req, 'edit_comment'), null);
  }

  // commentGallery（编辑评论）+ 错误位
  {
    const caller = new FakeCaller(() =>
      new FakeResponse(200, '<html><body><div id="chd"></div><p>Edit failed</p></body></html>'));
    let caught: Error | null = null;
    try {
      await EhEngine.commentGallery(null, caller, 'https://e-hentai.org/g/1/b/', 'txt', '12345');
    } catch (e) {
      caught = e as Error;
    }
    ok('编辑评论 + #chd+p → EhException', caught instanceof EhException);
    eq('错误消息来自 #chd + p', (caught as Error).message, 'Edit failed');
    eq('编辑评论字段', formValue(caller.requests[0], 'commenttext_edit'), 'txt');
    eq('edit_comment 字段', formValue(caller.requests[0], 'edit_comment'), '12345');
  }

  // ---------- getEditComment ----------
  {
    const payload = JSON.stringify({
      comment_id: 777,
      editable_comment: '<textarea name="commenttext_edit">my comment</textarea>'
    });
    const caller = new FakeCaller(() => new FakeResponse(200, payload));
    const r = await EhEngine.getEditComment(task(), caller, -1, 'key', 42, 'aaaaaaaaaa', 777);
    eq('editComment id', r.id, 777);
    eq('editComment 文本', r.comment, 'my comment');
    const req = caller.requests[0];
    ok('editComment JSON method', jsonBody(req).indexOf('"method":"geteditcomment"') >= 0);
    ok('editComment JSON comment_id', jsonBody(req).indexOf('"comment_id":777') >= 0);
    eq('editComment Referer', headerOf(req, 'Referer'), 'https://e-hentai.org/g/42/aaaaaaaaaa/');
  }

  // ---------- getGalleryToken ----------
  {
    const caller = new FakeCaller(() =>
      new FakeResponse(200, '{"tokenlist":[{"gid":42,"token":"0439fa3666"}]}'));
    const token = await EhEngine.getGalleryToken(task(), caller, 42, 'oldtoken', 2);
    eq('token 返回值', token, '0439fa3666');
    const req = caller.requests[0];
    ok('token JSON method gtoken', jsonBody(req).indexOf('"method":"gtoken"') >= 0);
    // page=2（0 基）→ API 传 3
    ok('pagelist 页码 +1（2 → 3）', jsonBody(req).indexOf('"pagelist":[[42,"oldtoken",3]]') >= 0);
    eq('token Origin', headerOf(req, 'Origin'), 'https://e-hentai.org');
  }

  // ---------- 失败路径：400 → StatusCodeException ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(400, 'bad request'));
    let caught = false;
    try {
      await EhEngine.getGalleryToken(null, caller, 1, 't', 0);
    } catch (e) {
      caught = e !== null;
    }
    ok('getGalleryToken 400 → 抛错（JSON 解析失败走容错链）', caught);
    // ParseException 路径也覆盖一下：非法 JSON 且 code=200 且有 html → parse error
    const caller2 = new FakeCaller(() => new FakeResponse(200, 'not json'));
    let msg = '';
    try {
      await EhEngine.getEditComment(null, caller2, 1, 'k', 1, 't', 1);
    } catch (e) {
      msg = (e as Error).message;
    }
    eq('非法 JSON + 无 < → 消息就是 body', msg, 'not json');
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhEngine batch2 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
