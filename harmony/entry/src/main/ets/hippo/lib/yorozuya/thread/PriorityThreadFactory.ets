/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0427   上游: com/hippo/lib/yorozuya/thread/PriorityThreadFactory.java（35 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/thread/PriorityThreadFactory.ets
 *
 * 平台差异：
 *  1. `ThreadFactory.newThread(Runnable): Thread` → `newThread(r): PriorityThread`。
 *     ArkTS 的 `PriorityThread` 已退化为「任务+名字+优先级」载体（无真实线程），
 *     故工厂产出的也是该载体，不是线程。
 *  2. `AtomicInteger mIdGenerator` → `number`（单 VM，无并发自增需求）。
 *  3. 线程名 `<name>-<id>` 逐字保留：日志/排查时这个名字是唯一能把 ArkTS 侧任务
 *     与上游 `Conaco-Disk-0` / `Conaco-Network-1` 对上号的线索。
 */

import { PriorityThread } from './PriorityThread';

export class PriorityThreadFactory {

  private readonly mPriority: number;
  private readonly mName: string;
  private mIdGenerator: number = 0;

  constructor(name: string, priority: number) {
    this.mName = name;
    this.mPriority = priority;
  }

  newThread(r: () => void): PriorityThread {
    const id: number = this.mIdGenerator++;
    return new PriorityThread(r, `${this.mName}-${id}`, this.mPriority);
  }

  getName(): string {
    return this.mName;
  }
}