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

import { Rect } from '../util/Rect';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { Animation } from '../anim/Animation';
import { Interpolator } from '../../yorozuya/AnimationUtils';

/** AOSP `DecelerateInterpolator`：`1 - (1-x)²`。 */
class DecelerateInterpolator implements Interpolator {
  getInterpolation(input: number): number {
    return 1.0 - (1.0 - input) * (1.0 - input);
  }
}

/**
 * `com.hippo.lib.glview.widget.GLEdgeEffect` 的 ArkTS 等价实现（Material 边缘辉光）。
 *
 * 五个状态机：`IDLE → PULL → PULL_DECAY → RECEDE → IDLE`，另有 `ABSORB`（惯性撞边界）。
 * 所有时间常量都是 AOSP `EdgeEffect` 原值，不许自己调：
 *
 * | 常量 | 值 | 含义 |
 * |---|---:|---|
 * | `RECEDE_TIME` | 600ms | 完全收回 |
 * | `PULL_TIME` | 167ms | 拉起后开始衰减前的时间 |
 * | `PULL_DECAY_TIME` | 2000ms | 拉起后衰减到部分强度 |
 * | `MAX_ALPHA` | 0.5 | 最大不透明度 |
 * | `MAX_GLOW_SCALE` | 2.0 | 辉光最大缩放 |
 * | `MIN/MAX_VELOCITY` | 100 / 10000 | 吸收速度的钳制区间 |
 * | `ANGLE` | π/6（30°） | 扇形张角，决定半径与高度关系 |
 *
 * ## 平台差异
 * `AnimationUtils.currentAnimationTimeMillis()` → `Animation.uptimeMillis()`（单调时钟，
 * 不用墙钟，否则改系统时间会让辉光瞬间跳变）。
 */
export class GLEdgeEffect {
  private static readonly RECEDE_TIME: number = 600;
  private static readonly PULL_TIME: number = 167;
  private static readonly PULL_DECAY_TIME: number = 2000;

  private static readonly MAX_ALPHA: number = 0.5;
  private static readonly MAX_GLOW_SCALE: number = 2.0;
  private static readonly PULL_GLOW_BEGIN: number = 0.0;

  private static readonly MIN_VELOCITY: number = 100;
  private static readonly MAX_VELOCITY: number = 10000;

  private static readonly EPSILON: number = 0.001;

  private static readonly ANGLE: number = Math.PI / 6;
  private static readonly SIN: number = Math.sin(GLEdgeEffect.ANGLE);
  private static readonly COS: number = Math.cos(GLEdgeEffect.ANGLE);

  private static readonly STATE_IDLE: number = 0;
  private static readonly STATE_PULL: number = 1;
  private static readonly STATE_ABSORB: number = 2;
  private static readonly STATE_RECEDE: number = 3;
  private static readonly STATE_PULL_DECAY: number = 4;

  private static readonly PULL_DISTANCE_ALPHA_GLOW_FACTOR: number = 0.8;
  private static readonly VELOCITY_GLOW_FACTOR: number = 6;

  private mGlowAlpha: number = 0;
  private mGlowScaleY: number = 0;

  private mGlowAlphaStart: number = 0;
  private mGlowAlphaFinish: number = 0;
  private mGlowScaleYStart: number = 0;
  private mGlowScaleYFinish: number = 0;

  private mStartTime: number = 0;
  private mDuration: number = 0;

  private readonly mInterpolator: Interpolator = new DecelerateInterpolator();

  private mState: number = GLEdgeEffect.STATE_IDLE;

  private mPullDistance: number = 0;

  private readonly mBounds: Rect = new Rect();
  private mColor: number;
  private mRadius: number = 0;
  private mBaseGlowScale: number = 0;
  private mDisplacement: number = 0.5;
  private mTargetDisplacement: number = 0.5;

  constructor(color: number) {
    this.mColor = color;
  }

