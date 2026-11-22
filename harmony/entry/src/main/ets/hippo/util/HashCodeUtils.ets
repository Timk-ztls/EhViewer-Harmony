/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0490   上游: com/hippo/util/HashCodeUtils.kt（37 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/HashCodeUtils.ets
 *
 * `hash = 31 * hash + (o?.hashCode() ?: 0)`，null 元素按 0 计；`args == null` 返回 0
 * （Kotlin 的可变参数在 Java 层可能是 null，ArkTS 的可变参数永远是数组 → 空数组等价于上游 null，
 *   两者都返回 0，语义一致）。
 *
 * 平台差异：
 *   ArkTS 无 `Object.hashCode()`（与 AbstractMultimap 差异 7 同源）→ 用已交付的
 *   `AbstractMultimap.hashString()` 做字符串化后的哈希；number 直接取整数部分参与运算。
 *   这与上游对 String/Number 元素的结果一致；**对自定义对象不一致**（上游用 identity/重写的
 *   hashCode，我们按 `toString`）。上游调用点只传 String/Number/Tag 的 name，故无实际差异 —— 已注明。
 */

export class HashCodeUtils {

  private static readonly X: number = 31;

  /** 对应上游 `hashCode(vararg args: Any?)` */
  static hashCode(...args: (Object | null)[]): number {
    if (args === null || args.length === 0) {
      return 0;
    }
    let hash: number = 0;
    for (let i = 0; i < args.length; i++) {
      const o: Object | null = args[i];
      const h: number = (o === null) ? 0 : HashCodeUtils.hashOf(o);
      // Java int 溢出回绕 → 必须 |0
      hash = (HashCodeUtils.X * hash + h) | 0;
    }
    return hash;
  }

  /** 对应 `Object.hashCode()` 的近似：String → Java String.hashCode，number → 取整 */
  private static hashOf(o: Object): number {
    if (typeof o === 'number') {
      const n: number = o as number;
      // Java Integer.hashCode = 值本身；Double/Long 会不同，上游不传浮点故取整即可
      return (Number.isFinite(n) ? Math.trunc(n) : 0) | 0;
    }
    if (typeof o === 'boolean') {
      // Java Boolean.hashCode = 1231/1237
      return (o as boolean) ? 1231 : 1237;
    }
    return HashCodeUtils.javaStringHash(`${o}`);
  }

  /** Java `String.hashCode()`：`h = 31*h + char`，32 位回绕 */
  private static javaStringHash(s: string): number {
    let h: number = 0;
    for (let i = 0; i < s.length; i++) {
      h = (31 * h + s.charCodeAt(i)) | 0;
    }
    return h;
  }
}