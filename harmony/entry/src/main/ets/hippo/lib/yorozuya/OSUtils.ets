/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0418   上游: com/hippo/lib/yorozuya/OSUtils.java（79 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/OSUtils.ets
 *
 * 上游调用面（git grep）：checkMainLoop ×4（SpiderQueen:196/301、GalleryProvider:51/61，
 *   全部是语句式调用，返回值被忽略）；getAppAllocatedMemory ×1（Crash:115）；
 *   getAppMaxMemory ×2（Crash:117、EhApplication:551）；getTotalMemory ×2（Crash:118、
 *   GalleryProvider:234）。
 *
 * 平台差异（按 Lead 2026-10-24 口径裁定：方案 (a) + getAppMaxMemory 单独 TODO）：
 *  1. `checkMainLoop()`：Android 用 Looper.myLooper() != Looper.getMainLooper() 抛异常。
 *     ArkTS 无 Looper 概念、无公开 API 可判断"当前是否 UI 线程"。
 *     按裁定改为**空实现 + 返回 true（乐观默认）**，避免调用点走异常分支。
 *     注意：上游该方法返回 void，本实现返回 boolean，语句式调用点不受影响。
 *  2. `getAppAllocatedMemory()` → **改名 `getAppPssMemory()`**（Lead 要求）。
 *     Java 侧是 Runtime.totalMemory() - freeMemory()（Java 堆已分配量，字节）；
 *     鸿蒙侧用 `@ohos.hidebug.getPss()`（进程 PSS，KB）换算成字节返回。
 *     **口径差异（务必知悉）**：PSS = 进程实际驻留物理内存（含 native/图形/共享页均摊），
 *     与"Java 堆分配量"不可比，数值通常显著更大。返回单位仍为字节，便于沿用
 *     FileUtils.humanReadableByteCount()。
 *  3. `getTotalMemory()`：保留原名与原语义（设备 RAM 字节数）。上游读 /proc/meminfo 的 MemTotal
 *     再 ×1024；鸿蒙侧用 `@ohos.hidebug.getSystemMemInfo().totalMem`（KB，官方注释即
 *     "obtained by reading MemTotal in /proc/meminfo"），×1024 后同样得到字节，语义完全对得上。
 *     结果静态缓存（上游也是 sTotalMem 缓存）。
 *  4. `getAppMaxMemory()`：**TODO(platform)** —— 鸿蒙无 "Java heap 上限" 概念，
 *     返回 -1（上游 Long.MIN_VALUE 哨兵在语义上是"未取到"，这里用 -1 更明确）。
 *     2 处调用点需各自处理 -1：Crash:117 只是打印（-1 无害）；
 *     EhApplication:551 是 `Math.min(20MB, (int) getAppMaxMemory())`，会退化成 -1，
 *     该处应由 storage-db / gl-render 侧改为固定 20MB 或改用 PSS 估算（已在 MR 标注）。
 *  5. java.io.BufferedReader/FileReader（读 /proc）不再使用：鸿蒙应用沙箱不允许直接读 /proc/meminfo，
 *     hidebug 封装了同一数据源，故 IOUtils.closeQuietly 依赖一并消失。
 *  6. IllegalStateException（checkMainLoop 的 "It is in not main loop!"）随空实现消失。
 */

import hidebug from '@ohos.hidebug';

export class OSUtils {

  private static sTotalMem: number = -1;

  /**
   * Android 侧用于断言当前在主线程。ArkTS 无 Looper API，无法检测当前线程。
   * TODO(platform): ArkTS 无 Looper API，无法检测当前线程；乐观返回 true，不做线程校验。
   */
  static checkMainLoop(): boolean {
    return true;
  }

  /**
   * Get application PSS memory size, in bytes.
   *
   * 口径差异：PSS（进程实际驻留物理内存，含 native/图形/共享页均摊）≠ Java 堆分配量。
   * 对应上游 getAppAllocatedMemory()，改名以避免下游误用（见文件头差异 2）。
   */
  static getAppPssMemory(): number {
    // hidebug.getPss() 单位 KB
    return Number(hidebug.getPss()) * 1024;
  }

  /**
   * Get application max memory size.
   *
   * TODO(platform): 鸿蒙无 "Java heap 上限" 概念，恒返回 -1；调用方必须处理 -1。
   */
  static getAppMaxMemory(): number {
    return -1;
  }

  /**
   * Get device RAM size, in bytes.
   */
  static getTotalMemory(): number {
    if (OSUtils.sTotalMem < 0) {
      const info: hidebug.SystemMemInfo = hidebug.getSystemMemInfo();
      // totalMem 单位 KB（官方注释：读取 /proc/meminfo 的 MemTotal）
      const mem: number = Number(info.totalMem) * 1024;
      OSUtils.sTotalMem = mem > 0 ? mem : -1;
    }
    return OSUtils.sTotalMem;
  }
}
