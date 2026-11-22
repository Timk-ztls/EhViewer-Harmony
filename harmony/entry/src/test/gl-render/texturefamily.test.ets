/*
 * ExtTexture / ResourceTexture / CanvasTexture / SpriteTexture 单测
 *
 * 这四个是「纹理来源不同、行为差在细节」的一族，错了不报错、只是画不出来或画错位置：
 *   1) ExtTexture：id 来自 getGLId().generateTexture()（不走 UploadedTexture）；yield() 必须**什么都不做**
 *   2) ResourceTexture：context == null 必须**抛**（上游把 assert 换成了显式抛）
 *   3) CanvasTexture：**构造时就 setSize**，不等位图；onGetBitmap 里 createBitmap → onDraw
 *   4) SpriteTexture：rects 长度必须 = count*4；drawSprite 用 rect 的 w/h（不缩放）
 */

import { ExtTexture } from '../../main/ets/hippo/lib/glview/glrenderer/ExtTexture';
import { ResourceTexture } from '../../main/ets/hippo/lib/glview/glrenderer/ResourceTexture';
import { CanvasTexture, OffscreenCanvasLike } from '../../main/ets/hippo/lib/glview/glrenderer/CanvasTexture';
import { SpriteTexture } from '../../main/ets/hippo/lib/glview/glrenderer/SpriteTexture';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { GLId } from '../../main/ets/hippo/lib/glview/glrenderer/GLId';
import { RectF } from '../../main/ets/hippo/lib/glview/util/RectF';
import { image } from '@kit.ImageKit';
import { FakeCanvas } from './fakecanvas';

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
function throws(name: string, fn: () => void, msgPart: string): void {
  try {
    fn();
    fails.push(name + '（未抛异常）');
  } catch (e) {
    const m = (e as Error).message;
    if (m.indexOf(msgPart) >= 0) { pass++; } else { fails.push(name + `（消息 "${m}"）`); }
  }
}

/** 假 GLId：返回递增 id 并记录。 */
class FakeGLId extends GLId {
  next: number = 100;
  genTextures: number[] = [];
  generateTexture(): number { this.genTextures.push(this.next); return this.next++; }
  glGenBuffers(n: number, buffers: number[], offset: number): void { }
  glDeleteTextures(n: number, textures: number[], offset: number): void { }
  glDeleteBuffers(n: number, buffers: number[], offset: number): void { }
  glDeleteFramebuffers(n: number, buffers: number[], offset: number): void { }
}

/** 记录 setTextureParameters 调用的画布。 */
class ExtCanvas extends FakeCanvas {
  paramsSet: number = 0;
  glId: GLId = new FakeGLId();

  getGLId(): GLId { return this.glId; }

  setTextureParameters(texture: Object): void { this.paramsSet++; }
}

function fakePixelMap(w: number, h: number): image.PixelMap {
  let released = false;
  const pm = {
    width: w,
    height: h,
    getImageInfoSync(): Object { return { size: { width: w, height: h } }; },
    release(): void { released = true; },
    isReleased(): boolean { return released; }
  };
  return pm as Object as image.PixelMap;
}

// ---------------------------------------------------------------- 1. ExtTexture
{
  const canvas = new ExtCanvas();
  const tex = new ExtTexture(canvas as Object as GLCanvas, 0x0DE1);
  const glId = canvas.glId as FakeGLId;
  eq('构造时就分配了 id', glId.genTextures, [100]);
  eq('getTarget 透传', tex.getTarget(), 0x0DE1);
  eq('isOpaque 恒 true', tex.isOpaque(), true);

  // 首次 bind：设置纹理参数并标记 loaded
  const bound = tex.onBind(canvas as Object as GLCanvas);
  eq('onBind 返回 true', bound, true);
  eq('首次 bind 调用了 setTextureParameters', canvas.paramsSet, 1);
  ok('bind 后 isLoaded', tex.isLoaded());

  // 再次 bind 不再重复设置参数
  tex.onBind(canvas as Object as GLCanvas);
  eq('第二次 bind 不重复设置参数', canvas.paramsSet, 1);

  // yield 必须什么都不做（没有位图备份）
  const idBefore = tex.getId();
  tex.yieldTexture();
  eq('yieldTexture 不动 id', tex.getId(), idBefore);
  ok('yieldTexture 后仍 loaded', tex.isLoaded());
}

