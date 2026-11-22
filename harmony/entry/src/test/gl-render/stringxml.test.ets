/*
 * StringTexture / XmlResourceTexture 单测
 *
 * 这两个都在「尺寸计算」上容易静默出错（错了不报错，只是文字被裁/纹理是黑的）：
 *   1) StringTexture：width = ceil(measureText)、height = metrics.bottom - metrics.top、
 *      **两者 <=0 时兜底 1**；绘制前必须 translate(0, -ascent)
 *   2) XmlResourceTexture：宽度<=0 才用 intrinsic（**逐项独立判断**，不是"都 <=0 才用"）；
 *      最终仍 <=0 兜底 1；setBound 必须 invalidateContent
 */

import { StringTexture, TextPaintFactoryLike } from '../../main/ets/hippo/lib/glview/glrenderer/StringTexture';
import {
  XmlResourceTexture, DrawableLike, XmlDrawableContextLike
} from '../../main/ets/hippo/lib/glview/glrenderer/XmlResourceTexture';
import {
  FontMetricsLike, OffscreenCanvasLike, OffscreenDrawingContext, TextPaintLike
} from '../../main/ets/hippo/lib/glview/glrenderer/CanvasTexture';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { image } from '@kit.ImageKit';
import { ExtCanvas } from './fakecanvas';

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

/** 假 paint：measureText 按「字符数 × 字符宽」算；metrics 固定。 */
class FakePaint implements TextPaintLike {
  private textSize: number = 0;
  private color: number = 0;
  private bold: boolean = false;
  charWidth: number = 10;
  metrics: FontMetricsLike = { top: -12, ascent: -10, descent: 4, bottom: 2 };
  ellipsizeCalls: string[] = [];

  constructor(private maxChars: number = Number.MAX_SAFE_INTEGER) { }

  getColor(): number { return this.color; }
  setColor(color: number): void { this.color = color; }
  getStrokeWidth(): number { return 1; }
  setStrokeWidth(width: number): void { }
  getTextSize(): number { return this.textSize; }
  setTextSize(size: number): void { this.textSize = size; }
  isAntiAlias(): boolean { return true; }
  measureText(text: string): number { return text.length * this.charWidth; }
  getFontMetrics(): FontMetricsLike { return this.metrics; }
  ellipsize(text: string, maxWidth: number): string {
    this.ellipsizeCalls.push(`${text}@${maxWidth}`);
    const maxChars: number = Math.floor(maxWidth / this.charWidth);
    if (text.length <= maxChars) { return text; }
    return text.substring(0, Math.max(0, maxChars - 1)) + '…';
  }
  setBold(bold: boolean): void { this.bold = bold; }
  isBold(): boolean { return this.bold; }
}

const paintFactory = (paint: FakePaint): TextPaintFactoryLike => ({
  createDefaultPaint: (textSize: number, color: number): TextPaintLike => {
    paint.setTextSize(textSize);
    paint.setColor(color);
    return paint;
  }
});

/** 记录画布操作的 offscreen。 */
class FakeOffscreen implements OffscreenCanvasLike {
  created: string[] = [];
  ops: string[] = [];

  createBitmap(width: number, height: number): image.PixelMap {
    this.created.push(`${width}x${height}`);
    // UploadedTexture 会通过 getImageInfoSync 读尺寸，桩必须提供
    return {
      width: width,
      height: height,
      getImageInfoSync: (): Object => ({ size: { width: width, height: height } }),
      release: (): void => { }
    } as Object as image.PixelMap;
  }

  createCanvas(bitmap: image.PixelMap): OffscreenDrawingContext {
    const self = this;
    const ctx = {
      getWidth: (): number => (bitmap as Object as { width: number }).width,
      getHeight: (): number => (bitmap as Object as { height: number }).height,
      drawColor: (color: number): void => { self.ops.push(`drawColor:${color}`); },
      drawText: (text: string, x: number, y: number, paint: TextPaintLike): void => {
        self.ops.push(`drawText:${text}@${x},${y}`);
      },
      drawBitmap: (): void => { self.ops.push('drawBitmap'); },
      drawLine: (): void => { self.ops.push('drawLine'); },
      drawRect: (): void => { self.ops.push('drawRect'); },
      translate: (dx: number, dy: number): void => { self.ops.push(`translate:${dx},${dy}`); }
    };
    return ctx as Object as OffscreenDrawingContext;
  }
}

// ---------------------------------------------------------------- 1. StringTexture 尺寸
{
  const paint = new FakePaint();
  paint.charWidth = 10;
  const off = new FakeOffscreen();
  const tex = StringTexture.newInstance('hello', 20, 0xFFFFFFFF, paintFactory(paint), off);

  // width = ceil(5 * 10) = 50；height = bottom - top = 2 - (-12) = 14
  eq('宽度 = ceil(measureText)', tex.getWidth(), 50);
  eq('高度 = metrics.bottom - metrics.top', tex.getHeight(), 14);
  eq('文字透传', tex.getText(), 'hello');

  // 空串 → 宽 0 → 兜底 1；高仍按 metrics
  const empty = StringTexture.newInstance('', 20, 0xFF, paintFactory(new FakePaint()), off);
  eq('空串宽度兜底为 1', empty.getWidth(), 1);

  // metrics 高度为 0 → 兜底 1
  const flat = new FakePaint();
  flat.metrics = { top: 0, ascent: 0, descent: 0, bottom: 0 };
  const flatTex = StringTexture.newInstance('x', 20, 0xFF, paintFactory(flat), off);
  eq('行高 0 兜底为 1', flatTex.getHeight(), 1);
}

