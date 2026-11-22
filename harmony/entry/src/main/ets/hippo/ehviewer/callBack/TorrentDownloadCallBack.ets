/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0041   上游: com/hippo/ehviewer/callBack/TorrentDownloadCallBack.java（22 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/callBack/TorrentDownloadCallBack.ets
 *
 * 平台差异：
 *  1. Java interface → ArkTS interface。
 *  2. 三个回调的参数**逐字保留**（path/name、url/name、url/name/progress）；
 *     上游无 `@NonNull`，但语义上 url 在失败/下载中必非空 —— 见 C-7 第 4 条：
 *     这里**不加 `| null`**，因为上游注释写明 url 是种子地址（不是可选项）。
 *  3. `int progress` 保留 number（进度百分比）。
 */

export interface TorrentDownloadCallBack {

  /** 种子下载成功 */
  torrentDownLoadSuccess(path: string, name: string): void;

  /** 种子下载失败 */
  torrentDownLoadFailed(url: string, name: string): void;

  /** 种子下载中 */
  torrentDownLoading(url: string, name: string, progress: number): void;
}