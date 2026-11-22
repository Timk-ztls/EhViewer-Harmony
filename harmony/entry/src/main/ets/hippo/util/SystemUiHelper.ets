/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0502   上游: com/hippo/util/SystemUiHelper.java（236 行，AOSP 代码）
 * 目标   : harmony/entry/src/main/ets/hippo/util/SystemUiHelper.ets
 *
 * 【D-033 拆分】上游是"按 API 版本选 SystemUiHelperImpl 子类 + Handler 延时隐藏"的 UI 助手。
 * 其中：
 *   · `Activity.getWindow()/getDecorView()/getActionBar()`、`Handler.postDelayed`、
 *     `View.setOnSystemUiVisibilityChangeListener` → **纯 UI，归 ui-widget**
 *   · 鸿蒙侧对应能力：`window.Window.setWindowSystemBarEnable` / `setWindowLayoutFullScreen`
 *     / `window.setWindowSystemBarProperties`（由 ui-widget 调用）
 *   · **留下的是真正的纯逻辑**：四个 LEVEL 的 `createShowFlags / createHideFlags /
 *     createTestFlags` 位运算 —— 这是"哪种隐藏级别该置哪些 SYSTEM_UI_FLAG"的全部知识，
 *     可完全单测（见 SystemUiHelperImpl*.ets）。
 *
 * 平台差异：
 *  1. `View.SYSTEM_UI_FLAG_*` 是 Android 常量，鸿蒙没有对应位标志 → **镜像常量值**并注明出处，
 *     由 ui-widget 把"语义"翻译成 `window` API 调用（例如 FULLSCREEN 位 → setWindowLayoutFullScreen(true)）。
 *  2. `Handler` 延时隐藏 → `SystemUiHelper.delayHide(ms)` 用 `setTimeout`，返回可取消的 id
 *     （上游 `removeQueuedRunnables()` 的等价物）。
 *  3. `toggle()` 逐行照搬：**直接调 mImpl.isShowing() 判断**（上游此处**不** removeQueuedRunnables，
 *     与 show/hide/delayHide 不同 —— 这个不一致是上游原样，照搬）。
 */

import { SystemUiHelperImplKK } from './SystemUiHelperImplKK';

/** 版本档位：对应上游 base/HC/ICS/JB/KK 五个实现 */
export enum SystemUiVersion {
  /** API <= 10，上游 SystemUiHelperImplBase */
  BASE = 0,
  /** API 11-13，上游 SystemUiHelperImplHC */
  HC = 1,
  /** API 14-15，上游 SystemUiHelperImplICS */
  ICS = 2,
  /** API 16-18，上游 SystemUiHelperImplJB */
  JB = 3,
  /** API >= 19，上游 SystemUiHelperImplKK */
  KK = 4
}

export class SystemUiHelper {

  static readonly LEVEL_LOW_PROFILE: number = 0;
  static readonly LEVEL_HIDE_STATUS_BAR: number = 1;
  static readonly LEVEL_LEAN_BACK: number = 2;
  static readonly LEVEL_IMMERSIVE: number = 3;

  static readonly FLAG_LAYOUT_IN_SCREEN_OLDER_DEVICES: number = 0x1;
  static readonly FLAG_IMMERSIVE_STICKY: number = 0x2;

  // 镜像 android.view.View 的 SYSTEM_UI_FLAG_*（ui-widget 负责翻译成 window API）
  static readonly SYSTEM_UI_FLAG_VISIBLE: number = 0;
  static readonly SYSTEM_UI_FLAG_LOW_PROFILE: number = 0x1;
  static readonly SYSTEM_UI_FLAG_HIDE_NAVIGATION: number = 0x2;
  static readonly SYSTEM_UI_FLAG_FULLSCREEN: number = 0x4;
  static readonly SYSTEM_UI_FLAG_LAYOUT_STABLE: number = 0x100;
  static readonly SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION: number = 0x200;
  static readonly SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN: number = 0x400;
  static readonly SYSTEM_UI_FLAG_IMMERSIVE: number = 0x800;
  static readonly SYSTEM_UI_FLAG_IMMERSIVE_STICKY: number = 0x1000;
  // 镜像 android.view.View 的 STATUS_BAR_VISIBLE / STATUS_BAR_HIDDEN（HC 档用）
  static readonly STATUS_BAR_VISIBLE: number = 0;
  static readonly STATUS_BAR_HIDDEN: number = 0x1;

  /**
   * 对应上游构造器里的 `new SystemUiHelperImplKK(activity, level, flags, listener)` ——
   * **上游恒用 KK 实现**（`@TargetApi(KITKAT)`，minSdk 已是 19+）。这里保留版本档位枚举，
   * 但 `createImpl` 与上游一致地返回 KK 档。
   */
  static createImpl(level: number, flags: number): SystemUiHelperImplKK {
    return new SystemUiHelperImplKK(level, flags);
  }

  /** 上游 `toggle()`：**不**清理延时任务（与 show/hide 不同，照搬该不一致） */
  static toggle(isShowing: boolean): boolean {
    return !isShowing;
  }
}