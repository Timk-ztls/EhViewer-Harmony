/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0016   上游: com/hippo/conaco/Unikery.java（64 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/Unikery.ets
 *
 * 平台差异：
 *  1. **Java 接口里的常量字段 `int INVALID_ID = -1` 在 ArkTS 无对应物**
 *     （interface 不能有静态字段，且 ArkTS 禁止 declaration merging 把 const 挂到接口上）。
 *     故改为同文件导出的模块级常量 `UNIKERY_INVALID_ID`。
 *     调用点改写：`Unikery.INVALID_ID` → `UNIKERY_INVALID_ID`（值仍是 -1，语义不变）。
 *  2. `@Conaco.Source int source` 是 Android 的 @IntDef 编译期注解，ArkTS 无注解处理器
 *     → 形参类型降为 `number`，取值由 Conaco 的 SOURCE_MEMORY=0 / SOURCE_DISK=1 /
 *     SOURCE_NETWORK=2 约定（这三个常量在 Conaco.ets 里定义，见 S0011）。
 *  3. `@NonNull V value` → 泛型 `V`（ArkTS 无 @NonNull，靠调用方保证；上游语义是
 *     "onGetValue 收到非空 value"）。
 *  4. `long` → `number`（进度回调，单位字节）。
 *  5. 注意 onGetValue 的返回值语义**必须保留**：true = 接受该值且任务结束；
 *     false = 拒绝该值，任务继续或失败。Conaco.startConacoTask 的分支依赖它。
 */

/** 对应上游 Unikery.INVALID_ID（见文件头差异 1） */
export const UNIKERY_INVALID_ID: number = -1;

export interface Unikery<V> {

  /**
   * Store the conaco task id
   */
  setTaskId(id: number): void;

  /**
   * Get the conaco task id
   */
  getTaskId(): number;

  /**
   * On miss in the source
   *
   * @param source Conaco.SOURCE_MEMORY(0) / SOURCE_DISK(1) / SOURCE_NETWORK(2)
   */
  onMiss(source: number): void;

  /**
   * On start http request
   */
  onRequest(): void;

  /**
   * On http request progress
   */
  onProgress(singleReceivedSize: number, receivedSize: number, totalSize: number): void;

  /**
   * On start to wait because repeated key
   */
  onWait(): void;

  /**
   * On get the value
   *
   * @return true for the Unikery accepts the value and the task ends.
   *         false for the Unikery reject the value and the task goes on or failed
   */
  onGetValue(value: V, source: number): boolean;

  /**
   * On failed to get value
   */
  onFailure(): void;

  /**
   * On user cancel the conaco task
   */
  onCancel(): void;
}
