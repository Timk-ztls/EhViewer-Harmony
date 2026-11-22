/*
 * ArchiveGalleryProvider 错误路径单测（假 A7ZipBridge + 假 fs）
 *
 * 压缩包链路有四条失败分支，上游都只做「置错误 / 通知失败」，**不会崩、也不会报错到日志以外**：
 *   1. 文件打不开        → size() = STATE_ERROR(-2)，getError() = error_reading_failed
 *   2. 不是合法归档      → size() = STATE_ERROR，getError() = error_invalid_archive
 *   3. 请求越界          → notifyPageFailed(index, error_out_of_range)
 *   4. 条目解压/解码失败 → notifyPageFailed(index, error_decoding_failed)
 * 这些是用户真实会遇到的（下载的压缩包损坏、索引算错）。没有断言时，只有代码级审阅能保证。
 *
 * 造法：
 *   - `A7ZipArchive.setBridge(fake)` 注入假 7z 后端（不碰 NDK）
 *   - fs 桩约定：路径含 `unopenable` 时 openSync 抛错 → 覆盖分支 1
 *   - 假 bridge 的 `open()` 抛错 → 覆盖分支 2
 *   - 假 bridge 正常但 `extractEntry()` 不写任何字节 → 空条目 → 覆盖分支 4
 */

import { ArchiveGalleryProvider } from '../../main/ets/hippo/ehviewer/gallery/ArchiveGalleryProvider';
import fs from '@ohos.file.fs';
import { A7ZipArchive, A7ZipBridge, A7ZipArchiveEntry, PropType } from '../../main/ets/hippo/ehviewer/gallery/A7ZipArchive';
import { BufferSink } from '../../main/ets/hippo/ehviewer/gallery/ArchiveGalleryProvider';
import { Contracts } from '../../main/ets/hippo/unifile/Contracts';
import { UniRandomAccessFile } from '../../main/ets/hippo/unifile/UniRandomAccessFile';
import { GalleryProvider, GalleryListener } from '../../main/ets/hippo/lib/glgallery/GalleryProvider';
import { ImageWrapper } from '../../main/ets/hippo/lib/glview/image/ImageWrapper';
import { UniFile } from '../../main/ets/hippo/unifile/UniFile';
import { OutputStream } from '../../main/ets/hippo/unifile/Contracts';
import { GLRoot, GLRootOnGLIdleListener } from '../../main/ets/hippo/lib/glview/view/GLRoot';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { Matrix } from '../../main/ets/hippo/lib/glview/util/Matrix';
import { CanvasAnimation } from '../../main/ets/hippo/lib/glview/anim/CanvasAnimation';
import { OrientationSource } from '../../main/ets/hippo/lib/glview/view/OrientationSource';
import { GLView } from '../../main/ets/hippo/lib/glview/view/GLView';

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

/** 记录 listener 收到的事件（通知在无 GLRoot 时会被基类丢弃，所以这里主要验证"不崩 + 状态正确"）。 */
class Recorder implements GalleryListener {
  dataChanged: number = 0;
  fails2: string[] = [];
  succeeds: number = 0;
  waits: number = 0;
  percents: number = 0;

  onDataChanged(): void {
    this.dataChanged++;
  }

  onDataChangedAt(index: number): void {
    this.dataChanged++;
  }

  onPageWait(index: number): void {
    this.waits++;
  }

  onPagePercent(index: number, percent: number): void {
    this.percents++;
  }

  onPageSucceed(index: number, image: ImageWrapper): void {
    this.succeeds++;
  }

  onPageFailed(index: number, error: string): void {
    this.fails2.push(`${index}:${error}`);
  }
}

/** 假 7z 后端：条目名固定，open 可按需失败，extract 可写出指定字节。 */
class FakeBridge implements A7ZipBridge {
  private readonly mNames: string[];
  private readonly mFailOpen: boolean;
  private readonly mPayload: number[];
  extractCalls: number = 0;
  /** 记录被解压的条目下标（顺序）与路径，用于断言「页号 → 归档内自然序条目」的映射。 */
  extractedIndices: number[] = [];
  extractedPaths: string[] = [];

  constructor(names: string[], failOpen: boolean, payload: number[]) {
    this.mNames = names;
    this.mFailOpen = failOpen;
    this.mPayload = payload;
  }

  open(file: UniRandomAccessFile): number {
    if (this.mFailOpen) {
      throw new Error('fake: not an archive');
    }
    return 1;
  }

