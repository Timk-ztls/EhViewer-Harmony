/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0281   上游: com/hippo/ehviewer/util/MiuiOptimizationHelper.kt（253 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/util/MiuiOptimizationHelper.ets
 *
 * 【判据：**不是**整个类 na，而是"判定逻辑可移植、设置跳转与属性反射不可移植"】
 *
 * 先查调用点（`git grep MiuiOptimizationHelper`）：只有 `download/DownloadService.kt` 6 处，
 * **调用点本身没有 `isMiui()` 判断** → 属于"类内部自己判"的第 ② 种：
 * 非 MIUI 设备会走到 `else` 分支（LOW 优先级等），**那条路径是活的、必须移植**。
 *
 * 移植（纯决策逻辑，输入全是可注入的设备属性）：
 *   · `isMiuiDevice` —— 厂商 ∈ {Xiaomi, Redmi, POCO}（忽略大小写）**或** MIUI version code 属性非空
 *   · `getMiuiVersion` —— 从 `ro.miui.ui.version.name` 用正则 `V(\d+)` 取号；失败回落到 version code；再失败 -1
 *   · `isHyperOsDevice` —— isMiui && (版本 ≥14 || DISPLAY 含 "HyperOS")
 *   · `needsMiuiOptimization` —— isMiui && SDK ≥ 29（Q）
 *   · `needsAggressiveOptimization` —— SDK ≥ 34（UPSIDE_DOWN_CAKE）**或** HyperOS
 *   · `getRecommendedNotificationImportance` —— 三分支（HIGH / DEFAULT / LOW）
 *   · `getDeviceInfo` —— 诊断文本（纯字符串拼接）
 *
 * 不移植（Android 专有）：
 *   · `getSystemProperty` 的**两条取值路径**（`android.os.SystemProperties` 反射 + `getprop` 子进程）
 *     → 属性值由调用方注入（鸿蒙侧恒为空串/undefined，语义等价"取不到"）
 *   · `openMiuiBatterySettings` / `openMiuiAutoStartSettings` / `openMiuiPowerSaveSettings`
 *     → `Intent("miui.intent.action.*")` 是 MIUI 专有 Activity，鸿蒙无对应 → **na**
 *   · `Log.e` → `hilog`
 *
 * ⚠️ **`Build.VERSION.SDK_INT` 的映射（必须显式说明）**：鸿蒙没有 Android SDK 版本号。
 *    本文件把 `sdkInt` 作为**显式参数**：鸿蒙调用方应传 `0`（未知）—— 此时
 *    `needsAggressiveOptimization` 只由 HyperOS 判定决定（恒 false），即"不做小米激进优化"，
 *    这正是非小米设备应有的路径。**不要**把鸿蒙 API 号（如 20）直接当 SDK_INT 传入 ——
 *    那是两个不同 OS 的版本轴，混用会在未来鸿蒙 API 升到 34 时误开小米优化。
 */

/** 注入的设备属性（对应上游 `Build.MANUFACTURER` 等 + `getprop` 结果） */
export interface DeviceProps {
  manufacturer: string;
  brand: string;
  model: string;
  display: string;
  /** `Build.VERSION.RELEASE`（鸿蒙侧可传 "HarmonyOS x.y" 之类的可读串） */
  versionRelease: string;
  /** 上游 `Build.VERSION.SDK_INT`；**鸿蒙传 0**（见文件头说明） */
  sdkInt: number;
  /** `ro.miui.ui.version.code`（取不到 → null） */
  miuiVersionCode: string | null;
  /** `ro.miui.ui.version.name`（取不到 → null） */
  miuiVersionName: string | null;
}

/** Android `NotificationManager.IMPORTANCE_*` 的值 */
export class NotificationImportance {
  static readonly IMPORTANCE_HIGH: number = 4;
  static readonly IMPORTANCE_DEFAULT: number = 3;
  static readonly IMPORTANCE_LOW: number = 2;
}

/** Android `Build.VERSION_CODES` 的两个相关值 */
export class SdkVersion {
  static readonly Q: number = 29;
  static readonly UPSIDE_DOWN_CAKE: number = 34;
}

export class MiuiOptimizationHelper {

  static readonly TAG: string = 'MiuiOptimization';
  static readonly KEY_MIUI_VERSION_CODE: string = 'ro.miui.ui.version.code';
  static readonly KEY_MIUI_VERSION_NAME: string = 'ro.miui.ui.version.name';
  static readonly KEY_MIUI_INTERNAL_STORAGE: string = 'ro.miui.internal.storage';

