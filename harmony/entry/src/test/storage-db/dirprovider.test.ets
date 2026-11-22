/*
 * DirGalleryProvider 扫描/排序/过滤 单测
 *
 * 覆盖上游 `DirGalleryProvider.run()` 的前半段（列举 → 过滤 → 自然序排序 → 置 size）与
 * `decodeAt` 的取文件逻辑。这段错了的表现：
 *   - 过滤器把 `.PNG` 漏掉 → 用户看到"缺页"
 *   - 自然序写成字典序 → `b1, b10, b2` → 阅读顺序乱（第 2 页显示第 10 张）
 *   - 目录不可读时静默 size=0 → 空画廊，用户以为下载没成功
 * 三种都不报错，只在真机看图时暴露。
 *
 * 依赖两个假物：
 *   - 假 fs：路径含 `gallery` 时 `listFileSync` 返回固定 5 项（4 张图 + 1 个非图片），
 *     否则抛错（模拟"不是目录"）；`openSync` 记录被打开的路径（用于断言取的是哪一条）
 *   - 假 GLRoot：基类没有 `setGLRoot` 时会静默丢弃通知（gl-render 的既有结论）
 */

import fs from '@ohos.file.fs';
import { DirGalleryProvider } from '../../main/ets/hippo/ehviewer/gallery/DirGalleryProvider';
import { GalleryProvider, GalleryListener } from '../../main/ets/hippo/lib/glgallery/GalleryProvider';
import { ImageWrapper } from '../../main/ets/hippo/lib/glview/image/ImageWrapper';
import { UniFile } from '../../main/ets/hippo/unifile/UniFile';
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

class Recorder implements GalleryListener {
  dataChanged: number = 0;
  succeeded: number = 0;
  failed: string[] = [];
  waited: number = 0;

  onDataChanged(): void {
    this.dataChanged++;
  }

  onDataChangedAt(index: number): void {
    this.dataChanged++;
  }

  onPageWait(index: number): void {
    this.waited++;
  }

  onPagePercent(index: number, percent: number): void {
  }

  onPageSucceed(index: number, image: ImageWrapper): void {
    this.succeeded++;
  }

  onPageFailed(index: number, error: string): void {
    this.failed.push(`${index}`);
  }
}

class FakeGLRoot implements GLRoot {
  private listeners: GLRootOnGLIdleListener[] = [];

  addOnGLIdleListener(listener: GLRootOnGLIdleListener): void {
    this.listeners.push(listener);
  }

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

  getWidth(): number {
    return 1080;
  }

  getHeight(): number {
    return 1920;
  }
}

/**
 * 假 fs 桩记录的被打开路径。
 * 注意：这是**测试专用**的自定义属性（桩是我自己写的模块），
 * 生产代码永远不会访问它 —— 因此这里用局部类型断言是合理的，不是"给被测代码打补丁"。
 */
interface FsStubWithLog {
  __opened?: string[];
}

function fsStub(): FsStubWithLog {
  return fs as FsStubWithLog;
}

function openedPaths(): string[] {
  const log: FsStubWithLog = fsStub();
  return log.__opened !== undefined ? log.__opened : [];
}

function resetOpened(): void {
  fsStub().__opened = [];
}

async function tick(times: number): Promise<void> {
  for (let i = 0; i < times; i++) {
    await Promise.resolve();
    await new Promise<void>((resolve) => setTimeout(resolve, 1));
  }
}

// ================================================================ 1) 目录不可读 → STATE_ERROR（不是静默 size=0）

async function caseNotADirectory(): Promise<void> {
  const dir: UniFile | null = UniFile.fromFile('/tmp/unlistable')  // 路径里不能含 gallery：假桩按子串判定
  // （第一版写成 '/tmp/not-a-gallery'，子串命中导致桩返回了目录列表，断言才会拿到 4）;
  if (dir === null) {
    fails.push('无法构造目录 UniFile');
    return;
  }
  const provider: DirGalleryProvider = new DirGalleryProvider(dir);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();
  eq('不可读目录 → size() = STATE_ERROR（不是 0）', provider.size(), GalleryProvider.STATE_ERROR);
  eq('不可读目录 → getError() 是字符串', typeof provider.getError(), 'string');
}

// ================================================================ 2) 过滤 + 自然序

