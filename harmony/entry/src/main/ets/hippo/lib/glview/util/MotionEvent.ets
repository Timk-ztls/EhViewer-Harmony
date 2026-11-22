/*
 * Copyright (C) 2007 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { Matrix } from './Matrix';

/**
 * `android.view.MotionEvent` 的 ArkTS 等价实现（只含 glview/glgallery 实耗的子集）。
 *
 * 为什么需要它：`glgallery` 的手势层（`GestureRecognizer`/`DownUpDetector`/`GalleryView`/
 * `ImageView`）全部以 `MotionEvent` 为输入，5 个类共 30+ 处引用；直接改签名成 ArkUI
 * `TouchEvent` 会让 `Fling`/`GestureDetector` 的移植无法逐行对照，且 ArkUI 的
 * `TouchEvent` 不可 copy（`GestureRecognizer` 需要 `MotionEvent.obtain` 复制事件 +
 * 合成 `ACTION_CANCEL`）。所以保留同名同义的值对象。
 *
 * 平台胶水在 `GLRootView`：ArkUI `TouchEvent`（vp 坐标）→ 本类（px 坐标），一次性转换。
 *
 * 语义对齐点：
 * - `action` 低 8 位是动作类型，高 8 位是触点索引（`getActionMasked`/`getActionIndex`）
 * - 坐标按触点索引取，`getX()`/`getY()` 等价 `getX(0)`/`getY(0)`
 * - `obtain` 系列是"复用池"语义的替身；ArkTS 侧由 GC 管理，因此 `recycle()` 只置标记，
 *   重复使用同一对象会抛错（与 Android 的 IllegalStateException 对齐）
 */
export class PointerCoords {
  x: number = 0;
  y: number = 0;
  pressure: number = 0;
  size: number = 0;
  touchMajor: number = 0;
  touchMinor: number = 0;
  toolMajor: number = 0;
  toolMinor: number = 0;
  /** 朝向（弧度），MotionEventHelper.transformAngle 会改写它。 */
  orientation: number = 0;
}

export class MotionEvent {
  static readonly ACTION_MASK: number = 0xFF;
  static readonly ACTION_DOWN: number = 0;
  static readonly ACTION_UP: number = 1;
  static readonly ACTION_MOVE: number = 2;
  static readonly ACTION_CANCEL: number = 3;
  static readonly ACTION_OUTSIDE: number = 4;
  static readonly ACTION_POINTER_DOWN: number = 5;
  static readonly ACTION_POINTER_UP: number = 6;
  static readonly ACTION_HOVER_MOVE: number = 7;
  static readonly ACTION_SCROLL: number = 8;

  static readonly ACTION_POINTER_INDEX_MASK: number = 0xFF00;
  static readonly ACTION_POINTER_INDEX_SHIFT: number = 8;

  static readonly FLAG_WINDOW_IS_OBSCURED: number = 0x1;

  downTime: number = 0;
  eventTime: number = 0;
  action: number = 0;
  metaState: number = 0;
  deviceId: number = 0;
  edgeFlags: number = 0;
  source: number = 0;
  flags: number = 0;
  xPrecision: number = 1.0;
  yPrecision: number = 1.0;

  private pointerIdsArr: number[] = [0];
  private coordsArr: PointerCoords[] = [new PointerCoords()];
  private recycled: boolean = false;

  /**
   * 上游 6 处 `MotionEvent.obtain(...)` 调用的统一入口。两种形态：
   * 1) `obtain(downTime, eventTime, action, x, y, metaState)` —— 单触点
   * 2) `obtain(downTime, eventTime, action, pointerCount, pointerIds, coords, metaState,
   *            xPrecision, yPrecision, deviceId, edgeFlags, source, flags)` —— 多触点（MotionEventHelper 用）
   *
   * ArkTS 无重载，用两种静态工厂表达，调用点语义不变。
   */
  static obtainSimple(downTime: number, eventTime: number, action: number, x: number, y: number,
    metaState: number): MotionEvent {
    const e = new MotionEvent();
    e.downTime = downTime;
    e.eventTime = eventTime;
    e.action = action;
    e.metaState = metaState;
    const c = new PointerCoords();
    c.x = x;
    c.y = y;
    e.coordsArr = [c];
    e.pointerIdsArr = [0];
    return e;
  }

