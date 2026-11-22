/*
 * MovableTextTexture 单测
 *
 * 这个类错了**不报错，只是文字画歪/缺字/图集巨大**：
 *   1) 图集网格的两次缩减（顺序不能换）
 *   2) binarySearch 找不到时返回负数 → 绘制时**只前进不画**（空格等）
 *   3) drawText 的 x 累加用 `widths[index]`（该字符实际宽度），不是 maxWidth
 *   4) 图集绘制前 translate(0, height - fixed)
 */

import { MovableTextTexture } from '../../main/ets/hippo/lib/glview/glrenderer/MovableTextTexture';
import { FontMetricsLike, OffscreenCanvasLike, OffscreenDrawingContext, TextPaintLike } from '../../main/ets/hippo/lib/glview/glrenderer/CanvasTexture';
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
function near(name: string, got: number, want: number, eps: number = 1e-4): void {
  if (Math.abs(got - want) <= eps) { pass++; } else { fails.push(`${name}: got ${got} want ${want}`); }
}

/** 假 paint：字符宽度由映射表决定（默认等宽 10）。 */
class FakeTextPaint implements TextPaintLike {
  metrics: FontMetricsLike = { top: -12, ascent: -10, descent: 4, bottom: 2 };
  widths: Map<string, number> = new Map<string, number>();

  constructor(private defaultWidth: number = 10) { }

  getColor(): number { return 0xFF000000; }
  setColor(color: number): void { }
  getStrokeWidth(): number { return 1; }
  setStrokeWidth(width: number): void { }
  getTextSize(): number { return 20; }
  setTextSize(size: number): void { }
  isAntiAlias(): boolean { return true; }
  measureText(text: string): number {
    const w = this.widths.get(text);
    return w === undefined ? this.defaultWidth : w;
  }
  getFontMetrics(): FontMetricsLike { return this.metrics; }
  ellipsize(text: string, maxWidth: number): string { return text; }
  setBold(bold: boolean): void { }
}

class FakeOffscreen implements OffscreenCanvasLike {
  created: string[] = [];
  ops: string[] = [];

  createBitmap(width: number, height: number): image.PixelMap {
    this.created.push(`${width}x${height}`);
    return {
      width: width,
      height: height,
      getImageInfoSync: (): Object => ({ size: { width: width, height: height } }),
      release: (): void => { }
    } as Object as image.PixelMap;
  }

  createCanvas(bitmap: image.PixelMap): OffscreenDrawingContext {
    const self = this;
    return {
      getWidth: (): number => (bitmap as Object as { width: number }).width,
      getHeight: (): number => (bitmap as Object as { height: number }).height,
      drawColor: (): void => { },
      drawText: (text: string, x: number, y: number, paint: TextPaintLike): void => {
        self.ops.push(`text:${text}@${x},${y}`);
      },
      drawBitmap: (): void => { },
      drawLine: (): void => { },
      drawRect: (): void => { },
      translate: (dx: number, dy: number): void => { self.ops.push(`translate:${dx},${dy}`); }
    } as Object as OffscreenDrawingContext;
  }
}

// ---------------------------------------------------------------- 1. 图集网格与 rect
{
  const paint = new FakeTextPaint(10);
  const off = new FakeOffscreen();
  const chars = ['a', 'b', 'c', 'd'];
  const tex = MovableTextTexture.create(paint, chars, off);

  // height = bottom - top = 2 - (-12) = 14；maxWidth = 10；length = 4
  // hCount = ceil(sqrt(14/10*4)) = ceil(sqrt(5.6)) = ceil(2.366) = 3
  // vCount = ceil(sqrt(10/14*4)) = ceil(sqrt(2.857)) = ceil(1.690) = 2
  // 缩减：hCount*(vCount-1)=3*1=3 > 4? 否； (hCount-1)*vCount=2*2=4 > 4? 否
  // 位图 = ceil(3*10) x ceil(2*14) = 30 x 28
  eq('图集尺寸 30x28', off.created, ['30x28']);
  eq('行高 14', tex.getTextHeight(), 14);
  eq('maxWidth 10', tex.getMaxWidth(), 10);
  eq('sprite 数量 = 字符数', tex.getCount(), 4);
  eq('绘制前 translate(0, height-fixed) = translate(0,12)', off.ops[0], 'translate:0,12');
  eq('逐字符画进图集', off.ops.length, 1 + 4);
  eq('第一个字符在 (0,0)', off.ops[1], 'text:a@0,0');
  eq('第二个字符 x 前进 maxWidth', off.ops[2], 'text:b@10,0');
  // 换行发生在**画完当前字符之后**：i=2 时 i%hCount == hCount-1(2) → 先画在 (20,0)，再重置 x、y+=height
  eq('第三个字符画在行末 (20,0)', off.ops[3], 'text:c@20,0');
  eq('第四个字符换到下一行行首 (0,14)', off.ops[4], 'text:d@0,14');
}

