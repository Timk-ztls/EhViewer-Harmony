/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0037   上游: com/hippo/ehviewer/Analytics.kt（约 70 行，Kotlin object）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/Analytics.ets
 *
 * ⚠️【DEVIATION-ANALYTICS】上游三个方法全部依赖 Firebase（Google 服务），鸿蒙不可用：
 *      FirebaseAnalytics.getInstance(ctx) / FirebaseCrashlytics.getInstance().recordException(e)
 *      / analytics.logEvent("scene_view", bundle)
 *    本实现降级为**本地实现**（Lead 裁定方案 A）：
 *      - recordException(e) → hilog.error（保住本地可查的那部分诊断价值）
 *      - start / onSceneView 保留签名、空实现（调用点无需改写，1:1 保持）
 *      - isEnabled() 恒 false
 *    **能力损失**：无远端埋点统计、无远端崩溃聚合上报。这是有意的取舍，不是遗漏。
 *
 * 为什么不接 AGC（华为分析）：需要 appId + 网络 + 隐私合规声明，且 recordException 在崩溃
 * 现场可能本身就不可用——接了也不可靠；不落这个类则要删 SpiderQueen 的 5 处调用点，违背 1:1。
 *
 * 平台差异：
 *  1. `android.util.Log` → `@ohos.hilog`
 *  2. `Settings.getEnableAnalytics()` 只在"真接远端"时才需要；恒 false 后不再依赖它
 *  3. `onSceneView(SceneFragment)` → `onSceneView(sceneName: string)`：ArkTS 侧由调用方传类名，
 *     不引入 SceneFragment 依赖（否则序列化/反射都不能用）
 */

import hilog from '@ohos.hilog';

export class Analytics {

  private static readonly LOG_TAG: string = 'Analytics';
  private static readonly DOMAIN: number = 0x0001;

  /** 对应上游 start(Context)：降级为空实现（见文件头 DEVIATION-ANALYTICS） */
  static start(_context: Object): void {
    // 无第三方 SDK 可初始化
  }

  /** 对应上游 isEnabled：恒 false（未接任何远端上报） */
  static isEnabled(): boolean {
    return false;
  }

  /**
   * 对应上游 recordException(Throwable)：本地 hilog 记录。
   * 上游还会 Log.e + FirebaseCrashlytics.recordException，前者本实现保留、后者不接。
   */
  static recordException(e: Error): void {
    hilog.error(Analytics.DOMAIN, Analytics.LOG_TAG, '%{public}s', Analytics.describe(e));
  }

  /** 对应上游 onSceneView(SceneFragment)：降级为空实现，但保留调用点 */
  static onSceneView(_sceneName: string): void {
    // 无远端埋点
  }

  /** Error → 可读串（含 stack，便于本地定位） */
  private static describe(e: Error): string {
    const msg: string = e.message;
    const stack: string = (e.stack === undefined) ? '' : e.stack;
    return stack.length > 0 ? (msg + '\n' + stack) : msg;
  }
}