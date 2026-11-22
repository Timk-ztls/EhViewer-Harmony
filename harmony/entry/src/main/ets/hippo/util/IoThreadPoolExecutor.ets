/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0491   上游: com/hippo/util/IoThreadPoolExecutor.kt（约 75 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/IoThreadPoolExecutor.ets
 *
 * ⚠️【DEVIATION-IOTHREADPOOL】ArkTS 无自建线程池（taskpool 的线程数由系统决定）。
 *    本实现退化为**带并发上限的异步任务队列**（Lead 裁定方案 A）：
 *      - **保留"排队 + 回压"语义** —— 这正是上游自定义 ThreadQueue.offer 的唯一目的：
 *          override fun offer(o): Boolean {
 *              val allWorkingThreads = activeCount + super.size
 *              return allWorkingThreads < poolSize && super.offer(o)   // 线程全忙才排队
 *          }
 *        上游用"3 core / 32 max + 有界回压"表达"别一次把 IO 打满"；
 *        本实现用"最多 N 个在跑 + 其余排队"表达同一件事。
 *      - **丢掉"32 线程"**：鸿蒙 taskpool 的实际并发远小于 32，映射过去没有意义。
 *      - 上游 `PutRunnableBackHandler`（拒绝时 queue.put 阻塞）→ 本实现的队列**永不拒绝**，
 *        天然等价于"放回队列"，无需 handler。
 *
 * ⚠️ 使用约束（重要）：**task 必须是异步的**（`() => Promise<void>`）。
 *    若有人传入重 CPU 的同步函数，事件循环会被占满，"并发上限"形同虚设 —— 这种任务应该
 *    交给 `taskpool`（真并行）。本类管的是 IO/等待型任务的**排队与回压**，不是并行计算。
 *
 * 并发上限取 4：上游 core=3 / max=32；鸿蒙侧 4 个并发 + 无限排队，最接近"3 核心 + 队列"的形态。
 *
 * 平台差异：
 *  1. `PriorityThreadFactory("IO", THREAD_PRIORITY_BACKGROUND)` → 无对应（无自建线程）
 *  2. `getActiveCount()/getQueue().size()` → `getActiveCount()/getQueuedCount()`（元数据保留）
 *  3. 上游是 `ThreadPoolExecutor` 子类（外部可调用全部父类方法）；本实现只暴露 execute + 计数，
 *     **不模拟 ThreadPoolExecutor 的 API 面**（免得调用方以为能做 shutdown/awaitTermination）
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

export class IoThreadPoolExecutor {

  /** 上游 core=3 / max=32；鸿蒙取 4（见文件头） */
  static readonly DEFAULT_MAX_CONCURRENCY: number = 4;

  private readonly mMaxConcurrency: number;
  private mRunning: number = 0;
  private mQueue: Array<() => Promise<void>> = [];

  private static sInstance: IoThreadPoolExecutor | null = null;

  constructor(maxConcurrency?: number) {
    this.mMaxConcurrency = (maxConcurrency === undefined || maxConcurrency <= 0)
      ? IoThreadPoolExecutor.DEFAULT_MAX_CONCURRENCY
      : maxConcurrency;
  }

  /** 对应上游 `IoThreadPoolExecutor.Companion.getInstance()` */
  static getInstance(): IoThreadPoolExecutor {
    if (IoThreadPoolExecutor.sInstance === null) {
      IoThreadPoolExecutor.sInstance = new IoThreadPoolExecutor();
    }
    return IoThreadPoolExecutor.sInstance;
  }

  /**
   * 对应上游 execute(Runnable)。
   * 有富余并发则立即启动，否则入队等待（**不拒绝、不丢任务**，对齐上游
   * PutRunnableBackHandler 的"放回队列"语义）。
   */
  execute(task: () => Promise<void>): void {
    this.mQueue.push(task);
    this.pump();
  }

  private pump(): void {
    while (this.mRunning < this.mMaxConcurrency && this.mQueue.length > 0) {
      const task: (() => Promise<void>) | undefined = this.mQueue.shift();
      if (task === undefined) {
        return;
      }
      this.mRunning++;
      // 用 then/catch 而非 async/await：保证即使 task 同步抛错也能正确释放并发额度
      Promise.resolve()
        .then(() => task())
        .catch((_e: Error) => {
          // 单个任务失败不影响队列推进 —— 但"不推进"和"静默失败"在日志里必须能区分。
          hilog.error(0x0000, 'IoThreadPoolExecutor', 'task failed: %{public}s', _e.message);
        })
        .then(() => {
          this.mRunning--;
          this.pump();
        });
    }
  }

  /** 对应上游 getActiveCount() */
  getActiveCount(): number {
    return this.mRunning;
  }

  /** 对应上游 getQueue().size() */
  getQueuedCount(): number {
    return this.mQueue.length;
  }
}