  close(handle: number): void {
  }

  entryCount(handle: number): number {
    return this.mNames.length;
  }

  entryPath(handle: number, index: number): string {
    return this.mNames[index];
  }

  /** 上游 4 个布尔条目属性：假实现一律 false（= 不加密/不是目录/不分卷/不固实）。 */
  entryBoolean(handle: number, index: number, prop: string): boolean {
    return false;
  }

  /** 归档级属性类型：只对未加密/非固实/非分卷回答 BOOL，值由 archiveBoolean 给 false。 */
  archivePropertyType(handle: number, prop: string): string {
    return PropType.BOOL;
  }

  archiveBoolean(handle: number, prop: string): boolean {
    return false;
  }

  extractEntry(handle: number, index: number, sink: OutputStream): void {
    this.extractCalls++;
    this.extractedIndices.push(index);
    this.extractedPaths.push(this.mNames[index]);
    if (this.mPayload.length > 0) {
      const buf: ArrayBuffer = new ArrayBuffer(this.mPayload.length);
      const view: Uint8Array = new Uint8Array(buf);
      for (let i = 0; i < this.mPayload.length; i++) {
        view[i] = this.mPayload[i];
      }
      sink.writeBytes(buf, 0, this.mPayload.length);
    }
  }
}

/**
 * 假 GLRoot：**必须提供**，否则基类的通知会被静默丢弃（gl-render 明确说过：
 * 没有 listener 或没有 setGLRoot 时通知一律丢弃，上游如此）。
 * 这里只实现「挂 onGLIdle 监听 + 手动驱动」两件事，其余方法空实现。
 */
class FakeGLRoot implements GLRoot {
  private listeners: GLRootOnGLIdleListener[] = [];

  addOnGLIdleListener(listener: GLRootOnGLIdleListener): void {
    this.listeners.push(listener);
  }

  /** 驱动所有挂上的 onGLIdle，清空队列（基类在队列空时返回 false 并自行摘除）。 */
  drain(): void {
    const current: GLRootOnGLIdleListener[] = this.listeners;
    this.listeners = [];
    for (const l of current) {
      l.onGLIdle(null as unknown as GLCanvas, false);
    }
  }

  requestRender(): void {
  }

  requestRenderForced(): void {
  }

  requestLayoutContentPane(): void {
  }

  lockRenderThread(): void {
  }

  unlockRenderThread(): void {
  }

  freeze(): void {
  }

  unfreeze(): void {
  }

  getWidth(): number {
    return 1080;
  }

  getHeight(): number {
    return 1920;
  }

  // GLRoot 其余成员：测试里一律空实现（provider 不会用到这些）
  registerLaunchedAnimation(animation: CanvasAnimation): void {
  }

  setContentPane(content: GLView | null): void {
  }

  setOrientationSource(source: OrientationSource | null): void {
  }

  getDisplayRotation(): number {
    return 0;
  }

  getCompensation(): number {
    return 0;
  }

  getCompensationMatrix(): Matrix {
    return new Matrix();
  }

  setLightsOutMode(enabled: boolean): void {
  }
}

/** 等事件循环把 async archiveTask 推进到下一步（该任务没有外部可 await 的句柄）。 */
async function tick(times: number): Promise<void> {
  for (let i = 0; i < times; i++) {
    await Promise.resolve();
    await new Promise<void>((resolve) => setTimeout(resolve, 1));
  }
}

// ================================================================ 1) 初始状态必须等

{
  const file: UniFile | null = UniFile.fromFile('/tmp/a.zip');
  ok('构造 UniFile', file !== null);
  if (file !== null) {
    const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
    eq('start 之前 size() = STATE_WAIT', provider.size(), GalleryProvider.STATE_WAIT);
    eq('start 之前 getError() 为空', provider.getError(), '');
  }
}

// ================================================================ 2) 分支 1：文件打不开

