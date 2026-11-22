/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0015   上游: com/hippo/conaco/Register.java（59 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/Register.ets
 *
 * 平台差异：
 *  1. `synchronized` 方法 → 无锁（方案 §5-4：单 VM 无共享内存线程，conaco 的调用都在同一
 *     任务调度域内）。**登记为"无可观察差异"**，与已批准的 C-XXX 口径一致。
 *  2. `SparseILArray<ConacoTask<V>>` / `Multimap<String, ConacoTask<V>>` → 直接复用已移植的
 *     `SparseILArray` / `Multimap`（S0400/S0401），行为一致（含 Multimap 的多值语义）。
 *  3. **`ConacoTask` 尚未移植**，故用一个最小契约 `ConacoTaskLike` 表达 Register 唯一依赖的成员
 *     `getKey(): string | null`。这不是发明 API —— 上游 Register 对 task 的全部用法就是
 *     `task.getKey()` + 类型承载；`ConacoTask` 落地时只要 `implements ConacoTaskLike` 即可，
 *     接口本身不需要再改。ArkTS 禁结构化类型（arkts-no-structural-typing），所以必须有显式接口。
 *  4. `List<ConacoTask<V>> get(key)` → `T[] | null`（C-13：可空一律 `| null`）。
 */

import { Multimap } from '../lib/yorozuya/collect/Multimap';
import { SparseILArray } from '../lib/yorozuya/collect/SparseILArray';

/** Register 对任务对象的唯一依赖（见文件头差异 3） */
export interface ConacoTaskLike {
  getKey(): string | null;
}

export class Register<V, T extends ConacoTaskLike> {

  private readonly mIdMap: SparseILArray<T> = new SparseILArray<T>();
  private readonly mKeyMap: Multimap<string | null, T> = Multimap.create<string | null, T>();

  /**
   * @return true 表示该 key 已经注册过（重复 key）
   */
  register(id: number, task: T): boolean {
    let repeatedKey: boolean = false;
    const taskKey: string | null = task.getKey();

    // For no-key task, there no need to check
    if (taskKey !== null) {
      repeatedKey = this.mKeyMap.countElements(taskKey) !== 0;
    }

    // Append task
    this.mKeyMap.putElement(taskKey, task);
    this.mIdMap.append(id, task);

    return repeatedKey;
  }

  unregister(id: number): T | null {
    const task: T | undefined = this.mIdMap.remove(id);
    if (task === undefined) {
      return null;
    }
    this.mKeyMap.removeElement(task.getKey(), task);
    return task;
  }

  contain(id: number): boolean {
    return this.mIdMap.indexOfKey(id) >= 0;
  }

  getByKey(key: string | null): T | null {
    if (key === null) {
      return null;
    }
    const list: T[] | undefined = this.mKeyMap.get(key);
    if (list !== undefined && list.length > 0) {
      return list[0];
    }
    return null;
  }
}