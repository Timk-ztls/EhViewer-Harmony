/*
 * ArkUI TouchEvent (vp, ns) → MotionEvent (px, ms) 桥接器（Stage C Track P5 新增）。
 *
 * 将 ArkUI XComponent.onTouch 回调转换为 GestureRecognizer / GalleryView 可消费的
 * Android 语义 MotionEvent，支持单指按压/移动/抬起/取消与双指缩放 ACTION_POINTER_DOWN/UP。
 */

import { MotionEvent, PointerCoords } from '../util/MotionEvent';

export const ARK_TOUCH_DOWN: number = 0;
export const ARK_TOUCH_UP: number = 1;
export const ARK_TOUCH_MOVE: number = 2;
export const ARK_TOUCH_CANCEL: number = 3;

export interface ArkTouchPoint {
  id: number;
  x: number;
  y: number;
}

export interface ArkTouchEventLike {
  type: number;
  timestamp: number;
  touches: ArkTouchPoint[];
  changedTouches: ArkTouchPoint[];
}

export class TouchEventBridge {
  private downTimeMs: number = 0;

  reset(): void {
    this.downTimeMs = 0;
  }

  toMotionEvent(ev: ArkTouchEventLike, vpToPx: number): MotionEvent | null {
    const scale: number = vpToPx > 0 ? vpToPx : 1.0;
    const rawTs: number = ev.timestamp;
    const eventTimeMs: number = rawTs >= 10_000_000 ? Math.trunc(rawTs / 1000000) : Math.trunc(rawTs);

    const activeTouches: ArkTouchPoint[] = [];
    for (let i = 0; i < ev.touches.length; i++) {
      activeTouches.push(ev.touches[i]);
    }
    const changed: ArkTouchPoint | null = ev.changedTouches.length > 0 ? ev.changedTouches[0] : null;
    if (activeTouches.length === 0 && changed !== null) {
      activeTouches.push(changed);
    }
    if (activeTouches.length === 0) {
      return null;
    }

    let actionIndex: number = 0;
    if (changed !== null) {
      let foundIndex: number = -1;
      for (let i = 0; i < activeTouches.length; i++) {
        if (activeTouches[i].id === changed.id) {
          foundIndex = i;
          break;
        }
      }
      if (foundIndex >= 0) {
        actionIndex = foundIndex;
      } else if (ev.type === ARK_TOUCH_UP || ev.type === ARK_TOUCH_DOWN) {
        // ArkUI Up 时 changedTouch 可能已不在 touches 列表里：补回末尾以保留 pointerCount=2 语义
        actionIndex = activeTouches.length;
        activeTouches.push(changed);
      }
    }

    let maskedAction: number;
    if (ev.type === ARK_TOUCH_DOWN) {
      if (activeTouches.length <= 1) {
        this.downTimeMs = eventTimeMs;
        maskedAction = MotionEvent.ACTION_DOWN;
      } else {
        maskedAction = MotionEvent.ACTION_POINTER_DOWN |
          ((actionIndex & 0xFF) << MotionEvent.ACTION_POINTER_INDEX_SHIFT);
      }
    } else if (ev.type === ARK_TOUCH_UP) {
      if (activeTouches.length <= 1) {
        maskedAction = MotionEvent.ACTION_UP;
      } else {
        maskedAction = MotionEvent.ACTION_POINTER_UP |
          ((actionIndex & 0xFF) << MotionEvent.ACTION_POINTER_INDEX_SHIFT);
      }
    } else if (ev.type === ARK_TOUCH_CANCEL) {
      maskedAction = MotionEvent.ACTION_CANCEL;
    } else {
      maskedAction = MotionEvent.ACTION_MOVE;
    }

    const downTime: number = this.downTimeMs > 0 ? this.downTimeMs : eventTimeMs;
    if (maskedAction === MotionEvent.ACTION_UP || maskedAction === MotionEvent.ACTION_CANCEL) {
      this.downTimeMs = 0;
    }

    const count: number = activeTouches.length;
    if (count === 1) {
      const p: ArkTouchPoint = activeTouches[0];
      return MotionEvent.obtainSimple(downTime, eventTimeMs, maskedAction, p.x * scale, p.y * scale, 0);
    }

    const pointerIds: number[] = new Array<number>(count);
    const coords: PointerCoords[] = new Array<PointerCoords>(count);
    for (let i = 0; i < count; i++) {
      const p: ArkTouchPoint = activeTouches[i];
      pointerIds[i] = p.id;
      const pc: PointerCoords = new PointerCoords();
      pc.x = p.x * scale;
      pc.y = p.y * scale;
      coords[i] = pc;
    }
    return MotionEvent.obtainFull(downTime, eventTimeMs, maskedAction, count,
      pointerIds, coords, 0, 1.0, 1.0, 0, 0, 0, 0);
  }
}
