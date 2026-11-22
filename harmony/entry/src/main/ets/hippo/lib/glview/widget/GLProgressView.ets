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

import { Color } from '../util/Color';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { GLPaint } from '../glrenderer/GLPaint';
import { Animation } from '../anim/Animation';
import { FloatAnimation } from '../anim/FloatAnimation';
import { PathInterpolator, PathSegment } from '../anim/PathInterpolator';
import { Interpolator } from '../../yorozuya/AnimationUtils';
import { AnimationTime } from '../view/AnimationTime';
import { GLView } from '../view/GLView';

/** 线性插值器（上游 `LinearInterpolator`）。 */
class LinearInterpolator implements Interpolator {
  getInterpolation(input: number): number {
    return input;
  }
}

/** 把 `FloatAnimation.get()` 抄进宿主字段的动画（上游是匿名子类）。 */
class FloatFieldAnimation extends FloatAnimation {
  private readonly mOwner: GLProgressView;
  private readonly mField: number;

  /** @param field 0=trimStart 1=trimEnd 2=trimOffset 3=trimRotation */
  constructor(owner: GLProgressView, field: number) {
    super();
    this.mOwner = owner;
    this.mField = field;
  }

  protected onCalculate(progress: number): void {
    super.onCalculate(progress);
    this.mOwner.setTrimField(this.mField, this.get());
  }
}

/**
 * `com.hippo.lib.glview.widget.GLProgressView` 的 ArkTS 等价实现（环形进度/转圈）。
 *
 * ## 不确定进度的四条动画（AOSP Material 进度圈原值，不许自己调）
 * | 字段 | 区间 | 时长 | 缓动 |
 * |---|---|---:|---|
 * | trimStart | 0 .. 0.75 | 1333ms | 自定义贝塞尔路径（折线+三次） |
 * | trimEnd | 0 .. 0.75 | 1333ms | 自定义贝塞尔路径（三次+折线） |
 * | trimOffset | 0 .. 0.25 | 1333ms | 线性 |
 * | trimRotation | 0 .. 720° | 6665ms | 线性 |
 * 全部 `repeatCount = INFINITE`。
 *
 * 弧线绘制：`startAngle = (trimStart + trimOffset) * 360 - 90`，
 * `sweepAngle = max(12°, (trimEnd - trimStart) * 360)` —— **最小 12°** 保证进度很小时也看得见。
 *
 * ## 几何常量（AOSP）
 * `lineWidth = min(w,h)/12`、`radiusX = w/48*19`、`radiusY = h/48*19`。
 *
 * ## 平台差异
 * 上游 `PathInterpolatorCompat.create(Path)` → 本项目 `PathInterpolator`（采样实现，
 * 精度差异 1e-3 量级，已登记；见该类注释）。
 */
export class GLProgressView extends GLView {
  private static readonly TRIM_START_INTERPOLATOR: Interpolator = GLProgressView.buildTrimStart();
  private static readonly TRIM_END_INTERPOLATOR: Interpolator = GLProgressView.buildTrimEnd();
  private static readonly LINEAR_INTERPOLATOR: Interpolator = new LinearInterpolator();

  private static buildTrimStart(): Interpolator {
    // moveTo(0,0) lineTo(0.5,0) cubicTo(0.7,0, 0.6,1, 1,1)
    return new PathInterpolator([
      PathSegment.line(0.0, 0.0, 0.5, 0.0),
      PathSegment.cubic(0.5, 0.0, 0.7, 0.0, 0.6, 1.0, 1.0, 1.0)
    ]);
  }

  private static buildTrimEnd(): Interpolator {
    // moveTo(0,0) cubicTo(0.2,0, 0.1,1, 0.5,1) lineTo(1,1)
    return new PathInterpolator([
      PathSegment.cubic(0.0, 0.0, 0.2, 0.0, 0.1, 1.0, 0.5, 1.0),
      PathSegment.line(0.5, 1.0, 1.0, 1.0)
    ]);
  }

  private readonly mGLPaint: GLPaint = new GLPaint();

  private mCx: number = 0;
  private mCy: number = 0;
  private mRadiusX: number = 0;
  private mRadiusY: number = 0;

  private mTrimStart: number = 0.0;
  private mTrimEnd: number = 0.0;
  private mTrimOffset: number = 0.0;
  private mTrimRotation: number = 0.0;

  private mIndeterminate: boolean = false;

  private readonly mAnimations: Animation[] = [];

  constructor() {
    super();
    this.mGLPaint.setColor(Color.WHITE);
    this.mGLPaint.setBackgroundColor(Color.BLACK);
    this.setupAnimations();
  }

