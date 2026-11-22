/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0175   上游: com/hippo/ehviewer/preference/VersionPreference.java（48 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/preference/VersionPreference.ets
 *
 * 【D-033 拆分】上游该类 `extends Preference`，**类本身就带 UI**。ArkTS 无 Preference 体系，
 * 故本文件只保留**纯逻辑**（版本号读取）。UI 由 ui-widget 的 ArkUI 组件表达
 * （见 ui-widget.extra.txt 的 SettingsItem<Version>）。
 *
 * 平台差异：
 *  1. `PackageManager.getPackageInfo(pkg, 0).versionName` →
 *     `bundleManager.getBundleInfoForSelfSync(GET_BUNDLE_INFO_DEFAULT).versionName`
 *  2. 取不到时回退文案：上游用 `R.string.error_unknown`，本实现返回 `'unknown'`
 *     （资源名 `error_unknown` 由 UI 层负责取，逻辑层不依赖资源管理器，便于测试）
 *     —— 若调用方需要本地化文案，请用 `GetText.getString('error_unknown')` 覆盖返回值。
 */

import bundleManager from '@ohos.bundle.bundleManager';

export class VersionPreference {

  /** 取不到版本号时的回退值（对应上游 R.string.error_unknown 的语义） */
  static readonly FALLBACK: string = 'unknown';

  /**
   * 对应上游 init() 里的版本号读取。
   * 失败返回 `FALLBACK`（上游是 `e.printStackTrace()` 后 setSummary(error_unknown)）。
   */
  static getVersionName(): string {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const name: string = info.versionName;
      return (name === undefined || name.length === 0) ? VersionPreference.FALLBACK : name;
    } catch (e) {
      return VersionPreference.FALLBACK;
    }
  }
}