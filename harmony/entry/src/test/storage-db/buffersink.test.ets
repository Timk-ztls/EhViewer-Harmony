/*
 * BufferSink 单测（ArchiveGalleryProvider 的解压缓冲核心，纯逻辑）
 *
 * 为什么值得测：压缩包条目的解压结果是 `writeBytes` **多次分块**写进来的（7z 的解压回调按块返回），
 * 而解码 API `image.createImageSource(buffer)` 要**一段连续内存**。合并逻辑写错的表现是
 * 「图片打开但花了 / 只显示上半部分 / 解码返回 null」——三种都不报错，只在看图时暴露。
 *
 * 另外钉住 64MB 上限：损坏的归档条目可以声称任意大小，没有上限就是 OOM 崩溃。
 */

import { BufferSink, MAX_BUFFER_BYTES } from '../../main/ets/hippo/ehviewer/gallery/ArchiveGalleryProvider';
import { UniFile, RawFile, TreeDocumentFile } from '../../main/ets/hippo/unifile/UniFile';
import { Contracts, FsInputStream } from '../../main/ets/hippo/unifile/Contracts';
import { DocumentsContractApi19 } from '../../main/ets/hippo/unifile/DocumentsContractApi19';
import { MediaContract } from '../../main/ets/hippo/unifile/MediaContract';
import { FileDescriptorRandomAccessFile } from '../../main/ets/hippo/unifile/FileDescriptorRandomAccessFile';
import { Settings } from '../../main/ets/hippo/ehviewer/Settings';
import fs from '@ohos.file.fs';

interface FsRegressHook {
  __activeFdCount?: () => number;
  __seedFile?: (p: string, data: string | Uint8Array) => void;
}

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

function bytes(values: number[]): ArrayBuffer {
  const buf: ArrayBuffer = new ArrayBuffer(values.length);
  const view: Uint8Array = new Uint8Array(buf);
  for (let i = 0; i < values.length; i++) {
    view[i] = values[i];
  }
  return buf;
}

function toArray(buf: ArrayBuffer): number[] {
  const view: Uint8Array = new Uint8Array(buf);
  const out: number[] = [];
  for (let i = 0; i < view.length; i++) {
    out.push(view[i]);
  }
  return out;
}

// ================================================================ 1) 常量

eq('MAX_BUFFER_BYTES = 64MB', MAX_BUFFER_BYTES, 64 * 1024 * 1024);

// ================================================================ 2) 基本写入与合并

{
  const sink: BufferSink = new BufferSink();
  eq('初始长度 0', sink.byteLength(), 0);
  sink.write(bytes([1, 2, 3]));
  eq('write 后长度 3', sink.byteLength(), 3);
  sink.write(bytes([4, 5]));
  eq('两次 write 后长度 5', sink.byteLength(), 5);
  eq('合并结果按写入顺序', toArray(sink.toArrayBuffer()), [1, 2, 3, 4, 5]);
}

// ================================================================ 3) writeBytes 的 off/len（7z 回调的真实形态）

{
  const sink: BufferSink = new BufferSink();
  // 一整块里只取中间 3 个字节（模拟"缓冲区 8 字节，本次有效 3 字节"）
  sink.writeBytes(bytes([0xaa, 0xbb, 0x11, 0x22, 0x33, 0xcc, 0xdd, 0xee]), 2, 3);
  eq('只取 [2,5) 三个字节', toArray(sink.toArrayBuffer()), [0x11, 0x22, 0x33]);

  // 连续两次带偏移写入，验证不串位
  sink.writeBytes(bytes([9, 9, 0x44]), 2, 1);
  sink.writeBytes(bytes([0x55, 8, 8]), 0, 1);
  eq('多次偏移写入拼接正确', toArray(sink.toArrayBuffer()), [0x11, 0x22, 0x33, 0x44, 0x55]);
}

// ================================================================ 4) 写入后源缓冲被改动不影响已写入内容（必须拷贝）