  static obtainFull(downTime: number, eventTime: number, action: number, pointerCount: number,
    pointerIds: number[], pointerCoords: PointerCoords[], metaState: number, xPrecision: number,
    yPrecision: number, deviceId: number, edgeFlags: number, source: number,
    flags: number): MotionEvent {
    const e = new MotionEvent();
    e.downTime = downTime;
    e.eventTime = eventTime;
    e.action = action;
    e.metaState = metaState;
    e.xPrecision = xPrecision;
    e.yPrecision = yPrecision;
    e.deviceId = deviceId;
    e.edgeFlags = edgeFlags;
    e.source = source;
    e.flags = flags;
    e.pointerIdsArr = new Array<number>(pointerCount);
    e.coordsArr = new Array<PointerCoords>(pointerCount);
    for (let i = 0; i < pointerCount; i++) {
      e.pointerIdsArr[i] = pointerIds[i];
      const src = pointerCoords[i];
      const dst = new PointerCoords();
      dst.x = src.x;
      dst.y = src.y;
      dst.pressure = src.pressure;
      dst.size = src.size;
      dst.touchMajor = src.touchMajor;
      dst.touchMinor = src.touchMinor;
      dst.toolMajor = src.toolMajor;
      dst.toolMinor = src.toolMinor;
      dst.orientation = src.orientation;
      e.coordsArr[i] = dst;
    }
    return e;
  }

  /** 拷贝构造（`MotionEvent.obtain(e)`），供 `transform` 使用。 */
  static obtainCopy(other: MotionEvent): MotionEvent {
    const e = new MotionEvent();
    e.downTime = other.downTime;
    e.eventTime = other.eventTime;
    e.action = other.action;
    e.metaState = other.metaState;
    e.xPrecision = other.xPrecision;
    e.yPrecision = other.yPrecision;
    e.deviceId = other.deviceId;
    e.edgeFlags = other.edgeFlags;
    e.source = other.source;
    e.flags = other.flags;
    const n = other.pointerIdsArr.length;
    e.pointerIdsArr = new Array<number>(n);
    e.coordsArr = new Array<PointerCoords>(n);
    for (let i = 0; i < n; i++) {
      e.pointerIdsArr[i] = other.pointerIdsArr[i];
      const src = other.coordsArr[i];
      const dst = new PointerCoords();
      dst.x = src.x;
      dst.y = src.y;
      dst.pressure = src.pressure;
      dst.size = src.size;
      dst.touchMajor = src.touchMajor;
      dst.touchMinor = src.touchMinor;
      dst.toolMajor = src.toolMajor;
      dst.toolMinor = src.toolMinor;
      dst.orientation = src.orientation;
      e.coordsArr[i] = dst;
    }
    return e;
  }

  getDownTime(): number {
    return this.downTime;
  }

  getEventTime(): number {
    return this.eventTime;
  }

  /** 含触点索引的完整 action。 */
  getAction(): number {
    return this.action;
  }

  /** 只保留动作类型（低 8 位）。DownUpDetector 的 switch 走这里。 */
  getActionMasked(): number {
    return this.action & MotionEvent.ACTION_MASK;
  }

  /** 动作涉及的触点索引（高 8 位）。 */
  getActionIndex(): number {
    return (this.action & MotionEvent.ACTION_POINTER_INDEX_MASK)
      >> MotionEvent.ACTION_POINTER_INDEX_SHIFT;
  }

  getPointerCount(): number {
    return this.coordsArr.length;
  }

  getPointerId(pointerIndex: number): number {
    if (pointerIndex < 0 || pointerIndex >= this.pointerIdsArr.length) {
      throw new Error(`pointerIndex out of range: ${pointerIndex}`);
    }
    return this.pointerIdsArr[pointerIndex];
  }

