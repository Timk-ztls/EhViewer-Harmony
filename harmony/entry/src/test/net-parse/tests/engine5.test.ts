// EhEngine 第 5a 批（imageSearch / getArchiver / downloadArchive / downloadArchiver）测试
//
// imageSearch 是嵌套分支，重点断言：multipart part 顺序、三个可选开关、302 二次请求、
// 临时文件的两条清理路径（成功/失败）。

import {
  EhEngine, EngineCall, EngineHeaders, EngineResponse, EngineTask, HttpCaller, ImageSearchFileOps
} from '../EhEngine';
import { Request } from '../../../okhttp/Request';
import { MultipartBody } from '../../../okhttp/MultipartBody';
import { EhException } from '../exception/EhException';
import { CancelledException, NoHAtHClientException } from '../exception/MarkerExceptions';

// 测试需要真实文件（RequestBody.createFromFile 会真读文件）→ 用 node fs 造临时文件
declare function require(id: string): any;
declare const process: { env: Record<string, string | undefined>; pid: number };

const nodeFs = require('fs');
const tmpRoot: string = (process.env.TEMP || process.env.TMP || '/tmp') + '/eh-engine5-' + process.pid;
if (!nodeFs.existsSync(tmpRoot)) {
  nodeFs.mkdirSync(tmpRoot, { recursive: true });
}
const JPG_PATH: string = tmpRoot + '/aaa.jpg';
const PNG_PATH: string = tmpRoot + '/bbb.png';
const PNG_PATH2: string = tmpRoot + '/c.png';
nodeFs.writeFileSync(JPG_PATH, new Uint8Array([0xff, 0xd8, 0xff]));
nodeFs.writeFileSync(PNG_PATH, new Uint8Array([0x89, 0x50, 0x4e, 0x47]));
nodeFs.writeFileSync(PNG_PATH2, new Uint8Array([0x89, 0x50, 0x4e, 0x47]));
// 完全没扩展名的文件（触发「加 .jpg 并复制」分支）
const NOEXT_PATH: string = tmpRoot + '/noext';
nodeFs.writeFileSync(NOEXT_PATH, new Uint8Array([0xff, 0xd8, 0xff]));
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
  constructor(private map: Record<string, string> = {}) { }
  get(name: string): string | null {
    const v = this.map[name];
    return v === undefined ? null : v;
  }
}

class FakeResponse implements EngineResponse {
  urlHost?: string;
  constructor(private _code: number, private _body: string, private _headers: EngineHeaders,
    host?: string) {
    if (host !== undefined) {
      this.urlHost = host;
    }
  }
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

class FakeFileOps implements ImageSearchFileOps {
  copied: string[] = [];
  deleted: string[] = [];
  getName(path: string): string {
    const i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
  siblingPath(path: string, name: string): string {
    const i = path.lastIndexOf('/');
    return (i < 0 ? '' : path.substring(0, i + 1)) + name;
  }
  copyFile(from: string, to: string): void {
    this.copied.push(to);
    nodeFs.copyFileSync(from, to); // 真复制：createFromFile 会去读这个文件
  }
  delete(path: string): void {
    this.deleted.push(path);
    if (nodeFs.existsSync(path)) {
      nodeFs.unlinkSync(path);
    }
  }
}

function partNames(req: Request): string[] {
  const body = req.body() as MultipartBody;
  const out: string[] = [];
  for (let i = 0; i < body.parts().length; i++) {
    const cd = body.part(i).headers.get('Content-Disposition');
    const m = cd === null ? null : cd.match(/name="([^"]+)"/);
    out.push(m === null ? '?' : m[1]);
  }
  return out;
}

const listHtml = '<html><body><div class="itg gld">' +
  '<div class="gl1e"><div class="glink glname">' +
  '<a href="https://e-hentai.org/g/1/aaaaaaaaaa/">T</a></div></div></div></body></html>';

async function main(): Promise<void> {
  // ---------- imageSearch：jpg 文件名，三个开关全开 ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, listHtml, new FakeHeaders()));
    const ops = new FakeFileOps();
    const r = await EhEngine.imageSearch(task(), caller, JPG_PATH, true, true, true, ops);
    eq('imageSearch 解析出 1 项', r.galleryInfoList.length, 1);
    const req = caller.requests[0];
    eq('imageSearch URL', req.url().toString(), 'https://upld.e-hentai.org/image_lookup.php');
    eq('imageSearch Referer 末尾带 /', req.headers().get('Referer'), 'https://e-hentai.org/');
    eq('imageSearch Origin', req.headers().get('Origin'), 'https://e-hentai.org');
    eq('multipart part 顺序', partNames(req), ['sfile', 'fs_similar', 'fs_covers', 'fs_exp', 'f_sfile']);
    eq('jpg 无需复制/删除', ops.copied.length + ops.deleted.length, 0);
  }

