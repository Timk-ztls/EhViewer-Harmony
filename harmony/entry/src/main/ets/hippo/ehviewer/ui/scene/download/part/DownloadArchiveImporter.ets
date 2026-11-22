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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/download/part/DownloadArchiveImporter.kt（232 行）。
 *
 * ============================================================================
 * 一、上游是什么（"把本地压缩包导入成一条下载记录"）
 * ============================================================================
 *   ```kotlin
 *   importLocalArchive(launcher)      // ACTION_OPEN_DOCUMENT + 8 个 MIME + CATEGORY_OPENABLE
 *   handleSelectedFile(result)        // 取持久化读权限 → 后台 processArchiveFile(uri)
 *   processArchiveFile(uri):
 *     ① 先 openInputStream 一次**验证 uri 真的可读**（权限虽然申请过，仍可能丢）
 *     ② fileName = getFileName(context, uri)；取不到 → "imported_archive_<now>"
 *     ③ isValidArchiveFormat：.zip / .rar / .cbz / .cbr（小写后 endsWith）
 *     ④ createArchiveDownloadInfo：gid = now；title = 去扩展名的文件名；archiveUri = uri（**裸 uri**）
 *     ⑤ 已存在同 gid → already_imported
 *     ⑥ manager.addDownload([info]) → 成功 Toast + updateForLabel + updateView
 *   ```
 *
 * 逐行对照时最容易丢的**五条**（本文件逐条保留并断言）：
 *   1. **先验证可读**再继续（上游 `openInputStream(...).use {}` 只是为了"打不开就失败"），
 *      不是"顺便读一下内容"；
 *   2. 取不到文件名时的兜底是 **`imported_archive_<毫秒时间戳>`**（没有扩展名 → 后面格式校验会失败，
 *      这是上游的既有行为，不要"顺手"给它补 `.zip`）；
 *   3. 格式白名单只有 **zip / rar / cbz / cbr**（7z 不支持）；
 *   4. 标题是**去掉最后一个扩展名**（正则 `\.[^.]*$`），`a.b.cbz` → `a.b`；
 *   5. `archiveUri` 存的是**裸 uri**（不像相册导入加 `local-album:` 前缀），
 *      所以 `isLocalAlbum()` 不会把它误判成本地相册。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * 与 `DownloadAlbumImporter` 同构：判据/构造在本文件，文件访问注入，
 * 界面只消费 `ArchiveImportResult`（outcome + 文案资源名）。
 */

import { DownloadInfo } from '../../../../dao/DownloadInfo';
import { EhUtils } from '../../../../client/EhUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'DownloadArchiveImporter';

/** 文件选择器接受的 MIME（上游 `EXTRA_MIME_TYPES` 的 8 项，顺序照搬）。 */
export const ARCHIVE_MIME_TYPES: string[] = [
  'application/zip',
  'application/x-zip-compressed',
  'application/x-rar-compressed',
  'application/vnd.rar',
  'application/x-rar',
  'application/rar',
  'application/x-cbz',
  'application/x-cbr'
];

/** 支持的扩展名白名单（上游 `isValidArchiveFormat`）。 */
export const SUPPORTED_ARCHIVE_EXTENSIONS: string[] = ['.zip', '.rar', '.cbz', '.cbr'];

/** 归档导入记录的 uploader 显示名（上游 `"Local Archive"`）。 */
export const ARCHIVE_UPLOADER: string = 'Local Archive';

/** 导入结果（页面据此 Toast）。 */
export enum ArchiveImportOutcome {
  SUCCESS = 0,
  FAILED = 1,
  INVALID_FORMAT = 2,
  ALREADY_IMPORTED = 3,
  /** 持久化权限申请失败（上游用 `archive_permission_lost` 文案） */
  PERMISSION_LOST = 4
}

export class ArchiveImportResult {
  outcome: ArchiveImportOutcome;
  /** 生成的 gid（毫秒时间戳；失败时可能为 0） */
  gid: number;
  /** 去扩展名后的标题 */
  title: string;

  constructor(outcome: ArchiveImportOutcome, gid: number, title: string) {
    this.outcome = outcome;
    this.gid = gid;
    this.title = title;
  }
}

/** 要写入的 DownloadInfo 字段（纯数据）。 */
export class ArchiveDownloadInfoSpec {
  gid: number = 0;
  token: string = '';
  title: string = '';
  titleJpn: string | null = null;
  thumb: string | null = null;
  category: number = EhUtils.UNKNOWN;
  posted: string | null = null;
  uploader: string = ARCHIVE_UPLOADER;
  rating: number = -1;
  state: number = 0;
  legacy: number = 0;
  time: number = 0;
  label: string | null = null;
  total: number = 0;
  finished: number = 0;
  archiveUri: string = '';
}

/** 文件选择/读取侧（生产实现包 `@ohos.file.picker` + `@ohos.file.fs`）。 */
export interface ArchiveFileSource {
  /** 申请并持有持久化读权限；失败返回 false（上游 `takePersistableUriPermission` 的两类异常）。 */
  takePersistableReadPermission(uri: string): boolean;
  /** 打开一次输入流验证可读（上游 `openInputStream(...).use {}`）。 */
  canOpen(uri: string): boolean;
  /** 取文件名；取不到返回 null（上游 `getFileName`）。 */
  fileNameOf(uri: string): string | null;
}

