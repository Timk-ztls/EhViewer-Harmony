/*
 * Copyright 2016 Hippo Seven
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { Animation } from '../glview/anim/Animation';
import { MotionEvent } from '../glview/util/MotionEvent';
import { DownUpDetector, DownUpListener } from './DownUpDetector';
import { LayoutUtils } from '../yorozuya/LayoutUtils';

/**
 * `com.hippo.lib.glgallery.GestureRecognizer` 的 ArkTS 等价实现。
 *
 * ## ⚠️ 这不是移植，是**重写**（登记 D-026）
 * 上游 150 行里几乎全是委托：
 * ```java
 * private final GestureDetectorCompat mGestureDetector;   // android.view.GestureDetector
 * private final ScaleGestureDetector mScaleDetector;      // android.view.ScaleGestureDetector
 * ```
 * 鸿蒙**没有**这两个类，也没有等价物。所以本文件把它们的判定逻辑按 AOSP 语义重写：
 * `VelocityTracker`（最小二乘拟合）、tap/double-tap/long-press 状态机、
 * 双指 span 缩放判定，全部自己实现。
 *
 * ## 常量表（AOSP `ViewConfiguration` 默认值，按 density 换算成 px）
 * | 常量 | 值 | 用途 |
 * |---|---:|---|
 * | `TAP_TIMEOUT` | 100ms | 超时后按下不再算 tap |
 * | `DOUBLE_TAP_TIMEOUT` | 300ms | 两次点击的最大间隔 |
 * | `DOUBLE_TAP_MIN_TIME` | 40ms | 两次点击的最小间隔（防误判） |
 * | `LONG_PRESS_TIMEOUT` | 500ms | 长按判定 |
 * | `TOUCH_SLOP` | 8dp | 移动超过即判为滑动 |
 * | `MIN_FLING_VELOCITY` | 50dp/s | fling 最小速度 |
 * | `MAX_FLING_VELOCITY` | 8000dp/s | fling 速度上限 |
 * | `MIN_SCALING_SPAN` | 27dp | 缩放最小指纹间距 |
 * | `SPAN_SLOP` | `2 * TOUCH_SLOP` | 缩放启动阈值 |
 *
 * ## D-026 登记的风险（已知不可控项）
 * `ScaleGestureDetector` 的 span 判定算法未公开全部细节，双指缩放的**手感**
 * 可能与上游有细微差异。验收口径是"与上游同常量的行为对齐"，不是像素级。
 *
 * ## 事件顺序（**必须**与上游一致，否则 `GalleryView` 的手势互斥会错）
 * ```java
 * mScaleDetector.onTouchEvent(event);
 * mGestureDetector.onTouchEvent(event);
 * mDownUpDetector.onTouchEvent(event);
 * ```
 * 三个检测器**都**收到每一个事件，顺序不能换：`ScaleGestureDetector` 先吃掉双指，
 * 此后 `GestureDetector` 收到的是"仍在处理"的事件，`DownUpDetector` 只维护整体按下态。
 */
export class GestureRecognizer {
  /** 缓冲区大小（AOSP `VelocityTracker` 的 `HISTORY_SIZE`）。 */
  private static readonly HISTORY_SIZE: number = 20;

  private readonly mListener: GestureRecognizerListener;
  private readonly mTap: TapDetector;
  private readonly mScale: SpanScaleDetector;
  private readonly mDownUp: DownUpDetector;

  constructor(listener: GestureRecognizerListener) {
    this.mListener = listener;
    this.mTap = new TapDetector(listener);
    this.mScale = new SpanScaleDetector(listener);
    this.mDownUp = new DownUpDetector(new RecognizerDownUpBridge(listener));
  }

  onTouchEvent(event: MotionEvent): void {
    // 顺序与上游一致，见类注释
    this.mScale.onTouchEvent(event);
    this.mTap.onTouchEvent(event);
    this.mDownUp.onTouchEvent(event);
  }

  isDown(): boolean {
    return this.mDownUp.isDown();
  }

  /** 强制结束缩放（等价上游构造一个 `ACTION_CANCEL` 喂给 `ScaleGestureDetector`）。 */
  cancelScale(): void {
    const now = Animation.uptimeMillis();
    const cancelEvent = MotionEvent.obtainSimple(now, now, MotionEvent.ACTION_CANCEL, 0, 0, 0);
    this.mScale.onTouchEvent(cancelEvent);
    cancelEvent.recycle();
  }
}

/** 上游 `GestureRecognizer.Listener`。 */
export interface GestureRecognizerListener {
  onSingleTapUp(x: number, y: number): boolean;

