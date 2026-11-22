/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0171   上游: com/hippo/ehviewer/preference/RestoreDownloadPreference.kt（267 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/preference/RestoreDownloadPreference.ets
 *
 * 【D-033 拆分】上游是「Preference（UI）+ RestoreTask（AsyncTask）」一体的类。
 * 本文件只保留 **扫描 + 应用** 两段纯逻辑；UI（进度对话框 / Toast / ProgressDialog）由 ui-widget 承担。
 *
 * 上游 `doInBackground` 的算法（逐行照搬）：
 *   1. `dir = Settings.getDownloadLocation()`；null → 失败（返回 null）
 *   2. `dir.listFiles()`；null → 失败
 *   3. `publishProgress(0, total)` → 逐个 `getRestoreItem(file)` → `publishProgress(i+1, total)`
 *   4. 列表为空 → 返回 EMPTY_LIST（→ 提示"未找到可恢复项"）
 *   5. 非空 → `publishProgress(-1, -1)`（切不确定进度）→ `EhEngine.fillGalleryListByApi(...)`
 * 上游 `getRestoreItem(file)`：
 *   dir 不合法（null / 非目录）→ null；找不到 `SPIDER_INFO_FILENAME` → null；
 *   `SpiderInfo.readHeader` 失败 → null；**该 gid 已在下载列表 → null**；
 *   否则返回 `{ gid, token, dirname = file.getName() }`
 * 上游 `onPostExecute`：对每个 `title != null` 的项 → `mManager.addDownload(item, null)` +
 *   `EhDB.putDownloadDirname(gid, dirname)`，计数；**title 为 null 的跳过**（填充详情失败的项）
 *
 * 平台改写（**依赖注入，避免跨模块循环依赖**，与 CleanRedundancy / importDB 同一模式）：
 *   · `Settings.getDownloadLocation()` → 可通过 `dirOverride` 注入（测试用）
 *   · `UniFile.isDirectory()/findFile()/listFiles()/getName()` → 沿用 storage-db 的 UniFile 契约
 *   · `SpiderInfo.readHeader(siFile)` → 注入 `readHeader(file) => {gid, token} | null`
 *     （**注意**：上游 `SPIDER_INFO_FILENAME` 在 `SpiderQueen` 里，值必须由调用方给或从 SpiderQueen 取）
 *   · `mManager.containDownloadInfo(gid)` → 注入 `containsDownload(gid): boolean`
 *   · `EhEngine.fillGalleryListByApi(...)` → 注入 `fillGalleryList(items): Promise<GalleryInfo[] | null>`
 *   · `mManager.addDownload(item, null)` → 注入 `addDownload(item): void`
 *   · `EhDB.putDownloadDirname` → 注入 `putDirname(gid, dirname): Promise<void>`
 *   · `ProgressDialog` / `Toast` / `Handler(Looper)` → 全部属 UI，不移植；进度用回调
 */

import { UniFile } from '../../unifile/UniFile';

/** 上游 `RestoreItem : GalleryInfo { var dirname: String? }` —— 只保留恢复流程用到的字段 */
export class RestoreItem {
  gid: number;
  token: string | null;
  dirname: string | null;

  constructor(gid: number, token: string | null, dirname: string | null) {
    this.gid = gid;
    this.token = token;
    this.dirname = dirname;
  }
}

/** `SpiderInfo.readHeader` 的最小返回（上游用 gid/token 两个字段） */
export class SpiderHeader {
  gid: number;
  token: string | null;

  constructor(gid: number, token: string | null) {
    this.gid = gid;
    this.token = token;
  }
}

/** 扫描结果：区分"目录不可用"与"扫到了但为空"——上游分别对应 null 与 EMPTY_LIST 两种提示 */
export class RestoreScanResult {
  items: RestoreItem[] = [];
  /** 目录取不到（downloadLocation 为 null 或 listFiles 为 null）→ 上游返回 null */
  noDirectory: boolean = false;
}

export class RestoreDownloadPreference {

