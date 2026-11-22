/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/download/ArchiverDownloadCompleter.kt（415 行含注释 / 388 逻辑行）。
 *
 * 职责：归档 zip 下载完之后的**解压 + 导入**：解压到临时目录 → 找出图片 → 按序号改名
 * 拷进 SpiderDen 的下载目录 → 建"归档"标签并登记一条 STATE_FINISH 记录 → 清持久化状态。
 *
 * ============================================================================
 * 解压策略（D-η，与上游不同的唯一一处）
 * ============================================================================
 * 上游自己写 `ZipInputStream` 逐条目解压，边解压边按 `%08d + 扩展名` 命名，
 * 于是"编号顺序 = zip 条目顺序"，同时跳过目录/非图片/含 `..` 的条目。
 *
 * 鸿蒙无 `java.util.zip`。可用的系统能力是 `@ohos.zlib.decompressFile(inFile, outFile, options)`
 * （整体解压到目录，底层是 zlib/7z 兼容实现）。因此改成两段式：
 *   ① `zlib.decompressFile` 整体解压到 `AppConfig.getExternalTempDir()/archiver_<gid>`；
 *   ② 递归收集图片文件、**按文件名升序**编号、逐张拷进下载目录。
 *
 * 行为差异（已登记在 MR）：zip 条目顺序信息在 ① 之后不可得，编号顺序退化为"文件名升序"。
 *   - 对 EhViewer 归档（页面文件名本身有序：`0001.jpg` / `001-02.png` …）结果与上游一致；
 *   - 对"条目乱序但内容有序"的第三方 zip，页序可能与上游不同。
 * 安全语义加强而非削弱：整体解压由系统负责落到指定目录，且 ② 只从解压后的目录里取文件
 * （不拿条目名拼路径），因此"含 `..` 的条目"不可能逃逸到下载目录之外。
 *
 * 其余等价点：
 *   1. `tryBeginHandling/endHandling`（同一 taskId 不可并发处理）保留。
 *   2. `handleFailedTask` 的五步清理顺序保留（先删 gid→taskId 映射，再删 4 个 taskId 键）。
 *   3. `createFileName(title, gid)`：`sanitizeFilename` + UTF-8 截断到 255 - len(".zip")，
 *      空则 `archiver_<gid>`；`truncateUtf8ToMaxBytes` 的代理对处理逐行保留。
 *   4. `resolveImportRoot`：本层有图片就用本层，只有唯一子目录才下钻，否则用本层。
 *   5. `getImageExtension`：不支持的扩展名回退到 `SUPPORT_IMAGE_EXTENSIONS[0]`。
 *   6. 拷完后 `copiedCount == 0` → 失败；成功 → 加"归档"标签 + `addDownload(..., STATE_FINISH)`。
 *   7. `SpiderDen.setMode(MODE_DOWNLOAD)` + `prepareDownloadStorage()` 的调用顺序保留。
 */

import { BusinessError } from '@kit.BasicServicesKit';
import i18n from '@ohos.i18n';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { zlib } from '@kit.BasicServicesKit';

import { AppConfig } from '../AppConfig';
import { DownloadManager } from './DownloadManager';
import { Settings } from '../Settings';
import { CompareUtil } from '../../util/CompareUtil';
import { DownloadInfo } from '../dao/DownloadInfo';
import { GalleryInfo } from '../client/data/GalleryInfo';
import { MODE_DOWNLOAD, SpiderDen, SUPPORT_IMAGE_EXTENSIONS } from '../spider/SpiderDen';
import { UniFile } from '../../unifile/UniFile';
import { InputStream, OutputStream } from '../../unifile/Contracts';
import { StringUtils } from '../../lib/yorozuya/StringUtils';
import { A7ZipArchive, A7ZipArchiveEntry } from '../gallery/A7ZipArchive';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'ArchiverDownloadCompleter';

/** 解压缓冲（上游 `EXTRACT_BUFFER_SIZE = 8192`；系统解压内部使用，此值仅用于拷贝阶段说明）。 */
const EXTRACT_BUFFER_SIZE: number = 8192;