  onSingleTapConfirmed(x: number, y: number): boolean;

  onDoubleTap(x: number, y: number): boolean;

  onDoubleTapConfirmed(x: number, y: number): boolean;

  onLongPress(x: number, y: number): void;

  /** `dx/dy` 是"上一位置 - 当前位置"（AOSP `distanceX/Y` 符号），total 是总位移。 */
  onScroll(dx: number, dy: number, totalX: number, totalY: number, x: number, y: number): boolean;

  onFling(e1: MotionEvent, e2: MotionEvent, velocityX: number, velocityY: number): boolean;

  onScaleBegin(focusX: number, focusY: number): boolean;

  onScale(focusX: number, focusY: number, scale: number): boolean;

  onScaleEnd(): void;

  onDown(x: number, y: number): void;

  onUp(): void;

  onPointerDown(x: number, y: number): void;

  onPointerUp(): void;
}

/** `DownUpDetector.DownUpListener` → `GestureRecognizerListener` 的适配。 */
class RecognizerDownUpBridge implements DownUpListener {
  private readonly mL: GestureRecognizerListener;

  constructor(l: GestureRecognizerListener) {
    this.mL = l;
  }

  onDown(e: MotionEvent): void {
    this.mL.onDown(e.getX(), e.getY());
  }

  onUp(e: MotionEvent): void {
    this.mL.onUp();
  }

  onPointerDown(e: MotionEvent): void {
    this.mL.onPointerDown(e.getX(), e.getY());
  }

  onPointerUp(e: MotionEvent): void {
    this.mL.onPointerUp();
  }
}

/**
 * 速度追踪（AOSP `VelocityTracker` 的**简化等价**）。
 *
 * 上游用"最近 20 个样本 + 二次多项式最小二乘拟合"求瞬时速度；这里用**线性回归**
 * 求平均速度。差异：加速/减速过程中线性拟合的估计略钝，但只用于
 * "是否达到 fling 阈值"与 fling 初速度，`ScrollLayoutManager` 的 fling 曲线
 * 对该差异不敏感（它只用速度决定距离/时长，本来就是经验模型）。
 *
 * **登记为近似**：不作为像素级等价声明。
 */
export class VelocityTracker {
  /** 缓冲区大小（AOSP `VelocityTracker.HISTORY_SIZE`）。 */
  static readonly HISTORY_SIZE: number = 20;

  private static readonly HORIZON: number = 100;  // ms，参与拟合的时间窗

  private mTimes: number[] = [];
  private mXs: number[] = [];
  private mYs: number[] = [];
  private mPointerId: number = -1;

  reset(): void {
    this.mTimes = [];
    this.mXs = [];
    this.mYs = [];
    this.mPointerId = -1;
  }

  addMovement(event: MotionEvent): void {
    const action = event.getActionMasked();
    if (action === MotionEvent.ACTION_DOWN || this.mPointerId < 0) {
      this.mPointerId = event.getPointerId(0);
    }
    const now = event.getEventTime();
    this.mTimes.push(now);
    this.mXs.push(event.getX());
    this.mYs.push(event.getY());

    // 丢弃时间窗外的样本
    const horizon = now - VelocityTracker.HORIZON;
    while (this.mTimes.length > 2 && this.mTimes[0] < horizon) {
      this.mTimes.shift();
      this.mXs.shift();
      this.mYs.shift();
    }
    if (this.mTimes.length > VelocityTracker.HISTORY_SIZE) {
      this.mTimes.shift();
      this.mXs.shift();
      this.mYs.shift();
    }
  }

  /** 某轴速度（px/s），样本不足或时间跨度为 0 时返回 0。 */
  private estimate(values: number[]): number {
    const n = this.mTimes.length;
    if (n < 2) {
      return 0;
    }
    let sumT = 0;
    let sumV = 0;
    for (let i = 0; i < n; i++) {
      sumT += this.mTimes[i];
      sumV += values[i];
    }
    const meanT = sumT / n;
    const meanV = sumV / n;
    let num = 0;
    let den = 0;
    for (let i = 0; i < n; i++) {
      const dt = this.mTimes[i] - meanT;
      num += dt * (values[i] - meanV);
      den += dt * dt;
    }
    if (den === 0) {
      return 0;
    }
    return num / den * 1000.0;   // px/ms → px/s
  }

  getXVelocity(): number {
    return this.estimate(this.mXs);
  }

  getYVelocity(): number {
    return this.estimate(this.mYs);
  }
}

