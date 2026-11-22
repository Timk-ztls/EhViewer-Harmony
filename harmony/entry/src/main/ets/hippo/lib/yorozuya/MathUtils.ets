/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0414   上游: com/hippo/lib/yorozuya/MathUtils.java（339 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/MathUtils.ets
 *
 * 上游实际调用面（git grep）：ceilDivide / clamp / coverageRadius / delerp / hammingWeight /
 *   lerp / max / nextPowerOf2 / positiveModulo / radians / random。其余方法一并移植保持 API 完整。
 *
 * 平台差异（方案 §5-7 无重载 —— 本类是全项目重载最密的一个，共 26 个方法签名）：
 *  1. int/float 参数在 ArkTS 都是 number，Java 里靠重载区分的两组可直接合并为单方法：
 *       max(a,b) / max(int,int)                     → max(a: number, b: number)
 *       max(a,b,c) / max(int,int,int)               → max(a, b, c?: number)   ← 三参用可选参
 *       max(float...) / max(int...)                 → maxOf(values: number[])
 *       min 同理                                     → min / minOf
 *       clamp(int,int,int)/clamp(float...)/clamp(long...) → clamp(x, min, max)
 *       ceilDivide(int,int) / ceilDivide(long,long) → ceilDivide(a, b)
 *       delerp(int,int,int) / delerp(float...)      → delerp(start, stop, value)
 *  2. **必须拆开的两个**（返回语义不同，合并会改变行为）：
 *       lerp(int,int,float) 返回 int（截断）  → lerpInt(start, stop, amount)
 *       lerp(float,float,float) 返回 float    → lerp(start, stop, amount)
 *       random(int) 返回 int（截断）          → randomInt(howbig)
 *       random(int,int) 返回 int              → randomIntRange(howsmall, howbig)
 *       random(float) / random(float,float)   → random(howbig) / randomRange(howsmall, howbig)
 *  3. dist(4 参) / dist(6 参) → dist(...) / dist3(...)
 *     near(5 参) / near(7 参) → near(...) / near3(...)
 *     mag(2 参) / mag(3 参)   → mag(...) / mag3(...)
 *  4. **hammingWeight 必须用 Math.imul**：Java 的 `(n & 0x0F0F0F0F) * 0x01010101` 是 int32 乘法
 *     （溢出后回绕），JS/ArkTS 的 `*` 是双精度乘法，0x0F0F0F0F * 0x01010101 ≈ 2.7e17 > 2^53
 *     会丢精度。改用 Math.imul 复刻 int32 语义（金样本里有 0xFFFFFFFF/0xAAAAAAAA 对照）。
 *  5. `(int)` 强转 → Math.trunc（Java 向零截断，JS Math.floor 对负数是向下取整，不能混用）。
 *  6. java.util.Random → 本文件内置 xorshift32 伪随机（randomSeed 可复现）。**序列值与
 *     java.util.Random 不同**（上游只用它做随机页跳转/随机采样，不依赖具体序列）；
 *     若将来有"同种子必须同序列"的需求，需改为移植 java.util.Random 的 LCG（48 位）。
 *  7. float → number：Java float 是 32 位，ArkTS number 是 64 位双精度，中间结果精度更高。
 *     上游这些函数用于手势/布局/纹理尺寸，更高精度不改变可观察行为；
 *     唯一需要注意的是"用相等比较 float 结果"的地方（上游无）。
 *  8. IllegalArgumentException → Error，消息串逐字保留（"Empty argument" / "n is invalid: N"）。
 */

export class MathUtils {

  private static readonly DEG_TO_RAD: number = 3.1415926 / 180.0;
  private static readonly RAD_TO_DEG: number = 180.0 / 3.1415926;

  /** xorshift32 状态（见差异 6） */
  private static sSeed: number = 0x9E3779B9;

  static abs(v: number): number {
    return v > 0 ? v : -v;
  }

  static log(a: number): number {
    return Math.log(a);
  }

  static exp(a: number): number {
    return Math.exp(a);
  }

  static pow(a: number, b: number): number {
    return Math.pow(a, b);
  }

  // ── max / min（见差异 1、3） ────────────────────────────────────────────

