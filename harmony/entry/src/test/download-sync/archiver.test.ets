/*
 * download-sync 纯逻辑单测：归档下载的边界算法（C-10：harmony/entry/src/test/<module>/）
 *
 * 这三块是"不报错但会算错"的高危区，全部是纯静态函数，宿主可验：
 *   1. 断点续传的总长解析 —— `Content-Range: bytes a-b/total` 的 total 优先，
 *      否则 offset + contentLength，否则 0（上游 `resolveTotal`）
 *   2. 416 / 206 判定依赖的 Range 解析细节（`bytes 0-9/*` 必须返回 0，不能当 1000）
 *   3. 归档文件名生成 —— 按 **UTF-8 字节** 截断到 255-4，代理对不截半（上游 `createFileName`）
 */

import { ArchiverDownloader } from '../../main/ets/hippo/ehviewer/download/ArchiverDownloader';
import { ArchiverDownloadCompleter } from '../../main/ets/hippo/ehviewer/download/ArchiverDownloadCompleter';
import { DownloadTorrentManager } from '../../main/ets/hippo/ehviewer/download/DownloadTorrentManager';

let pass = 0;
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
    fails.push(`${name}\n    want true, got false`);
  }
}

/** 按 UTF-8 计算字节数（与 createFileName 的截断口径一致）。 */
function utf8Length(s: string): number {
  const enc: TextEncoder = new TextEncoder();
  return enc.encode(s).length;
}

