/*
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
 * 条目   : S0397
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/CollectionUtils.java（152 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/CollectionUtils.ets
 *
 * 平台差异（方案 §5-7 重载改造 + §5-9 集合 API 差异）：
 *  1. Java 的 append/insert 各有 4 个重载（T[] / boolean[] / int[] / long[]），
 *     ArkTS 无重载，按「类型入名」拆分：
 *       append(T[], int, T)                → append
 *       append(boolean[], int, boolean)    → appendBoolean
 *       append(int[], int, int)            → appendInt
 *       append(long[], int, long)          → appendLong
 *       insert(T[], int, int, T)           → insert
 *       insert(boolean[], int, int, bool)  → insertBoolean
 *       insert(int[], int, int, int)       → insertInt
 *       insert(long[], int, int, long)     → insertLong
 *     注意 ArkTS 只有 number，long 与 int 在类型层不可区分，appendLong/insertLong
 *     与 appendInt/insertInt 实现相同，保留双名仅为让上游调用点可机械映射、
 *     并在后续需要 BigInt 语义时能定点替换。
 *  2. System.arraycopy → 显式循环。语义逐字对齐 Java：源区间 [from, from+len)，
 *     越界时 Java 抛 IndexOutOfBoundsException，此处抛 RangeError。
 *  3. 泛型数组创建：Java 用 (T[]) new Object[n]（型擦除），ArkTS 用
 *     new Array<T>(n)；Java 侧 [currentSize, capacity) 为 null，ArkTS 侧为 undefined，
 *     两者在调用方都是「未写入的空槽」，不参与读取。
 *  4. 基本类型数组 (boolean[]/int[]) 新块用 0/false 预填，对齐 Java 数组默认值，
 *     避免 ArkTS 稀疏数组读到 undefined。
 *  5. EMPTY_* 常量保留名称与类型。上游 IntList/LongList 默认直接别名
 *     EMPTY_INT_ARRAY（Java 数组长度 0 不可写，别名安全）；ArkTS 的 Array 可 push，
 *     别名会互相污染，故 IntList/LongList 改为各自持有独立空数组，
 *     不改变任何可观察行为（见 IntList.ets 差异说明）。
 */

export class CollectionUtils {

  /**
   * An empty immutable {@code boolean} array.
   */
  static readonly EMPTY_BOOLEAN_ARRAY: boolean[] = [];

  /**
   * An empty immutable {@code int} array.
   */
  static readonly EMPTY_INT_ARRAY: number[] = [];

  /**
   * An empty immutable {@code long} array.
   */
  static readonly EMPTY_LONG_ARRAY: number[] = [];

  /**
   * An empty immutable {@code String} array.
   */
  static readonly EMPTY_OBJECT_ARRAY: Object[] = [];

  /**
   * Appends an element to the end of the array, growing the array if there is no more room.
   *
   * @param array       The array to which to append the element. This must NOT be null.
   * @param currentSize The number of elements in the array. Must be less than or equal to
   *                    array.length.
   * @param element     The element to append.
   * @return the array to which the element was appended. This may be different than the given
   * array.
   */
  static append<T>(array: Array<T>, currentSize: number, element: T): Array<T> {
    if (currentSize + 1 > array.length) {
      const newArray: Array<T> = new Array<T>(CollectionUtils.growSize(currentSize));
      CollectionUtils.arrayCopy(array, 0, newArray, 0, currentSize);
      array = newArray;
    }
    array[currentSize] = element;
    return array;
  }

  /**
   * Primitive boolean version of {@link #append}.
   */
  static appendBoolean(array: boolean[], currentSize: number, element: boolean): boolean[] {
    if (currentSize + 1 > array.length) {
      const newArray: boolean[] = new Array<boolean>(CollectionUtils.growSize(currentSize));
      newArray.fill(false);
      CollectionUtils.arrayCopy(array, 0, newArray, 0, currentSize);
      array = newArray;
    }
    array[currentSize] = element;
    return array;
  }

  /**
   * Primitive int version of {@link #append}.
   */
  static appendInt(array: number[], currentSize: number, element: number): number[] {
    if (currentSize + 1 > array.length) {
      const newArray: number[] = new Array<number>(CollectionUtils.growSize(currentSize));
      newArray.fill(0);
      CollectionUtils.arrayCopy(array, 0, newArray, 0, currentSize);
      array = newArray;
    }
    array[currentSize] = element;
    return array;
  }

