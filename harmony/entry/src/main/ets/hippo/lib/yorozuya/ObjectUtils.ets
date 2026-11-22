/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0417   上游: com/hippo/lib/yorozuya/ObjectUtils.java（203 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/ObjectUtils.ets
 *
 * 上游实际调用面（git grep 全量 18 处）：**只有 ObjectUtils.equal**，
 *   如 EhDB:1024、dao/Filter:79、DownloadManager:939、SecurityScene:212、
 *   network/CookieSet:91-93、network/CookieRepository:134。
 *   `dump(...)` 全套 0 调用点。
 *
 * 平台差异：
 *  1. equal(a, b) 的 Java 语义是 Objects.equals → a.equals(b)：
 *     - String / 装箱 Integer 等：值相等
 *     - 普通对象：默认 Object.equals 即**引用相等**
 *     ArkTS 的 `===` 对 string/number/boolean 是值相等、对类实例是引用相等 —— 完全对应，
 *     故用泛型 + `===` 实现，不做 `toString()` 拼接比较（那样会把不同对象判成相等）。
 *  2. toString(o)：null → "null"，否则 String(o)。泛型签名以兼容 string/number 实参
 *     （ArkTS 里 string 不是 Object 的子类型）。
 *  3. **dump(...) 整族未移植**（TODO）：它依赖 java.lang.reflect（getClass().isArray()、
 *     getDeclaredFields()、Modifier.isStatic、Field.get/setAccessible）与 java.io.PrintWriter，
 *     ArkTS 无反射、无 PrintWriter，且没有"按声明字段展开任意对象"的等价能力。
 *     上游 0 调用点，故不伪造实现；若将来需要对象转储，应由各数据类显式提供 dumps()。
 */

export class ObjectUtils {

  /**
   * Returns true if two possibly-null objects are equal.
   */
  static equal<T>(a: T | null | undefined, b: T | null | undefined): boolean {
    // Java Objects.equals(null, null) === true
    if (a === null || a === undefined) {
      return b === null || b === undefined;
    }
    if (b === null || b === undefined) {
      return false;
    }
    return a === b;
  }

  /**
   * Returns "null" for null or o.toString().
   */
  static toString<T>(o: T | null | undefined): string {
    return (o === null || o === undefined) ? 'null' : `${o}`;
  }
}
