/*
 * download-sync 接手批单测：DownloadFragment（S0203，582 行）的纯逻辑
 *
 * 钉住六条"写错也会通过编译、甚至看起来合理"的语义：
 *   1. media_scan 的布尔**语义是反的**：true → 删 .nomedia（允许扫描）/ false → 建 .nomedia
 *   2. toTimeoutTime 解析失败 → 0（0 = 不限时），不是抛错、不是 -1
 *   3. 导出文件名用 Locale.US 的 yyyy-MM-dd-HH-mm-ss（补零 + 24 小时制）
 *   4. 导入跳过表头行，且只导入 DownloadManager 里没有的 gid
 *   5. 清理任务四种结局（空目录删目录 / 缺 .ehviewer / 行数不足 / 文件数不符删文件）
 *   6. 清理日志文件名是 yyyyMMddHHmm（**与导出的格式不同**）
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  DownloadFragment, DownloadSettingAction, DownloadSettingKey, NoMediaAction, SettingsWrite,
  UiIntent, CleanLog, CleanDirDecision, ImportPlan
} from '../../main/ets/hippo/ehviewer/ui/fragment/DownloadFragment';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
/*
 * 不 import `download/DownloadManager`：它会把 EhDB→RDB→@ohos.data.relationalStore 整条依赖拉进
 * 本测试的模块图，宿主环境（Node + shim）加载失败。
 * 两个常量改为**被测代码自身产出**与**磁盘上的字面值**：
 *   - 表头 = `DownloadFragment.buildExportContent([])`（它就是 DOWNLOAD_INFO_HEADER）
 *   - `.ehviewer` 文件名 = 字面量（这是磁盘契约，本来就该独立断言，用常量自证是同义反复）
 */
const DOWNLOAD_INFO_FILENAME: string = '.ehviewer';
const DOWNLOAD_INFO_HEADER: string = DownloadFragment.buildExportContent([]);

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
    fails.push(`${name}  (want true)`);
  }
}

/**
 * 造一个能 `toCSV()` → `fromCSV()` **完整往返**的 GalleryInfo。
 *
 * `fromCSV` 要求 ≥20 个字段且数字字段可解析（`galleryInfoFromCsv` 的实现），
 * 只填 gid/title 的实例会解析出 null —— 上一轮就是这样导致 `parsed[0].gid` 抛
 * `Cannot read properties of undefined`（"跨对象键不匹配"的又一次实例）。
 */
function fullInfo(gid: number, title: string): GalleryInfo {
  const gi: GalleryInfo = new GalleryInfo();
  gi.gid = gid;
  gi.token = 'tok';
  gi.title = title;
  gi.titleJpn = 'jpn';
  gi.thumb = 'thumb';
  gi.category = 1;
  gi.posted = '2026-01-01 00:00';
  gi.uploader = 'up';
  gi.rating = 4.5;
  gi.rated = false;
  gi.simpleLanguage = null;
  gi.simpleTags = [];
  gi.thumbWidth = 100;
  gi.thumbHeight = 200;
  gi.spanSize = 0;
  gi.spanIndex = 0;
  gi.spanGroupIndex = 0;
  gi.favoriteSlot = -2;
  gi.favoriteName = null;
  gi.pages = 10;
  return gi;
}

// ---------------------------------------------------------------- 键与点击意图

