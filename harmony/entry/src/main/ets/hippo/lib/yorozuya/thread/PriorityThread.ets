/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0426   上游: com/hippo/lib/yorozuya/thread/PriorityThread.java（33 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/thread/PriorityThread.ets
 *
 * ⚠️ 本条**撤销此前的 na 裁决**：之前裁定"职责并入 Worker 的 name/priority，标 na"，
 *    但 storage-db 的 `ArchiveGalleryProvider` / `DirGalleryProvider` 等**直接 extends/持有
 *    PriorityThread**，标 na 会让这 3 个 gallery provider（668 行）无法 import。
 *    本类改为 **ported**，提供可编译可运行的退化实现。
 *
 * 平台差异：
 *  1. **ArkTS 没有 Thread 类**，无法"继承一个线程"。本类退化为「任务 + 名字 + 优先级」的载体：
 *       `start()` → 在当前线程**同步**执行 `run()`
 *       `run()`   → 默认执行构造时传入的 task（子类可 override，与上游模板方法结构一致）
 *     真实并发由调用方交给 `taskpool` / `@ohos.worker`（conaco 的等价层就是这么做的）。
 *  2. `android.os.Process.setThreadPriority(int)` → 无对应 API。优先级**只作为元数据保留**
 *     （`getPriority()`），不映射到 OS 线程优先级 —— 因为本类不再拥有线程。
 *     若要真实优先级，调用方应使用 `taskpool.Priority` 或 `WorkerOptions.priority`
 *     （`ThreadWorkerPriority`）。
 *  3. 两个 Java 构造重载 `(Runnable, int)` / `(Runnable, String, int)` → ArkTS 无重载：
 *     `constructor(runnable, nameOrPriority, priority?)`。
 *  4. `Thread.getName()` → `getName(): string | null`。
 */

export class PriorityThread {

  private readonly mPriority: number;
  private readonly mName: string | null;
  private readonly mTask: (() => void) | null;

  constructor(runnable: (() => void) | null, nameOrPriority: string | number, priority?: number) {
    this.mTask = runnable;
    if (typeof nameOrPriority === 'number') {
      this.mPriority = nameOrPriority;
      this.mName = null;
    } else {
      this.mName = nameOrPriority;
      this.mPriority = (priority === undefined) ? 0 : priority;
    }
  }

  getName(): string | null {
    return this.mName;
  }

  getPriority(): number {
    return this.mPriority;
  }

  /**
   * 对应上游 start()（Thread.start）。本实现无真实线程：同步执行 run()。
   */
  start(): void {
    this.run();
  }

  /**
   * 对应上游 run()：先 setThreadPriority 再 super.run()。
   * ArkTS 无 setThreadPriority（见差异 2），故只剩任务体；子类 override 本方法即可。
   */
  run(): void {
    const task: (() => void) | null = this.mTask;
    if (task !== null) {
      task();
    }
  }
}