async function caseFilterAndSort(): Promise<void> {
  resetOpened();
  const dir: UniFile | null = UniFile.fromFile('/tmp/gallery1');
  if (dir === null) {
    fails.push('无法构造目录 UniFile');
    return;
  }
  const provider: DirGalleryProvider = new DirGalleryProvider(dir);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();

  // 假 fs 返回：b10.jpg / b2.jpg / b1.jpg / note.txt / c3.PNG
  // → 过滤掉 note.txt，剩 4 项；`.PNG` 大写必须保留（旧 Android 目录常见）
  eq('过滤掉非图片，剩 4 项', provider.size(), 4);
  eq('合法目录 getError() 为空串', provider.getError(), '');

  // 第 0 页必须是自然序第一（b1.jpg），不是列举顺序第一（b10.jpg）
  resetOpened();
  provider.request(0);
  await tick(4);
  gl.drain();
  const opened0: string[] = openedPaths();
  ok('第 0 页打开了文件', opened0.length >= 1);
  ok('第 0 页 → 自然序第一 b1.jpg（不是 b10.jpg）',
    opened0.length >= 1 && opened0[0].endsWith('b1.jpg'));

  // 第 2 页 → 自然序第三 = b10.jpg（字典序会把它排到第二）
  resetOpened();
  provider.request(2);
  await tick(4);
  gl.drain();
  const opened2: string[] = openedPaths();
  ok('第 2 页 → 自然序第三 b10.jpg（字典序会错成 b2.jpg）',
    opened2.length >= 1 && opened2[0].endsWith('b10.jpg'));

  // 第 3 页 → 大写扩展名的 c3.PNG（过滤大小写不敏感）
  resetOpened();
  provider.request(3);
  await tick(4);
  gl.drain();
  const opened3: string[] = openedPaths();
  ok('第 3 页 → c3.PNG（大写扩展名未被过滤）',
    opened3.length >= 1 && opened3[0].endsWith('c3.PNG'));
}

// ================================================================ 3) 越界请求 → 失败通知（带正确的 index）

async function caseOutOfRange(): Promise<void> {
  const dir: UniFile | null = UniFile.fromFile('/tmp/gallery1');
  if (dir === null) {
    fails.push('无法构造目录 UniFile');
    return;
  }
  const provider: DirGalleryProvider = new DirGalleryProvider(dir);
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();
  await tick(3);
  gl.drain();

  provider.request(99);
  await tick(4);
  gl.drain();
  await tick(1);
  gl.drain();
  ok('越界请求 → 有失败通知', rec.failed.length >= 1);
  ok('越界请求 → index 是 99', rec.failed.length >= 1 && rec.failed[0] === '99');
}

// ================================================================ 4) 取消与 getImageFilename

async function caseCancelAndName(): Promise<void> {
  const dir: UniFile | null = UniFile.fromFile('/tmp/gallery1');
  if (dir === null) {
    fails.push('无法构造目录 UniFile');
    return;
  }
  const provider: DirGalleryProvider = new DirGalleryProvider(dir);
  provider.start();
  await tick(3);
  eq('getImageFilename 保持上游 TODO（index 本身）', provider.getImageFilename(7), '7');
  let threw: boolean = false;
  try {
    provider.cancelRequest(1);
    provider.stop();
    provider.request(0);
    await tick(2);
  } catch (e) {
    threw = true;
  }
  ok('取消/停止后不抛异常', !threw);
}

// ================================================================ 5) saveToFile / saveToDir（上游这两条有实现，与 Archive 的 TODO 不同）

async function caseSave(): Promise<void> {
  resetOpened();
  const dir: UniFile | null = UniFile.fromFile('/tmp/gallery1');
  if (dir === null) {
    fails.push('无法构造目录 UniFile');
    return;
  }
  const provider: DirGalleryProvider = new DirGalleryProvider(dir);
  provider.start();
  await tick(3);

  const destFile: UniFile | null = UniFile.fromFile('/tmp/out.bin');
  const destDir: UniFile | null = UniFile.fromFile('/tmp/outdir');
  if (destFile === null || destDir === null) {
    fails.push('无法构造目标 UniFile');
    return;
  }

  // saveToFile：整段拷贝 → 返回 true，且源/目标都被打开
  resetOpened();
  const saved: boolean = provider.saveToFile(0, destFile);
  ok('saveToFile 返回 true', saved);
  const openedA: string[] = openedPaths();
  ok('saveToFile 打开了源文件（自然序第一个 b1.jpg）', openedA.length >= 1 && openedA[0].endsWith('b1.jpg'));
  ok('saveToFile 打开了目标文件（/tmp/out.bin）', openedA.some((p: string) => p.endsWith('out.bin')));

  // saveToDir：**保留原扩展名**（上游 FileUtils.getExtensionFromFilename + "." + ext）
  resetOpened();
  const dst: UniFile | null = provider.saveToDir(1, destDir, 'mypage');
  ok('saveToDir 返回非 null', dst !== null);
  const openedB: string[] = openedPaths();
  const outPath: string = openedB.length > 0 ? openedB[openedB.length - 1] : '';
  ok('saveToDir 生成的文件名保留原扩展名（mypage.jpg）', outPath.endsWith('mypage.jpg') || outPath.endsWith('mypage.jpg'));
  ok('saveToDir 的源是自然序第二个 b2.jpg', openedB.some((p: string) => p.endsWith('b2.jpg')));

  // 越界：上游返回 false / null（不抛错）
  eq('越界 saveToFile → false', provider.saveToFile(99, destFile), false);
  eq('越界 saveToDir → null', provider.saveToDir(99, destDir, 'x'), null);
  eq('负数索引 saveToFile → false', provider.saveToFile(-1, destFile), false);
  eq('负数索引 saveToDir → null', provider.saveToDir(-1, destDir, 'x'), null);
}
async function runCases(): Promise<void> {
  await caseNotADirectory();
  await caseFilterAndSort();
  await caseOutOfRange();
  await caseCancelAndName();
  await caseSave();
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
