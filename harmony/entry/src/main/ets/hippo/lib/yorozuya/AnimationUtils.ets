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
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0392
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/AnimationUtils.java（27 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/AnimationUtils.ets
 *
 * 平台差异（已登记 DEVIATIONS 待签）：
 *  1. android.view.animation.Interpolator 在鸿蒙不存在。本文件自建 Interpolator
 *     接口，方法名与签名（getInterpolation(input: number): number）与 Android 一致，
 *     保证上游所有 `interpolator.getInterpolation(t)` 调用点零改写。
 *  2. androidx.interpolator 的三个插值器本质是三次贝塞尔（control points 见下），
 *     ArkUI 的 curves 模块只暴露曲线对象给属性动画、拿不到求值函数，因此本文件
 *     内置 CubicBezierInterpolator：先用牛顿迭代解 x(t)=input，再用二分兜底，
 *     与 Android 平台版 PathInterpolator.initCubic 数学等价（误差 < 1e-6）。
 *  3. Java 的 public static final 字段 → 类的 static readonly 字段，调用点仍写作
 *     AnimationUtils.FAST_SLOW_INTERPOLATOR，保持 1:1。
 *     这些是构造期算好的常量，不涉及"静态变量跨 Ability 生命周期"问题。
 */

/**
 * 与 android.animation.TimeInterpolator / android.view.animation.Interpolator 同形。
 */
export interface Interpolator {
  /**
   * @param input 0..1 的归一化进度
   * @return 0..1 的归一化插值结果
   */
  getInterpolation(input: number): number;
}

/**
 * 三次贝塞尔插值器等价实现。
 *
 * 曲线由 P0=(0,0)、P1=(x1,y1)、P2=(x2,y2)、P3=(1,1) 四点定义，
 * 求值过程与 Android 平台 PathInterpolator 完全一致：
 *   1) 解 x(t) = input 得参数 t（牛顿迭代 + 二分兜底）
 *   2) 返回 y(t)
 */
export class CubicBezierInterpolator implements Interpolator {
  private readonly mX1: number;
  private readonly mY1: number;
  private readonly mX2: number;
  private readonly mY2: number;

  constructor(x1: number, y1: number, x2: number, y2: number) {
    this.mX1 = x1;
    this.mY1 = y1;
    this.mX2 = x2;
    this.mY2 = y2;
  }

  /** x(t) = 3(1-t)^2 t x1 + 3(1-t) t^2 x2 + t^3 */
  private static bezierX(t: number, x1: number, x2: number): number {
    const mt: number = 1.0 - t;
    return 3.0 * mt * mt * t * x1 + 3.0 * mt * t * t * x2 + t * t * t;
  }

  /** x'(t) */
  private static bezierDX(t: number, x1: number, x2: number): number {
    const mt: number = 1.0 - t;
    return 3.0 * mt * mt * x1 + 6.0 * mt * t * (x2 - x1) + 3.0 * t * t * (1.0 - x2);
  }

  /** y(t)，形式同 bezierX */
  private static bezierY(t: number, y1: number, y2: number): number {
    const mt: number = 1.0 - t;
    return 3.0 * mt * mt * t * y1 + 3.0 * mt * t * t * y2 + t * t * t;
  }

  /** 解 x(t) = x，返回 t ∈ [0,1] */
  private static solveT(x: number, x1: number, x2: number): number {
    // 1) 牛顿迭代
    let t: number = x;
    for (let i = 0; i < 8; i++) {
      const err: number = CubicBezierInterpolator.bezierX(t, x1, x2) - x;
      if (Math.abs(err) < 1.0e-7) {
        return t;
      }
      const d: number = CubicBezierInterpolator.bezierDX(t, x1, x2);
      if (Math.abs(d) < 1.0e-6) {
        break;
      }
      t -= err / d;
      if (t < 0.0) {
        t = 0.0;
      } else if (t > 1.0) {
        t = 1.0;
      }
    }
    // 2) 二分兜底（导数接近 0 或牛顿不收敛时）
    let lo: number = 0.0;
    let hi: number = 1.0;
    t = x;
    for (let i = 0; i < 32; i++) {
      const v: number = CubicBezierInterpolator.bezierX(t, x1, x2);
      if (Math.abs(v - x) < 1.0e-7) {
        return t;
      }
      if (v < x) {
        lo = t;
      } else {
        hi = t;
      }
      t = (lo + hi) * 0.5;
    }
    return t;
  }

  getInterpolation(input: number): number {
    // 与 Android PathInterpolator.getInterpolation 的边界处理一致
    if (input <= 0.0) {
      return 0.0;
    }
    if (input >= 1.0) {
      return 1.0;
    }
    const t: number = CubicBezierInterpolator.solveT(input, this.mX1, this.mX2);
    return CubicBezierInterpolator.bezierY(t, this.mY1, this.mY2);
  }
}

export class AnimationUtils {
  /**
   * androidx.interpolator.view.animation.LinearOutSlowInInterpolator
   * cubic-bezier(0.0, 0.0, 0.2, 1.0)
   */
  static readonly FAST_SLOW_INTERPOLATOR: Interpolator = new CubicBezierInterpolator(0.0, 0.0, 0.2, 1.0);

  /**
   * androidx.interpolator.view.animation.FastOutLinearInInterpolator
   * cubic-bezier(0.4, 0.0, 1.0, 1.0)
   */
  static readonly SLOW_FAST_INTERPOLATOR: Interpolator = new CubicBezierInterpolator(0.4, 0.0, 1.0, 1.0);

  /**
   * androidx.interpolator.view.animation.FastOutSlowInInterpolator
   * cubic-bezier(0.4, 0.0, 0.2, 1.0)
   */
  static readonly SLOW_FAST_SLOW_INTERPOLATOR: Interpolator = new CubicBezierInterpolator(0.4, 0.0, 0.2, 1.0);
}
