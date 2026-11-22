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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/download/part/DownloadAlbumImporter.kt（355 行）。
 *
 * ============================================================================
 * 一、上游是什么（"把本地图片文件夹导入成一个已完成画廊"）
 * ============================================================================
 *   ```kotlin
 *   importLocalAlbum(launcher)          // ACTION_OPEN_DOCUMENT_TREE 选目录
 *   handleSelectedFolder(result)        // 取持久化读权限 → 后台 processAlbumFolder(uri)
 *   processAlbumFolder(uri):
 *     ① UniFile.fromTreeUri → 非目录 → 失败
 *     ② archiveUri = "local-album:" + uri ；已导入过 → 提示 already_imported
 *     ③ resolveImportRoot：本层有图用本层；唯一子目录则下钻；否则本层
 *     ④ collectImageFiles（递归）→ 空 → no_images
 *     ⑤ **按文件名自然序排序**（NaturalComparator）—— 决定页序
 *     ⑥ 下载目录为空 → invalid_download_location
 *     ⑦ gid = System.currentTimeMillis()
 *     ⑧ prepareDownloadStorage 失败 → 清理 + 失败
 *     ⑨ copyImages：命名用 `generateImageFilename(copiedCount, ext)`（**成功数当序号**）
 *     ⑩ total = finished = copiedCount；写 SpiderInfo；复制首图当 .thumb
 *     ⑪ manager.addDownload([info]) → 成功 Toast + updateForLabel + updateView
 *   ```
 *
 * 逐行对照时最容易丢的**六条**（本文件逐条保留并断言）：
 *   1. `archiveUri` 前缀是 **`local-album:`**（与归档导入的裸 uri 区分，`isLocalAlbum` 靠它判定）；
 *   2. `resolveImportRoot` 的三个分支：**本层有图 → 本层**；**唯一子目录 → 递归下钻**；否则本层
 *      （注意"唯一子目录"要求 subdirCount == 1，多个子目录不下钻）；
 *   3. 图片列表按 **NaturalComparator**（`a2 < a10`）排序，不是字典序；
 *   4. 目标文件名序号用 **已成功复制的数量**（跳过的文件不留空号）；
 *   5. 标题取文件夹名；**名字为空（含全空白）** → `imported_album_<gid>`；
 *   6. 失败清理要删目录 **并** `EhDB.removeDownloadDirname(gid)`（否则下次同名目录会被沿用）。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * 上游 355 行里约 150 行是 Android 选择器/权限/Toast 胶水。移植分三层：
 *   - **判据/构造**（本文件）：路径解析、图片筛选与排序、命名、DownloadInfo 字段、去重判定；
 *   - **文件系统** → 注入 `AlbumFileSystem`（生产实现包 UniFile / `@ohos.file.fs`）；
 *   - **界面** → 返回 `AlbumImportResult`（成功/失败 + 文案资源名 + 计数），由 ArkUI 页面 Toast。
 *
 * gid 用 `Date.now()`（上游 `System.currentTimeMillis()`）—— 时间戳当本地画廊 id。
 */

import { DownloadInfo } from '../../../../dao/DownloadInfo';
import { EhUtils } from '../../../../client/EhUtils';
import { NaturalComparator } from '../../../../../util/NaturalComparator';
import { SUPPORT_IMAGE_EXTENSIONS, SpiderDen } from '../../../../spider/SpiderDen';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'DownloadAlbumImporter';

/** 本地相册的 archiveUri 前缀（上游 `URI_PREFIX`）：与归档导入的裸 uri 区分。 */
export const URI_PREFIX: string = 'local-album:';
/** 本地相册的 token / thumb 占位（上游 `LOCAL_TOKEN` / `LOCAL_THUMB`，**都是 "local"**）。 */
export const LOCAL_TOKEN: string = 'local';
export const LOCAL_THUMB: string = 'local';
/** 本地相册的 uploader 显示名（上游 `LOCAL_UPLOADER`）。 */
export const LOCAL_UPLOADER: string = 'Local Album';
/** 缩略图文件名（上游 `.thumb`）。 */
export const THUMB_FILENAME: string = '.thumb';

