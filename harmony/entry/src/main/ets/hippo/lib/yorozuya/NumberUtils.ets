/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0416   上游: com/hippo/lib/yorozuya/NumberUtils.java（80 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/NumberUtils.ets
 *
 * 平台差异（关键：不能让解析变宽松）：
 *  1. Java Integer.parseInt / Long.parseLong 是**严格**解析：只允许可选正负号 + ASCII 数字，
 *     越界抛 NumberFormatException。JS 的 Number()/parseInt() 会接受 "12abc"、""、十六进制前缀等，
 *     直接替换会把非法输入静默接受（上游这类值来自设置项/DB/网络，变宽松=行为改变）。
 *     故本实现用严格正则 + 范围校验复刻 Java 语义，非法时返回 defaultValue。
 *  2. parseLongSafely 的 long → number：可精确表示到 2^53-1。超出该范围时 Java 能返回精确值
 *     而 ArkTS 不能 —— 本实现对 |v| > 2^53-1 视为非法并返回 default（宁可回退也不返回错误数值）。
 *  3. Float.parseFloat 的 Java 语义（接受 1.5f/1.5d 后缀、NaN、Infinity、十六进制浮点）
 *     只保留常用子集：十进制小数 + 指数 + f/F/d/D 后缀 + NaN/Infinity。十六进制浮点
 *     与 Unicode 数字不接受（上游无此类输入）。差异登记在 MR。
 */

export class NumberUtils {

  private static readonly INT_PATTERN: RegExp = new RegExp('^[+-]?[0-9]+$');
  private static readonly FLOAT_PATTERN: RegExp =
    new RegExp('^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?[fFdD]?$');
  private static readonly LONG_SAFE: number = 9007199254740991; // 2^53 - 1

  /**
   * 0 for false, Non 0 for true
   */
  static int2boolean(integer: number): boolean {
    return integer !== 0;
  }

  /**
   * false for 0, true for 1
   */
  static boolean2int(bool: boolean): number {
    return bool ? 1 : 0;
  }

  /**
   * Do not throw NumberFormatException, use default value（Java Integer.parseInt 严格语义）
   */
  static parseIntSafely(str: string, defaultValue: number): number {
    if (str === null || str === undefined) {
      return defaultValue;
    }
    if (!NumberUtils.INT_PATTERN.test(str)) {
      return defaultValue;
    }
    const v: number = Number(str);
    if (!Number.isFinite(v) || v > 2147483647 || v < -2147483648) {
      return defaultValue;
    }
    return v;
  }

  /**
   * Do not throw NumberFormatException, use default value（Java Long.parseLong 严格语义）
   */
  static parseLongSafely(str: string, defaultValue: number): number {
    if (str === null || str === undefined) {
      return defaultValue;
    }
    if (!NumberUtils.INT_PATTERN.test(str)) {
      return defaultValue;
    }
    const v: number = Number(str);
    if (!Number.isFinite(v) || Math.abs(v) > NumberUtils.LONG_SAFE) {
      return defaultValue;
    }
    return v;
  }

  /**
   * Do not throw NumberFormatException, use default value（Java Float.parseFloat 常用子集）
   */
  static parseFloatSafely(str: string, defaultValue: number): number {
    if (str === null || str === undefined) {
      return defaultValue;
    }
    if (str === 'NaN') {
      return NaN;
    }
    if (str === 'Infinity' || str === '+Infinity') {
      return Number.POSITIVE_INFINITY;
    }
    if (str === '-Infinity') {
      return Number.NEGATIVE_INFINITY;
    }
    if (!NumberUtils.FLOAT_PATTERN.test(str)) {
      return defaultValue;
    }
    let body: string = str;
    const last: string = body.charAt(body.length - 1);
    if (last === 'f' || last === 'F' || last === 'd' || last === 'D') {
      body = body.substring(0, body.length - 1);
    }
    const v: number = Number(body);
    if (Number.isNaN(v)) {
      return defaultValue;
    }
    return v;
  }
}