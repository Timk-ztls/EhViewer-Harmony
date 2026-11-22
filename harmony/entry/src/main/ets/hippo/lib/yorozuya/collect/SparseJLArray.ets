/*
 * Copyright (C) 2006 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0406
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/SparseJLArray.java（357 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/SparseJLArray.ets
 *
 * 平台差异：
 *  1. get(int) / get(int, E) 重载 → get(key) / getOrDefault(key, valueIfKeyNotFound)。
 *     get(key) 返回 E | undefined（对应上游 null），调用方写 `const v = a.get(k);
 *     if (v === undefined) …`。
 *  2. 删除标记：上游用私有哨兵对象 `DELETED = new Object()` 占位在 Object[] 里。
 *     ArkTS 泛型数组无法容纳异类型哨兵（E 不是 Object 的超类型），改为
 *     **平行 boolean[] mDeleted** 标记删除位。可观察行为完全一致：
 *     get/getOrDefault/delete/removeReturnOld/removeAt/put/append/size/valueAt/
 *     indexOfValue/toString 的返回值与顺序不变（哨兵本就私有、外部拿不到）。
 *  3. 【内存滞留 · DEVIATIONS D-011 · 已由 Lead 批准】
 *     **槽位不置 null，对象引用滞留至数组重建。**
 *     上游 gc()/clear() 会把被移除的槽位写 null 以尽早释放对象引用；ArkTS 泛型数组
 *     （Array<E>）在类型层不能写入 null，本实现只清 mDeleted 标记位，被删对象的引用
 *     仍留在 epoch 数组中，直到该槽位被新值覆盖。
 *     **数组重建（= 释放滞留引用的唯一时机）触发条件**：
 *       a) CollectionUtils.insert/append 在容量不足时新建数组（growSize：len<=4 时取 8，
 *          否则 len*2）并整体拷贝，旧数组随之可回收 —— 这是唯一会让滞留引用消失的路径；
 *       b) removeAtRange / removeAt / delete 只翻标记位，**不**重建数组；
 *       c) gc() 只在原地压缩 (keys/values/deleted 前移)，**不**缩小数组、**不**重建。
 *     影响面：长生命周期的大对象集合（如上千条 Gallery 条目缓存）会有内存滞留，
 *     上限 = 当前 capacity 个槽位；稀疏数组设计用途是数百条映射，故此滞留量有界。
 *     对外可观察行为（get/size/valueAt/keyAt/indexOfValue/toString）完全一致。
 *  4. implements Cloneable + super.clone() → 显式 clone()（4 个数组 slice() 浅拷贝，
 *     与上游浅拷贝语义一致）。
 *  5. CollectionUtils.insert/append 的 int/Object 重载 → insertLong/insert<E>/appendLong/append<E>/
 *     insertBoolean/appendBoolean（ArkTS 无重载，类型入名）。
 *  6. System.arraycopy（removeAtRange 不涉及；put 的插入走 CollectionUtils.insert）→
 *     同数组重叠搬移用 copyWithin（语义等同 System.arraycopy）。
 *  8. long 键 → number（ArkTS 无 long，与 S0403/S0405 一致；本类键为 id/时间戳，落在 2^53 内）。
 *  7. java.lang.Math.min → Math.min；`mValues[i] == DELETED` 的引用比较 →
 *     mDeleted[i] 布尔比较。
 */

import { CollectionUtils } from './CollectionUtils';
import { ContainerHelpers } from './ContainerHelpers';

/**
 * SparseJLArrays map longs to Objects.  Unlike a normal array of Objects,
 * there can be gaps in the indices.
 */
export class SparseJLArray<E> {
  private mGarbage: boolean = false;

  private mKeys: number[];
  private mValues: Array<E>;
  /** 删除标记：mDeleted[i] === true 表示 mValues[i]/mKeys[i] 逻辑上已删除 */
  private mDeleted: boolean[];
  private mSize: number = 0;

