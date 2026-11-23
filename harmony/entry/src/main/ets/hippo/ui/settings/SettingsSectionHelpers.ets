/*
 * Phase B Track P2: Pure ArkTS/TypeScript helpers & controllers for Settings 7 groups,
 * DirPickerPage, and LicensePage.
 *
 * Kept free of ArkUI struct imports so every rule, filesystem adapter, CSV/DB/logcat
 * workflow, and state transition can be unit-tested cleanly in Node/tsc without ArkUI runtime.
 */

import fs from '@ohos.file.fs';
import i18n from '@ohos.i18n';
import util from '@ohos.util';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../../ehviewer/Settings';
import { AppConfig } from '../../ehviewer/AppConfig';
import { GalleryInfo } from '../../ehviewer/client/data/GalleryInfo';
import { UniFile } from '../../unifile/UniFile';
import { Contracts, InputStream, OutputStream } from '../../unifile/Contracts';
import {
  DownloadFragment,
  NoMediaAction,
  SettingsWrite,
  UiIntent,
  CleanLog,
  CleanDirDecision,
  ImportPlan
} from '../../ehviewer/ui/fragment/DownloadFragment';
import { ReadSettingsRules } from '../../ehviewer/ui/fragment/ReadSettingsRules';
import { PrivacySettingsRules, AnalyticsTogglePlan } from '../../ehviewer/ui/fragment/PrivacySettingsRules';
import {
  AdvancedFragment,
  AdvancedActionsLike,
  LoadingStatusStore
} from '../../ehviewer/ui/fragment/AdvancedFragment';
import { AboutFragment, AboutActionsLike } from '../../ehviewer/ui/fragment/AboutFragment';
import { DirectoryExplorerLike } from '../../ehviewer/ui/DirPickerActivity';
import { LicenseActivity } from '../../ehviewer/ui/LicenseActivity';
import {
  RestoreDownloadPreference,
  RestoreItem,
  RestoreScanResult,
  SpiderHeader
} from '../../ehviewer/preference/RestoreDownloadPreference';
import { CleanResult } from '../../ehviewer/preference/CleanRedundancyPreference';
import { VersionPreference } from '../../ehviewer/preference/VersionPreference';
import { PreferenceActions } from '../../ehviewer/preference/PreferenceActions';
import { LogCat, LogCatIo } from '../../util/LogCat';
import { ReadableTime } from '../../util/ReadableTime';
import { DOWNLOAD_INFO_FILENAME } from '../../ehviewer/download/DownloadInfoCsvFormat';
import { ReadingRefreshRate } from '../../ehviewer/util/ReadingRefreshRate';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'SettingsSectionHelpers';

// ── Shared string formatting helper ─────────────────────────────────────────

export class SettingsTextFormatter {
  /**
   * Formats simple printf-style placeholders (`%s`, `%d`, `%1$s`, `%1$d`) for UI toasts/summaries.
   */
  static format(template: string, args: Array<string | number>): string {
    if (args.length === 0) {
      return template;
    }
    let out: string = template;
    for (let i = 0; i < args.length; i++) {
      const val: string = `${args[i]}`;
      const pos: number = i + 1;
      const posStr: string = `%${pos}$s`;
      const posNum: string = `%${pos}$d`;
      if (out.indexOf(posStr) >= 0) {
        out = out.split(posStr).join(val);
        continue;
      }
      if (out.indexOf(posNum) >= 0) {
        out = out.split(posNum).join(val);
        continue;
      }
      const sIdx: number = out.indexOf('%s');
      const dIdx: number = out.indexOf('%d');
      if (sIdx >= 0 && (dIdx < 0 || sIdx < dIdx)) {
        out = out.substring(0, sIdx) + val + out.substring(sIdx + 2);
      } else if (dIdx >= 0) {
        out = out.substring(0, dIdx) + val + out.substring(dIdx + 2);
      }
    }
    return out;
  }

  /**
   * Converts simple HTML tags (`<br>`, `<a href="...">`, `<b>`) into readable plain text for AlertDialog.
   */
  static stripBasicHtml(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    let out: string = raw.replace(/<br\s*\/?>/gi, '\n');
    out = out.replace(/<\/p>/gi, '\n\n');
    out = out.replace(/<[^>]+>/g, '');
    out = out.replace(/&amp;/g, '&');
    out = out.replace(/&lt;/g, '<');
    out = out.replace(/&gt;/g, '>');
    out = out.replace(/&quot;/g, '"');
    return out.trim();
  }
}

// ── UTF-8 UniFile text helpers ──────────────────────────────────────────────

export class UniFileTextIo {
  static writeUtf8(file: UniFile, text: string): boolean {
    let os: OutputStream | null = null;
    try {
      const encoder: util.TextEncoder = new util.TextEncoder();
      const encoded: Uint8Array = encoder.encodeInto(text);
      const buf: ArrayBuffer = encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.byteLength);
      os = file.openOutputStream();
      os.write(buf);
      os.flush();
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'writeUtf8 failed for %{public}s: %{public}s', file.getUri(), msg);
      return false;
    } finally {
      if (os !== null) {
        try {
          os.close();
        } catch (closeErr) {
          const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'writeUtf8 close failed: %{public}s', msg);
        }
      }
    }
  }

  static readUtf8(file: UniFile): string | null {
    let is: InputStream | null = null;
    try {
      is = file.openInputStream();
      const chunks: Uint8Array[] = [];
      let totalLen: number = 0;
      const chunkSize: number = 4096;
      let reading: boolean = true;
      while (reading) {
        const buf: ArrayBuffer = new ArrayBuffer(chunkSize);
        const n: number = is.readBuffer(buf);
        if (n <= 0) {
          reading = false;
        } else {
          chunks.push(new Uint8Array(buf, 0, n));
          totalLen += n;
        }
      }
      const merged: Uint8Array = new Uint8Array(totalLen);
      let offset: number = 0;
      for (let i = 0; i < chunks.length; i++) {
        merged.set(chunks[i], offset);
        offset += chunks[i].length;
      }
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(merged);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'readUtf8 failed for %{public}s: %{public}s', file.getUri(), msg);
      return null;
    } finally {
      if (is !== null) {
        try {
          is.close();
        } catch (closeErr) {
          const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'readUtf8 close failed: %{public}s', msg);
        }
      }
    }
  }
}

