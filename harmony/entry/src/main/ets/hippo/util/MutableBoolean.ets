/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0494   上游: com/hippo/util/MutableBoolean.kt（17 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/MutableBoolean.ets
 *
 * 平台差异：无。上游是 `class MutableBoolean(@JvmField var value: Boolean)` ——
 * 一个可变布尔持有者（Kotlin 里用于让 lambda 内可写外层的 val）。
 * ArkTS 的闭包可以捕获并修改 `let` 变量，理论上不需要这个类；但**上游调用点用它做
 * "跨回调共享标志"**，保留同名类能保持调用点 1:1，且语义清晰。
 */

export class MutableBoolean {

  value: boolean;

  constructor(value: boolean) {
    this.value = value;
  }
}