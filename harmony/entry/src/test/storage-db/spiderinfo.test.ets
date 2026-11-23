/*
 * storage-db 纯逻辑单测（C-10：harmony/entry/src/test/<module>/）
 *
 * 覆盖三块「不依赖设备/RDB」的核心逻辑：
 *   1. SpiderInfo 的 spider_info 文件格式（**逐字节**断言）—— 这是"旧 Android 下载目录可迁移"的唯一自动化证据
 *   2. MSQLiteBuilder 的迁移语句生成与版本区间选择
 *   3. Filter 的 equals/hashCode（影响 FilterDao 备份去重，等价于上游 HashCodeUtils.hashCode）
 *
 * 断言风格：字节级字符串比对 + 显式期望值（不写"和实现一致"的镜像断言）。
 */

import { SpiderInfo, PTokenLine, SPIDER_INFO_FILENAME, SPIDER_INFO_CACHE_DIRNAME, DownloadDirProvider } from '../../main/ets/hippo/ehviewer/spider/SpiderInfo';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { GalleryDetail } from '../../main/ets/hippo/ehviewer/client/data/GalleryDetail';
import { LargePreviewSet } from '../../main/ets/hippo/ehviewer/client/data/LargePreviewSet';
import { SimpleDiskCache } from '../../main/ets/hippo/beerbelly/SimpleDiskCache';
import { InputStreamPipe } from '../../main/ets/hippo/streampipe/InputStreamPipe';
import { UniFile } from '../../main/ets/hippo/unifile/UniFile';
import { MSQLiteBuilder, SqlType } from '../../main/ets/hippo/database/MSQLiteBuilder';
import { Filter } from '../../main/ets/hippo/ehviewer/dao/Filter';
import { InputStream, OutputStream } from '../../main/ets/hippo/unifile/Contracts';
import fs from '@ohos.file.fs';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
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
    fails.push(name);
  }
}

// ---------------------------------------------------------------- 内存流（实现 unifile/Contracts 的契约）

class MemoryInputStream implements InputStream {
  private readonly data: Uint8Array;
  private pos: number = 0;
  private closed: boolean = false;

  constructor(text: string) {
    const bytes: number[] = [];
    for (let i = 0; i < text.length; i++) {
      bytes.push(text.charCodeAt(i) & 0xff);
    }
    this.data = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      this.data[i] = bytes[i];
    }
  }

  read(): number {
    if (this.pos >= this.data.length) {
      return -1;
    }
    return this.data[this.pos++];
  }

  readBuffer(buffer: ArrayBuffer): number {
    const view: Uint8Array = new Uint8Array(buffer);
    let n: number = 0;
    while (n < view.length && this.pos < this.data.length) {
      view[n++] = this.data[this.pos++];
    }
    return n === 0 ? -1 : n;
  }

  readBytes(buffer: ArrayBuffer, off: number, len: number): number {
    const view: Uint8Array = new Uint8Array(buffer);
    let n: number = 0;
    while (n < len && this.pos < this.data.length && off + n < view.length) {
      view[off + n] = this.data[this.pos++];
      n++;
    }
    return n === 0 ? -1 : n;
  }

  skip(n: number): number {
    const step: number = Math.min(n, this.data.length - this.pos);
    this.pos += step;
    return step;
  }

  available(): number {
    return this.data.length - this.pos;
  }

  close(): void {
    this.closed = true;
  }
}

class MemoryOutputStream implements OutputStream {
  private readonly chunks: number[] = [];
  private closed: boolean = false;
  flushed: boolean = false;

  write(buffer: ArrayBuffer): void {
    const view: Uint8Array = new Uint8Array(buffer);
    for (let i = 0; i < view.length; i++) {
      this.chunks.push(view[i]);
    }
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    const view: Uint8Array = new Uint8Array(buffer);
    for (let i = 0; i < len; i++) {
      this.chunks.push(view[off + i]);
    }
  }

  flush(): void {
    this.flushed = true;
  }

  close(): void {
    this.closed = true;
  }

