/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0495   上游: com/hippo/util/NaturalComparator.kt（144 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/NaturalComparator.ets
 *
 * 平台差异：
 *  1. Kotlin `Comparator<String?>` 接口 → ArkTS 无 Comparator 接口（yorozuya 里的
 *     `Comparator<T>` 是**函数类型** `(a,b)=>number`）。故本类：
 *       - 提供 `compare(o1, o2): number` 方法（面向对象用法，与上游同形）
 *       - 同时导出 `naturalCompare` 函数常量，可直接传给 `Array.sort()`
 *  2. Kotlin 的 `s[index]` 字符取址 → `str.charAt(index)`（返回单字符 string）
 *  3. `String.compareTo(other, ignoreCase = true)` → 手写大小写不敏感比较
 *     （逐字符 toLowerCase 后比 charCode；与原实现等价）
 *  4. `Char in '0'..'9'` → `ch >= '0' && ch <= '9'`（ArkTS 支持单字符字符串比较）
 *  5. 语义逐条保留：null 排最前（null<null=0, null<非null=-1）、数字段去前导零后先比长度
 *     再逐位比、等值时**短的原串排前**（`-s1.length.compareTo(s2.length)`）
 */

export class NaturalComparator {

  compare(o1: string | null | undefined, o2: string | null | undefined): number {
    if ((o1 === null || o1 === undefined) && (o2 === null || o2 === undefined)) {
      return 0;
    }
    if (o1 === null || o1 === undefined) {
      return -1;
    }
    if (o2 === null || o2 === undefined) {
      return 1;
    }
    const s1: string = o1;
    const s2: string = o2;

    let index1: number = 0;
    let index2: number = 0;
    while (true) {
      const data1: string | null = NaturalComparator.nextSlice(s1, index1);
      const data2: string | null = NaturalComparator.nextSlice(s2, index2);

      if (data1 === null && data2 === null) {
        return 0;
      }
      if (data1 === null) {
        return -1;
      }
      if (data2 === null) {
        return 1;
      }

      index1 += data1.length;
      index2 += data2.length;

      let result: number;
      if (NaturalComparator.isDigit(data1) && NaturalComparator.isDigit(data2)) {
        result = NaturalComparator.compareNumberString(data1, data2);
      } else {
        result = NaturalComparator.compareIgnoreCase(data1, data2);
      }

      if (result !== 0) {
        return result;
      }
    }
  }

  private static isDigit(str: string): boolean {
    // Just check the first char
    const ch: string = str.charAt(0);
    return ch >= '0' && ch <= '9';
  }

  private static nextSlice(str: string, index: number): string | null {
    const length: number = str.length;
    if (index === length) {
      return null;
    }
    const ch: string = str.charAt(index);
    if (ch === '.' || ch === ' ') {
      return str.substring(index, index + 1);
    }
    if (ch >= '0' && ch <= '9') {
      return str.substring(index, NaturalComparator.nextNumberBound(str, index + 1));
    }
    return str.substring(index, NaturalComparator.nextOtherBound(str, index + 1));
  }

  private static nextNumberBound(str: string, index: number): number {
    let i: number = index;
    const length: number = str.length;
    while (i < length) {
      const ch: string = str.charAt(i);
      if (!(ch >= '0' && ch <= '9')) {
        break;
      }
      i++;
    }
    return i;
  }

  private static nextOtherBound(str: string, index: number): number {
    let i: number = index;
    const length: number = str.length;
    while (i < length) {
      const ch: string = str.charAt(i);
      if (ch === '.' || ch === ' ' || (ch >= '0' && ch <= '9')) {
        break;
      }
      i++;
    }
    return i;
  }

  private static removeLeadingZero(s: string): string {
    if (s.length === 0) {
      return s;
    }
    // At least keep the last number
    let i: number = 0;
    const n: number = s.length - 1;
    while (i < n) {
      if (s.charAt(i) !== '0') {
        return s.substring(i);
      }
      i++;
    }
    return s.substring(s.length - 1);
  }

  private static compareNumberString(s1: string, s2: string): number {
    const p1: string = NaturalComparator.removeLeadingZero(s1);
    const p2: string = NaturalComparator.removeLeadingZero(s2);

    const l1: number = p1.length;
    const l2: number = p2.length;

    if (l1 > l2) {
      return 1;
    } else if (l1 < l2) {
      return -1;
    } else {
      for (let i = 0; i < l1; i++) {
        const c1: string = p1.charAt(i);
        const c2: string = p2.charAt(i);
        if (c1 > c2) {
          return 1;
        } else if (c1 < c2) {
          return -1;
        }
      }
    }

    // 等值时短的原串排前（上游 -s1.length.compareTo(s2.length)）
    // 上游：-s1.length.compareTo(s2.length) → s2 更长时返回 +1（短的原串排前）
    if (s2.length > s1.length) {
      return 1;
    }
    if (s2.length < s1.length) {
      return -1;
    }
    return 0;
  }

  /** Kotlin String.compareTo(other, ignoreCase = true) 的等价 */
  private static compareIgnoreCase(a: string, b: string): number {
    const n: number = Math.min(a.length, b.length);
    for (let i = 0; i < n; i++) {
      const ca: string = a.charAt(i).toLowerCase();
      const cb: string = b.charAt(i).toLowerCase();
      if (ca < cb) {
        return -1;
      }
      if (ca > cb) {
        return 1;
      }
    }
    return a.length - b.length;
  }
}

/** 直接传给 Array.sort 的函数形态 */
export function naturalCompare(a: string | null | undefined, b: string | null | undefined): number {
  return new NaturalComparator().compare(a, b);
}