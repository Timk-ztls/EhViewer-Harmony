/*
 * Copyright (C) 2016 Hippo Seven
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

import { Interpolator } from '../../yorozuya/AnimationUtils';

/** 路径段：直线（isLine=true）或三次贝塞尔。 */
export class PathSegment {
  isLine: boolean;
  /** 段起点。 */
  x0: number;
  y0: number;
  /** 控制点 1 / 2（直线段时忽略）。 */
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  /** 段终点。 */
  x3: number;
  y3: number;

  private constructor(isLine: boolean, x0: number, y0: number, x1: number, y1: number,
    x2: number, y2: number, x3: number, y3: number) {
    this.isLine = isLine;
    this.x0 = x0;
    this.y0 = y0;
    this.x1 = x1;
    this.y1 = y1;
    this.x2 = x2;
    this.y2 = y2;
    this.x3 = x3;
    this.y3 = y3;
  }

  static line(x0: number, y0: number, x3: number, y3: number): PathSegment {
    return new PathSegment(true, x0, y0, x0, y0, x3, y3, x3, y3);
  }

  static cubic(x0: number, y0: number, x1: number, y1: number, x2: number, y2: number,
    x3: number, y3: number): PathSegment {
    return new PathSegment(false, x0, y0, x1, y1, x2, y2, x3, y3);
  }

  /** 参数 t∈[0,1] 上的点。 */
  pointAt(t: number): number[] {
    if (this.isLine) {
      return [this.x0 + (this.x3 - this.x0) * t, this.y0 + (this.y3 - this.y0) * t];
    }
    const mt = 1 - t;
    const a = mt * mt * mt;
    const b = 3 * mt * mt * t;
    const c = 3 * mt * t * t;
    const d = t * t * t;
    return [
      a * this.x0 + b * this.x1 + c * this.x2 + d * this.x3,
      a * this.y0 + b * this.y1 + c * this.y2 + d * this.y3
    ];
  }
}

/**
 * `androidx.core.view.animation.PathInterpolatorCompat`（按 Path 构造的插值器）的 ArkTS 等价实现。
 *
 * 用途：`GLProgressView` 的两条不确定进度弧线（trimStart / trimEnd）用**带折线的三次贝塞尔路径**
 * 定义缓动曲线：
 * ```
 * trimStart: moveTo(0,0) lineTo(0.5,0) cubicTo(0.7,0, 0.6,1, 1,1)
 * trimEnd  : moveTo(0,0) cubicTo(0.2,0, 0.1,1, 0.5,1) lineTo(1,1)
 * ```
 * AndroidX 内部把 Path 采样成一组 (x,y) 点再按 x 求 y（单调 x 保证可逆）。
 *
 * ## 实现与精度（登记为近似）
 * 本实现同样按**均匀参数采样** `SAMPLE_COUNT` 个点建表，`getInterpolation(x)` 用二分定位
 * 相邻两点再线性插值。与 AndroidX 的差异：
 * - AndroidX 用 `PathMeasure` 按**弧长**采样，这里按**贝塞尔参数 t** 采样；
 *   对单调曲线两者只在中间段的采样密度上略有差异，实测误差量级 1e-3（见单测）。
 * - 不处理"x 非单调"的路径（上游也只支持单调 x），遇到会抛错而不是静默给出乱序结果。
 */
export class PathInterpolator implements Interpolator {
  private static readonly SAMPLE_COUNT: number = 512;

  private readonly mX: number[] = [];
  private readonly mY: number[] = [];

  /**
   * @param segments 首尾相接的路径段（第一段的起点即路径起点）
   */
  constructor(segments: PathSegment[]) {
    if (segments.length === 0) {
      throw new Error('PathInterpolator: empty path');
    }
    const total = PathInterpolator.SAMPLE_COUNT;
    // 每条段平均分配采样点（末点只取一次）
    const perSegment = Math.max(2, Math.trunc(total / segments.length));
    for (let s = 0; s < segments.length; s++) {
      const seg = segments[s];
      for (let i = 0; i <= perSegment; i++) {
        if (s > 0 && i === 0) {
          continue; // 段首点与上一段末点重复，跳过
        }
        const t = i / perSegment;
        const p = seg.pointAt(t);
        const x = p[0];
        const y = p[1];
        // x 必须单调不减，否则无法反解
        if (this.mX.length > 0 && x < this.mX[this.mX.length - 1] - 1e-6) {
          throw new Error('PathInterpolator: path x is not monotonic');
        }
        this.mX.push(x);
        this.mY.push(y);
      }
    }
    // 端点修正（采样误差可能让首尾不等于 0/1）
    this.mX[0] = 0;
    this.mY[0] = 0;
    this.mX[this.mX.length - 1] = 1;
    this.mY[this.mY.length - 1] = 1;
  }

  /** 便捷构造：单条三次贝塞尔（等价 `CubicBezierInterpolator`）。 */
  static cubicBezier(x1: number, y1: number, x2: number, y2: number): PathInterpolator {
    return new PathInterpolator([PathSegment.cubic(0, 0, x1, y1, x2, y2, 1, 1)]);
  }

  getInterpolation(input: number): number {
    if (input <= 0) {
      return 0;
    }
    if (input >= 1) {
      return 1;
    }
    // 二分找 x 所在区间
    let lo = 0;
    let hi = this.mX.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (this.mX[mid] <= input) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    const x0 = this.mX[lo];
    const x1 = this.mX[hi];
    const y0 = this.mY[lo];
    const y1 = this.mY[hi];
    if (x1 === x0) {
      return y1;
    }
    const t = (input - x0) / (x1 - x0);
    return y0 + (y1 - y0) * t;
  }

  /** 诊断/单测：采样点数。 */
  sampleCount(): number {
    return this.mX.length;
  }
}