  /** 收集到的字节按 Latin-1 还原成字符串（文件内容是 ASCII，不需要真 UTF-8 解码）。 */
  asText(): string {
    let s = '';
    for (const b of this.chunks) {
      s += String.fromCharCode(b);
    }
    return s;
  }

  byteLength(): number {
    return this.chunks.length;
  }
}

function makeInfo(): SpiderInfo {
  const info: SpiderInfo = new SpiderInfo();
  info.startPage = 31;          // 0x1f → "%08x" 应为 0000001f
  info.gid = 123456;
  info.token = 'abcd1234';
  info.previewPages = 10;
  info.previewPerPage = 20;
  info.pages = 3;
  const map: Map<number, string> = new Map<number, string>();
  map.set(0, 'aaaa');
  map.set(1, SpiderInfo.TOKEN_FAILED);   // 必须被跳过
  map.set(2, 'cccc');
  info.pTokenMap = map;
  return info;
}

// ================================================================ 1) SpiderInfo 文件格式

// --- 1.1 逐字节写出（含 %08x 补零、failed 跳过、页号升序）
{
  const out: MemoryOutputStream = new MemoryOutputStream();
  makeInfo().write(out);
  const expected: string =
    'VERSION2\n' +
    '0000001f\n' +
    '123456\n' +
    'abcd1234\n' +
    '1\n' +
    '10\n' +
    '20\n' +
    '3\n' +
    '0 aaaa\n' +
    '2 cccc\n';
  eq('spider_info 逐字节内容', out.asText(), expected);
  eq('spider_info 字节数', out.byteLength(), expected.length);
  ok('write() 调用了 flush', out.flushed);
}

// --- 1.2 写 → 读往返（字段 + pTokenMap 等价）
{
  const out: MemoryOutputStream = new MemoryOutputStream();
  makeInfo().write(out);
  const parsed: SpiderInfo | null = SpiderInfo.readStreamInclude(new MemoryInputStream(out.asText()), true);
  ok('roundtrip 解析成功', parsed !== null);
  if (parsed !== null) {
    eq('roundtrip.startPage', parsed.startPage, 31);
    eq('roundtrip.gid', parsed.gid, 123456);
    eq('roundtrip.token', parsed.token, 'abcd1234');
    eq('roundtrip.previewPages', parsed.previewPages, 10);
    eq('roundtrip.previewPerPage', parsed.previewPerPage, 20);
    eq('roundtrip.pages', parsed.pages, 3);
    eq('roundtrip pToken[0]', parsed.pTokenMap !== null ? parsed.pTokenMap.get(0) : undefined, 'aaaa');
    eq('roundtrip pToken[2]', parsed.pTokenMap !== null ? parsed.pTokenMap.get(2) : undefined, 'cccc');
    eq('roundtrip pToken 数量（failed 未写盘）', parsed.getPTokenCount(), 2);
  }
}

// --- 1.3 readHeader（不读 pTokenMap）
{
  const out: MemoryOutputStream = new MemoryOutputStream();
  makeInfo().write(out);
  const header: SpiderInfo | null = SpiderInfo.readStreamInclude(new MemoryInputStream(out.asText()), false);
  ok('readHeader 解析成功', header !== null);
  if (header !== null) {
    eq('readHeader.pages', header.pages, 3);
    eq('readHeader pToken 数量为 0', header.getPTokenCount(), 0);
  }
}

// --- 1.4 %08x 补零边界：0 / 1 / 999999
{
  const cases: number[][] = [[0, 0], [1, 1], [999999, 999999]];
  const want: string[] = ['00000000', '00000001', '000f423f'];
  for (let i = 0; i < cases.length; i++) {
    const info: SpiderInfo = makeInfo();
    info.startPage = cases[i][0];
    const out: MemoryOutputStream = new MemoryOutputStream();
    info.write(out);
    const secondLine: string = out.asText().split('\n')[1];
    eq(`%08x 边界 startPage=${cases[i][0]}`, secondLine, want[i]);
  }
  // 负数按上游 Math.max(startPage, 0) 处理
  const neg: SpiderInfo = makeInfo();
  neg.startPage = -5;
  const negOut: MemoryOutputStream = new MemoryOutputStream();
  neg.write(negOut);
  eq('%08x 负数归零', negOut.asText().split('\n')[1], '00000000');
}

