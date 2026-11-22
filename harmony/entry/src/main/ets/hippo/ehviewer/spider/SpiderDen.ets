/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/spider/SpiderDen.java（445 行）
 *
 * 作用：「一张图存在哪里」的统一入口。两种存储：阅读缓存（SimpleDiskCache，按 key=EhCacheKeyFactory.getImageKey）
 * 与下载目录（UniFile 下 `%08d.jpg` 这类文件）。SpiderQueen 通过它读写每一页图片。
 *
 * ── 本文件的落地范围（lead 指定「先写不依赖下载根目录的部分」）───────────────
 * 已实现（不依赖被阻塞模块）：
 *   - StartWithFilenameFilter / generateImageFilename / findImageFile / fixExtension
 *   - 缓存侧全部：containInCache / removeFromCache / openCacheInputStreamPipe / openCacheOutputStreamPipe
 *     （SimpleDiskCache 与 EhCacheKeyFactory 都已在 main）
 *   - 下载目录侧：containInDownloadDir / removeFromDownloadDir / copyFromCacheToDownloadDir /
 *     openDownloadInputStreamPipe / openDownloadOutputStreamPipe / contain / remove
 *   - 生命周期：initialize / setGid / setMode / isDownloadMode / isReady / prepareDownloadStorage
 * 通过**注入点**解耦（依赖未落地的模块，未注入时抛带归属的 TODO 错误，绝不静默降级）：
 *   - `SyncDownloadSettingProvider` ← core-runtime `Settings.getSyncDownloadWhileReading()`（唯一未落的一项；`getDownloadLocation` 已直接调用真实Settings）
 *   - `DirnameStore`            ← core-runtime `EhDB` 门面（getDownloadDirname / putDownloadDirname）
 *   - `GalleryTitleProvider`    ← net-parse `EhUtils.getSuitableTitle`
 *
 * ── 与上游的三处必要差异 ──────────────────────────────────────────────────
 * 1) `Looper.getMainLooper()` 判定：ArkTS 无线程上下文查询 API。上游用它「在主线程不做 SAF 目录列举」
 *    （列表列举慢，会卡 UI）。鸿蒙侧对应物是「不要在主线程 await 目录列举」，本文件把
 *    findDownloadDirname 做成 async 并在文档里写明调用约束；不给假的 isMainThread() 返回 false。
 * 2) `BitmapFactory.Options.inJustDecodeBounds` 嗅探 MIME：鸿蒙 API 20 的 `image.ImageInfo` 无 mimeType
 *    字段 → 改为读文件头魔数自行判定（JPEG/PNG/GIF/WEBP），与上游 outMimeType + MimeTypeMap 等价，
 *    且可单测（见 test/storage-db）。
 * 3) 静态常量归属：上游 `MODE_READ/MODE_DOWNLOAD` 在 SpiderQueen、`SUPPORT_IMAGE_EXTENSIONS` 在
 *    GalleryProvider2。这两个文件分别因 core-runtime / gl-render 阻塞尚未落地，
 *    故本文件**单点定义**并导出；它们落地时**必须从这里 re-export**，禁止再写字面量
 *    （与 `SPIDER_INFO_FILENAME` 同一约定）。
 */

import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UniFile } from '../../unifile/UniFile';
import { FilenameFilter } from '../../unifile/FilenameFilter';
import { Contracts, InputStream, OutputStream } from '../../unifile/Contracts';
import { Utils } from '../../unifile/Utils';
import { UniFileInputStreamPipe } from '../../io/UniFileInputStreamPipe';
import { UniFileOutputStreamPipe } from '../../io/UniFileOutputStreamPipe';
import { InputStreamPipe } from '../../streampipe/InputStreamPipe';
import { OutputStreamPipe, ByteSink } from '../../streampipe/OutputStreamPipe';
import { SimpleDiskCache } from '../../beerbelly/SimpleDiskCache';
import { EhCacheKeyFactory } from '../client/EhCacheKeyFactory';
import { GalleryInfo } from '../client/data/GalleryInfo';
import { IOUtils } from '../../lib/yorozuya/IOUtils';
import { MathUtils } from '../../lib/yorozuya/MathUtils';
import { FileUtils } from '../../lib/yorozuya/FileUtils';
import { GalleryProvider2 } from '../gallery/GalleryProvider2';
import { Settings } from '../Settings';

const TAG: string = 'SpiderDen';

