/*
 * download-sync 纯逻辑单测：Arc 归档导入链路（C-10：harmony/entry/src/test/<module>/）
 *
 * 本文件的定位 —— **把 7z 后端与 Arc 导入之间那层契约钉住**，这是目前唯一横跨
 * native-image / storage-db / download-sync 三方的接缝：
 *
 *   native-image 交付：extract7z(archive: ArrayBuffer, outDir: string, password?): number
 *                      （整体解压到目录，返回文件数，错误码 7001–7004）
 *   storage-db  交付：A7ZipArchive + A7ZipBridge（**逐条目** open/entryCount/entryPath/extractEntry）
 *   download-sync 需要：按**条目顺序**把图片写成 SpiderDen 的 %08d.jpg（上游 unzipArchive 行为）
 *
 * 三者形状不一致：extract7z 是"整体解压到目录"，A7ZipBridge 是"逐条目吐流"。
 * 本测试用**假桥（FakeBridge）**驱动 A7ZipArchive，验证：
 *   1. 归档级拒绝规则（加密 / 固实 / 分卷）在上层就能被拦住，不必等 native；
 *   2. 条目枚举顺序就是写入顺序 —— 这是"编号序 = zip 条目序"（上游行为）成立的前提，
 *      也是当前 ArchiverDownloadCompleter 走 zlib 整体解压时**丢失**的那条信息（D-η）；
 *   3. extractEntry 的 sink 收到的字节与条目一一对应（能正确落 %08d 文件）。
 *
 * 一旦 native-image 把 A7ZipBridge 实现出来（或提供一个"逐条目"适配层），
 * 断言 2/3 就是 ArchiverDownloadCompleter 从 zlib 切回 A7ZipArchive 的验收标准。
 *
 * 运行：pwsh -File harmony/entry/src/test/download-sync/run.ps1
 *      （与 storage-db / gl-render 的约定一致：整棵树原结构镜像成 .ts，不改 import）
 */

import { A7ZipArchive, A7ZipBridge, PropId, PropType } from '../../main/ets/hippo/ehviewer/gallery/A7ZipArchive';
import { InputStream, OutputStream } from '../../main/ets/hippo/unifile/Contracts';
import { UniRandomAccessFile } from '../../main/ets/hippo/unifile/UniRandomAccessFile';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
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

function throws(name: string, body: () => void, expectSubstring: string): void {
  try {
    body();
    fails.push(`${name}\n    expected throw containing "${expectSubstring}", nothing thrown`);
  } catch (e) {
    const msg: string = (e as Error).message;
    if (msg.indexOf(expectSubstring) >= 0) {
      pass++;
    } else {
      fails.push(`${name}\n    got "${msg}"\n    want contains "${expectSubstring}"`);
    }
  }
}

/** 假归档：条目 = [路径, 内容]，按给定顺序枚举（顺序即断言对象）。 */
class FakeArchive {
  public encrypted: boolean = false;
  public solid: boolean = false;
  public volume: boolean = false;
  public entries: string[][] = [];
  public opened: boolean = false;
  public closed: boolean = false;
}

/** 把写入的字节收集起来，模拟 UniFile 的 OutputStream。 */
class CollectingSink implements OutputStream {
  public chunks: string[] = [];
  public flushed: boolean = false;

  write(buffer: ArrayBuffer): void {
    this.chunks.push(String.fromCharCode(...new Uint8Array(buffer)));
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    const view: Uint8Array = new Uint8Array(buffer);
    let s: string = '';
    for (let i = 0; i < len; i++) {
      s += String.fromCharCode(view[off + i]);
    }
    this.chunks.push(s);
  }

  flush(): void {
    this.flushed = true;
  }

  close(): void {
  }
}

/** 按 A7ZipBridge 契约实现（native 侧的替身）。 */
class FakeBridge implements A7ZipBridge {
  public archive: FakeArchive;

  constructor(archive: FakeArchive) {
    this.archive = archive;
  }

  open(file: UniRandomAccessFile): number {
    this.archive.opened = true;
    return 0x7A;      // 任意非 0 句柄
  }

  close(handle: number): void {
    this.archive.closed = true;
  }

  entryCount(handle: number): number {
    return this.archive.entries.length;
  }

  entryPath(handle: number, index: number): string {
    return this.archive.entries[index][0];
  }

  entryBoolean(handle: number, index: number, prop: string): boolean {
    if (prop === PropId.IS_DIR) {
      return this.archive.entries[index][0].endsWith('/');
    }
    return false;
  }

  archivePropertyType(handle: number, prop: string): string {
    if (prop === PropId.ENCRYPTED && this.archive.encrypted) {
      return PropType.BOOL;
    }
    if (prop === PropId.SOLID && this.archive.solid) {
      return PropType.BOOL;
    }
    if (prop === PropId.IS_VOLUME && this.archive.volume) {
      return PropType.BOOL;
    }
    return PropType.NONE;
  }

  archiveBoolean(handle: number, prop: string): boolean {
    if (prop === PropId.ENCRYPTED) {
      return this.archive.encrypted;
    }
    if (prop === PropId.SOLID) {
      return this.archive.solid;
    }
    if (prop === PropId.IS_VOLUME) {
      return this.archive.volume;
    }
    return false;
  }