// ── DirPicker helpers & real sandbox DirectoryExplorerLike ──────────────────

export class DirPickerHelpers {
  static normalizePath(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    if (Contracts.isUri(raw)) {
      return raw;
    }
    let normalized: string = raw.replace(/\\/g, '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static basenameOf(pathOrUri: string): string {
    const clean: string = DirPickerHelpers.normalizePath(pathOrUri);
    if (clean.length === 0 || clean === '/') {
      return '/';
    }
    const idx: number = clean.lastIndexOf('/');
    if (idx < 0 || idx === clean.length - 1) {
      return clean;
    }
    return clean.substring(idx + 1);
  }

  static canGoUp(currentPath: string): boolean {
    if (currentPath.length === 0) {
      return false;
    }
    if (UniFile.isDocumentUri(currentPath)) {
      return false;
    }
    const fsPath: string = Contracts.normalize(currentPath);
    const idx: number = fsPath.lastIndexOf('/');
    return idx > 0;
  }

  static resolveInitialPath(paramPath: string | null, currentLocation: UniFile | null,
    defaultDownloadDir: string | null): string {
    if (paramPath !== null && paramPath.length > 0) {
      return DirPickerHelpers.normalizePath(paramPath);
    }
    if (currentLocation !== null) {
      const uri: string = currentLocation.getUri();
      if (uri.length > 0) {
        if (UniFile.isDocumentUri(uri)) {
          return uri;
        }
        return Contracts.normalize(uri);
      }
    }
    if (defaultDownloadDir !== null && defaultDownloadDir.length > 0) {
      return DirPickerHelpers.normalizePath(defaultDownloadDir);
    }
    return '/';
  }

  static resolveDownloadLocationUniFile(pathOrUri: string): UniFile | null {
    const trimmed: string = pathOrUri.trim();
    if (trimmed.length === 0) {
      return null;
    }
    if (Contracts.isUri(trimmed)) {
      return UniFile.fromUri(trimmed);
    }
    return UniFile.fromFile(trimmed);
  }

  static isAuthorizedDocumentUri(uri: string): boolean {
    return UniFile.isDocumentUri(uri);
  }
}

export class SandboxDirectoryExplorer implements DirectoryExplorerLike {
  private readonly authorizedUris: Set<string> = new Set<string>();
  private readonly onListed: ((path: string, entries: string[]) => void) | null;

  constructor(onListed: ((path: string, entries: string[]) => void) | null = null) {
    this.onListed = onListed;
  }

  markAuthorizedPickerUri(uri: string): void {
    if (uri.length > 0) {
      this.authorizedUris.add(uri);
    }
  }

  async listDirectories(path: string): Promise<string[]> {
    const dirs: string[] = [];
    if (path.length === 0) {
      this.notifyLoaded(path, dirs);
      return dirs;
    }
    const fsPath: string = Contracts.normalize(path);
    try {
      if (!fs.accessSync(fsPath)) {
        this.notifyLoaded(path, dirs);
        return dirs;
      }
      const stat: fs.Stat = fs.statSync(fsPath);
      if (!stat.isDirectory()) {
        this.notifyLoaded(path, dirs);
        return dirs;
      }
      const names: string[] = fs.listFileSync(fsPath);
      names.sort((a: string, b: string): number => a.localeCompare(b));
      for (let i = 0; i < names.length; i++) {
        const name: string = names[i];
        if (name.length === 0 || name === '.' || name === '..') {
          continue;
        }
        const childPath: string = Contracts.childOf(fsPath, name);
        try {
          const childStat: fs.Stat = fs.statSync(childPath);
          if (childStat.isDirectory()) {
            dirs.push(childPath);
          }
        } catch (childErr) {
          const msg: string = childErr instanceof Error ? childErr.message : String(childErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'stat child dir failed for %{public}s: %{public}s', childPath, msg);
        }
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'listDirectories failed for %{public}s: %{public}s', path, msg);
    }
    this.notifyLoaded(path, dirs);
    return dirs;
  }

  async isWritable(path: string): Promise<boolean> {
    if (path.length === 0) {
      return false;
    }
    if (this.authorizedUris.has(path)) {
      return true;
    }
    if (UniFile.isDocumentUri(path)) {
      const docFile: UniFile | null = UniFile.fromUri(path);
      return docFile !== null && docFile.exists() && docFile.canWrite();
    }
    const fsPath: string = Contracts.normalize(path);
    try {
      if (!fs.accessSync(fsPath)) {
        return false;
      }
      const st: fs.Stat = fs.statSync(fsPath);
      if (!st.isDirectory()) {
        return false;
      }
      return fs.accessSync(fsPath, fs.AccessModeType.WRITE);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'isWritable check failed for %{public}s: %{public}s', path, msg);
      return false;
    }
  }

  private notifyLoaded(path: string, entries: string[]): void {
    if (this.onListed !== null) {
      this.onListed(path, entries);
    }
  }
}

// ── Download Settings Controller ────────────────────────────────────────────

export class MediaScanApplyResult {
  readonly action: NoMediaAction;
  readonly applied: boolean;

  constructor(action: NoMediaAction, applied: boolean) {
    this.action = action;
    this.applied = applied;
  }
}

export class DownloadExportResult {
  readonly ok: boolean;
  readonly fileUri: string;
  readonly toast: UiIntent;

  constructor(ok: boolean, fileUri: string, toast: UiIntent) {
    this.ok = ok;
    this.fileUri = fileUri;
    this.toast = toast;
  }
}

export class DownloadImportResult {
  readonly importedCount: number;
  readonly parsedCount: number;
  readonly toast: UiIntent;

  constructor(importedCount: number, parsedCount: number, toast: UiIntent) {
    this.importedCount = importedCount;
    this.parsedCount = parsedCount;
    this.toast = toast;
  }
}

