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
 * 条目   : S0405
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/SparseJBArray.java（232 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/SparseJBArray.ets
 *
 * 平台差异：
 *  1. get(long key) / get(long, boolean) 重载 → get(key) / getOrDefault(key, def)。
 *  2. long 键 → number（ArkTS 无 long）；boolean[] → boolean[]。
 *  3. Cloneable + super.clone() → 显式 clone()（数组 slice() 浅拷贝，行为一致）。
 *  4. CollectionUtils.insert/append → insertLong/insertInt + appendLong/appendBoolean
 *     （对应上游重载：int[] 用 insertLong 形态——上游 insert 的 long 重载；
 *      boolean[] 用 insertBoolean/appendBoolean）。
 *  5. delete(long) 上游未复用 removeAt，而是内联两次 arraycopy —— 逐字保留该形态，
 *     用 copyWithin 表达同数组重叠搬移（与 System.arraycopy 同语义）。
 *  6. 容量 0 用独立空数组（见 IntList 差异 5）。
 */

import { CollectionUtils } from './CollectionUtils';
import { ContainerHelpers } from './ContainerHelpers';

/**
 * SparseJBArrays map longs to booleans.
 */
export class SparseJBArray {
  private mKeys: number[];
  private mValues: boolean[];
  private mSize: number;

  constructor(initialCapacity?: number) {
    const capacity: number = initialCapacity === undefined ? 10 : initialCapacity;
    if (capacity === 0) {
      this.mKeys = [];
      this.mValues = [];
    } else {
      const keys: number[] = new Array<number>(capacity);
      keys.fill(0);
      const values: boolean[] = new Array<boolean>(capacity);
      values.fill(false);
      this.mKeys = keys;
      this.mValues = values;
    }
    this.mSize = 0;
  }

  clone(): SparseJBArray {
    const clone: SparseJBArray = new SparseJBArray(0);
    clone.mKeys = this.mKeys.slice();
    clone.mValues = this.mValues.slice();
    clone.mSize = this.mSize;
    return clone;
  }

  /**
   * Gets the boolean mapped from the specified key, or false if no such mapping has been made.
   */
  get(key: number): boolean {
    return this.getOrDefault(key, false);
  }

  /**
   * Gets the boolean mapped from the specified key, or the specified value
   * if no such mapping has been made.
   */
  getOrDefault(key: number, valueIfKeyNotFound: boolean): boolean {
    const i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
    if (i < 0) {
      return valueIfKeyNotFound;
    } else {
      return this.mValues[i];
    }
  }

  /**
   * Removes the mapping from the specified key, if there was any.
   */
  delete(key: number): void {
    const i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
    if (i >= 0) {
      const count: number = this.mSize - (i + 1);
      if (count > 0) {
        this.mKeys.copyWithin(i, i + 1, i + 1 + count);
        this.mValues.copyWithin(i, i + 1, i + 1 + count);
      }
      this.mSize--;
    }
  }

  /**
   * Removes the mapping at the given index.
   */
  removeAt(index: number): void {
    const count: number = this.mSize - (index + 1);
    if (count > 0) {
      this.mKeys.copyWithin(index, index + 1, index + 1 + count);
      this.mValues.copyWithin(index, index + 1, index + 1 + count);
    }
    this.mSize--;
  }

  /**
   * Adds a mapping from the specified key to the specified value,
   * replacing the previous mapping from the specified key if there was one.
   */
  put(key: number, value: boolean): void {
    let i: number = ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);

    if (i >= 0) {
      this.mValues[i] = value;
    } else {
      i = ~i;
      this.mKeys = CollectionUtils.insertLong(this.mKeys, this.mSize, i, key);
      this.mValues = CollectionUtils.insertBoolean(this.mValues, this.mSize, i, value);
      this.mSize++;
    }
  }

  /**
   * Returns the number of key-value mappings that this SparseJBArray currently stores.
   */
  size(): number {
    return this.mSize;
  }

  /**
   * Given an index in the range 0...size()-1, returns the key from the
   * index-th key-value mapping that this SparseJBArray stores.
   */
  keyAt(index: number): number {
    return this.mKeys[index];
  }

  /**
   * Given an index in the range 0...size()-1, returns the value from the
   * index-th key-value mapping that this SparseJBArray stores.
   */
  valueAt(index: number): boolean {
    return this.mValues[index];
  }

  setValueAt(index: number, value: boolean): void {
    this.mValues[index] = value;
  }

  /**
   * Returns the index for which keyAt would return the specified key,
   * or a negative number if the specified key is not mapped.
   */
  indexOfKey(key: number): number {
    return ContainerHelpers.binarySearchLong(this.mKeys, this.mSize, key);
  }

  /**
   * Returns an index for which valueAt would return the specified value,
   * or a negative number if no keys map to the specified value.
   */
  indexOfValue(value: boolean): number {
    for (let i = 0; i < this.mSize; i++) {
      if (this.mValues[i] === value) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Removes all key-value mappings from this SparseJBArray.
   */
  clear(): void {
    this.mSize = 0;
  }

  /**
   * Puts a key/value pair into the array, optimizing for the case where
   * the key is greater than all existing keys in the array.
   */
  append(key: number, value: boolean): void {
    if (this.mSize !== 0 && key <= this.mKeys[this.mSize - 1]) {
      this.put(key, value);
      return;
    }
    this.mKeys = CollectionUtils.appendLong(this.mKeys, this.mSize, key);
    this.mValues = CollectionUtils.appendBoolean(this.mValues, this.mSize, value);
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
      const value: boolean = this.valueAt(i);
      sb.push(`${value}`);
    }
    sb.push('}');
    return sb.join('');
  }
}
