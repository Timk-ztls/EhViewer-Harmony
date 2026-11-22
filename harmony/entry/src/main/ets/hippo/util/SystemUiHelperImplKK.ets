/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0506   上游: com/hippo/util/SystemUiHelperImplKK.java（47 行，AOSP）
 * 目标   : harmony/entry/src/main/ets/hippo/util/SystemUiHelperImplKK.ets
 *
 * 唯一的增量：**IMMERSIVE 级别**在 hide 时额外加 IMMERSIVE/IMMERSIVE_STICKY 位
 * （由 FLAG_IMMERSIVE_STICKY 决定加哪一个）。上游注释解释了为什么只在 4.4+ 做：
 * "Applying HIDE_NAVIGATION without IMMERSIVE prevents the activity from accepting all touch
 *  events" —— 即不加 IMMERSIVE 的话，隐藏导航栏会导致**收不到触摸事件**（用户可感知的死界面）。
 */

import { SystemUiHelper } from './SystemUiHelper';
import { SystemUiHelperImplJB } from './SystemUiHelperImplJB';

export class SystemUiHelperImplKK extends SystemUiHelperImplJB {

  constructor(level: number, flags: number) {
    super(level, flags);
  }

  createHideFlags(): number {
    let flag: number = super.createHideFlags();
    if (this.level === SystemUiHelper.LEVEL_IMMERSIVE) {
      // If the client requested immersive mode, and we're on Android 4.4 or later,
      // add relevant flags. Applying HIDE_NAVIGATION without IMMERSIVE prevents the
      // activity from accepting all touch events, so we only do this on Android 4.4
      // and later (where IMMERSIVE is present).  —— 上游原注释
      flag |= ((this.flags & SystemUiHelper.FLAG_IMMERSIVE_STICKY) !== 0)
        ? SystemUiHelper.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        : SystemUiHelper.SYSTEM_UI_FLAG_IMMERSIVE;
    }
    return flag;
  }
}