export class CleanInvalidResult {
  readonly invalidCount: number;
  readonly logFileUri: string | null;
  readonly logs: string[];
  readonly toast: UiIntent;

  constructor(invalidCount: number, logFileUri: string | null, logs: string[], toast: UiIntent) {
    this.invalidCount = invalidCount;
    this.logFileUri = logFileUri;
    this.logs = logs;
    this.toast = toast;
  }
}

export class RestoreRunResult {
  readonly noDirectory: boolean;
  readonly foundCount: number;
  readonly restoredCount: number;
  readonly toastResKey: string;
  readonly toastArg: number | null;

  constructor(noDirectory: boolean, foundCount: number, restoredCount: number,
    toastResKey: string, toastArg: number | null) {
    this.noDirectory = noDirectory;
    this.foundCount = foundCount;
    this.restoredCount = restoredCount;
    this.toastResKey = toastResKey;
    this.toastArg = toastArg;
  }
}

export class CleanRedundancyRunResult {
  readonly result: CleanResult;
  readonly toastResKey: string;
  readonly toastArg: number | null;

  constructor(result: CleanResult, toastResKey: string, toastArg: number | null) {
    this.result = result;
    this.toastResKey = toastResKey;
    this.toastArg = toastArg;
  }
}

export class DownloadSettingsController {
  static readonly NO_MEDIA_FILENAME: string = '.nomedia';
  static readonly MULTI_THREAD_VALUES: string[] = ['1', '3', '5', '7'];
  static readonly PRELOAD_IMAGE_VALUES: string[] = ['3', '5', '7', '11', '13', '17'];
  static readonly IMAGE_RESOLUTION_VALUES: string[] = ['a', '780', '1280', '1600', '2400'];
  static readonly DOWNLOAD_TIMEOUT_VALUES: string[] = ['0', '10', '30', '50', '100', '200', '300'];

  static getDownloadLocationSummary(resolveRes: (key: string) => string,
    locationOverride?: UniFile | null): string {
    const loc: UniFile | null = locationOverride !== undefined ? locationOverride : Settings.getDownloadLocation();
    const uri: string | null = loc !== null ? loc.getUri() : null;
    const intent: UiIntent = DownloadFragment.downloadLocationSummary(uri);
    if (intent.resKey === 'settings_download_invalid_download_location') {
      return resolveRes(intent.resKey);
    }
    return intent.resKey;
  }

  /**
   * Persists media_scan and enforces upstream inverted `.nomedia` semantics:
   *   - `enabled === true`  (allow media scan)    -> REMOVE `.nomedia`
   *   - `enabled === false` (disallow media scan) -> ENSURE `.nomedia`
   */
  static applyMediaScanChange(enabled: boolean, dirOverride?: UniFile | null): MediaScanApplyResult {
    Settings.putMediaScan(enabled);
    const action: NoMediaAction = DownloadFragment.planMediaScanChange(enabled);
    const dir: UniFile | null = dirOverride !== undefined ? dirOverride : Settings.getDownloadLocation();
    if (dir === null || action === NoMediaAction.NONE) {
      return new MediaScanApplyResult(action, false);
    }
    try {
      if (action === NoMediaAction.REMOVE) {
        const noMedia: UniFile | null = dir.subFile(DownloadSettingsController.NO_MEDIA_FILENAME);
        if (noMedia !== null && noMedia.isFile()) {
          return new MediaScanApplyResult(action, noMedia.delete());
        }
        return new MediaScanApplyResult(action, true);
      }
      if (action === NoMediaAction.ENSURE) {
        const created: UniFile | null = dir.createFile(DownloadSettingsController.NO_MEDIA_FILENAME);
        return new MediaScanApplyResult(action, created !== null);
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'applyMediaScanChange failed: %{public}s', msg);
    }
    return new MediaScanApplyResult(action, false);
  }

  static applyImageResolution(rawValue: string): string | null {
    const plan: Map<string, Object> = DownloadFragment.planSettingsWrite(
      DownloadFragment.KEY_IMAGE_RESOLUTION, rawValue);
    if (plan.get('write') === SettingsWrite.PUT_IMAGE_RESOLUTION) {
      const val: string = plan.get('value') as string;
      Settings.putImageResolution(val);
      return val;
    }
    return null;
  }

  static applyDownloadTimeout(rawValue: string): number {
    const plan: Map<string, Object> = DownloadFragment.planSettingsWrite(
      DownloadFragment.KEY_DOWNLOAD_TIMEOUT, rawValue);
    if (plan.get('write') === SettingsWrite.SET_DOWNLOAD_TIMEOUT) {
      const timeout: number = plan.get('value') as number;
      Settings.putDownloadTimeout(timeout);
      return timeout;
    }
    const fallback: number = DownloadFragment.toTimeoutTime(rawValue);
    Settings.putDownloadTimeout(fallback);
    return fallback;
  }

  static exportDownloadItems(items: GalleryInfo[], downloadDir: UniFile | null,
    now?: Date): DownloadExportResult {
    const dirUri: string | null = downloadDir !== null ? downloadDir.getUri() : null;
    const preCheck: UiIntent | null = DownloadFragment.planExport(items.length, dirUri);
    if (preCheck !== null) {
      return new DownloadExportResult(false, '', preCheck);
    }
    const dir: UniFile = downloadDir as UniFile;
    const timestamp: Date = now !== undefined ? now : new Date();
    const fileName: string = DownloadFragment.exportFileName(timestamp);
    const outFile: UniFile | null = dir.createFile(fileName);
    if (outFile === null) {
      return new DownloadExportResult(false, '', DownloadFragment.exportResultToast(false, ''));
    }
    const content: string = DownloadFragment.buildExportContent(items);
    const written: boolean = UniFileTextIo.writeUtf8(outFile, content);
    const outUri: string = outFile.getUri();
    return new DownloadExportResult(written, written ? outUri : '',
      DownloadFragment.exportResultToast(written, outUri));
  }