function testKeysAndClicks(): void {
  eq('download_location → PICK_DIRECTORY',
    DownloadFragment.planClick('download_location'), DownloadSettingAction.PICK_DIRECTORY);
  eq('export_download_items → EXPORT_CSV',
    DownloadFragment.planClick('export_download_items'), DownloadSettingAction.EXPORT_CSV);
  eq('import_download_items → PICK_IMPORT_FILE',
    DownloadFragment.planClick('import_download_items'), DownloadSettingAction.PICK_IMPORT_FILE);
  eq('clean_invalid_download → CONFIRM_CLEAN_INVALID',
    DownloadFragment.planClick('clean_invalid_download'), DownloadSettingAction.CONFIRM_CLEAN_INVALID);
  eq('未知 key → NONE', DownloadFragment.planClick('whatever'), DownloadSettingAction.NONE);

  eq('keyOf 未知 → OTHER', DownloadFragment.keyOf('x'), DownloadSettingKey.OTHER);

  // key 字面值必须与上游 Settings 一致（image_resolution 的**字面值是 image_size**）
  eq('KEY_MEDIA_SCAN 字面值', DownloadFragment.KEY_MEDIA_SCAN, 'media_scan');
  eq('KEY_IMAGE_RESOLUTION 字面值是 image_size（不是 image_resolution）',
    DownloadFragment.KEY_IMAGE_RESOLUTION, 'image_size');
  eq('KEY_DOWNLOAD_TIMEOUT 字面值', DownloadFragment.KEY_DOWNLOAD_TIMEOUT, 'download_timeout');
}

// ---------------------------------------------------------------- 摘要

function testSummaries(): void {
  const withDir: UiIntent = DownloadFragment.downloadLocationSummary('file:///storage/emulated/0/Eh');
  eq('有目录 → 摘要文本就是 uri', withDir.resKey, 'file:///storage/emulated/0/Eh');
  const noDir: UiIntent = DownloadFragment.downloadLocationSummary(null);
  eq('无目录 → 位置无效文案', noDir.resKey, 'settings_download_invalid_download_location');
  eq('空串也算无目录', DownloadFragment.downloadLocationSummary('').resKey,
    'settings_download_invalid_download_location');

  const m: Map<string, UiIntent> = DownloadFragment.initSummaries(true, '1600', 0, false);
  eq('多线程摘要带布尔串', (m.get('download_thread') as UiIntent).args, ['true']);
  eq('分辨率摘要', (m.get('image_size') as UiIntent).args, ['1600']);
  // timeout=0 → "不限时"资源名（不是字符串 "0"）
  eq('超时 0 → 不限时文案', (m.get('download_timeout') as UiIntent).args, ['download_timeout_unlimited']);
  eq('预加载摘要', (m.get('preload_image') as UiIntent).args, ['false']);

  const m2: Map<string, UiIntent> = DownloadFragment.initSummaries(false, '1280', 30, true);
  eq('超时 30 → 数字串', (m2.get('download_timeout') as UiIntent).args, ['30']);
}

// ---------------------------------------------------------------- 媒体扫描（语义反向）

function testMediaScan(): void {
  // 关键：true = 允许扫描 = **删** .nomedia
  eq('新值 true → REMOVE .nomedia（允许媒体扫描）',
    DownloadFragment.planMediaScanChange(true), NoMediaAction.REMOVE);
  eq('新值 false → ENSURE .nomedia（禁止媒体扫描）',
    DownloadFragment.planMediaScanChange(false), NoMediaAction.ENSURE);
  eq('非布尔 → NONE', DownloadFragment.planMediaScanChange('true'), NoMediaAction.NONE);
  eq('null → NONE', DownloadFragment.planMediaScanChange(null), NoMediaAction.NONE);
}

// ---------------------------------------------------------------- 超时解析

function testTimeout(): void {
  eq('"30" → 30', DownloadFragment.toTimeoutTime('30'), 30);
  eq('"0" → 0', DownloadFragment.toTimeoutTime('0'), 0);
  eq('"" → 0（不限时）', DownloadFragment.toTimeoutTime(''), 0);
  eq('"abc" → 0（不是抛错、不是 -1）', DownloadFragment.toTimeoutTime('abc'), 0);
  eq('null → 0', DownloadFragment.toTimeoutTime(null), 0);
  eq('" 15 " → 15（前后空格）', DownloadFragment.toTimeoutTime(' 15 '), 15);
  eq('"-5" → -5（上游 parseInt 允许负数，不做业务校验）',
    DownloadFragment.toTimeoutTime('-5'), -5);
}

// ---------------------------------------------------------------- 设置写入计划