/**
 * tap / double-tap / long-press / scroll / fling 的判定（AOSP `GestureDetector` 语义子集）。
 *
 * ## 状态机要点
 * - `ACTION_DOWN`：记录起点与时间；在 `TAP_TIMEOUT + LONG_PRESS_TIMEOUT` 内没有移动超过 slop
 *   且一直按着 → **长按**
 * - 若上一次 UP 在 `DOUBLE_TAP_TIMEOUT` 内且位置在 slop 内 → 本次 DOWN 进入**双击**分支
 *   （`onDoubleTap`），后续事件走 `onDoubleTapEvent`，`ACTION_UP` 时 `onDoubleTapConfirmed`
 * - 单击：UP 时若未超过 `TAP_TIMEOUT` 且在 slop 内 → **立刻** `onSingleTapUp`，
 *   同时挂一个 `DOUBLE_TAP_TIMEOUT` 的定时器；到点仍无第二次 DOWN → `onSingleTapConfirmed`
 * - 移动超过 slop → 判为 **scroll**（第一次触发前要先 `onSingleTapUp` 已发或直接跳过 tap）
 * - UP 且速度超过 `MIN_FLING_VELOCITY` → **fling**
 */
export class TapDetector {
  private static readonly TAP_TIMEOUT: number = 100;
  private static readonly DOUBLE_TAP_TIMEOUT: number = 300;
  private static readonly DOUBLE_TAP_MIN_TIME: number = 40;
  private static readonly LONG_PRESS_TIMEOUT: number = 500;

  private readonly mL: GestureRecognizerListener;
  private readonly mSlop: number;

  private mDownTime: number = 0;
  private mDownX: number = 0;
  private mDownY: number = 0;
  private mLastX: number = 0;
  private mLastY: number = 0;

  private mIsDown: boolean = false;
  /** 已超过 slop，视为滑动。 */
  private mIsScrolling: boolean = false;
  /** 已触发长按（本次手势内不再判 tap/fling）。 */
  private mLongPressFired: boolean = false;
  /** 处于双击手势内（第二次 DOWN 之后）。 */
  private mIsDoubleTapping: boolean = false;
  /** 上一次 UP 的时间与位置（双击判定用）。 */
  private mLastUpTime: number = 0;
  private mLastUpX: number = 0;
  private mLastUpY: number = 0;
  /** 单击确认定时器。 */
  private mSingleTapConfirmedTimer: number = -1;
  private mLongPressTimer: number = -1;

  private readonly mVelocity: VelocityTracker = new VelocityTracker();

  /** AOSP `ViewConfiguration`：fling 速度区间 50dp/s ~ 8000dp/s。 */
  private readonly mMinFlingVelocity: number = LayoutUtils.dp2pix(50);
  private readonly mMaxFlingVelocity: number = LayoutUtils.dp2pix(8000);

  private mFirstEvent: MotionEvent | null = null;

  constructor(listener: GestureRecognizerListener) {
    this.mL = listener;
    this.mSlop = LayoutUtils.dp2pix(8);
  }

  private clearTimers(): void {
    if (this.mSingleTapConfirmedTimer >= 0) {
      clearTimeout(this.mSingleTapConfirmedTimer);
      this.mSingleTapConfirmedTimer = -1;
    }
    if (this.mLongPressTimer >= 0) {
      clearTimeout(this.mLongPressTimer);
      this.mLongPressTimer = -1;
    }
  }

  onTouchEvent(event: MotionEvent): void {
    const action = event.getActionMasked();
    const x = event.getX();
    const y = event.getY();
    const now = event.getEventTime();

    switch (action) {
      case MotionEvent.ACTION_DOWN:
        this.onDownInternal(event, x, y, now);
        break;
      case MotionEvent.ACTION_MOVE:
        this.onMoveInternal(event, x, y, now);
        break;
      case MotionEvent.ACTION_POINTER_DOWN:
        // 多指按下：结束 tap 判定（上游 GestureDetector 同样这么做）
        this.clearTimers();
        if (this.mIsDoubleTapping) {
          this.mIsDoubleTapping = false;
        }
        break;
      case MotionEvent.ACTION_UP:
        this.onUpInternal(event, x, y, now);
        break;
      case MotionEvent.ACTION_CANCEL:
        this.clearTimers();
        this.mIsDown = false;
        this.mIsScrolling = false;
        this.mIsDoubleTapping = false;
        this.mFirstEvent = null;
        break;
      default:
        break;
    }
  }