/** 目录项的最小投影（避免规则层依赖 UniFile）。 */
export class DirEntryLike {
  name: string;
  isDirectory: boolean;
  isFile: boolean;

  constructor(name: string, isDirectory: boolean, isFile: boolean) {
    this.name = name;
    this.isDirectory = isDirectory;
    this.isFile = isFile;
  }
}

/**
 * 文件系统抽象（生产实现包 UniFile / `@ohos.file.fs`；测试用内存实现）。
 *
 * 路径用字符串表示，目录用完整路径；`list` 返回**条目名**（与 `UniFile.listFiles + getName` 一致）。
 */
export interface AlbumFileSystem {
  isDirectory(path: string): boolean;
  isFile(path: string): boolean;
  list(dir: string): DirEntryLike[] | null;
  /** 在 `dir` 下创建文件；成功返回 true。 */
  createFile(dir: string, name: string): boolean;
  /** `dir` 下是否存在同名条目。 */
  exists(dir: string, name: string): boolean;
  /** 删除 `dir/name`；成功返回 true。 */
  deleteIn(dir: string, name: string): boolean;
  /** 复制文件；成功返回 true。 */
  copyFile(srcPath: string, destPath: string): boolean;
  /** 删除整个目录（失败不抛）。 */
  deleteDir(path: string): boolean;
}

/** 导入结果（页面据此 Toast）；`kind` 与上游每个出口一一对应。 */
export enum AlbumImportOutcome {
  SUCCESS = 0,
  FAILED = 1,
  ALREADY_IMPORTED = 2,
  NO_IMAGES = 3,
  INVALID_DOWNLOAD_LOCATION = 4
}

export class AlbumImportResult {
  outcome: AlbumImportOutcome;
  /** SUCCESS 时的已复制张数 */
  copiedCount: number;
  /** `archiveUri`（`local-album:` + uri）；失败时可能为空 */
  archiveUri: string;

  constructor(outcome: AlbumImportOutcome, copiedCount: number, archiveUri: string) {
    this.outcome = outcome;
    this.copiedCount = copiedCount;
    this.archiveUri = archiveUri;
  }
}

/** 导入时要写入的 DownloadInfo 字段（纯数据，便于断言"字段集与值"）。 */
export class AlbumDownloadInfoSpec {
  gid: number = 0;
  token: string = LOCAL_TOKEN;
  title: string = '';
  titleJpn: string | null = null;
  thumb: string = LOCAL_THUMB;
  category: number = EhUtils.UNKNOWN;
  posted: string | null = null;
  uploader: string = LOCAL_UPLOADER;
  rating: number = -1;
  state: number = 0;
  legacy: number = 0;
  time: number = 0;
  label: string | null = null;
  total: number = 0;
  finished: number = 0;
  archiveUri: string = '';
}

/**
 * 相册导入（对位上游 `DownloadAlbumImporter`）。
 */
export class DownloadAlbumImporter {
  /** 是否本地相册（上游 `isLocalAlbum`）：`archiveUri` 以 `local-album:` 开头。 */
  static isLocalAlbum(info: DownloadInfo | null): boolean {
    if (info === null) {
      return false;
    }
    const uri: string | null = info.archiveUri;
    return uri !== null && uri.startsWith(URI_PREFIX);
  }

  /** 构造 `archiveUri`（上游 `URI_PREFIX + uri.toString()`）。 */
  static archiveUriOf(uri: string): string {
    return URI_PREFIX + uri;
  }

  /**
   * 是否已导入过（上游 `isAlreadyImported`：遍历全部下载记录比 `archiveUri`）。
   *
   * 注意是**全等比较**（不是前缀/包含）—— 同一个 uri 只能用一次。
   */
  static isAlreadyImported(archiveUri: string, infos: DownloadInfo[]): boolean {
    for (let i = 0; i < infos.length; i++) {
      if (archiveUri === infos[i].archiveUri) {
        return true;
      }
    }
    return false;
  }

