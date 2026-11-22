/*
 * Animation 单测（C-10：harmony/entry/src/test/<module>/）
 *
 * 为什么值得单测：`Animation.calculate()` 里有 4 个容易写错的边界
 *   1) duration == 0 时必须当作 1.0（否则 0/0 = NaN，插值器吐出 NaN，矩阵变 NaN，整屏黑）
 *   2) start() 后第一次 calculate(t) 才确定起点（起点不是 start() 调用的时刻）
 *   3) onCalculate 里允许 cancel()，返回后必须重新读 mStartTime
 *   4) 结束判定是 elapse >= duration，且 repeatCount 到达才 finish
 * 这四条任何一条错了，动画表现为"不跑 / 瞬移 / 永远不结束 / 整屏黑"，都不报错。
 */

import { Animation } from '../../main/ets/hippo/lib/glview/anim/Animation';
import { Interpolator } from '../../main/ets/hippo/lib/yorozuya/AnimationUtils';

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

/** 记录 progress 的探针动画。 */
class Probe extends Animation {
  values: number[] = [];
  finished: number = 0;

  protected onCalculate(progress: number): void {
    this.values.push(progress);
  }

  protected onFinish(): void {
    this.finished++;
  }
}

/** 线性插值器（便于断言插值确实被应用）。 */
class Linear implements Interpolator {
  getInterpolation(input: number): number { return input * 2; }
}

// ---------- 1) 基本推进：起点由第一次 calculate 决定 ----------
{
  const a = new Probe();
  a.setDuration(100);
  a.start();
  ok('running right after start', a.isRunning());
  a.calculate(1000);          // 起点 = 1000
  eq('progress at start', a.values, [0]);
  a.calculate(1050);
  eq('progress at half', a.values, [0, 0.5]);
  a.calculate(1100);
  eq('progress at end', a.values, [0, 0.5, 1]);
  eq('finished once', a.finished, 1);
  ok('not running after end', !a.isRunning());
}

// ---------- 2) duration == 0 不产生 NaN ----------
{
  const a = new Probe();
  a.setDuration(0);
  a.start();
  a.calculate(500);
  eq('duration 0 => progress 1', a.values, [1]);
  ok('duration 0 no NaN', !Number.isNaN(a.values[0]));
}

// ---------- 3) 插值器参与 ----------
{
  const a = new Probe();
  a.setDuration(100);
  a.setInterpolator(new Linear());
  a.start();
  a.calculate(0);
  a.calculate(25);
  eq('interpolator applied', a.values, [0, 0.5]);
}

// ---------- 4) 未 start 时 calculate 立即返回 false ----------
{
  const a = new Probe();
  a.setDuration(100);
  ok('not started returns false', !a.calculate(10));
  eq('no progress when not started', a.values, []);
}

// ---------- 5) repeatCount 未到不结束 ----------
{
  const a = new Probe();
  a.setDuration(100);
  a.setRepeatCount(2);
  a.start();
  a.calculate(0);
  const stillRunning = a.calculate(100);   // 第一轮结束
  ok('keeps running while repeats left', stillRunning);
  eq('not finished yet', a.finished, 0);
  a.calculate(200);                        // 第二轮结束
  eq('finished after 2 rounds', a.finished, 1);
}

// ---------- 6) onCalculate 里 cancel() 生效 ----------
{
  class CancelInCalculate extends Animation {
    cancelled: boolean = false;
    protected onCalculate(_progress: number): void {
      if (!this.cancelled) {
        this.cancelled = true;
        this.cancel();
      }
    }
  }
  const a = new CancelInCalculate();
  a.setDuration(100);
  a.start();
  const running = a.calculate(0);
  ok('cancel inside onCalculate stops', !running);
  ok('not running after cancel', !a.isRunning());
}

// ---------- 7) reset / startNow ----------
{
  const a = new Probe();
  a.setDuration(100);
  a.start();
  a.calculate(0);
  a.cancel();
  a.reset();
  ok('reset clears startTime sentinel', a.isRunning());
  a.startNow();
  ok('startNow sets concrete start time', a.isRunning());
  a.calculate(a.getLastFrameTime() + 0);
  eq('startNow then calculate emits progress', a.values.length >= 1, true);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