  /** 供 `FloatFieldAnimation` 回写（上游用匿名子类直接改宿主字段）。 */
  setTrimField(field: number, value: number): void {
    switch (field) {
      case 0:
        this.mTrimStart = value;
        break;
      case 1:
        this.mTrimEnd = value;
        break;
      case 2:
        this.mTrimOffset = value;
        break;
      case 3:
        this.mTrimRotation = value;
        break;
      default:
        break;
    }
  }

  private setupAnimations(): void {
    const trimStart = new FloatFieldAnimation(this, 0);
    trimStart.setRange(0.0, 0.75);
    trimStart.setDuration(1333);
    trimStart.setInterpolator(GLProgressView.TRIM_START_INTERPOLATOR);
    trimStart.setRepeatCount(Animation.INFINITE);

    const trimEnd = new FloatFieldAnimation(this, 1);
    trimEnd.setRange(0.0, 0.75);
    trimEnd.setDuration(1333);
    trimEnd.setInterpolator(GLProgressView.TRIM_END_INTERPOLATOR);
    trimEnd.setRepeatCount(Animation.INFINITE);

    const trimOffset = new FloatFieldAnimation(this, 2);
    trimOffset.setRange(0.0, 0.25);
    trimOffset.setDuration(1333);
    trimOffset.setInterpolator(GLProgressView.LINEAR_INTERPOLATOR);
    trimOffset.setRepeatCount(Animation.INFINITE);

    const trimRotation = new FloatFieldAnimation(this, 3);
    trimRotation.setRange(0.0, 720.0);
    trimRotation.setDuration(6665);
    trimRotation.setInterpolator(GLProgressView.LINEAR_INTERPOLATOR);
    trimRotation.setRepeatCount(Animation.INFINITE);

    this.mAnimations.push(trimStart);
    this.mAnimations.push(trimEnd);
    this.mAnimations.push(trimOffset);
    this.mAnimations.push(trimRotation);
  }

  private startAnimations(): void {
    for (let i = 0, n = this.mAnimations.length; i < n; i++) {
      this.mAnimations[i].reset();
    }
  }

  private stopAnimations(): void {
    for (let i = 0, n = this.mAnimations.length; i < n; i++) {
      this.mAnimations[i].cancel();
    }
  }

  protected onLayout(changeSize: boolean, left: number, top: number, right: number,
    bottom: number): void {
    super.onLayout(changeSize, left, top, right, bottom);

    const width = right - left;
    const height = bottom - top;
    this.mGLPaint.setLineWidth(Math.min(width, height) / 12.0);
    this.mCx = Math.trunc(width / 2);
    this.mCy = Math.trunc(height / 2);
    this.mRadiusX = width / 48.0 * 19.0;
    this.mRadiusY = height / 48.0 * 19.0;
  }

  setColor(color: number): void {
    this.mGLPaint.setColor(color);
    this.invalidate();
  }

  setBgColor(color: number): void {
    this.mGLPaint.setBackgroundColor(color);
    this.invalidate();
  }

  setIndeterminate(indeterminate: boolean): void {
    if (this.mIndeterminate !== indeterminate) {
      this.mIndeterminate = indeterminate;
      if (indeterminate) {
        this.startAnimations();
      } else {
        this.stopAnimations();
      }
      this.invalidate();
    }
  }

  isIndeterminate(): boolean {
    return this.mIndeterminate;
  }

  setProgress(progress: number): void {
    if (!this.mIndeterminate) {
      this.mTrimStart = 0.0;
      this.mTrimEnd = progress;
      this.mTrimOffset = 0.0;
      this.mTrimRotation = 0.0;
      this.invalidate();
    }
  }

  onRender(canvas: GLCanvas): void {
    this.update();

    const width = this.getWidth();
    const height = this.getHeight();
    const cx = Math.trunc(width / 2);
    const cy = Math.trunc(height / 2);

    const startAngle = (this.mTrimStart + this.mTrimOffset) * 360.0 - 90;
    const sweepAngle = Math.max(12.0, (this.mTrimEnd - this.mTrimStart) * 360.0);
    const rotation = this.mTrimRotation + startAngle;

    canvas.save();

    canvas.translate(cx, cy);
    canvas.rotate(rotation, 0, 0, 1);
    if (rotation % 180 !== 0) {
      canvas.translate(-cy, -cx);
    } else {
      canvas.translate(-cx, -cy);
    }

    canvas.drawArc(this.mCx, this.mCy, this.mRadiusX, this.mRadiusY, sweepAngle, this.mGLPaint);

    canvas.restore();
  }

  private update(): void {
    let needInvalidate = false;

    if (this.mIndeterminate) {
      const currentTime = AnimationTime.get();
      for (let i = 0, n = this.mAnimations.length; i < n; i++) {
        needInvalidate = this.mAnimations[i].calculate(currentTime) || needInvalidate;
      }
    }

    if (needInvalidate) {
      this.invalidate();
    }
  }
}
