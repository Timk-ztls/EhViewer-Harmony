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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/fragment/DownloadFragment.java（582 行）。
 *
 * ============================================================================
 * 一、上游是什么（"设置 → 下载"这一页的全部行为）
 * ============================================================================
 * 5 个可点项 + 3 个可改项 + 2 个后台任务：
 *
 *   ```java
 *   点击：download_location（选目录）/ export_download_items（导出 CSV）
 *         import_download_items（导入 CSV）/ clean_invalid_download（清理无效下载）
 *   改动：KEY_MEDIA_SCAN / KEY_IMAGE_RESOLUTION / KEY_DOWNLOAD_TIMEOUT
 *   任务：ImportDownloadTask（读 CSV → addDownload）/ CleanInvalidDownloadTask（扫描并清理目录）
 *   ```
 *
 * 逐行对照时最容易丢/写反的**六条**（本文件逐条保留并断言）：
 *   1. **`KEY_MEDIA_SCAN` 的布尔语义是反的**：`newValue == true` → `removeNoMediaFile`（删 `.nomedia`
 *      = 允许媒体扫描），`false` → `ensureNoMediaFile`（建 `.nomedia` = 禁止扫描）。
 *      顺手写成"真就建"是最容易犯的错，且生效后用户会看到"相册里多/少了图"，很难查。
 *   2. `toTimeoutTime` 解析失败返回 **0**（0 在 UI 上表示"不限时"），不是抛错、不是 -1。
 *   3. 导出文件名 `ehviewer-download-yyyy-MM-dd-HH-mm-ss.csv`（**Locale.US** 的格式化，
 *      所以月份/小时都补零，且用 24 小时制）。
 *   4. 导入时**跳过表头行**（`line.startsWith(DOWNLOAD_INFO_HEADER)`），并且只导入
 *      `downloadManager.getDownloadInfo(gid) == null` 的条目（已存在的不覆盖）。
 *   5. 清理任务对"文件数不一致"的目录：**删掉所有非点开头的文件**（保留 `.ehviewer`），
 *      并把该 gid 的下载状态重置为 `STATE_NONE`（重新变为"未下载"）。
 *   6. 清理日志文件名 `delfile-yyyyMMddHHmm.log`（与导出的格式**不同**：无分隔符、精确到分）。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * 上游 582 行里，**约 400 行是 Android 脚手架**（PreferenceFragmentCompat 生命周期、
 * ProgressDialog、AsyncTask、Intent/ActivityResult、Build.VERSION 分支）。移植时：
 *
 *   - **判据/算法** → 本文件的纯函数与状态机（可断言）：summary 文案、点击意图、
 *     媒体扫描反向语义、超时解析、CSV 导入计划、清理决策、日志/文件名格式；
 *   - **IO** → 注入 `DownloadSettingsIo`（列目录/读文件/删文件/写文件/取 uri）与
 *     `DownloadSettingsStore`（设置读写 + 下载管理查询）；
 *   - **界面** → 返回 `UiIntent`（Toast/对话框/文件选择器），由 ArkUI 页面执行。
 *
 * `Build.VERSION` 的三分支（<19 / <21 / else）在鸿蒙上**没有对应物**：统一走"系统目录选择器"，
 * 这条等价关系写在这里，避免后人以为漏了一个分支。
 */

import { GalleryInfo } from '../../client/data/GalleryInfo';
import { DownloadInfo } from '../../dao/DownloadInfo';
import { DOWNLOAD_INFO_FILENAME, DOWNLOAD_INFO_HEADER } from '../../download/DownloadInfoCsvFormat';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'DownloadFragment';

/** 下载设置页里可点击的四个项（上游 `KEY_*` 常量）。 */
export enum DownloadSettingKey {
  DOWNLOAD_LOCATION = 0,
  EXPORT_DOWNLOAD_ITEMS = 1,
  IMPORT_DOWNLOAD_ITEMS = 2,
  CLEAN_INVALID_DOWNLOAD = 3,
  /** 其余（普通设置项，不在此页处理点击） */
  OTHER = 99
}