  static async importDownloadItemsFromContent(csvContent: string,
    hasDownload: (gid: number) => boolean,
    addDownload: (gi: GalleryInfo) => Promise<void>): Promise<DownloadImportResult> {
    const parsed: GalleryInfo[] = DownloadFragment.parseImportCsv(csvContent);
    const plan: ImportPlan = DownloadFragment.planImport(parsed, hasDownload);
    let importedCount: number = 0;
    for (let i = 0; i < plan.toAdd.length; i++) {
      try {
        await addDownload(plan.toAdd[i]);
        importedCount++;
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'importDownloadItem gid=%{public}d failed: %{public}s',
          plan.toAdd[i].gid, msg);
      }
    }
    return new DownloadImportResult(importedCount, plan.parsedCount,
      DownloadFragment.importResultToast(importedCount));
  }

  static async cleanInvalidDownloads(downloadDir: UniFile | null,
    resetDownloadState: (gid: number) => Promise<void>,
    now?: Date,
    onProgress?: (done: number, total: number) => void): Promise<CleanInvalidResult> {
    if (downloadDir === null) {
      return new CleanInvalidResult(0, null, [],
        UiIntent.toast('settings_download_invalid_download_location'));
    }
    const entries: UniFile[] | null = downloadDir.listFiles();
    if (entries === null) {
      return new CleanInvalidResult(0, null, [],
        UiIntent.toast('settings_download_invalid_download_location'));
    }
    const total: number = entries.length;
    if (onProgress !== undefined) {
      const initState = DownloadFragment.cleanProgress(0, total);
      onProgress(initState.progress, initState.max);
    }

    const cleanLog: CleanLog = new CleanLog();
    let invalidCount: number = 0;

    for (let i = 0; i < total; i++) {
      const entry: UniFile = entries[i];
      const rawName: string | undefined = entry.getName();
      const dirName: string = rawName !== undefined ? rawName : '';
      const isDir: boolean = entry.isDirectory();

      let subFileNames: string[] = [];
      let infoContent: string | null = null;
      const childMap: Map<string, UniFile> = new Map<string, UniFile>();

      if (isDir) {
        const children: UniFile[] | null = entry.listFiles();
        if (children !== null) {
          for (let c = 0; c < children.length; c++) {
            const child: UniFile = children[c];
            const childName: string | undefined = child.getName();
            if (childName !== undefined && childName.length > 0) {
              if (!child.isDirectory()) {
                subFileNames.push(childName);
                childMap.set(childName, child);
              }
              if (childName === DOWNLOAD_INFO_FILENAME && child.isFile()) {
                infoContent = UniFileTextIo.readUtf8(child);
              }
            }
          }
        }
      }

      const decision: CleanDirDecision = DownloadFragment.planCleanDir(
        dirName, isDir, subFileNames, infoContent);
      if (decision.invalid) {
        invalidCount++;
        if (decision.log.length > 0) {
          cleanLog.add(decision.log);
        }
        if (decision.deleteDir) {
          entry.delete();
        }
        for (let d = 0; d < decision.deleteFiles.length; d++) {
          const target: UniFile | undefined = childMap.get(decision.deleteFiles[d]);
          if (target !== undefined) {
            target.delete();
          }
        }
        if (decision.resetGid >= 0) {
          try {
            await resetDownloadState(decision.resetGid);
          } catch (resetErr) {
            const msg: string = resetErr instanceof Error ? resetErr.message : String(resetErr);
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'resetDownloadState gid=%{public}d failed: %{public}s',
              decision.resetGid, msg);
          }
        }
      }

      if (onProgress !== undefined) {
        const step = DownloadFragment.cleanProgress(i + 1, total);
        onProgress(step.progress, step.max);
      }
    }

    let logFileUri: string | null = null;
    if (!cleanLog.isEmpty()) {
      const logTime: Date = now !== undefined ? now : new Date();
      const logName: string = DownloadFragment.cleanLogFileName(logTime);
      const logFile: UniFile | null = downloadDir.createFile(logName);
      if (logFile !== null) {
        const ok: boolean = UniFileTextIo.writeUtf8(logFile, DownloadFragment.buildCleanLogContent(cleanLog));
        if (ok) {
          logFileUri = logFile.getUri();
        }
      }
    }

    return new CleanInvalidResult(invalidCount, logFileUri, cleanLog.lines.slice(),
      DownloadFragment.cleanResultToast(invalidCount));
  }

  static async runRestoreDownloads(
    containsDownload: (gid: number) => boolean,
    readHeader: (file: UniFile) => SpiderHeader | null,
    fillTitles: (items: RestoreItem[]) => Promise<Map<number, string>>,
    addDownload: (item: RestoreItem, title: string) => void,
    putDirname: (gid: number, dirname: string) => Promise<void>,
    onProgress?: (progress: number, max: number) => void,
    dirOverride?: UniFile | null,
    readComicInfo?: (dir: UniFile) => SpiderHeader | null
  ): Promise<RestoreRunResult> {
    const scan: RestoreScanResult = await RestoreDownloadPreference.scanRestoreItems(
      containsDownload,
      readHeader,
      DOWNLOAD_INFO_FILENAME,
      onProgress,
      undefined,
      dirOverride,
      (): UniFile | null => Settings.getDownloadLocation(),
      readComicInfo
    );
    if (scan.noDirectory) {
      return new RestoreRunResult(true, 0, 0, 'settings_download_cant_get_download_location', null);
    }
    if (scan.items.length === 0) {
      return new RestoreRunResult(false, 0, 0, 'settings_download_restore_not_found', null);
    }
    if (onProgress !== undefined) {
      onProgress(-1, -1);
    }
    let titleMap: Map<number, string> = new Map<number, string>();
    try {
      titleMap = await fillTitles(scan.items);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'restore fillTitles failed (fallback to dirname/gid): %{public}s', msg);
    }
    const restored: number = await RestoreDownloadPreference.applyRestore(
      scan.items,
      (item: RestoreItem): string | null => {
        const t: string | undefined = titleMap.get(item.gid);
        return t !== undefined && t.length > 0 ? t : null;
      },
      (item: RestoreItem): void => {
        const t: string | undefined = titleMap.get(item.gid);
        const resolvedTitle: string = item.title !== null && item.title.length > 0
          ? item.title
          : RestoreDownloadPreference.resolveRestoreTitle(item, t);
        addDownload(item, resolvedTitle);
      },
      putDirname
    );
    if (restored > 0) {
      return new RestoreRunResult(false, scan.items.length, restored,
        'settings_download_restore_successfully', restored);
    }
    return new RestoreRunResult(false, scan.items.length, 0, 'settings_download_restore_failed', null);
  }

  static async runCleanRedundancy(
    contains: (gid: number) => boolean,
    onProgress?: (done: number, total: number) => void,
    dirOverride?: UniFile | null
  ): Promise<CleanRedundancyRunResult> {
    const res: CleanResult = await PreferenceActions.cleanRedundancy(contains, onProgress, dirOverride);
    if (res.noDirectory) {
      return new CleanRedundancyRunResult(res, 'settings_download_cant_get_download_location', null);
    }
    if (res.count > 0) {
      return new CleanRedundancyRunResult(res, 'settings_download_clean_redundancy_done', res.count);
    }
    return new CleanRedundancyRunResult(res, 'settings_download_clean_redundancy_no_redundancy', null);
  }
}