/** 对位 `SpiderQueen.MODE_READ`（S0180 落地后从本文件 re-export）。 */
export const MODE_READ: number = 0;
/** 对位 `SpiderQueen.MODE_DOWNLOAD`（S0180 落地后从本文件 re-export）。 */
export const MODE_DOWNLOAD: number = 1;

/**
 * 对位 `GalleryProvider2.SUPPORT_IMAGE_EXTENSIONS`。
 * 上游的 home 是 GalleryProvider2（S0159）；该文件已落地，故这里直接**引用**而不是再写一份字面量。
 * 保留本文件的导出名，是因为 SpiderDen 的调用点（含下游）一直按这个名字用。
 */
export const SUPPORT_IMAGE_EXTENSIONS: string[] = GalleryProvider2.SUPPORT_IMAGE_EXTENSIONS;

/**
 * 只覆盖**尚未落地的那个**设置项。
 *
 * `Settings.getDownloadLocation()` 与 `Settings.getReadCacheSize()` 已在 main 上（core-runtime 已交付），
 * 本文件**直接调用**，符合上游（上游 SpiderDen 就是直接 `Settings.getDownloadLocation()`）。
 *
 * 唯一还没落的是 `Settings.getSyncDownloadWhileReading()`：
 *   上游 key = `"sync_download_while_reading"`，默认 false（Settings.java:KEY_SYNC_DOWNLOAD_WHILE_READING）。
 * core-runtime 补上后应删掉本接口、直接调 Settings。
 */
export interface SyncDownloadSettingProvider {
  /** 对位 `Settings.getSyncDownloadWhileReading(): boolean`。 */
  getSyncDownloadWhileReading(): boolean;
}

/** 对位 core-runtime 的 `EhDB` 门面里与本文件相关的两个方法（EhDB.java:484/497）。 */
export interface DirnameStore {
  getDownloadDirname(gid: number): Promise<string | null>;

  putDownloadDirname(gid: number, dirname: string): Promise<void>;
}

/** 对位 net-parse 的 `EhUtils.getSuitableTitle(GalleryInfo): String`。 */
export interface GalleryTitleProvider {
  getSuitableTitle(info: GalleryInfo): string;
}

/** 对位 `SpiderDen.StartWithFilenameFilter`：按前缀过滤目录项。 */
export class StartWithFilenameFilter implements FilenameFilter {
  private readonly mPrefix: string;

  constructor(prefix: string) {
    this.mPrefix = prefix;
  }

  accept(dir: UniFile, filename: string): boolean {
    return filename.startsWith(this.mPrefix);
  }
}

export class SpiderDen {
  private readonly mGalleryInfo: GalleryInfo;
  private mGid: number;
  private mMode: number = MODE_READ;
  private mDownloadDir: UniFile | null = null;

  private static sCache: SimpleDiskCache | null = null;
  private static syncSettings: SyncDownloadSettingProvider | null = null;
  private static dirnameStore: DirnameStore | null = null;
  private static titleProvider: GalleryTitleProvider | null = null;
  private static readonly sDirnameCache: Map<number, string> = new Map<number, string>();

  // ---------------------------------------------------------------- 注入点

  /** 仅用于 `getSyncDownloadWhileReading`（Settings 里这个方法尚未落地，见 SyncDownloadSettingProvider）。 */
  static setSyncDownloadSettingProvider(provider: SyncDownloadSettingProvider | null): void {
    SpiderDen.syncSettings = provider;
  }

  /** core-runtime 的 EhDB 门面落地后注入。 */
  static setDirnameStore(store: DirnameStore | null): void {
    SpiderDen.dirnameStore = store;
  }

  /** net-parse 的 EhUtils 落地后注入。 */
  static setTitleProvider(provider: GalleryTitleProvider | null): void {
    SpiderDen.titleProvider = provider;
  }



  private static requireDirnameStore(): DirnameStore {
    const d: DirnameStore | null = SpiderDen.dirnameStore;
    if (d === null) {
      throw new Error(`[${TAG}] TODO(core-runtime): DirnameStore 未注入（需要 EhDB.getDownloadDirname / putDownloadDirname）`);
    }
    return d;
  }

  private static requireTitleProvider(): GalleryTitleProvider {
    const t: GalleryTitleProvider | null = SpiderDen.titleProvider;
    if (t === null) {
      throw new Error(`[${TAG}] TODO(net-parse): GalleryTitleProvider 未注入（需要 EhUtils.getSuitableTitle）`);
    }
    return t;
  }