/** 点击后的意图（UI 层据此弹选择器/对话框/跑任务）。 */
export enum DownloadSettingAction {
  NONE = 0,
  /** 打开目录选择器（上游三个 SDK 分支统一到这条） */
  PICK_DIRECTORY = 1,
  /** 导出 CSV */
  EXPORT_CSV = 2,
  /** 选一个 CSV 文件来导入 */
  PICK_IMPORT_FILE = 3,
  /** 弹确认框（确认后跑清理任务） */
  CONFIRM_CLEAN_INVALID = 4
}

/** 媒体扫描开关变化后要对 `.nomedia` 做什么。 */
export enum NoMediaAction {
  /** 无需动作（新值不是布尔） */
  NONE = 0,
  /** 删除 `.nomedia`（允许媒体扫描）—— 上游 `newValue == true` 分支 */
  REMOVE = 1,
  /** 创建 `.nomedia`（禁止媒体扫描）—— 上游 `newValue == false` 分支 */
  ENSURE = 2
}

/** 要落到 Settings 的写入（Settings 侧 API 未 land 前，调用方按此意图写）。 */
export enum SettingsWrite {
  NONE = 0,
  PUT_IMAGE_RESOLUTION = 1,
  SET_DOWNLOAD_TIMEOUT = 2
}

/** 一条 UI 意图（Toast / 摘要 / 对话框），由 ArkUI 页面渲染。 */
export class UiIntent {
  /** `toast` / `summary` / `dialog` */
  kind: string;
  resKey: string;
  args: (string | number)[];

  constructor(kind: string, resKey: string, args: (string | number)[]) {
    this.kind = kind;
    this.resKey = resKey;
    this.args = args;
  }

  static toast(resKey: string, ...args: (string | number)[]): UiIntent {
    return new UiIntent('toast', resKey, args);
  }

  static summary(resKey: string, ...args: (string | number)[]): UiIntent {
    return new UiIntent('summary', resKey, args);
  }
}

/** 设置读取侧（上游直接 `Settings.xxx()`；这里注入，便于 Settings 未补齐时也能跑规则）。 */
export interface DownloadSettingsStore {
  /** 下载目录 uri（`Settings.getDownloadLocation()` 的 uri 字符串）；无则 null。 */
  downloadLocationUri(): string | null;
  multiThreadDownload(): boolean;
  imageResolution(): string;
  /** 0 表示不限时（上游 `Settings.getDownloadTimeout()`）。 */
  downloadTimeout(): number;
  preloadImage(): boolean;
  /** 已存在的下载 gid 集合（上游 `downloadManager.getDownloadInfo(gid) != null` 的判定）。 */
  hasDownload(gid: number): boolean;
}

/** 清理任务的日志（上游 `mLogs`）。 */
export class CleanLog {
  lines: string[] = [];

  add(line: string): void {
    this.lines.push(line);
  }

  isEmpty(): boolean {
    return this.lines.length === 0;
  }
}

/** 单个目录的清理决策（`CleanInvalidDownloadTask.doInBackground` 的循环体）。 */
export class CleanDirDecision {
  /** 是否计入 invalidCount */
  invalid: boolean;
  /** 要删掉的整个目录（空目录） */
  deleteDir: boolean;
  /** 要删掉的文件名（非点开头、非 `.ehviewer`） */
  deleteFiles: string[];
  /** 需要重置为 STATE_NONE 的 gid；-1 表示不用 */
  resetGid: number;
  /** 日志行；空串表示不记 */
  log: string;

  constructor(invalid: boolean, deleteDir: boolean, deleteFiles: string[], resetGid: number, log: string) {
    this.invalid = invalid;
    this.deleteDir = deleteDir;
    this.deleteFiles = deleteFiles;
    this.resetGid = resetGid;
    this.log = log;
  }
}

/** 导入计划（`ImportDownloadTask.doInBackground` 的结果）。 */
export class ImportPlan {
  /** 可导入的画廊（已去重：只留 downloadManager 里没有的） */
  toAdd: GalleryInfo[];
  /** CSV 里解析出的有效条目总数（含已存在的） */
  parsedCount: number;
  /** CSV 行总数（不含表头） */
  lineCount: number;