  /**
   * Primitive long version of {@link #append}.
   * ArkTS 无 long，实现与 {@link #appendInt} 相同。
   */
  static appendLong(array: number[], currentSize: number, element: number): number[] {
    return CollectionUtils.appendInt(array, currentSize, element);
  }

  /**
   * Inserts an element into the array at the specified index, growing the array if there is no
   * more room.
   *
   * @param array       The array to which to append the element. Must NOT be null.
   * @param currentSize The number of elements in the array. Must be less than or equal to
   *                    array.length.
   * @param element     The element to insert.
   * @return the array to which the element was appended. This may be different than the given
   * array.
   */
  static insert<T>(array: Array<T>, currentSize: number, index: number, element: T): Array<T> {
    if (currentSize + 1 <= array.length) {
      CollectionUtils.arrayCopy(array, index, array, index + 1, currentSize - index);
      array[index] = element;
      return array;
    }

    const newArray: Array<T> = new Array<T>(CollectionUtils.growSize(currentSize));
    CollectionUtils.arrayCopy(array, 0, newArray, 0, index);
    newArray[index] = element;
    // 注意：此处上游用的是 array.length - index（容量，不是 currentSize），
    // 移植保持原样（bug-for-bug 等价），不要"修"成 currentSize - index。
    CollectionUtils.arrayCopy(array, index, newArray, index + 1, array.length - index);
    return newArray;
  }

  /**
   * Primitive boolean version of {@link #insert}.
   */
  static insertBoolean(array: boolean[], currentSize: number, index: number,
    element: boolean): boolean[] {
    if (currentSize + 1 <= array.length) {
      CollectionUtils.arrayCopy(array, index, array, index + 1, currentSize - index);
      array[index] = element;
      return array;
    }

    const newArray: boolean[] = new Array<boolean>(CollectionUtils.growSize(currentSize));
    newArray.fill(false);
    CollectionUtils.arrayCopy(array, 0, newArray, 0, index);
    newArray[index] = element;
    CollectionUtils.arrayCopy(array, index, newArray, index + 1, array.length - index);
    return newArray;
  }

  /**
   * Primitive int version of {@link #insert}.
   */
  static insertInt(array: number[], currentSize: number, index: number, element: number): number[] {
    if (currentSize + 1 <= array.length) {
      CollectionUtils.arrayCopy(array, index, array, index + 1, currentSize - index);
      array[index] = element;
      return array;
    }

    const newArray: number[] = new Array<number>(CollectionUtils.growSize(currentSize));
    newArray.fill(0);
    CollectionUtils.arrayCopy(array, 0, newArray, 0, index);
    newArray[index] = element;
    CollectionUtils.arrayCopy(array, index, newArray, index + 1, array.length - index);
    return newArray;
  }

  /**
   * Primitive long version of {@link #insert}.
   * ArkTS 无 long，实现与 {@link #insertInt} 相同。
   */
  static insertLong(array: number[], currentSize: number, index: number, element: number): number[] {
    return CollectionUtils.insertInt(array, currentSize, index, element);
  }

  /**
   * Given the current size of an array, returns an ideal size to which the array should grow.
   * This is typically double the given size, but should not be relied upon to do so in the
   * future.
   */
  static growSize(currentSize: number): number {
    return currentSize <= 4 ? 8 : currentSize * 2;
  }

  /**
   * System.arraycopy 的等价实现（Java 语义：支持同数组重叠拷贝，方向由区间关系决定）。
   * 越界抛 RangeError（Java 抛 IndexOutOfBoundsException）。
   */
  private static arrayCopy<T>(src: Array<T>, srcPos: number, dest: Array<T>, destPos: number,
    length: number): void {
    if (length < 0 || srcPos < 0 || destPos < 0
      || srcPos + length > src.length || destPos + length > dest.length) {
      throw new RangeError(`arraycopy out of bounds: srcPos=${srcPos}, destPos=${destPos}, ` +
        `length=${length}, src.length=${src.length}, dest.length=${dest.length}`);
    }
    if (src === dest && destPos > srcPos) {
      // 向后搬：从尾部倒序，避免覆盖
      for (let i = length - 1; i >= 0; i--) {
        dest[destPos + i] = src[srcPos + i];
      }
    } else {
      for (let i = 0; i < length; i++) {
        dest[destPos + i] = src[srcPos + i];
      }
    }
  }
}
