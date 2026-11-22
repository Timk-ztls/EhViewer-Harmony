/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0036   上游: com/hippo/ehviewer/callBack/DownloadSearchCallback.java（8 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/callBack/DownloadSearchCallback.ets
 *
 * 平台差异：
 *  1. `java.util.List<DownloadInfo>` → `DownloadInfo[]`（方案 §5-9）
 *  2. Java interface → ArkTS interface（实现方显式 `implements`，ArkTS 不做结构化推断）
 *  3. 三个回调的语义照搬：搜索成功 / 列表处理成功 / 搜索失败（失败也带 list，上游如此）
 */

import { DownloadInfo } from '../dao/DownloadInfo';

export interface DownloadSearchCallback {

  /** 上游 `void onDownloadSearchSuccess(List<DownloadInfo> list)`：**无 @NonNull，可能为 null**（C-7 第 4 条） */
  onDownloadSearchSuccess(mList: DownloadInfo[] | null): void;

  onDownloadListHandleSuccess(mList: DownloadInfo[] | null): void;

  onDownloadSearchFailed(mList: DownloadInfo[] | null): void;
}