/** 归档标签名（上游 `R.string.download_label_archiver`）。 */
/**
 * 归档标签名的**纯函数映射**（c6 / L-16）：对位上游 `R.string.download_label_archiver` 的四份资源。
 *
 * 上游（`app/src/main/res/`）：
 * ```
 *   values/         → Archiver        （默认，未列出的语言）
 *   values-zh-rCN/  → 档案
 *   values-zh-rHK/  → 歸檔器
 *   values-zh-rTW/  → 歸檔器
 * ```
 * 为什么必须按 locale 取而不是硬编码：`DownloadManager.addLabel(label)` 按**标签名**建标签，
 * 而标签名是 DB 里的字符串主键 —— 硬编码 `'归档'` 会让**从原 Android EhViewer 导入 .db 的用户
 * 出现两个标签**（旧标签 `档案`/`歸檔器` 里的归档看起来丢了一半）。
 *
 * 参数是**语言标签**而不是直接读系统语言，是为了可断言（纯函数）。
 */
export function archiverLabelFor(langTag: string): string {
  const tag: string = langTag.toLowerCase();
  // 繁体优先判：zh-hant / zh-hk / zh-tw / zh-mo
  // 只用 startsWith：=== 'zh-hk' 被 startsWith('zh-hk') 完全覆盖，留着会让读者误以为语义不同
  if (tag.startsWith('zh-hant') || tag.startsWith('zh-hk')
    || tag.startsWith('zh-tw') || tag.startsWith('zh-mo')) {
    return '歸檔器';
  }
  // 简体：zh-hans / zh-cn / zh-sg，以及裸 'zh'（HarmonyOS 常返回 'zh' 表示简体）
  if (tag.startsWith('zh')) {
    return '档案';
  }
  return 'Archiver';
}

/**
 * 生产环境的 locale 取值表达式。
 *
 * **必须是 `getSystemLocale()` 而不是 `getSystemLanguage()`**（R-11）：
 * `getSystemLanguage()` 只给**语言**（`'zh'`），带 script/region 的是 `getSystemLocale()`（`'zh-Hans-CN'`）。
 * 用前者的话 `zh-Hant` / `zh-HK` / `zh-TW` 分支在生产路径上**永远不可达** ——
 * 港台用户拿到的也是裸 `'zh'` → 命中简体分支 → 旧 `.db` 的 `歸檔器` 标签与新建的 `档案` 并存（L-16 换形态保留）。
 *
 * 抽成常量是为了可注入：单测能替换成 `() => 'zh-Hant-TW'` 等，从而断言"调用点喂进来的形状"。
 */
export const SYSTEM_LOCALE_PROVIDER: () => string = (): string => i18n.System.getSystemLocale();

/** 当前系统 locale 下的归档标签名（读不到时按英文默认，与上游 `values/` 一致）。 */
export function archiverLabel(provider: () => string = SYSTEM_LOCALE_PROVIDER): string {
  try {
    return archiverLabelFor(provider());
  } catch (e) {
    return 'Archiver';
  }
}

/** 一条"从归档抽取并落盘"的任务（纯数据）。 */
export interface ImportTarget {
  /** 归档内条目下标（`getArchiveEntries()`/`entryName(i)` 的下标，非排序后的位次）。 */
  entryIndex: number;
  /** 归档内路径（用于取扩展名与日志）。 */
  entryPath: string;
  /** 落盘文件名（`SpiderDen.generateImageFilename(k, ext)`，按下标编号）。 */
  fileName: string;
}

export class ArchiverDownloadCompleter {
  private static sInstance: ArchiverDownloadCompleter | null = null;

  /** 正在处理的 taskId 集合（上游 `handlingIds = HashSet<Long>()`）。 */
  private readonly handlingIds: Set<number> = new Set<number>();

  private constructor() {
  }

  public static getInstance(): ArchiverDownloadCompleter {
    if (ArchiverDownloadCompleter.sInstance === null) {
      ArchiverDownloadCompleter.sInstance = new ArchiverDownloadCompleter();
    }
    return ArchiverDownloadCompleter.sInstance;
  }