function testSettingsWrite(): void {
  const scan: Map<string, Object> = DownloadFragment.planSettingsWrite('media_scan', false);
  eq('media_scan=false → noMedia=ENSURE', scan.get('noMedia'), NoMediaAction.ENSURE);

  const res: Map<string, Object> = DownloadFragment.planSettingsWrite('image_size', '2048');
  eq('image_size → 写分辨率', res.get('write'), SettingsWrite.PUT_IMAGE_RESOLUTION);
  eq('image_size 值', res.get('value'), '2048');

  const to: Map<string, Object> = DownloadFragment.planSettingsWrite('download_timeout', '45');
  eq('timeout → 写超时', to.get('write'), SettingsWrite.SET_DOWNLOAD_TIMEOUT);
  eq('timeout 值转数字', to.get('value'), 45);

  eq('非字符串新值 → 不写分辨率',
    DownloadFragment.planSettingsWrite('image_size', true).size, 0);
  eq('未知 key → 空计划', DownloadFragment.planSettingsWrite('x', 'y').size, 0);
}

// ---------------------------------------------------------------- 文件名格式

function testFileNames(): void {
  const d: Date = new Date(2026, 0, 5, 7, 8, 9);   // 2026-01-05 07:08:09 本地时间
  eq('导出文件名（补零 + 24 小时制）',
    DownloadFragment.exportFileName(d), 'ehviewer-download-2026-01-05-07-08-09.csv');

  const d2: Date = new Date(2026, 11, 31, 23, 59, 59);
  eq('年尾 23:59:59 不越界', DownloadFragment.exportFileName(d2),
    'ehviewer-download-2026-12-31-23-59-59.csv');

  // 清理日志：无分隔符、只到分钟（与导出格式**不同**）
  const d3: Date = new Date(2026, 0, 5, 7, 8, 9);
  eq('清理日志文件名（yyyyMMddHHmm）',
    DownloadFragment.cleanLogFileName(d3), 'delfile-202601050708.log');
}

// ---------------------------------------------------------------- 导出

function testExport(): void {
  eq('无条目 → 提示导出无内容',
    (DownloadFragment.planExport(0, 'file:///d') as UiIntent).resKey, 'settings_download_export_no_items');
  eq('无下载目录 → 提示位置无效',
    (DownloadFragment.planExport(3, null) as UiIntent).resKey,
    'settings_download_invalid_download_location');
  eq('正常 → 无提示', DownloadFragment.planExport(3, 'file:///d'), null);

  eq('成功提示带 uri',
    DownloadFragment.exportResultToast(true, 'file:///d/x.csv').args, ['file:///d/x.csv']);
  eq('失败提示', DownloadFragment.exportResultToast(false, '').resKey,
    'settings_download_export_failed');

  // 内容：表头 + 每条 toCSV()（toCSV 自带换行，不能再补）
  const a: GalleryInfo = fullInfo(111, 'A');
  const content: string = DownloadFragment.buildExportContent([a]);
  ok('内容以表头开头', content.startsWith(DOWNLOAD_INFO_HEADER));
  ok('表头后紧跟条目', content.length > DOWNLOAD_INFO_HEADER.length);
  eq('空列表 → 只有表头', DownloadFragment.buildExportContent([]), DOWNLOAD_INFO_HEADER);
}

// ---------------------------------------------------------------- 导入

