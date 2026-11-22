/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0503   上游: com/hippo/util/SystemUiHelperImplHC.java（74 行，AOSP）
 * 目标   : harmony/entry/src/main/ets/hippo/util/SystemUiHelperImplHC.ets
 *
 * 只保留 flag 位运算；`mDecorView.setSystemUiVisibility(...)`、
 * `setOnSystemUiVisibilityChangeListener`、`ActionBar.show/hide` 是 Android UI → ui-widget。
 *
 * HC 档的 flag 极简：show → STATUS_BAR_VISIBLE(0)，hide → STATUS_BAR_HIDDEN(1)，
 * test → STATUS_BAR_HIDDEN。（Android 11–13 只有这两个"状态栏可见性"标志。）
 */

import { SystemUiHelper } from './SystemUiHelper';

export class SystemUiHelperImplHC {

  protected level: number;
  protected flags: number;

  constructor(level: number, flags: number) {
    this.level = level;
    this.flags = flags;
  }

  createShowFlags(): number {
    return SystemUiHelper.STATUS_BAR_VISIBLE;
  }

  createHideFlags(): number {
    return SystemUiHelper.STATUS_BAR_HIDDEN;
  }

  createTestFlags(): number {
    return SystemUiHelper.STATUS_BAR_HIDDEN;
  }

  /** 上游 `onSystemUiVisibilityChange`：`(visibility & createTestFlags()) != 0` → 隐藏 */
  isHiddenByVisibility(visibility: number): boolean {
    return (visibility & this.createTestFlags()) !== 0;
  }
}