  constructor(initialCapacity?: number) {
    const capacity: number = initialCapacity === undefined ? 10 : initialCapacity;
    if (capacity === 0) {
      // 上游别名 CollectionUtils.EMPTY_*（ArkTS Array 可变，不能别名）
      this.mKeys = [];
      this.mValues = [];
      this.mDeleted = [];
    } else {
      const keys: number[] = new Array<number>(capacity);
      keys.fill(0);
      const deleted: boolean[] = new Array<boolean>(capacity);
      deleted.fill(false);
      this.mKeys = keys;
      this.mValues = new Array<E>(capacity);
      this.mDeleted = deleted;
    }
    this.mSize = 0;
  }

  clone(): SparseJLArray<E> {
    const clone: SparseJLArray<E> = new SparseJLArray<E>(0);
    clone.mKeys = this.mKeys.slice();
    clone.mValues = this.mValues.slice();
    clone.mDeleted = this.mDeleted.slice();
    clone.mSize = this.mSize;
    clone.mGarbage = this.mGarbage;
    return clone;
  }

  /**
   * Gets the Object mapped from the specified key, or undefined
   * if no such mapping has been made.
   */
  get(key: number): E | undefined {
    const i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
    if (i < 0 || this.mDeleted[i]) {
      return undefined;
    } else {
      return this.mValues[i];
    }
  }

  /**
   * Gets the Object mapped from the specified key, or the specified Object
   * if no such mapping has been made.
   */
  getOrDefault(key: number, valueIfKeyNotFound: E): E {
    const i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
    if (i < 0 || this.mDeleted[i]) {
      return valueIfKeyNotFound;
    } else {
      return this.mValues[i];
    }
  }

  /**
   * Removes the mapping from the specified key, if there was any.
   */
  delete(key: number): E | undefined {
    const i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
    if (i >= 0 && !this.mDeleted[i]) {
      const deleted: E = this.mValues[i];
      this.mDeleted[i] = true;
      this.mGarbage = true;
      return deleted;
    }
    return undefined;
  }

  /**
   * Removes the mapping from the specified key, if there was any, returning the old value.
   */
  removeReturnOld(key: number): E | undefined {
    const i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
    if (i >= 0 && !this.mDeleted[i]) {
      const old: E = this.mValues[i];
      this.mDeleted[i] = true;
      this.mGarbage = true;
      return old;
    }
    return undefined;
  }

  /**
   * Alias for delete(key).
   */
  remove(key: number): E | undefined {
    return this.delete(key);
  }

  /**
   * Removes the mapping at the specified index.
   */
  removeAt(index: number): void {
    if (!this.mDeleted[index]) {
      this.mDeleted[index] = true;
      this.mGarbage = true;
    }
  }

  /**
   * Remove a range of mappings as a batch.
   */
  removeAtRange(index: number, size: number): void {
    const end: number = Math.min(this.mSize, index + size);
    for (let i = index; i < end; i++) {
      this.removeAt(i);
    }
  }

  private gc(): void {
    const n: number = this.mSize;
    let o: number = 0;
    const keys: number[] = this.mKeys;
    const values: Array<E> = this.mValues;
    const deleted: boolean[] = this.mDeleted;

    for (let i = 0; i < n; i++) {
      if (!deleted[i]) {
        if (i !== o) {
          keys[o] = keys[i];
          values[o] = values[i];
          deleted[o] = false;
          deleted[i] = false;
          // 上游此处置 values[i] = null 释放引用，见文件头差异 3
        }
        o++;
      }
    }

    this.mGarbage = false;
    this.mSize = o;
  }

  /**
   * Adds a mapping from the specified key to the specified value,
   * replacing the previous mapping from the specified key if there was one.
   */
  put(key: number, value: E): void {
    let i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);

