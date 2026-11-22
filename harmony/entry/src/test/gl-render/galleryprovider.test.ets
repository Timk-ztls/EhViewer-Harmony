/*
 * GalleryProvider 单测（C-10：harmony/entry/src/test/<module>/）
 *
 * 覆盖基类的四件事：请求去重、跨线程通知路由、LRU 淘汰与引用计数、生命周期约束。
 * 子类行为（onRequest/onForceRequest/onCancelRequest）用最小实现打桩，
 * 因为 storage-db 的四个 provider 会各自实现。
 *
 * 这里不 mock ImageWrapper 的语义，而是造一个 FakeImage 实现 Image 被用到的方法，
 * 断言的是"引用计数与淘汰时机"，不是像素。
 */

import { GalleryProvider, GalleryListener } from '../../main/ets/hippo/lib/glgallery/GalleryProvider';
import { ImageWrapper } from '../../main/ets/hippo/lib/glview/image/ImageWrapper';
import { Image } from '../../main/ets/hippo/lib/image/Image';
import { GLRoot, GLRootOnGLIdleListener } from '../../main/ets/hippo/lib/glview/view/GLRoot';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}

/** 只实现 GalleryProvider 用到的那部分 Image 接口。 */
class FakeImage {
  width: number;
  height: number;
  animated: boolean;
  recycled: boolean = false;
  recycleCount: number = 0;

  constructor(width: number, height: number, animated: boolean = false) {
    this.width = width;
    this.height = height;
    this.animated = animated;
  }

  getWidth(): number { return this.width; }
  getHeight(): number { return this.height; }
  getAnimated(): boolean { return this.animated; }
  isRecycled(): boolean { return this.recycled; }
  recycle(): void { this.recycled = true; this.recycleCount++; }
  obtain(): boolean { return !this.recycled; }
  release(): void { }
  texImage(_init: boolean, _x: number, _y: number, _w: number, _h: number): void { }
  start(): void { }
  getDelay(): number { return 0; }
  isOpaque(): boolean { return true; }
  getPixelMap(): Object { return {}; }
}

function asImage(f: FakeImage): Image {
  return f as unknown as Image;
}

/** 记录 idle 监听器，手动触发（模拟 GL 线程）。 */
class FakeGLRoot {
  listeners: GLRootOnGLIdleListener[] = [];
  addOnGLIdleListener(listener: GLRootOnGLIdleListener): void { this.listeners.push(listener); }
  requestRender(): void { }
  requestRenderForced(): void { }
  requestLayoutContentPane(): void { }
  lockRenderThread(): void { }
  unlockRenderThread(): void { }
  freeze(): void { }
  unfreeze(): void { }
  getWidth(): number { return 100; }
  getHeight(): number { return 100; }

  /** 模拟一次 GL idle：把当前挂着的监听器全部跑一遍。 */
  idle(): number {
    const pending = this.listeners;
    this.listeners = [];
    for (const l of pending) { l.onGLIdle({} as GLCanvas, false); }
    return pending.length;
  }
}

class FakeListener implements GalleryListener {
  events: string[] = [];
  lastImage: ImageWrapper | null = null;
  onDataChanged(): void { this.events.push('dataChanged'); }
  onDataChangedAt(index: number): void { this.events.push(`dataChanged:${index}`); }
  onPageWait(index: number): void { this.events.push(`wait:${index}`); }
  onPagePercent(index: number, percent: number): void { this.events.push(`percent:${index}:${percent}`); }
  onPageSucceed(index: number, image: ImageWrapper): void { this.events.push(`succeed:${index}`); this.lastImage = image; }
  onPageFailed(index: number, error: string): void { this.events.push(`failed:${index}:${error}`); }
}

/** 被测子类：记录回调，size 可控。 */
class FakeProvider extends GalleryProvider {
  requested: number[] = [];
  forced: number[] = [];
  cancelled: number[] = [];
  pageCount: number = 3;
  error: string = '';