function main(): void {
  // ------------------------------------------------- 1) 断点续传总长解析
    eq('total 优先取 Content-Range 的总长', ArchiverDownloader.resolveTotal(1000, 300, 700), 1000);
  eq('无 Content-Range → offset + contentLength', ArchiverDownloader.resolveTotal(0, 300, 700), 1000);
  eq('完整流（offset=0）→ 等于 contentLength 而非 2x', ArchiverDownloader.resolveTotal(0, 0, 139787743), 139787743);
  eq('两者都没有 → 0（未知长度）', ArchiverDownloader.resolveTotal(0, 0, 0), 0);
  eq('初始活动归档任务快照为空', ArchiverDownloader.getInstance().getActiveTasks().length, 0);

  // ------------------------------------------------- 2) Content-Range 解析
  eq('bytes 100-999/1000 → 1000', ArchiverDownloader.parseContentRangeTotal('bytes 100-999/1000'), 1000);
  eq('bytes 0-9/* → 0（未知，不能当 1000）',
    ArchiverDownloader.parseContentRangeTotal('bytes 0-9/*'), 0);
  eq('无斜杠 → 0', ArchiverDownloader.parseContentRangeTotal('bytes 0-9'), 0);
  eq('斜杠在末尾 → 0', ArchiverDownloader.parseContentRangeTotal('bytes 0-9/'), 0);
  eq('非数字 → 0', ArchiverDownloader.parseContentRangeTotal('bytes 0-9/abc'), 0);

  // ------------------------------------------------- 3) 归档文件名（UTF-8 截断）
  //
  // 规则：sanitize → 按 UTF-8 字节截到 255-4=251 → 空则 archiver_<gid>
  eq('普通标题原样保留', ArchiverDownloadCompleter.createFileName('作品 A', 123), '作品 A');
  ok('超长中文标题截断后 UTF-8 字节数 <= 251',
    utf8Length(ArchiverDownloadCompleter.createFileName('あ'.repeat(200), 123)) <= 251);
  ok('截断不会切出半个字符（往返编解码仍合法）',
    ((): boolean => {
      const name: string = ArchiverDownloadCompleter.createFileName('あ'.repeat(200), 123);
      return name.indexOf('\uFFFD') < 0;   // 不含替换字符 => 没有截半
    })());
  eq('非法路径分隔符被替换为 _',
    ArchiverDownloadCompleter.createFileName('a/b\\c:d', 123), 'a_b_c_d');
  eq('空标题回退 archiver_<gid>', ArchiverDownloadCompleter.createFileName('', 456), 'archiver_456');
  eq('空标题且 gid<=0 回退 archiver', ArchiverDownloadCompleter.createFileName('', 0), 'archiver');

  // ------------------------------------------------- 4) 种子文件名与分块切片
  eq('getNameFromUrl 取最后一段', DownloadTorrentManager.getNameFromUrl('https://x/y/a.torrent'), 'a.torrent');
  eq('getNameFromUrl 无斜杠 → 原样', DownloadTorrentManager.getNameFromUrl('a.torrent'), 'a.torrent');
  eq('getNameFromUrl 尾斜杠 → 空串', DownloadTorrentManager.getNameFromUrl('https://x/y/'), '');
  {
    const raw: Uint8Array = new Uint8Array(2500);
    for (let i = 0; i < raw.length; i++) {
      raw[i] = i & 0xff;
    }
    const chunk: ArrayBuffer = DownloadTorrentManager.sliceChunk(raw.buffer as ArrayBuffer, 2048, 2500);
    eq('sliceChunk 只切 [2048,2500) 长度 452B（而非整包 2500B）', chunk.byteLength, 452);
    const chunkView: Uint8Array = new Uint8Array(chunk);
    eq('sliceChunk 首字节对齐 offset=2048', chunkView[0], raw[2048]);
    eq('sliceChunk 尾字节对齐 end-1=2499', chunkView[451], raw[2499]);
  }

  // ------------------------------------------------- 5) 流式下载头/代理/请求选项构建
  {
    const hdrsObj: Record<string, string> = {
      'ResponseCode': '206',
      'Content-Range': 'bytes 100-999/1000',
      'CONTENT-LENGTH': '900'
    };
    eq('readHeaderIgnoreCase 匹配 responseCode', ArchiverDownloader.readHeaderIgnoreCase(hdrsObj, 'responseCode'), '206');
    eq('readHeaderIgnoreCase 匹配 content-range', ArchiverDownloader.readHeaderIgnoreCase(hdrsObj, 'content-range'), 'bytes 100-999/1000');
    eq('readHeaderIgnoreCase 匹配 content-length', ArchiverDownloader.readHeaderIgnoreCase(hdrsObj, 'content-length'), '900');

    const freshHeaders = ArchiverDownloader.buildStreamHeaders(0, 'ipb_member_id=1', 'https://e-hentai.org/g/1/a/', 'CustomUA/1');
    eq('offset=0 不发送 Range 头', freshHeaders['Range'] === undefined, true);
    eq('fresh 请求携带 Cookie', freshHeaders['Cookie'], 'ipb_member_id=1');
    eq('fresh 请求携带 Referer', freshHeaders['Referer'], 'https://e-hentai.org/g/1/a/');
    eq('fresh 请求携带 User-Agent', freshHeaders['User-Agent'], 'CustomUA/1');

    const resumeHeaders = ArchiverDownloader.buildStreamHeaders(2048, '', '', '');
    eq('offset=2048 发送 Range bytes=2048-', resumeHeaders['Range'], 'bytes=2048-');
    eq('空 Cookie 不写入 Cookie 头', resumeHeaders['Cookie'] === undefined, true);
    eq('空 User-Agent 回退默认 Chrome UA', resumeHeaders['User-Agent'], ArchiverDownloader.CHROME_USER_AGENT);

    const directProxy = ArchiverDownloader.resolveHttpProxyForStream(ArchiverDownloader.PROXY_TYPE_DIRECT, '127.0.0.1', 7890);
    eq('PROXY_TYPE_DIRECT -> false', directProxy, false);
    const sysProxy = ArchiverDownloader.resolveHttpProxyForStream(ArchiverDownloader.PROXY_TYPE_SYSTEM, null, -1);
    eq('PROXY_TYPE_SYSTEM -> true', sysProxy, true);
    const invalidHttpProxy = ArchiverDownloader.resolveHttpProxyForStream(ArchiverDownloader.PROXY_TYPE_HTTP, '', 7890);
    eq('无效 HTTP 代理配置回退系统代理 true', invalidHttpProxy, true);
    const httpProxy = ArchiverDownloader.resolveHttpProxyForStream(ArchiverDownloader.PROXY_TYPE_HTTP, '127.0.0.1', 7890);
    eq('HTTP 代理返回 HttpProxy 结构', httpProxy, { host: '127.0.0.1', port: 7890, exclusionList: [] });

    const reqOpts = ArchiverDownloader.buildStreamRequestOptions(resumeHeaders, httpProxy, true);
    eq('HttpRequestOptions 携带 usingProxy', reqOpts.usingProxy, { host: '127.0.0.1', port: 7890, exclusionList: [] });
    eq('HttpRequestOptions remoteValidation=skip', reqOpts.remoteValidation, 'skip');
  }

  // ------------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('archiver test failed');
  }
  console.log(`✓ archiver: ${pass} 条断言全部通过`);
}

main();
