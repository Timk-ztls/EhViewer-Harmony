/*
 * Phase B Track P2 unit tests:
 *  1. DirPickerActivity + SandboxDirectoryExplorer + DirPickerHelpers + Settings.putDownloadLocation
 *  2. LicenseActivity + open_source_licenses.html asset contract
 *  3. DownloadSettingsController (inverted .nomedia, timeout, image resolution, CSV export/import,
 *     clean invalid downloads, restore download items, clean redundancy)
 *  4. ReadSettingsRules + ReadSettingsHelpers (conditional refresh rate omission & option bounds)
 *  5. PrivacySettingsRules + PrivacySettingsHelpers (pattern summary, analytics start-only-on-true,
 *     secure screen persistence, HTML stripping)
 *  6. AdvancedFragment + AdvancedSettingsHelpers (logcat dump, memory cache clear, DB export/import
 *     state machine, backup file listing, action dispatch)
 *  7. AboutFragment + AboutSettingsHelpers (author/donate actions, version fallback, D-003 compliance)
 *
 * Run:
 *   pwsh -NoProfile -ExecutionPolicy Bypass -File harmony/entry/src/test/ui-scene/run.ps1 -Filter p2-settings-fragments
 */

import fs from '@ohos.file.fs';
import { Settings } from '../../main/ets/hippo/ehviewer/Settings';
import { AppConfig } from '../../main/ets/hippo/ehviewer/AppConfig';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { UniFile } from '../../main/ets/hippo/unifile/UniFile';
import { SceneArgs } from '../../main/ets/hippo/scene/SceneTypes';
import { DirPickerActivity } from '../../main/ets/hippo/ehviewer/ui/DirPickerActivity';
import { LicenseActivity } from '../../main/ets/hippo/ehviewer/ui/LicenseActivity';
import { DownloadFragment, NoMediaAction } from '../../main/ets/hippo/ehviewer/ui/fragment/DownloadFragment';
import { ReadSettingsRules } from '../../main/ets/hippo/ehviewer/ui/fragment/ReadSettingsRules';
import { PrivacySettingsRules, AnalyticsTogglePlan } from '../../main/ets/hippo/ehviewer/ui/fragment/PrivacySettingsRules';
import {
  AdvancedFragment,
  InMemoryLoadingStatusStore
} from '../../main/ets/hippo/ehviewer/ui/fragment/AdvancedFragment';
import { AboutFragment } from '../../main/ets/hippo/ehviewer/ui/fragment/AboutFragment';
import { RestoreItem, SpiderHeader } from '../../main/ets/hippo/ehviewer/preference/RestoreDownloadPreference';
import { VersionPreference } from '../../main/ets/hippo/ehviewer/preference/VersionPreference';
import { ReadingRefreshRate } from '../../main/ets/hippo/ehviewer/util/ReadingRefreshRate';
import {
  AboutSettingsHelpers,
  AdvancedSettingsHelpers,
  CleanInvalidResult,
  CleanRedundancyRunResult,
  DbExportResult,
  DbImportResult,
  DirPickerHelpers,
  DownloadExportResult,
  DownloadImportResult,
  DownloadSettingsController,
  FsLogCatIo,
  LicensePageHelpers,
  LogcatDumpResult,
  MediaScanApplyResult,
  PrivacySettingsHelpers,
  ReadSettingsHelpers,
  RestoreRunResult,
  SandboxDirectoryExplorer,
  SettingsAboutActions,
  SettingsAdvancedActions,
  SettingsTextFormatter,
  UniFileTextIo
} from '../../main/ets/hippo/ui/settings/SettingsSectionHelpers';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}\n    want true, got false`);
  }
}

function makeGallery(gid: number, title: string): GalleryInfo {
  const gi: GalleryInfo = new GalleryInfo();
  gi.gid = gid;
  gi.token = 'abcdef1234';
  gi.title = title;
  gi.titleJpn = 'jpn_title';
  gi.thumb = 'https://example.org/t.jpg';
  gi.category = 2;
  gi.posted = '2026-11-21 10:00';
  gi.uploader = 'tester';
  gi.rating = 4.5;
  gi.rated = false;
  gi.simpleLanguage = null;
  gi.simpleTags = [];
  gi.thumbWidth = 100;
  gi.thumbHeight = 140;
  gi.spanSize = 0;
  gi.spanIndex = 0;
  gi.spanGroupIndex = 0;
  gi.favoriteSlot = -2;
  gi.favoriteName = null;
  gi.pages = 12;
  return gi;
}

function ensureDir(dir: string): void {
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
}

function writeFile(path: string, content: string): void {
  const f: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(f.fd, content);
  } finally {
    fs.closeSync(f);
  }
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

// ── 1. DirPickerActivity + SandboxDirectoryExplorer + DirPickerHelpers ──────

async function testDirPicker(): Promise<void> {
  ensureDir('/tmp/p2/root/alpha');
  ensureDir('/tmp/p2/root/beta');
  writeFile('/tmp/p2/root/readme.txt', 'not a dir');

  let lastListedPath: string = '';
  let lastListedEntries: string[] = [];
  const explorer: SandboxDirectoryExplorer = new SandboxDirectoryExplorer(
    (p: string, entries: string[]): void => {
      lastListedPath = p;
      lastListedEntries = entries;
    }
  );
  const pickerAct: DirPickerActivity = new DirPickerActivity();
  pickerAct.setExplorer(explorer);

  const args: SceneArgs = new Map<string, Object>();
  args.set(DirPickerActivity.KEY_FILE_PATH, '/tmp/p2/root');
  pickerAct.init(args);
  await flushMicrotasks();

  eq('DirPicker init currentPath', pickerAct.getCurrentPath(), '/tmp/p2/root');
  eq('DirPicker lists only subdirectories sorted', pickerAct.getEntries(), [
    '/tmp/p2/root/alpha',
    '/tmp/p2/root/beta'
  ]);
  eq('Explorer callback notified with path & entries', lastListedPath, '/tmp/p2/root');
  eq('Explorer callback entry count', lastListedEntries.length, 2);

  // Enter subdirectory
  pickerAct.enter('/tmp/p2/root/alpha');
  await flushMicrotasks();
  eq('DirPicker enter updates currentPath', pickerAct.getCurrentPath(), '/tmp/p2/root/alpha');
  eq('DirPicker basenameOf extracts folder name', DirPickerHelpers.basenameOf('/tmp/p2/root/alpha'), 'alpha');

  // Go up
  ok('canGoUp true for nested path', DirPickerHelpers.canGoUp('/tmp/p2/root/alpha'));
  ok('canGoUp false for root', !DirPickerHelpers.canGoUp('/'));
  pickerAct.goUp();
  await flushMicrotasks();
  eq('DirPicker goUp returns to parent', pickerAct.getCurrentPath(), '/tmp/p2/root');

  // Confirm writable sandbox dir
  const confirmed: string | null = await pickerAct.confirm();
  eq('DirPicker confirm succeeds on writable directory', confirmed, '/tmp/p2/root');

  // Confirm non-existent dir fails
  pickerAct.enter('/tmp/p2/does-not-exist');
  await flushMicrotasks();
  const badConfirm: string | null = await pickerAct.confirm();
  eq('DirPicker confirm returns null on non-existent path', badConfirm, null);

  // Authorized DocumentViewPicker URI (D-038)
  const docUri: string = 'file://docs/storage/Users/currentUser/Download/EhViewer';
  explorer.markAuthorizedPickerUri(docUri);
  pickerAct.enter(docUri);
  await flushMicrotasks();
  ok('isAuthorizedDocumentUri recognizes file://docs/', DirPickerHelpers.isAuthorizedDocumentUri(docUri));
  ok('canGoUp false for document URI', !DirPickerHelpers.canGoUp(docUri));
  eq('confirm accepts authorized DocumentViewPicker URI', await pickerAct.confirm(), docUri);

  // Reset to default & persist via Settings.putDownloadLocation
  ensureDir('/tmp/p2/default_dl');
  pickerAct.resetToDefault('/tmp/p2/default_dl');
  await flushMicrotasks();
  const defConfirmed: string | null = await pickerAct.confirm();
  eq('resetToDefault confirm returns default dir', defConfirmed, '/tmp/p2/default_dl');
  const locFile: UniFile | null = DirPickerHelpers.resolveDownloadLocationUniFile(defConfirmed as string);
  ok('resolveDownloadLocationUniFile creates UniFile for raw path', locFile !== null);
  Settings.putDownloadLocation(locFile as UniFile);
  const storedLoc: UniFile | null = Settings.getDownloadLocation();
  ok('Settings.getDownloadLocation returns persisted path',
    storedLoc !== null && storedLoc.getUri().indexOf('/tmp/p2/default_dl') >= 0);

  // Resolve initial path precedence
  eq('resolveInitialPath prefers param',
    DirPickerHelpers.resolveInitialPath('/tmp/param/', storedLoc, '/tmp/fallback'), '/tmp/param');
  eq('resolveInitialPath falls back to default when location null',
    DirPickerHelpers.resolveInitialPath(null, null, '/tmp/fallback'), '/tmp/fallback');
}

// ── 2. LicenseActivity + open_source_licenses.html asset contract ───────────

function testLicenseContract(): void {
  eq('LicenseActivity.ASSET_PATH is open_source_licenses.html',
    LicenseActivity.ASSET_PATH, 'open_source_licenses.html');
  eq('LicensePageHelpers.getAssetPath matches LicenseActivity',
    LicensePageHelpers.getAssetPath(), LicenseActivity.ASSET_PATH);
  ok('LicensePageHelpers reports bundled local asset', LicensePageHelpers.isBundledLocalAsset());
  ok('LicenseActivity.isLocalAsset accepts $rawfile:',
    LicenseActivity.isLocalAsset('$rawfile:open_source_licenses.html'));
  ok('LicenseActivity.isLocalAsset accepts android_asset',
    LicenseActivity.isLocalAsset('file:///android_asset/open_source_licenses.html'));
  ok('LicenseActivity.isLocalAsset rejects remote URL',
    !LicenseActivity.isLocalAsset('https://example.org/licenses.html'));
  ok('Bundled OSS libraries include native codecs + 7z',
    LicensePageHelpers.BUNDLED_LIBRARIES.indexOf('libpng') >= 0
      && LicensePageHelpers.BUNDLED_LIBRARIES.indexOf('libjpeg-turbo') >= 0
      && LicensePageHelpers.BUNDLED_LIBRARIES.indexOf('libwebp') >= 0
      && LicensePageHelpers.BUNDLED_LIBRARIES.indexOf('giflib') >= 0
      && LicensePageHelpers.BUNDLED_LIBRARIES.indexOf('7-Zip LZMA SDK') >= 0);
}

// ── 3. DownloadSettingsController (media scan, timeout, CSV, clean, restore) ─

async function testDownloadSettings(): Promise<void> {
  const dlPath: string = '/tmp/p2/dl_ops';
  ensureDir(dlPath);
  const dlDir: UniFile = UniFile.fromFile(dlPath) as UniFile;

  // Inverted .nomedia semantics: false -> ENSURE (creates .nomedia)
  const disableScan: MediaScanApplyResult = DownloadSettingsController.applyMediaScanChange(false, dlDir);
  eq('media_scan=false plans ENSURE', disableScan.action, NoMediaAction.ENSURE);
  ok('media_scan=false applied', disableScan.applied);
  ok('media_scan=false creates .nomedia file on disk', fs.accessSync(`${dlPath}/.nomedia`));
  eq('Settings.getMediaScan() persisted false', Settings.getMediaScan(), false);

  // Inverted .nomedia semantics: true -> REMOVE (deletes .nomedia)
  const enableScan: MediaScanApplyResult = DownloadSettingsController.applyMediaScanChange(true, dlDir);
  eq('media_scan=true plans REMOVE', enableScan.action, NoMediaAction.REMOVE);
  ok('media_scan=true applied', enableScan.applied);
  ok('media_scan=true deletes .nomedia file from disk', !fs.accessSync(`${dlPath}/.nomedia`));
  eq('Settings.getMediaScan() persisted true', Settings.getMediaScan(), true);

  // Timeout & image resolution
  eq('applyDownloadTimeout parses valid seconds', DownloadSettingsController.applyDownloadTimeout('50'), 50);
  eq('Settings.getDownloadTimeout() persisted 50', Settings.getDownloadTimeout(), 50);
  eq('applyDownloadTimeout invalid string -> 0 (unlimited)',
    DownloadSettingsController.applyDownloadTimeout('bad'), 0);
  eq('applyImageResolution persists 1600', DownloadSettingsController.applyImageResolution('1600'), '1600');
  eq('Settings.getImageResolution() is 1600', Settings.getImageResolution(), '1600');
  Settings.putString(Settings.KEY_IMAGE_RESOLUTION, Settings.IMAGE_SIZE_980X);
  eq('Settings.getImageResolution migrates 980 -> 780', Settings.getImageResolution(), '780');

  // Download location summary
  eq('location summary returns URI when set',
    DownloadSettingsController.getDownloadLocationSummary((k: string) => k, dlDir), dlDir.getUri());
  eq('location summary returns invalid resource key when null',
    DownloadSettingsController.getDownloadLocationSummary((k: string) => `RES:${k}`, null),
    'RES:settings_download_invalid_download_location');

  // CSV Export
  const emptyExp: DownloadExportResult = DownloadSettingsController.exportDownloadItems([], dlDir);
  ok('export with 0 items fails gracefully', !emptyExp.ok);
  eq('export 0 items toast key', emptyExp.toast.resKey, 'settings_download_export_no_items');

  const g1: GalleryInfo = makeGallery(1001, 'Gallery One');
  const g2: GalleryInfo = makeGallery(1002, 'Gallery Two');
  const fixedDate: Date = new Date(2026, 10, 21, 9, 5, 3);
  const expRes: DownloadExportResult = DownloadSettingsController.exportDownloadItems([g1, g2], dlDir, fixedDate);
  ok('export succeeds with valid items', expRes.ok);
  ok('export filename matches yyyy-MM-dd-HH-mm-ss',
    expRes.fileUri.indexOf('ehviewer-download-2026-11-21-09-05-03.csv') >= 0);
  eq('export success toast key', expRes.toast.resKey, 'settings_download_export_succeed');

  // CSV Import (round-trip with deduplication of existing gid=1001)
  const exportedFile: UniFile = UniFile.fromUri(expRes.fileUri) as UniFile;
  const csvContent: string | null = UniFileTextIo.readUtf8(exportedFile);
  ok('exported CSV file readable', csvContent !== null && csvContent.length > 0);
  const addedGids: number[] = [];
  const impRes: DownloadImportResult = await DownloadSettingsController.importDownloadItemsFromContent(
    csvContent as string,
    (gid: number): boolean => gid === 1001,
    async (gi: GalleryInfo): Promise<void> => {
      addedGids.push(gi.gid);
    }
  );
  eq('import parses both items (including header-concat self-heal)', impRes.parsedCount, 2);
  eq('import skips existing gid 1001 and adds gid 1002', addedGids, [1002]);
  eq('import count = 1', impRes.importedCount, 1);
  eq('import toast key', impRes.toast.resKey, 'settings_download_import_succeed');

  // Clean invalid downloads
  const cleanRoot: string = '/tmp/p2/clean_test';
  ensureDir(`${cleanRoot}/empty_dir`);
  ensureDir(`${cleanRoot}/missing_info`);
  writeFile(`${cleanRoot}/missing_info/001.jpg`, 'img');
  ensureDir(`${cleanRoot}/mismatch_dir`);
  writeFile(`${cleanRoot}/mismatch_dir/.ehviewer`, '5001\na\nb\nc\nd\ne\nf\n3\nrest');
  writeFile(`${cleanRoot}/mismatch_dir/.nomedia`, '');
  writeFile(`${cleanRoot}/mismatch_dir/001.jpg`, 'img1');
  writeFile(`${cleanRoot}/mismatch_dir/002.jpg`, 'img2');
  ensureDir(`${cleanRoot}/valid_dir`);
  writeFile(`${cleanRoot}/valid_dir/.ehviewer`, '5002\na\nb\nc\nd\ne\nf\n2\nrest');
  writeFile(`${cleanRoot}/valid_dir/001.jpg`, 'img1');
  writeFile(`${cleanRoot}/valid_dir/002.jpg`, 'img2');

  const resetGids: number[] = [];
  const progressSteps: number[] = [];
  const cleanDirFile: UniFile = UniFile.fromFile(cleanRoot) as UniFile;
  const cleanRes: CleanInvalidResult = await DownloadSettingsController.cleanInvalidDownloads(
    cleanDirFile,
    async (gid: number): Promise<void> => {
      resetGids.push(gid);
    },
    new Date(2026, 10, 21, 9, 5, 3),
    (done: number, _total: number): void => {
      progressSteps.push(done);
    }
  );
  eq('clean detects 3 invalid dirs (empty, missing .ehviewer, mismatch)', cleanRes.invalidCount, 3);
  ok('empty_dir deleted', !fs.accessSync(`${cleanRoot}/empty_dir`));
  ok('missing_info dir preserved (not deleted)', fs.accessSync(`${cleanRoot}/missing_info`));
  ok('mismatch_dir non-dot images deleted', !fs.accessSync(`${cleanRoot}/mismatch_dir/001.jpg`)
    && !fs.accessSync(`${cleanRoot}/mismatch_dir/002.jpg`));
  ok('mismatch_dir preserves .ehviewer and .nomedia',
    fs.accessSync(`${cleanRoot}/mismatch_dir/.ehviewer`) && fs.accessSync(`${cleanRoot}/mismatch_dir/.nomedia`));
  ok('valid_dir untouched', fs.accessSync(`${cleanRoot}/valid_dir/001.jpg`)
    && fs.accessSync(`${cleanRoot}/valid_dir/002.jpg`));
  eq('mismatch_dir gid reset to STATE_NONE', resetGids, [5001]);
  ok('clean log file written with delfile-yyyyMMddHHmm.log',
    cleanRes.logFileUri !== null && cleanRes.logFileUri.indexOf('delfile-202611210905.log') >= 0);
  ok('clean progress reported monotonically', progressSteps.length >= 2 && progressSteps[0] === 0);

  // Restore download items + Clean redundancy
  const restoreRoot: string = '/tmp/p2/restore_test';
  ensureDir(`${restoreRoot}/7001-existing`);
  writeFile(`${restoreRoot}/7001-existing/.ehviewer`, 'hdr');
  ensureDir(`${restoreRoot}/7002-new`);
  writeFile(`${restoreRoot}/7002-new/.ehviewer`, 'hdr');
  const restoreDirFile: UniFile = UniFile.fromFile(restoreRoot) as UniFile;
  const restoredGids: number[] = [];
  const restoredDirnames: string[] = [];
  const restoreRes: RestoreRunResult = await DownloadSettingsController.runRestoreDownloads(
    (gid: number): boolean => gid === 7001,
    (file: UniFile): SpiderHeader | null => {
      const u: string = file.getUri();
      if (u.indexOf('7001') >= 0) {
        return new SpiderHeader(7001, 'tok1');
      }
      if (u.indexOf('7002') >= 0) {
        return new SpiderHeader(7002, 'tok2');
      }
      return null;
    },
    async (_items: RestoreItem[]): Promise<Map<number, string>> => {
      const m: Map<number, string> = new Map<number, string>();
      m.set(7002, 'Restored Gallery');
      return m;
    },
    (item: RestoreItem, _title: string): void => {
      restoredGids.push(item.gid);
    },
    async (_gid: number, dirname: string): Promise<void> => {
      restoredDirnames.push(dirname);
    },
    undefined,
    restoreDirFile
  );
  eq('restore finds 1 new item (skips existing 7001)', restoreRes.foundCount, 1);
  eq('restore restores 1 item', restoreRes.restoredCount, 1);
  eq('restored gids', restoredGids, [7002]);
  eq('restored dirnames', restoredDirnames, ['7002-new']);
  eq('restore success toast key', restoreRes.toastResKey, 'settings_download_restore_successfully');

  const redRes: CleanRedundancyRunResult = await DownloadSettingsController.runCleanRedundancy(
    (gid: number): boolean => gid === 7001,
    undefined,
    restoreDirFile
  );
  eq('clean redundancy removes 7002-new not in download list', redRes.result.count, 1);
  eq('clean redundancy toast key', redRes.toastResKey, 'settings_download_clean_redundancy_done');
}

// ── 4. ReadSettingsRules + ReadSettingsHelpers ──────────────────────────────

function testReadSettings(): void {
  eq('ReadSettingsRules.shouldShowReadingRefreshRate matches ReadingRefreshRate.isSupported()',
    ReadSettingsRules.shouldShowReadingRefreshRate(), ReadingRefreshRate.isSupported());

  const keysSupported: string[] = ReadSettingsHelpers.buildVisibleReadKeys(true);
  const keysUnsupported: string[] = ReadSettingsHelpers.buildVisibleReadKeys(false);
  ok('refresh rate included when supported',
    keysSupported.indexOf(ReadSettingsRules.KEY_READING_REFRESH_RATE) >= 0);
  ok('refresh rate COMPLETELY OMITTED (not disabled) when unsupported',
    keysUnsupported.indexOf(ReadSettingsRules.KEY_READING_REFRESH_RATE) < 0);
  eq('unsupported key list has exactly 1 fewer item',
    keysSupported.length - keysUnsupported.length, 1);
  eq('supported read key list has all 16 read_settings items', keysSupported.length, 16);

  eq('clampAutoTransferTime clamps low/high bounds',
    [ReadSettingsHelpers.clampAutoTransferTime(-3),
      ReadSettingsHelpers.clampAutoTransferTime(8),
      ReadSettingsHelpers.clampAutoTransferTime(99)],
    [0, 8, 15]);
  eq('clampScreenLightness clamps [0..200]',
    [ReadSettingsHelpers.clampScreenLightness(-10),
      ReadSettingsHelpers.clampScreenLightness(120),
      ReadSettingsHelpers.clampScreenLightness(300)],
    [0, 120, 200]);

  eq('sanitizeRefreshRateValue allows 60/90/120/-1/0 and falls back invalid to 0',
    [ReadSettingsHelpers.sanitizeRefreshRateValue('120'),
      ReadSettingsHelpers.sanitizeRefreshRateValue('-1'),
      ReadSettingsHelpers.sanitizeRefreshRateValue('75'),
      ReadSettingsHelpers.sanitizeRefreshRateValue('bad')],
    [120, -1, 0, 0]);

  // Verify Settings persistence for newly surfaced read settings
  Settings.putScreenRotation(2);
  Settings.putReadingRefreshRateHz(90);
  Settings.putStartPosition(4);
  Settings.putStartTransferTime(7);
  Settings.putShowPageInterval(false);
  Settings.putVolumePage(true);
  Settings.putReverseVolumePage(true);
  Settings.putReadingFullscreen(false);
  Settings.putCustomScreenLightness(true);
  Settings.putScreenLightness(140);
  eq('Read settings persisted in Settings',
    [
      Settings.getScreenRotation(),
      Settings.getReadingRefreshRateHz(),
      Settings.getStartPosition(),
      Settings.getStartTransferTime(),
      Settings.getShowPageInterval(),
      Settings.getVolumePage(),
      Settings.getReverseVolumePage(),
      Settings.getReadingFullscreen(),
      Settings.getCustomScreenLightness(),
      Settings.getScreenLightness()
    ],
    [2, 90, 4, 7, false, true, true, false, true, 140]);
}

// ── 5. PrivacySettingsRules + PrivacySettingsHelpers ────────────────────────

function testPrivacySettings(): void {
  eq('empty pattern -> not_set resource key',
    PrivacySettingsHelpers.patternProtectionSummaryRes(''),
    PrivacySettingsRules.RES_PATTERN_NOT_SET);
  eq('null pattern -> not_set resource key',
    PrivacySettingsHelpers.patternProtectionSummaryRes(null),
    PrivacySettingsRules.RES_PATTERN_NOT_SET);
  eq('non-empty pattern -> set resource key',
    PrivacySettingsHelpers.patternProtectionSummaryRes('0123'),
    PrivacySettingsRules.RES_PATTERN_SET);

  let startCalls: number = 0;
  const planTrue: AnalyticsTogglePlan = PrivacySettingsHelpers.applyAnalyticsToggle(true, (): void => {
    startCalls++;
  });
  eq('toggle analytics true accepts & triggers start', [planTrue.accept, planTrue.shouldStartAnalytics], [true, true]);
  eq('Analytics.start invoked once on true', startCalls, 1);
  eq('Settings.getEnableAnalytics() is true', Settings.getEnableAnalytics(), true);

  const planFalse: AnalyticsTogglePlan = PrivacySettingsHelpers.applyAnalyticsToggle(false, (): void => {
    startCalls++;
  });
  eq('toggle analytics false accepts & does NOT trigger start',
    [planFalse.accept, planFalse.shouldStartAnalytics], [true, false]);
  eq('Analytics.start NOT invoked on false (still 1)', startCalls, 1);
  eq('Settings.getEnableAnalytics() is false', Settings.getEnableAnalytics(), false);

  // Secure screen writes KEY_SEC_SECURITY without clobbering KEY_READING_FULLSCREEN
  Settings.putReadingFullscreen(true);
  PrivacySettingsHelpers.applySecureScreenToggle(true);
  eq('KEY_SEC_SECURITY updated to true', Settings.getEnabledSecurity(), true);
  eq('KEY_READING_FULLSCREEN untouched', Settings.getReadingFullscreen(), true);
  PrivacySettingsHelpers.applySecureScreenToggle(false);
  eq('KEY_SEC_SECURITY reverted to false', Settings.getEnabledSecurity(), false);
  eq('KEY_READING_FULLSCREEN still untouched', Settings.getReadingFullscreen(), true);

  // Privacy cache serialization & reader exit preservation
  eq('encodePrivacyCache(true)', PrivacySettingsRules.encodePrivacyCache(true), '1');
  eq('encodePrivacyCache(false)', PrivacySettingsRules.encodePrivacyCache(false), '0');
  eq('decodePrivacyCache("1", false)', PrivacySettingsRules.decodePrivacyCache('1', false), true);
  eq('decodePrivacyCache("0\\n", true)', PrivacySettingsRules.decodePrivacyCache('0\n', true), false);
  eq('decodePrivacyCache("", true)', PrivacySettingsRules.decodePrivacyCache('', true), true);
  eq('decodePrivacyCache(null, false)', PrivacySettingsRules.decodePrivacyCache(null, false), false);
  eq('decodePrivacyCache("garbage", true)', PrivacySettingsRules.decodePrivacyCache('garbage', true), true);
  eq('reader enter keeps enabledSecurity=true', PrivacySettingsRules.resolveReaderPrivacyMode(true, true), true);
  eq('reader exit preserves enabledSecurity=true (no false reset)',
    PrivacySettingsRules.resolveReaderPrivacyMode(true, false), true);
  eq('reader exit keeps enabledSecurity=false', PrivacySettingsRules.resolveReaderPrivacyMode(false, false), false);

  eq('stripBasicHtml formats <br> and removes anchors',
    SettingsTextFormatter.stripBasicHtml('Line1<br><a href="https://a">Link</a>'),
    'Line1\nLink');
}

// ── 6. AdvancedFragment + AdvancedSettingsHelpers ───────────────────────────

async function testAdvancedSettings(): Promise<void> {
  const logDir: string = '/tmp/p2/logcat';
  ensureDir(logDir);
  const dumpRes: LogcatDumpResult = await AdvancedSettingsHelpers.dumpDiagnosticLogcat(
    logDir,
    new FsLogCatIo(),
    Date.UTC(2026, 10, 21, 8, 0, 0)
  );
  ok('dumpDiagnosticLogcat writes log file', dumpRes.ok);
  eq('dumpDiagnosticLogcat success toast key', dumpRes.toastResKey, 'settings_advanced_dump_logcat_to');
  ok('logcat file exists on disk', fs.accessSync(dumpRes.filePath));
  const dumpedText: string = fs.readTextSync(dumpRes.filePath);
  ok('diagnostic snapshot includes non-sensitive settings header',
    dumpedText.indexOf('EhViewer HarmonyOS Diagnostic Log') >= 0
      && dumpedText.indexOf('readCacheSizeMB=') >= 0);
  ok('diagnostic snapshot never leaks security pattern or cookies',
    dumpedText.indexOf('ipb_pass_hash') < 0 && dumpedText.indexOf('security=') < 0);

  // Backup file listing sorted
  const dataDir: string = '/tmp/p2/db_backups';
  ensureDir(dataDir);
  writeFile(`${dataDir}/2026-11-21.db`, 'db2');
  writeFile(`${dataDir}/2026-11-01.db`, 'db1');
  eq('listBackupFiles returns sorted filenames',
    AdvancedSettingsHelpers.listBackupFiles(dataDir),
    ['2026-11-01.db', '2026-11-21.db']);

  // Export DB via PreferenceActions.exportData (AppConfig initialized)
  AppConfig.initialize({ filesDir: '/tmp/p2/app_files', cacheDir: '/tmp/p2/app_cache' });
  let exportedPathCapture: string = '';
  const dbExpOk: DbExportResult = await AdvancedSettingsHelpers.runExportDatabase(
    async (path: string): Promise<boolean> => {
      exportedPathCapture = path;
      return true;
    }
  );
  ok('runExportDatabase succeeds and returns .db path', dbExpOk.ok && dbExpOk.filePath.endsWith('.db'));
  eq('export callback received same path', exportedPathCapture, dbExpOk.filePath);
  eq('export success toast key', dbExpOk.toastResKey, 'settings_advanced_export_data_to');

  const dbExpFail: DbExportResult = await AdvancedSettingsHelpers.runExportDatabase(
    async (_path: string): Promise<boolean> => false
  );
  ok('runExportDatabase reports failure cleanly', !dbExpFail.ok);
  eq('export fail toast key', dbExpFail.toastResKey, 'settings_advanced_export_data_failed');

  // AdvancedFragment action dispatch & DB import loading state machine
  const store: InMemoryLoadingStatusStore = new InMemoryLoadingStatusStore();
  const calls: string[] = [];
  const actions: SettingsAdvancedActions = new SettingsAdvancedActions(
    async (): Promise<void> => { calls.push('dump'); },
    async (): Promise<void> => { calls.push('clearMem'); },
    (): void => { calls.push('lang'); },
    async (): Promise<void> => { calls.push('import'); },
    (): void => { calls.push('wifiServer'); },
    (): void => { calls.push('wifiClient'); }
  );
  const frag: AdvancedFragment = new AdvancedFragment(store, actions);
  frag.onPreferenceClick(AdvancedFragment.KEY_DUMP_LOGCAT);
  frag.onPreferenceClick(AdvancedFragment.KEY_CLEAR_MEMORY_CACHE);
  frag.onPreferenceClick(AdvancedFragment.KEY_APP_LANGUAGE);
  frag.onPreferenceClick(AdvancedFragment.KEY_IMPORT_DATA);
  frag.onPreferenceClick(AdvancedFragment.KEY_WIFI_SERVER);
  frag.onPreferenceClick(AdvancedFragment.KEY_WIFI_CLIENT);
  await flushMicrotasks();
  eq('AdvancedFragment dispatches all 6 actions', calls,
    ['dump', 'clearMem', 'lang', 'import', 'wifiServer', 'wifiClient']);

  const progressLog: number[] = [];
  let loadingDuringImport: boolean = false;
  const impOk: DbImportResult = await AdvancedSettingsHelpers.runImportDatabase(
    frag,
    store,
    async (onProgress: (p: number) => void): Promise<string | null> => {
      loadingDuringImport = frag.isDbLoading();
      onProgress(10);
      progressLog.push(frag.getDbProgress());
      onProgress(50);
      progressLog.push(frag.getDbProgress());
      onProgress(90);
      progressLog.push(frag.getDbProgress());
      return null;
    }
  );
  ok('AdvancedFragment enters DB_LOADING during import', loadingDuringImport);
  eq('AdvancedFragment tracks 10/50/90 progress', progressLog, [10, 50, 90]);
  ok('AdvancedFragment exits DB_LOADING when import completes', !frag.isDbLoading() && frag.getDbProgress() === 100);
  ok('DB import success result', impOk.ok && impOk.toastResKey === 'settings_advanced_import_data_successfully');

  const impErr: DbImportResult = await AdvancedSettingsHelpers.runImportDatabase(
    frag,
    store,
    async (_onProgress: (p: number) => void): Promise<string | null> => 'cant_read_the_file'
  );
  ok('DB import error finishes loading state & reports error key',
    !impErr.ok && !frag.isDbLoading() && impErr.toastResKey === 'cant_read_the_file');
}

// ── 7. AboutFragment + AboutSettingsHelpers (D-003 compliance) ──────────────

async function testAboutSettings(): Promise<void> {
  eq('formatAuthorSummary replaces $ with @',
    AboutSettingsHelpers.formatAuthorSummary('SXJ_LonelyDog <xiaojieonly$foxmail.com>'),
    'SXJ_LonelyDog <xiaojieonly@foxmail.com>');
  eq('resolveVersionSummary replaces unknown fallback with localized string',
    AboutSettingsHelpers.resolveVersionSummary('Unknown', VersionPreference.FALLBACK),
    'Unknown');
  eq('resolveVersionSummary preserves real version string',
    AboutSettingsHelpers.resolveVersionSummary('Unknown', '2.0.2.6'),
    '2.0.2.6');

  // D-003 compliance: NO update checker in visible keys
  const visibleKeys: string[] = AboutSettingsHelpers.getVisibleAboutKeys();
  ok('About visible keys omit check_for_updates (D-003)',
    visibleKeys.indexOf(AboutFragment.KEY_CHECK_FOR_UPDATES) < 0);
  ok('About visible keys omit close_auto_updates (D-003)',
    visibleKeys.indexOf(Settings.KEY_CLOSE_AUTO_UPDATES) < 0);
  ok('About visible keys include declaration, author, source, license, version, donate',
    visibleKeys.indexOf(AboutSettingsHelpers.KEY_DECLARATION) >= 0
      && visibleKeys.indexOf(AboutFragment.KEY_AUTHOR) >= 0
      && visibleKeys.indexOf(AboutSettingsHelpers.KEY_SOURCE) >= 0
      && visibleKeys.indexOf(AboutSettingsHelpers.KEY_LICENSE) >= 0
      && visibleKeys.indexOf(AboutSettingsHelpers.KEY_VERSION) >= 0
      && visibleKeys.indexOf(AboutFragment.KEY_DONATE) >= 0);

  const triggered: string[] = [];
  const actions: SettingsAboutActions = new SettingsAboutActions(
    async (): Promise<boolean> => {
      triggered.push('author');
      return true;
    },
    async (): Promise<boolean> => {
      triggered.push('donate');
      return true;
    }
  );
  const aboutFrag: AboutFragment = new AboutFragment(actions);
  aboutFrag.onPreferenceClick(AboutFragment.KEY_AUTHOR);
  aboutFrag.onPreferenceClick(AboutFragment.KEY_DONATE);
  const updateResult: boolean = await actions.checkForUpdates();
  await flushMicrotasks();

  eq('AboutFragment dispatches author and donate actions', triggered, ['author', 'donate']);
  eq('SettingsAboutActions.checkForUpdates strictly returns false (D-003)', updateResult, false);

  // SettingsTextFormatter positional & printf args
  eq('SettingsTextFormatter formats %s and %d',
    SettingsTextFormatter.format('Saved %d items to %s', [5, '/tmp/a.csv']),
    'Saved 5 items to /tmp/a.csv');
}

async function main(): Promise<void> {
  await testDirPicker();
  testLicenseContract();
  await testDownloadSettings();
  testReadSettings();
  testPrivacySettings();
  await testAdvancedSettings();
  await testAboutSettings();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} failed / ${pass + fails.length} assertions`);
    for (let i = 0; i < fails.length; i++) {
      console.error('  - ' + fails[i]);
    }
    throw new Error('p2-settings-fragments test failed');
  }
  console.log(`✓ p2-settings-fragments: ${pass} assertions passed`);
}

main().catch((err: Object): void => {
  console.error(err);
  throw err;
});