// ── Read Settings Helpers ───────────────────────────────────────────────────

export class ReadSettingsHelpers {
  static readonly SCREEN_ROTATION_VALUES: string[] = ['0', '1', '2', '3'];
  static readonly SCREEN_ROTATION_LABEL_KEYS: string[] = [
    'settings_read_screen_rotation_default',
    'settings_read_screen_rotation_portrait',
    'settings_read_screen_rotation_landscape',
    'settings_read_screen_rotation_sensor'
  ];

  static readonly REFRESH_RATE_VALUES: string[] = ['0', '60', '90', '120', '-1'];
  static readonly REFRESH_RATE_LABEL_KEYS: string[] = [
    'settings_read_refresh_rate_default',
    'settings_read_refresh_rate_60',
    'settings_read_refresh_rate_90',
    'settings_read_refresh_rate_120',
    'settings_read_refresh_rate_max'
  ];

  static readonly READING_DIRECTION_VALUES: string[] = ['0', '1', '2'];
  static readonly READING_DIRECTION_LABEL_KEYS: string[] = [
    'settings_read_reading_direction_left_to_right',
    'settings_read_reading_direction_right_to_Left',
    'settings_read_reading_direction_top_to_bottom'
  ];

  static readonly PAGE_SCALING_VALUES: string[] = ['0', '1', '2', '3', '4'];
  static readonly PAGE_SCALING_LABEL_KEYS: string[] = [
    'settings_read_page_scaling_actual_size',
    'settings_read_page_scaling_fit_to_width',
    'settings_read_page_scaling_fit_to_height',
    'settings_read_page_scaling_fit_to_screen',
    'settings_read_page_scaling_fixed_scale'
  ];

  static readonly START_POSITION_VALUES: string[] = ['0', '1', '2', '3', '4'];
  static readonly START_POSITION_LABEL_KEYS: string[] = [
    'settings_read_start_position_top_left',
    'settings_read_start_position_top_right',
    'settings_read_start_position_bottom_left',
    'settings_read_start_position_bottom_right',
    'settings_read_start_position_center'
  ];

  static readonly AUTO_TRANSFER_TIME_MIN: number = 0;
  static readonly AUTO_TRANSFER_TIME_MAX: number = 15;
  static readonly SCREEN_LIGHTNESS_MIN: number = 0;
  static readonly SCREEN_LIGHTNESS_MAX: number = 200;

  /**
   * Aligns with ReadSettingsRules: strictly hides Reading Refresh Rate when unsupported.
   */
  static shouldShowReadingRefreshRate(supportedOverride?: boolean): boolean {
    if (supportedOverride !== undefined) {
      return supportedOverride;
    }
    return ReadSettingsRules.shouldShowReadingRefreshRate();
  }

  /**
   * Ordered preference keys rendered by ReadSettingsSection.
   * When refresh rate is unsupported, `reading_refresh_rate` is omitted completely (not disabled).
   */
  static buildVisibleReadKeys(refreshRateSupported?: boolean): string[] {
    const keys: string[] = [Settings.KEY_SCREEN_ROTATION];
    if (ReadSettingsHelpers.shouldShowReadingRefreshRate(refreshRateSupported)) {
      keys.push(ReadSettingsRules.KEY_READING_REFRESH_RATE);
    }
    keys.push(
      Settings.KEY_READING_DIRECTION,
      Settings.KEY_PAGE_SCALING,
      Settings.KEY_START_POSITION,
      Settings.KEY_START_TRANSFER_TIME,
      Settings.KEY_KEEP_SCREEN_ON,
      Settings.KEY_SHOW_CLOCK,
      Settings.KEY_SHOW_PROGRESS,
      Settings.KEY_SHOW_BATTERY,
      Settings.KEY_SHOW_PAGE_INTERVAL,
      Settings.KEY_VOLUME_PAGE,
      Settings.KEY_REVERSE_VOLUME_PAGE,
      Settings.KEY_READING_FULLSCREEN,
      Settings.KEY_CUSTOM_SCREEN_LIGHTNESS,
      Settings.KEY_SCREEN_LIGHTNESS
    );
    return keys;
  }

  static clampAutoTransferTime(value: number): number {
    const n: number = Math.trunc(value);
    if (n < ReadSettingsHelpers.AUTO_TRANSFER_TIME_MIN) {
      return ReadSettingsHelpers.AUTO_TRANSFER_TIME_MIN;
    }
    if (n > ReadSettingsHelpers.AUTO_TRANSFER_TIME_MAX) {
      return ReadSettingsHelpers.AUTO_TRANSFER_TIME_MAX;
    }
    return n;
  }

