/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0425   上游: com/hippo/lib/yorozuya/thread/InfiniteThreadExecutor.java（83 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/thread/InfiniteThreadExecutor.ets
 *
 * ⚠️【DEVIATION-INFINITEEXEC】上游语义：**每来一个任务就开一个线程**（无上限），
 *    空闲线程保活 `mKeepAliveMillis` 后自行退出；`mEmptyThreadCount > 0` 时复用空闲线程。
 *    即"并发数 = 同时需要执行的任务数"，这是它与 SerialThreadExecutor 的本质区别。
 *
 *    ArkTS 无可自建线程 → 本实现用「每个任务一个异步 runner + 空闲计数」表达：
 *      · `execute` 直接启动 runner（不排队、不拒绝），并发度不受限
 *      · runner 执行完任务后进入"空闲等待"：`mEmptyThreadCount++` + setTimeout 保活
 *      · 新任务到来时若 `mEmptyThreadCount > 0` → 复用（计数减一、取消其计时器）
 *      · 保活到期 → 计数减一，runner 结束（等价于线程退出）
 *   **可观察差异**：没有真实线程；`getThreadCount()` 返回的是活跃 runner 数。
 *
 * ⚠️ **内存提示**：上游每个线程默认栈 ~1MB（Java 默认 2 或 4 MB 保留/提交），
 *    历史上 conaco 的 InfiniteThreadExecutor 只用于字节流泵这类短任务。ArkTS 侧 runner
 *    是对象而非线程，**不会有每任务 MB 级开销**，但任务体本身的内存仍按任务计。
 *
 * 平台差异：
 *  1. `AtomicInteger mThreadCount` → `number`（单 VM）
 *  2. `synchronized(mLock)` + `mLock.wait()` → 无锁 + setTimeout
 *  3. `Queue<Runnable>` → `Array<() => void>`（上游用 poll 取队首，本实现每 runner 直接持有任务）
 */

import { PriorityThreadFactory } from './PriorityThreadFactory';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class InfiniteThreadExecutor {

  private readonly mKeepAliveMillis: number;
  private readonly mWorkQueue: Array<() => void>;
  private readonly mThreadFactory: PriorityThreadFactory;

  private mThreadCount: number = 0;
  /** 等价于上游 mEmptyThreadCount：处于保活等待中的 runner 数 */
  private mEmptyThreadCount: number = 0;
  private mIdleTimers: number[] = [];

  constructor(keepAliveMillis: number, workQueue: Array<() => void>,
    threadFactory: PriorityThreadFactory) {
    this.mKeepAliveMillis = keepAliveMillis;
    this.mWorkQueue = workQueue;
    this.mThreadFactory = threadFactory;
  }

  /** 对应上游 execute(Runnable) */
  execute(command: () => void): void {
    // 有富余并发则直接交给一个新 runner（上游同样是 newThread 而非入队）
    this.mWorkQueue.push(command);
    this.mThreadCount++;
    this.runNext();
  }

  /** 线程名前缀（对应上游 PriorityThreadFactory 的 name，日志可对照 Conaco-Network） */
  getThreadName(): string {
    return this.mThreadFactory.getName();
  }

  /** 对应上游 getThreadCount() */
  getThreadCount(): number {
    return this.mThreadCount;
  }

  /** 空闲等待中的 runner 数（上游 mEmptyThreadCount，测试用） */
  getEmptyThreadCount(): number {
    return this.mEmptyThreadCount;
  }

  /** 主动终止所有空闲等待（等价于所有保活线程到期退出） */
  terminate(): void {
    for (let i = 0; i < this.mIdleTimers.length; i++) {
      clearTimeout(this.mIdleTimers[i]);
    }
    this.mIdleTimers = [];
    this.mThreadCount -= this.mEmptyThreadCount;
    this.mEmptyThreadCount = 0;
  }

  /**
   * runner 主体：取一个任务执行；执行完进入保活等待。
   * 对应上游 Task.run() 的 for(;;) { poll(); run(); ++empty; wait(keepAlive); }
   */
  private runNext(): void {
    const command: (() => void) | undefined = this.mWorkQueue.shift();
    if (command === undefined) {
      // 队列空：本 runner 直接进入空闲等待
      this.enterIdle();
      return;
    }

    Promise.resolve()
      .then(() => command())
      .catch((_e: Error) => {
        // 上游：e.printStackTrace() 后继续 —— **那本身就是一条痕迹**。
        // 我们此前把注释当成了实现：吞掉的是"异常传播"，不是"日志"。
        // silent-failures 闸门抓的就是这里（B2 catch 无痕迹）。
        hilog.error(0x0000, 'InfiniteThreadExecutor', 'command failed, continue: %{public}s', _e.message);
      })
      .then(() => {
        this.enterIdle();
      });
  }

  private enterIdle(): void {
    this.mEmptyThreadCount++;
    const timer: number = setTimeout(() => {
      // 保活到期：runner 退出
      this.mEmptyThreadCount--;
      this.mThreadCount--;
      const idx: number = this.mIdleTimers.indexOf(timer);
      if (idx >= 0) {
        this.mIdleTimers.splice(idx, 1);
      }
      // 若期间又有任务进来（上游靠 notify 复用），这里再拉一次
      if (this.mWorkQueue.length > 0) {
        this.mThreadCount++;
        this.runNext();
      }
    }, this.mKeepAliveMillis);
    this.mIdleTimers.push(timer);
  }
}
