/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0412   上游: com/hippo/lib/yorozuya/LayoutUtils.java（59 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/LayoutUtils.ets
 *
 * 平台差异：
 *  1. 上游每个方法都收 `Context context` 只为取 `context.getResources().getDisplayMetrics()`
 *     的 density / scaledDensity。ArkTS 无 Context→DisplayMetrics 通道，改由 `@ohos.display`
 *     直接取：densityPixels / scaledDensity（SDK 20 `@ohos.display.d.ts` 确认这两个字段存在）。
 *     **签名随之去掉 context 形参**：`dp2pix(context, dp)` → `dp2pix(dp)`。
 *     25 处调用点改写时删掉第一个实参即可。
 *  2. `(int)(x * density + 0.5f)` 的强转 → Math.trunc（入参恒为正，等价于向下取整；
 *     不用 Math.floor 以免负数语义漂移）。
 *  3. density 结果做静态缓存（`getDefaultDisplaySync()` 是跨进程调用，布局热路径不该每次问）。
 *     缓存不随折叠屏/分屏形态变化而刷新——若后续需要，调用 `invalidateMetrics()` 重新读取。
 *     该静态缓存只存两个 number，不持有 Ability/Context，不触发方案 §5-3 的静态变量约束。
 */

import display from '@ohos.display';

export class LayoutUtils {

  private static sDensity: number = -1;
  private static sScaledDensity: number = -1;

  private static density(): number {
    if (LayoutUtils.sDensity < 0) {
      LayoutUtils.invalidateMetrics();
    }
    return LayoutUtils.sDensity;
  }

  private static scaledDensity(): number {
    if (LayoutUtils.sScaledDensity < 0) {
      LayoutUtils.invalidateMetrics();
    }
    return LayoutUtils.sScaledDensity;
  }

  /** 重新读取当前显示器的 density / scaledDensity（折叠屏形态变化后可调用） */
  static invalidateMetrics(): void {
    const d: display.Display = display.getDefaultDisplaySync();
    LayoutUtils.sDensity = d.densityPixels;
    LayoutUtils.sScaledDensity = d.scaledDensity;
  }

  /**
   * dp conversion to pix
   *
   * @param dp The value you want to conversion
   * @return value in pix
   */
  static dp2pix(dp: number): number {
    return Math.trunc(dp * LayoutUtils.density() + 0.5);
  }

  /**
   * pix conversion to dp
   *
   * @param pix The value you want to conversion
   * @return value in dp
   */
  static pix2dp(pix: number): number {
    return pix / LayoutUtils.density();
  }

  /**
   * sp conversion to pix
   *
   * @param sp The value you want to conversion
   * @return value in pix
   */
  static sp2pix(sp: number): number {
    return Math.trunc(sp * LayoutUtils.scaledDensity() + 0.5);
  }

  /**
   * pix conversion to sp
   *
   * @param pix The value you want to conversion
   * @return value in sp
   */
  static pix2sp(pix: number): number {
    return pix / LayoutUtils.scaledDensity();
  }
}