  /**
   * 对位 `initialize(Context)`：建阅读缓存。
   *
   * 上游：`new SimpleDiskCache(new File(context.getCacheDir(), "image"),
   *        MathUtils.clamp(Settings.getReadCacheSize(), 40, 640) * 1024 * 1024)`
   * 鸿蒙：缓存目录由调用方给（应用沙箱 `context.cacheDir + '/image'`），
   *       cacheSizeMb 直接传 `Settings.getReadCacheSize()` 的原值（单位 MB），
   *       clamp(40,640) 与 ×1024×1024 的换算在这里做，与上游一致。
   */
  static initialize(cacheDir: string, cacheSizeMb: number): void {
    const sizeBytes: number = MathUtils.clamp(cacheSizeMb, 40, 640) * 1024 * 1024;
    SpiderDen.sCache = new SimpleDiskCache(cacheDir, sizeBytes);
  }

  /** 仅测试/重启用：清掉缓存实例。 */
  static resetCache(): void {
    SpiderDen.sCache = null;
    SpiderDen.sDirnameCache.clear();
  }

  // ---------------------------------------------------------------- 下载目录解析（静态）

  /**
   * 对位 `findDownloadDirname(GalleryInfo, UniFile parentDir)`。
   *
   * 三步（与上游一致）：
   *   1. 先查 DB（EhDB.getDownloadDirname）；命中则 `FileUtils.sanitizeFilename` 规整后**回写**（上游同）
   *   2. 未命中则列举父目录里以 `"<gid>-"` 开头的项，取**名字最长**的那个目录（上游注释：Get max-length-name dir）
   *   3. 仍未命中返回 null（由调用方决定是否创建）
   *
   * 调用约束（替代上游的 Looper 判定）：第 2 步是目录列举，**不要在 UI 线程同步等待**；
   * 在 `aboutToAppear` 里调用需配 loading 态，或放到 TaskPool。
   */
  private static async findDownloadDirname(info: GalleryInfo, parentDir: UniFile): Promise<string | null> {
    const store: DirnameStore = SpiderDen.requireDirnameStore();
    let dirname: string | null = await store.getDownloadDirname(info.gid);
    if (dirname !== null) {
      // 某些版本的目录名可能不合法 → 规整后回写（上游同）
      dirname = FileUtils.sanitizeFilename(dirname);
      SpiderDen.sDirnameCache.set(info.gid, dirname);
      await store.putDownloadDirname(info.gid, dirname);
      return dirname;
    }

    try {
      const files: UniFile[] | null = parentDir.listFilesFiltered(new StartWithFilenameFilter(`${info.gid}-`));
      if (files !== null) {
        let maxLength: number = -1;
        let found: string | null = null;
        for (const file of files) {
          if (file.isDirectory()) {
            const name: string | undefined = file.getName();
            if (name !== undefined && name.length > maxLength) {
              maxLength = name.length;
              found = name;
            }
          }
        }
        if (found !== null) {
          SpiderDen.sDirnameCache.set(info.gid, found);
          await store.putDownloadDirname(info.gid, found);
          dirname = found;
        }
      }
    } catch (e) {
      Utils.throwIfFatal(e);
      // 存储不可用/权限丢失时与上游一致：吞掉，返回 null
      Utils.logW(TAG, `Failed to list files in download directory: ${e}`);
    }
    return dirname;
  }

  /** 对位 `getExistingGalleryDownloadDir`：只取已存在/已知的目录，**绝不创建**（UI 删除下载时安全）。 */
  static async getExistingGalleryDownloadDir(info: GalleryInfo): Promise<UniFile | null> {
    const dir: UniFile | null = Settings.getDownloadLocation();
    if (dir === null) {
      return null;
    }
    const dirname: string | null = await SpiderDen.findDownloadDirname(info, dir);
    return dirname !== null ? dir.subFile(dirname) : null;
  }