  constructor(toAdd: GalleryInfo[], parsedCount: number, lineCount: number) {
    this.toAdd = toAdd;
    this.parsedCount = parsedCount;
    this.lineCount = lineCount;
  }
}

/**
 * 下载设置页（对位上游 `DownloadFragment`）。
 */
export class DownloadFragment {
  /** 上游 `KEY_DOWNLOAD_LOCATION` / `KEY_EXPORT_DOWNLOAD_ITEMS` / `KEY_IMPORT_DOWNLOAD_ITEMS` /
   *  `KEY_CLEAN_INVALID_DOWNLOAD` 的**字面值**（设置页 XML 里用它们做 key，必须逐字一致）。 */
  public static readonly KEY_DOWNLOAD_LOCATION: string = 'download_location';
  public static readonly KEY_EXPORT_DOWNLOAD_ITEMS: string = 'export_download_items';
  public static readonly KEY_IMPORT_DOWNLOAD_ITEMS: string = 'import_download_items';
  public static readonly KEY_CLEAN_INVALID_DOWNLOAD: string = 'clean_invalid_download';

  /** 上游 `"download_thread"` / `"preload_image"`（普通设置项，只用来设 summary）。 */
  public static readonly KEY_DOWNLOAD_THREAD: string = 'download_thread';
  public static readonly KEY_PRELOAD_IMAGE: string = 'preload_image';

  /**
   * `Settings` 侧三个 key 的**字面值**（上游 `Settings.java`）：
   *   `KEY_MEDIA_SCAN = "media_scan"`、`KEY_IMAGE_RESOLUTION = "image_size"`、`KEY_DOWNLOAD_TIMEOUT = "download_timeout"`
   *
   * 注意 `KEY_IMAGE_RESOLUTION` 的字面值是 **`"image_size"`**（不是 `image_resolution`）——
   * 设置页 XML 与 `Settings` 都按这个字符串对接，写错就静默失效。
   * Settings 侧尚未导出这些常量，故在此单点声明；将来 Settings 导出后改为引用。
   */
  public static readonly KEY_MEDIA_SCAN: string = 'media_scan';
  public static readonly KEY_IMAGE_RESOLUTION: string = 'image_size';
  public static readonly KEY_DOWNLOAD_TIMEOUT: string = 'download_timeout';

  /** 清理时判定 `.ehviewer` 有效性的最少行数（上游 `lines.length < 8`）。 */
  public static readonly MIN_INFO_LINES: number = 8;
  /** `.ehviewer` 里第 9 行（下标 7）是页数（上游 `Integer.parseInt(lines[7])`）。 */
  public static readonly INFO_PAGES_INDEX: number = 7;
  /** `.ehviewer` 里第 1 行（下标 0）是 gid（上游 `Long.parseLong(lines[0])`）。 */
  public static readonly INFO_GID_INDEX: number = 0;

  // ------------------------------------------------------------------ 键与摘要

  /** 设置项的 key → 可点击项枚举（上游 `onPreferenceClick` 的 if 链）。 */
  static keyOf(key: string): DownloadSettingKey {
    switch (key) {
      case DownloadFragment.KEY_DOWNLOAD_LOCATION:
        return DownloadSettingKey.DOWNLOAD_LOCATION;
      case DownloadFragment.KEY_EXPORT_DOWNLOAD_ITEMS:
        return DownloadSettingKey.EXPORT_DOWNLOAD_ITEMS;
      case DownloadFragment.KEY_IMPORT_DOWNLOAD_ITEMS:
        return DownloadSettingKey.IMPORT_DOWNLOAD_ITEMS;
      case DownloadFragment.KEY_CLEAN_INVALID_DOWNLOAD:
        return DownloadSettingKey.CLEAN_INVALID_DOWNLOAD;
      default:
        return DownloadSettingKey.OTHER;
    }
  }