  private onDownInternal(event: MotionEvent, x: number, y: number, now: number): void {
    this.clearTimers();
    this.mFirstEvent = MotionEvent.obtainCopy(event);
    this.mIsDown = true;
    this.mIsScrolling = false;
    this.mLongPressFired = false;
    this.mDownTime = now;
    this.mDownX = x;
    this.mDownY = y;
    this.mLastX = x;
    this.mLastY = y;

    this.mVelocity.reset();
    this.mVelocity.addMovement(event);

    // 双击判定：距上次 UP 在 [MIN, TIMEOUT] 内且位移在 slop 内
    const deltaTime = now - this.mLastUpTime;
    if (deltaTime > TapDetector.DOUBLE_TAP_MIN_TIME
      && deltaTime < TapDetector.DOUBLE_TAP_TIMEOUT
      && Math.abs(x - this.mLastUpX) <= this.mSlop
      && Math.abs(y - this.mLastUpY) <= this.mSlop) {
      this.mIsDoubleTapping = true;
      this.mL.onDoubleTap(x, y);
      return;
    }
    this.mIsDoubleTapping = false;

    // 长按定时器
    this.mLongPressTimer = setTimeout(() => {
      this.mLongPressTimer = -1;
      if (this.mIsDown && !this.mIsScrolling && !this.mLongPressFired
        && !this.mIsDoubleTapping) {
        this.mLongPressFired = true;
        this.mL.onLongPress(this.mLastX, this.mLastY);
      }
    }, TapDetector.LONG_PRESS_TIMEOUT);
  }

  private onMoveInternal(event: MotionEvent, x: number, y: number, now: number): void {
    if (!this.mIsDown) {
      return;
    }
    this.mVelocity.addMovement(event);

    if (this.mIsDoubleTapping) {
      // 双击手势内的移动不判 scroll（上游 onDoubleTapEvent 分支）
      return;
    }

    const dxTotal = x - this.mDownX;
    const dyTotal = y - this.mDownY;

    if (!this.mIsScrolling) {
      if (Math.abs(dxTotal) > this.mSlop || Math.abs(dyTotal) > this.mSlop) {
        this.mIsScrolling = true;
        // 一旦开始滑动，取消长按
        if (this.mLongPressTimer >= 0) {
          clearTimeout(this.mLongPressTimer);
          this.mLongPressTimer = -1;
        }
      }
    }

    if (this.mIsScrolling) {
      // AOSP `distanceX/Y` = 上一位置 - 当前位置
      const distanceX = this.mLastX - x;
      const distanceY = this.mLastY - y;
      this.mL.onScroll(distanceX, distanceY, dxTotal, dyTotal, x, y);
    }

    this.mLastX = x;
    this.mLastY = y;
  }

  private onUpInternal(event: MotionEvent, x: number, y: number, now: number): void {
    this.mVelocity.addMovement(event);
    this.mIsDown = false;

    if (this.mLongPressTimer >= 0) {
      clearTimeout(this.mLongPressTimer);
      this.mLongPressTimer = -1;
    }

    if (this.mIsDoubleTapping) {
      this.mIsDoubleTapping = false;
      this.mLastUpTime = now;
      this.mLastUpX = x;
      this.mLastUpY = y;
      this.mL.onDoubleTapConfirmed(x, y);
      this.mFirstEvent = null;
      return;
    }

    if (this.mLongPressFired) {
      this.mLongPressFired = false;
      this.mLastUpTime = now;
      this.mLastUpX = x;
      this.mLastUpY = y;
      this.mFirstEvent = null;
      return;
    }

    const isTap = Math.abs(x - this.mDownX) <= this.mSlop
      && Math.abs(y - this.mDownY) <= this.mSlop
      && !this.mIsScrolling;

    if (isTap) {
      this.mL.onSingleTapUp(x, y);
      this.mLastUpTime = now;
      this.mLastUpX = x;
      this.mLastUpY = y;
      // 单击确认：DOUBLE_TAP_TIMEOUT 内无第二次 DOWN
      this.mSingleTapConfirmedTimer = setTimeout(() => {
        this.mSingleTapConfirmedTimer = -1;
        this.mL.onSingleTapConfirmed(x, y);
      }, TapDetector.DOUBLE_TAP_TIMEOUT);
      this.mFirstEvent = null;
      return;
    }

    // fling：速度在 [MIN_FLING_VELOCITY, MAX_FLING_VELOCITY] 内
    const vx = this.mVelocity.getXVelocity();
    const vy = this.mVelocity.getYVelocity();
    const speed = Math.sqrt(vx * vx + vy * vy);
    const first = this.mFirstEvent;
    // AOSP：速度须在 [MIN_FLING_VELOCITY, MAX_FLING_VELOCITY] 区间内才判 fling
    if (first !== null && speed >= this.mMinFlingVelocity && speed <= this.mMaxFlingVelocity) {
      this.mL.onFling(first, event, vx, vy);
    }

    this.mLastUpTime = now;
    this.mLastUpX = x;
    this.mLastUpY = y;
    this.mIsScrolling = false;
    this.mFirstEvent = null;
  }
}