async function caseOpenFailure(): Promise<void> {
  A7ZipArchive.setBridge(new FakeBridge(['1.jpg'], false, []));
  const file: UniFile | null = UniFile.fromFile('/tmp/unopenable.zip');
  if (file === null) {
    fails.push('无法构造 unopenable 文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();
  eq('打不开 → size() = STATE_ERROR', provider.size(), GalleryProvider.STATE_ERROR);
  // 文案来自 GetText（Node 里无资源管理器 → 空串），所以只断言状态机到达 ERROR；
  // 断言文案等于在测桩，不是测代码（与「不做模拟」同一原则）。
  eq('打不开 → getError() 是字符串', typeof provider.getError(), 'string');
  ok('打不开 → 发出了 dataChanged 通知', rec.dataChanged >= 1);
}

// ================================================================ 3) 分支 2：不是合法归档

interface FsActiveFdExt {
  __activeFdCount?: () => number;
}

async function caseInvalidArchive(): Promise<void> {
  const fsExt: FsActiveFdExt = fs as unknown as FsActiveFdExt;
  const fdsBefore: number = fsExt.__activeFdCount !== undefined ? fsExt.__activeFdCount() : 0;
  A7ZipArchive.setBridge(new FakeBridge(['1.jpg'], true, []));
  const file: UniFile | null = UniFile.fromFile('/tmp/notarchive.zip');
  if (file === null) {
    fails.push('无法构造非法归档文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();
  eq('非法归档 → size() = STATE_ERROR', provider.size(), GalleryProvider.STATE_ERROR);
  eq('非法归档 → getError() 是字符串', typeof provider.getError(), 'string');
  const fdsAfter: number = fsExt.__activeFdCount !== undefined ? fsExt.__activeFdCount() : 0;
  eq('P2 #14: A7ZipArchive.create 失败后已关闭 uraf，无 FD 泄漏', fdsAfter, fdsBefore);
}

// ================================================================ 4) 正常归档：条目数与自然序（b1,b2,b10 而不是 b1,b10,b2）

async function caseSortedEntries(): Promise<void> {
  A7ZipArchive.setBridge(new FakeBridge(['b10.jpg', 'b2.jpg', 'b1.jpg'], false, []));
  const file: UniFile | null = UniFile.fromFile('/tmp/ok.zip');
  if (file === null) {
    fails.push('无法构造正常归档文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();
  eq('条目数 = 3', provider.size(), 3);
  eq('合法归档 getError() 为空', provider.getError(), '');
  eq('getImageFilename 上游就是 index', provider.getImageFilename(0), '0');
  // 上游 save / save(dir, name) 都是 TODO → 必须保持 false / null，不能"顺手实现"
  ok('saveToFile 保持上游 TODO（false）', !provider.saveToFile(0, file));
  eq('saveToDir 保持上游 TODO（null）', provider.saveToDir(0, file, 'x'), null);
}

// ================================================================ 5) 分支 3：请求越界

async function caseOutOfRange(): Promise<void> {
  A7ZipArchive.setBridge(new FakeBridge(['1.jpg'], false, []));
  const file: UniFile | null = UniFile.fromFile('/tmp/ok2.zip');
  if (file === null) {
    fails.push('无法构造归档文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();
  provider.request(5);   // 只有 1 个条目
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();
  ok('越界请求 → 至少一次失败通知', rec.fails2.length >= 1);
  ok('越界请求 → 失败索引是 5', rec.fails2.length > 0 && rec.fails2[0].startsWith('5:'));
}

// ================================================================ 6) 分支 4：空条目 → 解码失败（不是崩溃）

async function caseEmptyEntry(): Promise<void> {
  const bridge: FakeBridge = new FakeBridge(['1.jpg'], false, []);  // payload 为空
  A7ZipArchive.setBridge(bridge);
  const file: UniFile | null = UniFile.fromFile('/tmp/empty.zip');
  if (file === null) {
    fails.push('无法构造归档文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();
  provider.request(0);
  await tick(4);
  gl.drain();
  await tick(1);
  gl.drain();
  ok('空条目 → 触发了 extract', bridge.extractCalls >= 1);
  ok('空条目 → 至少一次失败通知（不是静默）', rec.fails2.length >= 1);
}

// ================================================================ 7) 页号 → 归档条目映射（自然序，不是字节序）

async function caseEntryMapping(): Promise<void> {
  // 归档内实际顺序（字节序）：b10, b2, b1  → 自然序应为 b1, b2, b10
  const bridge: FakeBridge = new FakeBridge(['b10.jpg', 'b2.jpg', 'b1.jpg'], false, []);
  A7ZipArchive.setBridge(bridge);
  const file: UniFile | null = UniFile.fromFile('/tmp/map.zip');
  if (file === null) {
    fails.push('无法构造归档文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();

  eq('自然序后的条目数', provider.size(), 3);

  // 第 0 页必须是自然序第一个（b1），不是归档里的第一个（b10）
  provider.request(0);
  await tick(4);
  gl.drain();
  await tick(1);
  gl.drain();
  eq('第 0 页解压了 1 个条目', bridge.extractCalls, 1);
  eq('第 0 页 → 自然序第 1 个（b1.jpg）', bridge.extractedPaths[0], 'b1.jpg');

  // 第 2 页 → 自然序第 3 个（b10.jpg）——字节序会让它排第一，自然序必须排最后
  provider.request(2);
  await tick(4);
  gl.drain();
  await tick(1);
  gl.drain();
  eq('第 2 页 → 自然序第 3 个（b10.jpg）', bridge.extractedPaths[1], 'b10.jpg');
}

// ================================================================ 8) stop 后再请求不崩

async function caseStop(): Promise<void> {
  A7ZipArchive.setBridge(new FakeBridge(['1.jpg', '2.jpg'], false, []));
  const file: UniFile | null = UniFile.fromFile('/tmp/stop.zip');
  if (file === null) {
    fails.push('无法构造归档文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  provider.start();
  await tick(2);
  provider.stop();
  let threw: boolean = false;
  try {
    provider.request(0);
    provider.request(1);
    await tick(2);
  } catch (e) {
    threw = true;
  }
  ok('stop 后 request 不抛异常', !threw);
}

// ================================================================ 8) getArchiveEntries()（上游 A7ZipArchive.java:67）

async function caseArchiveEntries(): Promise<void> {
  // 归档内字节序 b10/b2/b1 + 一个非图片 + 一个目录（假 bridge 的 entryBoolean 全 false，
  // 所以目录需要靠"非图片后缀"来验证过滤）
  const bridge: FakeBridge = new FakeBridge(['b10.jpg', 'b2.jpg', 'b1.jpg', 'note.txt'], false, []);
  A7ZipArchive.setBridge(bridge);
  const file: UniFile | null = UniFile.fromFile('/tmp/entries.zip');
  if (file === null) {
    fails.push('无法构造归档文件');
    return;
  }
  const archive: A7ZipArchive = A7ZipArchive.create(file.createRandomAccessFile('r'));

  const entries: A7ZipArchiveEntry[] = archive.getArchiveEntries();
  eq('条目数 = 3（note.txt 已被 create() 过滤）', entries.length, 3);
  eq('顺序 = 归档内顺序（不排序）', entries.map((e: A7ZipArchiveEntry): string => e.getPath()),
    ['b10.jpg', 'b2.jpg', 'b1.jpg']);
  eq('getArchiveEntries 与 entryCount 一致', entries.length, archive.entryCount());
  eq('第 0 项路径同 entryName(0)', entries[0].getPath(), archive.entryName(0));
  // extract 走 openEntry
  const before: number = bridge.extractCalls;
  const sink: BufferSink = new BufferSink();
  entries[1].extract(sink);
  ok('extract 触发了 bridge.extractEntry', bridge.extractCalls === before + 1);
}
interface FsTestExt {
  __activeFdCount?: () => number;
  __seedFile: (path: string, data: Uint8Array | string) => void;
  __opened: string[];
}

// ================================================================ 9) RAR 魔数识别与明确提示（R1）

async function caseRarUnsupported(): Promise<void> {
  const fsExt: FsTestExt = fs as unknown as FsTestExt;
  const rarBytes = new Uint8Array([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00, 0x00]);
  fsExt.__seedFile('/tmp/sample_comic.cbr', rarBytes);
  const fdsBefore: number = fsExt.__activeFdCount !== undefined ? fsExt.__activeFdCount() : 0;

  A7ZipArchive.setBridge(new FakeBridge(['1.jpg'], false, []));
  const file: UniFile | null = UniFile.fromFile('/tmp/sample_comic.cbr');
  if (file === null) {
    fails.push('无法构造 RAR 测试文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  await tick(1);
  gl.drain();

  eq('RAR 魔数 → size() = STATE_ERROR', provider.size(), GalleryProvider.STATE_ERROR);
  ok('RAR 魔数 → getError() 非空', provider.getError().length > 0);
  ok('RAR 魔数 → 含 RAR 提示语义', provider.getError().toLowerCase().indexOf('rar') >= 0);
  const fdsAfter: number = fsExt.__activeFdCount !== undefined ? fsExt.__activeFdCount() : 0;
  eq('RAR 识别后无 fd 泄漏', fdsAfter, fdsBefore);
  provider.stop();
}

// ================================================================ 10) ZIP zlib fallback + Swiper 按页提取 + stop 清理（Z2）

async function caseZipZlibFallbackAndSwiper(): Promise<void> {
  const fsExt: FsTestExt = fs as unknown as FsTestExt;
  // PK\x03\x04 ZIP header
  fsExt.__seedFile('/tmp/fallback_comic.zip', new Uint8Array([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00]));
  A7ZipArchive.setBridge(new FakeBridge([], true, []));

  let createdExtractDir: string = '';
  ArchiveGalleryProvider.setZipFallbackExtractor(async (_srcPath: string, outDir: string): Promise<void> => {
    createdExtractDir = outDir;
    fsExt.__seedFile(`${outDir}/ch1/page10.jpg`, new Uint8Array([0xFF, 0xD8, 0xAA, 0x10]));
    fsExt.__seedFile(`${outDir}/ch1/page2.jpg`, new Uint8Array([0xFF, 0xD8, 0xAA, 0x02]));
    fsExt.__seedFile(`${outDir}/ch1/page1.png`, new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x01]));
    fsExt.__seedFile(`${outDir}/readme.txt`, 'ignored');
  });

  const file: UniFile | null = UniFile.fromFile('/tmp/fallback_comic.zip');
  if (file === null) {
    fails.push('无法构造 fallback zip 测试文件');
    return;
  }
  const provider: ArchiveGalleryProvider = new ArchiveGalleryProvider(file);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();

  const readySize: number = await provider.waitUntilReady();
  eq('zlib fallback → 仅保留图片且按自然序数为 3', readySize, 3);
  eq('zlib fallback → provider.size() = 3', provider.size(), 3);
  ok('zlib fallback 创建了解压临时目录', createdExtractDir.length > 0);

  // 验证按自然序映射到页号：0=page1.png, 1=page2.jpg, 2=page10.jpg
  const copied0: boolean = await provider.preparePageFileForSwiper(0, '/tmp/swiper_p0.png');
  const copied2: boolean = await provider.preparePageFileForSwiper(2, '/tmp/swiper_p2.jpg');
  ok('Swiper 准备第 0 页成功', copied0);
  ok('Swiper 准备第 2 页成功', copied2);
  const st2 = fs.statSync('/tmp/swiper_p2.jpg');
  eq('Swiper 第 2 页字节长度对应 page10.jpg', st2.size, 4);

  provider.stop();
  let dirExistsAfterStop: boolean = true;
  try {
    dirExistsAfterStop = fs.accessSync(createdExtractDir);
  } catch (_e) {
    dirExistsAfterStop = false;
  }
  eq('stop() 后清理 fallback 临时目录', dirExistsAfterStop, false);
  ArchiveGalleryProvider.setZipFallbackExtractor(null);
}

// ================================================================ 11) 外部 file://docs/ URI 优先按原始 URI 打开

async function caseExternalDocsUriOpen(): Promise<void> {
  const fsExt: FsTestExt = fs as unknown as FsTestExt;
  const docsUri: string = 'file://docs/storage/Users/currentUser/Download/comic.zip';
  fsExt.__seedFile(docsUri, new Uint8Array([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]));
  const openedBefore: number = fsExt.__opened.length;
  const opened: fs.File = Contracts.openReadFile(docsUri);
  ok('Contracts.openReadFile 成功打开外部 file://docs/ URI', opened.fd > 0);
  eq('优先直接以原始 URI 调用 fs.openSync', fsExt.__opened[openedBefore], docsUri);
  fs.closeSync(opened);
}

async function runCases(): Promise<void> {
  await caseOpenFailure();
  await caseInvalidArchive();
  await caseSortedEntries();
  await caseOutOfRange();
  await caseEmptyEntry();
  await caseEntryMapping();
  await caseStop();
  await caseArchiveEntries();
  await caseRarUnsupported();
  await caseZipZlibFallbackAndSwiper();
  await caseExternalDocsUriOpen();
}

runCases().then(() => {
  report();
}).catch((e: Error) => {
  fails.push(`用例抛异常: ${e.message}`);
  report();
});

function report(): void {
  if (fails.length > 0) {
    console.log(`\n${fails.length} 个断言失败：`);
    for (const f of fails) {
      console.log(`  ✗ ${f}`);
    }
    console.log(`\n通过 ${pass}，失败 ${fails.length}`);
    process.exit(1);
  }
  console.log(`全部通过：${pass} 个断言`);
}
