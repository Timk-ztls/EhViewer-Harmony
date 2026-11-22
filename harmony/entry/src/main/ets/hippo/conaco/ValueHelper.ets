/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0018   上游: com/hippo/conaco/ValueHelper.java（48 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/ValueHelper.ets
 *
 * 平台差异：
 *  1. **`decode(InputStreamPipe)` / `decode(InputStreamPipe, boolean hardware)` 两个重载 →
 *     合并为 `decode(isPipe, hardware?)`**（ArkTS 无重载解析，方案 §5-7）。
 *     两个调用点都能原样迁移：一参调用走 hardware 缺省 false（与上游
 *     BeerBelly.read 的无 hardware 分支一致），二参调用显式传值。
 *  2. `@Nullable V` → `V | null`（ArkTS 编译期强制判空）。
 *  3. `@NonNull String key` / `@NonNull V value` → 直接类型（ArkTS 无 @NonNull，靠类型系统）。
 *  4. `useMemoryCache(@NonNull String key, V holder)` 的 holder **允许为 null**：
 *     上游调用点就是 `mHelper.useMemoryCache(key, null)`（Conaco.startConacoTask），
 *     故声明为 `holder: V | null`。
 *  5. `int sizeOf(...)` → `number`（返回字节数，用于 LRU 容量统计）。
 */

import { InputStreamPipe } from '../streampipe/InputStreamPipe';

export interface ValueHelper<V> {

  /**
   * Decode object for the InputStreamPipe
   *
   * @param hardware 对应上游 decode(isPipe, hardware) 的 hardware 重载；
   *                 缺省 false（与 BeerBelly.read 的无 hardware 分支一致）
   * @return the decoded object
   */
  decode(isPipe: InputStreamPipe, hardware?: boolean): V | null;

  /**
   * Get the size of the object
   */
  sizeOf(key: string, value: V): number;

  /**
   * Called when the object added to memory cache
   */
  onAddToMemoryCache(oldValue: V): void;

  /**
   * Called when the object removed from memory cache
   */
  onRemoveFromMemoryCache(key: string, oldValue: V): void;

  /**
   * Use cache memory or not. Sometimes large object should not be stored in memory cache.
   */
  useMemoryCache(key: string, holder: V | null): boolean;
}
