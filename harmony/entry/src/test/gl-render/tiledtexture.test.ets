/*
 * TiledTexture 单测（纯几何 + 上床调度）
 *
 * 为什么值得单测：这个类错了**不报错，只是画歪**：
 *   1) 瓦片网格：CONTENT_SIZE=254 而不是 256（TILE_SIZE 才是 256 = 254 + 2×1 边框）
 *   2) mapRect：把纹理坐标线性映射到画布坐标，比例算错就整块偏移
 *   3) 区域绘制时的 `src.intersect(source)`：不相交要**跳过**，否则边缘瓦片会被拉伸
 *   4) Uploader 的时间片：每帧最多 4ms，且「先判时间再上床」
 */

import { TiledTexture, TiledTextureUploader, Tile, GLIdleListener } from '../../main/ets/hippo/lib/glview/glrenderer/TiledTexture';
import { RectF } from '../../main/ets/hippo/lib/glview/util/RectF';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { BasicTexture } from '../../main/ets/hippo/lib/glview/glrenderer/BasicTexture';
import { image } from '@kit.ImageKit';

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
function near(name: string, got: number, want: number, eps: number = 1e-4): void {
  if (Math.abs(got - want) <= eps) { pass++; } else { fails.push(`${name}: got ${got} want ${want}`); }
}

/** 记录 drawTexture / drawMixed 调用的假画布（只实现用到的成员）。 */
class RecordingCanvas {
  textures: string[] = [];
  mixes: string[] = [];

  drawTexture(t: BasicTexture, a: number | RectF | number[], b?: number | RectF,
    c?: number, d?: number): void {
    if (a instanceof RectF) {
      this.textures.push(`${r(a)}->${r(b as RectF)}`);
    } else {
      this.textures.push(`num:${a},${b},${c},${d}`);
    }
  }

  drawMixed(t: BasicTexture, color: number, ratio: number, a: number | RectF,
    b: number | RectF): void {
    this.mixes.push(`${color},${ratio},${r(a as RectF)}->${r(b as RectF)}`);
  }
}

function r(x: RectF): string {
  return `${x.left},${x.top},${x.right},${x.bottom}`;
}

function fakeBitmap(w: number, h: number): image.PixelMap {
  // 测试替身：只提供 width/height（TiledTexture 只用这两个字段）
  return { width: w, height: h } as Object as image.PixelMap;
}

// ---------------------------------------------------------------- 1. 瓦片网格
{
  // 100x100 → 1 块
  const t1 = new TiledTexture(fakeBitmap(100, 100), false);
  eq('100x100 → 1 块瓦片', t1.tiles().length, 1);
  eq('单块 content 尺寸 = 原图', [t1.tiles()[0].contentWidth, t1.tiles()[0].contentHeight], [100, 100]);

  // 300x100 → 2 块（254 + 46）
  const t2 = new TiledTexture(fakeBitmap(300, 100), false);
  eq('300x100 → 2 块瓦片', t2.tiles().length, 2);
  eq('第一块 content 宽 = CONTENT_SIZE(254)', t2.tiles()[0].contentWidth, 254);
  eq('第二块 content 宽 = 余量 46', t2.tiles()[1].contentWidth, 46);
  eq('第二块 offsetX = 254', t2.tiles()[1].offsetX, 254);

  // 254x254 正好一块；255x255 → 4 块
  eq('254x254 → 1 块', new TiledTexture(fakeBitmap(254, 254), false).tiles().length, 1);
  eq('255x255 → 4 块', new TiledTexture(fakeBitmap(255, 255), false).tiles().length, 4);

  // 纹理尺寸 = content + 2*BORDER
  const t3 = new TiledTexture(fakeBitmap(300, 100), false);
  eq('瓦片纹理宽 = content + 2 边框', t3.tiles()[0].getWidth(), 256);
  eq('瓦片纹理高 = content + 2 边框', t3.tiles()[1].getHeight(), 102);
  eq('getWidth 是原图宽', t3.getWidth(), 300);
  eq('getHeight 是原图高', t3.getHeight(), 100);
  eq('isOpaque 恒 false（瓦片有透明边框）', t3.isOpaque(), false);
  eq('CONTENT_SIZE = 254', TiledTexture.CONTENT_SIZE, 254);
  eq('BORDER_SIZE = 1', TiledTexture.BORDER_SIZE, 1);
  eq('TILE_SIZE = 256', TiledTexture.TILE_SIZE, 256);
}

// ---------------------------------------------------------------- 2. mapRect 线性映射
{
  const out = new RectF();
  // 纹理 (0,0)-(100,100) 映射到画布 (10,20)-(110,220)：scaleX=1, scaleY=2
  TiledTexture.mapRect(out, new RectF(0, 0, 100, 100), 0, 0, 10, 20, 1, 2);
  eq('mapRect 全图', r(out), '10,20,110,220');

  // 带 x0/y0：源坐标系平移 (50,50)，映射到同一目标
  TiledTexture.mapRect(out, new RectF(50, 50, 150, 150), 50, 50, 0, 0, 1, 1);
  eq('mapRect 带原点偏移', r(out), '0,0,100,100');

  // 缩放 0.5
  TiledTexture.mapRect(out, new RectF(0, 0, 200, 200), 0, 0, 0, 0, 0.5, 0.5);
  eq('mapRect 缩小一半', r(out), '0,0,100,100');
}