// --- 1.5 版本 1 兼容（首行不是 VERSION 头，而是 %08x 的 startPage）
{
  const v1: string =
    '0000000a\n' +   // 首行是 startPage（version 1 判定）
    '777\n' +
    'tok\n' +
    '1\n' +
    '5\n' +          // previewPages
    '9\n' +          // v1 这一行被读出后丢弃（上游同样丢弃）
    '4\n' +          // version 1 里这行是 pages（不读 previewPerPage）
    '0 aaaa\n';
  const parsed: SpiderInfo | null = SpiderInfo.readStreamInclude(new MemoryInputStream(v1), true);
  ok('v1 解析成功', parsed !== null);
  if (parsed !== null) {
    eq('v1.startPage', parsed.startPage, 10);
    eq('v1.previewPerPage 保持 -1', parsed.previewPerPage, -1);
    eq('v1.pages', parsed.pages, 4);
  }
}

// --- 1.6 损坏行跳过、不中断（非数字下标 / 空 token / 无空格）
{
  const text: string =
    'VERSION2\n' +
    '00000000\n' +
    '1\n' +
    'tok\n' +
    '1\n' +
    '0\n' +
    '0\n' +
    '4\n' +          // 下面共 4 行 pToken（坏 3 行 + 好 1 行）
    'x aaaa\n' +     // 非数字下标 → 跳过
    '1\n' +          // 没有空格 → 跳过
    '2 \n' +         // 空 pToken → 跳过
    '3 cccc\n';      // 有效
  const parsed: SpiderInfo | null = SpiderInfo.readStreamInclude(new MemoryInputStream(text), true);
  ok('损坏行场景解析成功', parsed !== null);
  if (parsed !== null) {
    eq('损坏行只保留有效条目', parsed.getPTokenCount(), 1);
    eq('损坏行保留的条目', parsed.pTokenMap !== null ? parsed.pTokenMap.get(3) : undefined, 'cccc');
  }
}

// --- 1.7 pages 上限/下限（防 OOM 与空文件）
{
  const make = (pages: string): string =>
    'VERSION2\n00000000\n1\ntok\n1\n0\n0\n' + pages + '\n';
  ok('pages=0 → null', SpiderInfo.readStreamInclude(new MemoryInputStream(make('0')), true) === null);
  ok('pages=100001 → null', SpiderInfo.readStreamInclude(new MemoryInputStream(make('100001')), true) === null);
  ok('pages=100000 → 非 null', SpiderInfo.readStreamInclude(new MemoryInputStream(make('100000')), false) !== null);
}

// --- 1.8 tryParsePTokenLine 单点行为
{
  const ok1: PTokenLine | null = SpiderInfo.tryParsePTokenLine('7 ptoken7');
  ok('tryParse 有效行', ok1 !== null && ok1.index === 7 && ok1.pToken === 'ptoken7');
  ok('tryParse 无空格 → null', SpiderInfo.tryParsePTokenLine('7ptoken') === null);
  ok('tryParse 下标在首位 → null', SpiderInfo.tryParsePTokenLine(' abc') === null);
  ok('tryParse 空 token → null', SpiderInfo.tryParsePTokenLine('7 ') === null);
  // 超长 token（>1024）拒绝，防止损坏文件塞进巨串
  const longToken: string = 'a'.repeat(2000);
  ok('tryParse 超长 token → null', SpiderInfo.tryParsePTokenLine(`7 ${longToken}`) === null);
  // 上游 SpiderQueen.java:108 → .ehviewer（下载目录里的进度文件）；spider_info 是**缓存目录名**（EhApplication.java:595）
  eq('SPIDER_INFO_FILENAME 与上游一致（.ehviewer，不是 spider_info）', SPIDER_INFO_FILENAME, '.ehviewer');
  eq('缓存目录名单独一个常量（spider_info）', SPIDER_INFO_CACHE_DIRNAME, 'spider_info');
  eq('TOKEN_FAILED 常量', SpiderInfo.TOKEN_FAILED, 'failed');
}