  static max(a: number, b: number, c?: number): number {
    if (c === undefined) {
      return a > b ? a : b;
    }
    return a > b ? (a > c ? a : c) : (b > c ? b : c);
  }

  static maxOf(values: number[]): number {
    const length: number = values.length;
    if (length <= 0) {
      throw new Error('Empty argument');
    }
    let n: number = values[0];
    for (let i = 1; i < length; i++) {
      if (values[i] > n) {
        n = values[i];
      }
    }
    return n;
  }

  static min(a: number, b: number, c?: number): number {
    if (c === undefined) {
      return a < b ? a : b;
    }
    return a < b ? (a < c ? a : c) : (b < c ? b : c);
  }

  static minOf(values: number[]): number {
    const length: number = values.length;
    if (length <= 0) {
      throw new Error('Empty argument');
    }
    let n: number = values[0];
    for (let i = 1; i < length; i++) {
      if (values[i] < n) {
        n = values[i];
      }
    }
    return n;
  }

  // ── 距离 / 模长 ──────────────────────────────────────────────────────────

  static dist(x1: number, y1: number, x2: number, y2: number): number {
    const x: number = x2 - x1;
    const y: number = y2 - y1;
    return Math.hypot(x, y);
  }

  static dist3(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number): number {
    const x: number = x2 - x1;
    const y: number = y2 - y1;
    const z: number = z2 - z1;
    return Math.sqrt(x * x + y * y + z * z);
  }

  static near(x1: number, y1: number, x2: number, y2: number, slop: number): boolean {
    return MathUtils.dist(x1, y1, x2, y2) < slop;
  }

  static near3(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number,
    slop: number): boolean {
    return MathUtils.dist3(x1, y1, z1, x2, y2, z2) < slop;
  }

  static mag(a: number, b: number): number {
    return Math.hypot(a, b);
  }

  static mag3(a: number, b: number, c: number): number {
    return Math.sqrt(a * a + b * b + c * c);
  }

  static sq(v: number): number {
    return v * v;
  }

  static cross(v1x: number, v1y: number, v2x: number, v2y: number): number {
    return v1x * v2y - v1y * v2x;
  }

  // ── 角度 ────────────────────────────────────────────────────────────────

  static radians(degrees: number): number {
    return degrees * MathUtils.DEG_TO_RAD;
  }

  static degrees(radians: number): number {
    return radians * MathUtils.RAD_TO_DEG;
  }

  static acos(value: number): number {
    return Math.acos(value);
  }

  static asin(value: number): number {
    return Math.asin(value);
  }

  static atan(value: number): number {
    return Math.atan(value);
  }

  static atan2(a: number, b: number): number {
    return Math.atan2(a, b);
  }

  static tan(angle: number): number {
    return Math.tan(angle);
  }

  // ── 插值 ────────────────────────────────────────────────────────────────

  /** Java lerp(int start, int stop, float amount) —— 结果向零截断 */
  static lerpInt(start: number, stop: number, amount: number): number {
    return start + Math.trunc((stop - start) * amount);
  }

  /** Java lerp(float start, float stop, float amount) */
  static lerp(start: number, stop: number, amount: number): number {
    return start + (stop - start) * amount;
  }

  static delerp(start: number, stop: number, value: number): number {
    if (stop === start) {
      return 1.0;
    } else {
      return (value - start) / (stop - start);
    }
  }

  static norm(start: number, stop: number, value: number): number {
    return (value - start) / (stop - start);
  }

  static map(minStart: number, minStop: number, maxStart: number, maxStop: number,
    value: number): number {
    return maxStart + (maxStart - maxStop) * ((value - minStart) / (minStop - minStart));
  }

  // ── 取整 / 位运算 ────────────────────────────────────────────────────────

  /**
   * Returns the input value x clamped to the range [min, max].
   */
  static clamp(x: number, min: number, max: number): number {
    if (x > max) {
      return max;
    }
    if (x < min) {
      return min;
    }
    return x;
  }

  /**
   * Returns the next power of two.
   */
  static nextPowerOf2(n: number): number {
    if (n <= 0 || n > (1 << 30)) {
      throw new Error(`n is invalid: ${n}`);
    }
    let x: number = n - 1;
    x |= x >> 16;
    x |= x >> 8;
    x |= x >> 4;
    x |= x >> 2;
    x |= x >> 1;
    return x + 1;
  }