  /** 对位 `getGalleryDownloadDir`：取目录，缺失时用「gid-标题」建名并写库。 */
  static async getGalleryDownloadDir(info: GalleryInfo): Promise<UniFile | null> {
    const dir: UniFile | null = Settings.getDownloadLocation();
    if (dir === null) {
      return null;
    }
    let dirname: string | null = await SpiderDen.findDownloadDirname(info, dir);
    if (dirname === null) {
      const title: string = SpiderDen.requireTitleProvider().getSuitableTitle(info);
      dirname = FileUtils.sanitizeFilename(`${info.gid}-${title}`);
      SpiderDen.sDirnameCache.set(info.gid, dirname);
      await SpiderDen.requireDirnameStore().putDownloadDirname(info.gid, dirname);
    }
    return dir.subFile(dirname);
  }

  // ---------------------------------------------------------------- 实例

  constructor(galleryInfo: GalleryInfo) {
    this.mGalleryInfo = galleryInfo;
    this.mGid = galleryInfo.gid;
  }

  setMGid(gid: number): void {
    this.mGid = gid;
  }

  setMode(mode: number): void {
    this.mMode = mode;
  }

  isDownloadMode(): boolean {
    return this.mMode === MODE_DOWNLOAD;
  }

  /** 对位 `shouldSyncDownloadWhileReading()`：阅读模式 + 设置里开启「边读边存」。 */
  private shouldSyncDownloadWhileReading(): boolean {
    if (this.mMode !== MODE_READ) {
      return false;
    }
    const s: SyncDownloadSettingProvider | null = SpiderDen.syncSettings;
    if (s === null) {
      // 不能默认 false —— 那会把"边读边存"静默关掉（行为降级），故抛错让调用方显式注入
      throw new Error(`[${TAG}] TODO(core-runtime): Settings.getSyncDownloadWhileReading() 未落地，` +
        '请通过 SpiderDen.setSyncDownloadSettingProvider 注入（上游 key="sync_download_while_reading"，默认 false）');
    }
    return s.getSyncDownloadWhileReading();
  }

  shouldWriteToDownloadDir(): boolean {
    return this.isDownloadMode() || this.shouldSyncDownloadWhileReading();
  }

  /** 对位 `prepareDownloadStorage()`：仅下载模式需要，worker 线程调用。 */
  async prepareDownloadStorage(): Promise<boolean> {
    if (this.mMode !== MODE_DOWNLOAD) {
      return true;
    }
    return this.ensureDownloadDirExists();
  }

  /** 确保下载目录存在（供 MODE_DOWNLOAD 与边读边存路径共用）。 */
  async ensureDownloadDirExists(): Promise<boolean> {
    if (this.mDownloadDir === null) {
      this.mDownloadDir = await SpiderDen.getGalleryDownloadDir(this.mGalleryInfo);
    }
    const dir: UniFile | null = this.mDownloadDir;
    return dir !== null && dir.ensureDir();
  }

  /**
   * 同步懒解析下载目录：先看 mDownloadDir，其次查内存 dirname 缓存或扫描下载根目录中
   * 以 `<gid>-` 开头的最长现有目录；仅 `createIfMissing === true` 且标题提供者就绪时才新建。
   */
  private resolveDownloadDirSync(createIfMissing: boolean): UniFile | null {
    const current: UniFile | null = this.mDownloadDir;
    if (current !== null) {
      if (createIfMissing) {
        current.ensureDir();
      }
      return current.isDirectory() ? current : null;
    }
    const rootDir: UniFile | null = Settings.getDownloadLocation();
    if (rootDir === null) {
      return null;
    }
    const cached: string | undefined = SpiderDen.sDirnameCache.get(this.mGalleryInfo.gid);
    let dirname: string | null = cached !== undefined ? cached : null;
    if (dirname === null) {
      try {
        const files: UniFile[] | null = rootDir.listFilesFiltered(
          new StartWithFilenameFilter(`${this.mGalleryInfo.gid}-`));
        if (files !== null) {
          let maxLength: number = -1;
          for (const file of files) {
            if (file.isDirectory()) {
              const name: string | undefined = file.getName();
              if (name !== undefined && name.length > maxLength) {
                maxLength = name.length;
                dirname = name;
              }
            }
          }
        }
      } catch (e) {
        Utils.throwIfFatal(e);
      }
    }
    if (dirname === null && createIfMissing && SpiderDen.titleProvider !== null) {
      const title: string = SpiderDen.titleProvider.getSuitableTitle(this.mGalleryInfo);
      dirname = FileUtils.sanitizeFilename(`${this.mGalleryInfo.gid}-${title}`);
      if (SpiderDen.dirnameStore !== null) {
        SpiderDen.dirnameStore.putDownloadDirname(this.mGalleryInfo.gid, dirname).catch((e: Object) => {
          Utils.throwIfFatal(e);
          const msg: string = e instanceof Error ? e.message : String(e);
          hilog.warn(0x0000, TAG, 'putDownloadDirname(%{public}d) failed: %{public}s', this.mGalleryInfo.gid, msg);
        });
      }
    }
    if (dirname === null) {
      return null;
    }
    const candidate: UniFile | null = rootDir.subFile(dirname);
    if (candidate === null) {
      return null;
    }
    if (createIfMissing && !candidate.ensureDir()) {
      return null;
    }
    if (candidate.isDirectory()) {
      this.mDownloadDir = candidate;
      SpiderDen.sDirnameCache.set(this.mGalleryInfo.gid, dirname);
      return candidate;
    }
    return null;
  }

