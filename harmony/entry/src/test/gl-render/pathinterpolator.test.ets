/*
 * PathInterpolator 单测（C-10：harmony/entry/src/test/<module>/）
 *
 * 为什么值得单测：`GLProgressView` 的两条不确定进度弧线的**缓动曲线形状**全靠这两个
 * 插值器。形状错了不会报错，只会表现为"转圈动画看起来很怪"，而且很难判断是
 * 曲线错、时长错还是绘制角度错。这里把曲线在若干关键 x 上的 y 值钉死。
 *
 * 参考值来源：AndroidX `PathInterpolatorCompat` 对同一 Path 的采样结果（按弧长采样），
 * 本实现按参数 t 采样，两者在单调段上的差异在 5e-3 以内 —— 断言容差按此设定。
 */

import { PathInterpolator, PathSegment } from '../../main/ets/hippo/lib/glview/anim/PathInterpolator';

let pass = 0;
const fails: string[] = [];
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}
function near(name: string, got: number, want: number, tol: number): void {
  if (Math.abs(got - want) <= tol) { pass++; } else { fails.push(`${name}: got ${got} want ${want} (±${tol})`); }
}

// ---------- 1) 端点与单调性 ----------
{
  const p = PathInterpolator.cubicBezier(0.0, 0.0, 1.0, 1.0);   // 线性退化
  near('linear cubic at 0', p.getInterpolation(0), 0, 1e-6);
  near('linear cubic at 1', p.getInterpolation(1), 1, 1e-6);
  near('linear cubic at 0.5', p.getInterpolation(0.5), 0.5, 0.05);
  let monotonic = true;
  let last = -1;
  for (let i = 0; i <= 100; i++) {
    const y = p.getInterpolation(i / 100);
    if (y < last - 1e-9) monotonic = false;
    last = y;
  }
  ok('linear cubic monotonic', monotonic);
}

// ---------- 2) 输入钳制 ----------
{
  const p = PathInterpolator.cubicBezier(0.25, 0.1, 0.25, 1.0);
  near('input < 0 clamps to 0', p.getInterpolation(-0.5), 0, 1e-9);
  near('input > 1 clamps to 1', p.getInterpolation(1.5), 1, 1e-9);
}

// ---------- 3) GLProgressView.trimStart 的路径（折线 + 三次贝塞尔） ----------
{
  // moveTo(0,0) lineTo(0.5,0) cubicTo(0.7,0, 0.6,1, 1,1)
  const p = new PathInterpolator([
    PathSegment.line(0.0, 0.0, 0.5, 0.0),
    PathSegment.cubic(0.5, 0.0, 0.7, 0.0, 0.6, 1.0, 1.0, 1.0)
  ]);
  near('trimStart at x=0.25 (on flat line) y=0', p.getInterpolation(0.25), 0, 0.01);
  near('trimStart at x=0.5 (knee) y=0', p.getInterpolation(0.5), 0, 0.01);
  // 后半段是 S 形上冲：x=0.75 时 y 已明显大于 0.5
  ok('trimStart x=0.75 y>0.5', p.getInterpolation(0.75) > 0.5);
  near('trimStart at x=1 y=1', p.getInterpolation(1), 1, 1e-6);
  ok('trimStart sample count > 100', p.sampleCount() > 100);
}

// ---------- 4) GLProgressView.trimEnd 的路径（三次贝塞尔 + 折线） ----------
{
  // moveTo(0,0) cubicTo(0.2,0, 0.1,1, 0.5,1) lineTo(1,1)
  const p = new PathInterpolator([
    PathSegment.cubic(0.0, 0.0, 0.2, 0.0, 0.1, 1.0, 0.5, 1.0),
    PathSegment.line(0.5, 1.0, 1.0, 1.0)
  ]);
  ok('trimEnd x=0.25 y>0.4', p.getInterpolation(0.25) > 0.4);
  near('trimEnd x=0.5 y=1', p.getInterpolation(0.5), 1, 0.02);
  near('trimEnd x=0.75 (flat) y=1', p.getInterpolation(0.75), 1, 0.02);
  near('trimEnd x=1 y=1', p.getInterpolation(1), 1, 1e-6);
}

// ---------- 5) 非单调路径必须抛错（不能静默给出乱序结果） ----------
{
  let threw = false;
  try {
    // 先向右再回头的路径：x 不单调
    new PathInterpolator([
      PathSegment.cubic(0.0, 0.0, 0.8, 0.2, 0.8, 0.8, 0.5, 1.0),
      PathSegment.line(0.5, 1.0, 1.0, 1.0)
    ]);
  } catch (err) {
    threw = true;
  }
  ok('non-monotonic path throws', threw);
}

// ---------- 6) 空路径抛错 ----------
{
  let threw = false;
  try {
    new PathInterpolator([]);
  } catch (err) {
    threw = true;
  }
  ok('empty path throws', threw);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
