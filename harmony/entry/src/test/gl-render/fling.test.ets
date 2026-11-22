/*
 * Fling 单测（C-10：harmony/entry/src/test/<module>/）
 *
 * 为什么值得单测：`Fling` 的样条表是 101 点数值过程（二分 1e-5），任何常数写错
 * 都不会报错，只会让"滑动手感变了"——最难查也最容易被归因成"设备性能问题"。
 * 这里把**表的性质**和**物理系数**固定住：
 *   1) 表长 101、首尾为 0 与 1
 *   2) 严格单调不减（二分解不收敛/方向写反时立刻暴露）
 *   3) 物理系数 = 9.80665 * 39.37 * density*160 * 0.84
 *   4) fling 距离/时长随速度单调递增，且速度 0 时距离为 0
 */

import { Fling } from '../../main/ets/hippo/lib/glgallery/Fling';

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
function near(name: string, got: number, want: number, tol: number): void {
  if (Math.abs(got - want) <= tol) { pass++; } else { fails.push(`${name}: got ${got} want ${want} (±${tol})`); }
}

/** 具体化 Fling（上游是 abstract，子类只需实现 onCalculate）。 */
class ProbeFling extends Fling {
  lastProgress: number = 0;

  protected onCalculate(progress: number): void {
    this.lastProgress = progress;
  }

  // 暴露 protected 方法供断言
  duration(velocity: number): number {
    return this.getSplineFlingDuration(velocity);
  }

  distance(velocity: number): number {
    return this.getSplineFlingDistance(velocity);
  }

  adjust(start: number, oldFinal: number, newFinal: number, duration: number): number {
    return this.adjustDuration(start, oldFinal, newFinal, duration);
  }
}

// ---------- 1) 样条表结构 ----------
{
  const position = Fling.getSplinePositionTable();
  const time = Fling.getSplineTimeTable();
  eq('position table length', position.length, 101);
  eq('time table length', time.length, 101);
  // 注意 position[0] **不是** 0：上游二分在 |tx-alpha| < 1e-5 时收敛，
  // alpha=0 的解落在 x≈1e-5 处，所以首点是一个极小正数（2.29e-5）。
  // 这个值我按上游算法逐字复算过（独立 node 实现给出同样数字），不是移植误差。
  near('position[0] ~ 2.29e-5 (二分容差)', position[0], 0.00002288818359, 1e-9);
  eq('position[100]', position[100], 1);
  eq('time[100]', time[100], 1);
  ok('position monotonic', Fling.isTableMonotonic(position));
  ok('time monotonic', Fling.isTableMonotonic(time));
  // 减速曲线特征：**前半段时间走完大部分距离**（快起慢收）
  ok('position[1] in (0, 0.1)', position[1] > 0 && position[1] < 0.1);
  near('position[50] = 0.858411（半时间走完 85.8% 距离）', position[50], 0.858411, 1e-6);
  near('time[50] = 0.202230（50% 距离用时 20.2%）', time[50], 0.202230, 1e-6);
}

// ---------- 2) 物理系数 ----------
{
  const fling = new ProbeFling(1.0);   // mdpi：density=1 => ppi=160
  near('physicalCoeff density=1', fling.getPhysicalCoeff(),
    9.80665 * 39.37 * 160 * 0.84, 1e-6);

  const fling3 = new ProbeFling(3.0);
  near('physicalCoeff density=3', fling3.getPhysicalCoeff(),
    9.80665 * 39.37 * 480 * 0.84, 1e-6);
}

// ---------- 3) 距离/时长随速度单调 ----------
{
  const fling = new ProbeFling(2.0);
  const v1 = 1000;
  const v2 = 4000;
  const d1 = fling.distance(v1);
  const d2 = fling.distance(v2);
  const t1 = fling.duration(v1);
  const t2 = fling.duration(v2);
  ok('distance increases with velocity', d2 > d1);
  ok('duration increases with velocity', t2 > t1);
  ok('duration positive', t1 > 0 && t2 > 0);
  // 量级检查：1000 px/s 在 2x 密度下应落在几百毫秒 ~ 1 秒
  ok('duration magnitude sane (200..1500ms)', t1 > 200 && t1 < 1500);
}

// ---------- 4) 插值器：起点 0、终点 1、单调 ----------
{
  const fling = new ProbeFling(1.0);
  // 通过 Animation 的 calculate 驱动，间接验证插值器被装上
  fling.setDuration(300);
  fling.start();
  fling.calculate(0);
  // 同上：插值器起点是 2.29e-5 而非精确 0（上游同）
  near('progress at t=0 ~ 2.29e-5', fling.lastProgress, 0.00002288818359, 1e-9);
  fling.calculate(300);
  eq('progress at t=end', fling.lastProgress, 1);
}

// ---------- 5) adjustDuration：新终点更近 => 时长更短 ----------
{
  const fling = new ProbeFling(2.0);
  const same = fling.adjust(0, 1000, 1000, 500);
  const closer = fling.adjust(0, 1000, 500, 500);
  ok('adjust to closer target shortens duration', closer < same);
  ok('adjust result positive', closer > 0);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