/**
 * 归档导入（对位上游 `DownloadArchiveImporter`）。
 */
export class DownloadArchiveImporter {
  /** 是否支持的归档格式（上游 `isValidArchiveFormat`：小写后 endsWith 白名单之一）。 */
  static isValidArchiveFormat(fileName: string | null): boolean {
    if (fileName === null) {
      return false;
    }
    const lower: string = fileName.toLowerCase();
    for (let i = 0; i < SUPPORTED_ARCHIVE_EXTENSIONS.length; i++) {
      if (lower.endsWith(SUPPORTED_ARCHIVE_EXTENSIONS[i])) {
        return true;
      }
    }
    return false;
  }

  /**
   * 取文件名；取不到时兜底 `imported_archive_<now>`（上游 `fileName == null` 分支）。
   *
   * 兜底名**没有扩展名** → 后续格式校验必然失败。这是上游行为，不要"补一个 .zip"。
   */
  static resolveFileName(actual: string | null, now: number): string {
    return actual === null ? `imported_archive_${now}` : actual;
  }

  /**
   * 由文件名得到标题（上游 `fileName.replace("\\.[^.]*$".toRegex(), "")`）。
   *
   * 等价实现：去掉**最后一个点**及其后全部字符；没有点则原样返回。
   */
  static titleOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    if (dot < 0) {
      return fileName;
    }
    return fileName.substring(0, dot);
  }

  /**
   * 构造要写入的 DownloadInfo 字段（上游 `createArchiveDownloadInfo`）。
   *
   * 关键点：`token` 是 **空串**（不是 null）、`thumb` 是 **null**、`rating` 是 **-1**、
   * `total/finished` 都是 **0**（由归档 provider 之后补），`archiveUri` 存**裸 uri**。
   */
  static buildInfoSpec(gid: number, uri: string, fileName: string): ArchiveDownloadInfoSpec {
    const spec: ArchiveDownloadInfoSpec = new ArchiveDownloadInfoSpec();
    spec.gid = gid;
    spec.token = '';
    spec.title = DownloadArchiveImporter.titleOf(fileName);
    spec.titleJpn = null;
    spec.thumb = null;
    spec.category = EhUtils.UNKNOWN;
    spec.posted = null;
    spec.uploader = ARCHIVE_UPLOADER;
    spec.rating = -1;
    spec.state = DownloadInfo.STATE_FINISH;
    spec.legacy = 0;
    spec.time = gid;             // 上游 `time = System.currentTimeMillis()`，与 gid 同源
    spec.label = null;
    spec.total = 0;
    spec.finished = 0;
    spec.archiveUri = uri;
    return spec;
  }

  /**
   * 完整流程的判定（把上游 `processArchiveFile` 的控制流压成纯函数）。
   *
   * 顺序照上游：**权限 → 可读 → 文件名 → 格式 → 已存在**。
   * 注意"取不到文件名"不在这里判失败 —— 它走兜底名，再由格式校验拦下（上游就是这样）。
   *
   * @param contains gid 是否已存在（上游 `downloadManager.containDownloadInfo(gid)`）
   */
  static planImport(uri: string, source: ArchiveFileSource, now: number,
    contains: (gid: number) => boolean): ArchiveImportResult {
    if (!source.takePersistableReadPermission(uri)) {
      return new ArchiveImportResult(ArchiveImportOutcome.PERMISSION_LOST, 0, '');
    }
    if (!source.canOpen(uri)) {
      hilog.error(DOMAIN, TAG, 'cannot open uri: %{public}s', uri);
      return new ArchiveImportResult(ArchiveImportOutcome.FAILED, 0, '');
    }
    const fileName: string = DownloadArchiveImporter.resolveFileName(source.fileNameOf(uri), now);
    if (!DownloadArchiveImporter.isValidArchiveFormat(fileName)) {
      return new ArchiveImportResult(ArchiveImportOutcome.INVALID_FORMAT, 0,
        DownloadArchiveImporter.titleOf(fileName));
    }
    const gid: number = now;
    const title: string = DownloadArchiveImporter.titleOf(fileName);
    if (contains(gid)) {
      return new ArchiveImportResult(ArchiveImportOutcome.ALREADY_IMPORTED, gid, title);
    }
    return new ArchiveImportResult(ArchiveImportOutcome.SUCCESS, gid, title);
  }

  /** 结果提示的资源名（上游每个出口的 Toast；权限丢失用专属文案）。 */
  static toastResOf(outcome: ArchiveImportOutcome): string {
    switch (outcome) {
      case ArchiveImportOutcome.SUCCESS:
        return 'import_archive_success';
      case ArchiveImportOutcome.INVALID_FORMAT:
        return 'import_archive_invalid_format';
      case ArchiveImportOutcome.ALREADY_IMPORTED:
        return 'import_archive_already_imported';
      case ArchiveImportOutcome.PERMISSION_LOST:
        return 'archive_permission_lost';
      default:
        return 'import_archive_failed';
    }
  }
}