// ---------------------------------------------------------------- 2. 索引查找（找不到为负）
{
  const paint = new FakeTextPaint(10);
  const off = new FakeOffscreen();
  // 字符数组必须**排序**（上游用 binarySearch，要求有序）
  const tex = MovableTextTexture.create(paint, ['a', 'b', 'c'], off);
  eq('索引：命中', tex.getTextIndexes('abc'), [0, 1, 2]);
  const idx = tex.getTextIndexes('a c');
  eq('空格命中 0 号之外？(空格不在表里 → 负数)', idx[0], 0);
  ok('空格返回负值', (idx[1] as number) < 0);
  eq('末字符命中', idx[2], 2);
}

// ---------------------------------------------------------------- 3. 宽度累加
{
  const paint = new FakeTextPaint(10);
  paint.widths.set('W', 25);
  const off = new FakeOffscreen();
  const tex = MovableTextTexture.create(paint, ['W', 'a'], off);

  near('"Wa" 宽度 = 25 + 10', tex.getTextWidth('Wa'), 35);
  // maxWidth = 所有字宽的最大值 = 25（不是默认 10）
  near('不存在的字符按 maxWidth 计', tex.getTextWidth('W?'), 25 + 25);
  near('索引版宽度', tex.getTextWidthOfIndexes([0, 1]), 35);
  near('索引版遇到负值按 maxWidth', tex.getTextWidthOfIndexes([0, -1]), 25 + 25);
}

// ---------------------------------------------------------------- 4. 绘制路径
{
  const paint = new FakeTextPaint(10);
  const off = new FakeOffscreen();
  const tex = MovableTextTexture.create(paint, ['a', 'b'], off);
  const canvas = new ExtCanvas() as Object as GLCanvas;

  // drawText：命中的字符推进该字符宽度
  tex.drawText(canvas, 'ab', 5, 7);
  ok('drawText 不抛', true);

  // 含未知字符：只前进不画
  tex.drawText(canvas, 'a?b', 0, 0);
  ok('含未知字符时也能走通', true);

  const indexes = tex.getTextIndexes('ab');
  tex.drawTextOfIndexes(canvas, indexes, 0, 0);
  ok('drawTextOfIndexes 走通', true);
}

// ---------------------------------------------------------------- 5. 不同字宽 → 网格缩减
{
  // 让 maxWidth 远大于 height，触发 vCount-- 分支：
  // height=14, maxWidth=100, length=4
  // hCount = ceil(sqrt(14/100*4)) = ceil(sqrt(0.56)) = 1
  // vCount = ceil(sqrt(100/14*4)) = ceil(sqrt(28.57)) = 6
  // hCount*(vCount-1) = 5 > 4 → vCount-- → 5；再判 (hCount-1)*vCount = 0 > 4 否
  const paint = new FakeTextPaint(100);
  const off = new FakeOffscreen();
  const tex = MovableTextTexture.create(paint, ['a', 'b', 'c', 'd'], off);
  eq('缩减后位图 = ceil(1*100) x ceil(5*14)', off.created, ['100x70']);
  eq('每行 1 个字符（hCount=1）', off.ops[1], 'text:a@0,0');
  eq('第二字符马上换行', off.ops[2], 'text:b@0,14');
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('movabletext 断言失败：' + fails.length);
}
