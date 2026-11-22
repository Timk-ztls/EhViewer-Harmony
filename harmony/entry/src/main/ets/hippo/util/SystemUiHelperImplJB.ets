/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0505   上游: com/hippo/util/SystemUiHelperImplJB.java（74 行，AOSP）
 * 目标   : harmony/entry/src/main/ets/hippo/util/SystemUiHelperImplJB.ets
 *
 * 只保留 flag 位运算。JB 档在父类基础上**按 level 叠加 layout 标志**：
 *   show → super.show | (level>=HIDE_STATUS_BAR ? LAYOUT_STABLE|LAYOUT_FULLSCREEN
 *                                                     [: |LAYOUT_HIDE_NAVIGATION if >=LEAN_BACK])
 *   hide → super.hide | (同样条件再叠 FULLSCREEN)
 * `onSystemUiShown/Hidden` 里的 ActionBar 操作是 UI → ui-widget（这里只留 `shouldToggleActionBar` 判定）。
 */

import { SystemUiHelper } from './SystemUiHelper';
import { SystemUiHelperImplICS } from './SystemUiHelperImplICS';

export class SystemUiHelperImplJB extends SystemUiHelperImplICS {

  constructor(level: number, flags: number) {
    super(level, flags);
  }

  createShowFlags(): number {
    let flag: number = super.createShowFlags();
    if (this.level >= SystemUiHelper.LEVEL_HIDE_STATUS_BAR) {
      flag |= SystemUiHelper.SYSTEM_UI_FLAG_LAYOUT_STABLE | SystemUiHelper.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN;
      if (this.level >= SystemUiHelper.LEVEL_LEAN_BACK) {
        flag |= SystemUiHelper.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION;
      }
    }
    return flag;
  }

  createHideFlags(): number {
    let flag: number = super.createHideFlags();
    if (this.level >= SystemUiHelper.LEVEL_HIDE_STATUS_BAR) {
      flag |= SystemUiHelper.SYSTEM_UI_FLAG_LAYOUT_STABLE
        | SystemUiHelper.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        | SystemUiHelper.SYSTEM_UI_FLAG_FULLSCREEN;
      if (this.level >= SystemUiHelper.LEVEL_LEAN_BACK) {
        flag |= SystemUiHelper.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION;
      }
    }
    return flag;
  }

  /**
   * 对应上游 `onSystemUiShown/Hidden` 里对 ActionBar 的处理：
   * **只有 LEVEL_LOW_PROFILE 才手动 show/hide ActionBar**（其它级别由系统处理）。
   */
  shouldToggleActionBar(): boolean {
    return this.level === SystemUiHelper.LEVEL_LOW_PROFILE;
  }
}