/**
 * 双指缩放的 span 判定（AOSP `ScaleGestureDetector` 的语义子集，**quickScale 不启用**）。
 *
 * 判定：
 * 1. 少于 2 个触点 → 结束缩放
 * 2. `span = |p0 - p1|`，`focus = (p0 + p1) / 2`
 * 3. 首次进入时记 `prevSpan/currSpan`；当 `|span - prevSpan| > SPAN_SLOP` 时触发 `onScaleBegin`
 * 4. 之后每次变化 `scale = span / prevSpan`
 *
 * 与 AOSP 的差异（D-026 已登记）：AOSP 还有 `mSpanSlop` 的动态修正与"触点切换时的补偿"，
 * 这里按固定 `2 * TOUCH_SLOP` 处理，双指缩放手感可能有细微差别。
 */
export class SpanScaleDetector {
  private static readonly MIN_SCALING_SPAN_DP: number = 27;

  private readonly mL: GestureRecognizerListener;
  private readonly mMinSpan: number;
  private readonly mSpanSlop: number;

  private mInProgress: boolean = false;
  private mInitialSpan: number = 0;
  private mPrevSpan: number = 0;
  private mCurrSpan: number = 0;
  private mFocusX: number = 0;
  private mFocusY: number = 0;
  private mPrevFocusX: number = 0;
  private mPrevFocusY: number = 0;

  constructor(listener: GestureRecognizerListener) {
    this.mL = listener;
    this.mMinSpan = LayoutUtils.dp2pix(SpanScaleDetector.MIN_SCALING_SPAN_DP);
    this.mSpanSlop = LayoutUtils.dp2pix(8) * 2;
  }

  onTouchEvent(event: MotionEvent): void {
    const action = event.getActionMasked();
    const pointerCount = event.getPointerCount();

    if (action === MotionEvent.ACTION_CANCEL || action === MotionEvent.ACTION_UP) {
      this.endIfInProgress();
      return;
    }

    if (pointerCount < 2) {
      this.endIfInProgress();
      return;
    }

    const x0 = event.getXAt(0);
    const y0 = event.getYAt(0);
    const x1 = event.getXAt(1);
    const y1 = event.getYAt(1);
    const span = Math.sqrt((x0 - x1) * (x0 - x1) + (y0 - y1) * (y0 - y1));
    this.mFocusX = (x0 + x1) / 2;
    this.mFocusY = (y0 + y1) / 2;

    if (action === MotionEvent.ACTION_POINTER_DOWN) {
      // 新的双指手势：记录基准 span
      this.mInitialSpan = span;
      this.mPrevSpan = span;
      this.mCurrSpan = span;
      this.mPrevFocusX = this.mFocusX;
      this.mPrevFocusY = this.mFocusY;
      return;
    }

    this.mCurrSpan = span;

    if (!this.mInProgress) {
      // AOSP：以**初始 span** 为基准判断是否超过 spanSlop（不是逐帧增量，
      // 逐帧比较会在慢速缩放时永远攒不够阈值 —— 我第一版就写错了这个）
      if (Math.abs(this.mCurrSpan - this.mInitialSpan) > this.mSpanSlop
        && this.mCurrSpan > this.mMinSpan) {
        this.mInProgress = this.mL.onScaleBegin(this.mFocusX, this.mFocusY);
        if (!this.mInProgress) {
          // 监听器拒绝（如正在翻页）：把当前 span 当成新基准，避免下次立即又触发
          this.mInitialSpan = this.mCurrSpan;
          return;
        }
        this.mPrevSpan = this.mCurrSpan;
      }
      return;
    }

    // 进行中：算比例
    const prev = this.mPrevSpan;
    if (prev > 0) {
      const scale = this.mCurrSpan / prev;
      this.mL.onScale(this.mFocusX, this.mFocusY, scale);
    }
    this.mPrevSpan = this.mCurrSpan;
    this.mPrevFocusX = this.mFocusX;
    this.mPrevFocusY = this.mFocusY;
  }

  private endIfInProgress(): void {
    if (this.mInProgress) {
      this.mInProgress = false;
      this.mL.onScaleEnd();
    }
  }

  isInProgress(): boolean {
    return this.mInProgress;
  }

  getFocusX(): number {
    return this.mFocusX;
  }

  getFocusY(): number {
    return this.mFocusY;
  }
}