  /**
   * 设置边缘效果尺寸（像素）。半径与高度由 30° 张角决定：
   * `r = w * 0.75 / sin(30°)`、`y = cos(30°) * r`、`h = r - y`。
   */
  setSize(width: number, height: number): void {
    const r = width * 0.75 / GLEdgeEffect.SIN;
    const y = GLEdgeEffect.COS * r;
    const h = r - y;
    const or = height * 0.75 / GLEdgeEffect.SIN;
    const oy = GLEdgeEffect.COS * or;
    const oh = or - oy;

    this.mRadius = r;
    this.mBaseGlowScale = h > 0 ? Math.min(oh / h, 1.0) : 1.0;

    this.mBounds.set(this.mBounds.left, this.mBounds.top, width,
      Math.trunc(Math.min(height, h)));
  }

  isFinished(): boolean {
    return this.mState === GLEdgeEffect.STATE_IDLE;
  }

  finish(): void {
    this.mState = GLEdgeEffect.STATE_IDLE;
  }

  /** `onPull(deltaDistance)` 与 `onPull(deltaDistance, displacement)` 合一。 */
  onPull(deltaDistance: number, displacement?: number): void {
    const disp = displacement === undefined ? 0.5 : displacement;
    const now = Animation.uptimeMillis();
    this.mTargetDisplacement = disp;
    if (this.mState === GLEdgeEffect.STATE_PULL_DECAY
      && now - this.mStartTime < this.mDuration) {
      return;
    }
    if (this.mState !== GLEdgeEffect.STATE_PULL) {
      this.mGlowScaleY = Math.max(GLEdgeEffect.PULL_GLOW_BEGIN, this.mGlowScaleY);
    }
    this.mState = GLEdgeEffect.STATE_PULL;

    this.mStartTime = now;
    this.mDuration = GLEdgeEffect.PULL_TIME;

    this.mPullDistance += deltaDistance;

    const absdd = Math.abs(deltaDistance);
    this.mGlowAlpha = Math.min(GLEdgeEffect.MAX_ALPHA,
      this.mGlowAlpha + absdd * GLEdgeEffect.PULL_DISTANCE_ALPHA_GLOW_FACTOR);
    this.mGlowAlphaStart = this.mGlowAlpha;

    if (this.mPullDistance === 0) {
      this.mGlowScaleY = 0;
      this.mGlowScaleYStart = 0;
    } else {
      const scale = Math.max(0, 1 - 1
        / Math.sqrt(Math.abs(this.mPullDistance) * this.mBounds.height()) - 0.3) / 0.7;
      this.mGlowScaleY = scale;
      this.mGlowScaleYStart = scale;
    }

    this.mGlowAlphaFinish = this.mGlowAlpha;
    this.mGlowScaleYFinish = this.mGlowScaleY;
  }

  onRelease(): void {
    this.mPullDistance = 0;

    if (this.mState !== GLEdgeEffect.STATE_PULL
      && this.mState !== GLEdgeEffect.STATE_PULL_DECAY) {
      return;
    }

    this.mState = GLEdgeEffect.STATE_RECEDE;
    this.mGlowAlphaStart = this.mGlowAlpha;
    this.mGlowScaleYStart = this.mGlowScaleY;

    this.mGlowAlphaFinish = 0.0;
    this.mGlowScaleYFinish = 0.0;

    this.mStartTime = Animation.uptimeMillis();
    this.mDuration = GLEdgeEffect.RECEDE_TIME;
  }

  /** 吸收一次惯性冲击（fling 撞到边界时）。velocity 单位 px/s。 */
  onAbsorb(velocity: number): void {
    this.mState = GLEdgeEffect.STATE_ABSORB;
    const v = Math.min(Math.max(GLEdgeEffect.MIN_VELOCITY, Math.abs(velocity)),
      GLEdgeEffect.MAX_VELOCITY);

    this.mStartTime = Animation.uptimeMillis();
    this.mDuration = 0.15 + v * 0.02;

    this.mGlowAlphaStart = 0.3;
    this.mGlowScaleYStart = Math.max(this.mGlowScaleY, 0.0);

    // 辉光尺寸按速度二次增长（AOSP 原式）
    this.mGlowScaleYFinish = Math.min(0.025 + (v * (v / 100) * 0.00015) / 2, 1.0);
    this.mGlowAlphaFinish = Math.max(this.mGlowAlphaStart,
      Math.min(v * GLEdgeEffect.VELOCITY_GLOW_FACTOR * 0.00001, GLEdgeEffect.MAX_ALPHA));
    this.mTargetDisplacement = 0.5;
  }