  private ensureDownloadDirExistsSync(): boolean {
    if (this.resolveDownloadDirSync(false) !== null) {
      return true;
    }
    return this.resolveDownloadDirSync(true) !== null;
  }

  /** 对位 `isReady()`：阅读模式看缓存是否就绪；下载模式看目录是否为目录。 */
  isReady(): boolean {
    if (this.mMode === MODE_READ) {
      return SpiderDen.sCache !== null;
    }
    if (this.mMode === MODE_DOWNLOAD) {
      return this.getDownloadDir() !== null;
    }
    return false;
  }

  /** 对位 `getDownloadDir()`：懒解析并返回已存在的下载目录（不是目录则 null）。 */
  getDownloadDir(): UniFile | null {
    return this.resolveDownloadDirSync(false);
  }

  /** 对位 `getDownloadDirName()`。 */
  getDownloadDirName(): UniFile | null {
    if (this.mDownloadDir === null) {
      this.resolveDownloadDirSync(false);
    }
    return this.mDownloadDir;
  }

  // ---------------------------------------------------------------- 文件名（静态工具）

  /**
   * 对位 `generateImageFilename(index, extension)`：`%08d` + 扩展名（extension 带点）。
   * 上游用 `String.format(Locale.US, "%08d%s", index + 1, extension)` —— 注意是 **index+1**（从 1 开始）。
   */
  static generateImageFilename(index: number, extension: string): string {
    let num: string = `${index + 1}`;
    while (num.length < 8) {
      num = `0${num}`;
    }
    return `${num}${extension}`;
  }

  /** 对位 `findImageFile(dir, index)`：按支持的扩展名顺序找第一个存在的文件。 */
  /**
   * 某个 index 的**全部**候选文件名（每个支持的扩展名一个）。
   *
   * 抽出来的理由（断言需要）：`remove(index)` 必须删掉**所有扩展名**的文件 ——
   * 只删一个的话用户看到"删了但磁盘没空"（`.webp` 与 `.jpg` 并存时）。
   * `findImageFile` 只返回**第一个**存在的，所以它无法用来验证"全删"。
   */
  static imageFilenamesFor(index: number): string[] {
    const names: string[] = [];
    for (const extension of SUPPORT_IMAGE_EXTENSIONS) {
      names.push(SpiderDen.generateImageFilename(index, extension));
    }
    return names;
  }

  static findImageFile(dir: UniFile, index: number): UniFile | null {
    for (const extension of SUPPORT_IMAGE_EXTENSIONS) {
      const filename: string = SpiderDen.generateImageFilename(index, extension);
      const file: UniFile | null = dir.findFile(filename);
      if (file !== null) {
        return file;
      }
    }
    return null;
  }

  /** 对位 `fixExtension(extension)`：不在支持列表里就退回第一个（.jpg）。 */
  private static fixExtension(extension: string): string {
    if (SUPPORT_IMAGE_EXTENSIONS.indexOf(extension) >= 0) {
      return extension;
    }
    return SUPPORT_IMAGE_EXTENSIONS[0];
  }

