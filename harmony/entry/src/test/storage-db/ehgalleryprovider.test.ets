/*
 * EhGalleryProvider 单测（阅读器 ↔ 下载器的桥）
 *
 * 它是唯一把 `SpiderQueen` 的回调翻译成 `GalleryProvider` 通知的地方，所以错的代价是
 * 「图明明下载好了但界面永远转圈」或「进度条乱跳」。这里钉住的是**三态分派**与**8 个回调的翻译**：
 *   1) `request()` 三态：number → 进度、string → 失败、null → 等待（上游 Float/String/null）
 *   2) `onPageDownload` 只在 contentLength > 0 时算百分比（未知长度不显示假 0%）
 *   3) 没有 queen 时：`size()` = STATE_ERROR、`getError()` = 'Error'（上游字面量，不发明文案）
 *   4) `getImageFilename` = `gid-token-%08d(index+1)`
 *   5) stop() 是 **postDelayed 3000ms** 释放（转屏重入保护）
 */

import { EhGalleryProvider, SpiderQueenLike } from '../../main/ets/hippo/ehviewer/gallery/EhGalleryProvider';
import { GalleryProvider, GalleryListener } from '../../main/ets/hippo/lib/glgallery/GalleryProvider';
import { SpiderQueen, OnSpiderListener, PageRequestResult } from '../../main/ets/hippo/ehviewer/spider/SpiderQueen';
import { MODE_READ, SpiderDen } from '../../main/ets/hippo/ehviewer/spider/SpiderDen';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { UniFile } from '../../main/ets/hippo/unifile/UniFile';
import { Image } from '../../main/ets/hippo/lib/image/Image';
import { ImageWrapper } from '../../main/ets/hippo/lib/glview/image/ImageWrapper';
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
  dataChangedAt: number = 0;
  waits: number = 0;
  percents: string[] = [];
  succeeds: number = 0;
  failed: string[] = [];

  onDataChanged(): void {
    this.dataChanged++;
  }

  onDataChangedAt(index: number): void {
    this.dataChangedAt++;
  }

  onPageWait(index: number): void {
    this.waits++;
  }

  onPagePercent(index: number, percent: number): void {
    this.percents.push(`${index}=${percent}`);
  }

  onPageSucceed(index: number, image: ImageWrapper): void {
    this.succeeds++;
  }

  onPageFailed(index: number, error: string): void {
    this.failed.push(`${index}:${error}`);
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

/** 假 queen：记录调用、按脚本返回三态结果。 */
class FakeQueen implements SpiderQueenLike {
  requestResult: PageRequestResult = null;
  forceResult: PageRequestResult = null;
  saveFileResult: boolean = true;
  sizeValue: number = 5;
  errorValue: string = '';
  startPageValue: number = 3;
  putStartPageCalls: number[] = [];
  cancelCalls: number[] = [];
  listeners: OnSpiderListener[] = [];
  released: number = 0;

  addOnSpiderListener(listener: OnSpiderListener): void {
    this.listeners.push(listener);
  }

  removeOnSpiderListener(listener: OnSpiderListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }

  getStartPage(): number {
    return this.startPageValue;
  }

  putStartPage(page: number): void {
    this.putStartPageCalls.push(page);
  }

  size(): number {
    return this.sizeValue;
  }

  getError(): string {
    return this.errorValue;
  }

  request(index: number): PageRequestResult {
    return this.requestResult;
  }

  forceRequest(index: number): PageRequestResult {
    return this.forceResult;
  }

  cancelRequest(index: number): void {
    this.cancelCalls.push(index);
  }

  saveToFile(index: number, file: UniFile): boolean {
    return this.saveFileResult;
  }

  saveToDir(index: number, dir: UniFile, filename: string): UniFile | null {
    return dir;
  }
}

function makeInfo(): UniFile {
  const f: UniFile | null = UniFile.fromFile('/tmp/dest.bin');
  if (f === null) {
    throw new Error('无法构造 UniFile');
  }
  return f;
}

function makeGallery(): GalleryInfo {
  const g: GalleryInfo = new GalleryInfo();
  g.gid = 123456;
  g.token = 'abcd1234';
  return g;
}

async function tick(): Promise<void> {
  await Promise.resolve();
  await new Promise<void>((resolve) => setTimeout(resolve, 1));
}

// ================================================================ 1) 未注入工厂 → 显式抛错

{
  EhGalleryProvider.setSpiderQueenFactory(null);
  const provider: EhGalleryProvider = new EhGalleryProvider(makeGallery());
  let threw: boolean = false;
  let msg: string = '';
  try {
    provider.start();
  } catch (e) {
    threw = true;
    msg = (e as Error).message !== undefined ? (e as Error).message : '';
  }
  ok('未注入 SpiderQueenFactory → start() 抛错', threw);
  ok('错误信息点名 SpiderQueenFactory', msg.indexOf('SpiderQueenFactory') >= 0);

  // 没有 queen 时的兜底值（上游字面量）
  eq('无 queen → size() = STATE_ERROR', provider.size(), GalleryProvider.STATE_ERROR);
  eq('无 queen → getError() = "Error"（上游 TODO 字面量）', provider.getError(), 'Error');
  eq('无 queen → saveToFile=false', provider.saveToFile(0, makeInfo()), false);
  eq('无 queen → saveToDir=null', provider.saveToDir(0, makeInfo(), 'x'), null);
  eq('无 queen → getStartPage 用基类默认 0', provider.getStartPage(), 0);
  ok('无 queen → hasSpiderQueen=false', !provider.hasSpiderQueen());
}

// ================================================================ 2) 文件名格式（gid-token-%08d(index+1)）

{
  const provider: EhGalleryProvider = new EhGalleryProvider(makeGallery());
  eq('第 0 页 → 00000001', provider.getImageFilename(0), '123456-abcd1234-00000001');
  eq('第 9 页 → 00000010', provider.getImageFilename(9), '123456-abcd1234-00000010');
  eq('第 99 页 → 00000100', provider.getImageFilename(99), '123456-abcd1234-00000100');
  eq('9 位不截断', provider.getImageFilename(99999999), '123456-abcd1234-100000000');
}

// ================================================================ 3) 委托与三态分派

async function caseDelegationAndDispatch(): Promise<void> {
  const queen: FakeQueen = new FakeQueen();
  EhGalleryProvider.setSpiderQueenFactory((info: GalleryInfo, mode: number): SpiderQueenLike => queen);
  EhGalleryProvider.setSpiderQueenReleaser((q: SpiderQueenLike): void => {
    (q as FakeQueen).released++;
  });

  const provider: EhGalleryProvider = new EhGalleryProvider(makeGallery());
  const rec: Recorder = new Recorder();
  provider.setListener(rec);
  const gl: FakeGLRoot = new FakeGLRoot();
  provider.setGLRoot(gl);
  provider.start();

  ok('start 后持有 queen', provider.hasSpiderQueen());
  eq('已注册监听器', queen.listeners.length, 1);
  ok('注册的监听器就是 provider 自己', queen.listeners[0] === (provider as OnSpiderListener));

  // 委托
  eq('size 委托', provider.size(), 5);
  eq('getStartPage 委托', provider.getStartPage(), 3);
  provider.putStartPage(7);
  eq('putStartPage 委托', queen.putStartPageCalls, [7]);
  queen.errorValue = 'boom';
  eq('getError 委托', provider.getError(), 'boom');
  eq('saveToFile 委托', provider.saveToFile(0, makeInfo()), true);

  // 三态分派：null → wait
  queen.requestResult = null;
  provider.request(2);
  await tick();
  gl.drain();
  eq('request 返回 null → 一次 wait', rec.waits, 1);

  // number → percent
  queen.requestResult = 0.25;
  provider.request(3);
  await tick();
  gl.drain();
  ok('request 返回 number → percent 带正确 index 与值',
    rec.percents.length === 1 && rec.percents[0] === '3=0.25');

  // string → failed
  queen.requestResult = 'network broken';
  provider.request(4);
  await tick();
  gl.drain();
  ok('request 返回 string → failed 带原文',
    rec.failed.length === 1 && rec.failed[0] === '4:network broken');

  // forceRequest 同三态
  queen.forceResult = 0.5;
  provider.forceRequest(5);
  await tick();
  gl.drain();
  ok('forceRequest 返回 number → percent',
    rec.percents.length === 2 && rec.percents[1] === '5=0.5');

  // cancel 透传
  provider.cancelRequest(6);
  eq('cancelRequest 透传', queen.cancelCalls, [6]);

  // 8 个回调的翻译
  provider.onGetPages(10);
  await tick();
  gl.drain();
  eq('onGetPages → onDataChanged', rec.dataChanged, 1);

  provider.onPageSuccess(1, 1, 1, 10);
  await tick();
  gl.drain();
  eq('onPageSuccess → onDataChangedAt', rec.dataChangedAt, 1);

  // contentLength <= 0 不算百分比（未知长度不显示假 0%）
  provider.onPageDownload(1, -1, 100, 10);
  await tick();
  gl.drain();
  eq('contentLength = -1 时不算百分比', rec.percents.length, 2);

  provider.onPageDownload(1, 200, 100, 10);
  await tick();
  gl.drain();
  ok('contentLength > 0 时算百分比（0.5）',
    rec.percents.length === 3 && rec.percents[2] === '1=0.5');

  provider.onPageFailure(2, 'fatal', 0, 0, 10);
  await tick();
  gl.drain();
  ok('onPageFailure → onPageFailed', rec.failed.length === 2 && rec.failed[1] === '2:fatal');

  provider.onGetImageFailure(3, 'img broken');
  await tick();
  gl.drain();
  ok('onGetImageFailure → onPageFailed', rec.failed.length === 3 && rec.failed[2] === '3:img broken');

  provider.onFinish(10, 10, 10);
  provider.onGet509(1);
  await tick();
  gl.drain();
  ok('onFinish / onGet509 是上游空实现，不产生通知', rec.dataChanged === 1 && rec.failed.length === 3);

  // stop：移除监听 + 延迟释放（不是立即）
  provider.stop();
  eq('stop 后已从 queen 移除监听器', queen.listeners.length, 0);
  ok('stop 后 provider 不再持有 queen', !provider.hasSpiderQueen());
  await new Promise<void>((resolve) => setTimeout(resolve, 3200));
  await tick();
  eq('3 秒后执行释放', queen.released, 1);

  EhGalleryProvider.setSpiderQueenFactory(null);
  EhGalleryProvider.setSpiderQueenReleaser(null);

  // P0 #2: 真实 SpiderQueen 直接接入 EhGalleryProvider（implements SpiderQueenLike，无强转）
  SpiderQueen.resetForTest();
  SpiderDen.resetCache();
  EhGalleryProvider.setSpiderQueenFactory((info: GalleryInfo, mode: number): SpiderQueenLike =>
    SpiderQueen.obtainSpiderQueen(info, mode));
  EhGalleryProvider.setSpiderQueenReleaser((q: SpiderQueenLike): void => {
    SpiderQueen.releaseSpiderQueen(q as SpiderQueen, MODE_READ);
  });
  const realProvider: EhGalleryProvider = new EhGalleryProvider(makeGallery());
  realProvider.start();
  ok('P0 #2: 真实 SpiderQueen 接入 EhGalleryProvider.start() 成功', realProvider.hasSpiderQueen());
  eq('P0 #2: 已启动 SpiderQueen 的 getError() === ""', realProvider.getError(), '');
  eq('P0 #2: getStartPage() 默认返回 0', realProvider.getStartPage(), 0);
  realProvider.stop();
  await new Promise<void>((resolve) => setTimeout(resolve, 3200));
  eq('P0 #2: stop 3s 后真实 SpiderQueen 释放出 sQueenMap', SpiderQueen.activeQueenCount(), 0);
  EhGalleryProvider.setSpiderQueenFactory(null);
  EhGalleryProvider.setSpiderQueenReleaser(null);
  SpiderQueen.resetForTest();
}

async function runCases(): Promise<void> {
  await caseDelegationAndDispatch();
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
