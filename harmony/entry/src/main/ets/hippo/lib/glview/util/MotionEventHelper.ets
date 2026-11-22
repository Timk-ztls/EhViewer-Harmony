/*
 * Copyright (C) 2012 The Android Open Source Project
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
import { ApiHelper } from './ApiHelper';
import { Matrix } from './Matrix';
import { MotionEvent, PointerCoords } from './MotionEvent';

/**
 * `com.hippo.lib.glview.util.MotionEventHelper` 的 ArkTS 等价实现。
 *
 * 上游有两套实现（新 API 走 `MotionEvent.transform`，老 API 手工逐触点变换）。
 * 本项目 `MotionEvent` 是自实现的值对象（见 `MotionEvent.ets`），等价层本来就
 * 直接改写自身坐标，因此两条分支合并为一条 —— 但**变换算法逐行保留**：
 * 触点坐标用 `mapPoints`，朝向角用 `transformAngle`（这个函数是从
 * `frameworks/base/libs/input/Input.cpp` 抄来的，浮点分支必须逐字一致，
 * 否则 `ImageView` 的旋转手势会有 0.5° 级别的角度跳变）。
 */
export class MotionEventHelper {
  /**
   * 变换事件所有触点坐标与朝向。
   *
   * 与上游的差异（1 条）：上游返回**新的** `MotionEvent`（`MotionEvent.obtain(e)` 后
   * 原地 `transform`），这里同样返回新对象（`MotionEvent.obtainCopy`），调用点语义不变。
   */
  static transformEvent(e: MotionEvent, m: Matrix): MotionEvent {
    if (ApiHelper.HAS_MOTION_EVENT_TRANSFORM) {
      return MotionEventHelper.transformEventNew(e, m);
    }
    return MotionEventHelper.transformEventOld(e, m);
  }

  /** 对应上游 `transformEventNew`：拷贝后原地变换。 */
  private static transformEventNew(e: MotionEvent, m: Matrix): MotionEvent {
    const newEvent = MotionEvent.obtainCopy(e);
    newEvent.transform(m);
    return newEvent;
  }

  /** 对应上游 `transformEventOld`：逐触点取出坐标 → mapPoints → 写回，并变换朝向。 */
  private static transformEventOld(e: MotionEvent, m: Matrix): MotionEvent {
    const downTime = e.getDownTime();
    const eventTime = e.getEventTime();
    const action = e.getAction();
    const pointerCount = e.getPointerCount();
    const pointerIds = MotionEventHelper.getPointerIds(e);
    const pointerCoords = MotionEventHelper.getPointerCoords(e);
    const metaState = e.getMetaState();
    const xPrecision = e.getXPrecision();
    const yPrecision = e.getYPrecision();
    const deviceId = e.getDeviceId();
    const edgeFlags = e.getEdgeFlags();
    const source = e.getSource();
    const flags = e.getFlags();

    const xy: number[] = new Array<number>(pointerCoords.length * 2);
    for (let i = 0; i < pointerCount; i++) {
      xy[2 * i] = pointerCoords[i].x;
      xy[2 * i + 1] = pointerCoords[i].y;
    }
    m.mapPoints(xy);
    for (let i = 0; i < pointerCount; i++) {
      pointerCoords[i].x = xy[2 * i];
      pointerCoords[i].y = xy[2 * i + 1];
      pointerCoords[i].orientation = MotionEventHelper.transformAngle(m, pointerCoords[i].orientation);
    }

    return MotionEvent.obtainFull(downTime, eventTime, action, pointerCount, pointerIds,
      pointerCoords, metaState, xPrecision, yPrecision, deviceId, edgeFlags, source, flags);
  }

  private static getPointerIds(e: MotionEvent): number[] {
    const n = e.getPointerCount();
    const r: number[] = new Array<number>(n);
    for (let i = 0; i < n; i++) {
      r[i] = e.getPointerId(i);
    }
    return r;
  }

  private static getPointerCoords(e: MotionEvent): PointerCoords[] {
    const n = e.getPointerCount();
    const r: PointerCoords[] = new Array<PointerCoords>(n);
    for (let i = 0; i < n; i++) {
      r[i] = new PointerCoords();
      e.getPointerCoords(i, r[i]);
    }
    return r;
  }

  /**
   * 与 Android 框架 Input.cpp 完全一致的朝向变换：
   * 把"自竖直方向顺时针 angle 弧度"的向量做仿射变换后反解角度，
   * 并归一到 (-π/2, π/2]。
   */
  private static transformAngle(m: Matrix, angleRadians: number): number {
    const v: number[] = new Array<number>(2);
    v[0] = Math.sin(angleRadians);
    v[1] = -Math.cos(angleRadians);
    // mapVectors：只做线性部分（忽略平移），AOSP 的 Matrix.mapVectors 语义
    MotionEventHelper.mapVectors(m, v);

    let result = Math.atan2(v[0], -v[1]);
    if (result < -Math.PI / 2) {
      result += Math.PI;
    } else if (result > Math.PI / 2) {
      result -= Math.PI;
    }
    return result;
  }

  /** `Matrix.mapVectors`：只用 2x2 线性部分变换向量（不含 MTRANS_*）。 */
  private static mapVectors(m: Matrix, vec: number[]): void {
    const values: number[] = new Array<number>(9);
    m.getValues(values);
    const x = vec[0];
    const y = vec[1];
    vec[0] = values[0] * x + values[1] * y;
    vec[1] = values[3] * x + values[4] * y;
  }
}