function testImport(): void {
  const a: GalleryInfo = fullInfo(1, 'A');
  const b: GalleryInfo = fullInfo(2, 'B');

  // ============================================================
  // **上游 bug（1:1 保留）**：`DOWNLOAD_INFO_HEADER` 末尾**没有**换行，而 `GalleryInfo.toCSV()`
  // 每条**以换行结尾** —— 于是导出文件的第一行是「表头 + 第一条记录」拼在一起：
  //
  //   gid,token,...,pages1,token,...,pages\n      ← 表头与第一条粘在同一行
  //   2,token,...,pages\n
  //
  // 导入侧 `line.startsWith(DOWNLOAD_INFO_HEADER)` 会把这一整行跳过 → **第一条记录丢失**。
  // 也就是说 Android 端"导出 → 导入"一次就少一个条目。
  // 我们按 1:1 保留这个行为（改它就是改上游语义），但在这里用断言把它**钉成已知事实**，
  // 免得将来有人"顺手修好"却不知道自己在修什么。
  // ============================================================
  const content: string = DOWNLOAD_INFO_HEADER + a.toCSV() + b.toCSV();
  const parsed: GalleryInfo[] = DownloadFragment.parseImportCsv(content);
  // **导入侧自愈后**：粘连行被切开，两条都在。
  // （未自愈时这里只会有 1 条 —— 见本文件底部的 `testNoSelfHealBaseline` 反证。）
  eq('自愈后：粘连行被切开 → 2 条都在', parsed.length, 2);
  eq('自愈后顺序保持', [parsed[0].gid, parsed[1].gid], [1, 2]);

  // 反证：如果表头**带**换行（即修掉那个 bug），两条都能解析 →
  // 说明"丢一条"确实来自表头缺换行，而不是 fromCSV 解析能力问题。
  const fixedContent: string = DOWNLOAD_INFO_HEADER + '\n' + a.toCSV() + b.toCSV();
  const parsedFixed: GalleryInfo[] = DownloadFragment.parseImportCsv(fixedContent);
  eq('表头带换行（假想的修法）→ 两条都在', parsedFixed.length, 2);
  eq('按顺序：gid 1、2', [parsedFixed[0].gid, parsedFixed[1].gid], [1, 2]);

  // 只有表头 → 0 条
  eq('只有表头（长度等于表头）→ 不触发自愈、0 条',
    DownloadFragment.parseImportCsv(DOWNLOAD_INFO_HEADER).length, 0);
  // 空行跳过
  eq('空行跳过', DownloadFragment.parseImportCsv(DOWNLOAD_INFO_HEADER + '\n\n').length, 0);

  // 去重（用"表头带换行"的完整输入，避开上面那个上游 bug 的干扰）：
  // gid=1 已存在 → 只导入 gid=2
  const plan: ImportPlan = DownloadFragment.planImport(parsedFixed, (gid: number): boolean => gid === 1);
  eq('已存在的 gid 不重复导入', plan.toAdd.length, 1);
  eq('导入的是 gid=2', (plan.toAdd[0] as GalleryInfo).gid, 2);
  eq('解析总数仍记为 2', plan.parsedCount, 2);

  eq('全部已存在 → 0 条', DownloadFragment.planImport(parsedFixed,
    (_gid: number): boolean => true).toAdd.length, 0);

  eq('导入成功提示带计数', DownloadFragment.importResultToast(3).args, [3]);
  eq('导入 0 条 → 失败提示', DownloadFragment.importResultToast(0).resKey,
    'settings_download_import_failed');
}

// ---------------------------------------------------------------- 清理决策

function infoContentOf(gid: number, pages: number): string {
  // 上游 .ehviewer：第 0 行 gid、第 7 行页数；凑够 8 行以上
  const lines: string[] = [`${gid}`, 'x', 'x', 'x', 'x', 'x', 'x', `${pages}`, 'extra'];
  return lines.join('\n');
}