  /**
   * 由文件头魔数判定扩展名（带点），等价上游
   * `BitmapFactory.Options.inJustDecodeBounds` → `outMimeType` → `MimeTypeMap.getExtensionFromMimeType`。
   *
   * 鸿蒙 API 20 的 `image.ImageInfo` 没有 mimeType 字段（只有 size/density），
   * 所以这里直接看魔数：JPEG(FF D8 FF) / PNG(89 50 4E 47) / GIF("GIF8") / WEBP("RIFF"..."WEBP")。
   * 返回 null 表示不认识（调用方与上游一样放弃这次拷贝）。
   */
  static sniffImageExtension(head: ArrayBuffer): string | null {
    const b: Uint8Array = new Uint8Array(head);
    if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
      return '.jpg';
    }
    if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
      return '.png';
    }
    if (b.length >= 4 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) {
      return '.gif';
    }
    if (b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) {
      return '.webp';
    }
    return null;
  }

  // ---------------------------------------------------------------- 缓存侧

  private containInCache(index: number): boolean {
    const cache: SimpleDiskCache | null = SpiderDen.sCache;
    if (cache === null) {
      return false;
    }
    const key: string = EhCacheKeyFactory.getImageKey(this.mGid, index);
    return cache.contain(key);
  }

  private removeFromCache(index: number): boolean {
    const cache: SimpleDiskCache | null = SpiderDen.sCache;
    if (cache === null) {
      return false;
    }
    return cache.remove(EhCacheKeyFactory.getImageKey(this.mGid, index));
  }

  private openCacheInputStreamPipe(index: number): InputStreamPipe | null {
    const cache: SimpleDiskCache | null = SpiderDen.sCache;
    if (cache === null) {
      return null;
    }
    return cache.getInputStreamPipe(EhCacheKeyFactory.getImageKey(this.mGid, index));
  }

  private openCacheOutputStreamPipe(index: number): OutputStreamPipe | null {
    const cache: SimpleDiskCache | null = SpiderDen.sCache;
    if (cache === null) {
      return null;
    }
    return cache.getOutputStreamPipe(EhCacheKeyFactory.getImageKey(this.mGid, index));
  }

  // ---------------------------------------------------------------- 下载目录侧

  private containInDownloadDir(index: number): boolean {
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return false;
    }
    return SpiderDen.findImageFile(dir, index) !== null;
  }

  private removeFromDownloadDir(index: number): boolean {
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return false;
    }
    let result: boolean = false;
    for (const filename of SpiderDen.imageFilenamesFor(index)) {
      const file: UniFile | null = dir.subFile(filename);
      if (file !== null) {
        result = file.delete() || result;
      }
    }
    return result;
  }

  /**
   * 对位 `copyFromCacheToDownloadDir(index)`：缓存里有图、下载目录没有 → 拷过去。
   * 扩展名靠嗅探文件头决定（见 sniffImageExtension 的说明）。
   */
  private copyFromCacheToDownloadDir(index: number): boolean {
    const cache: SimpleDiskCache | null = SpiderDen.sCache;
    if (cache === null) {
      return false;
    }
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return false;
    }
    const pipe: InputStreamPipe | null = cache.getInputStreamPipe(EhCacheKeyFactory.getImageKey(this.mGid, index));
    if (pipe === null) {
      return false;
    }

    // 注意：写端类型必须是 unifile 的 OutputStream（名义类型），不能用 streampipe 的 ByteSink ——
    // 两者形状相似但无名义关系，ArkTS 会报 arkts-no-structural-typing（这个坑踩过一次）。
    let os: OutputStream | null = null;
    try {
      // 1) 读头部判扩展名
      pipe.obtain();
      const handle: fs.File = pipe.open();
      const head: ArrayBuffer = new ArrayBuffer(16);
      let read: number = 0;
      try {
        read = fs.readSync(handle.fd, head, { offset: 0, length: 16 });
      } catch (e) {
        Utils.throwIfFatal(e);
      }
      pipe.close();

      let extension: string | null = SpiderDen.sniffImageExtension(
        read >= 12 ? head.slice(0, read) : head.slice(0, read > 0 ? read : 0));
      if (extension === null) {
        return false;
      }
      extension = SpiderDen.fixExtension(extension);

      // 2) 建目标文件并整段拷贝
      const file: UniFile | null = dir.createFile(SpiderDen.generateImageFilename(index, extension));
      if (file === null) {
        return false;
      }
      const outOs: OutputStream = file.openOutputStream();
      os = outOs;
      // 逐块拷贝（IOUtils.copy 的写端契约是 write(buffer, off, len) 三参形态，与 unifile 的
      // OutputStream 名义不同；这里直接手写循环，避免再加一层适配器）
      const inHandle: fs.File = pipe.open();
      const buf: ArrayBuffer = new ArrayBuffer(IOUtils.DEFAULT_BUFFER_SIZE);
      while (true) {
        const n: number = fs.readSync(inHandle.fd, buf, { length: IOUtils.DEFAULT_BUFFER_SIZE });
        if (n <= 0) {
          break;
        }
        outOs.writeBytes(buf, 0, n);
      }
      outOs.flush();
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    } finally {
      Utils.closeQuietly(os);
      pipe.close();
      pipe.release();
    }
  }

  /** 对位 `contain(index)`：阅读模式先查缓存，下载模式先查目录（并尝试从缓存拷入）。 */
  contain(index: number): boolean {
    if (this.mMode === MODE_READ) {
      return this.containInCache(index) || this.containInDownloadDir(index);
    }
    if (this.mMode === MODE_DOWNLOAD) {
      return this.containInDownloadDir(index) || this.copyFromCacheToDownloadDir(index);
    }
    return false;
  }

  /** 对位 `remove(index)`：缓存与下载目录都删。 */
  remove(index: number): boolean {
    let result: boolean = this.removeFromCache(index);
    result = this.removeFromDownloadDir(index) || result;
    return result;
  }

  /** 对位 `openDownloadOutputStreamPipe(index, extension)`：extension 可带点也可不带。 */
  openDownloadOutputStreamPipe(index: number, extension: string | null): OutputStreamPipe | null {
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return null;
    }
    let ext: string;
    if (extension === null || !extension.includes('.')) {
      ext = SpiderDen.fixExtension(`.${extension !== null ? extension : ''}`);
    } else {
      ext = SpiderDen.fixExtension(extension);
    }
    const file: UniFile | null = dir.createFile(SpiderDen.generateImageFilename(index, ext));
    if (file === null) {
      return null;
    }
    return new UniFileOutputStreamPipe(file);
  }

  /** 对位 `openOutputStreamPipe(index, extension)`：按模式选缓存/下载目录；边读边存时自动创建目录。 */
  openOutputStreamPipe(index: number, extension: string | null): OutputStreamPipe | null {
    if (this.mMode === MODE_READ) {
      if (this.shouldSyncDownloadWhileReading()) {
        this.ensureDownloadDirExistsSync();
        const pipe: OutputStreamPipe | null = this.openDownloadOutputStreamPipe(index, extension);
        if (pipe !== null) {
          return pipe;
        }
      }
      return this.openCacheOutputStreamPipe(index);
    }
    if (this.mMode === MODE_DOWNLOAD) {
      return this.openDownloadOutputStreamPipe(index, extension);
    }
    return null;
  }

  /** 异步版写端获取：支持等待 async DirnameStore 建目录（MODE_DOWNLOAD 或边读边存）。 */
  async openOutputStreamPipeAsync(index: number, extension: string | null): Promise<OutputStreamPipe | null> {
    if (this.mMode === MODE_READ) {
      if (this.shouldSyncDownloadWhileReading()) {
        if (SpiderDen.dirnameStore !== null && SpiderDen.titleProvider !== null) {
          try {
            await this.ensureDownloadDirExists();
          } catch (e) {
            Utils.throwIfFatal(e);
          }
        }
        this.ensureDownloadDirExistsSync();
        const pipe: OutputStreamPipe | null = this.openDownloadOutputStreamPipe(index, extension);
        if (pipe !== null) {
          return pipe;
        }
      }
      return this.openCacheOutputStreamPipe(index);
    }
    if (this.mMode === MODE_DOWNLOAD) {
      if (this.mDownloadDir === null && SpiderDen.dirnameStore !== null && SpiderDen.titleProvider !== null) {
        try {
          await this.ensureDownloadDirExists();
        } catch (e) {
          Utils.throwIfFatal(e);
        }
      }
      return this.openDownloadOutputStreamPipe(index, extension);
    }
    return null;
  }

  /** 下载无 URL 扩展名时，通过文件头魔数修正下载目录中的文件扩展名。 */
  fixDownloadedExtension(index: number): void {
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return;
    }
    const file: UniFile | null = SpiderDen.findImageFile(dir, index);
    if (file === null) {
      return;
    }
    let stream: InputStream | null = null;
    let n: number = 0;
    const head: ArrayBuffer = new ArrayBuffer(16);
    try {
      stream = file.openInputStream();
      n = stream.readBuffer(head);
    } catch (e) {
      Utils.throwIfFatal(e);
      return;
    } finally {
      Utils.closeQuietly(stream);
    }
    const sniffed: string | null = n > 0 ? SpiderDen.sniffImageExtension(head.slice(0, n)) : null;
    if (sniffed === null) {
      return;
    }
    const targetName: string = SpiderDen.generateImageFilename(index, sniffed);
    const currentName: string | undefined = file.getName();
    if (currentName !== undefined && currentName === targetName) {
      return;
    }
    const conflict: UniFile | null = dir.findFile(targetName);
    if (conflict !== null) {
      conflict.delete();
    }
    file.renameTo(targetName);
  }

  /**
   * 对位 `openDownloadInputStreamPipe(index)`：
   * 最多试 2 次 —— 先找文件，找不到就尝试从缓存拷进来（拷完再找）。
   */
  openDownloadInputStreamPipe(index: number): InputStreamPipe | null {
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return null;
    }
    for (let i = 0; i < 2; i++) {
      const file: UniFile | null = SpiderDen.findImageFile(dir, index);
      if (file !== null) {
        return new UniFileInputStreamPipe(file);
      }
      if (!this.copyFromCacheToDownloadDir(index)) {
        return null;
      }
    }
    return null;
  }

  /** 对位 `openDownloadInputStreamPipeReadOnly(index)`：只读，不触发缓存→下载目录的拷贝。 */
  private openDownloadInputStreamPipeReadOnly(index: number): InputStreamPipe | null {
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return null;
    }
    const file: UniFile | null = SpiderDen.findImageFile(dir, index);
    return file !== null ? new UniFileInputStreamPipe(file) : null;
  }

  /** 对位 `openInputStreamPipe(index)`：阅读模式优先缓存、绝不因读而写下载目录。 */
  openInputStreamPipe(index: number): InputStreamPipe | null {
    if (this.mMode === MODE_READ) {
      if (this.shouldSyncDownloadWhileReading()) {
        const downloadPipe: InputStreamPipe | null = this.openDownloadInputStreamPipe(index);
        if (downloadPipe !== null) {
          return downloadPipe;
        }
        return this.openCacheInputStreamPipe(index);
      }
      const pipe: InputStreamPipe | null = this.openCacheInputStreamPipe(index);
      if (pipe !== null) {
        return pipe;
      }
      // 阅读模式不得触发 cache→download 的拷贝
      return this.openDownloadInputStreamPipeReadOnly(index);
    }
    if (this.mMode === MODE_DOWNLOAD) {
      return this.openDownloadInputStreamPipe(index);
    }
    return null;
  }

  /** 返回页图本地可用 URI（供原生 ArkUI Image 直接解码渲染，不经过 JS 字节搬运）。 */
  getImageFileUri(index: number): string | null {
    if (this.mMode === MODE_READ) {
      if (this.shouldSyncDownloadWhileReading()) {
        const dlUri: string | null = this.getDownloadFileUri(index, true);
        if (dlUri !== null) {
          return dlUri;
        }
        return this.getCacheFileUri(index);
      }
      const cacheUri: string | null = this.getCacheFileUri(index);
      if (cacheUri !== null) {
        return cacheUri;
      }
      return this.getDownloadFileUri(index, false);
    }
    if (this.mMode === MODE_DOWNLOAD) {
      const dlUri: string | null = this.getDownloadFileUri(index, true);
      if (dlUri !== null) {
        return dlUri;
      }
      return this.getCacheFileUri(index);
    }
    return null;
  }

  private getCacheFileUri(index: number): string | null {
    const cache: SimpleDiskCache | null = SpiderDen.sCache;
    if (cache === null) {
      return null;
    }
    const path: string | null = cache.getCacheFilePath(EhCacheKeyFactory.getImageKey(this.mGid, index));
    if (path === null || path.length === 0) {
      return null;
    }
    return Contracts.toUri(path);
  }

  private getDownloadFileUri(index: number, allowCopyFromCache: boolean): string | null {
    const dir: UniFile | null = this.getDownloadDir();
    if (dir === null) {
      return null;
    }
    let file: UniFile | null = SpiderDen.findImageFile(dir, index);
    if (file === null && allowCopyFromCache) {
      if (this.copyFromCacheToDownloadDir(index)) {
        file = SpiderDen.findImageFile(dir, index);
      }
    }
    return file !== null ? file.getUri() : null;
  }
}
