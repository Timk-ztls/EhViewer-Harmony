/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0039   上游: com/hippo/ehviewer/callBack/SpiderInfoReadCallBack.java（6 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/callBack/SpiderInfoReadCallBack.ets
 *
 * 平台差异：
 *  1. `Map<Long, SpiderInfo>` → `Map<number, SpiderInfo>`（ArkTS 无 long；Map 键为 number 时
 *     按值相等语义，与 Java 的 Long 装箱键等价）
 *  2. 命名保留上游的 `CallBack`（大写 B）拼写，避免调用点改写。
 */

import { SpiderInfo } from '../spider/SpiderInfo';

export interface SpiderInfoReadCallBack {

  /** 上游 `void resultCallBack(Map<Long, SpiderInfo> result)`：**无 @NonNull，value 可能为 null**（C-7 第 4 条） */
  resultCallBack(resultMap: Map<number, SpiderInfo | null>): void;
}