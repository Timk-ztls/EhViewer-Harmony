/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0429   上游: com/hippo/lib/yorozuya/thread/SerialThreadExecutor.java（88 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/thread/SerialThreadExecutor.ets
 *
 * ⚠️【DEVIATION-SERIALEXEC】ArkTS 无自建线程。上游是「1 个 worker 线程 + 有界保活」：
 *     · 任务严格**串行**、按入队顺序执行
 *     · 空闲超过 `mKeepAliveMillis` → worker 置 null 并退出（`run()` 里的 hasWaited 逻辑）
 *     · 新任务到来时若 worker 不在 → 新建 worker
 *   本实现用「异步串行泵 + setTimeout 空闲计时器」表达同一语义：
 *     · 同一时刻只有一个任务在执行（串行、保序）
 *     · 空闲计时器到期 → `mRunning = false`（等价于 worker 退出）
 *     · 新任务到来时若不在跑 → 重新启动泵
 *   **可观察差异**：没有真实线程，也就没有「线程优先级」与真实阻塞；任务执行在 ArkTS
 *   事件循环上（因为任务体是 `() => void`，见下方约束）。
 *
 * ⚠️ 任务约定：`() => void` 里**不要做长阻塞**（上游跑在独立线程上可以阻塞）。
 *    需要真并行/阻塞的应交给 `taskpool`。conaco 的任务体是 IO 等待型，故本改造可用。
 *
 * 平台差异：
 *  1. `ReentrantLock` / `synchronized(mWaitLock)` → 无锁（单 VM，任务泵天然串行）
 *  2. `Queue<Runnable>` → `Array<() => void>`（FIFO，语义同 LinkedList）
 *  3. `ThreadFactory` → `PriorityThreadFactory`（保留命名与优先级元数据）
 */

import { PriorityThreadFactory } from './PriorityThreadFactory';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class SerialThreadExecutor {

  private readonly mKeepAliveMillis: number;
  private readonly mWorkQueue: Array<() => void>;
  private readonly mThreadFactory: PriorityThreadFactory;

  /** 等价于上游 `mThread != null`：worker 是否活着 */
  private mRunning: boolean = false;
  private mIdleTimer: number = -1;

  constructor(keepAliveMillis: number, workQueue: Array<() => void>,
    threadFactory: PriorityThreadFactory) {
    this.mKeepAliveMillis = keepAliveMillis;
    this.mWorkQueue = workQueue;
    this.mThreadFactory = threadFactory;
  }

  /** 对应上游 execute(Runnable) */
  execute(command: () => void): void {
    this.mWorkQueue.push(command);
    this.cancelIdleTimer();
    if (!this.mRunning) {
      // Ensure thread：等价于 mThreadFactory.newThread(this).start()
      this.mRunning = true;
      this.pump();
    }
  }

  /** 主动终止 worker（上游无此方法，等价于"worker 已退出"状态；供 dispose 使用） */
  terminate(): void {
    this.cancelIdleTimer();
    this.mRunning = false;
  }

  /** worker 是否存活（上游用 mThread != null 隐式表达，这里显式暴露便于测试） */
  isRunning(): boolean {
    return this.mRunning;
  }

  /** 线程名前缀（对应上游 PriorityThreadFactory 的 name） */
  getThreadName(): string {
    return this.mThreadFactory.getName();
  }

  /** 队列长度（测试/诊断用） */
  getQueueSize(): number {
    return this.mWorkQueue.length;
  }

  private cancelIdleTimer(): void {
    if (this.mIdleTimer !== -1) {
      clearTimeout(this.mIdleTimer);
      this.mIdleTimer = -1;
    }
  }

  /**
   * 任务泵：严格串行取队首执行；队空时启动保活计时器，到期则"worker 退出"。
   * 对应上游 run() 的 for(;;) + poll() + wait(keepAlive) 结构。
   */
  private pump(): void {
    const command: (() => void) | undefined = this.mWorkQueue.shift();
    if (command === undefined) {
      // 对应上游 hasWaited 分支：等够时间后 mThread = null 并退出
      this.mIdleTimer = setTimeout(() => {
        this.mIdleTimer = -1;
        if (this.mWorkQueue.length === 0) {
          this.mRunning = false;
        } else {
          this.pump();
        }
      }, this.mKeepAliveMillis);
      return;
    }

    // 用 then 链保证：即使 command 同步抛错，泵也能继续（对应上游 try/catch）
    Promise.resolve()
      .then(() => command())
      .catch((_e: Error) => {
        // 上游：e.printStackTrace()，即吞掉继续 —— **吞掉的是传播，printStackTrace 仍然记了**。
        hilog.error(0x0000, 'SerialThreadExecutor', 'command failed, continue: %{public}s', _e.message);
      })
      .then(() => {
        this.pump();
      });
  }
}
