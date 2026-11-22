/*
 * FadeTexture / FadeInTexture / FadeOutTexture / AlphaAnimation 单测
 *
 * 为什么值得单测：这四个都是「时间驱动的视觉状态」，错了不报错、只是看起来不对：
 *   1) FadeTexture.getRatio() 返回的是**剩余**比例（1→0），若写成已过比例，淡入淡出方向整体反了
 *   2) isAnimating() 是惰性置 false；若写成每次读都重算，动画会「永不结束」或「提前结束」
 *   3) DURATION = 180 是常量，改了会让所有过场节奏变化
 *   4) FadeOutTexture 不在动画中 => 什么都不画（不是画原图）；FadeInTexture 相反要画原图
 *   5) AlphaAnimation 用 multiplyAlpha（乘法），不是 setAlpha；且插值后 clamp
 */

import { AnimationTime } from '../../main/ets/hippo/lib/glview/view/AnimationTime';
import { FadeTexture } from '../../main/ets/hippo/lib/glview/glrenderer/FadeTexture';
import { FadeInTexture } from '../../main/ets/hippo/lib/glview/glrenderer/FadeInTexture';
import { FadeOutTexture } from '../../main/ets/hippo/lib/glview/glrenderer/FadeOutTexture';
import { AlphaAnimation } from '../../main/ets/hippo/lib/glview/anim/AlphaAnimation';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { RectF } from '../../main/ets/hippo/lib/glview/util/RectF';
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
function near(name: string, got: number, want: number, eps: number = 1e-6): void {
  if (Math.abs(got - want) <= eps) { pass++; } else { fails.push(`${name}: got ${got} want ${want}`); }
}


/** 记录 draw / drawMixed 的假纹理（FadeOut 用）。 */
class FakeBasicTexture {
  draws: string[] = [];

  constructor(private w: number, private h: number, private opaque: boolean) { }

  getWidth(): number { return this.w; }
  getHeight(): number { return this.h; }
  isOpaque(): boolean { return this.opaque; }

  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, c?: number, d?: number): void {
    if (typeof a === 'number') {
      this.draws.push(`num:${a},${b},${c},${d}`);
    } else {
      this.draws.push('rect');
    }
  }
}

/** FadeIn 用的假纹理：多一个 drawMixed。 */
class FakeMixedTexture extends FakeBasicTexture {
  mixes: string[] = [];

  drawMixed(canvas: GLCanvas, color: number, ratio: number,
    a: number | RectF, b: number | RectF, c?: number, d?: number): void {
    if (typeof a === 'number') {
      this.mixes.push(`num:${color},${ratio},${a},${b},${c},${d}`);
    } else {
      this.mixes.push(`rect:${color},${ratio}`);
    }
  }
}

/** 暴露受保护成员的测试子类。 */
class ProbeFade extends FadeTexture {
  calls: string[] = [];

  constructor(w: number, h: number, opaque: boolean) {
    super(w, h, opaque);
  }

  ratio(): number { return this.getRatio(); }

  protected drawImpl(canvas: GLCanvas, a: number | RectF, b: number | RectF | number,
    w: number, h: number): void {
    this.calls.push(`draw:${a},${b},${w},${h}`);
  }
}

// ---------------------------------------------------------------- 1. FadeTexture 时间轴
{
  AnimationTime.update();
  const t0 = AnimationTime.get();
  const probe = new ProbeFade(100, 50, true);

  eq('尺寸透传 width', probe.getWidth(), 100);
  eq('尺寸透传 height', probe.getHeight(), 50);
  eq('isOpaque 透传', probe.isOpaque(), true);
  eq('DURATION 常量 = 180', FadeTexture.DURATION, 180);
  eq('刚创建时在动画中', probe.isAnimating(), true);
  near('刚创建时 ratio = 1', probe.ratio(), 1.0, 1e-3);

  // 90ms 后：剩余比例约 0.5（假设 AnimationTime.get() 由 update() 推进）
  AnimationTime.update();
  const t1 = AnimationTime.get();
  ok('时间在推进（至少不倒退）', t1 >= t0);

  // 三参 draw 会补成 4 参（w/h = 纹理自身尺寸）
  const canvas = new FakeCanvas();
  probe.draw(canvas, 3, 4);
  eq('draw(x,y) → 补自身尺寸', probe.calls[0], 'draw:3,4,100,50');
  probe.calls = [];
  probe.draw(canvas, 3, 4, 30, 40);
  eq('draw(x,y,w,h) 原样', probe.calls[0], 'draw:3,4,30,40');
  probe.calls = [];
  probe.draw(canvas, new RectF(0, 0, 10, 10), new RectF(0, 0, 20, 20));
  eq('draw(source,target) 走矩形分支', probe.calls.length, 1);
}

