/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0014   上游: com/hippo/conaco/ProgressNotifier.java（19 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/ProgressNotifier.ets
 *
 * 平台差异：
 *  1. Java interface → ArkTS interface（同为结构化契约，但**由实现方显式 implements**，
 *     ArkTS 不做结构类型推断，这点与 Java 的匿名类/lambda 用法不同）。
 *  2. `long` → `number`。三个参数是"单次接收量 / 已接收量 / 总量"，均为字节数，
 *     落在 2^53 内（单个文件最大 2^53 字节 = 8 PB），语义等价。
 *  3. 无方法体、无字段，零平台依赖。
 */

export interface ProgressNotifier {

  /**
   * 对应上游 notifyProgress(long singleReceivedSize, long receivedSize, long totalSize)
   */
  notifyProgress(singleReceivedSize: number, receivedSize: number, totalSize: number): void;
}
