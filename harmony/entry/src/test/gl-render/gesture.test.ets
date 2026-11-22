/*
 * 手势**序列**测试（Lead 建议：不要只测单次事件）
 *
 * `GestureRecognizer` 是 AOSP `GestureDetector` + `ScaleGestureDetector` 的重写（D-026），
 * 判定依赖**时序**：tap 要等 `DOUBLE_TAP_TIMEOUT` 才确认，双击要在窗口内，
 * 长按要 500ms 不移动。单事件测试无法覆盖这些分支 —— 这里按时间轴推事件序列。
 *
 * 时序常量（AOSP 原值）：TAP_TIMEOUT=100 / DOUBLE_TAP_TIMEOUT=300 /
 * DOUBLE_TAP_MIN_TIME=40 / LONG_PRESS_TIMEOUT=500 / TOUCH_SLOP=8dp
 */

import { GestureRecognizer, GestureRecognizerListener } from '../../main/ets/hippo/lib/glgallery/GestureRecognizer';
import { MotionEvent, PointerCoords } from '../../main/ets/hippo/lib/glview/util/MotionEvent';

let pass = 0;
const fails: string[] = [];
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => { setTimeout(resolve, ms); });
}

/** 记录所有回调（顺序敏感）。 */
class Recorder implements GestureRecognizerListener {
  log: string[] = [];
  scrolls: number[][] = [];
  scaleFactors: number[] = [];
  flingSpeed: number[] = [];

  private push(s: string): void { this.log.push(s); }

  onSingleTapUp(x: number, y: number): boolean { this.push('tapUp'); return true; }
  onSingleTapConfirmed(x: number, y: number): boolean { this.push('tapConfirmed'); return true; }
  onDoubleTap(x: number, y: number): boolean { this.push('doubleTap'); return true; }
  onDoubleTapConfirmed(x: number, y: number): boolean { this.push('doubleTapConfirmed'); return true; }
  onLongPress(x: number, y: number): void { this.push('longPress'); }
  onScroll(dx: number, dy: number, tx: number, ty: number, x: number, y: number): boolean {
    this.push('scroll'); this.scrolls.push([dx, dy, tx, ty]); return true;
  }
  onFling(e1: MotionEvent, e2: MotionEvent, vx: number, vy: number): boolean {
    this.push('fling'); this.flingSpeed.push(Math.sqrt(vx * vx + vy * vy)); return true;
  }
  onScaleBegin(fx: number, fy: number): boolean { this.push('scaleBegin'); return true; }
  onScale(fx: number, fy: number, scale: number): boolean {
    this.push('scale'); this.scaleFactors.push(scale); return true;
  }
  onScaleEnd(): void { this.push('scaleEnd'); }
  onDown(x: number, y: number): void { this.push('down'); }
  onUp(): void { this.push('up'); }
  onPointerDown(x: number, y: number): void { this.push('pointerDown'); }
  onPointerUp(): void { this.push('pointerUp'); }
}

let clock = 1000;
function ev(action: number, x: number, y: number, dt: number): MotionEvent {
  clock += dt;
  return MotionEvent.obtainSimple(clock, clock, action, x, y, 0);
}

/** 构造双指事件（ScaleGestureDetector 的判定需要 pointerCount >= 2）。 */
function ev2(action: number, x0: number, y0: number, x1: number, y1: number,
  dt: number): MotionEvent {
  clock += dt;
  const c0 = new PointerCoords();
  c0.x = x0;
  c0.y = y0;
  const c1 = new PointerCoords();
  c1.x = x1;
  c1.y = y1;
  return MotionEvent.obtainFull(clock, clock, action, 2, [0, 1], [c0, c1], 0, 1, 1, 0, 0, 0, 0);
}

