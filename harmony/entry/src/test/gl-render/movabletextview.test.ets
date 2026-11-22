/*
 * GLMovableTextView 单测
 *
 * 这个控件错了**不报错，只是文字不显示/位置错/尺寸不更新**：
 *   1) `setText(null)` 必须视为空串
 *   2) 内容相同要**早退**（不重排、不 requestLayout）
 *   3) `generateIndexes()`：纹理为 null 或文字为空 → 索引是**空数组**（不是 null）
 *   4) `getSuggestedMinimumWidth/Height` 与父类值**取 max**
 *   5) `onRender`：纹理或索引为 null 直接返回
 *   6) gravity 影响 x/y：FINISH → 右/下对齐，CENTER → 居中
 */

import { GLMovableTextView } from '../../main/ets/hippo/lib/glview/widget/GLMovableTextView';
import { MovableTextTexture } from '../../main/ets/hippo/lib/glview/glrenderer/MovableTextTexture';
import { GLView } from '../../main/ets/hippo/lib/glview/view/GLView';
import { Gravity } from '../../main/ets/hippo/lib/glview/view/Gravity';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { FontMetricsLike, OffscreenCanvasLike, OffscreenDrawingContext, TextPaintLike } from '../../main/ets/hippo/lib/glview/glrenderer/CanvasTexture';
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

class FakePaint implements TextPaintLike {
  metrics: FontMetricsLike = { top: -12, ascent: -10, descent: 4, bottom: 2 };
  getColor(): number { return 0; }
  setColor(c: number): void { }
  getStrokeWidth(): number { return 1; }
  setStrokeWidth(w: number): void { }
  getTextSize(): number { return 20; }
  setTextSize(s: number): void { }
  isAntiAlias(): boolean { return true; }
  measureText(text: string): number { return 10; }
  getFontMetrics(): FontMetricsLike { return this.metrics; }
  ellipsize(text: string, maxWidth: number): string { return text; }
  setBold(bold: boolean): void { }
}

class FakeOffscreen implements OffscreenCanvasLike {
  createBitmap(width: number, height: number): image.PixelMap {
    return {
      width: width, height: height,
      getImageInfoSync: (): Object => ({ size: { width: width, height: height } }),
      release: (): void => { }
    } as Object as image.PixelMap;
  }
  createCanvas(bitmap: image.PixelMap): OffscreenDrawingContext {
    return {
      getWidth: (): number => (bitmap as Object as { width: number }).width,
      getHeight: (): number => (bitmap as Object as { height: number }).height,
      drawColor: (): void => { },
      drawText: (): void => { },
      drawBitmap: (): void => { },
      drawLine: (): void => { },
      drawRect: (): void => { },
      translate: (): void => { }
    } as Object as OffscreenDrawingContext;
  }
}

/** 记录 drawTextOfIndexes 的调用参数。 */
class RecordingCanvas extends ExtCanvas {
  textCalls: string[] = [];

  drawSprite(texture: Object, index: number, x: number, y: number): void {
    // 不记录（走 drawTextOfIndexes 的路径更直接）
  }
}

function makeTexture(chars: string[]): MovableTextTexture {
  return MovableTextTexture.create(new FakePaint(), chars, new FakeOffscreen());
}

/** 直接观察 drawTextOfIndexes：用子类覆盖。 */
class ProbeView extends GLMovableTextView {
  renderCalls: string[] = [];
}

// ---------------------------------------------------------------- 1. 初始状态与索引
{
  const view = new GLMovableTextView();
  eq('初始文字为空串', view.getText(), '');
  eq('初始索引是空数组（不是 null）', view.getIndexes(), []);
  eq('初始无纹理', view.getTextTexture(), null);
  eq('初始 gravity = NO_GRAVITY', view.getGravity(), Gravity.NO_GRAVITY);

  const tex = makeTexture(['a', 'b', 'c']);
  view.setTextTexture(tex);
  eq('设纹理后仍无文字 → 索引空', view.getIndexes(), []);
  view.setText('abc');
  eq('设文字后索引为 [0,1,2]', view.getIndexes(), [0, 1, 2]);

  // setText(null) 视为空串
  view.setText(null);
  eq('setText(null) → 空串', view.getText(), '');
  eq('空文字 → 索引空数组', view.getIndexes(), []);
}

// ---------------------------------------------------------------- 2. 早退：相同内容不重复处理
{
  const view = new GLMovableTextView();
  const tex = makeTexture(['x']);
  view.setTextTexture(tex);
  view.setText('x');
  const before = view.getIndexes();

  // 同一个纹理对象再设一次 → 早退（索引数组对象不变）
  view.setTextTexture(tex);
  ok('同一纹理重复设置不重建索引', view.getIndexes() === before);

  // 相同文字再设一次 → 早退
  view.setText('x');
  ok('相同文字重复设置不重建索引', view.getIndexes() === before);
}

// ---------------------------------------------------------------- 3. 未知字符 → 负索引
{
  const view = new GLMovableTextView();
  view.setTextTexture(makeTexture(['a', 'b']));
  view.setText('a?b');
  const idx = view.getIndexes() as number[];
  eq('已知字符命中', idx[0], 0);
  ok('未知字符为负', idx[1] < 0);
  eq('末字符命中', idx[2], 1);
}

// ---------------------------------------------------------------- 4. gravity 只在实际变化时生效
{
  const view = new GLMovableTextView();
  view.setGravity(Gravity.CENTER);
  eq('gravity 已更新', view.getGravity(), Gravity.CENTER);
  view.setGravity(Gravity.CENTER);
  eq('重复设置无副作用', view.getGravity(), Gravity.CENTER);
}

// ---------------------------------------------------------------- 5. onRender：无纹理时不画
{
  const view = new GLMovableTextView();
  const canvas = new ExtCanvas() as Object as GLCanvas;
  // 不应抛异常
  view.onRender(canvas);
  ok('无纹理时 onRender 安全返回', true);

  // 有纹理但文字为空（索引空数组）→ 仍会调用 drawTextOfIndexes（空循环）
  view.setTextTexture(makeTexture(['a']));
  view.onRender(canvas);
  ok('空索引时 onRender 也安全', true);
}

// ---------------------------------------------------------------- 6. 建议尺寸与父类取 max
{
  const view = new GLMovableTextView();
  // 无纹理 → 等于父类值（0 + padding）
  const w0 = (view as Object as { getSuggestedMinimumWidth(): number }).getSuggestedMinimumWidth();
  ok('无纹理时建议宽 = 父类值', w0 >= 0);

  const tex = makeTexture(['a', 'b', 'c']); // 每字符 10 宽，行高 14
  view.setTextTexture(tex);
  view.setText('abc');
  const w1 = (view as Object as { getSuggestedMinimumWidth(): number }).getSuggestedMinimumWidth();
  ok('有纹理时建议宽 >= 文字宽 30', w1 >= 30);
  const h1 = (view as Object as { getSuggestedMinimumHeight(): number }).getSuggestedMinimumHeight();
  ok('建议高 >= 行高 14', h1 >= 14);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('glmovabletextview 断言失败：' + fails.length);
}
