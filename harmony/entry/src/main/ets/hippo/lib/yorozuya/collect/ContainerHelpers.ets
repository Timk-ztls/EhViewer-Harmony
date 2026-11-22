/*
 * Copyright (C) 2013 The Android Open Source Project
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
 * 条目   : S0398
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/ContainerHelpers.java（69 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/ContainerHelpers.ets
 *
 * 平台差异（方案 §5-7 重载改造 + §5-9）：
 *  1. Java 三个同名重载 binarySearch(int[]/long[]/T[]) → ArkTS 按类型入名：
 *       binarySearch(int[], int, int)                        → binarySearchInt
 *       binarySearch(long[], int, long)                      → binarySearchLong
 *       binarySearch(T[], int, T, Comparator<? super T>)     → binarySearchObject
 *  2. java.util.Comparator<? super T> → 函数类型 Comparator<T> = (a: T, b: T) => number，
 *     返回值符号语义与 Comparator.compare 一致（<0 / 0 / >0）。
 *  3. 返回值语义逐字保持：命中返回下标；未命中返回 ~lo（插入点的按位取反），
 *     供 SparseILArray 等使用「一次查找同时判断存在性与插入位置」的上游写法。
 *  4. ArkTS 无 long，binarySearchLong 与 binarySearchInt 实现相同，保留双名以便
 *     上游调用点机械映射。
 */

/**
 * 对应 java.util.Comparator<T>.compare 的符号契约：<0 表示 a<b，0 表示相等，>0 表示 a>b。
 */
export type Comparator<T> = (a: T, b: T) => number;

export class ContainerHelpers {

  // This is Arrays.binarySearch(), but doesn't do any argument validation.
  static binarySearchInt(array: number[], size: number, value: number): number {
    let lo: number = 0;
    let hi: number = size - 1;

    while (lo <= hi) {
      const mid: number = (lo + hi) >>> 1;
      const midVal: number = array[mid];

      if (midVal < value) {
        lo = mid + 1;
      } else if (midVal > value) {
        hi = mid - 1;
      } else {
        return mid;  // value found
      }
    }
    return ~lo;  // value not present
  }

  static binarySearchLong(array: number[], size: number, value: number): number {
    let lo: number = 0;
    let hi: number = size - 1;

    while (lo <= hi) {
      const mid: number = (lo + hi) >>> 1;
      const midVal: number = array[mid];

      if (midVal < value) {
        lo = mid + 1;
      } else if (midVal > value) {
        hi = mid - 1;
      } else {
        return mid;  // value found
      }
    }
    return ~lo;  // value not present
  }

  static binarySearchObject<T>(array: Array<T>, size: number, value: T,
    comparator: Comparator<T>): number {
    let lo: number = 0;
    let hi: number = size - 1;

    while (lo <= hi) {
      const mid: number = (lo + hi) >>> 1;
      const midValCmp: number = comparator(array[mid], value);

      if (midValCmp < 0) {
        lo = mid + 1;
      } else if (midValCmp > 0) {
        hi = mid - 1;
      } else {
        return mid;  // value found
      }
    }
    return ~lo;  // value not present
  }
}
