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
  title: string | null = null;

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
   * @param readHeader `SpiderInfo.readHeader(File)`（可内部回退 CBOR）
   * @param spiderInfoFilename `SpiderQueen.SPIDER_INFO_FILENAME`（调用方给，避免硬编常量漂移）
   * @param onProgress 进度回调 `(progress, max)`；切不确定进度时上游传 (-1, -1)，此处原样透传
   * @param isCancelled 取消检查（上游每轮检查 `mCancelled.get()`）
   * @param dirOverride 仅测试注入
   * @param getDownloadLocation 下载目录获取器
   * @param readComicInfo 可选 `ComicInfo.xml` 回退读取器（仅在 `.ehviewer` 缺失或解析失败时调用）
   */
  static async scanRestoreItems(containsDownload: (gid: number) => boolean,
    readHeader: (file: UniFile) => SpiderHeader | null,
    spiderInfoFilename: string,
    onProgress?: (progress: number, max: number) => void,
    isCancelled?: () => boolean,
    dirOverride?: UniFile | null,
    getDownloadLocation?: () => UniFile | null,
    readComicInfo?: (dir: UniFile) => SpiderHeader | null): Promise<RestoreScanResult> {
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
          spiderInfoFilename, readComicInfo);
      if (item !== null) {
        result.items.push(item);
      }
      if (onProgress !== undefined) {
        onProgress(i + 1, total);
      }
    }
    return result;
  }

  /**
   * 对应上游 `getRestoreItem(file)`：
   * 先读 `.ehviewer`（调用方可组合文本 + CBOR），失败或缺失时再读 `ComicInfo.xml`。
   */
  static async getRestoreItem(file: UniFile | null,
    containsDownload: (gid: number) => boolean,
    readHeader: (file: UniFile) => SpiderHeader | null,
    spiderInfoFilename: string,
    readComicInfo?: (dir: UniFile) => SpiderHeader | null): Promise<RestoreItem | null> {
    if (file === null || !file.isDirectory()) {
      return null;
    }
    let gid: number = -1;
    let token: string | null = null;
    const siFile: UniFile | null = await file.findFile(spiderInfoFilename);
    if (siFile !== null) {
      const header: SpiderHeader | null = readHeader(siFile);
      if (header !== null && header.gid >= 0 && header.token !== null && header.token.length > 0) {
        gid = header.gid;
        token = header.token;
      }
    }
    if ((gid < 0 || token === null || token.length === 0) && readComicInfo !== undefined) {
      const comicHeader: SpiderHeader | null = readComicInfo(file);
      if (comicHeader !== null && comicHeader.gid >= 0 &&
        comicHeader.token !== null && comicHeader.token.length > 0) {
        gid = comicHeader.gid;
        token = comicHeader.token;
      }
    }
    if (gid < 0 || token === null || token.length === 0) {
      return null;
    }
    if (containsDownload(gid)) {
      return null; // 已在下载列表 → 不需要恢复
    }
    const name: string | undefined = file.getName();
    return new RestoreItem(gid, token, (name === undefined) ? null : name);
  }

  /**
   * 对应上游标题兜底：`apiTitle` 非空时优先用它，否则回退 `item.dirname`，再回退 `String(item.gid)`。
   */
  static resolveRestoreTitle(item: RestoreItem, apiTitle: string | null | undefined): string {
    if (apiTitle !== null && apiTitle !== undefined && apiTitle.length > 0) {
      return apiTitle;
    }
    if (item.dirname !== null && item.dirname.length > 0) {
      return item.dirname;
    }
    return `${item.gid}`;
  }

  /**
   * 对应上游 `onPostExecute` 的应用阶段：
   * 即使线上 gdata 未取到标题，也按 `dirname -> gid` 兜底恢复并计数。
   *
   * @param titleOf 取 galleryInfo.title（null 或空串时自动使用兜底标题）
   */
  static async applyRestore(items: RestoreItem[],
    titleOf: (item: RestoreItem) => string | null,
    addDownload: (item: RestoreItem) => void,
    putDirname: (gid: number, dirname: string) => Promise<void>): Promise<number> {
    let count: number = 0;
    for (let i = 0; i < items.length; i++) {
      const item: RestoreItem = items[i];
      item.title = RestoreDownloadPreference.resolveRestoreTitle(item, titleOf(item));
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