{
  const sink: BufferSink = new BufferSink();
  const src: ArrayBuffer = bytes([1, 2, 3, 4]);
  sink.writeBytes(src, 0, 4);
  // 7z 回调会复用同一块缓冲 —— 若 sink 只存引用，第二次写入会把第一次的数据冲掉
  const view: Uint8Array = new Uint8Array(src);
  view[0] = 0xff;
  view[1] = 0xff;
  eq('sink 独立持有副本', toArray(sink.toArrayBuffer()), [1, 2, 3, 4]);
}

// ================================================================ 5) 64MB 上限（用可注入的小上限验证，避免真分配 64MB）

{
  const sink: BufferSink = new BufferSink(8);
  sink.write(bytes([1, 2, 3, 4, 5, 6, 7, 8]));
  eq('恰好 8 字节允许', sink.byteLength(), 8);

  let threw: boolean = false;
  try {
    sink.write(bytes([9]));
  } catch (e) {
    threw = true;
  }
  ok('超过上限抛错', threw);
  eq('超限后长度不变（未半途写入）', sink.byteLength(), 8);
  eq('超限后内容不被污染', toArray(sink.toArrayBuffer()), [1, 2, 3, 4, 5, 6, 7, 8]);

  // writeBytes 的 len 也要计入上限
  const sink2: BufferSink = new BufferSink(4);
  let threw2: boolean = false;
  try {
    sink2.writeBytes(bytes([1, 2, 3, 4, 5, 6]), 0, 6);
  } catch (e) {
    threw2 = true;
  }
  ok('writeBytes 超限同样抛错', threw2);
  eq('抛错时一个字节都没写进去', sink2.byteLength(), 0);
}

// ================================================================ 6) 空写入与 flush/close

{
  const sink: BufferSink = new BufferSink();
  sink.write(bytes([]));
  eq('空 write 不改变长度', sink.byteLength(), 0);
  sink.writeBytes(bytes([1, 2]), 0, 0);
  eq('len=0 不改变长度', sink.byteLength(), 0);
  sink.flush();
  sink.close();
  eq('flush/close 不影响已写内容', sink.byteLength(), 0);
  eq('空 sink 的 toArrayBuffer 是空数组', toArray(sink.toArrayBuffer()), []);
}

// ================================================================ 7) P0 #4: Settings DownloadLocation + UniFile.fromUri + MediaContract

{
  const dlPath: string = '/tmp/m42_dl_location';
  const loc: UniFile | null = UniFile.fromFile(dlPath);
  ok('构造 RawFile 下载目录', loc !== null);
  if (loc !== null) {
    Settings.putDownloadLocation(loc);
    const loaded: UniFile | null = Settings.getDownloadLocation();
    ok('P0 #4: getDownloadLocation 往返非空', loaded !== null);
    if (loaded !== null) {
      ok('P0 #4: 还原后的 URI 保留 file:// 前缀 (Contracts.isUri=true)', Contracts.isUri(loaded.getUri()));
      ok('P0 #4: 不存在目录的 file:///... 还原为 RawFile（不退化 SingleDocumentFile）', loaded instanceof RawFile);
      ok('P0 #4: 还原后的目录可 ensureDir 并 createFile', loaded.ensureDir() && loaded.subFile('test.txt') !== null);
    }
  }

  // file://docs/... 目录走 TreeDocumentFile；file:///... 不走 DocumentFile
  eq('P0 #4: file:///tmp/x → isFileUri=true', UniFile.isFileUri('file:///tmp/x'), true);
  eq('P0 #4: file:///tmp/x → isDocumentUri=false', UniFile.isDocumentUri('file:///tmp/x'), false);
  eq('P0 #4: file://docs/tmp/x → isFileUri=false', UniFile.isFileUri('file://docs/tmp/x'), false);
  eq('P0 #4: file://docs/tmp/x → isDocumentUri=true', UniFile.isDocumentUri('file://docs/tmp/x'), true);

  fs.mkdirSync('/tmp/m42_tree_doc', true);
  const treeFile: UniFile | null = UniFile.fromUri('file://docs/tmp/m42_tree_doc');
  ok('P0 #4: file://docs/已有目录 → TreeDocumentFile', treeFile instanceof TreeDocumentFile);

  // MediaContract.isMediaTarget 不再把 'file://media/Photo/1/img.jpg' 错剥成 '/Photo/...'
  const fsHook: FsRegressHook = fs as unknown as FsRegressHook;
  const mediaUri: string = 'file://media/Photo/1/IMG_001.jpg';
  eq('P0 #4: 不存在的 file://media URI 返回 false', MediaContract.isMediaTarget(mediaUri), false);
  if (fsHook.__seedFile !== undefined) {
    fsHook.__seedFile(mediaUri, new Uint8Array([0xff, 0xd8, 0xff]));
    eq('P0 #4: 可打开的非目录 media URI 通过 openSync+statSync(fd) 返回 true',
      MediaContract.isMediaTarget(mediaUri), true);
  }
}

