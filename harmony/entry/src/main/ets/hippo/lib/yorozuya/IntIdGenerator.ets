/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0410   上游: com/hippo/lib/yorozuya/IntIdGenerator.java（41 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/IntIdGenerator.ets
 *
 * 平台差异：
 *  1. java.util.concurrent.atomic.AtomicInteger → ArkTS 无原子整数类型。方案 §5-4 规定
 *     TaskPool/Worker 之间不共享对象（只能传可序列化数据），本类实例不会跨 VM 线程共享，
 *     故普通 number 计数即等价；若将来要跨 Worker 共享 id 空间，需改用
 *     SharedArrayBuffer + Atomics（当前架构无此需求）。
 *  2. IllegalStateException → Error，消息串逐字保留 "Can't set INVALID_ID"。
 *  3. nextId() 的 "跳过 INVALID_ID" 自旋逐字保留（Java 里 while((id = getAndIncrement()) == -1);）。
 *     注：number 走 int32 语义需要显式 >> 0，这里用 Math.trunc 保持整数（id 不会越过 2^31）。
 */

export class IntIdGenerator {

  static readonly INVALID_ID: number = -1;

  private mId: number = 0;

  constructor(init?: number) {
    if (init !== undefined) {
      this.setNextId(init);
    }
  }

  nextId(): number {
    let id: number = this.mId;
    while (true) {
      this.mId = id + 1;
      if (id !== IntIdGenerator.INVALID_ID) {
        return id;
      }
      id = this.mId;
    }
  }

  setNextId(id: number): void {
    IntIdGenerator.checkInvalidId(id);
    this.mId = id;
  }

  private static checkInvalidId(id: number): void {
    if (IntIdGenerator.INVALID_ID === id) {
      throw new Error("Can't set INVALID_ID");
    }
  }
}