  /** 点击意图（上游 `onPreferenceClick`）。 */
  static planClick(key: string): DownloadSettingAction {
    switch (DownloadFragment.keyOf(key)) {
      case DownloadSettingKey.DOWNLOAD_LOCATION:
        // 上游按 SDK 分三支（<19 直接选目录 / <21 提示后选目录 / else 提示两个按钮），
        // 鸿蒙无 SDK 分支 → 统一走系统目录选择器。
        return DownloadSettingAction.PICK_DIRECTORY;
      case DownloadSettingKey.EXPORT_DOWNLOAD_ITEMS:
        return DownloadSettingAction.EXPORT_CSV;
      case DownloadSettingKey.IMPORT_DOWNLOAD_ITEMS:
        return DownloadSettingAction.PICK_IMPORT_FILE;
      case DownloadSettingKey.CLEAN_INVALID_DOWNLOAD:
        return DownloadSettingAction.CONFIRM_CLEAN_INVALID;
      default:
        return DownloadSettingAction.NONE;
    }
  }

  /**
   * 下载目录的摘要（上游 `onUpdateDownloadLocation`）。
   *
   * 有目录 → 摘要就是 **uri 字符串**（不是路径）；没有 → 显示"位置无效"。
   */
  static downloadLocationSummary(uri: string | null): UiIntent {
    if (uri === null || uri.length === 0) {
      return UiIntent.summary('settings_download_invalid_download_location');
    }
    return UiIntent.summary(uri);
  }

  /**
   * 各设置项的初始摘要（上游 `onCreatePreferences` 里 5 个 setSummary）。
   *
   * @param multiThread 多线程下载开关（`Settings.getMultiThreadDownload()`）
   * @param resolution  图片分辨率（`Settings.getImageResolution()`）
   * @param timeout     超时秒数（0 = 不限时）
   * @param preload     预加载图片开关
   */
  static initSummaries(multiThread: boolean, resolution: string, timeout: number,
    preload: boolean): Map<string, UiIntent> {
    const map: Map<string, UiIntent> = new Map<string, UiIntent>();
    map.set(DownloadFragment.KEY_DOWNLOAD_THREAD,
      UiIntent.summary('settings_download_multi_thread_download_summary', `${multiThread}`));
    map.set(DownloadFragment.KEY_IMAGE_RESOLUTION,
      UiIntent.summary('settings_download_image_resolution_summary', resolution));
    // 0 → "不限时"文案（上游三元表达式）
    const timeoutText: string = timeout === 0 ? 'download_timeout_unlimited' : `${timeout}`;
    map.set(DownloadFragment.KEY_DOWNLOAD_TIMEOUT,
      UiIntent.summary('settings_download_timeout_summary', timeoutText));
    map.set(DownloadFragment.KEY_PRELOAD_IMAGE,
      UiIntent.summary('settings_download_preload_image_summary', `${preload}`));
    return map;
  }

  // ------------------------------------------------------------------ 设置变更

  /**
   * 媒体扫描开关变化（上游 `onPreferenceChange` 的 `KEY_MEDIA_SCAN` 分支）。
   *
   * **语义是反的**：新值 `true` = 允许媒体扫描 = **删掉** `.nomedia`；
   * 新值 `false` = 禁止扫描 = **创建** `.nomedia`。
   */
  static planMediaScanChange(newValue: Object | null): NoMediaAction {
    // **不能写 `newValue instanceof Boolean`**：Java 的 `instanceof` 在这里没有等价语义 ——
    // ArkTS/JS 的 boolean 原始值 `true` 并不是 `Boolean` 的实例，`instanceof` 恒为 false，
    // 照抄会静默变成"永远不动作"（开关改了但 .nomedia 没动）。用 `typeof` 判原始类型。
    if (typeof newValue !== 'boolean') {
      return NoMediaAction.NONE;
    }
    return (newValue as boolean) ? NoMediaAction.REMOVE : NoMediaAction.ENSURE;
  }

  /**
   * 下载超时的解析（上游 `toTimeoutTime`）：解析失败 → **0**（= 不限时）。
   */
  static toTimeoutTime(newValue: string | null): number {
    if (newValue === null) {
      return 0;
    }
    const trimmed: string = newValue.trim();
    if (trimmed.length === 0) {
      return 0;
    }
    const parsed: number = Number.parseInt(trimmed, 10);
    if (Number.isNaN(parsed)) {
      return 0;
    }
    return parsed;
  }