// ---------------------------------------------------------------- 3. 整图绘制：每块瓦片一次 drawTexture
{
  const tex = new TiledTexture(fakeBitmap(300, 100), false);
  const canvas = new RecordingCanvas();
  tex.draw(canvas as Object as GLCanvas, 0, 0, 300, 100);
  eq('两块瓦片 → 两次 drawTexture', canvas.textures.length, 2);
  // 第 1 块：src 是 (1,1,255,101)（BORDER 偏移后），dest 是 (0,0,254,100)
  eq('第 1 块 src（+1 边框）', canvas.textures[0].split('->')[0], '1,1,255,101');
  eq('第 1 块 dest', canvas.textures[0].split('->')[1], '0,0,254,100');
  // 第 2 块：offsetX=254 → src (1,1,47,101)，dest (254,0,300,100)
  eq('第 2 块 src', canvas.textures[1].split('->')[0], '1,1,47,101');
  eq('第 2 块 dest', canvas.textures[1].split('->')[1], '254,0,300,100');
}

// ---------------------------------------------------------------- 4. 区域绘制：不相交的瓦片要跳过
{
  const tex = new TiledTexture(fakeBitmap(300, 100), false);
  const canvas = new RecordingCanvas();
  // 只画右半部分（source x ∈ [254,300)）→ 只有第 2 块瓦片相交
  tex.drawRect(canvas as Object as GLCanvas, new RectF(254, 0, 300, 100),
    new RectF(0, 0, 46, 100));
  eq('只画右半 → 只有 1 次 drawTexture', canvas.textures.length, 1);

  // 全图区域 → 2 次
  const canvas2 = new RecordingCanvas();
  tex.drawRect(canvas2 as Object as GLCanvas, new RectF(0, 0, 300, 100),
    new RectF(0, 0, 300, 100));
  eq('全图区域 → 2 次 drawTexture', canvas2.textures.length, 2);
}

// ---------------------------------------------------------------- 5. drawMixed
{
  const tex = new TiledTexture(fakeBitmap(300, 100), false);
  const canvas = new RecordingCanvas();
  tex.drawMixedScaled(canvas as Object as GLCanvas, 0xFF0000, 0.5, 0, 0, 300, 100);
  eq('drawMixedScaled → 2 次 drawMixed', canvas.mixes.length, 2);
  ok('drawMixed 带 color/ratio', canvas.mixes[0].indexOf('16711680,0.5,') === 0);

  const canvas2 = new RecordingCanvas();
  tex.drawMixedRegion(canvas2 as Object as GLCanvas, 0xFF0000, 0.25,
    new RectF(0, 0, 100, 100), new RectF(0, 0, 100, 100));
  eq('drawMixedRegion 只画相交的 1 块', canvas2.mixes.length, 1);
}

// ---------------------------------------------------------------- 6. Uploader 时间片
{
  // 假时钟：每次 uptimeMillis() 前进 1ms
  let t = 0;
  const clock = { uptimeMillis: (): number => { t += 1; return t; } };
  const renders: number[] = [];
  let listener: GLIdleListener | null = null;
  const requireListener = (): GLIdleListener => {
    if (listener === null) {
      throw new Error('listener 未注册');
    }
    return listener as GLIdleListener;
  };
  const host = {
    addOnGLIdleListener: (l: GLIdleListener): void => { listener = l; },
    requestRender: (): void => { renders.push(1); }
  };

  const uploader = new TiledTextureUploader(host, clock);
  const tex = new TiledTexture(fakeBitmap(255, 255), false); // 4 块，1ms/次 → 一轮能上完
  uploader.addTexture(tex);
  eq('addTexture 后队列长度 1', uploader.queueLength(), 1);
  eq('已挂上 idle 监听', uploader.isQueued(), true);
  ok('listener 已被注册', listener !== null);

  // 假时钟每次调用前进 1ms：4 块瓦片在 4ms 时间片内**一轮就能上完**
  const keep = requireListener().onGLIdle(new RecordingCanvas() as Object as GLCanvas, false);
  eq('1ms/次 时钟下 4 块一轮上完 → 队列空', keep, false);
  ok('一轮后 isReady', tex.isReady());
  ok('上完触发过 requestRender', renders.length > 0);

  // 换 3ms/次 的慢时钟：一轮只能上 1~2 块，必须多轮
  let slow = 0;
  const slowClock = { uptimeMillis: (): number => { slow += 3; return slow; } };
  let slowListener: GLIdleListener | null = null;
  const slowHost = {
    addOnGLIdleListener: (l: GLIdleListener): void => { slowListener = l; },
    requestRender: (): void => { }
  };
  const slowUploader = new TiledTextureUploader(slowHost, slowClock);
  const slowTex = new TiledTexture(fakeBitmap(255, 255), false); // 4 块
  slowUploader.addTexture(slowTex);
  if (slowListener === null) { throw new Error('slowListener 未注册'); }
  const keepSlow = (slowListener as GLIdleListener).onGLIdle(
    new RecordingCanvas() as Object as GLCanvas, false);
  eq('3ms/次 时钟下一轮上不完（还有余队）', keepSlow, true);
  ok('慢时钟一轮后未 ready', !slowTex.isReady());

  let guard = 0;
  while (!slowTex.isReady() && guard < 50) {
    (slowListener as GLIdleListener).onGLIdle(new RecordingCanvas() as Object as GLCanvas, false);
    guard++;
  }
  ok('多轮后最终 ready', slowTex.isReady());

  // 已 ready 的纹理再 add 会被忽略
  const before: number = uploader.queueLength();
  uploader.addTexture(tex);
  eq('ready 的纹理不入队', uploader.queueLength(), before);
}

// ---------------------------------------------------------------- 7. recycle 清位图
{
  const tex = new TiledTexture(fakeBitmap(100, 100), false);
  ok('构造后瓦片持有位图', tex.tiles()[0].bitmap !== null);
  tex.recycle();
  eq('recycle 后位图引用被清', tex.tiles()[0].bitmap, null);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('tiledtexture 断言失败：' + fails.length);
}
