/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0423   上游: com/hippo/lib/yorozuya/SimpleHandler.java（30 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/SimpleHandler.ets
 *
 * 上游是 `extends Handler` 的主线程单例。58 处调用点实际只用到三个方法（已核对 upstream 全量）：
 *   post(Runnable) / postDelayed(Runnable, long) / removeCallbacks(Runnable)
 * 例如 DownloadManager.java:1080/1349/1415、EhClient.java:131、EhApplication.java:306。
 *
 * 平台差异：
 *  1. Handler/Looper/MessageQueue 在 ArkTS 不存在。等价物是宿主事件循环的
 *     setTimeout/clearTimeout（在 UI Ability 的线程上执行），语义对齐：
 *     post → delay 0；postDelayed → 指定毫秒；removeCallbacks → 按 task 引用身份取消。
 *  2. Handler 的其余 API（sendMessage/obtainMessage/sendEmptyMessage/postAtTime）无调用点，
 *     不提供（避免造一个假的消息机制）。
 *  3. 单例字段 sInstance 为模块级静态对象。它是"无需跨 Ability 复用的无状态调度入口"，
 *     不持有业务数据，不触发方案 §5-3 的静态变量约束。
 */

/** 待执行任务的登记项：用于 removeCallbacks 的引用识别 */
class PendingTask {
  task: () => void;
  timerId: number;

  constructor(task: () => void, timerId: number) {
    this.task = task;
    this.timerId = timerId;
  }
}

export class SimpleHandler {

  private static sInstance: SimpleHandler | null = null;

  private mPending: PendingTask[] = [];

  private constructor() {
  }

  static getInstance(): SimpleHandler {
    if (SimpleHandler.sInstance === null) {
      SimpleHandler.sInstance = new SimpleHandler();
    }
    return SimpleHandler.sInstance;
  }

  /** 对应 Handler.post(Runnable)：投递到当前事件循环，尽快执行 */
  post(task: () => void): void {
    this.schedule(task, 0);
  }

  /** 对应 Handler.postDelayed(Runnable, long delayMillis) */
  postDelayed(task: () => void, delayMillis: number): void {
    this.schedule(task, delayMillis);
  }

  /** 对应 Handler.removeCallbacks(Runnable)：按引用身份取消未执行的任务 */
  removeCallbacks(task: () => void): void {
    for (let i = 0; i < this.mPending.length; i++) {
      if (this.mPending[i].task === task) {
        clearTimeout(this.mPending[i].timerId);
        this.mPending.splice(i, 1);
        return;
      }
    }
  }

  private schedule(task: () => void, delayMillis: number): void {
    const timerId: number = setTimeout(() => {
      this.forget(task);
      task();
    }, delayMillis);
    this.mPending.push(new PendingTask(task, timerId));
  }

  private forget(task: () => void): void {
    for (let i = 0; i < this.mPending.length; i++) {
      if (this.mPending[i].task === task) {
        this.mPending.splice(i, 1);
        return;
      }
    }
  }
}