  getX(): number {
    return this.coordsArr[0].x;
  }

  getY(): number {
    return this.coordsArr[0].y;
  }

  getXAt(pointerIndex: number): number {
    if (pointerIndex < 0 || pointerIndex >= this.coordsArr.length) {
      throw new Error(`pointerIndex out of range: ${pointerIndex}`);
    }
    return this.coordsArr[pointerIndex].x;
  }

  getYAt(pointerIndex: number): number {
    if (pointerIndex < 0 || pointerIndex >= this.coordsArr.length) {
      throw new Error(`pointerIndex out of range: ${pointerIndex}`);
    }
    return this.coordsArr[pointerIndex].y;
  }

  /** 把第 i 个触点坐标写入 out（上游 `getPointerCoords(i, out)`）。 */
  getPointerCoords(pointerIndex: number, out: PointerCoords): void {
    if (pointerIndex < 0 || pointerIndex >= this.coordsArr.length) {
      throw new Error(`pointerIndex out of range: ${pointerIndex}`);
    }
    const src = this.coordsArr[pointerIndex];
    out.x = src.x;
    out.y = src.y;
    out.pressure = src.pressure;
    out.size = src.size;
    out.touchMajor = src.touchMajor;
    out.touchMinor = src.touchMinor;
    out.toolMajor = src.toolMajor;
    out.toolMinor = src.toolMinor;
    out.orientation = src.orientation;
  }

  /** 直接取内部触点（只读用途，避免每帧分配）。 */
  peekCoords(pointerIndex: number): PointerCoords {
    return this.coordsArr[pointerIndex];
  }

  getMetaState(): number {
    return this.metaState;
  }

  getXPrecision(): number {
    return this.xPrecision;
  }

  getYPrecision(): number {
    return this.yPrecision;
  }

  getDeviceId(): number {
    return this.deviceId;
  }

  getEdgeFlags(): number {
    return this.edgeFlags;
  }

  getSource(): number {
    return this.source;
  }

  getFlags(): number {
    return this.flags;
  }

  isRecycled(): boolean {
    return this.recycled;
  }

  /** Android 的 recycle 只是归还到池；ArkTS 由 GC 回收，这里保留调用点 + 使用检查。 */
  recycle(): void {
    this.recycled = true;
  }

  /**
   * 改变事件坐标原点：所有触点整体平移 (dx, dy)。
   * 上游 `GLView.dispatchTouchEvent(...)` 用它把坐标换算到子视图局部坐标系
   * （进入子视图前 `offsetLocation(-left, -top)`，返回后原样加回）。
   */
  offsetLocation(dx: number, dy: number): void {
    for (let i = 0; i < this.coordsArr.length; i++) {
      this.coordsArr[i].x += dx;
      this.coordsArr[i].y += dy;
    }
  }

  /** 改写动作（`GLView` 在按下新目标时给旧目标合成 `ACTION_CANCEL` 用）。 */
  setAction(action: number): void {
    this.action = action;
  }

  /** 原地仿射变换所有触点（等价 `MotionEvent.transform(Matrix)`，只对 x/y 生效）。 */
  transform(m: Matrix): void {
    const n = this.coordsArr.length;
    const pts: number[] = new Array<number>(n * 2);
    for (let i = 0; i < n; i++) {
      pts[i * 2] = this.coordsArr[i].x;
      pts[i * 2 + 1] = this.coordsArr[i].y;
    }
    m.mapPoints(pts);
    for (let i = 0; i < n; i++) {
      this.coordsArr[i].x = pts[i * 2];
      this.coordsArr[i].y = pts[i * 2 + 1];
    }
  }

  toString(): string {
    return `MotionEvent(action=${this.getActionMasked()}, pointers=${this.coordsArr.length}, `
      + `x=${this.getX()}, y=${this.getY()})`;
  }
}