  /**
   * 对应上游 `isMiuiDevice()`：厂商三个名字（忽略大小写）**或** version code 属性非空。
   * 注意是 `||` —— 只要 `getprop ro.miui.ui.version.code` 有值就算小米设备（即使厂商名不认识）。
   */
  static isMiuiDevice(p: DeviceProps): boolean {
    const m: string = p.manufacturer.toLowerCase();
    return m === 'xiaomi' || m === 'redmi' || m === 'poco' || !MiuiOptimizationHelper.isNullOrEmpty(p.miuiVersionCode);
  }

  /**
   * 对应上游 `getMiuiVersion()`：
   * 非小米 → -1；否则先用 `V(\d+)` 从版本名取号，再看 version code 能否转 int，否则 -1。
   */
  static getMiuiVersion(p: DeviceProps): number {
    if (!MiuiOptimizationHelper.isMiuiDevice(p)) {
      return -1;
    }
    const versionName: string | null = p.miuiVersionName;
    if (!MiuiOptimizationHelper.isNullOrEmpty(versionName)) {
      // 例如 "V14"、"V13"、"V816" → 提取 V 后面的数字
      const match: RegExpMatchArray | null = (versionName as string).match(/V(\d+)/);
      if (match !== null) {
        return parseInt(match[1], 10);
      }
    }
    const versionCode: string | null = p.miuiVersionCode;
    if (!MiuiOptimizationHelper.isNullOrEmpty(versionCode)) {
      const n: number = parseInt(versionCode as string, 10);
      return Number.isNaN(n) ? -1 : n;
    }
    return -1;
  }

  /** 对应上游 `isHyperOsDevice()`：`isMiui && (版本 ≥14 || DISPLAY 含 "HyperOS")` */
  static isHyperOsDevice(p: DeviceProps): boolean {
    if (!MiuiOptimizationHelper.isMiuiDevice(p)) {
      return false;
    }
    return MiuiOptimizationHelper.getMiuiVersion(p) >= 14
      || p.display.toLowerCase().indexOf('hyperos') >= 0;
  }

  /** 对应上游 `needsMiuiOptimization()`：`isMiui && SDK ≥ 29` */
  static needsMiuiOptimization(p: DeviceProps): boolean {
    return MiuiOptimizationHelper.isMiuiDevice(p) && p.sdkInt >= SdkVersion.Q;
  }

  /**
   * 对应上游 `needsAggressiveOptimization()`：`SDK ≥ 34 || isHyperOsDevice()`。
   * ⚠️ 鸿蒙侧 `sdkInt` 传 0 → 只剩 HyperOS 判定（恒 false），即不做激进优化。
   */
  static needsAggressiveOptimization(p: DeviceProps): boolean {
    return p.sdkInt >= SdkVersion.UPSIDE_DOWN_CAKE
      || MiuiOptimizationHelper.isHyperOsDevice(p);
  }

  /**
   * 对应上游 `getRecommendedNotificationImportance()`：
   * 小米优化 → HIGH；Android 14+ → DEFAULT；其余 → LOW。
   * 鸿蒙（sdkInt=0、非小米）落到 **LOW** —— 与"其他设备"路径一致。
   */
  static getRecommendedNotificationImportance(p: DeviceProps): number {
    if (MiuiOptimizationHelper.needsMiuiOptimization(p)) {
      // 小米系统使用 HIGH 优先级，避免被系统杀后台
      return NotificationImportance.IMPORTANCE_HIGH;
    }
    if (p.sdkInt >= SdkVersion.UPSIDE_DOWN_CAKE) {
      return NotificationImportance.IMPORTANCE_DEFAULT;
    }
    return NotificationImportance.IMPORTANCE_LOW;
  }

  /** 对应上游 `getDeviceInfo()`：诊断文本（逐行拼接，格式与上游一致） */
  static getDeviceInfo(p: DeviceProps): string {
    return '=== Device Info ===\n'
      + 'Manufacturer: ' + p.manufacturer + '\n'
      + 'Brand: ' + p.brand + '\n'
      + 'Model: ' + p.model + '\n'
      + 'Display: ' + p.display + '\n'
      + 'Android Version: ' + p.versionRelease + ' (API ' + p.sdkInt + ')\n'
      + 'Is MIUI: ' + MiuiOptimizationHelper.isMiuiDevice(p) + '\n'
      + 'Is HyperOS: ' + MiuiOptimizationHelper.isHyperOsDevice(p) + '\n'
      + 'MIUI Version: ' + MiuiOptimizationHelper.getMiuiVersion(p) + '\n'
      + 'Needs MIUI Optimization: ' + MiuiOptimizationHelper.needsMiuiOptimization(p) + '\n'
      + 'Needs Aggressive Optimization: ' + MiuiOptimizationHelper.needsAggressiveOptimization(p);
  }

  private static isNullOrEmpty(s: string | null): boolean {
    return s === null || s.length === 0;
  }
}