    if (i >= 0) {
      this.mValues[i] = value;
      this.mDeleted[i] = false;
    } else {
      i = ~i;

      if (i < this.mSize && this.mDeleted[i]) {
        this.mKeys[i] = key;
        this.mValues[i] = value;
        this.mDeleted[i] = false;
        return;
      }

      if (this.mGarbage && this.mSize >= this.mKeys.length) {
        this.gc();
        // Search again because indices may have changed.
        i = ~ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
      }

      this.mKeys = CollectionUtils.insertLong(this.mKeys, this.mSize, i, key);
      this.mValues = CollectionUtils.insert<E>(this.mValues, this.mSize, i, value);
      this.mDeleted = CollectionUtils.insertBoolean(this.mDeleted, this.mSize, i, false);
      this.mSize++;
    }
  }

  /**
   * Returns the number of key-value mappings that this SparseJLArray currently stores.
   */
  size(): number {
    if (this.mGarbage) {
      this.gc();
    }
    return this.mSize;
  }

  /**
   * Given an index in the range 0...size()-1, returns the key from the
   * index-th key-value mapping that this SparseJLArray stores.
   */
  keyAt(index: number): number {
    if (this.mGarbage) {
      this.gc();
    }
    return this.mKeys[index];
  }

  /**
   * Given an index in the range 0...size()-1, returns the value from the
   * index-th key-value mapping that this SparseJLArray stores.
   */
  valueAt(index: number): E {
    if (this.mGarbage) {
      this.gc();
    }
    return this.mValues[index];
  }

  /**
   * Given an index in the range 0...size()-1, sets a new value for the
   * index-th key-value mapping that this SparseJLArray stores.
   */
  setValueAt(index: number, value: E): void {
    if (this.mGarbage) {
      this.gc();
    }
    this.mValues[index] = value;
    this.mDeleted[index] = false;
  }

  /**
   * Returns the index for which keyAt would return the specified key,
   * or a negative number if the specified key is not mapped.
   */
  indexOfKey(key: number): number {
    if (this.mGarbage) {
      this.gc();
    }
    return ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
  }

  /**
   * Returns an index for which valueAt would return the specified value,
   * or a negative number if no keys map to the specified value.
   * 注意：与上游一致，用引用/值相等比较（不是深度 equal）。
   */
  indexOfValue(value: E): number {
    if (this.mGarbage) {
      this.gc();
    }
    for (let i = 0; i < this.mSize; i++) {
      if (this.mValues[i] === value) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Removes all key-value mappings from this SparseJLArray.
   */
  clear(): void {
    const n: number = this.mSize;
    for (let i = 0; i < n; i++) {
      this.mDeleted[i] = false;
    }
    this.mSize = 0;
    this.mGarbage = false;
  }

  /**
   * Puts a key/value pair into the array, optimizing for the case where
   * the key is greater than all existing keys in the array.
   */
  append(key: number, value: E): void {
    if (this.mSize !== 0 && key <= this.mKeys[this.mSize - 1]) {
      this.put(key, value);
      return;
    }

    if (this.mGarbage && this.mSize >= this.mKeys.length) {
      this.gc();
    }

    this.mKeys = CollectionUtils.appendLong(this.mKeys, this.mSize, key);
    this.mValues = CollectionUtils.append<E>(this.mValues, this.mSize, value);
    this.mDeleted = CollectionUtils.appendBoolean(this.mDeleted, this.mSize, false);
    this.mSize++;
  }

  toString(): string {
    if (this.size() <= 0) {
      return '{}';
    }
    const sb: string[] = [];
    sb.push('{');
    for (let i = 0; i < this.mSize; i++) {
      if (i > 0) {
        sb.push(', ');
      }
      const key: number = this.keyAt(i);
      sb.push(`${key}`);
      sb.push('=');
      const value: E = this.valueAt(i);
      if ((value as Object) === (this as Object)) {
        sb.push('(this Map)');
      } else {
        sb.push(`${value}`);
      }
    }
    sb.push('}');
    return sb.join('');
  }
}