  /** 设置变更计划：要写哪个设置、写什么值（上游 `onPreferenceChange`）。 */
  static planSettingsWrite(key: string, newValue: Object | null): Map<string, Object> {
    const out: Map<string, Object> = new Map<string, Object>();
    if (key === DownloadFragment.KEY_MEDIA_SCAN) {
      out.set('noMedia', DownloadFragment.planMediaScanChange(newValue));
      return out;
    }
    // 同 planMediaScanChange：用 `typeof` 而不是 `instanceof String`（后者对原始字符串恒 false）
    if (key === DownloadFragment.KEY_IMAGE_RESOLUTION) {
      if (typeof newValue === 'string') {
        out.set('write', SettingsWrite.PUT_IMAGE_RESOLUTION);
        out.set('value', newValue as string);
      }
      return out;
    }
    if (key === DownloadFragment.KEY_DOWNLOAD_TIMEOUT) {
      if (typeof newValue === 'string') {
        out.set('write', SettingsWrite.SET_DOWNLOAD_TIMEOUT);
        out.set('value', DownloadFragment.toTimeoutTime(newValue as string));
      }
      return out;
    }
    return out;
  }

  // ------------------------------------------------------------------ 导出

  /** 两位补零（上游 `SimpleDateFormat` 的效果，不引 Intl/时区依赖）。 */
  private static pad2(v: number): string {
    return v < 10 ? `0${v}` : `${v}`;
  }

  /**
   * 导出文件名（上游 `SimpleDateFormat("yyyy-MM-dd-HH-mm-ss", Locale.US)`）。
   *
   * @param d 时间（毫秒）
   */
  static exportFileName(d: Date): string {
    const y: number = d.getFullYear();
    const mo: string = DownloadFragment.pad2(d.getMonth() + 1);
    const day: string = DownloadFragment.pad2(d.getDate());
    const h: string = DownloadFragment.pad2(d.getHours());
    const mi: string = DownloadFragment.pad2(d.getMinutes());
    const s: string = DownloadFragment.pad2(d.getSeconds());
    return `ehviewer-download-${y}-${mo}-${day}-${h}-${mi}-${s}.csv`;
  }

  /** 清理日志文件名（上游 `SimpleDateFormat("yyyyMMddHHmm", Locale.US)` + `delfile-` 前缀）。 */
  static cleanLogFileName(d: Date): string {
    const y: number = d.getFullYear();
    const mo: string = DownloadFragment.pad2(d.getMonth() + 1);
    const day: string = DownloadFragment.pad2(d.getDate());
    const h: string = DownloadFragment.pad2(d.getHours());
    const mi: string = DownloadFragment.pad2(d.getMinutes());
    return `delfile-${y}${mo}${day}${h}${mi}.log`;
  }

  /**
   * 导出的 CSV 内容（上游：先写表头，再逐条 `gi.toCSV()`）。
   *
   * 注意 `GalleryInfo.toCSV()` **自带换行**（上游也依赖这一点：直接拼，不再补 `\n`）。
   */
  static buildExportContent(items: GalleryInfo[]): string {
    let out: string = DOWNLOAD_INFO_HEADER;
    for (let i = 0; i < items.length; i++) {
      out += items[i].toCSV();
    }
    return out;
  }

  /** 导出前的检查（上游 `exportDownloadItems` 的两个 Toast 分支）。 */
  static planExport(itemCount: number, downloadLocationUri: string | null): UiIntent | null {
    if (itemCount === 0) {
      return UiIntent.toast('settings_download_export_no_items');
    }
    if (downloadLocationUri === null || downloadLocationUri.length === 0) {
      return UiIntent.toast('settings_download_invalid_download_location');
    }
    return null;
  }

  /** 导出成功/失败的提示（上游 `settings_download_export_succeed` 带 uri）。 */
  static exportResultToast(success: boolean, uri: string): UiIntent {
    return success
      ? UiIntent.toast('settings_download_export_succeed', uri)
      : UiIntent.toast('settings_download_export_failed');
  }

  // ------------------------------------------------------------------ 导入