  static clampScreenLightness(value: number): number {
    const n: number = Math.trunc(value);
    if (n < ReadSettingsHelpers.SCREEN_LIGHTNESS_MIN) {
      return ReadSettingsHelpers.SCREEN_LIGHTNESS_MIN;
    }
    if (n > ReadSettingsHelpers.SCREEN_LIGHTNESS_MAX) {
      return ReadSettingsHelpers.SCREEN_LIGHTNESS_MAX;
    }
    return n;
  }

  static sanitizeRefreshRateValue(raw: string): number {
    const parsed: number = Number.parseInt(raw, 10);
    if (Number.isNaN(parsed)) {
      return ReadingRefreshRate.SYSTEM_DEFAULT;
    }
    return ReadingRefreshRate.sanitize(parsed);
  }
}

// ── Privacy Settings Helpers ────────────────────────────────────────────────

export class PrivacySettingsHelpers {
  static patternProtectionSummaryRes(securityPattern: string | null): string {
    return PrivacySettingsRules.patternProtectionSummaryRes(securityPattern);
  }

  /**
   * Executes analytics toggle according to PrivacySettingsRules:
   * persists value and invokes `onStartAnalytics` ONLY when toggled to `true`.
   * Never stops analytics when toggled to `false`.
   */
  static applyAnalyticsToggle(newValue: boolean, onStartAnalytics: () => void): AnalyticsTogglePlan {
    const plan: AnalyticsTogglePlan = PrivacySettingsRules.planAnalyticsToggle(
      Settings.KEY_ENABLE_ANALYTICS,
      newValue,
      Settings.KEY_ENABLE_ANALYTICS
    );
    if (plan.accept) {
      Settings.putEnableAnalytics(newValue);
    }
    if (plan.shouldStartAnalytics) {
      onStartAnalytics();
    }
    return plan;
  }

  static applySecureScreenToggle(enabled: boolean): boolean {
    Settings.putEnabledSecurity(enabled);
    return Settings.getEnabledSecurity();
  }
}

// ── Advanced Settings Helpers ───────────────────────────────────────────────

export class LogcatDumpResult {
  readonly ok: boolean;
  readonly filePath: string;
  readonly toastResKey: string;

  constructor(ok: boolean, filePath: string, toastResKey: string) {
    this.ok = ok;
    this.filePath = filePath;
    this.toastResKey = toastResKey;
  }
}

export class DbExportResult {
  readonly ok: boolean;
  readonly filePath: string;
  readonly toastResKey: string;

  constructor(ok: boolean, filePath: string, toastResKey: string) {
    this.ok = ok;
    this.filePath = filePath;
    this.toastResKey = toastResKey;
  }
}

export class DbImportResult {
  readonly ok: boolean;
  readonly errorKey: string | null;
  readonly toastResKey: string;

  constructor(ok: boolean, errorKey: string | null, toastResKey: string) {
    this.ok = ok;
    this.errorKey = errorKey;
    this.toastResKey = toastResKey;
  }
}

export class FsLogCatIo implements LogCatIo {
  private readonly snapshotProvider: () => string;

  constructor(snapshotProvider?: () => string) {
    this.snapshotProvider = snapshotProvider !== undefined
      ? snapshotProvider
      : (): string => AdvancedSettingsHelpers.buildDiagnosticSnapshot();
  }

  async ensureFile(path: string): Promise<boolean> {
    try {
      const slashIdx: number = path.lastIndexOf('/');
      if (slashIdx > 0) {
        const parent: string = path.substring(0, slashIdx);
        if (!fs.accessSync(parent)) {
          fs.mkdirSync(parent, true);
        }
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.closeSync(file);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'FsLogCatIo.ensureFile failed for %{public}s: %{public}s', path, msg);
      return false;
    }
  }

  async dumpLogs(): Promise<Uint8Array> {
    const text: string = this.snapshotProvider();
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(text);
  }

  async writeBytes(path: string, bytes: Uint8Array): Promise<void> {
    const file: fs.File = fs.openSync(
      path,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC
    );
    try {
      const buf: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      fs.writeSync(file.fd, buf);
    } finally {
      try {
        fs.closeSync(file);
      } catch (closeErr) {
        const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'FsLogCatIo close failed: %{public}s', msg);
      }
    }
  }
}

export class SettingsAdvancedActions implements AdvancedActionsLike {
  private readonly onDumpLogcat: () => Promise<void>;
  private readonly onClearMemoryCache: () => Promise<void>;
  private readonly onOpenAppLanguage: () => void;
  private readonly onImportData: () => Promise<void>;
  private readonly onOpenWifiServer: () => void;
  private readonly onOpenWifiClient: () => void;

  constructor(
    onDumpLogcat: () => Promise<void>,
    onClearMemoryCache: () => Promise<void>,
    onOpenAppLanguage: () => void,
    onImportData: () => Promise<void>,
    onOpenWifiServer: () => void,
    onOpenWifiClient: () => void
  ) {
    this.onDumpLogcat = onDumpLogcat;
    this.onClearMemoryCache = onClearMemoryCache;
    this.onOpenAppLanguage = onOpenAppLanguage;
    this.onImportData = onImportData;
    this.onOpenWifiServer = onOpenWifiServer;
    this.onOpenWifiClient = onOpenWifiClient;
  }

  async dumpLogcat(): Promise<void> {
    await this.onDumpLogcat();
  }

  async clearMemoryCache(): Promise<void> {
    await this.onClearMemoryCache();
  }

  openAppLanguage(): void {
    this.onOpenAppLanguage();
  }

  async importData(): Promise<void> {
    await this.onImportData();
  }

  openWifiServer(): void {
    this.onOpenWifiServer();
  }

  openWifiClient(): void {
    this.onOpenWifiClient();
  }
}

export class AdvancedSettingsHelpers {
  static readonly READ_CACHE_SIZE_ENTRIES: string[] = ['40 MB', '80 MB', '160 MB', '320 MB', '640 MB'];
  static readonly READ_CACHE_SIZE_VALUES: string[] = ['40', '80', '160', '320', '640'];

