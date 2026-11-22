/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0428   上游: com/hippo/lib/yorozuya/thread/PVLock.java（44 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/thread/PVLock.ets
 *
 * 上游是一个**计数信号量**（P/V 原语）：
 * ```java
 * private int mCounter;
 * public synchronized void p() { while (true) { if (mCounter > 0) { mCounter--; break; } else wait(); } }
 * public synchronized void v() { mCounter++; if (mCounter > 0) notify(); }
 * ```
 *
 * 平台差异：
 *  1. **ArkTS 没有 `synchronized`、没有 `wait/notify`**，也没有"可被 park 的工作线程"可用
 *     （`@ohos.taskpool` 的 worker 是跨线程消息模型，不是共享内存）。
 *     → 语义改为**异步计数信号量**：`p()` 返回 `Promise<void>`，无配额时挂起（进等待队列）。
 *  2. `v()` 的 `notify()` 语义 → **直接移交**给队列里的下一个等待者
 *     （上游被唤醒的线程会重查 `mCounter > 0` 再 `--`，净效果同样是"计数器不变、唤醒一个"）。
 *  3. 上游 `p()` 声明 `throws InterruptedException` —— 异步版本没有中断概念，
 *     改为"永不加锁地等待"，无需异常。**没有调用方依赖这个异常**。
 *  4. `v()` 里 `if (mCounter > 0) notify()` 的判据在移交实现下恒为真（队列非空时计数器为 0），
 *     照搬成"队列非空就移交"。
 *
 * 语义要点（都有断言）：
 *  · `new PVLock(0)` → 第一次 `p()` 必须等 `v()`
 *  · `new PVLock(n)` → 前 n 次 `p()` **立即**完成
 *  · `v()` 有多余配额时**累积**（下一个 `p()` 立即完成）
 *  · 多个等待者按 **FIFO** 顺序唤醒（上游 `notify()` 不保证顺序，这里选了确定性的 FIFO）
 */

export class PVLock {

  private counter: number;
  private waiters: (() => void)[] = [];

  /** @param count 初始配额（上游 `PVLock(int count)`） */
  constructor(count: number) {
    this.counter = count;
  }

  /** 当前剩余配额（上游无此方法；诊断/测试用） */
  getCount(): number {
    return this.counter;
  }

  /** 当前等待者数量（上游无此方法） */
  getWaiterCount(): number {
    return this.waiters.length;
  }

  /** 对应上游 `p()`：拿到配额（配额不足则挂起，返回的 Promise 在拿到时 resolve） */
  async p(): Promise<void> {
    if (this.counter > 0) {
      this.counter--;
      return;
    }
    // 无配额 → 入队等待（对应上游 `this.wait()`）
    await new Promise<void>((resolve: () => void) => {
      this.waiters.push(resolve);
    });
  }

  /** 对应上游 `v()`：归还配额；若有等待者则**直接移交**（计数器不变） */
  v(): void {
    if (this.waiters.length > 0) {
      const next: (() => void) | undefined = this.waiters.shift();
      if (next !== undefined) {
        next();
      }
      return;
    }
    this.counter++;
  }
}