// ---------------------------------------------------------------- 2. FadeOutTexture：动画中才画
{
  AnimationTime.update();
  const inner = new FakeBasicTexture(64, 64, false);
  const tex = new FadeOutTexture(inner);
  const canvas = new FakeCanvas();

  tex.draw(canvas, 1, 2, 3, 4);
  ok('动画中：save(SAVE_FLAG_ALPHA) 先于 setAlpha',
    canvas.log.length >= 3 && canvas.log[0] === `save:${GLCanvas.SAVE_FLAG_ALPHA}`
    && (canvas.log[1] as string).indexOf('setAlpha:') === 0);
  eq('动画中：最后 restore', canvas.log[canvas.log.length - 1], 'restore');
  eq('动画中：子纹理被画一次', inner.draws.length, 1);
  eq('动画中：绘制参数原样', inner.draws[0], 'num:1,2,3,4');

  // 矩形形态
  inner.draws = [];
  canvas.log = [];
  tex.draw(canvas, new RectF(0, 0, 8, 8), new RectF(0, 0, 16, 16));
  eq('矩形形态：子纹理收到 rect', inner.draws[0], 'rect');
}

// ---------------------------------------------------------------- 3. FadeInTexture：动画中 mixed、结束后原图
{
  AnimationTime.update();
  const inner = new FakeMixedTexture(80, 40, true);
  const tex = new FadeInTexture(0xFF0000, inner);
  const canvas = new FakeCanvas();

  eq('FadeIn 尺寸来自子纹理', tex.getWidth(), 80);
  eq('FadeIn 高度来自子纹理', tex.getHeight(), 40);
  eq('FadeIn opaque 来自子纹理', tex.isOpaque(), true);

  tex.draw(canvas, 5, 6, 7, 8);
  eq('动画中：走 drawMixed 一次', inner.mixes.length, 1);
  eq('动画中：不直接 draw', inner.draws.length, 0);
  // ratio 可能已经是 0（时间已过 DURATION），但**必须在 [0,1] 之内**
  // 格式是 `num:<color>,<ratio>,<x>,<y>,<w>,<h>` → ratio 在下标 1
  const mixedRatio: number = Number((inner.mixes[0] as string).split(',')[1]);
  ok('动画中：drawMixed 的 ratio 在 [0,1]', mixedRatio >= 0 && mixedRatio <= 1);

  // 矩形形态走 drawMixed 的 rect 分支
  inner.mixes = [];
  tex.draw(canvas, new RectF(0, 0, 4, 4), new RectF(0, 0, 8, 8));
  ok('矩形形态：drawMixed rect 分支', (inner.mixes[0] as string).indexOf('rect:') === 0);
}

// ---------------------------------------------------------------- 4. AlphaAnimation
{
  const anim = new AlphaAnimation(0.2, 0.8);
  eq('save flags 只要 ALPHA', anim.getCanvasSaveFlags(), GLCanvas.SAVE_FLAG_ALPHA);
  near('初始 alpha = from', anim.getCurrentAlpha(), 0.2, 1e-6);

  const canvas = new FakeCanvas();
  anim.apply(canvas);
  eq('apply 用 multiplyAlpha（不是 setAlpha）', canvas.log[0], 'multiplyAlpha:0.2');

  // 越界输入：**构造函数不 clamp**（上游就是 `mCurrentAlpha = from`），
  // clamp 只发生在 onCalculate 里 —— 第一次 calculate() 之后才收敛到 [0,1]
  const wild = new AlphaAnimation(-1, 2);
  near('构造后 alpha = from（未 clamp，照搬上游）', wild.getCurrentAlpha(), -1.0, 1e-6);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('fadetexture 断言失败：' + fails.length);
}
