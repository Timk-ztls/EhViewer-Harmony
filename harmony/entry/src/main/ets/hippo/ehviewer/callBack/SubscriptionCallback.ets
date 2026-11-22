/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0040   上游: com/hippo/ehviewer/callBack/SubscriptionCallback.java（6 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/callBack/SubscriptionCallback.ets
 *
 * 平台差异：
 *  1. `UserTagList` 是 net-parse 的 `client/data/UserTagList`（尚未交付）→ 参数先用 `Object` 占位，
 *     待其落地后改成具体类型（**调用点无需改**，因为实现方签名由本接口约束）。
 *     这是"契约先行"，与 `ConacoTaskLike` 同处理方式。
 *  2. `getAddTagName` 返回 `String` → `string | null`（上游可能 return null 表示"不添加"）。
 */

export interface SubscriptionCallback {

  onSubscriptionItemClick(name: string): void;

  /** @param userTagList 上游 `UserTagList`（net-parse 未交付，暂用 Object 占位） */
  getAddTagName(userTagList: Object): string | null;
}