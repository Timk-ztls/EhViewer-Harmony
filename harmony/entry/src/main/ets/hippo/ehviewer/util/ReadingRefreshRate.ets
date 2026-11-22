/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0282   上游: com/hippo/ehviewer/util/ReadingRefreshRate.java（79 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/util/ReadingRefreshRate.ets
 *
 * `Settings.getReadingRefreshRate()` 会调 `ReadingRefreshRate.sanitize(...)` —— 本文件补齐这条链。
 *
 * 平台差异：
 *  1. `Build.VERSION.SDK_INT >= R` → 鸿蒙 API 20 **始终支持可变刷新率**，故 `isSupported()` 返回 true
 *     （保留方法名让上游调用点 1:1）。
 *  2. `Display.Mode` → 最小结构 `DisplayModeLike {physicalWidth, physicalHeight, refreshRate}`（注入），
 *     由 ui-scene 用 `@ohos.display` 的 supportedMode 适配。**算法逐行照搬**。
 *  3. `float` → `number`；`hz > targetHz + 0.1f` 的容差逐字保留（浮点比较必须有容差）。
 */

/** 上游 `Display.Mode` 用到的三个字段 */
export interface DisplayModeLike {
  physicalWidth: number;
  physicalHeight: number;
  refreshRate: number;
}

export class ReadingRefreshRate {

  static readonly SYSTEM_DEFAULT: number = 0;
  static readonly DISPLAY_MAX: number = -1;

  /** 上游：`Build.VERSION.SDK_INT >= R`；鸿蒙 API 20 恒为 true */
  static isSupported(): boolean {
    return true;
  }

  /** 只允许 DISPLAY_MAX / SYSTEM_DEFAULT / 60 / 90 / 120，其余回落 SYSTEM_DEFAULT */
  static sanitize(value: number): number {
    if (value === ReadingRefreshRate.DISPLAY_MAX || value === ReadingRefreshRate.SYSTEM_DEFAULT
      || value === 60 || value === 90 || value === 120) {
      return value;
    }
    return ReadingRefreshRate.SYSTEM_DEFAULT;
  }

  /**
   * 对应上游 `findBestMode(display, settingHz)`。
   * @returns 选中的 mode；**null** 表示"不干预"（display 为空 / SYSTEM_DEFAULT / 无模式）
   */
  static findBestMode(modes: DisplayModeLike[] | null, current: DisplayModeLike | null,
    settingHz: number): DisplayModeLike | null {
    if (modes === null || current === null || settingHz === ReadingRefreshRate.SYSTEM_DEFAULT) {
      return null;
    }
    if (modes.length === 0) {
      return null;
    }
    const width: number = current.physicalWidth;
    const height: number = current.physicalHeight;

    let maxHz: number = ReadingRefreshRate.maxRefreshRate(modes, width, height, true);
    if (maxHz <= 0) {
      maxHz = ReadingRefreshRate.maxRefreshRate(modes, width, height, false);
    }
    if (maxHz <= 0) {
      return current;
    }

    const targetHz: number = (settingHz === ReadingRefreshRate.DISPLAY_MAX) ? maxHz : Math.min(settingHz, maxHz);
    let best: DisplayModeLike | null = null;
    let bestHz: number = -1;
    let foundSameRes: boolean = false;
    for (let i = 0; i < modes.length; i++) {
      const mode: DisplayModeLike = modes[i];
      const sameRes: boolean = mode.physicalWidth === width && mode.physicalHeight === height;
      const hz: number = mode.refreshRate;
      if (hz > targetHz + 0.1) {
        continue;
      }
      if (sameRes) {
        if (!foundSameRes || hz > bestHz) {
          foundSameRes = true;
          bestHz = hz;
          best = mode;
        }
      } else if (!foundSameRes && hz > bestHz) {
        bestHz = hz;
        best = mode;
      }
    }
    return best !== null ? best : current;
  }

  /** 对应上游 `resolveHz`：SYSTEM_DEFAULT → 0（跟随系统），否则取选中模式的 Hz */
  static resolveHz(modes: DisplayModeLike[] | null, current: DisplayModeLike | null, settingHz: number): number {
    if (settingHz === ReadingRefreshRate.SYSTEM_DEFAULT) {
      return 0;
    }
    const mode: DisplayModeLike | null = ReadingRefreshRate.findBestMode(modes, current, settingHz);
    return (mode !== null) ? mode.refreshRate : 0;
  }

  private static maxRefreshRate(modes: DisplayModeLike[], width: number, height: number,
    matchRes: boolean): number {
    let maxHz: number = 0;
    for (let i = 0; i < modes.length; i++) {
      const mode: DisplayModeLike = modes[i];
      if (matchRes && (mode.physicalWidth !== width || mode.physicalHeight !== height)) {
        continue;
      }
      maxHz = Math.max(maxHz, mode.refreshRate);
    }
    return maxHz;
  }
}