// ---------------------------------------------------------------- 2. StringTexture 绘制：translate 后再 drawText
{
  const paint = new FakePaint();
  const off = new FakeOffscreen();
  const tex = StringTexture.newInstance('hi', 20, 0xFF, paintFactory(paint), off);
  // 触发 onGetBitmap → onDraw
  tex.onBind(new ExtCanvas() as Object as GLCanvas);
  eq('先分配位图', off.created, ['20x14']);
  eq('绘制顺序：translate 再 drawText', off.ops, ['translate:0,10', 'drawText:hi@0,0']);
  // ascent=-10 → translate(0, -(-10)) = translate(0, 10)（把基线向下挪，让文字顶部贴 0）
}

// ---------------------------------------------------------------- 3. StringTexture 截断
{
  const paint = new FakePaint();
  paint.charWidth = 10;
  const off = new FakeOffscreen();
  // 限制宽度 45 → 最多 4 个字符 → "abcd…"（4 字符里留 1 个给省略号）
  const tex = StringTexture.newInstanceLimited('abcdefgh', 20, 0xFF, 45, false, paintFactory(paint), off);
  ok('长度超限被截断', tex.getText().length < 8);
  ok('截断后带省略号', tex.getText().indexOf('…') >= 0);
  eq('ellipsize 被以正确的 maxWidth 调用', paint.ellipsizeCalls, ['abcdefgh@45']);

  // lengthLimit = 0 不截断
  const paint2 = new FakePaint();
  const off2 = new FakeOffscreen();
  const tex2 = StringTexture.newInstanceLimited('abcdefgh', 20, 0xFF, 0, false, paintFactory(paint2), off2);
  eq('lengthLimit=0 不截断', tex2.getText(), 'abcdefgh');

  // isBold 会传到 paint
  const paint3 = new FakePaint();
  StringTexture.newInstanceLimited('x', 20, 0xFF, 0, true, paintFactory(paint3), new FakeOffscreen());
  ok('isBold=true 传到 paint', paint3.isBold());
}

// ---------------------------------------------------------------- 4. XmlResourceTexture 尺寸三条规则
{
  const makeDrawable = (iw: number, ih: number): DrawableLike => ({
    getIntrinsicWidth: (): number => iw,
    getIntrinsicHeight: (): number => ih,
    setBounds: (l: number, t: number, r: number, b: number): void => { },
    draw: (canvas: OffscreenDrawingContext): void => { canvas.drawColor(0xFF00FF00); }
  });

  // 未 setBound → 都用 intrinsic（100x50）
  {
    const off = new FakeOffscreen();
    const ctx: XmlDrawableContextLike = { getDrawable: (): DrawableLike => makeDrawable(100, 50) };
    const tex = new XmlResourceTexture(ctx, 7, off);
    tex.onBind(new ExtCanvas() as Object as GLCanvas);
    eq('未 setBound → 用 intrinsic 尺寸', off.created, ['100x50']);
    // 0xFF00FF00 作为无符号 32 位是 4278255360（Java int 里是 -16711936）
    eq('drawable.draw 被调用（画了颜色）', off.ops, ['drawColor:4278255360']);
  }

  // setBound(30, 0) → 宽用 30、高用 intrinsic 50（**逐项独立判断**）
  {
    const off = new FakeOffscreen();
    const ctx: XmlDrawableContextLike = { getDrawable: (): DrawableLike => makeDrawable(100, 50) };
    const tex = new XmlResourceTexture(ctx, 7, off);
    tex.setBound(30, 0);
    tex.onBind(new ExtCanvas() as Object as GLCanvas);
    eq('宽用 bound、高用 intrinsic（逐项判断）', off.created, ['30x50']);
  }

  // setBound(-5, -5) 且 intrinsic 也是 0 → 兜底 1x1
  {
    const off = new FakeOffscreen();
    const ctx: XmlDrawableContextLike = { getDrawable: (): DrawableLike => makeDrawable(0, 0) };
    const tex = new XmlResourceTexture(ctx, 7, off);
    tex.setBound(-5, -5);
    tex.onBind(new ExtCanvas() as Object as GLCanvas);
    eq('全都 <=0 → 兜底 1x1', off.created, ['1x1']);
  }

  // setBound 会 invalidateContent：改完尺寸后重新取值应换尺寸
  {
    const off = new FakeOffscreen();
    const ctx: XmlDrawableContextLike = { getDrawable: (): DrawableLike => makeDrawable(10, 10) };
    const tex = new XmlResourceTexture(ctx, 7, off);
    tex.setBound(20, 20);
    tex.onBind(new ExtCanvas() as Object as GLCanvas);
    eq('第一次按 20x20', off.created, ['20x20']);
    tex.setBound(40, 40);
    tex.onBind(new ExtCanvas() as Object as GLCanvas);
    eq('setBound 后重新分配 40x40（invalidateContent 生效）', off.created, ['20x20', '40x40']);
  }

  eq('默认非不透明', new XmlResourceTexture(
    { getDrawable: (): DrawableLike => makeDrawable(1, 1) }, 1, new FakeOffscreen()).isOpaque(), false);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('string/xml 纹理断言失败：' + fails.length);
}