  /**
   * 决定真正的导入根（上游 `resolveImportRoot`）。
   *
   * 三个分支：
   *   - 本层有图片 → 用本层；
   *   - 只有一个子目录 → **递归下钻**（多套一层的解压目录常见）；
   *   - 其它（多个子目录 / 没有图也没有子目录）→ 用本层。
   *
   * @returns 导入根路径；入参不是目录时返回 null
   */
  static resolveImportRoot(fs: AlbumFileSystem, dir: string): string | null {
    if (!fs.isDirectory(dir)) {
      return null;
    }
    const children: DirEntryLike[] | null = fs.list(dir);
    if (children === null) {
      return null;
    }
    let hasImageAtLevel: boolean = false;
    let onlySubdir: string | null = null;
    let subdirCount: number = 0;
    for (let i = 0; i < children.length; i++) {
      const child: DirEntryLike = children[i];
      if (child.isFile && DownloadAlbumImporter.isImageName(child.name)) {
        hasImageAtLevel = true;
      } else if (child.isDirectory) {
        onlySubdir = DownloadAlbumImporter.join(dir, child.name);
        subdirCount++;
      }
    }
    if (hasImageAtLevel) {
      return dir;
    }
    if (subdirCount === 1 && onlySubdir !== null) {
      return DownloadAlbumImporter.resolveImportRoot(fs, onlySubdir);
    }
    return dir;
  }

  /** 递归收集图片的**完整路径**（上游 `collectImageFiles` + `...Recursive`）。 */
  static collectImagePaths(fs: AlbumFileSystem, root: string): string[] {
    const out: string[] = [];
    DownloadAlbumImporter.collectRecursive(fs, root, out);
    return out;
  }

  private static collectRecursive(fs: AlbumFileSystem, dir: string, out: string[]): void {
    const children: DirEntryLike[] | null = fs.list(dir);
    if (children === null) {
      return;
    }
    for (let i = 0; i < children.length; i++) {
      const child: DirEntryLike = children[i];
      if (child.isDirectory) {
        DownloadAlbumImporter.collectRecursive(fs, DownloadAlbumImporter.join(dir, child.name), out);
      } else if (DownloadAlbumImporter.isImageName(child.name)) {
        out.push(DownloadAlbumImporter.join(dir, child.name));
      }
    }
  }

  /**
   * 按文件名**自然序**排序（上游 `Collections.sort(images, NaturalComparator)`）。
   *
   * 为什么重要：这是**页序**。字典序会把 `10.jpg` 排到 `2.jpg` 之前，用户看到的顺序就乱了。
   */
  static sortNatural(paths: string[]): string[] {
    const cmp: NaturalComparator = new NaturalComparator();
    const copy: string[] = paths.slice();
    copy.sort((a: string, b: string): number =>
      cmp.compare(DownloadAlbumImporter.basename(a), DownloadAlbumImporter.basename(b)));
    return copy;
  }

  /** 文件名是否图片（上游 `isImageFile`：**小写后** endsWith 任一支持扩展名）。 */
  static isImageName(fileName: string): boolean {
    const lower: string = fileName.toLowerCase();
    for (let i = 0; i < SUPPORT_IMAGE_EXTENSIONS.length; i++) {
      if (lower.endsWith(SUPPORT_IMAGE_EXTENSIONS[i])) {
        return true;
      }
    }
    return false;
  }

  /**
   * 取图片扩展名（上游 `getImageExtension`）。
   *
   * 规则：取最后一个 `.` 之后（**含点**）、转小写；不在支持列表里（或没有扩展名）→
   * 回退到 `SUPPORT_IMAGE_EXTENSIONS[0]`（`.jpg`）。
   */
  static imageExtensionOf(fileName: string | null): string {
    if (fileName === null) {
      return SUPPORT_IMAGE_EXTENSIONS[0];
    }
    const dot: number = fileName.lastIndexOf('.');
    const ext: string = dot >= 0 ? fileName.substring(dot).toLowerCase() : '';
    for (let i = 0; i < SUPPORT_IMAGE_EXTENSIONS.length; i++) {
      if (SUPPORT_IMAGE_EXTENSIONS[i] === ext) {
        return ext;
      }
    }
    return SUPPORT_IMAGE_EXTENSIONS[0];
  }