async function main(): Promise<void> {
  // ---------- 1) 单击：立刻 tapUp，300ms 后 tapConfirmed ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 100, 0));
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 101, 101, 50));
    ok('single tap: tapUp fired immediately', r.log.indexOf('tapUp') >= 0);
    ok('single tap: not confirmed yet', r.log.indexOf('tapConfirmed') < 0);
    await sleep(380);
    ok('single tap: confirmed after DOUBLE_TAP_TIMEOUT', r.log.indexOf('tapConfirmed') >= 0);
    eq('single tap: no doubleTap', r.log.filter((s) => s.startsWith('doubleTap')).length, 0);
  }

  // ---------- 2) 双击：第二次 DOWN 触发 doubleTap，UP 触发 confirmed，且不产生 tapConfirmed ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 100, 0));
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 100, 100, 40));
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 102, 102, 80));   // 距上次 UP 120ms，窗口内
    ok('double tap: doubleTap fired', r.log.indexOf('doubleTap') >= 0);
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 102, 102, 40));
    ok('double tap: confirmed on UP', r.log.indexOf('doubleTapConfirmed') >= 0);
    await sleep(380);
    eq('double tap: no single tapConfirmed', r.log.indexOf('tapConfirmed'), -1);
  }

  // ---------- 3) 双击窗口外：第二次点击算新单击 ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 100, 0));
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 100, 100, 40));
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 100, 400));  // 超过 300ms
    eq('outside double-tap window: no doubleTap', r.log.indexOf('doubleTap'), -1);
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 100, 100, 40));
    eq('outside window: tapUp twice', r.log.filter((s) => s === 'tapUp').length, 2);
  }

  // ---------- 4) 长按：500ms 不移动 ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 100, 0));
    await sleep(560);
    ok('long press fired after 500ms', r.log.indexOf('longPress') >= 0);
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 100, 100, 10));
    eq('long press: no tapUp afterwards', r.log.indexOf('tapUp'), -1);
  }

  // ---------- 5) 长按前移动超过 slop：判为 scroll，不触发长按 ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 100, 0));
    g.onTouchEvent(ev(MotionEvent.ACTION_MOVE, 100, 140, 20));   // 40px > 8dp*2
    ok('move beyond slop => scroll', r.log.indexOf('scroll') >= 0);
    await sleep(560);
    eq('scroll cancels long press', r.log.indexOf('longPress'), -1);
    // AOSP 符号：distanceY = 上一位置 - 当前位置 = 100 - 140 = -40（手指向下 => 负）
    if (r.scrolls.length > 0) {
      eq('scroll dy sign (AOSP: last - current)', r.scrolls[0][1], -40);
      eq('scroll totalY', r.scrolls[0][3], 40);
    } else {
      fails.push('scroll record missing');
    }
  }

  // ---------- 6) fling：快速上滑后抬起 ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 400, 0));
    g.onTouchEvent(ev(MotionEvent.ACTION_MOVE, 100, 350, 10));
    g.onTouchEvent(ev(MotionEvent.ACTION_MOVE, 100, 300, 10));
    g.onTouchEvent(ev(MotionEvent.ACTION_MOVE, 100, 250, 10));
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 100, 250, 10));
    ok('fast swipe triggers fling', r.log.indexOf('fling') >= 0);
    if (r.flingSpeed.length > 0) {
      ok('fling speed above 50dp/s', r.flingSpeed[0] > 50);
      ok('fling speed below 8000dp/s', r.flingSpeed[0] < 8000);
    } else {
      fails.push('fling speed not recorded');
    }
    eq('fling: no tapUp', r.log.indexOf('tapUp'), -1);
  }

  // ---------- 7) 双指缩放 ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 300, 0));
    // 双指按下：间距 200
    g.onTouchEvent(ev2(MotionEvent.ACTION_POINTER_DOWN, 100, 300, 300, 300, 10));
    // 间距拉到 400（远超 spanSlop = 2*8dp）→ onScaleBegin
    g.onTouchEvent(ev2(MotionEvent.ACTION_MOVE, 0, 300, 400, 300, 20));
    ok('scale begin fired', r.log.indexOf('scaleBegin') >= 0);
    g.onTouchEvent(ev2(MotionEvent.ACTION_MOVE, 0, 300, 500, 300, 20));
    ok('scale fired', r.log.indexOf('scale') >= 0);
    if (r.scaleFactors.length > 0) {
      ok('scale factor > 1 when spreading', r.scaleFactors[r.scaleFactors.length - 1] > 1);
    } else {
      fails.push('scale factor not recorded');
    }
    g.onTouchEvent(ev2(MotionEvent.ACTION_UP, 0, 300, 500, 300, 10));
    ok('scale end fired', r.log.indexOf('scaleEnd') >= 0);
  }

  // ---------- 8) isDown 状态 ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    eq('isDown before DOWN', g.isDown(), false);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 100, 100, 0));
    eq('isDown after DOWN', g.isDown(), true);
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 100, 100, 40));
    eq('isDown after UP', g.isDown(), false);
  }

  // ---------- 9) 慢速单击（超过 100ms 仍在 slop 内且未滚动 → 仍触发 onSingleTapUp） ----------
  {
    const r = new Recorder();
    const g = new GestureRecognizer(r);
    g.onTouchEvent(ev(MotionEvent.ACTION_DOWN, 120, 120, 0));
    g.onTouchEvent(ev(MotionEvent.ACTION_UP, 121, 121, 180));
    ok('slow tap 180ms fires tapUp', r.log.indexOf('tapUp') >= 0);
  }

  console.log(`PASS ${pass}  FAIL ${fails.length}`);
  for (const f of fails) console.log('  x ' + f);
  process.exit(fails.length === 0 ? 0 : 1);
}

main();
