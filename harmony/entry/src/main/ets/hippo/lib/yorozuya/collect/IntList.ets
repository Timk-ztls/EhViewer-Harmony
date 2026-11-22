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
 * 条目   : S0399
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/IntList.java（190 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/IntList.ets
 *
 * 平台差异（方案 §5-7 重载改造 + §5-8 异常模型 + §4 Parcelize 手写序列化）：
 *  1. Java 的 add(int) / add(int,int) 重载 → add(value) / insert(location, value)。
 *     其余方法名（get/set/removeAt/remove/clear/contains/indexOf/isEmpty/size/
 *     getInternalArray）与上游完全一致。
 *  2. Parcelable + Parcel（android.os）在鸿蒙不存在。改为：
 *       serialize(): ArrayBuffer          ← writeToParcel
 *       static deserialize(buf): IntList  ← CREATOR.createFromParcel
 *     字节布局与上游 Parcel 完全一致：writeInt(mArray.length)、writeInt(mSize)、
 *     然后 mSize 个 int，全部小端 int32（Android Parcel 在小端设备上即小端）。
 *     describeContents()（恒返回 0）与 newArray() 无对应物，随 Parcelable 一起删除。
 *  3. IndexOutOfBoundsException → RangeError，消息串逐字保留
 *     "Invalid index <index>, size is <size>"。
 *  4. 严格化一处：上游 get/set/removeAt 只校验上界（负下标由 JVM 抛
 *     ArrayIndexOutOfBoundsException），ArkTS 数组负下标会静默返回 undefined。
 *     本移植在同样位置补上 < 0 校验，抛同样格式的 RangeError。
 *     合法下标路径行为零差异。
 *  5. 上游默认构造用 CollectionUtils.EMPTY_INT_ARRAY 作 mArray（Java 长度 0 的数组
 *     不可写，别名安全）。ArkTS 的 Array 可 push，共享别名会被污染，
 *     故默认构造改为独立空数组；对调用方不可观察。
 *  6. Java int → ArkTS number（IEEE754 双精度，可精确表示 int32 全范围）。
 *     上游所有运算都在 int32 范围内，无溢出路径，故无数值差异。
 */

const MIN_CAPACITY_INCREMENT: number = 12;

/**
 * System.arraycopy(src, srcPos, dest, destPos, length) 的最小等价实现。
 * 支持同数组重叠区间（Java 语义），方向由 srcPos/destPos 关系决定。
 */
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

export class IntList {
  private mArray: number[];
  private mSize: number = 0;

  constructor(capacity?: number) {
    if (capacity === undefined) {
      // 上游：this.mArray = CollectionUtils.EMPTY_INT_ARRAY;
      // ArkTS 下数组可变，不能共享别名（见文件头差异 5）
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
   * 对应上游 add(int location, int value)。
   */
  insert(location: number, value: number): void {
    let a: number[] = this.mArray;
    const s: number = this.mSize;
    if (location > s || location < 0) {
      IntList.throwIndexOutOfBoundsException(location, s);
    }

    if (s < a.length) {
      arrayCopy(a, location, a, location + 1, s - location);
    } else {
      // assert s === a.length
      const newArray: number[] = new Array<number>(IntList.newCapacity(s));
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
      IntList.throwIndexOutOfBoundsException(location, this.mSize);
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
      IntList.throwIndexOutOfBoundsException(location, s);
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
      IntList.throwIndexOutOfBoundsException(location, this.mSize);
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
   * 布局：int32 capacity、int32 size、size × int32，全部小端。
   */
  serialize(): ArrayBuffer {
    const s: number = this.mSize;
    const a: number[] = this.mArray;
    const buffer: ArrayBuffer = new ArrayBuffer(8 + s * 4);
    const view: DataView = new DataView(buffer);
    view.setInt32(0, a.length, true);
    view.setInt32(4, s, true);
    for (let i = 0; i < s; i++) {
      view.setInt32(8 + i * 4, a[i], true);
    }
    return buffer;
  }

  /**
   * 对应上游 CREATOR.createFromParcel(Parcel source)。
   */
  static deserialize(buffer: ArrayBuffer): IntList {
    const view: DataView = new DataView(buffer);
    const capacity: number = view.getInt32(0, true);
    const list: IntList = new IntList(capacity);
    const size: number = view.getInt32(4, true);
    list.mSize = size;
    for (let i = 0; i < size; i++) {
      list.mArray[i] = view.getInt32(8 + i * 4, true);
    }
    return list;
  }
}
