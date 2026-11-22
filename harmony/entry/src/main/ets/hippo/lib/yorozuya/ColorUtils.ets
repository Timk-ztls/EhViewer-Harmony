/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0407   上游: com/hippo/lib/yorozuya/ColorUtils.java（29 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/ColorUtils.ets
 *
 * 平台差异：无。Java int 的 0xAARRGGBB 布局与 ArkTS number 位运算语义一致
 *   （ArkTS 的 & | >>> 均为 int32 位运算），alpha 取最高字节的判断结果完全相同。
 * 调用方：gl-render 的 ColorTexture.isOpaque()（跨模块契约，故本类必须移植而非标 na）。
 */

export class ColorUtils {
  /**
   * Check is it the color opaque
   *
   * @param color the color (0xAARRGGBB)
   * @return true if it is opaque
   */
  static isOpaque(color: number): boolean {
    return (color >>> 24) === 0xFF;
  }
}