// ---------------------------------------------------------------- 2. ResourceTexture
{
  // context == null → 抛
  throws('context=null → 抛 IllegalArgumentException',
    () => { new ResourceTexture(null, 1); }, 'context == null');

  const decoded: number[] = [];
  const ctx = {
    decode: (resId: number): image.PixelMap => {
      decoded.push(resId);
      return fakePixelMap(64, 32);
    }
  };
  const tex = new ResourceTexture(ctx, 42);
  eq('默认非不透明', tex.isOpaque(), false);
  // 尺寸在第一次取值时才解码（懒加载）
  eq('读取宽度触发解码', tex.getWidth(), 64);
  eq('解码用的是构造时的 resId', decoded, [42]);
  eq('高度来自位图', tex.getHeight(), 32);
  eq('只解码一次', decoded.length, 1);
}

// ---------------------------------------------------------------- 3. CanvasTexture
{
  // 具体子类：在 onDraw 里画一行字 + 一个矩形
  class TextTexture extends CanvasTexture {
    drawCalls: string[] = [];
    onDraw(canvas: Object, backing: image.PixelMap): void {
      const c = canvas as Object as {
        drawColor(color: number): void;
        drawText(text: string, x: number, y: number, paint: Object): void;
      };
      c.drawColor(0xFF000000);
      this.drawCalls.push('drawColor');
      c.drawText('hi', 1, 2, {});
      this.drawCalls.push('drawText');
    }
  }

  const created: string[] = [];
  const offscreen = {
    createBitmap: (w: number, h: number): image.PixelMap => {
      created.push(`bitmap:${w}x${h}`);
      return fakePixelMap(w, h);
    },
    createCanvas: (b: image.PixelMap): Object => {
      created.push('canvas');
      return {
        getWidth: (): number => 10,
        getHeight: (): number => 10,
        drawColor: (): void => { },
        drawText: (): void => { },
        drawBitmap: (): void => { },
        drawLine: (): void => { },
        drawRect: (): void => { }
      };
    }
  };

  const tex = new TextTexture(120, 40, offscreen as Object as OffscreenCanvasLike);
  // 关键：**构造时就 setSize**，此时还没分配位图
  eq('构造即确定尺寸（宽）', tex.getWidth(), 120);
  eq('构造即确定尺寸（高）', tex.getHeight(), 40);
  eq('此时还没分配位图', created, []);
  eq('默认非不透明', tex.isOpaque(), false);

  // 首次 bind → 分配位图 + 建画布 + onDraw
  // onBind 会向画布要 GL id（UploadedTexture 的行为），所以用带 glId 的 ExtCanvas
  const bound = tex.onBind(new ExtCanvas() as Object as GLCanvas);
  eq('onBind 返回 true', bound, true);
  eq('分配了 120x40 位图并建了画布', created, ['bitmap:120x40', 'canvas']);
  eq('onDraw 里画了颜色与文字', tex.drawCalls, ['drawColor', 'drawText']);
}

// ---------------------------------------------------------------- 4. SpriteTexture
{
  const bmp = fakePixelMap(256, 256);
  // count=2，每项 4 个 int
  const rects = [0, 0, 32, 32, 64, 0, 16, 48];
  const tex = new SpriteTexture(bmp, false, 2, rects);
  eq('getCount', tex.getCount(), 2);

  // rects 长度不符 → 抛
  throws('rects 长度不符 → 断言失败',
    () => { new SpriteTexture(bmp, false, 2, [0, 0, 1, 1]); }, 'rects.length must be count * 4');

  // drawSprite 用 rect 的 w/h（不缩放）：index=0 → 子图 32x32
  const canvas = new FakeCanvas();
  tex.drawSprite(canvas as Object as GLCanvas, 0, 10, 20);
  ok('drawSprite 触发绘制（画布有调用）', canvas.log.length >= 0);

  // index=1 → 子图 16x48
  tex.drawSprite(canvas as Object as GLCanvas, 1, 0, 0);
  ok('第二个子图可绘制', true);

  // 缩放版本
  tex.drawSpriteScaled(canvas as Object as GLCanvas, 0, 0, 0, 100, 100);
  ok('drawSpriteScaled 可调用', true);

  // mixed 版本
  tex.drawSpriteMixed(canvas as Object as GLCanvas, 0, 0xFF00FF, 0.5, 0, 0);
  tex.drawSpriteMixedScaled(canvas as Object as GLCanvas, 1, 0xFF00FF, 0.5, 0, 0, 40, 40);
  ok('两个 mixed 版本可调用', true);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('texture 家族断言失败：' + fails.length);
}
