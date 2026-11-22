/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0017   上游: com/hippo/conaco/ValueCache.java（49 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/ValueCache.ets
 *
 * 平台差异：
 *  1. `extends BeerBelly<V>` 保留（BeerBelly 是 net-parse 落的 beerbelly 等价层，
 *     抽象点已对齐：sizeOf / memoryEntryAdded / memoryEntryRemoved / read / write）。
 *  2. `java.io.OutputStream` → `ByteSink`（streampipe/OutputStreamPipe 导出），
 *     与 BeerBelly.write 的抽象签名一致。
 *  3. `UnsupportedOperationException("Not support write object")` → `Error`，
 *     **消息串逐字保留**。上游 write 恒抛，因为 ValueCache 只读（写盘由 DataContainer 负责）。
 *  4. `memoryEntryRemoved` 的 `oldValue != null` 判空保留：ArkTS 的 `V | null` 需要显式判空，
 *     语义与上游一致（只有旧的缓存值存在时才回调 helper）。
 *  5. `read(InputStreamPipe, boolean hardware)` → 委托 `mHelper.decode(isPipe, hardware)`
 *     （ValueHelper.decode 的 hardware 是可选参，这里显式传值）。
 */

import { BeerBelly, BeerBellyParams } from '../beerbelly/BeerBelly';
import { ByteSink } from '../streampipe/OutputStreamPipe';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';
import { ValueHelper } from './ValueHelper';

export class ValueCache<V> extends BeerBelly<V> {

  private readonly mHelper: ValueHelper<V>;

  constructor(params: BeerBellyParams, helper: ValueHelper<V>) {
    super(params);
    this.mHelper = helper;
  }

  sizeOf(key: string, value: V): number {
    return this.mHelper.sizeOf(key, value);
  }

  memoryEntryAdded(value: V): void {
    this.mHelper.onAddToMemoryCache(value);
  }

  memoryEntryRemoved(evicted: boolean, key: string, oldValue: V | null, newValue: V | null): void {
    if (oldValue !== null && oldValue !== undefined) {
      this.mHelper.onRemoveFromMemoryCache(key, oldValue);
    }
  }

  read(isPipe: InputStreamPipe, hardware: boolean): V | null {
    return this.mHelper.decode(isPipe, hardware);
  }

  write(os: ByteSink, value: V): boolean {
    throw new Error('Not support write object');
  }
}
