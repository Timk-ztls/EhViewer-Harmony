/*
 * TouchEventBridge 单测（Stage C Track P5）：
 *   验证 ArkUI TouchEvent (vp, ns) 到 MotionEvent (px, ms) 转换，含多指缩放与 missing-changedTouch 兜底。
 */

import {
  ARK_TOUCH_CANCEL,
  ARK_TOUCH_DOWN,
  ARK_TOUCH_MOVE,
  ARK_TOUCH_UP,
  ArkTouchEventLike,
  TouchEventBridge
} from '../../main/ets/hippo/lib/glview/view/TouchEventBridge';
import { MotionEvent } from '../../main/ets/hippo/lib/glview/util/MotionEvent';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}: got ${g} want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(name);
  }
}

// 1) 单指 Down -> Move -> Up（含 vp->px、ns->ms 换算与 downTime 延续）
{
  const bridge = new TouchEventBridge();
  const downEv: ArkTouchEventLike = {
    type: ARK_TOUCH_DOWN,
    timestamp: 1_500_000_000, // 1500ms in ns
    touches: [{ id: 0, x: 100, y: 200 }],
    changedTouches: [{ id: 0, x: 100, y: 200 }]
  };
  const meDown = bridge.toMotionEvent(downEv, 3.0);
  ok('single down non-null', meDown !== null);
  eq('single down actionMasked', meDown!.getActionMasked(), MotionEvent.ACTION_DOWN);
  eq('single down x px', meDown!.getX(), 300);
  eq('single down y px', meDown!.getY(), 600);
  eq('single down time ms', meDown!.getEventTime(), 1500);
  eq('single down downTime ms', meDown!.getDownTime(), 1500);

  const moveEv: ArkTouchEventLike = {
    type: ARK_TOUCH_MOVE,
    timestamp: 1_550_000_000,
    touches: [{ id: 0, x: 120, y: 210 }],
    changedTouches: [{ id: 0, x: 120, y: 210 }]
  };
  const meMove = bridge.toMotionEvent(moveEv, 3.0);
  eq('single move actionMasked', meMove!.getActionMasked(), MotionEvent.ACTION_MOVE);
  eq('single move keeps downTime', meMove!.getDownTime(), 1500);
  eq('single move x px', meMove!.getX(), 360);

  const upEv: ArkTouchEventLike = {
    type: ARK_TOUCH_UP,
    timestamp: 1_600_000_000,
    touches: [],
    changedTouches: [{ id: 0, x: 120, y: 210 }]
  };
  const meUp = bridge.toMotionEvent(upEv, 3.0);
  eq('single up empty touches uses changedTouches', meUp!.getPointerCount(), 1);
  eq('single up actionMasked', meUp!.getActionMasked(), MotionEvent.ACTION_UP);
  eq('single up keeps downTime', meUp!.getDownTime(), 1500);

  // 下一手势 downTime 重置
  const nextDown: ArkTouchEventLike = {
    type: ARK_TOUCH_DOWN,
    timestamp: 2_000_000_000,
    touches: [{ id: 0, x: 10, y: 20 }],
    changedTouches: [{ id: 0, x: 10, y: 20 }]
  };
  const meNext = bridge.toMotionEvent(nextDown, 2.0);
  eq('next gesture new downTime', meNext!.getDownTime(), 2000);
}

// 2) 多指捏合 POINTER_DOWN / MOVE / POINTER_UP（含 Up 时 touches 仅剩 1 指场景）
{
  const bridge = new TouchEventBridge();
  bridge.toMotionEvent({
    type: ARK_TOUCH_DOWN,
    timestamp: 1000,
    touches: [{ id: 10, x: 50, y: 100 }],
    changedTouches: [{ id: 10, x: 50, y: 100 }]
  }, 2.0);

  const p2Down = bridge.toMotionEvent({
    type: ARK_TOUCH_DOWN,
    timestamp: 1020,
    touches: [{ id: 10, x: 50, y: 100 }, { id: 20, x: 150, y: 300 }],
    changedTouches: [{ id: 20, x: 150, y: 300 }]
  }, 2.0);
  ok('pointer2 down non-null', p2Down !== null);
  eq('pointer2 down masked', p2Down!.getActionMasked(), MotionEvent.ACTION_POINTER_DOWN);
  eq('pointer2 down index', p2Down!.getActionIndex(), 1);
  eq('pointer2 count', p2Down!.getPointerCount(), 2);
  eq('pointer2 id[1]', p2Down!.getPointerId(1), 20);
  eq('pointer2 x[1]', p2Down!.getXAt(1), 300);

  // ArkUI 在第二指抬起时 touches 只剩主指，changedTouches 含抬起的第二指
  const p2Up = bridge.toMotionEvent({
    type: ARK_TOUCH_UP,
    timestamp: 1060,
    touches: [{ id: 10, x: 60, y: 110 }],
    changedTouches: [{ id: 20, x: 160, y: 320 }]
  }, 2.0);
  eq('pointer2 up masked', p2Up!.getActionMasked(), MotionEvent.ACTION_POINTER_UP);
  eq('pointer2 up count restored to 2', p2Up!.getPointerCount(), 2);
  eq('pointer2 up index', p2Up!.getActionIndex(), 1);
  eq('pointer2 up x[1]', p2Up!.getXAt(1), 320);

  const cancelEv = bridge.toMotionEvent({
    type: ARK_TOUCH_CANCEL,
    timestamp: 1080,
    touches: [{ id: 10, x: 60, y: 110 }],
    changedTouches: [{ id: 10, x: 60, y: 110 }]
  }, 2.0);
  eq('cancel masked', cancelEv!.getActionMasked(), MotionEvent.ACTION_CANCEL);
}

// 3) 空触点兜底返回 null
{
  const bridge = new TouchEventBridge();
  const empty = bridge.toMotionEvent({
    type: ARK_TOUCH_MOVE,
    timestamp: 500,
    touches: [],
    changedTouches: []
  }, 1.0);
  eq('empty touches returns null', empty, null);
}

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