  /** 目标文件名（上游 `generateImageFilename(copiedCount, ext)`）：**序号用成功数**。 */
  static targetNameOf(copiedCount: number, sourceName: string): string {
    return SpiderDen.generateImageFilename(copiedCount, DownloadAlbumImporter.imageExtensionOf(sourceName));
  }

  /**
   * 构造要写入的 DownloadInfo 字段（上游 `createAlbumDownloadInfo`）。
   *
   * @param folderName 源目录名；`null` / 空 / **全空白** → `imported_album_<gid>`
   */
  static buildInfoSpec(gid: number, folderName: string | null, archiveUri: string,
    imageCount: number, label: string | null): AlbumDownloadInfoSpec {
    const spec: AlbumDownloadInfoSpec = new AlbumDownloadInfoSpec();
    spec.gid = gid;
    spec.time = gid;                       // 上游 `downloadInfo.time = gid`
    const trimmed: string = folderName === null ? '' : folderName.trim();
    spec.title = trimmed.length === 0 ? `imported_album_${gid}` : (folderName as string);
    spec.total = imageCount;
    spec.finished = imageCount;
    spec.archiveUri = archiveUri;
    spec.label = label;
    spec.state = DownloadInfo.STATE_FINISH;
    spec.legacy = 0;
    return spec;
  }

  /**
   * 复制阶段的逐张决策（`copyImages` 的循环体，纯逻辑）。
   *
   * 上游顺序：**跳过非文件 → 算目标名 → 若同名文件存在且删不掉 → 跳过 → 建文件（失败跳过）→ 复制（失败删掉）**。
   *
   * @returns 该张是否精确按"先删同名再建再复制"走完；调用方据此 `copiedCount++`
   */
  static copyOne(fs: AlbumFileSystem, sourcePath: string, downloadDir: string,
    copiedCount: number): boolean {
    if (!fs.isFile(sourcePath)) {
      return false;
    }
    const newName: string = DownloadAlbumImporter.targetNameOf(copiedCount,
      DownloadAlbumImporter.basename(sourcePath));
    if (fs.exists(downloadDir, newName) && !fs.deleteIn(downloadDir, newName)) {
      hilog.error(DOMAIN, TAG, 'cannot delete existing file: %{public}s', newName);
      return false;
    }
    if (!fs.createFile(downloadDir, newName)) {
      hilog.error(DOMAIN, TAG, 'cannot create file: %{public}s', newName);
      return false;
    }
    if (!fs.copyFile(sourcePath, DownloadAlbumImporter.join(downloadDir, newName))) {
      hilog.error(DOMAIN, TAG, 'copy failed: %{public}s → %{public}s', sourcePath, newName);
      fs.deleteIn(downloadDir, newName);
      return false;
    }
    return true;
  }

  /** 失败清理（上游 `cleanupFailedImport`）：删目录 + 删 gid→dirname 映射。 */
  static cleanupFailed(fs: AlbumFileSystem, downloadDir: string | null,
    gid: number, removeDirname: (gid: number) => void): void {
    if (downloadDir !== null) {
      try {
        fs.deleteDir(downloadDir);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'failed to delete incomplete album dir: %{public}s', `${e}`);
      }
    }
    if (gid > 0) {
      removeDirname(gid);
    }
  }

  /** 结果提示的资源名（上游每个出口的 Toast）。 */
  static toastResOf(outcome: AlbumImportOutcome): string {
    switch (outcome) {
      case AlbumImportOutcome.SUCCESS:
        return 'import_album_success';
      case AlbumImportOutcome.ALREADY_IMPORTED:
        return 'import_album_already_imported';
      case AlbumImportOutcome.NO_IMAGES:
        return 'import_album_no_images';
      case AlbumImportOutcome.INVALID_DOWNLOAD_LOCATION:
        return 'settings_download_invalid_download_location';
      default:
        return 'import_album_failed';
    }
  }

  /** 路径拼接（单级，与 UniFile.subFile 同语义）。 */
  static join(dir: string, name: string): string {
    return dir.length > 0 && dir.charAt(dir.length - 1) === '/' ? dir + name : `${dir}/${name}`;
  }

  /** 取文件名（`a/b/c.jpg` → `c.jpg`）。 */
  static basename(path: string): string {
    const idx: number = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }
}