  // ---------- imageSearch：名字**含 .** → 直接用，不复制 ----------
  // 上游判据是 `imageName.contains(".")`，不是「以 .jpg 结尾」：
  // bbb.png / IMG.JPEG 都直接上传原文件，只有**完全没扩展名**才复制成 <name>.jpg。
  {
    const caller = new FakeCaller(() => new FakeResponse(200, listHtml, new FakeHeaders()));
    const ops = new FakeFileOps();
    await EhEngine.imageSearch(null, caller, PNG_PATH, false, false, false, ops);
    eq('含 . 的 png 不复制（上游 contains(".")）', ops.copied, []);
    eq('含 . 的 png 不删除', ops.deleted, []);
    eq('开关全关 → 只有 2 个 part', partNames(caller.requests[0]), ['sfile', 'f_sfile']);
    const cd = (caller.requests[0].body() as MultipartBody)
      .part(0).headers.get('Content-Disposition') as string;
    ok('sfile 的 filename 用原名字 bbb.png', cd.indexOf('filename="bbb.png"') >= 0);
  }

  // ---------- imageSearch：完全没扩展名 → 复制成 <name>.jpg，成功后删除 ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, listHtml, new FakeHeaders()));
    const ops = new FakeFileOps();
    await EhEngine.imageSearch(null, caller, NOEXT_PATH, false, false, false, ops);
    eq('无扩展名 → 复制一次（noext.jpg）', ops.copied, [tmpRoot + '/noext.jpg']);
    eq('无扩展名 → 成功路径删除临时文件', ops.deleted, [tmpRoot + '/noext.jpg']);
    const cd = (caller.requests[0].body() as MultipartBody)
      .part(0).headers.get('Content-Disposition') as string;
    ok('sfile 的 filename 用 noext.jpg', cd.indexOf('filename="noext.jpg"') >= 0);
    ok('sfile 带 size="40"', cd.indexOf('size="40"') >= 0);
  }

  // ---------- imageSearch：302 跟随 + 失败路径删除 ----------
  {
    const caller = new FakeCaller((_req: Request, index: number) => {
      if (index === 0) {
        return new FakeResponse(302, '', new FakeHeaders({ 'Location': 'https://upld.e-hentai.org/redirect' }));
      }
      // 第二次请求网络失败（走真正的失败路径，而不是返回 500 让解析吞掉）
      return new Error('net down') as unknown as FakeResponse;
    });
    const ops = new FakeFileOps();
    let threw = false;
    try {
      await EhEngine.imageSearch(null, caller, PNG_PATH2, false, false, false, ops);
    } catch (e) {
      threw = true;
    }
    ok('302 后又请求一次', caller.requests.length === 2);
    eq('第二次请求 URL 来自 Location',
      caller.requests[1].url().toString(), 'https://upld.e-hentai.org/redirect');
    // 上游顺序是 throwException(...) 先、delete 后；throwException 一抛就跳出 catch 块 →
    // 临时文件**不会被删**。这是上游的遗留缺陷，本层照搬（与 D-039 同类：不擅自"修好"）
    eq('上游缺陷照搬：throwException 先抛 → 临时文件残留', ops.deleted, []);
    ok('imageSearch 失败抛错', threw);
  }

  // ---------- imageSearch：独立 imageCaller + 相对 Location + 第二步 setCall/code ----------
  {
    const regularCaller = new FakeCaller(() => new FakeResponse(200, '{"gmetadata":[]}', new FakeHeaders()));
    const imageCaller = new FakeCaller((_req: Request, index: number) => {
      if (index === 0) {
        return new FakeResponse(302, '', new FakeHeaders({ 'Location': '/?f_shash=abc123' }));
      }
      return new FakeResponse(200, listHtml, new FakeHeaders());
    });
    const ops = new FakeFileOps();
    const callsSet: Object[] = [];
    const trackedTask: EngineTask = {
      setCall: (c: Object | null): void => {
        if (c !== null) {
          callsSet.push(c);
        }
      }
    };
    const r = await EhEngine.imageSearch(trackedTask, regularCaller, JPG_PATH, false, false, false, ops, imageCaller);
    eq('imageCaller 承担两步搜图请求', imageCaller.requests.length, 2);
    eq('普通 caller 未承接搜图请求（仅在 needApi 时用）', regularCaller.requests.length, 0);
    eq('相对 Location 解析为完整 URL',
      imageCaller.requests[1].url().toString(), 'https://upld.e-hentai.org/?f_shash=abc123');
    eq('两步都调用了 task.setCall', callsSet.length, 2);
    eq('imageSearch 相对 Location 解析出 1 项', r.galleryInfoList.length, 1);

    // 302 缺 Location → EhException
    const missingLocCaller = new FakeCaller(() => new FakeResponse(302, '', new FakeHeaders()));
    let missingErr: Error | null = null;
    try {
      await EhEngine.imageSearch(null, missingLocCaller, JPG_PATH, false, false, false, ops);
    } catch (e) {
      missingErr = e as Error;
    }
    ok('302 缺 Location → 抛 EhException', missingErr instanceof EhException);

    // 第二步 task.setCall 抛 CancelledException（模拟中途取消）
    const cancelCaller = new FakeCaller((_req: Request, index: number) => {
      if (index === 0) {
        return new FakeResponse(302, '', new FakeHeaders({ 'Location': 'https://upld.e-hentai.org/r2' }));
      }
      return new FakeResponse(200, listHtml, new FakeHeaders());
    });
    let setCallCount = 0;
    const cancelTask: EngineTask = {
      setCall: (): void => {
        setCallCount++;
        if (setCallCount === 2) {
          throw new CancelledException();
        }
      }
    };
    let cancelErr: Error | null = null;
    try {
      await EhEngine.imageSearch(cancelTask, cancelCaller, JPG_PATH, false, false, false, ops);
    } catch (e) {
      cancelErr = e as Error;
    }
    ok('第二步取消 → 抛 CancelledException', cancelErr instanceof CancelledException);
  }

  // ---------- getArchiver ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200,
      '<html><body></body></html>', new FakeHeaders()));
    const r = await EhEngine.getArchiver(task(), caller,
      'https://e-hentai.org/archiver.php?gid=42', 42, 'aaaaaaaaaa');
    eq('getArchiver 返回 7 字段对象', [
      r.funds, r.originalCost, r.originalSize, r.originalUrl,
      r.resampleCost, r.resampleSize, r.resampleUrl
    ].length, 7);
    eq('getArchiver Referer = 详情页',
      caller.requests[0].headers().get('Referer'), 'https://e-hentai.org/g/42/aaaaaaaaaa/');
  }

  // ---------- downloadArchive ----------
  {
    const caller = new FakeCaller(() => new FakeResponse(200, '<html>ok</html>', new FakeHeaders()));
    await EhEngine.downloadArchive(task(), caller, 42, 'aaaaaaaaaa', 'resample', '1280');
    const req = caller.requests[0];
    eq('downloadArchive URL 带 or',
      req.url().toString(), 'https://e-hentai.org/archiver.php?gid=42&token=aaaaaaaaaa&or=resample');
    eq('hathdl_xres = 1280', (req.body() as unknown as { name(i: number): string; value(i: number): string })
      .value(0), '1280');
    eq('Referer = 详情页', req.headers().get('Referer'), 'https://e-hentai.org/g/42/aaaaaaaaaa/');

    // or=null → 抛
    let threw = false;
    try {
      await EhEngine.downloadArchive(null, caller, 1, 't', null, '1280');
    } catch (e) {
      threw = (e as Error).message === 'Invalid form param or: null';
    }
    ok('or=null → Invalid form param or', threw);

    // res 空 → 抛
    threw = false;
    try {
      await EhEngine.downloadArchive(null, caller, 1, 't', 'resample', '');
    } catch (e) {
      threw = (e as Error).message === 'Invalid res: ';
    }
    ok('res 空 → Invalid res', threw);

    // body 命中 H@H 提示 → NoHAtHClientException
    const caller2 = new FakeCaller(() => new FakeResponse(200,
      'You must have a H@H client assigned to your account to use this feature.', new FakeHeaders()));
    let noHath = false;
    try {
      await EhEngine.downloadArchive(null, caller2, 1, 't', 'resample', '1280');
    } catch (e) {
      noHath = e instanceof NoHAtHClientException;
    }
    ok('body 命中 H@H 提示 → NoHAtHClientException', noHath);
  }

  // ---------- downloadArchiver ----------
  {
    const caller = new FakeCaller((_req: Request, index: number) => {
      if (index === 0) {
        return new FakeResponse(200, 'document.location = "https://e-hentai.org/continue"',
          new FakeHeaders());
      }
      return new FakeResponse(200, '<a href="/dl/abc.zip">Click Here To Start Downloading</a>',
        new FakeHeaders(), 'e-hentai.org');
    });
    const url = await EhEngine.downloadArchiver(task(), caller,
      'https://e-hentai.org/archiver.php?gid=42', 'https://e-hentai.org/g/42/aaaaaaaaaa/', '1', '1');
    eq('downloadArchiver 两次请求', caller.requests.length, 2);
    eq('② continueUrl 来自 document.location', caller.requests[1].url().toString(),
      'https://e-hentai.org/continue');
    eq('② Referer = origin', caller.requests[1].headers().get('Referer'), 'https://e-hentai.org');
    eq('downloadArchiver 拼出下载链接', url, 'https://e-hentai.org/dl/abc.zip');
    const form = caller.requests[0].body() as unknown as { name(i: number): string; value(i: number): string };
    eq('dltype', form.value(0), '1');
    eq('dlcheck', form.value(1), '1');

    // 无 document.location → null
    const caller2 = new FakeCaller(() => new FakeResponse(200, '<html>no js</html>', new FakeHeaders()));
    eq('无 document.location → null',
      await EhEngine.downloadArchiver(null, caller2, 'https://x/y', 'https://r', '1', '1'), null);

    // 参数校验
    let threw = false;
    try {
      await EhEngine.downloadArchiver(null, caller2, '', 'r', '1', '1');
    } catch (e) {
      threw = (e as Error).message === 'Invalid form param url: ';
    }
    ok('url 空 → 抛', threw);
    threw = false;
    try {
      await EhEngine.downloadArchiver(null, caller2, 'https://x', '', '1', '1');
    } catch (e) {
      threw = (e as Error).message === 'Invalid form param referer: ';
    }
    ok('referer 空 → 抛', threw);
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhEngine batch5a 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