  /**
   * 对应上游 `doInBackground` 的**扫描阶段**（不含 fillGalleryListByApi）。
   *
   * @param containsDownload `mManager.containDownloadInfo(gid)`
   * @param readHeader `SpiderInfo.readHeader(File)`
   * @param spiderInfoFilename `SpiderQueen.SPIDER_INFO_FILENAME`（调用方给，避免硬编常量漂移）
   * @param onProgress 进度回调 `(progress, max)`；切不确定进度时上游传 (-1, -1)，此处原样透传
   * @param isCancelled 取消检查（上游每轮检查 `mCancelled.get()`）
   * @param dirOverride 仅测试注入
   */
  static async scanRestoreItems(containsDownload: (gid: number) => boolean,
    readHeader: (file: UniFile) => SpiderHeader | null,
    spiderInfoFilename: string,
    onProgress?: (progress: number, max: number) => void,
    isCancelled?: () => boolean,
    dirOverride?: UniFile | null,
    getDownloadLocation?: () => UniFile | null): Promise<RestoreScanResult> {
    const result: RestoreScanResult = new RestoreScanResult();

    const dir: UniFile | null = (dirOverride !== undefined)
      ? dirOverride
      : ((getDownloadLocation !== undefined) ? getDownloadLocation() : null);
    if (dir === null) {
      result.noDirectory = true;
      return result;
    }

    const files: UniFile[] | null = await dir.listFiles();
    if (files === null) {
      result.noDirectory = true;
      return result;
    }

    const total: number = files.length;
    if (onProgress !== undefined) {
      onProgress(0, total);
    }

    for (let i = 0; i < total; i++) {
      if (isCancelled !== undefined && isCancelled()) {
        return result; // 上游：取消即返回 null（不产出结果）
      }
      const item: RestoreItem | null =
        await RestoreDownloadPreference.getRestoreItem(files[i], containsDownload, readHeader,
          spiderInfoFilename);
      if (item !== null) {
        result.items.push(item);
      }
      if (onProgress !== undefined) {
        onProgress(i + 1, total);
      }
    }
    return result;
  }

  /** 对应上游 `getRestoreItem(file)` */
  static async getRestoreItem(file: UniFile | null,
    containsDownload: (gid: number) => boolean,
    readHeader: (file: UniFile) => SpiderHeader | null,
    spiderInfoFilename: string): Promise<RestoreItem | null> {
    if (file === null || !file.isDirectory()) {
      return null;
    }
    const siFile: UniFile | null = await file.findFile(spiderInfoFilename);
    if (siFile === null) {
      return null;
    }
    // 上游：只需 gid/token，避免损坏的 pToken 行导致整体失败
    const header: SpiderHeader | null = readHeader(siFile);
    if (header === null) {
      return null;
    }
    const gid: number = header.gid;
    if (containsDownload(gid)) {
      return null; // 已在下载列表 → 不需要恢复
    }
    const name: string | undefined = file.getName();
    return new RestoreItem(gid, header.token, (name === undefined) ? null : name);
  }

  /**
   * 对应上游 `onPostExecute` 的应用阶段：
   * 对每个 `title != null` 的项 → addDownload + putDownloadDirname，返回成功计数。
   *
   * @param titleOf 取 galleryInfo.title（null 表示填充详情失败 → 上游跳过）
   */
  static async applyRestore(items: RestoreItem[],
    titleOf: (item: RestoreItem) => string | null,
    addDownload: (item: RestoreItem) => void,
    putDirname: (gid: number, dirname: string) => Promise<void>): Promise<number> {
    let count: number = 0;
    for (let i = 0; i < items.length; i++) {
      const item: RestoreItem = items[i];
      // Avoid failed gallery info
      if (titleOf(item) === null) {
        continue;
      }
      addDownload(item);
      const dirname: string | null = item.dirname;
      if (dirname !== null) {
        await putDirname(item.gid, dirname);
      }
      count++;
    }
    return count;
  }
}
