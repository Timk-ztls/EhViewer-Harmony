/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0161   上游: com/hippo/ehviewer/GetText.java（34 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/GetText.ets
 *
 * 平台差异：
 *  1. **资源寻址方式变了**：上游用 `Resources.getString(@StringRes int id)`，id 来自 R.string.*
 *     编译期常量。ArkTS 的 ResourceManager 有两种入口：
 *       `getStringSync(resId: number)`   ← 需要数值 id（由 `$r('app.string.xxx')` 或
 *                                            `getStringByName` 系列的 name→id 映射得到）
 *       `getStringByNameSync(name: string)` ← 直接按名称，推荐
 *     本实现两种都支持：传 string 走 name、传 number 走 id。
 *     **调用点改写**：`GetText.getString(R.string.error_timeout)` →
 *     `GetText.getString('error_timeout')`（资源名即 `resources/base/element/string.json` 的 key）。
 *  2. 两个 Java 重载 `getString(int)` / `getString(int, Object...)` → ArkTS 无重载：
 *     `getString(resId)` 与 **`getStringFormat(resId, formatArgs)`**。
 *  3. `Context.getApplicationContext().getResources()` → `context.resourceManager`
 *     （ArkTS 的 ResourceManager 本身就是应用级）；需启动时 `GetText.initialize(context)`。
 *  4. 取不到资源时返回 **空串**（Java 会抛 NotFoundException）；正常路径零差异，
 *     且避免"某个 string 名字写错导致整条 UI 崩"。
 */

import common from '@ohos.app.ability.common';
import resourceManager from '@ohos.resourceManager';

export class GetText {

  private static sResMgr: resourceManager.ResourceManager | null = null;

  /** 对应上游 initialize(Context) */
  static initialize(context: common.Context): void {
    GetText.sResMgr = context.resourceManager;
  }

  static isInitialized(): boolean {
    return GetText.sResMgr !== null;
  }

  /**
   * 对应上游 getString(@StringRes int id)。
   * 支持 string（资源名，推荐）与 number（数值资源 id）。
   */
  static getString(resId: string | number): string {
    const mgr: resourceManager.ResourceManager | null = GetText.sResMgr;
    if (mgr === null) {
      return '';
    }
    try {
      if (typeof resId === 'string') {
        return mgr.getStringByNameSync(resId);
      }
      return mgr.getStringSync(resId);
    } catch (e) {
      return '';
    }
  }

  /**
   * 对应上游 getString(@StringRes int id, Object... formatArgs)。
   * formatArgs 顺序与上游一致（ArkTS 的 getStringSync 同样按占位符顺序替换）。
   */
  static getStringFormat(resId: string | number, formatArgs: Array<string | number>): string {
    const mgr: resourceManager.ResourceManager | null = GetText.sResMgr;
    if (mgr === null) {
      return '';
    }
    try {
      if (typeof resId === 'string') {
        // SDK 20 的 getStringSync 只有 (resId, ...args) 与 (Resource, ...args) 两种重载，
        // 没有 getResIdByName/ResourceType → 按名称走 getStringByNameSync（同名 ...args 重载）
        return mgr.getStringByNameSync(resId, ...formatArgs);
      }
      return mgr.getStringSync(resId, ...formatArgs);
    } catch (e) {
      return '';
    }
  }
}