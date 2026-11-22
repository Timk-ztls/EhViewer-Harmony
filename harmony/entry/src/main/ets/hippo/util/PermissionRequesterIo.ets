/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0498（同上，配套契约文件）
 * 目标   : harmony/entry/src/main/ets/hippo/util/PermissionRequesterIo.ets
 *
 * `PermissionRequester` 需要平台提供的三个能力，抽成接口注入（ArkTS 无 `ActivityCompat`）：
 *   · `isGranted(permission)`            ← `abilityAccessCtrl.checkAccessTokenSync`
 *   · `shouldShowRationale(permission)`  ← 鸿蒙无同名 API，由调用方按"上次拒绝且未选不再询问"推导
 *   · `requestPermissions(perms, code)`  ← `abilityAccessCtrl.requestPermissionsFromUser`
 *
 * 单独成文件而不是写在 `PermissionRequester.ets` 里：ArkTS 的 interface 与 class 同文件时
 * 导出没有问题，但把**注入契约**独立出来能让 ui-scene 只依赖这个文件（少 import 一个 class）。
 */

export interface PermissionRequesterIo {
  /** 是否已获得该权限 */
  isGranted(permission: string): boolean;

  /** 是否需要先向用户解释（对应 `ActivityCompat.shouldShowRequestPermissionRationale`） */
  shouldShowRationale(permission: string): boolean;

  /** 发起权限申请；结果通过系统回调返回（对应 `ActivityCompat.requestPermissions`） */
  requestPermissions(permissions: string[], requestCode: number): void;
}
