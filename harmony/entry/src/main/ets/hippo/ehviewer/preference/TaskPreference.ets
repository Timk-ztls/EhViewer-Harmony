/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0174   上游: com/hippo/ehviewer/preference/TaskPreference.java（193 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/preference/TaskPreference.ets
 *
 * 【D-033 拆分 + 平台判据】上游 `TaskPreference extends DialogPreference`，内嵌
 * `Task extends AsyncTask<Void, int[], Object>`。两者都是 **Android UI/线程框架的类**：
 *   · `DialogPreference` / `AlertDialog.Builder` / `ProgressBar.findViewById` → **UI，归 ui-widget**
 *   · `AsyncTask.executeOnExecutor` → 由 `IoThreadPoolExecutor` 覆盖（已交付，含并发上限与回压）
 *   · `AbsSavedState` / `Parcelable` → 鸿蒙侧由 ArkUI 的 `@State`/`onPageHide` 机制承担
 *   **不硬造 AsyncTask / DialogPreference**（D-033 判据：平台无对应概念时不硬造）。
 *
 * 因此本文件只落两段**真正的纯逻辑**：
 *  1. `TaskProgress.normalize(current, total)` —— 上游 `onProgressUpdate` 里的进度归一化：
 *       - `total <= 0` → **不确定进度**（indeterminate）
 *       - 否则 clamp `current` 到 `[0, total]`，再 setMax/setProgress
 *     这段是上游自己的防御逻辑（`if (current < 0) current = 0; if (current > total) current = total;`），
 *     与 UI 无关，且**可断言**。
 *  2. `TaskRegistry` —— 上游用 `EhApplication.putGlobalStuff(task)` 分配 int id、
 *     `removeGlobalStuff(task)` 清理，并把 id 存进 `SavedState.asyncTaskId` 以便
 *     **进程重建后重新 attach 到同一个 Task**（`onRestoreInstanceState`）。
 *     这里复用已落地的 `EhApplication.putGlobalStuff/getGlobalStuff/removeGlobalStuff`。
 *
 * 上游 `Task` 的其余成员（`getApplication/getPreference/setPreference`、`doInBackground` 抽象）
 * 是编排胶水，由 ui-widget 的组件 + `IoThreadPoolExecutor` 组合完成，本文件提供 `TaskRunner` 契约。
 */

import { EhApplication } from '../EhApplication';
import { IoThreadPoolExecutor } from '../../util/IoThreadPoolExecutor';

/** 归一化后的进度状态（对应上游对 ProgressBar 的三次调用：setIndeterminate/setMax/setProgress） */
export class TaskProgress {
  /** true → 上游调用 `bar.setIndeterminate(true)`（total <= 0） */
  indeterminate: boolean = false;
  /** 仅 indeterminate=false 时有意义（bar.setMax） */
  max: number = 0;
  /** 仅 indeterminate=false 时有意义（bar.setProgress） */
  progress: number = 0;
}

/** 上游 `Task extends AsyncTask<Void, int[], Object>` 的纯执行契约 */
export interface TaskRunner {
  /** 对应 `doInBackground`；返回 null 表示无结果（上游 `onPostExecute(null)`） */
  doInBackground(): Promise<Object | null>;
  /** 对应 `onProgressUpdate(int[] {current,total})`；UI 层据 TaskProgress 更新进度条 */
  onProgress(current: number, total: number): void;
  /** 对应 `onPostExecute(Object)` */
  onPostExecute(o: Object | null): void;
  /** 对应 `onCancelled`（上游 Task 没有覆写，但 ConacoTask 那套有；保留契约便于组合） */
  onCancelled(): void;
}

export class TaskPreference {

  /**
   * 对应上游 `Task.onProgressUpdate` 的判定：
   *   `if (total <= 0) indeterminate=true; else { clamp current; max=total; progress=current }`
   * 上游还有两道前置守卫（`mPreference == null` / `dialog == null` / `bar == null` / `values.length < 2`）
   * 都是 UI 存在性检查，归 ui-widget；这里只保留**数值语义**。
   */
  static normalizeProgress(current: number, total: number): TaskProgress {
    const p: TaskProgress = new TaskProgress();
    if (total <= 0) {
      p.indeterminate = true;
      return p;
    }
    let c: number = current;
    // Ensure current in bounds（逐字照搬）
    if (c < 0) {
      c = 0;
    }
    if (c > total) {
      c = total;
    }
    p.indeterminate = false;
    p.max = total;
    p.progress = c;
    return p;
  }

  /**
   * 对应上游 `TaskPreference.onDialogCreated` + `onRestoreInstanceState` 的 id 生命周期：
   * 启动时 `putGlobalStuff(task)` 拿 id（供进程重建后找回），结束时 `removeGlobalStuff(task)`。
   *
   * @returns 启动后的 taskId；**`-1`（INVALID_ID）** 表示未启动（对齐 `IntIdGenerator.INVALID_ID`）
   */
  static startTask(task: Object): number {
    const app: EhApplication | null = EhApplication.getInstance();
    if (app === null) {
      return -1;
    }
    return app.putGlobalStuff(task);
  }

  /** 对应上游 `Task.onPostExecute` 的 `mApplication.removeGlobalStuff(this)` */
  static finishTask(task: Object): void {
    const app: EhApplication | null = EhApplication.getInstance();
    if (app !== null) {
      app.removeGlobalStuff(task);
    }
  }

  /**
   * 对应上游 `onRestoreInstanceState`：按保存的 id 找回同一个 Task 实例。
   * 找不到 → 返回 null（上游此时把 `mTaskId` 置回 INVALID_ID）。
   */
  static restoreTask(taskId: number): Object | null {
    if (taskId === -1) {
      return null;
    }
    const app: EhApplication | null = EhApplication.getInstance();
    if (app === null) {
      return null;
    }
    return app.getGlobalStuff(taskId);
  }

  /**
   * 组合执行：对应 `onDialogCreated` 里 `mTask.executeOnExecutor(IoThreadPoolExecutor.getInstance())`。
   * 进度回调交给调用方（UI 层），这里只保证 **执行 → 进度 → 结束/取消** 的调用顺序与上游一致。
   */
  static run(task: TaskRunner, onDone?: (taskId: number) => void): void {
    const taskId: number = TaskPreference.startTask(task);
    IoThreadPoolExecutor.getInstance().execute(async () => {
      let result: Object | null = null;
      let cancelled: boolean = false;
      try {
        result = await task.doInBackground();
      } catch (e) {
        cancelled = true;
      }
      if (cancelled) {
        task.onCancelled();
      } else {
        task.onPostExecute(result);
      }
      // 对应上游 onPostExecute 里的 removeGlobalStuff（取消路径也清理，避免 global stuff 泄漏）
      TaskPreference.finishTask(task);
      if (onDone !== undefined) {
        onDone(taskId);
      }
    });
  }
}
