/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0164   上游: com/hippo/ehviewer/preference/CleanRedundancyPreference.java（107 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/preference/CleanRedundancyPreference.ets
 *
 * 【D-033 拆分】上游 `extends TaskPreference`（带 UI + AsyncTask）。本文件只保留**清理算法**，
 * UI（对话框 + 进度 + Toast）由 ui-widget 的 ArkUI 组件表达。
 *
 * 上游算法（ClearTask.doInBackground 逐行照搬）：
 *   1. `dir = Settings.getDownloadLocation()`；为 null → 计数 0
 *   2. `dir.listFiles()`；为 null → 计数 0
 *   3. 对每个文件：取 `getName()`；截到第一个 '-' 之前；`parseLongSafely(name, -1)`；
 *      -1 → 跳过；**该 gid 仍在下载管理器中 → 跳过**；否则 `delete()` 并 +1
 *   4. 每处理一个文件 publishProgress(i+1, total)
 *
 * 平台差异（依赖注入，避免跨模块循环依赖）：
 *   `mManager.containDownloadInfo(gid)`（download-sync 的 DownloadManager）→ 传入
 *   `contains: (gid: number) => boolean` 回调。**语义等价**，且使本算法可在 Node 侧断言。
 *   `UniFile` 沿用 storage-db 的契约（getName/delete/listFiles）。
 */

import { UniFile } from '../../unifile/UniFile';
import { NumberUtils } from '../../lib/yorozuya/NumberUtils';
import { Settings } from '../Settings';

/** 单文件判定结果 */
export class CleanResult {
  /** 已删除的文件数（对应上游 ClearTask 的返回值） */
  count: number = 0;
  /** 扫描的文件总数 */
  total: number = 0;
  /** 目录取不到（downloadLocation 为 null 或 listFiles 为 null） */
  noDirectory: boolean = false;
}

export class CleanRedundancyPreference {

  /**
   * 对应上游 ClearTask.doInBackground。
   * @param contains 该 gid 是否仍在下载列表中（上游 DownloadManager.containDownloadInfo）
   * @param onProgress 每处理一个文件回调 (已处理, 总数)，对应 publishProgress
   */
  static async cleanRedundancy(contains: (gid: number) => boolean,
    onProgress?: (done: number, total: number) => void,
    dirOverride?: UniFile | null): Promise<CleanResult> {
    const result: CleanResult = new CleanResult();

    // dirOverride 仅用于测试注入；生产路径走 Settings.getDownloadLocation()
    const dir: UniFile | null = (dirOverride !== undefined) ? dirOverride : Settings.getDownloadLocation();
    if (dir === null) {
      result.noDirectory = true;
      if (onProgress !== undefined) {
        onProgress(0, 0);
      }
      return result;
    }

    const files: UniFile[] | null = await dir.listFiles();
    if (files === null) {
      result.noDirectory = true;
      if (onProgress !== undefined) {
        onProgress(0, 0);
      }
      return result;
    }

    const total: number = files.length;
    result.total = total;
    let count: number = 0;
    for (let i = 0; i < total; i++) {
      if (CleanRedundancyPreference.clearFile(files[i], contains)) {
        count++;
      }
      if (onProgress !== undefined) {
        onProgress(i + 1, total);
      }
    }
    result.count = count;
    return result;
  }

  /** 对应上游 ClearTask.clearFile(UniFile)：true 表示已删除 */
  static clearFile(file: UniFile, contains: (gid: number) => boolean): boolean {
    const rawName: string | undefined = file.getName();
    if (rawName === undefined) {
      return false;
    }
    let name: string = rawName;
    if (name === null) {
      return false;
    }
    const index: number = name.indexOf('-');
    if (index >= 0) {
      name = name.substring(0, index);
    }
    const gid: number = NumberUtils.parseLongSafely(name, -1);
    if (gid === -1) {
      return false;
    }
    if (contains(gid)) {
      return false;
    }
    file.delete();
    return true;
  }
}