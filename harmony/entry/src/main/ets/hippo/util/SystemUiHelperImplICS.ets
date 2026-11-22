/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0504   上游: com/hippo/util/SystemUiHelperImplICS.java（74 行，AOSP）
 * 目标   : harmony/entry/src/main/ets/hippo/util/SystemUiHelperImplICS.ets
 *
 * 只保留 flag 位运算（UI 部分归 ui-widget）。ICS 档引入 LOW_PROFILE / HIDE_NAVIGATION：
 *   show  → SYSTEM_UI_FLAG_VISIBLE (0)
 *   test  → level >= LEAN_BACK ? HIDE_NAVIGATION : LOW_PROFILE   ← **随 level 变化**
 *   hide  → LOW_PROFILE | (level >= LEAN_BACK ? HIDE_NAVIGATION : 0)
 */

import { SystemUiHelper } from './SystemUiHelper';
import { SystemUiHelperImplHC } from './SystemUiHelperImplHC';

export class SystemUiHelperImplICS extends SystemUiHelperImplHC {

  constructor(level: number, flags: number) {
    super(level, flags);
  }

  createShowFlags(): number {
    return SystemUiHelper.SYSTEM_UI_FLAG_VISIBLE;
  }

  createTestFlags(): number {
    if (this.level >= SystemUiHelper.LEVEL_LEAN_BACK) {
      // Intentionally override test flags.（上游原注释）
      return SystemUiHelper.SYSTEM_UI_FLAG_HIDE_NAVIGATION;
    }
    return SystemUiHelper.SYSTEM_UI_FLAG_LOW_PROFILE;
  }

  createHideFlags(): number {
    let flag: number = SystemUiHelper.SYSTEM_UI_FLAG_LOW_PROFILE;
    if (this.level >= SystemUiHelper.LEVEL_LEAN_BACK) {
      flag |= SystemUiHelper.SYSTEM_UI_FLAG_HIDE_NAVIGATION;
    }
    return flag;
  }
}