  static readonly APP_LANGUAGE_LABEL_KEYS: string[] = [
    'app_language_system',
    'app_language_de',
    'app_language_en',
    'app_language_es',
    'app_language_fr',
    'app_language_ja',
    'app_language_ko',
    'app_language_th',
    'app_language_zh_cn',
    'app_language_zh_hk',
    'app_language_zh_tw'
  ];

  static readonly APP_LANGUAGE_VALUES: string[] = [
    'system',
    'de',
    'en',
    'es',
    'fr',
    'ja',
    'ko',
    'th',
    'zh-CN',
    'zh-HK',
    'zh-TW'
  ];

  static resolvePreferredLanguageTag(value: string): string {
    const clean: string = value.trim();
    switch (clean) {
      case '':
      case 'system':
      case 'default':
        return 'default';
      case 'de':
        return 'de-DE';
      case 'en':
        return 'en-US';
      case 'es':
        return 'es-ES';
      case 'fr':
        return 'fr-FR';
      case 'ja':
        return 'ja-JP';
      case 'ko':
        return 'ko-KR';
      case 'th':
        return 'th-TH';
      case 'zh-CN':
        return 'zh-Hans';
      case 'zh-HK':
        return 'zh-Hant-HK';
      case 'zh-TW':
        return 'zh-Hant-TW';
      default:
        return clean;
    }
  }

  static resolveRuntimeLanguageTag(value: string): string {
    const preferred: string = AdvancedSettingsHelpers.resolvePreferredLanguageTag(value);
    if (preferred === 'default') {
      try {
        const sysLang: string = i18n.System.getSystemLanguage();
        if (sysLang !== undefined && sysLang !== null && sysLang.trim().length > 0) {
          return sysLang.trim();
        }
      } catch (e) {
        hilog.warn(0x0000, 'SettingsSectionHelpers', 'getSystemLanguage failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
      return 'zh-Hans';
    }
    return preferred;
  }

  static applyAppLanguage(context: common.Context | null | undefined, value: string): boolean {
    const preferredTag: string = AdvancedSettingsHelpers.resolvePreferredLanguageTag(value);
    let applied: boolean = false;
    try {
      i18n.System.setAppPreferredLanguage(preferredTag);
      applied = true;
    } catch (e) {
      hilog.warn(0x0000, 'SettingsSectionHelpers', 'setAppPreferredLanguage(%{public}s) failed: %{public}s',
        preferredTag, e instanceof Error ? e.message : String(e));
    }
    if (context !== undefined && context !== null) {
      const runtimeTag: string = AdvancedSettingsHelpers.resolveRuntimeLanguageTag(value);
      try {
        context.getApplicationContext().setLanguage(runtimeTag);
        applied = true;
      } catch (e) {
        hilog.warn(0x0000, 'SettingsSectionHelpers', 'ApplicationContext.setLanguage(%{public}s) failed: %{public}s',
          runtimeTag, e instanceof Error ? e.message : String(e));
      }
    }
    return applied;
  }

  /**
   * Produces a non-sensitive diagnostic snapshot (never includes cookies or security patterns).
   */
  static buildDiagnosticSnapshot(nowMs?: number): string {
    const ts: number = nowMs !== undefined ? nowMs : Date.now();
    const lines: string[] = [
      '=== EhViewer HarmonyOS Diagnostic Log ===',
      `timestamp=${new Date(ts).toISOString()}`,
      `version=${PreferenceActions.getVersionName()}`,
      `gallerySite=${Settings.getGallerySite()}`,
      `theme=${Settings.getTheme()}`,
      `appLanguage=${Settings.getAppLanguage()}`,
      `readCacheSizeMB=${Settings.getReadCacheSize()}`,
      `multiThreadDownload=${Settings.getMultiThreadDownload()}`,
      `preloadImage=${Settings.getPreloadImage()}`,
      `imageResolution=${Settings.getImageResolution()}`,
      `downloadTimeout=${Settings.getDownloadTimeout()}`,
      `mediaScan=${Settings.getMediaScan()}`,
      `domainFronting=${Settings.getDF()}`,
      `dnsOverHttps=${Settings.getDoH()}`,
      `builtInHosts=${Settings.getBuiltInHosts()}`,
      `builtExHosts=${Settings.getBuiltEXHosts()}`,
      `saveParseErrorBody=${Settings.getSaveParseErrorBody()}`,
      `saveCrashLog=${Settings.getSaveCrashLog()}`,
      `readingRefreshRateHz=${Settings.getReadingRefreshRateHz()}`
    ];
    return lines.join('\n') + '\n';
  }

  static buildLogcatFilePath(logDir: string | null, nowMs?: number): string | null {
    if (logDir === null || logDir.length === 0) {
      return null;
    }
    const ts: number = nowMs !== undefined ? nowMs : Date.now();
    const fileName: string = `logcat-${ReadableTime.getFilenamableTime(ts)}.txt`;
    return Contracts.childOf(logDir, fileName);
  }

  static async dumpDiagnosticLogcat(
    logDirOverride?: string | null,
    ioOverride?: LogCatIo,
    nowMs?: number
  ): Promise<LogcatDumpResult> {
    const dir: string | null = logDirOverride !== undefined
      ? logDirOverride
      : AppConfig.getExternalLogcatDir();
    const path: string | null = AdvancedSettingsHelpers.buildLogcatFilePath(dir, nowMs);
    if (path === null) {
      return new LogcatDumpResult(false, '', 'settings_advanced_dump_logcat_failed');
    }
    const io: LogCatIo = ioOverride !== undefined ? ioOverride : new FsLogCatIo();
    const ok: boolean = await LogCat.save(path, io);
    return new LogcatDumpResult(
      ok,
      ok ? path : '',
      ok ? 'settings_advanced_dump_logcat_to' : 'settings_advanced_dump_logcat_failed'
    );
  }

  static listBackupFiles(dataDirOverride?: string | null): string[] | null {
    const dir: string | null = dataDirOverride !== undefined
      ? dataDirOverride
      : AppConfig.getExternalDataDir();
    if (dir === null || dir.length === 0) {
      return null;
    }
    try {
      if (!fs.accessSync(dir)) {
        return [];
      }
      const names: string[] = fs.listFileSync(dir);
      const files: string[] = [];
      for (let i = 0; i < names.length; i++) {
        const name: string = names[i];
        const full: string = Contracts.childOf(dir, name);
        try {
          if (fs.statSync(full).isFile()) {
            files.push(name);
          }
        } catch (stErr) {
          const msg: string = stErr instanceof Error ? stErr.message : String(stErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'stat backup entry %{public}s failed: %{public}s', full, msg);
        }
      }
      files.sort((a: string, b: string): number => a.localeCompare(b));
      return files;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'listBackupFiles failed for %{public}s: %{public}s', dir, msg);
      return [];
    }
  }

  static async runExportDatabase(
    exportFn: (path: string) => Promise<boolean>
  ): Promise<DbExportResult> {
    try {
      const outPath: string | null = await PreferenceActions.exportData(exportFn);
      if (outPath !== null && outPath.length > 0) {
        return new DbExportResult(true, outPath, 'settings_advanced_export_data_to');
      }
      return new DbExportResult(false, '', 'settings_advanced_export_data_failed');
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'runExportDatabase failed: %{public}s', msg);
      return new DbExportResult(false, '', 'settings_advanced_export_data_failed');
    }
  }

