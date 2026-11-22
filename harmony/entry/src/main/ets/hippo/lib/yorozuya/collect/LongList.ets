/*
 * Copyright 2015 Hippo Seven
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0400
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/LongList.java（190 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/LongList.ets
 *
 * 与 IntList.java 逐行同构，仅元素类型由 int 换 long。平台差异见 IntList.ets
 * 文件头的 1–6 条，此处只列 long 特有项：
 *  1. ArkTS 无 long，元素类型用 number（IEEE754 双精度可精确表示全部 int64 安全整数
 *     区间 |v| ≤ 2^53-1）。上游 LongList 的实际用途是 id/时间戳/文件长度，
 *     全部落在安全区间内；若后续出现 > 2^53 的 id，需在此定点改为 BigInt
 *     （getInternalArray() 的返回类型会随之改变，属于跨模块契约，需 Lead 裁决）。
 *  2. serialize() 的字节布局与上游 Parcel 一致：int32 capacity、int32 size、
 *     然后 mSize 个 int64，全部小端（DataView.setBigInt64 与 writeLong 一致）。
 *     写盘时用 BigInt 转换，避免超过 2^53 时静默丢精度。
 *  3. 严格化同 IntList：负下标补校验，抛同样格式的 RangeError。
 */

const MIN_CAPACITY_INCREMENT: number = 12;

function arrayCopy(src: number[], srcPos: number, dest: number[], destPos: number,
  length: number): void {
  if (length <= 0) {
    return;
  }
  if (src === dest && destPos > srcPos) {
    for (let i = length - 1; i >= 0; i--) {
      dest[destPos + i] = src[srcPos + i];
    }
  } else {
    for (let i = 0; i < length; i++) {
      dest[destPos + i] = src[srcPos + i];
    }
  }
}

export class LongList {
  private mArray: number[];
  private mSize: number = 0;

  constructor(capacity?: number) {
    if (capacity === undefined) {
      // 上游：this.mArray = CollectionUtils.EMPTY_LONG_ARRAY;（见差异 5）
      this.mArray = [];
    } else {
      const a: number[] = new Array<number>(capacity);
      a.fill(0);
      this.mArray = a;
    }
  }

  private static throwIndexOutOfBoundsException(index: number, size: number): void {
    throw new RangeError(`Invalid index ${index}, size is ${size}`);
  }

  private static newCapacity(currentCapacity: number): number {
    const increment: number = (currentCapacity < (MIN_CAPACITY_INCREMENT / 2)
      ? MIN_CAPACITY_INCREMENT : currentCapacity >> 1);
    return currentCapacity + increment;
  }

  add(value: number): void {
    let a: number[] = this.mArray;
    const s: number = this.mSize;
    if (s === a.length) {
      const newSize: number = s + (s < (MIN_CAPACITY_INCREMENT / 2)
        ? MIN_CAPACITY_INCREMENT : s >> 1);
      const newArray: number[] = new Array<number>(newSize);
      newArray.fill(0);
      arrayCopy(a, 0, newArray, 0, s);
      this.mArray = a = newArray;
    }
    a[s] = value;
    this.mSize = s + 1;
  }

  /**
   * 对应上游 add(int location, long value)。
   */
  insert(location: number, value: number): void {
    let a: number[] = this.mArray;
    const s: number = this.mSize;
    if (location > s || location < 0) {
      LongList.throwIndexOutOfBoundsException(location, s);
    }

    if (s < a.length) {
      arrayCopy(a, location, a, location + 1, s - location);
    } else {
      // assert s === a.length
      const newArray: number[] = new Array<number>(LongList.newCapacity(s));
      newArray.fill(0);
      arrayCopy(a, 0, newArray, 0, location);
      arrayCopy(a, location, newArray, location + 1, s - location);
      this.mArray = a = newArray;
    }
    a[location] = value;
    this.mSize = s + 1;
  }

  clear(): void {
    this.mSize = 0;
  }

  contains(value: number): boolean {
    const a: number[] = this.mArray;
    const s: number = this.mSize;
    for (let i = 0; i < s; i++) {
      if (a[i] === value) {
        return true;
      }
    }
    return false;
  }

  get(location: number): number {
    if (location >= this.mSize || location < 0) {
      LongList.throwIndexOutOfBoundsException(location, this.mSize);
    }
    return this.mArray[location];
  }

  indexOf(value: number): number {
    const a: number[] = this.mArray;
    const s: number = this.mSize;
    for (let i = 0; i < s; i++) {
      if (a[i] === value) {
        return i;
      }
    }
    return -1;
  }

  isEmpty(): boolean {
    return this.mSize === 0;
  }

  removeAt(location: number): number {
    const a: number[] = this.mArray;
    let s: number = this.mSize;
    if (location >= s || location < 0) {
      LongList.throwIndexOutOfBoundsException(location, s);
    }
    const result: number = a[location];
    s--;
    arrayCopy(a, location + 1, a, location, s - location);
    this.mSize = s;
    return result;
  }

  remove(value: number): boolean {
    const a: number[] = this.mArray;
    let s: number = this.mSize;
    for (let i = 0; i < s; i++) {
      if (a[i] === value) {
        s--;
        arrayCopy(a, i + 1, a, i, s - i);
        this.mSize = s;
        return true;
      }
    }
    return false;
  }

  set(location: number, value: number): number {
    const a: number[] = this.mArray;
    if (location >= this.mSize || location < 0) {
      LongList.throwIndexOutOfBoundsException(location, this.mSize);
    }
    const result: number = a[location];
    a[location] = value;
    return result;
  }

  size(): number {
    return this.mSize;
  }

  getInternalArray(): number[] {
    return this.mArray;
  }

  toString(): string {
    const a: number[] = this.mArray;
    if (a === null || a === undefined) {
      return 'null';
    }
    if (this.mSize === 0) {
      return '[]';
    }
    const sb: string[] = [];
    sb.push('[');
    sb.push(`${a[0]}`);
    for (let i = 1; i < this.mSize; i++) {
      sb.push(', ');
      sb.push(`${a[i]}`);
    }
    sb.push(']');
    return sb.join('');
  }

  /**
   * 对应上游 writeToParcel(Parcel dest, int flags)。
   * 布局：int32 capacity、int32 size、size × int64，全部小端。
   */
  serialize(): ArrayBuffer {
    const s: number = this.mSize;
    const a: number[] = this.mArray;
    const buffer: ArrayBuffer = new ArrayBuffer(8 + s * 8);
    const view: DataView = new DataView(buffer);
    view.setInt32(0, a.length, true);
    view.setInt32(4, s, true);
    for (let i = 0; i < s; i++) {
      view.setBigInt64(8 + i * 8, BigInt(a[i]), true);
    }
    return buffer;
  }

  /**
   * 对应上游 CREATOR.createFromParcel(Parcel source)。
   */
  static deserialize(buffer: ArrayBuffer): LongList {
    const view: DataView = new DataView(buffer);
    const capacity: number = view.getInt32(0, true);
    const list: LongList = new LongList(capacity);
    const size: number = view.getInt32(4, true);
    list.mSize = size;
    for (let i = 0; i < size; i++) {
      const v: bigint = view.getBigInt64(8 + i * 8, true);
      list.mArray[i] = Number(v);
    }
    return list;
  }
}
