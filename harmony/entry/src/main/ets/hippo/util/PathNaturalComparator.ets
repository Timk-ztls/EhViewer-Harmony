/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0497   上游: com/hippo/util/PathNaturalComparator.kt（89 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/PathNaturalComparator.ets
 *
 * 把路径按"分隔符段 / 普通段"切开，**逐段**用 `NaturalComparator` 比较 —— 这样
 * `file2/` 会排在 `file10/` 前面（数字按数值比），而 `/` 与 `\` 作为分隔符不参与自然排序。
 *
 * 平台差异：
 *  1. `Comparator<String?>` → 静态 `compare(o1: string | null, o2: string | null): number`。
 *     ArkTS 无 `Comparator` 接口的函数式实现习惯；但为避免调用点改成 lambda，
 *     同时提供 `PathNaturalComparator.INSTANCE` 兼容 `Array.sort(cmp)` 用法。
 *  2. `Char` → `string`（ArkTS 无 char），`getType` 用单字符字符串比较。
 *  3. null 语义**逐字照搬**：两个 null → 0；o1 null → -1；o2 null → 1。
 */

import { NaturalComparator } from './NaturalComparator';

export class PathNaturalComparator {

  /** 上游 companion 里的 NaturalComparator() 实例（每次新建也可，但复用更省） */
  private static readonly NATURAL: NaturalComparator = new NaturalComparator();

  private static readonly TYPE_SEPARATOR: boolean = false;
  private static readonly TYPE_NORMAL: boolean = true;

  /** 兼容 `Array.sort()` 的用法：`arr.sort(PathNaturalComparator.INSTANCE.compare)` */
  static readonly INSTANCE: PathNaturalComparator = new PathNaturalComparator();

  compare(o1: string | null, o2: string | null): number {
    if (o1 === null && o2 === null) {
      return 0;
    }
    if (o1 === null) {
      return -1;
    }
    if (o2 === null) {
      return 1;
    }
    let index1: number = 0;
    let index2: number = 0;
    while (true) {
      let data1: string | null = null;
      let data2: string | null = null;

      while (true) {
        const newIndex1: number = PathNaturalComparator.nextSegmentStart(o1, index1);
        if (newIndex1 === index1) {
          data1 = null;
          break;
        }
        if (PathNaturalComparator.getType(o1.charAt(newIndex1 - 1))) {
          data1 = o1.substring(index1, newIndex1);
          index1 = newIndex1;
          break;
        }
        index1 = newIndex1;
      }

      while (true) {
        const newIndex2: number = PathNaturalComparator.nextSegmentStart(o2, index2);
        if (newIndex2 === index2) {
          data2 = null;
          break;
        }
        if (PathNaturalComparator.getType(o2.charAt(newIndex2 - 1))) {
          data2 = o2.substring(index2, newIndex2);
          index2 = newIndex2;
          break;
        }
        index2 = newIndex2;
      }

      if (data1 === null && data2 === null) {
        return 0;
      }
      if (data1 === null) {
        return -1;
      }
      if (data2 === null) {
        return 1;
      }

      const result: number = PathNaturalComparator.NATURAL.compare(data1, data2);
      if (result !== 0) {
        return result;
      }
    }
  }

  private static nextSegmentStart(str: string, index: number): number {
    if (index >= str.length) {
      return index;
    }
    const type: boolean = PathNaturalComparator.getType(str.charAt(index));
    let i: number = index + 1;
    while (i < str.length && type === PathNaturalComparator.getType(str.charAt(i))) {
      i += 1;
    }
    return i;
  }

  private static getType(c: string): boolean {
    return (c === '/' || c === '\\') ? PathNaturalComparator.TYPE_SEPARATOR : PathNaturalComparator.TYPE_NORMAL;
  }
}