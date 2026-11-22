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

/**
 * gl-render 用到的 `com.hippo.lib.yorozuya.MathUtils` 子集的本地等价实现。
 *
 * 最终归属：`hippo/lib/yorozuya/MathUtils.ets`（core-runtime 维护，见 Lead 裁决 C）。
 * 本文件只做过渡，等 yorozuya 的 MathUtils 合入 main 后整体删掉、改为 re-export，
 * 对外符号名不变。
 *
 * **精度要求（不是洁癖，是像素级等价）**：
 * 上游 `DEG_TO_RAD` 写死为 `3.1415926f / 180.0f`，**不是** `Math.PI / 180`。
 * `GLES20Canvas` 的圆/扇形顶点表 `BOX_COORDINATES` 就是用它算出来的
 * （`sin(radians(90f / n * i))`），换成 Math.PI 会让 120 个圆弧顶点的坐标
 * 在第 7 位小数上漂移，放大到全屏就是边缘 1px 的抗锯齿差异。所以这里照抄。
 */
const DEG_TO_RAD: number = 3.1415926 / 180.0;
const RAD_TO_DEG: number = 180.0 / 3.1415926;

export class GLMath {
  /** 角度 → 弧度（截断的 π，见文件头说明）。 */
  static radians(degrees: number): number {
    return degrees * DEG_TO_RAD;
  }

  /** 弧度 → 角度。 */
  static degrees(radians: number): number {
    return radians * RAD_TO_DEG;
  }

  /**
   * 正模。逐字照抄上游（含 `if (x < 0) result += y` 这个只在 x<0 时修正的分支）。
   *
   * 注意：当 x<0 且 |x|>y 时该实现仍可能返回负数（Java `%` 的余数语义），
   * 这是上游既有行为。`GLES20Canvas.fillSector` 依赖它算共轭角，
   * 改成数学上"更正确"的 floorMod 会让扇形起始角偏移，因此保持一致。
   */
  static positiveModulo(x: number, y: number): number {
    let result = x % y;
    if (x < 0) {
      result += y;
    }
    return result;
  }

  static abs(v: number): number {
    return v > 0 ? v : -v;
  }

  static clamp(x: number, min: number, max: number): number {
    if (x > max) {
      return max;
    }
    if (x < min) {
      return min;
    }
    return x;
  }

  static max(a: number, b: number): number {
    return a > b ? a : b;
  }

  static min(a: number, b: number): number {
    return a < b ? a : b;
  }

  static dist(x1: number, y1: number, x2: number, y2: number): number {
    const x = x2 - x1;
    const y = y2 - y1;
    return Math.sqrt(x * x + y * y);
  }

  static mag(a: number, b: number): number {
    return Math.sqrt(a * a + b * b);
  }

  static sq(v: number): number {
    return v * v;
  }

  static lerp(start: number, stop: number, amount: number): number {
    return start + (stop - start) * amount;
  }

  static inverseLerp(start: number, stop: number, value: number): number {
    if (stop === start) {
      return 1.0;
    }
    return (value - start) / (stop - start);
  }

  static nextPowerOf2(n: number): number {
    if (n <= 0 || n > (1 << 30)) {
      throw new Error(`n is invalid: ${n}`);
    }
    n -= 1;
    n |= n >> 16;
    n |= n >> 8;
    n |= n >> 4;
    n |= n >> 2;
    n |= n >> 1;
    n += 1;
    return n;
  }

  static prevPowerOf2(n: number): number {
    if (n <= 0 || n > (1 << 30)) {
      throw new Error(`n is invalid: ${n}`);
    }
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    n -= n >> 1;
    return n;
  }
}
