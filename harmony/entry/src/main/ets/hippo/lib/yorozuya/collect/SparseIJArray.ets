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
 * 条目   : S0403
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/SparseIJArray.java（229 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/SparseIJArray.ets
 *
 * 平台差异：
 *  1. get(int key) / get(int key, long valueIfKeyNotFound) 重载 → get(key) /
 *     getOrDefault(key, valueIfKeyNotFound)（ArkTS 无重载，方案 §5-7）。
 *  2. long → number（ArkTS 无 long）。本类实际负载是 id/大小/时间戳，落在 2^53 内。
 *  3. implements Cloneable + super.clone() 在 ArkTS 无对应物：clone() 改为
 *     显式新建实例 + 数组 slice()。上游是浅拷贝（mValues 元素共享引用），
 *     本实现行为一致（数值类型无引用语义，等价性更强）。
 *  4. CollectionUtils.insert/append 的 int 版 → insertInt/appendInt（同签名，类型入名）。
 *  5. 构造容量为 0 时使用独立空数组而非 CollectionUtils.EMPTY_*（ArkTS Array 可变，
 *     别名会互污；与 IntList/LongList 处理一致）。
 *  6. 逐字保留：二分查找、插入点 ~i、append 快路径、removeAt 的 System.arraycopy 语义、
 *     toString 的 "{k=v, k=v}" 格式（数值均用十进制输出）。
 */

import { CollectionUtils } from './CollectionUtils';
import { ContainerHelpers } from './ContainerHelpers';

/**
 * SparseIJArrays map integers to longs.  Unlike a normal array of longs,
 * there can be gaps in the indices.
 */
export class SparseIJArray {
  private mKeys: number[];
  private mValues: number[];
  private mSize: number;

  constructor(initialCapacity?: number) {
    const capacity: number = initialCapacity === undefined ? 10 : initialCapacity;
    if (capacity === 0) {
      // 上游别名 CollectionUtils.EMPTY_INT_ARRAY / EMPTY_LONG_ARRAY（见差异 5）
      this.mKeys = [];
      this.mValues = [];
    } else {
      const keys: number[] = new Array<number>(capacity);
      keys.fill(0);
      const values: number[] = new Array<number>(capacity);
      values.fill(0);
      this.mKeys = keys;
      this.mValues = values;
    }
    this.mSize = 0;
  }

  clone(): SparseIJArray {
    const clone: SparseIJArray = new SparseIJArray(0);
    clone.mKeys = this.mKeys.slice();
    clone.mValues = this.mValues.slice();
    clone.mSize = this.mSize;
    return clone;
  }

  /**
   * Gets the long mapped from the specified key, or 0 if no such mapping has been made.
   */
  get(key: number): number {
    return this.getOrDefault(key, 0);
  }

  /**
   * Gets the long mapped from the specified key, or the specified value
   * if no such mapping has been made.
   */
  getOrDefault(key: number, valueIfKeyNotFound: number): number {
    const i: number = ContainerHelpers.binarySearchInt(this.mKeys, this.mSize, key);
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
    const i: number = ContainerHelpers.binarySearchInt(this.mKeys, this.mSize, key);
    if (i >= 0) {
      this.removeAt(i);
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
  put(key: number, value: number): void {
    let i: number = ContainerHelpers.binarySearchInt(this.mKeys, this.mSize, key);

    if (i >= 0) {
      this.mValues[i] = value;
    } else {
      i = ~i;
      this.mKeys = CollectionUtils.insertInt(this.mKeys, this.mSize, i, key);
      this.mValues = CollectionUtils.insertInt(this.mValues, this.mSize, i, value);
      this.mSize++;
    }
  }

  /**
   * Returns the number of key-value mappings that this SparseIJArray currently stores.
   */
  size(): number {
    return this.mSize;
  }

  /**
   * Given an index in the range 0...size()-1, returns the key from the
   * index-th key-value mapping that this SparseIJArray stores.
   */
  keyAt(index: number): number {
    return this.mKeys[index];
  }

  /**
   * Given an index in the range 0...size()-1, returns the value from the
   * index-th key-value mapping that this SparseIJArray stores.
   */
  valueAt(index: number): number {
    return this.mValues[index];
  }

  /**
   * Returns the index for which keyAt would return the specified key,
   * or a negative number if the specified key is not mapped.
   */
  indexOfKey(key: number): number {
    return ContainerHelpers.binarySearchInt(this.mKeys, this.mSize, key);
  }

  /**
   * Returns an index for which valueAt would return the specified value,
   * or a negative number if no keys map to the specified value.
   */
  indexOfValue(value: number): number {
    for (let i = 0; i < this.mSize; i++) {
      if (this.mValues[i] === value) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Removes all key-value mappings from this SparseIJArray.
   */
  clear(): void {
    this.mSize = 0;
  }

  /**
   * Puts a key/value pair into the array, optimizing for the case where
   * the key is greater than all existing keys in the array.
   */
  append(key: number, value: number): void {
    if (this.mSize !== 0 && key <= this.mKeys[this.mSize - 1]) {
      this.put(key, value);
      return;
    }
    this.mKeys = CollectionUtils.appendInt(this.mKeys, this.mSize, key);
    this.mValues = CollectionUtils.appendInt(this.mValues, this.mSize, value);
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
      const value: number = this.valueAt(i);
      sb.push(`${value}`);
    }
    sb.push('}');
    return sb.join('');
  }
}