// ================================================================ 8) P1 #12: FsInputStream.skip(lseek), DocumentsContractApi19.delete(递归), FileDescriptorRandomAccessFile

{
  const fsHook: FsRegressHook = fs as unknown as FsRegressHook;
  const baseFds: number = fsHook.__activeFdCount !== undefined ? fsHook.__activeFdCount() : 0;

  // FsInputStream.skip 真实通过 lseek 移动内核偏移
  const skipFile: string = '/tmp/m42_skip.bin';
  const f1: fs.File = fs.openSync(skipFile, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(f1.fd, new Uint8Array([10, 11, 12, 13, 14, 15]).buffer);
  fs.closeSync(f1);

  const is: FsInputStream = new FsInputStream(skipFile);
  eq('P1 #12: FsInputStream.skip(3) 返回 3', is.skip(3), 3);
  const tail: ArrayBuffer = new ArrayBuffer(3);
  const nRead: number = is.readBuffer(tail);
  eq('P1 #12: skip(3) 后读出后续 3 字节', nRead, 3);
  eq('P1 #12: 读取的是 [13, 14, 15]（证明内核指针确被 lseek 移动）', toArray(tail), [13, 14, 15]);
  is.close();
  if (fsHook.__activeFdCount !== undefined) {
    eq('P1 #12: FsInputStream 关闭后无 FD 泄漏', fsHook.__activeFdCount(), baseFds);
  }

  // DocumentsContractApi19.delete 对非空目录递归删除
  fs.mkdirSync('/tmp/m42_doc_del/sub', true);
  const fSub: fs.File = fs.openSync('/tmp/m42_doc_del/sub/a.dat', fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
  fs.closeSync(fSub);
  eq('P1 #12: DocumentsContractApi19.delete 递归删除非空目录返回 true',
    DocumentsContractApi19.delete('file:///tmp/m42_doc_del'), true);
  eq('P1 #12: 目录确已删除', fs.accessSync('/tmp/m42_doc_del'), false);

  // FileDescriptorRandomAccessFile mode 校验 & readBytes/writeBytes 边界校验 & lseek
  let badModeThrew: boolean = false;
  try {
    FileDescriptorRandomAccessFile.create('/tmp/m42_raf.bin', 'bad_mode');
  } catch (e) {
    badModeThrew = true;
  }
  ok('P1 #12: 非法 mode 抛错', badModeThrew);

  const raf: FileDescriptorRandomAccessFile = FileDescriptorRandomAccessFile.create('/tmp/m42_raf.bin', 'rw');
  raf.write(bytes([1, 2, 3, 4, 5, 6]));
  raf.seek(2);
  const gotBuf: ArrayBuffer = new ArrayBuffer(4);
  eq('P1 #12: seek(2) 后 readBytes 读出 2 字节', raf.readBytes(gotBuf, 1, 2), 2);
  eq('P1 #12: readBytes(off=1,len=2) 写入槽位 [0,3,4,0]', toArray(gotBuf), [0, 3, 4, 0]);

  let oobReadThrew: boolean = false;
  try {
    raf.readBytes(gotBuf, -1, 2);
  } catch (e) {
    oobReadThrew = true;
  }
  ok('P1 #12: 负偏移 readBytes 抛 RangeError', oobReadThrew);

  let oobWriteThrew: boolean = false;
  try {
    raf.writeBytes(gotBuf, 2, 5); // 2+5 > 4
  } catch (e) {
    oobWriteThrew = true;
  }
  ok('P1 #12: 越界 writeBytes 抛 RangeError', oobWriteThrew);
  raf.close();
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
