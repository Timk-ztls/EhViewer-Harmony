/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0038   上游: com/hippo/ehviewer/callBack/PermissionCallBack.java（4 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/callBack/PermissionCallBack.ets
 *
 * 平台差异：Java interface → ArkTS interface（实现方显式 implements）。
 * `int permissionCode` 保留为 number —— 语义是"哪个权限请求的回执"，
 * 鸿蒙侧对应 `abilityAccessCtrl` 的 requestPermissionsFromUser 的请求序号（由调用方分配）。
 */

export interface PermissionCallBack {

  agree(permissionCode: number): void;
}