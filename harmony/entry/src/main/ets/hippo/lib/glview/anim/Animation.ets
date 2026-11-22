/*
 * Copyright (C) 2010 The Android Open Source Project
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

import { MathUtils } from '../../yorozuya/MathUtils';
import { Interpolator } from '../../yorozuya/AnimationUtils';
import { systemDateTime } from '@kit.BasicServicesKit';

/**
 * `com.hippo.lib.glview.anim.Animation` 的 ArkTS 等价实现。
 *
 * 用法（上游注释直译）：
 * 1. `setDuration(ms)` 设时长
 * 2. `start()` 启动；实际开始时间是第一次 `calculate(now)` 传入的值
 * 3. 每次要取值就 `calculate(currentTimeMillis)`，然后 `get()` 读当前值
 * 4. `calculate` 内部调 `onCalculate(progress)`（progress ∈ [0,1]），子类据此算值
 * 5. 可有 `Interpolator` 先改造 progress（例如 overshoot 会超出 [0,1]）
 * 6. `isRunning()` 在 start 之后、且传入时间未达 duration 之前为 true
 *
 * ## 计时源
 * 上游用 `SystemClock.uptimeMillis()`（自启动单调计数）。鸿蒙等价物是
 * `systemDateTime.getUptime(TimeType.STARTUP)` —— **不能用 `Date.now()`**：
 * 墙钟会被用户改时间/NTP 校正而跳变，动画会突然"瞬移"或倒放。
 *
 * ## 已知行为差异（登记）
 * 上游 `mRepeatMode`（RESTART/REVERSE）字段存在但**从未被使用**（源码里就写着 `// TODO mRepeatMode`），
 * 这里保留字段与 setter 以维持调用点，但同样不实现方向反转 —— 与上游行为一致。
 */
export abstract class Animation {
  private static readonly ANIMATION_START: number = -1;
  private static readonly NO_ANIMATION: number = -2;

  /** 到达末尾且 repeatCount 为 INFINITE 或正数时，从头重播。 */
  static readonly RESTART: number = 1;

  /** 到达末尾时每次迭代反向。 */
  static readonly REVERSE: number = 2;

  /** 无限循环。 */
  static readonly INFINITE: number = -1;

  private mStartTime: number = Animation.NO_ANIMATION;
  private mDuration: number = 0;
  private mInterpolator: Interpolator | null = null;
  private mRepeatCount: number = 0;
  private mRepeatMode: number = 0;

  private mRunnedCount: number = 0;
  private mLastFrameTime: number = 0;

  setInterpolator(interpolator: Interpolator | null): void {
    this.mInterpolator = interpolator;
  }

  setDuration(duration: number): void {
    this.mDuration = duration;
  }

  setRepeatCount(repeatCount: number): void {
    this.mRepeatCount = repeatCount;
  }

  setRepeatMode(repeatMode: number): void {
    this.mRepeatMode = repeatMode;
  }

  isRunning(): boolean {
    return this.mStartTime > 0 || this.mStartTime === Animation.ANIMATION_START;
  }

  getLastFrameTime(): number {
    return this.mLastFrameTime;
  }

  start(): void {
    if (this.mStartTime === Animation.NO_ANIMATION) {
      this.mStartTime = Animation.ANIMATION_START;
      this.mRunnedCount = 0;
      this.mLastFrameTime = 0;
    }
  }

  startAt(time: number): void {
    this.start();
    this.setStartTime(time);
  }

  /** 以单调时钟的当前值启动（等价上游 `SystemClock.uptimeMillis()`）。 */
  startNow(): void {
    this.start();
    this.setStartTime(Animation.uptimeMillis());
  }

  setStartTime(time: number): void {
    this.mStartTime = time;
  }

  cancel(): void {
    this.mStartTime = Animation.NO_ANIMATION;
  }

  reset(): void {
    this.mStartTime = Animation.ANIMATION_START;
    this.mRunnedCount = 0;
    this.mLastFrameTime = 0;
  }

  /**
   * 推进动画。
   * @return true 表示动画仍在进行（下一帧还需继续调用）
   */
  calculate(currentTimeMillis: number): boolean {
    if (this.mStartTime === Animation.NO_ANIMATION) {
      return false;
    }
    if (this.mStartTime === Animation.ANIMATION_START) {
      this.mStartTime = currentTimeMillis;
    }
    this.mLastFrameTime = currentTimeMillis;

    const elapse = currentTimeMillis - this.mStartTime;
    // 防 NaN：duration 为 0 时直接当作 1.0（上游同一行三元表达式）
    const raw = this.mDuration === 0 ? 1.0 : elapse / this.mDuration;
    const x = MathUtils.clamp(raw, 0.0, 1.0);
    const interpolator = this.mInterpolator;
    this.onCalculate(interpolator !== null ? interpolator.getInterpolation(x) : x);

    // onCalculate 里允许调 cancel()，所以这里要重新读 mStartTime
    if (this.mStartTime !== Animation.NO_ANIMATION && elapse >= this.mDuration) {
      this.mRunnedCount++;
      if (this.mRunnedCount >= this.mRepeatCount && this.mRepeatCount !== Animation.INFINITE) {
        this.onFinish();
        this.mStartTime = Animation.NO_ANIMATION;
      } else {
        this.mStartTime += elapse;
      }
    }

    return this.mStartTime !== Animation.NO_ANIMATION;
  }

  /** 子类按 progress 计算当前值。 */
  protected abstract onCalculate(progress: number): void;

  protected onFinish(): void {
  }

  /** 单调毫秒时钟（`SystemClock.uptimeMillis()` 等价物）。 */
  static uptimeMillis(): number {
    return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
  }
}