// --- 1.9 CBOR 格式 .ehviewer 头部读取（上游 9cbb77f7）
{
  const makeBinaryStream = (bytes: number[]): InputStream => {
    let pos: number = 0;
    return {
      read(): number {
        return pos >= bytes.length ? -1 : (bytes[pos++] & 0xFF);
      },
      readBuffer(buffer: ArrayBuffer): number {
        const view: Uint8Array = new Uint8Array(buffer);
        let n: number = 0;
        while (n < view.length && pos < bytes.length) {
          view[n++] = bytes[pos++] & 0xFF;
        }
        return n === 0 ? -1 : n;
      },
      readBytes(buffer: ArrayBuffer, off: number, len: number): number {
        const view: Uint8Array = new Uint8Array(buffer);
        let n: number = 0;
        while (n < len && pos < bytes.length && off + n < view.length) {
          view[off + n] = bytes[pos++] & 0xFF;
          n++;
        }
        return n === 0 ? -1 : n;
      },
      skip(n: number): number {
        const step: number = Math.min(n, bytes.length - pos);
        pos += step;
        return step;
      },
      available(): number {
        return bytes.length - pos;
      },
      close(): void {
      }
    };
  };

  // 上游 SpiderInfoTest.readCborHeader_readsGidAndTokenFromIndefiniteMap 原样字节样本
  const indefiniteBytes: number[] = [
    0xBF, 0x63, 0x67, 0x69, 0x64, 0x1A, 0x35, 0xA4, 0xE9, 0x02,
    0x65, 0x74, 0x6F, 0x6B, 0x65, 0x6E, 0x6A, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30,
    0x30, 0x30, 0x30, 0x30, 0x65, 0x70, 0x61, 0x67, 0x65, 0x73, 0x18, 0x4D, 0x69,
    0x70, 0x54, 0x6F, 0x6B, 0x65, 0x6E, 0x4D, 0x61, 0x70, 0xBF, 0x00, 0x6A,
    0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x31, 0xFF, 0x6C,
    0x70, 0x72, 0x65, 0x76, 0x69, 0x65, 0x77, 0x50, 0x61, 0x67, 0x65, 0x73, 0x02,
    0x6E, 0x70, 0x72, 0x65, 0x76, 0x69, 0x65, 0x77, 0x50, 0x65, 0x72, 0x50, 0x61,
    0x67, 0x65, 0x18, 0x28, 0xFF
  ];
  const indefInfo: SpiderInfo | null = SpiderInfo.readCborHeaderStream(makeBinaryStream(indefiniteBytes));
  ok('CBOR 不定长 map 解析成功', indefInfo !== null);
  if (indefInfo !== null) {
    eq('CBOR 不定长 gid', indefInfo.gid, 900000002);
    eq('CBOR 不定长 token', indefInfo.token, '0000000000');
  }
  ok('CBOR 字节流不被文本 readHeaderStream 误认',
    SpiderInfo.readHeaderStream(makeBinaryStream(indefiniteBytes)) === null);

  // 上游 SpiderInfoTest.readCborHeader_readsDefiniteMap 原样字节样本
  const definiteBytes: number[] = [
    0xA2, 0x63, 0x67, 0x69, 0x64, 0x1A, 0x35, 0xA4, 0xE9, 0x02,
    0x65, 0x74, 0x6F, 0x6B, 0x65, 0x6E, 0x6A, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30,
    0x30, 0x30, 0x30, 0x30
  ];
  const defInfo: SpiderInfo | null = SpiderInfo.readCborHeaderStream(makeBinaryStream(definiteBytes));
  ok('CBOR 定长 map 解析成功', defInfo !== null);
  if (defInfo !== null) {
    eq('CBOR 定长 gid', defInfo.gid, 900000002);
    eq('CBOR 定长 token', defInfo.token, '0000000000');
  }

  // 上游 SpiderInfoTest.readHeader_rejectsInvalidTextAndCbor
  const invalidBytes: number[] = [];
  const invalidText: string = 'INVALID_FORMAT';
  for (let i = 0; i < invalidText.length; i++) {
    invalidBytes.push(invalidText.charCodeAt(i));
  }
  ok('文本 readHeader 拒绝非法字节', SpiderInfo.readHeaderStream(makeBinaryStream(invalidBytes)) === null);
  ok('CBOR readCborHeader 拒绝非法字节', SpiderInfo.readCborHeaderStream(makeBinaryStream(invalidBytes)) === null);
  ok('CBOR readCborHeader(null) → null', SpiderInfo.readCborHeader(null) === null);

  // ArkTS 64-bit 整数无 32 位截断：gid = 0x00000001_00000005 (4294967301 > 2^31)
  const bigGidBytes: number[] = [
    0xA2, 0x63, 0x67, 0x69, 0x64, 0x1B, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x05,
    0x65, 0x74, 0x6F, 0x6B, 0x65, 0x6E, 0x6A, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x31, 0x32, 0x33, 0x34
  ];
  const bigGidInfo: SpiderInfo | null = SpiderInfo.readCborHeaderStream(makeBinaryStream(bigGidBytes));
  ok('CBOR 64-bit gid > 2^31 解析成功（无 32 位截断）', bigGidInfo !== null);
  if (bigGidInfo !== null) {
    eq('CBOR 64-bit gid 精确值', bigGidInfo.gid, 4294967301);
    eq('CBOR 64-bit token', bigGidInfo.token, 'abcdef1234');
  }

  // 已读到 gid/token 后即使尾部 pTokenMap 截断损坏仍返回已读到的值
  const truncatedTailBytes: number[] = indefiniteBytes.slice(0, 48);
  const partialInfo: SpiderInfo | null = SpiderInfo.readCborHeaderStream(makeBinaryStream(truncatedTailBytes));
  ok('CBOR 尾部截断仍保留已读到的 gid/token',
    partialInfo !== null && partialInfo.gid === 900000002 && partialInfo.token === '0000000000');

  // 嵌套超深（> 16 层）放在 gid 之前 → 安全中止返回 null
  const deepBytes: number[] = [0xA2, 0x64, 0x64, 0x65, 0x65, 0x70];
  for (let d = 0; d < 20; d++) {
    deepBytes.push(0x81); // 1-element array x 20
  }
  deepBytes.push(0x00, 0x63, 0x67, 0x69, 0x64, 0x01);
  ok('CBOR 嵌套深度超过 MAX_DEPTH(16) 返回 null',
    SpiderInfo.readCborHeaderStream(makeBinaryStream(deepBytes)) === null);

  // 通过 UniFile 读取磁盘 CBOR .ehviewer
  const cborDir: string = '/tmp/m42_cbor_spiderinfo';
  fs.mkdirSync(cborDir, true);
  const cborPath: string = `${cborDir}/.ehviewer`;
  const cborFileHandle: fs.File = fs.openSync(cborPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(cborFileHandle.fd, new Uint8Array(definiteBytes).buffer as ArrayBuffer);
  fs.closeSync(cborFileHandle);
  const cborUni: UniFile | null = UniFile.fromFile(cborPath);
  const diskCborInfo: SpiderInfo | null = SpiderInfo.readCborHeader(cborUni);
  ok('CBOR UniFile 磁盘读取成功',
    diskCborInfo !== null && diskCborInfo.gid === 900000002 && diskCborInfo.token === '0000000000');
}

// ================================================================ 2) MSQLiteBuilder

{
  const b: MSQLiteBuilder = new MSQLiteBuilder();
  b.version(1);
  b.createTable('t');
  b.insertColumn('t', 'c', SqlType.STRING);
  eq('迁移语句 1', b.getStatements(0, 1), [
    'CREATE TABLE t (_id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY);',
    'ALTER TABLE t ADD COLUMN c TEXT;'
  ]);

  b.version(3);
  b.statement('DROP TABLE t;');
  eq('版本区间 [1,1] 为空（没有 version 2 的语句）', b.getStatements(1, 1), []);
  eq('版本区间 [2,3] 只含 v3 语句', b.getStatements(2, 3), ['DROP TABLE t;']);
  eq('版本区间 [0,3] 汇总', b.getStatements(0, 3).length, 3);
  eq('getVersion', b.getVersion(), 3);

  // 类型映射与上游一致
  const b2: MSQLiteBuilder = new MSQLiteBuilder();
  b2.version(1).createTableTyped('t2', 'k', SqlType.LONG);
  eq('LONG 类型映射', b2.getStatements(0, 1), ['CREATE TABLE t2 (k INTEGER NOT NULL DEFAULT 0 PRIMARY KEY);']);
  const b3: MSQLiteBuilder = new MSQLiteBuilder();
  b3.version(1).createTableTyped('t3', 'k', SqlType.FLOAT);
  eq('FLOAT 类型映射', b3.getStatements(0, 1), ['CREATE TABLE t3 (k REAL NOT NULL DEFAULT 0 PRIMARY KEY);']);

  // 未调 version 就加语句 / 版本不递增 必须抛错（上游 IllegalStateException）
  let threw: boolean = false;
  try {
    new MSQLiteBuilder().statement('X;');
  } catch (e) {
    threw = true;
  }
  ok('未 version() 就 statement() 抛错', threw);

  let threw2: boolean = false;
  try {
    const b4: MSQLiteBuilder = new MSQLiteBuilder();
    b4.version(2);
    b4.version(2);
  } catch (e) {
    threw2 = true;
  }
  ok('version 不递增抛错', threw2);
}

// ================================================================ 3) Filter equals/hashCode

{
  const a: Filter = new Filter(undefined, 1, 'tag');
  const b: Filter = new Filter(99, 1, 'tag');       // id 不同也算相等（上游只比 mode+text）
  const c: Filter = new Filter(undefined, 2, 'tag');
  ok('Filter.equals 忽略 id', a.equals(b));
  ok('Filter.equals 区分 mode', !a.equals(c));

  // 上游 HashCodeUtils.hashCode(mode, text) = 31*(mode) + javaStringHash(text)
  // 'abc' 的 Java String.hashCode = 96354
  const f: Filter = new Filter(undefined, 0, 'abc');
  eq('Filter.hashCode(mode=0,text=abc)', f.hashCode(), 96354);
  const g: Filter = new Filter(undefined, 1, 'abc');
  eq('Filter.hashCode(mode=1,text=abc)', g.hashCode(), 31 + 96354);
  // 空 text：上游 text.hashCode() 为 0（null 也是 0）
  const h: Filter = new Filter(undefined, 3, undefined);
  eq('Filter.hashCode(text=undefined)', h.hashCode(), 31 * 3);
}

// ================================================================ 9) 缺依赖分支必须"显式抛错"，不能静默返回 null

{
  // 上游 getSpiderInfo(GalleryInfo) 依赖 SpiderDen.getGalleryDownloadDir；
  // 我把它收敛成 DownloadDirProvider 注入点。未注入时**必须抛错**：
  // 若静默返回 null，调用方会以为"没下载过"，于是重新下载整个画廊 —— 静默的行为降级。
  let threw: boolean = false;
  let msg: string = '';
  try {
    const info: SpiderInfo = makeInfo();
    const g: GalleryInfo = new GalleryInfo();
    g.gid = info.gid;
    // SpiderInfo.token 是 string | null（C-13），GalleryInfo.token 是 string\n    g.token = info.token !== null ? info.token : '';
    SpiderInfo.getSpiderInfoByGalleryInfo(g);
  } catch (e) {
    threw = true;
    msg = (e as Error).message !== undefined ? (e as Error).message : '';
  }
  ok('未注入 DownloadDirProvider → 抛错（不是返回 null）', threw);
  ok('错误信息指出缺什么（DownloadDirProvider）', msg.indexOf('DownloadDirProvider') >= 0);
}

{
  // P0 #2: getSpiderInfoByGalleryDetail 使用 GalleryDetail + GalleryPageUrlParser 构建 SpiderInfo
  eq('getSpiderInfoByGalleryDetail(null) → null', SpiderInfo.getSpiderInfoByGalleryDetail(null), null);

  const emptyDetail: GalleryDetail = new GalleryDetail();
  emptyDetail.gid = 555;
  emptyDetail.token = 'tok555';
  emptyDetail.SpiderInfoPages = 0;
  eq('pages <= 0 → null', SpiderInfo.getSpiderInfoByGalleryDetail(emptyDetail), null);

  const detail: GalleryDetail = new GalleryDetail();
  detail.gid = 12345;
  detail.token = 'abcd9999';
  detail.SpiderInfoPages = 10;
  detail.SpiderInfoPreviewPages = 2;
  const pset: LargePreviewSet = new LargePreviewSet();
  pset.addItem(0, 'https://ehgt.org/t1.jpg', 'https://e-hentai.org/s/abcdef0123/12345-1');
  pset.addItem(1, 'https://ehgt.org/t2.jpg', 'https://exhentai.org/s/0123456789/12345-2');
  detail.SpiderInfoPreviewSet = pset;

  const built: SpiderInfo | null = SpiderInfo.getSpiderInfoByGalleryDetail(detail);
  ok('P0 #2: getSpiderInfoByGalleryDetail 返回非 null', built !== null);
  if (built !== null) {
    eq('P0 #2: gid 一致', built.gid, 12345);
    eq('P0 #2: token 一致', built.token, 'abcd9999');
    eq('P0 #2: pages 一致', built.pages, 10);
    eq('P0 #2: previewPages 一致', built.previewPages, 2);
    eq('P0 #2: previewPerPage = previewSet.size()', built.previewPerPage, 2);
    ok('P0 #2: 解析第 0 页 pToken', built.pTokenMap !== null && built.pTokenMap.get(0) === 'abcdef0123');
    ok('P0 #2: 解析第 1 页 pToken', built.pTokenMap !== null && built.pTokenMap.get(1) === '0123456789');
  }

  // P1 #11: writeNewSpiderInfoToLocal 同步写入本地 .ehviewer 与 SimpleDiskCache
  const dlDirPath: string = '/tmp/m42_spiderinfo_dl';
  fs.mkdirSync(dlDirPath, true);
  const dlDir: UniFile | null = UniFile.fromFile(dlDirPath);
  const infoCache: SimpleDiskCache = new SimpleDiskCache('/tmp/m42_spiderinfo_cache', 1024 * 1024);
  if (built !== null) {
    built.startPage = 3;
    built.writeNewSpiderInfoToLocal(dlDir, infoCache);
    ok('P1 #11: 本地 .ehviewer 已写出', dlDir !== null && dlDir.findFile(SPIDER_INFO_FILENAME) !== null);
    ok('P1 #11: SimpleDiskCache 已按 gid 回写 SpiderInfo', infoCache.contain('12345'));
    const cachePipe: InputStreamPipe | null = infoCache.getInputStreamPipe('12345');
    if (cachePipe !== null) {
      cachePipe.obtain();
      const cacheFile: fs.File = cachePipe.open();
      const stat: fs.Stat = fs.statSync(cacheFile.fd);
      ok('P1 #11: 缓存内容非空', stat.size > 0);
      cachePipe.close();
      cachePipe.release();
    }
    const readLocal: SpiderInfo | null = SpiderInfo.readHeaderFile(
      dlDir !== null ? dlDir.findFile(SPIDER_INFO_FILENAME) : null
    );
    eq('P1 #11: 本地 .ehviewer 读回 startPage = 3', readLocal !== null ? readLocal.startPage : -1, 3);
  }
}

{
  // 注入一个"永远返回 null 的目录"的 provider：此时不应抛错，而是按上游语义返回 null
  // （目录不存在 / 没有 spider_info / gid-token 不匹配 都归到 null）
  SpiderInfo.setDownloadDirProvider({
    getGalleryDownloadDir: (info: GalleryInfo): UniFile | null => null
  });
  const g: GalleryInfo = new GalleryInfo();
  g.gid = 1;
  g.token = 'x';
  const result: SpiderInfo | null = SpiderInfo.getSpiderInfoByGalleryInfo(g);
  ok('provider 返回 null 目录 → 结果 null（不抛错）', result === null);
  SpiderInfo.setDownloadDirProvider(null as unknown as DownloadDirProvider);
}
// ================================================================ 汇总

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