  setColor(color: number): void {
    this.mColor = color;
  }

  getColor(): number {
    return this.mColor;
  }

  /**
   * 绘制。调用前画布已按边方向旋转过、尺寸已设置。
   * @return true 表示下一帧还要继续画（动画未结束）
   */
  draw(canvas: GLCanvas): boolean {
    this.update();

    canvas.save();

    const centerX = this.mBounds.centerX();
    const centerY = this.mBounds.height() - this.mRadius;

    canvas.translate(-centerX, 0.0);
    canvas.scale(1.0, Math.min(this.mGlowScaleY, 1.0) * this.mBaseGlowScale, 0);
    canvas.translate(centerX, 0.0);

    const displacement = Math.max(0, Math.min(this.mDisplacement, 1.0)) - 0.5;
    const translateX = this.mBounds.width() * displacement / 2;

    canvas.translate(translateX, 0);
    canvas.fillOval(centerX, centerY, this.mRadius, this.mRadius, this.mColor);
    canvas.restore();

    let oneLastFrame = false;
    if (this.mState === GLEdgeEffect.STATE_RECEDE && this.mGlowScaleY === 0) {
      this.mState = GLEdgeEffect.STATE_IDLE;
      oneLastFrame = true;
    }

    return this.mState !== GLEdgeEffect.STATE_IDLE || oneLastFrame;
  }

  /** 最大绘制高度（`mBounds.height() * MAX_GLOW_SCALE`，四舍五入）。 */
  getMaxHeight(): number {
    return Math.trunc(this.mBounds.height() * GLEdgeEffect.MAX_GLOW_SCALE + 0.5);
  }

  private update(): void {
    const time = Animation.uptimeMillis();
    const t = Math.min((time - this.mStartTime) / this.mDuration, 1.0);

    const interp = this.mInterpolator.getInterpolation(t);

    this.mGlowAlpha = this.mGlowAlphaStart + (this.mGlowAlphaFinish - this.mGlowAlphaStart) * interp;
    this.mGlowScaleY = this.mGlowScaleYStart
      + (this.mGlowScaleYFinish - this.mGlowScaleYStart) * interp;
    this.mDisplacement = (this.mDisplacement + this.mTargetDisplacement) / 2;

    if (t >= 1.0 - GLEdgeEffect.EPSILON) {
      switch (this.mState) {
        case GLEdgeEffect.STATE_ABSORB:
          this.mState = GLEdgeEffect.STATE_RECEDE;
          this.mStartTime = Animation.uptimeMillis();
          this.mDuration = GLEdgeEffect.RECEDE_TIME;
          this.mGlowAlphaStart = this.mGlowAlpha;
          this.mGlowScaleYStart = this.mGlowScaleY;
          this.mGlowAlphaFinish = 0.0;
          this.mGlowScaleYFinish = 0.0;
          break;
        case GLEdgeEffect.STATE_PULL:
          this.mState = GLEdgeEffect.STATE_PULL_DECAY;
          this.mStartTime = Animation.uptimeMillis();
          this.mDuration = GLEdgeEffect.PULL_DECAY_TIME;
          this.mGlowAlphaStart = this.mGlowAlpha;
          this.mGlowScaleYStart = this.mGlowScaleY;
          this.mGlowAlphaFinish = 0.0;
          this.mGlowScaleYFinish = 0.0;
          break;
        case GLEdgeEffect.STATE_PULL_DECAY:
          this.mState = GLEdgeEffect.STATE_RECEDE;
          break;
        case GLEdgeEffect.STATE_RECEDE:
          this.mState = GLEdgeEffect.STATE_IDLE;
          break;
        default:
          break;
      }
    }
  }
}