  size(): number { return this.pageCount; }
  getError(): string { return this.error; }
  protected onRequest(index: number): void { this.requested.push(index); }
  protected onForceRequest(index: number): void { this.forced.push(index); }
  protected onCancelRequest(index: number): void { this.cancelled.push(index); }
}

// ---------- 1) 生命周期 ----------
{
  const p = new FakeProvider();
  p.start();
  let threw = false;
  try { p.start(); } catch { threw = true; }
  ok('start twice throws', threw);
}

// ---------- 2) 未命中缓存 -> 交给子类 onRequest ----------
{
  const p = new FakeProvider();
  const root = new FakeGLRoot();
  p.setGLRoot(root as unknown as GLRoot);
  p.request(2);
  eq('cache miss routes to onRequest', p.requested, [2]);
  eq('no notify without listener', root.idle(), 0);
}

// ---------- 3) notifyPageSucceed：包 wrapper -> 入缓存 -> GL idle 交 listener ----------
{
  const p = new FakeProvider();
  const root = new FakeGLRoot();
  const listener = new FakeListener();
  p.setGLRoot(root as unknown as GLRoot);
  p.setListener(listener);

  const img = new FakeImage(100, 50);
  p.notifyPageSucceed(5, asImage(img));
  eq('one task queued', root.listeners.length, 1);
  root.idle();
  eq('listener got succeed', listener.events, ['succeed:5']);
  ok('wrapper carries size', listener.lastImage !== null
    && listener.lastImage!.getWidth() === 100 && listener.lastImage!.getHeight() === 50);

  // 再请求同页：应命中缓存，不再走 onRequest
  p.request(5);
  eq('cache hit skips onRequest', p.requested, []);
  root.idle();
  eq('cache hit notifies again', listener.events, ['succeed:5', 'succeed:5']);
}

// ---------- 4) 动画图不入缓存 ----------
{
  const p = new FakeProvider();
  const root = new FakeGLRoot();
  const listener = new FakeListener();
  p.setGLRoot(root as unknown as GLRoot);
  p.setListener(listener);

  p.notifyPageSucceed(0, asImage(new FakeImage(10, 10, true)));
  root.idle();
  eq('animated notified', listener.events, ['succeed:0']);
  p.request(0);
  eq('animated not cached -> onRequest', p.requested, [0]);
}

// ---------- 5) 失败/等待/百分比 与 dataChanged 路由 ----------
{
  const p = new FakeProvider();
  const root = new FakeGLRoot();
  const listener = new FakeListener();
  p.setGLRoot(root as unknown as GLRoot);
  p.setListener(listener);

  p.notifyDataChanged();
  p.notifyDataChangedAt(7);
  p.notifyPageWait(1);
  p.notifyPagePercent(1, 0.25);
  p.notifyPageFailed(2, 'boom');
  eq('five tasks queued', root.listeners.length, 5);
  root.idle();
  eq('event order', listener.events,
    ['dataChanged', 'dataChanged:7', 'wait:1', 'percent:1:0.25', 'failed:2:boom']);
}

// ---------- 6) 没有 GLRoot / listener 时通知被丢弃（上游行为） ----------
{
  const p = new FakeProvider();
  p.setListener(new FakeListener());          // 有 listener 但没有 glRoot
  p.notifyPageSucceed(0, asImage(new FakeImage(1, 1)));
  const root = new FakeGLRoot();
  p.setGLRoot(root as unknown as GLRoot);
  p.setListener(null);                        // 有 glRoot 但没有 listener
  p.notifyPageSucceed(1, asImage(new FakeImage(1, 1)));
  eq('dropped without glRoot/listener', root.listeners.length, 0);
}