  extractEntry(handle: number, index: number, sink: OutputStream): void {
    sink.writeBytes(new TextEncoder().encode(this.archive.entries[index][1]).buffer as ArrayBuffer, 0,
      this.archive.entries[index][1].length);
    sink.flush();
  }
}

/** 造一个不做任何 IO 的 UniRandomAccessFile 替身（create() 只把它透传给 bridge）。 */
function fakeRandomAccess(): UniRandomAccessFile {
  return {} as UniRandomAccessFile;
}

function main(): void {
  // ---------------------------------------------------------------- 1) 拒绝规则
  const enc: FakeArchive = new FakeArchive();
  enc.encrypted = true;
  A7ZipArchive.setBridge(new FakeBridge(enc));
  throws('加密归档必须被拒（上游 ArchiveException("Unsupported archive")）',
    () => { A7ZipArchive.create(fakeRandomAccess()); }, 'Unsupported archive');

  const solid: FakeArchive = new FakeArchive();
  solid.solid = true;
  A7ZipArchive.setBridge(new FakeBridge(solid));
  throws('固实归档必须被拒', () => { A7ZipArchive.create(fakeRandomAccess()); }, 'Unsupported archive');

  const vol: FakeArchive = new FakeArchive();
  vol.volume = true;
  A7ZipArchive.setBridge(new FakeBridge(vol));
  throws('分卷归档必须被拒', () => { A7ZipArchive.create(fakeRandomAccess()); }, 'Unsupported archive');

  // ---------------------------------------------------------------- 2) 条目顺序
  const plain: FakeArchive = new FakeArchive();
  plain.entries = [
    ['vol1/007.jpg', 'G'],
    ['vol1/001.jpg', 'A'],
    ['vol1/003.jpg', 'C'],
    ['vol1/002.jpg', 'B']
  ];
  A7ZipArchive.setBridge(new FakeBridge(plain));
  const archive: A7ZipArchive = A7ZipArchive.create(fakeRandomAccess());

  eq('entryCount 必须等于归档条目数', archive.entryCount(), 4);
  eq('entryName(0) 必须是**条目序**第一个（不是字典序）', archive.entryName(0), 'vol1/007.jpg');
  eq('entryName(1) 保持条目序', archive.entryName(1), 'vol1/001.jpg');

  // 这是 D-η 的核心：按条目序编号 -> 007/001/003/002 -> 00000001..00000004
  const order: string[] = [];
  for (let i = 0; i < archive.entryCount(); i++) {
    order.push(archive.entryName(i));
  }
  eq('按条目序枚举（写入顺序 = 上游 %08d 编号顺序）', order,
    ['vol1/007.jpg', 'vol1/001.jpg', 'vol1/003.jpg', 'vol1/002.jpg']);

  // ---------------------------------------------------------------- 3) 条目内容
  const sink: CollectingSink = new CollectingSink();
  archive.openEntry(2, sink);
  eq('openEntry(2) 取到第 3 个条目的字节', sink.chunks.join(''), 'C');
  ok('extractEntry 之后 sink 被 flush', sink.flushed);

  const sink0: CollectingSink = new CollectingSink();
  archive.openEntry(0, sink0);
  eq('openEntry(0) 取到第 1 个条目的字节', sink0.chunks.join(''), 'G');

  // ---------------------------------------------------------------- 4) 句柄生命周期
  archive.close();
  ok('close() 必须把关闭透传给 bridge', plain.closed);

  // ---------------------------------------------------------------- 5) 无桥时报错清晰
  A7ZipArchive.setBridge(null);
  throws('未注入 bridge 时必须抛「后端未接入」而不是静默失败',
    () => { A7ZipArchive.create(fakeRandomAccess()); }, '7z 解压后端未接入');

  // ---------------------------------------------------------------- 6) 含目录/非图片条目时，openEntry 按原始下标映射
  const mixed: FakeArchive = new FakeArchive();
  mixed.entries = [
    ['vol1/', 'DIR'],
    ['vol1/readme.txt', 'TXT'],
    ['vol1/002.jpg', 'IMG2'],
    ['vol1/001.jpg', 'IMG1']
  ];
  A7ZipArchive.setBridge(new FakeBridge(mixed));
  const mixedArc: A7ZipArchive = A7ZipArchive.create(fakeRandomAccess());
  eq('过滤目录与 txt 后剩余 2 张图', mixedArc.entryCount(), 2);
  eq('过滤后第 0 张为 002.jpg', mixedArc.entryName(0), 'vol1/002.jpg');
  const mixedSink0: CollectingSink = new CollectingSink();
  mixedArc.openEntry(0, mixedSink0);
  eq('openEntry(0) 必须映射到原始条目下标 2（IMG2），而非目录下标 0',
    mixedSink0.chunks.join(''), 'IMG2');
  const mixedSink1: CollectingSink = new CollectingSink();
  mixedArc.openEntry(1, mixedSink1);
  eq('openEntry(1) 必须映射到原始条目下标 3（IMG1）',
    mixedSink1.chunks.join(''), 'IMG1');

  // ---------------------------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('arc-import test failed');
  }
  console.log(`✓ arc-import: ${pass} 条断言全部通过`);
}

main();