  /**
   * Returns the previous power of two.
   */
  static previousPowerOf2(n: number): number {
    if (n <= 0 || n > (1 << 30)) {
      throw new Error(`n is invalid: ${n}`);
    }
    let x: number = n;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    return x - (x >> 1);
  }

  /**
   * 32 位整数的 popcount。注意用 Math.imul 复刻 Java 的 int32 乘法（见差异 4）。
   */
  static hammingWeight(n: number): number {
    let x: number = n - ((n >>> 1) & 0x55555555);
    x = (x & 0x33333333) + ((x >>> 2) & 0x33333333);
    return (Math.imul((x + (x >>> 4)) & 0x0F0F0F0F, 0x01010101) >>> 24);
  }

  /**
   * divide and ceil
   */
  static ceilDivide(a: number, b: number): number {
    return Math.trunc((a + b - 1) / b);
  }

  /**
   * Get coverage radius of a area
   */
  static coverageRadius(w: number, h: number, x: number, y: number): number {
    let x2: number;
    let y2: number;
    if (x > w / 2) {
      x2 = 0;
    } else {
      x2 = w;
    }
    if (y > h / 2) {
      y2 = 0;
    } else {
      y2 = h;
    }
    return MathUtils.dist(x, y, x2, y2);
  }

  static positiveModulo(x: number, y: number): number {
    let result: number = x % y;
    if (x < 0) {
      result += y;
    }
    return result;
  }

  static negativeModulo(x: number, y: number): number {
    let result: number = x % y;
    if (x > 0) {
      result -= y;
    }
    return result;
  }

  // ── 伪随机（见差异 2、6） ────────────────────────────────────────────────

  /** xorshift32，返回 [0,1) 的 double */
  private static nextFloat(): number {
    let x: number = MathUtils.sSeed;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    MathUtils.sSeed = x >>> 0;
    return MathUtils.sSeed / 4294967296;
  }

  /** [0, howbig) 的整数 */
  static randomInt(howbig: number): number {
    return Math.trunc(MathUtils.nextFloat() * howbig);
  }

  /** [howsmall, howbig) 的整数 */
  static randomIntRange(howsmall: number, howbig: number): number {
    if (howsmall >= howbig) {
      return howsmall;
    }
    return MathUtils.lerpInt(howsmall, howbig, MathUtils.nextFloat());
  }

  /** [0, howbig) 的浮点数 */
  static random(howbig: number): number {
    return MathUtils.nextFloat() * howbig;
  }

  /** [howsmall, howbig) 的浮点数 */
  static randomRange(howsmall: number, howbig: number): number {
    if (howsmall >= howbig) {
      return howsmall;
    }
    return MathUtils.lerp(howsmall, howbig, MathUtils.nextFloat());
  }

  static randomSeed(seed: number): void {
    // 防止全 0 状态（xorshift 的固定点）
    MathUtils.sSeed = (seed === 0) ? 0x9E3779B9 : (seed >>> 0);
  }
  // ── 32 位转换（跨模块通用，net-parse 在 gl-render 上两次踩到）───────────
  //
  // 背景：Java 的 `int` 是 **32 位有符号**，`0xFF00FF00` 字面量在 Java 里是 `-16711936`；
  // JS 的 number 是双精度，同样的值是 `4278255360`。两块代码交换颜色/位掩码时必须显式转换，
  // 否则「同一个颜色判等失败」「掩码位全错」这类 bug **不报错、只是结果不对**。
  //
  // 放在 MathUtils 而不是各模块自己写（陷阱 76：同一算法只能有一处实现）。

  /**
   * 32 位**有符号**转换，等价 Java `int` 语义（`0xFF00FF00 → -16711936`）。
   * `| 0` 在 JS 里就是 ToInt32。
   */
  static toSigned32(v: number): number {
    return v | 0;
  }

  /**
   * 32 位**无符号**转换（`0xFF00FF00 → 4278255360`）。
   * `>>> 0` 在 JS 里就是 ToUint32（结果仍是 number，但值域 [0, 2^32)）。
   */
  static toUnsigned32(v: number): number {
    return v >>> 0;
  }
}