  /**
   * 对应上游 `importDownloadedZip(zipFile, galleryInfo, taskId)`：
   * 校验文件 → 抢占 taskId → 解压 → 导入。
   */
  public async importDownloadedZip(zipPath: string | null, galleryInfo: GalleryInfo, taskId: number): Promise<void> {
    if (zipPath === null || !this.isFile(zipPath)) {
      await this.handleFailedTask(galleryInfo, taskId);
      return;
    }
    if (!this.tryBeginHandling(taskId)) {
      return;
    }
    const tempDir: string | null = AppConfig.getExternalTempDir();
    if (tempDir === null) {
      this.endHandling(taskId);
      await this.handleFailedTask(galleryInfo, taskId);
      return;
    }
    const displayName: string = ArchiverDownloadCompleter.createFileName(galleryInfo.title, galleryInfo.gid);
    const targetDir: string = `${tempDir}/archiver_${galleryInfo.gid}`;

    try {
      // D-η：先按条目直读（无需临时目录）；不可用时回退到 zlib 整档解压
      const handled: boolean = await this.importFromArchive(zipPath, galleryInfo, taskId, displayName);
      if (handled) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'fallback to zlib whole-archive import: %{public}s', zipPath);
      const ok: boolean = await ArchiverDownloadCompleter.unzipArchive(zipPath, targetDir);
      if (!ok) {
        await this.postImportFailed(galleryInfo, taskId);
        return;
      }
      await this.importGallery(targetDir, galleryInfo, taskId, displayName);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Error importing downloaded zip: %{public}s',
        this.errorToString(e as Object));
      this.deleteDir(targetDir);
      await this.postImportFailed(galleryInfo, taskId);
    }
  }

  private tryBeginHandling(taskId: number): boolean {
    if (this.handlingIds.has(taskId)) {
      return false;
    }
    this.handlingIds.add(taskId);
    return true;
  }

  private endHandling(taskId: number): void {
    this.handlingIds.delete(taskId);
  }

  /**
   * 对应上游 `handleFailedTask(galleryInfo, taskId)`。
   */
  /**
   * **async 原因**：清理 5 个 Settings 键的 delete 已改为 `Promise<boolean>`（必须 await，
   * 否则拿到 Promise 对象恒 truthy = "永远删成功"）。
   */
  private async handleFailedTask(galleryInfo: GalleryInfo | null, taskId: number): Promise<void> {
    if (galleryInfo !== null) {
      await Settings.deleteArchiverDownloadId(galleryInfo.gid);
    }
    await Settings.deleteArchiverDownload(taskId);
    await Settings.deleteArchiverDownloadUrl(taskId);
    await Settings.deleteArchiverDownloadPaused(taskId);
    await Settings.deleteArchiverDownloadTotal(taskId);
    try {
      promptAction.showToast({ message: $r('app.string.import_album_failed'), duration: 3000 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showToast failed');
    }
  }

  private async postImportFailed(galleryInfo: GalleryInfo | null, taskId: number): Promise<void> {
    this.endHandling(taskId);
    await this.handleFailedTask(galleryInfo, taskId);
  }

  /**
   * D-η 的真正修复：**不解压整档**，逐条 `openEntry()` 抽取并直接落盘。
   *
   * 与 zlib 整档解压相比：
   *   - 不需要临时目录（大合集的临时空间从"一份完整副本"降到 0）；
   *   - 天然只处理 `create()` 过滤后的可读条目（加密/目录/分卷/固实 + 非图片已被剔掉）；
   *   - 页序直接取归档条目序（打包者的顺序就是他想要的顺序）。
   *
   * 返回 false 表示"归档路径不可用"，调用方应回退到 zlib 整档解压：
   *   - `A7ZipArchive` 的 bridge 未注入（TODO(D-004)）/ `create()` 抛错；
   *   - 条目数为 0（例如空归档）。
   */
  private async importFromArchive(zipPath: string, galleryInfo: GalleryInfo, taskId: number,
    displayName: string): Promise<boolean> {
    const zipFile: UniFile | null = await UniFile.fromFile(zipPath);
    if (zipFile === null) {
      return false;
    }
    let archive: A7ZipArchive | null = null;
    try {
      archive = A7ZipArchive.create(zipFile.createRandomAccessFile('r'));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'A7ZipArchive unavailable, fallback to zlib: %{public}s',
        this.errorToString(e as Object));
      return false;
    }
    if (archive === null) {
      return false;
    }

    try {
      const count: number = archive.entryCount();
      if (count === 0) {
        return false;
      }
      // 与上游同形：`getArchiveEntries()` 返回的已是 create() 过滤后的可读条目
      // （加密/目录/分卷/固实 + 非图片后缀都剔掉了），顺序 = 归档内顺序
      const entries: A7ZipArchiveEntry[] = archive.getArchiveEntries();
      const entryPaths: string[] = [];
      for (let i = 0; i < entries.length; i++) {
        entryPaths.push(entries[i].getPath());
      }
      const targets: ImportTarget[] = ArchiverDownloadCompleter.planImportTargets(entryPaths, true);
      if (targets.length === 0) {
        return false;
      }

      const downloadDir: UniFile | null = await this.prepareDownloadDir(galleryInfo);
      if (downloadDir === null) {
        await this.postImportFailed(galleryInfo, taskId);
        return true;   // 已处理（失败已上报），不再回退
      }

      let copiedCount: number = 0;
      for (let k = 0; k < targets.length; k++) {
        const target: ImportTarget = targets[k];
        if (target.entryIndex < 0) {
          continue;
        }
        const destFile: UniFile | null = await downloadDir.createFile(target.fileName);
        if (destFile === null) {
          hilog.error(DOMAIN, TAG, 'Failed to create file: %{public}s', target.fileName);
          continue;
        }
        let ok: boolean = true;
        const sink: OutputStream = destFile.openOutputStream();
        try {
          // 上游形态：`getArchiveEntries().get(i).extract(os)`
          entries[target.entryIndex].extract(sink);
        } catch (e) {
          ok = false;
          hilog.error(DOMAIN, TAG, 'Failed to extract entry %{public}s: %{public}s',
            target.entryPath, this.errorToString(e as Object));
        } finally {
          try {
            sink.close();
          } catch (e) {
            // 关闭失败不应覆盖抽取结果
          }
        }
        if (!ok) {
          await destFile.delete();
          continue;
        }
        copiedCount++;
      }

      if (copiedCount === 0) {
        await this.postImportFailed(galleryInfo, taskId);
        return true;
      }
      await this.finishImport(galleryInfo, taskId, displayName, copiedCount);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'importFromArchive failed: %{public}s', this.errorToString(e as Object));
      await this.postImportFailed(galleryInfo, taskId);
      return true;
    } finally {
      archive.close();
    }
  }

  /** 准备下载目录（与 importGallery 共用）。 */
  private async prepareDownloadDir(galleryInfo: GalleryInfo): Promise<UniFile | null> {
    const spiderDen: SpiderDen = new SpiderDen(galleryInfo);
    spiderDen.setMode(MODE_DOWNLOAD);
    await spiderDen.prepareDownloadStorage();
    return spiderDen.getDownloadDir();
  }
  /**
   * 对应上游 `importGallery(tempFilePath, galleryInfo, taskId, displayName)`。
   */
  private async importGallery(tempDirPath: string, galleryInfo: GalleryInfo, taskId: number,
    displayName: string): Promise<void> {
    if (tempDirPath.length === 0) {
      await this.postImportFailed(galleryInfo, taskId);
      return;
    }
    const importRoot: string | null = this.resolveImportRoot(tempDirPath);
    if (importRoot === null) {
      await this.postImportFailed(galleryInfo, taskId);
      return;
    }
    // 顺序与过滤统一走 planImportOrder（有单测）。`byEntryOrder = false` = 上游按文件名排序
    // （当前实现：zlib 整档解压后按 baseName 排，与上游 `Collections.sort` 一致）。
    //
    // `byEntryOrder = true` 现在走的是**归档直读**路径（importFromArchive）：条目序取自
    // `A7ZipArchive.getArchiveEntries()`（上游 A7ZipArchive.java:67），逐条 `extract()` 直接落盘，
    // 不整档解压、不需要临时目录。zlib 整档解压只在归档不可用时作为兜底（`byEntryOrder = false`）。
    const pictures: string[] = ArchiverDownloadCompleter.planImportOrder(this.collectImageFiles(importRoot), false);
    if (pictures.length === 0) {
      hilog.error(DOMAIN, TAG, 'No image files found under: %{public}s', tempDirPath);
      await this.postImportFailed(galleryInfo, taskId);
      return;
    }

    const downloadDir: UniFile | null = await this.prepareDownloadDir(galleryInfo);
    if (downloadDir === null) {
      await this.postImportFailed(galleryInfo, taskId);
      return;
    }

    let copiedCount: number = 0;
    try {
      for (let i = 0; i < pictures.length; i++) {
        const picture: string = pictures[i];
        if (!this.isFile(picture)) {
          hilog.warn(DOMAIN, TAG, 'Skip missing file: %{public}s', picture);
          continue;
        }
        const extension: string = ArchiverDownloadCompleter.getImageExtension(
          ArchiverDownloadCompleter.baseName(picture));
        const newName: string = SpiderDen.generateImageFilename(i, extension);

        const destFile: UniFile | null = await downloadDir.createFile(newName);
        if (destFile === null) {
          hilog.error(DOMAIN, TAG, 'Failed to create file: %{public}s', newName);
          continue;
        }
        const sourceFile: UniFile | null = await UniFile.fromFile(picture);
        if (sourceFile === null) {
          hilog.error(DOMAIN, TAG, 'Cannot open source file: %{public}s', picture);
          await destFile.delete();
          continue;
        }
        const copied: boolean = ArchiverDownloadCompleter.copyFile(sourceFile, destFile);
        if (!copied) {
          hilog.error(DOMAIN, TAG, 'Failed to copy file: %{public}s to %{public}s', picture, newName);
          await destFile.delete();
          continue;
        }
        copiedCount++;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Error in importGallery: %{public}s', this.errorToString(e as Object));
      await this.postImportFailed(galleryInfo, taskId);
      return;
    }

    if (copiedCount === 0) {
      hilog.error(DOMAIN, TAG, 'No images were copied from: %{public}s', tempDirPath);
      await this.postImportFailed(galleryInfo, taskId);
      return;
    }

    this.deleteDir(tempDirPath);

    await this.finishImport(galleryInfo, taskId, displayName, copiedCount);
  }

  /**
   * 导入成功的公共尾部：加标签 + 登记 STATE_FINISH + Toast + 清 Settings + 结束处理。
   * （上游在 `mainHandler.post` 里做；zlib 路径与归档直读路径共用。）
   */
  private async finishImport(galleryInfo: GalleryInfo, taskId: number, displayName: string,
    copiedCount: number): Promise<void> {
    hilog.info(DOMAIN, TAG, 'import done: gid=%{public}d, copied=%{public}d', galleryInfo.gid, copiedCount);
    // DownloadManager 单例由本模块持有（对位上游 EhApplication.getDownloadManager）
    const manager: DownloadManager = await DownloadManager.getInstance();
    await manager.addLabel(archiverLabel());
    await manager.addDownload(galleryInfo, archiverLabel(), DownloadInfo.STATE_FINISH);
    try {
      promptAction.showToast({ message: `已成功下载 ${displayName}`, duration: 3000 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showToast failed');
    }
    await Settings.deleteArchiverDownloadId(galleryInfo.gid);
    await Settings.deleteArchiverDownload(taskId);
    await Settings.deleteArchiverDownloadUrl(taskId);
    await Settings.deleteArchiverDownloadPaused(taskId);
    await Settings.deleteArchiverDownloadTotal(taskId);
    this.endHandling(taskId);
  }

  // ---------------------------------------------------------------- 静态工具

  /**
   * 对应上游 `createFileName(name, gid)`。
   */
  /**
   * 决定"导入顺序"的纯函数 —— 归档导入的编号契约就靠它。
   *
   * 两种顺序来源：
   *   - `byEntryOrder = false`（当前 zlib 整档解压）：解压出的本地文件顺序不可靠，
   *     上游 `Collections.sort { a.name.compareTo(b.name) }` 按文件名排序；
   *   - `byEntryOrder = true`（归档直读路径，`getArchiveEntries()` 已交付）：按**归档内条目顺序**，
   *     这才是压缩包原本的页序（文件名排序在 `1.jpg, 10.jpg, 2.jpg` 这种命名下会错）。
   *
   * 过滤规则与上游一致：跳过空项、含 `..` 的路径、非图片扩展名。
   * 编号由调用方用**下标**生成（`for i in indices`），因此跳过的项会**留下空号** —— 上游同样如此。
   */
  public static planImportOrder(entries: string[], byEntryOrder: boolean): string[] {
    const result: string[] = [];
    for (let i = 0; i < entries.length; i++) {
      const entry: string = entries[i];
      if (entry.length === 0 || entry.indexOf('..') >= 0) {
        continue;
      }
      // 用 isImagePath 过滤，**不能**用 getImageExtension：后者对未知扩展名会回退到
      // SUPPORT_IMAGE_EXTENSIONS[0]（上游行为），永远非空，拿它当过滤器等于不过滤。
      if (!ArchiverDownloadCompleter.isImagePath(entry)) {
        continue;
      }
      result.push(entry);
    }
    if (!byEntryOrder) {
      // 上游 `Collections.sort(tempPictures) { f1, f2 -> f1.name.compareTo(f2.name) }`
      // → **Java compareTo 是逐 UTF-16 码元的字典序**，必须用 CompareUtil.compareCodeUnits；
      //   `localeCompare` 走 locale 规则（中文/日文设备上顺序会与上游不同），是错误等价物。
      result.sort((a: string, b: string): number => {
        return CompareUtil.compareCodeUnits(ArchiverDownloadCompleter.baseName(a),
          ArchiverDownloadCompleter.baseName(b));
      });
    }
    return result;
  }
  /**
   * 把**归档条目列表**映射成"逐条抽取任务"（纯函数，可断言）。
   *
   * 拆出这一层的理由：顺序、过滤、编号全是决策；真正的 IO（`openEntry(i, sink)`）只是循环执行。
   * 决策留在纯函数里，才能在宿主上验"003 排第一 / note.txt 被剔掉 / 编号按下标"这些事。
   *
   * `entryPaths` 必须来自 `A7ZipArchive`（`create()` 已过滤加密/目录/分卷/固实 + 非图片后缀），
   * 不要自己从 native 层拿未过滤的列表 —— 那会把 `note.txt` 当图片。
   */
  public static planImportTargets(entryPaths: string[], byEntryOrder: boolean): ImportTarget[] {
    const ordered: string[] = ArchiverDownloadCompleter.planImportOrder(entryPaths, byEntryOrder);
    const targets: ImportTarget[] = [];
    for (let k = 0; k < ordered.length; k++) {
      const entryPath: string = ordered[k];
      const extension: string = ArchiverDownloadCompleter.getImageExtension(
        ArchiverDownloadCompleter.baseName(entryPath));
      targets.push({
        entryIndex: entryPaths.indexOf(entryPath),
        entryPath: entryPath,
        fileName: SpiderDen.generateImageFilename(k, extension)
      });
    }
    return targets;
  }
  public static createFileName(name: string | null, gid: number): string {
    let result: string = name === null ? '' :
      ArchiverDownloadCompleter.sanitizeFilename(name);
    result = ArchiverDownloadCompleter.truncateUtf8ToMaxBytes(result, 255 - '.zip'.length);
    if (result.length === 0) {
      result = gid > 0 ? `archiver_${gid}` : 'archiver';
    }
    return result;
  }

  /**
   * 对应上游 `unzipArchive(zipFile, destDir)`。
   *
   * 与上游的差异见文件头 D-η：系统 `zlib.decompressFile` 整体解压（拿到不存在的目录则先清空），
   * 之后由调用方按文件名升序编号。返回 false 表示解压失败或无图片。
   */
  public static async unzipArchive(zipPath: string, destDir: string): Promise<boolean> {
    // 先清掉上一次残留（上游同样先 `delete(destDir)`）
    ArchiverDownloadCompleter.deleteDirStatic(destDir);
    try {
      fs.mkdirSync(destDir);
    } catch (e) {
      if (!fs.accessSync(destDir)) {
        hilog.error(DOMAIN, TAG, 'Failed to create temp dir: %{public}s', destDir);
        return false;
      }
    }

    try {
      await zlib.decompressFile(zipPath, destDir, {});
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to unzip archive: %{public}s, code=%{public}d, message=%{public}s',
        zipPath, err.code, err.message);
      ArchiverDownloadCompleter.deleteDirStatic(destDir);
      return false;
    }

    if (!ArchiverDownloadCompleter.hasImageRecursive(destDir)) {
      hilog.error(DOMAIN, TAG, 'No image files found in archive: %{public}s', zipPath);
      ArchiverDownloadCompleter.deleteDirStatic(destDir);
      return false;
    }
    return true;
  }

  /**
   * 对应上游 `resolveImportRoot(dir)`：
   * 本层有图片 → 本层；只有唯一子目录 → 下钻；否则本层。
   */
  private resolveImportRoot(dirPath: string): string | null {
    if (!this.isDirectory(dirPath)) {
      return null;
    }
    const children: string[] = this.listChildPaths(dirPath);
    let hasImageAtLevel: boolean = false;
    let onlySubdir: string | null = null;
    let subdirCount: number = 0;
    for (let i = 0; i < children.length; i++) {
      const child: string = children[i];
      if (this.isFile(child) && ArchiverDownloadCompleter.isImagePath(child)) {
        hasImageAtLevel = true;
      } else if (this.isDirectory(child)) {
        onlySubdir = child;
        subdirCount++;
      }
    }
    if (hasImageAtLevel) {
      return dirPath;
    }
    if (subdirCount === 1 && onlySubdir !== null) {
      return this.resolveImportRoot(onlySubdir);
    }
    return dirPath;
  }

  /**
   * 对应上游 `collectImageFiles(root)`：递归收集图片文件（返回路径列表）。
   */
  private collectImageFiles(rootPath: string): string[] {
    const images: string[] = [];
    this.collectImageFilesRecursive(rootPath, images);
    return images;
  }

  private collectImageFilesRecursive(dirPath: string, images: string[]): void {
    const children: string[] = this.listChildPaths(dirPath);
    for (let i = 0; i < children.length; i++) {
      const child: string = children[i];
      if (this.isDirectory(child)) {
        this.collectImageFilesRecursive(child, images);
      } else if (ArchiverDownloadCompleter.isImagePath(child)) {
        images.push(child);
      }
    }
  }

  private static isImagePath(path: string): boolean {
    const name: string = ArchiverDownloadCompleter.baseName(path).toLowerCase();
    return StringUtils.endsWith(name, SUPPORT_IMAGE_EXTENSIONS);
  }

  /**
   * 对应上游 `getImageExtension(fileName)`：未知扩展名回退到第一个受支持扩展名。
   */
  private static getImageExtension(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    const extension: string = dot >= 0 ? fileName.substring(dot).toLowerCase() : '';
    // 上游 Utilities.contain(list, value)；core-runtime 的 Utilities 只提供
    // containObject/containChar（无 string[] + string 的组合），因此这里用等价的 indexOf
    if (SUPPORT_IMAGE_EXTENSIONS.indexOf(extension) >= 0) {
      return extension;
    }
    return SUPPORT_IMAGE_EXTENSIONS[0];
  }

  /**
   * 对应上游 `truncateUtf8ToMaxBytes(s, maxBytes)`：按 UTF-8 字节数截断，
   * 代理对（surrogate pair）不截半。
   */
  private static truncateUtf8ToMaxBytes(s: string | null, maxBytes: number): string {
    if (s === null || s.length === 0 || maxBytes <= 0) {
      return s === null ? '' : s;
    }
    let byteCount: number = 0;
    let cutCharEnd: number = 0;
    let i: number = 0;
    while (i < s.length) {
      const code: number = s.charCodeAt(i);
      let charUtf8Bytes: number;
      let charWidth: number;
      if (code <= 0x7F) {
        charUtf8Bytes = 1;
        charWidth = 1;
      } else if (code <= 0x7FF) {
        charUtf8Bytes = 2;
        charWidth = 1;
      } else if (code >= 0xD800 && code <= 0xDBFF) {
        // high surrogate
        charUtf8Bytes = 4;
        charWidth = 2;
        if (i + 1 >= s.length) {
          break;
        }
      } else {
        charUtf8Bytes = 3;
        charWidth = 1;
      }
      if (byteCount + charUtf8Bytes > maxBytes) {
        break;
      }
      byteCount += charUtf8Bytes;
      i += charWidth;
      cutCharEnd = i;
    }
    return cutCharEnd < s.length ? s.substring(0, cutCharEnd) : s;
  }

  /**
   * 对应上游 `YorozuyaFileUtils.sanitizeFilename(name)`：
   * 把路径分隔符与常见非法字符替换成 `_`，去掉首尾空白与尾部点号。
   */
  private static sanitizeFilename(name: string): string {
    let result: string = '';
    for (let i = 0; i < name.length; i++) {
      const ch: string = name.charAt(i);
      if (ch === '/' || ch === '\\' || ch === ':' || ch === '*' || ch === '?' ||
        ch === '"' || ch === '<' || ch === '>' || ch === '|' || ch === '\n' || ch === '\r' ||
        ch === '\t' || ch === '\0') {
        result += '_';
      } else {
        result += ch;
      }
    }
    result = result.trim();
    while (result.length > 0 && result.charAt(result.length - 1) === '.') {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /** 文件名部分（上游 `entryBaseName` / `File.name`）。 */
  private static baseName(path: string): string {
    const slash: number = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  // ---------------------------------------------------------------- 文件系统

  private isFile(path: string): boolean {
    try {
      return fs.statSync(path).isFile();
    } catch (e) {
      return false;
    }
  }

  private isDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  private listChildPaths(dirPath: string): string[] {
    try {
      const names: string[] = fs.listFileSync(dirPath);
      const result: string[] = [];
      for (let i = 0; i < names.length; i++) {
        result.push(`${dirPath}/${names[i]}`);
      }
      return result;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'listFileSync failed: %{public}s', dirPath);
      return [];
    }
  }

  private deleteDir(dirPath: string): void {
    ArchiverDownloadCompleter.deleteDirStatic(dirPath);
  }

  private static deleteDirStatic(dirPath: string): void {
    try {
      if (fs.accessSync(dirPath)) {
        fs.rmdirSync(dirPath);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to delete temp dir: %{public}s', dirPath);
    }
  }

  private static hasImageRecursive(dirPath: string): boolean {
    try {
      const names: string[] = fs.listFileSync(dirPath);
      for (let i = 0; i < names.length; i++) {
        const child: string = `${dirPath}/${names[i]}`;
        const stat: fs.Stat = fs.statSync(child);
        if (stat.isDirectory()) {
          if (ArchiverDownloadCompleter.hasImageRecursive(child)) {
            return true;
          }
        } else if (ArchiverDownloadCompleter.isImagePath(child)) {
          return true;
        }
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  /**
   * 等价上游 `com.hippo.util.FileUtils.copyFile(source, dest, false)`。
   *
   * core-runtime 的 `hippo/util/FileUtils`（S0488）尚未交付，且 `lib/yorozuya/FileUtils`
   * 只有"路径字符串"版本（没有 UniFile 版本）。因此这里直接用 UniFile 自带的流做拷贝 ——
   * 不引入任何跨模块依赖，语义与上游一致：`replace = false`（目标由 createFile 新建，
   * 已存在时上游也不会覆盖，这里同样在调用点先 delete 再 create）。
   */
  private static copyFile(source: UniFile, dest: UniFile): boolean {
    let input: InputStream | null = null;
    let output: OutputStream | null = null;
    try {
      if (source.length() <= 0) {
        return false;
      }
      input = source.openInputStream();
      output = dest.openOutputStream();
      const buffer: ArrayBuffer = new ArrayBuffer(EXTRACT_BUFFER_SIZE);
      while (true) {
        const read: number = input.readBytes(buffer, 0, EXTRACT_BUFFER_SIZE);
        if (read <= 0) {
          break;
        }
        output.writeBytes(buffer, 0, read);
      }
      output.flush();
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'copyFile failed: %{public}s', String(e));
      return false;
    } finally {
      if (input !== null) {
        try { input.close(); } catch (e) { hilog.warn(DOMAIN, TAG, 'close input failed'); }
      }
      if (output !== null) {
        try { output.close(); } catch (e) { hilog.warn(DOMAIN, TAG, 'close output failed'); }
      }
    }
  }

  public static getExtractBufferSize(): number {
    return EXTRACT_BUFFER_SIZE;
  }

  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }
}