  /**
   * 解析导入的 CSV 内容（上游 `ImportDownloadTask` 的解析段）。
   *
   * - 按 `\n` 切行；
   * - **跳过表头行**（`startsWith(DOWNLOAD_INFO_HEADER)`）；
   * - `GalleryInfo.fromCSV(line)` 返回 null 的行直接丢弃（字段不足/数字解析失败）。
   */
  static parseImportCsv(content: string): GalleryInfo[] {
    const out: GalleryInfo[] = [];
    const lines: string[] = content.split('\n');
    // ---- 导入侧自愈（Lead 裁决：只修「数据损失」，不改导出格式）----
    // 上游导出把「表头」与「第一条记录」粘在同一行（`DOWNLOAD_INFO_HEADER` 末尾无换行，
    // 而 `GalleryInfo.toCSV()` 每条以换行结尾），导入侧再按 `startsWith(HEADER)` 跳过整行
    // → 第一条永久丢失。这里把它切回来：
    //   * 仅当第一行**以表头开头且更长**时才切（长度正好等于表头 → 本来就只有表头）；
    //   * 保留 warn，让"数据被修复过"这件事在日志里可见。
    // 为什么修在导入侧而不是改导出格式：改导出会让"我们的 csv ≠ 上游的 csv"，
    // 验收时无法再用金样本比对；而丢记录是用户的实质损失。
    if (lines.length > 0) {
      const first: string = lines[0];
      if (first.length > DOWNLOAD_INFO_HEADER.length && first.startsWith(DOWNLOAD_INFO_HEADER)) {
        lines[0] = first.substring(DOWNLOAD_INFO_HEADER.length);
        hilog.warn(DOMAIN, TAG,
          'import: repaired concatenated header+first-record line (upstream export defect), ' +
            'restored %{public}d chars', lines[0].length);
      }
    }
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith(DOWNLOAD_INFO_HEADER)) {
        continue;
      }
      const gi: GalleryInfo | null = GalleryInfo.fromCSV(line);
      if (gi !== null) {
        out.push(gi);
      }
    }
    return out;
  }

  /**
   * 导入计划（上游：只导入 `getDownloadInfo(gid) == null` 的条目）。
   *
   * @param parsed 已解析出的画廊
   * @param existing 判定"是否已存在"的注入函数（避免规则层依赖 DownloadManager 单例）
   */
  static planImport(parsed: GalleryInfo[], existing: (gid: number) => boolean): ImportPlan {
    const toAdd: GalleryInfo[] = [];
    for (let i = 0; i < parsed.length; i++) {
      if (!existing(parsed[i].gid)) {
        toAdd.push(parsed[i]);
      }
    }
    return new ImportPlan(toAdd, parsed.length, parsed.length);
  }

  /** 导入结果提示（上游 `result > 0` 两支）。 */
  static importResultToast(importCount: number): UiIntent {
    return importCount > 0
      ? UiIntent.toast('settings_download_import_succeed', importCount)
      : UiIntent.toast('settings_download_import_failed');
  }

  // ------------------------------------------------------------------ 清理无效下载

  /**
   * 单个目录的清理决策（上游 `CleanInvalidDownloadTask` 循环体）。
   *
   * 四种结局（与上游日志字符串逐字一致）：
   *   ① 非目录 → 跳过（invalid=false）
   *   ② 目录为空 → 日志 `Empty directory: <name>`，invalid，**删目录**
   *   ③ 缺 `.ehviewer` → 日志 `Missing .ehviewer file: <name>`，invalid（**不删**）
   *   ④ `.ehviewer` 行数 < 8 → 日志 `Invalid .ehviewer file: <name>`，invalid，
   *      并尝试用 `lines[0]` 当 gid 重置状态
   *   ⑤ 文件数与页数不一致 → 日志 `Inconsistent file count: <name>, expected: X, actual: Y`，
   *      invalid，删掉所有非点开头文件（保留 `.ehviewer`），并重置状态
   *
   * @param dirName    目录名
   * @param isDirectory 是否为目录
   * @param subFiles   子文件名列表（不含目录项）
   * @param infoContent `.ehviewer` 内容；null 表示文件不存在
   */
  static planCleanDir(dirName: string, isDirectory: boolean, subFiles: string[],
    infoContent: string | null): CleanDirDecision {
    if (!isDirectory) {
      return new CleanDirDecision(false, false, [], -1, '');
    }
    if (subFiles.length === 0) {
      return new CleanDirDecision(true, true, [], -1, `Empty directory: ${dirName}`);
    }
    if (infoContent === null) {
      return new CleanDirDecision(true, false, [], -1, `Missing .ehviewer file: ${dirName}`);
    }
    const lines: string[] = infoContent.split('\n');
    if (lines.length < DownloadFragment.MIN_INFO_LINES) {
      const gid: number = DownloadFragment.parseGid(lines);
      return new CleanDirDecision(true, false, [], gid, `Invalid .ehviewer file: ${dirName}`);
    }
    const pageCount: number = DownloadFragment.parsePageCount(lines);
    if (pageCount < 0) {
      // 上游 `Integer.parseInt(lines[7])` 抛 NumberFormatException 会被外层 catch 记
      // `Error processing directory: ...`，这里等价地返回 invalid + 该日志
      return new CleanDirDecision(true, false, [], -1,
        `Error processing directory: ${dirName} - pageCount parse failed`);
    }
    let imageFileCount: number = 0;
    const toDelete: string[] = [];
    for (let i = 0; i < subFiles.length; i++) {
      const name: string = subFiles[i];
      if (name.length > 0 && !name.startsWith('.')) {
        imageFileCount++;
        if (name !== DOWNLOAD_INFO_FILENAME) {
          toDelete.push(name);
        }
      }
    }
    if (imageFileCount !== pageCount) {
      const gid: number = DownloadFragment.parseGid(lines);
      return new CleanDirDecision(true, false, toDelete, gid,
        `Inconsistent file count: ${dirName}, expected: ${pageCount}, actual: ${imageFileCount}`);
    }
    return new CleanDirDecision(false, false, [], -1, '');
  }

  /** `.ehviewer` 第一行的 gid（上游 `Long.parseLong(lines[0])`，失败 → -1）。 */
  static parseGid(lines: string[]): number {
    if (lines.length <= DownloadFragment.INFO_GID_INDEX) {
      return -1;
    }
    const v: number = Number.parseInt(lines[DownloadFragment.INFO_GID_INDEX].trim(), 10);
    return Number.isNaN(v) ? -1 : v;
  }

  /** `.ehviewer` 里的页数（上游 `Integer.parseInt(lines[7])`，失败 → -1）。 */
  static parsePageCount(lines: string[]): number {
    if (lines.length <= DownloadFragment.INFO_PAGES_INDEX) {
      return -1;
    }
    const v: number = Number.parseInt(lines[DownloadFragment.INFO_PAGES_INDEX].trim(), 10);
    return Number.isNaN(v) ? -1 : v;
  }

  /** 清理结果提示（上游 `result > 0` 两支）。 */
  static cleanResultToast(invalidCount: number): UiIntent {
    return invalidCount > 0
      ? UiIntent.toast('settings_download_clean_invalid_done', invalidCount)
      : UiIntent.toast('settings_download_clean_invalid_no_invalid');
  }

  /** 清理日志的正文（上游 `saveLog`：每条 + `\n`）。 */
  static buildCleanLogContent(logs: CleanLog): string {
    let out: string = '';
    for (let i = 0; i < logs.lines.length; i++) {
      out += `${logs.lines[i]}\n`;
    }
    return out;
  }

  // ------------------------------------------------------------------ 任务状态机

  /**
   * 清理任务的进度（上游 `publishProgress(0, total)` 起步、每处理一个 `publishProgress(i+1, total)`）。
   *
   * 独立成纯函数是因为"进度条不动/倒退"是这类任务最常见的可见 bug。
   */
  static cleanProgress(index: number, total: number): ProgressState {
    return new ProgressState(index, total);
  }
}

/** 进度（上游 `ProgressDialog.setProgress/setMax`）。 */
export class ProgressState {
  progress: number;
  max: number;

  constructor(progress: number, max: number) {
    this.progress = progress;
    this.max = max;
  }
}