function testCleanDecisions(): void {
  // ① 非目录 → 跳过
  const notDir: CleanDirDecision = DownloadFragment.planCleanDir('f.txt', false, [], null);
  eq('非目录 → 不计入', notDir.invalid, false);
  eq('非目录 → 无日志', notDir.log, '');

  // ② 空目录 → 删目录
  const empty: CleanDirDecision = DownloadFragment.planCleanDir('123', true, [], '');
  eq('空目录 → invalid', empty.invalid, true);
  eq('空目录 → 删整个目录', empty.deleteDir, true);
  eq('空目录日志逐字', empty.log, 'Empty directory: 123');

  // ③ 缺 .ehviewer
  const noInfo: CleanDirDecision = DownloadFragment.planCleanDir('456', true, ['001.jpg'], null);
  eq('缺 .ehviewer → invalid', noInfo.invalid, true);
  eq('缺 .ehviewer **不删目录**', noInfo.deleteDir, false);
  eq('缺 .ehviewer 日志', noInfo.log, 'Missing .ehviewer file: 456');

  // ④ .ehviewer 行数不足 → 尝试用第一行 gid 重置
  const shortInfo: CleanDirDecision = DownloadFragment.planCleanDir('789', true, ['001.jpg'], '789\n1\n2');
  eq('行数不足 → invalid', shortInfo.invalid, true);
  eq('行数不足 → 用第一行当 gid 重置', shortInfo.resetGid, 789);
  eq('行数不足日志', shortInfo.log, 'Invalid .ehviewer file: 789');

  // ④b 行数不足且第一行不是数字 → gid=-1（不重置）
  eq('gid 解析失败 → -1', DownloadFragment.planCleanDir('789', true, ['a'], 'abc\nx').resetGid, -1);

  // ⑤ 文件数不符 → 删非点开头文件（保留 .ehviewer），并重置
  const files: string[] = ['001.jpg', '002.jpg', DOWNLOAD_INFO_FILENAME, '.nomedia'];
  const mismatch: CleanDirDecision = DownloadFragment.planCleanDir('120', true, files, infoContentOf(120, 3));
  eq('文件数 2 vs 页数 3 → invalid', mismatch.invalid, true);
  eq('删掉两个图，保留 .ehviewer 与点文件',
    mismatch.deleteFiles, ['001.jpg', '002.jpg']);
  eq('重置 gid=120', mismatch.resetGid, 120);
  eq('日志逐字', mismatch.log,
    'Inconsistent file count: 120, expected: 3, actual: 2');

  // ⑥ 文件数与页数一致 → 不 invalid
  const okDir: CleanDirDecision = DownloadFragment.planCleanDir('120', true,
    ['001.jpg', '002.jpg', '003.jpg', DOWNLOAD_INFO_FILENAME], infoContentOf(120, 3));
  eq('一致 → 不计入 invalid', okDir.invalid, false);
  eq('一致 → 不删文件', okDir.deleteFiles, []);
  eq('一致 → 无日志', okDir.log, '');

  // ⑦ 页数行不是数字 → 归到"处理失败"日志（上游外层 catch 的等价）
  const badPages: CleanDirDecision = DownloadFragment.planCleanDir('9', true,
    ['001.jpg'], '9\nx\nx\nx\nx\nx\nx\nNaN\n');
  eq('页数解析失败 → invalid', badPages.invalid, true);
  ok('页数解析失败 → 日志含 "Error processing directory"',
    badPages.log.startsWith('Error processing directory: 9'));

  // ⑧ 结果提示
  eq('有无效项 → 提示清理数', DownloadFragment.cleanResultToast(4).args, [4]);
  eq('无无效项 → 提示"没有无效下载"', DownloadFragment.cleanResultToast(0).resKey,
    'settings_download_clean_invalid_no_invalid');
}

// ---------------------------------------------------------------- 清理日志

function testCleanLog(): void {
  const log: CleanLog = new CleanLog();
  eq('空日志 isEmpty', log.isEmpty(), true);
  log.add('Empty directory: 1');
  log.add('Missing .ehviewer file: 2');
  eq('有内容后非空', log.isEmpty(), false);
  eq('日志正文每条 + 换行',
    DownloadFragment.buildCleanLogContent(log),
    'Empty directory: 1\nMissing .ehviewer file: 2\n');
}

// ---------------------------------------------------------------- 进度

function testProgress(): void {
  const p = DownloadFragment.cleanProgress(0, 10);
  eq('进度起步 0/10', [p.progress, p.max], [0, 10]);
  const p2 = DownloadFragment.cleanProgress(10, 10);
  eq('进度到顶 10/10', [p2.progress, p2.max], [10, 10]);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testKeysAndClicks();
  testSummaries();
  testMediaScan();
  testTimeout();
  testSettingsWrite();
  testFileNames();
  testExport();
  testImport();
  testCleanDecisions();
  testCleanLog();
  testProgress();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync download fragment test failed');
  }
  console.log(`✓ download-sync 下载设置页批: ${pass} 条断言全部通过`);
}

main();