// ---------- 7) 通知任务池复用：连续 12 次通知不炸、每次只消费一次 ----------
{
  const p = new FakeProvider();
  const root = new FakeGLRoot();
  const listener = new FakeListener();
  p.setGLRoot(root as unknown as GLRoot);
  p.setListener(listener);
  for (let i = 0; i < 12; i++) {
    p.notifyPageWait(i);
    root.idle();                              // 立即消费，池(5)够用
  }
  eq('pool reuse 12 events', listener.events.length, 12);
  eq('pool reuse last', listener.events[11], 'wait:11');
}

// ---------- 8) LRU：单张超预算时整表淘汰并 release ----------
{
  const p = new FakeProvider();
  const listener = new FakeListener();
  const root = new FakeGLRoot();
  p.setGLRoot(root as unknown as GLRoot);
  p.setListener(listener);

  // 容量上限 = clamp(总内存/16, 32MB, 128MB)；run.ps1 的 hidebug 桩报 8GB 总内存
  // => 上限 = 128MB。6000*6000*4 = 144MB > 128MB，put 后立刻被 trim 淘汰。
  const big = new FakeImage(6000, 6000);
  p.notifyPageSucceed(0, asImage(big));
  root.idle();
  ok('big image notified before eviction', listener.events.length === 1);
  p.request(0);
  eq('big image evicted (cache miss again)', p.requested, [0]);
}

// ---------- 9) forceRequest 绕过缓存 ----------
{
  const p = new FakeProvider();
  const root = new FakeGLRoot();
  p.setGLRoot(root as unknown as GLRoot);
  p.notifyPageSucceed(3, asImage(new FakeImage(10, 10)));
  root.idle();
  p.forceRequest(3);
  eq('forceRequest always goes to subclass', p.forced, [3]);
  eq('forceRequest does not touch onRequest', p.requested, []);
}

// ---------- 10) cancelRequest 透传 ----------
{
  const p = new FakeProvider();
  p.cancelRequest(9);
  eq('cancelRequest passthrough', p.cancelled, [9]);
}

// ---------- 11) ImageWrapper 引用计数与裁剪 ----------
{
  const img = new FakeImage(100, 80);
  const w = new ImageWrapper(asImage(img));
  eq('wrapper size = full image', [w.getWidth(), w.getHeight()], [100, 80]);
  w.setCutRect(-10, -10, 50, 40);             // clamp 到 [0,0,50,40]
  eq('cut clamped', [w.getWidth(), w.getHeight()], [50, 40]);
  w.setCutRect(10, 10, 10, 20);               // 空 => 回退整图
  eq('empty cut falls back to full', [w.getWidth(), w.getHeight()], [100, 80]);
  ok('obtain ok', w.obtain());
  ok('obtain again ok', w.obtain());
  w.release();
  ok('not recycled at ref=1', !img.isRecycled());
  w.release();
  ok('recycled at ref=0', img.isRecycled());
  ok('obtain fails after recycle', !w.obtain());
}

// ---------- 12) 真实 Image.release() 引用计数归零触发回收 ----------
{
  let pmReleased = 0;
  const mockPm = {
    getImageInfoSync: () => ({ size: { width: 64, height: 64 } }),
    release: () => { pmReleased++; }
  };
  const realImg = Image.decodePixelMap(mockPm as unknown as never, false);
  ok('decodePixelMap 返回非空 Image', realImg !== null);
  if (realImg !== null) {
    ok('初始未回收', !realImg.isRecycled());
    ok('第 1 次 obtain 成功', realImg.obtain());
    ok('第 2 次 obtain 成功', realImg.obtain());
    realImg.release();
    eq('ref=1 时不释放 PixelMap', pmReleased, 0);
    ok('ref=1 时 isRecycled 仍为 false', !realImg.isRecycled());
    realImg.release();
    eq('ref=0 时释放 PixelMap', pmReleased, 1);
    ok('ref=0 时 isRecycled 为 true', realImg.isRecycled());
    ok('回收后 obtain 返回 false', !realImg.obtain());
  }
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