  static async runImportDatabase(
    fragment: AdvancedFragment,
    store: LoadingStatusStore,
    importTask: (onProgress: (percent: number) => void) => Promise<string | null>
  ): Promise<DbImportResult> {
    store.setStatus(AdvancedFragment.DB_LOADING);
    store.setProgress(0);
    try {
      const errorKey: string | null = await importTask((percent: number): void => {
        fragment.onDbSyncProgress(percent);
      });
      fragment.onDbSyncProgress(100);
      if (errorKey === null) {
        return new DbImportResult(true, null, 'settings_advanced_import_data_successfully');
      }
      return new DbImportResult(false, errorKey, errorKey);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'runImportDatabase failed: %{public}s', msg);
      fragment.onDbSyncProgress(100);
      return new DbImportResult(false, 'cant_read_the_file', 'cant_read_the_file');
    }
  }
}

// ── About Settings Helpers (D-003 Compliant) ────────────────────────────────

export class SettingsAboutActions implements AboutActionsLike {
  private readonly onAuthor: () => Promise<boolean>;
  private readonly onDonate: () => Promise<boolean>;

  constructor(onAuthor: () => Promise<boolean>, onDonate: () => Promise<boolean>) {
    this.onAuthor = onAuthor;
    this.onDonate = onDonate;
  }

  async openAuthorPage(): Promise<boolean> {
    return await this.onAuthor();
  }

  async openDonatePage(): Promise<boolean> {
    return await this.onDonate();
  }

  /**
   * Strictly obeys D-003: AppUpdater / self-update is permanently removed on HarmonyOS.
   */
  async checkForUpdates(): Promise<boolean> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'checkForUpdates disabled per D-003 (AppUpdater removed)');
    return false;
  }
}

export class AboutSettingsHelpers {
  static readonly URL_SOURCE: string = 'https://github.com/xiaojieonly/Ehviewer_CN_SXJ';
  static readonly URL_LATEST_RELEASE: string = 'https://github.com/xiaojieonly/Ehviewer_CN_SXJ/releases';
  static readonly URL_ISSUE_HELP: string =
    'https://github.com/xiaojieonly/Ehviewer_CN_SXJ/blob/BiLi_PC_Gamer/feedauthor/EhviewerIssue.md';

  static readonly KEY_DECLARATION: string = 'declaration';
  static readonly KEY_SOURCE: string = 'source';
  static readonly KEY_LATEST_RELEASE: string = 'latest_release';
  static readonly KEY_ISSUE_HELP: string = 'issue_help';
  static readonly KEY_LICENSE: string = 'license';
  static readonly KEY_VERSION: string = 'version';

  /**
   * Upstream `AboutFragment.java` obfuscated author summary replaces `$` with `@`.
   */
  static formatAuthorSummary(rawSummary: string): string {
    return rawSummary.replace('$', '@');
  }

  static resolveVersionSummary(unknownFallback: string, versionOverride?: string): string {
    const version: string = versionOverride !== undefined
      ? versionOverride
      : PreferenceActions.getVersionName();
    if (version.length === 0 || version === VersionPreference.FALLBACK) {
      return unknownFallback;
    }
    return version;
  }

  /**
   * Visible About group items strictly honoring D-003 (no `check_for_updates` / `close_auto_updates`).
   */
  static getVisibleAboutKeys(): string[] {
    return [
      AboutSettingsHelpers.KEY_DECLARATION,
      AboutFragment.KEY_AUTHOR,
      AboutSettingsHelpers.KEY_SOURCE,
      AboutSettingsHelpers.KEY_LATEST_RELEASE,
      AboutSettingsHelpers.KEY_ISSUE_HELP,
      AboutSettingsHelpers.KEY_LICENSE,
      AboutSettingsHelpers.KEY_VERSION,
      AboutFragment.KEY_DONATE
    ];
  }

  /**
   * Upstream Alipay account text (decoded from AboutFragment.java without hardcoding in UI render call).
   */
  static getDonateAlipayAccount(): string {
    return '1031082091' + String.fromCharCode(64) + 'qq.com';
  }
}

// ── License Page Helpers ────────────────────────────────────────────────────

export class LicensePageHelpers {
  static readonly BUNDLED_LIBRARIES: string[] = [
    'EhViewer',
    'libpng',
    'libjpeg-turbo',
    'libwebp',
    'giflib',
    '7-Zip LZMA SDK'
  ];

  static getAssetPath(): string {
    return LicenseActivity.ASSET_PATH;
  }

  static getRawfileUri(): string {
    return `$rawfile:${LicenseActivity.ASSET_PATH}`;
  }

  static isBundledLocalAsset(): boolean {
    return LicenseActivity.isLocalAsset(LicensePageHelpers.getRawfileUri());
  }
}
