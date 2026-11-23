// Settings 访问器全面断言：key 字面量、默认值、14 个布尔迁移、aPutNumber、类型容错、EhConfig 同步、Reader 设置等
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { Settings } = require(path.join(OUT, 'ehviewer', 'Settings.js'));
const { AppConfig } = require(path.join(OUT, 'ehviewer', 'AppConfig.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};
const S = Settings;

// ── key 字面量（审计按字面量 grep，必须完全一致）──
eq([S.KEY_DOWNLOAD_ORIGIN_IMAGE, S.KEY_DOWNLOAD_DELAY, S.KEY_DOWNLOAD_TIMEOUT,
    S.KEY_SYNC_DOWNLOAD_WHILE_READING, S.KEY_HISTORY_INFO_SIZE],
  ['download_origin_image', 'download_delay', 'download_timeout',
    'sync_download_while_reading', 'history_info_size'],
  '五个下载相关 key 与上游字面量一致');
eq([S.KEY_SAVE_CRASH_LOG, S.KEY_ENABLE_ANALYTICS, S.KEY_MEDIA_SCAN, S.KEY_DOMAIN_FRONTING],
  ['save_crash_log', 'enable_analytics', 'media_scan', 'domain_fronting'],
  '崩溃/统计/扫描/DF 四个 key 一致');
eq([S.KEY_SHOW_GALLERY_PAGES, S.KEY_SHOW_JPN_TITLE, S.KEY_SHOW_GALLERY_COMMENT, S.KEY_SAVE_PARSE_ERROR_BODY],
  ['show_gallery_pages', 'show_jpn_title', 'show_gallery_comment', 'save_parse_error_body'],
  '列表/详情显示四个 key 一致');
eq([S.KEY_THUMB_RESOLUTION, S.KEY_IMAGE_RESOLUTION, S.KEY_THEME, S.KEY_START_TRANSFER_TIME],
  ['thumb_resolution', 'image_size', 'theme', 'start_transfer_time'],
  '画质/主题/启动传输四个 key 一致');

// ── 默认值 ──
eq([S.DEFAULT_DOWNLOAD_ORIGIN_IMAGE, S.DEFAULT_DOWNLOAD_DELAY, S.DEFAULT_DOWNLOAD_TIMEOUT,
    S.DEFAULT_SYNC_DOWNLOAD_WHILE_READING, S.DEFAULT_HISTORY_INFO_SIZE],
  [false, 0, 0, false, 100], '默认值：origin=false / delay=0 / timeout=0 / sync=false / history=100');
eq([S.DEFAULT_SAVE_CRASH_LOG, S.DEFAULT_ENABLE_ANALYTICS, S.DEFAULT_MEDIA_SCAN, S.DEFAULT_FRONTING],
  [false, false, false, true], '默认值：crash=false / analytics=false / mediaScan=false / **DF=true**');
eq([S.DEFAULT_SHOW_GALLERY_PAGES, S.DEFAULT_SHOW_JPN_TITLE, S.IS_SHOW_GALLERY_COMMENT,
    S.DEFAULT_SAVE_PARSE_ERROR_BODY],
  [false, false, true, false], '默认值：pages=false / jpn=false / **comment=true** / parseError=false');
eq([S.DEFAULT_THUMB_RESOLUTION, S.DEFAULT_IMAGE_RESOLUTION, S.DEFAULT_THEME, S.DEFAULT_START_TRANSFER_TIME],
  [0, 'a', 0, 2], "默认值：thumb=0 / image='a' / theme=THEME_LIGHT(0) / startTransfer=2");
eq([S.IMAGE_SIZE_AUTO, S.IMAGE_SIZE_780X, S.IMAGE_SIZE_980X, S.IMAGE_SIZE_1280X,
    S.IMAGE_SIZE_1600X, S.IMAGE_SIZE_2400X], ['a', '780', '980', '1280', '1600', '2400'],
  'EhConfig 六个 image_size 取值与上游一致');
eq([S.THEME_LIGHT, S.THEME_DARK, S.THEME_BLACK], [0, 1, 2], '主题常量 LIGHT/DARK/BLACK = 0/1/2');

// ── 读默认值（未 attach、未写入 → 全部回到默认）──
eq([S.getDownloadOriginImage(), S.getDownloadDelay(), S.getDownloadTimeout(), S.getSyncDownloadWhileReading()],
  [false, 0, 0, false], '未写入时读默认值');
eq([S.getSaveCrashLog(), S.getEnableAnalytics(), S.getMediaScan(), S.getDF()],
  [false, false, false, true], '未写入时读默认值（DF 为 true）');
eq([S.getShowGalleryPages(), S.getShowJpnTitle(), S.getShowGalleryComment(), S.getSaveParseErrorBody()],
  [false, false, true, false], '未写入时读默认值（comment 为 true）');
eq([S.getThumbResolution(), S.getImageResolution(), S.getTheme(), S.getStartTransferTime()],
  [0, 'a', 0, 2], '未写入时读默认值');

// ── 写读往返 + 14 个非归档布尔全落 sMem（不落 sArchiverMem）──
const mem = S.sMem;
const archMem = S.sArchiverMem;
S.putGuideGallery(false);
eq(S.getGuideGallery(), false, 'putGuideGallery(false) → 读回 false');
S.putDownloadOriginImage(true);
eq(S.getDownloadOriginImage(), true, 'putDownloadOriginImage → 读回 true');
S.putDownloadDelay(1500);
eq(S.getDownloadDelay(), 1500, 'putDownloadDelay(1500) → 读回 1500');
S.putSyncDownloadWhileReading(true);
eq(S.getSyncDownloadWhileReading(), true, 'putSyncDownloadWhileReading → 读回 true');
S.putSaveCrashLog(true);
eq(S.getSaveCrashLog(), true, 'putSaveCrashLog → 读回 true');
S.putEnableAnalytics(true);
eq(S.getEnableAnalytics(), true, 'putEnableAnalytics → 读回 true');
S.putMediaScan(true);
eq(S.getMediaScan(), true, 'putMediaScan → 读回 true');
S.putDF(false);
eq(S.getDF(), false, 'putDF(false) → 读回 false');
S.putShowGalleryPages(true);
eq(S.getShowGalleryPages(), true, 'putShowGalleryPages → 读回 true');
S.putShowJpnTitle(true);
eq(S.getShowJpnTitle(), true, 'putShowJpnTitle → 读回 true');
S.putShowGalleryComment(false);
eq(S.getShowGalleryComment(), false, 'putShowGalleryComment(false) → 读回 false');
S.setShowGalleryComment(true);
eq(S.getShowGalleryComment(), true, 'setShowGalleryComment(true) → 读回 true');
S.putSaveParseErrorBody(true);
eq(S.getSaveParseErrorBody(), true, 'putSaveParseErrorBody → 读回 true');
S.putGuideDownloadThumb(false);
eq(S.getGuideDownloadThumb(), false, 'putGuideDownloadThumb(false) → 读回 false');
S.puttGuideDownloadLabels(false);
eq(S.getGuideDownloadLabels(), false, 'puttGuideDownloadLabels(false) → 读回 false');
S.setKeyShowEhEvents(false);
eq(S.getShowEhEvents(() => true), false, 'setKeyShowEhEvents(false) → 读回 false');
eq(archMem.size, 0, '14 个非归档布尔开关全部走主库 sMem，未误写入 sArchiverMem');

S.putThumbResolution(2);
eq(S.getThumbResolution(), 2, 'putThumbResolution(2) → 读回 2');
S.putTheme(S.THEME_DARK);
eq(S.getTheme(), S.THEME_DARK, 'putTheme(DARK) → 读回 1');
S.putStartTransferTime(5);
eq(S.getStartTransferTime(), 5, 'putStartTransferTime(5) → 读回 5');

// ── aPutNumber 修复：落 sArchiverMem 而非 sMem ──
S.putArchiverDownloadId(101, 555);
S.putArchiverDownloadTotal(555, 4096);
eq(S.getArchiverDownloadId(101), 555, 'aPutNumber 写回 getArchiverDownloadId');
eq(S.getArchiverDownloadTotal(555), 4096, 'aPutNumber 写回 getArchiverDownloadTotal');
eq(archMem.get('101DId'), '555', 'aPutNumber 写入 sArchiverMem');
eq(mem.has('archiver:101DId'), false, 'aPutNumber 不再误写入 sMem');
eq(S.hasPendingArchiverDownloads(), true, 'hasPendingArchiverDownloads 正确命中');
eq(S.getPendingArchiverDownloadIds(), [555], 'getPendingArchiverDownloadIds 返回 [555]');

// ── 三处非平凡行为 ──
mem.set(S.KEY_DOWNLOAD_TIMEOUT, '-100');
eq(S.getDownloadTimeout(), 0, 'getDownloadTimeout：负数被 Math.max 钳到 0');
mem.set(S.KEY_HISTORY_INFO_SIZE, '50');
eq(S.getHistoryInfoSize(), 100, 'getHistoryInfoSize(50) → 返回 100');
eq(mem.get(S.KEY_HISTORY_INFO_SIZE), '100', '…并把配置自愈写回 100');
mem.set(S.KEY_HISTORY_INFO_SIZE, '250');
eq(S.getHistoryInfoSize(), 250, 'getHistoryInfoSize(250) → 原样返回 250');
mem.set(S.KEY_IMAGE_RESOLUTION, '980');
eq(S.getImageResolution(), '780', "getImageResolution('980') → 返回 '780'");
eq(mem.get(S.KEY_IMAGE_RESOLUTION), '780', "…并把配置迁移为 '780'");
eq(S.getEhConfig().imageSize, '780', '…同步更新 sEhConfig.imageSize');
mem.set(S.KEY_IMAGE_RESOLUTION, '1600');
eq(S.getImageResolution(), '1600', "getImageResolution('1600') → 原样");
S.putImageResolution('1280');
eq(S.getImageResolution(), '1280', "putImageResolution('1280') → 读回 '1280'");
eq(S.getEhConfig().imageSize, '1280', 'putImageResolution 同步更新 sEhConfig');

// ── 新增网络/启动门/安全/显示/收藏/标签/语言访问器 ──
eq([S.getBuiltInHosts(), S.getBuiltEXHosts(), S.getDoH()], [true, true, false],
  '网络默认：builtInHosts=true / builtEXHosts=true / doh=false');
S.putBuiltInHosts(false);
S.putBuiltEXHosts(false);
S.putDoH(true);
eq([S.getBuiltInHosts(), S.getBuiltEXHosts(), S.getDoH()], [false, false, true], '网络开关写读往返');

eq([S.getDefaultCategories(), S.getExcludedTagNamespaces(), S.getExcludedLanguages()],
  [0x3ff, 0, null], '分类/标签命名空间/排除语言默认值');
S.putDefaultCategories(0x15);
S.putExcludedTagNamespaces(0x09);
S.putExcludedLanguages('0,1024');
eq([S.getDefaultCategories(), S.getExcludedTagNamespaces(), S.getExcludedLanguages()],
  [0x15, 0x09, '0,1024'], '分类/标签命名空间/排除语言写读往返');
eq([S.getEhConfig().defaultCategories, S.getEhConfig().excludedNamespaces, S.getEhConfig().excludedLanguages],
  [0x15, 0x09, '0,1024'], '…并同步更新 sEhConfig');
S.putExcludedLanguages(null);
eq(S.getExcludedLanguages(), null, 'putExcludedLanguages(null) → 读回 null');
eq(S.getEhConfig().excludedLanguages, '', '…sEhConfig.excludedLanguages 归为空串');

eq([S.getSecurity(), S.getEnableFingerprint(), S.getEnabledSecurity()], ['', false, false], '安全默认');
S.putSecurity('1234');
S.putEnableFingerprint(true);
S.putEnabledSecurity(true);
eq([S.getSecurity(), S.getEnableFingerprint(), S.getEnabledSecurity()], ['1234', true, true], '安全写读往返');
eq(S.getReadingFullscreen(), true, 'putEnabledSecurity 修复：不再误改 reading_fullscreen');

eq([S.getShowWarning(), S.getAskAnalytics(), S.getNeedSignIn(), S.getSelectSite()],
  [true, false, true, true], '启动门默认除 askAnalytics=false 外全 true');
S.putAskAnalytics(true);
eq(S.getAskAnalytics(), true, 'putAskAnalytics(true) 写读往返');
S.putShowWarning(false);
S.putAskAnalytics(false);
S.putNeedSignIn(false);
S.putSelectSite(false);
eq([S.getShowWarning(), S.getAskAnalytics(), S.getNeedSignIn(), S.getSelectSite()],
  [false, false, false, false], '启动门写读往返');

eq(S.getLaunchPageGalleryListSceneAction(), 'action_homepage', 'launch_page 默认 → action_homepage');
mem.set(S.KEY_LAUNCH_PAGE, '1');
eq(S.getLaunchPageGalleryListSceneAction(), 'action_subscription', 'launch_page=1 → action_subscription');
mem.set(S.KEY_LAUNCH_PAGE, '2');
eq(S.getLaunchPageGalleryListSceneAction(), 'action_whats_hot', 'launch_page=2 → action_whats_hot');
mem.set(S.KEY_LAUNCH_PAGE, '99');
eq(S.getLaunchPageGalleryListSceneAction(), 'action_homepage', 'launch_page 非法 → action_homepage');

eq([S.getDisplayName(), S.getAvatar()], [null, null], 'displayName/avatar 默认 null');
S.putDisplayName('Hippo');
S.putAvatar('https://ehgt.org/a.png');
eq([S.getDisplayName(), S.getAvatar()], ['Hippo', 'https://ehgt.org/a.png'], 'displayName/avatar 写读');
S.putDisplayName(null);
S.putAvatar(null);
eq([S.getDisplayName(), S.getAvatar()], [null, null], 'displayName/avatar 写 null 清空');

AppConfig.initialize({ filesDir: '/tmp/nonexistent-eh-test', cacheDir: '/tmp/nonexistent-eh-cache' });
const uid1 = S.getUserID();
const uid2 = S.getUserID();
eq(/^[0-9a-z]{32}$/.test(uid1), true, 'getUserID 生成 32 位 [0-9a-z]');
eq(uid1, uid2, 'getUserID 多次读取一致');

S.setLoginProvider(null);
eq(S.isLogin(), false, '未配置 provider 且未写 is_login → false');
S.setLoginState(true);
eq(S.isLogin(), true, 'setLoginState(true) → isLogin() === true');
S.setLoginProvider(() => false);
eq(S.isLogin(), false, '注入 loginProvider 返回 false 时以 cookie provider 为准');
S.setLoginProvider(() => true);
eq(S.isLogin(), true, '注入 loginProvider 返回 true 时 isLogin() === true');

eq([S.getFixThumbUrl(), S.getShowTagTranslations(), S.getShowGalleryRating()],
  [false, true, true], 'fixThumbUrl/tagTranslations/galleryRating 默认');
S.setShowGalleryRating(false);
eq(S.getShowGalleryRating(), false, 'setShowGalleryRating(false) → 读回 false');

let limitsLoginChecked = false;
S.setKeyShowEhLimits(false);
eq(S.getShowEhLimits(() => { limitsLoginChecked = true; return true; }), false, 'getShowEhLimits 关闭短路');
eq(limitsLoginChecked, false, '…未查登录态');
S.setKeyShowEhLimits(true);
eq(S.getShowEhLimits(() => true), true, 'getShowEhLimits 开启+已登录 → true');

eq([S.getListMode(), S.getDetailSize(), S.getDetailSizeResId()],
  [0, 0, 'app.float.gallery_list_column_width_long'], 'listMode/detailSize 默认');
mem.set(S.KEY_DETAIL_SIZE, '1');
eq(S.getDetailSizeResId(), 'app.float.gallery_list_column_width_short', 'detailSize=1 → short');

eq([S.getThumbSize(), S.getThumbSizeResId()], [1, 'app.float.gallery_grid_column_width_middle'], 'thumbSize=1 → middle');
mem.set(S.KEY_THUMB_SIZE, '0');
eq(S.getThumbSizeResId(), 'app.float.gallery_grid_column_width_large', 'thumbSize=0 → large');
mem.set(S.KEY_THUMB_SIZE, '2');
eq(S.getThumbSizeResId(), 'app.float.gallery_grid_column_width_small', 'thumbSize=2 → small');

eq([S.getShowReadProgress(), S.getGuideQuickSearch(), S.getQuickSearchTip(), S.getClipboardTextHashCode()],
  [true, true, true, 0], 'readProgress/guideQuickSearch/quickSearchTip/clipboardHash 默认');
S.setShowReadProgress(false);
S.putGuideQuickSearch(false);
S.putQuickSearchTip(false);
S.putClipboardTextHashCode(-12345);
eq([S.getShowReadProgress(), S.getGuideQuickSearch(), S.getQuickSearchTip(), S.getClipboardTextHashCode()],
  [false, false, false, -12345], '写读往返');

const defFav = S.getFavCat();
eq(defFav.length, 10, 'getFavCat 默认 10 项');
eq([defFav[0], defFav[9]], ['Favorites 0', 'Favorites 9'], 'getFavCat 默认名');
const customFav = defFav.map((v, idx) => `Cat_${idx}`);
S.putFavCat(customFav);
eq(S.getFavCat(), customFav, 'putFavCat / getFavCat 往返');

eq([S.getDefaultFavSlot(), S.getHasDefaultDownloadLabel(), S.getDefaultDownloadLabel(),
    S.getRecentDownloadLabel(), S.getRemoveImageFiles(), S.getDragDownloadGallery(),
    S.getAppLanguage(), S.isThemeAutoSwitchAvailable()],
  [-2, false, null, null, true, false, 'system', false], '收藏槽/下载标签/删除图片/拖拽/语言/自动主题 默认');
S.putDefaultFavSlot(3);
S.putHasDefaultDownloadLabel(true);
S.putDefaultDownloadLabel('Favs');
S.putRecentDownloadLabel('Recent');
S.putRemoveImageFiles(false);
S.setDragDownloadGallery(true);
S.putAppLanguage('zh');
eq([S.getDefaultFavSlot(), S.getHasDefaultDownloadLabel(), S.getDefaultDownloadLabel(),
    S.getRecentDownloadLabel(), S.getRemoveImageFiles(), S.getDragDownloadGallery(),
    S.getAppLanguage()],
  [3, true, 'Favs', 'Recent', false, true, 'zh'], '收藏槽/下载标签/删除图片/拖拽/语言 写读');

// ── 阅读器设置（GalleryActivity）──
eq([S.getStartPosition(), S.getScreenRotation(), S.getReadingRefreshRateHz(), S.getKeepScreenOn(),
    S.getShowClock(), S.getShowProgress(), S.getShowBattery(), S.getShowPageInterval(),
    S.getVolumePage(), S.getReverseVolumePage(), S.getReadingFullscreen(),
    S.getCustomScreenLightness(), S.getScreenLightness()],
  [1, 0, 0, false, true, true, true, true, false, false, true, false, 50], '阅读器设置全部默认值');
S.putStartPosition(4);
eq(S.getStartPosition(), 4, 'putStartPosition(4) → 4');
S.putStartPosition(99);
eq(S.getStartPosition(), 1, 'getStartPosition 非法值回退 START_POSITION_TOP_RIGHT(1)');
S.putScreenRotation(2);
S.putReadingRefreshRateHz(60);
eq([S.getScreenRotation(), S.getReadingRefreshRateHz()], [2, 60], 'screenRotation / readingRefreshRate 60');
S.putReadingRefreshRateHz(75);
eq(S.getReadingRefreshRateHz(), 0, 'readingRefreshRate 非法 75 被 sanitize 为 0');
S.putKeepScreenOn(true);
S.putShowClock(false);
S.putShowProgress(false);
S.putShowBattery(false);
S.putShowPageInterval(false);
S.putVolumePage(true);
S.putReverseVolumePage(true);
S.putReadingFullscreen(false);
S.putCustomScreenLightness(true);
S.putScreenLightness(88);
eq([S.getKeepScreenOn(), S.getShowClock(), S.getShowProgress(), S.getShowBattery(),
    S.getShowPageInterval(), S.getVolumePage(), S.getReverseVolumePage(), S.getReadingFullscreen(),
    S.getCustomScreenLightness(), S.getScreenLightness()],
  [true, false, false, false, false, true, true, false, true, 88], '阅读器设置全部写读往返');

// ── putDownloadLocation + .nomedia 维护 ──
let deletedNoMedia = 0;
let createdNoMedia = 0;
const fakeDir = {
  getUri: () => 'file:///tmp/dl_root',
  subFile: (name) => name === '.nomedia' ? { isFile: () => true, delete: () => { deletedNoMedia++; return true; } } : null,
  createFile: (name) => { if (name === '.nomedia') createdNoMedia++; return {}; },
};
S.putMediaScan(false);
S.putDownloadLocation(fakeDir);
eq([createdNoMedia, deletedNoMedia], [1, 0], 'putDownloadLocation(mediaScan=false) → createFile(.nomedia)');
S.putMediaScan(true);
S.putDownloadLocation(fakeDir);
eq([createdNoMedia, deletedNoMedia], [1, 1], 'putDownloadLocation(mediaScan=true) → removeNoMediaFile(.nomedia)');

// ── 底层 getBoolean/getInt/getLong/getFloat/getString 类型错配容错（ClassCastException 等价）──
const badStore = new Map([
  ['b_bad', 'not_bool'],
  ['i_bad', 'not_int'],
  ['l_bad', true],
  ['f_bad', 'not_float'],
  ['s_bad', 12345],
]);
S.sPref = {
  getSync: (k, d) => (badStore.has(k) ? badStore.get(k) : d),
  putSync: (k, v) => { badStore.set(k, v); },
  deleteSync: (k) => { badStore.delete(k); },
  hasSync: (k) => badStore.has(k),
  flush: async () => {},
  getAll: async () => ({}),
};
eq(S.getBoolean('b_bad', true), true, 'getBoolean 类型错配回退 defValue');
eq(S.getInt('i_bad', 77), 77, 'getInt 类型错配回退 defValue');
eq(S.getLong('l_bad', 9999999999), 9999999999, 'getLong 类型错配回退 defValue');
eq(S.getFloat('f_bad', 1.5), 1.5, 'getFloat 类型错配回退 defValue');
eq(S.getString('s_bad', 'fallback'), 'fallback', 'getString 类型错配回退 defValue');
S.putBoolean('b_ok', true);
S.putLong('l_ok', 9007199254740000);
S.putFloat('f_ok', 3.25);
eq([S.getBoolean('b_ok', false), S.getLong('l_ok', 0), S.getFloat('f_ok', 0)],
  [true, 9007199254740000, 3.25], 'attached 状态 getBoolean/getLong/getFloat 正常读写');
S.sPref = null;

// ── B1: Settings.ets 补全常量与访问器 ──────────────────────────────────────
S.sMem.delete(S.KEY_LAUNCH_PAGE);
S.sMem.delete(S.KEY_SECURITY);
eq([
  S.KEY_THEME_DARK,
  S.DEFAULT_THEME_AUTO_SWITCH,
  S.USER_BACKGROUND_IMAGE,
  S.USER_AVATAR_IMAGE,
  S.KEY_BETA_UPDATE_CHANNEL,
  S.DEFAULT_BETA_UPDATE_CHANNEL,
  S.KEY_SKIP_UPDATE_VERSION,
  S.DEFAULT_SKIP_UPDATE_VERSION,
  S.KEY_CLOSE_AUTO_UPDATES,
  S.IS_CLOSE_AUTO_UPDATES,
  S.KEY_LAST_UPDATE_TIME,
  S.DEFAULT_LAST_UPDATE_TIME,
], [
  'theme',
  false,
  'background_image_path',
  'avatar_image_path',
  'beta_update_channel',
  false,
  'skip_update_version',
  0,
  'close_auto_updates',
  false,
  'last_update_time',
  0,
], 'B1 新增常量对齐上游默认值');

eq(S.getLaunchPage(), 0, 'getLaunchPage 默认 0');
S.putLaunchPage(2);
eq([S.getLaunchPage(), S.getLaunchPageGalleryListSceneAction(), S.sMem.get(S.KEY_LAUNCH_PAGE)],
  [2, S.ACTION_WHATS_HOT, '2'], 'putLaunchPage(2) 存字符串且联动 WhatsHot');
S.putLaunchPage(1);
eq(S.getLaunchPageGalleryListSceneAction(), S.ACTION_SUBSCRIPTION, 'putLaunchPage(1) 联动 Subscription');
S.putLaunchPage(0);
eq(S.getLaunchPageGalleryListSceneAction(), S.ACTION_HOMEPAGE, 'putLaunchPage(0) 联动 Homepage');

S.putListMode(1);
S.putDetailSize(1);
S.putThumbSize(2);
S.putReadCacheSize(320);
eq([
  S.getListMode(), S.sMem.get(S.KEY_LIST_MODE),
  S.getDetailSize(), S.getDetailSizeResId(), S.sMem.get(S.KEY_DETAIL_SIZE),
  S.getThumbSize(), S.getThumbSizeResId(), S.sMem.get(S.KEY_THUMB_SIZE),
  S.getReadCacheSize(), S.sMem.get(S.KEY_READ_CACHE_SIZE),
], [
  1, '1',
  1, 'app.float.gallery_list_column_width_short', '1',
  2, 'app.float.gallery_grid_column_width_small', '2',
  320, '320',
], 'putListMode/putDetailSize/putThumbSize/putReadCacheSize 均按 C-12 存字符串');

S.putFixThumbUrl(true);
S.putShowTagTranslations(false);
S.putCellularNetworkWarning(true);
S.putThemeAutoSwitchAvailable(true);
S.putApplyNavBarThemeColor(true);
eq([
  S.getFixThumbUrl(),
  S.getShowTagTranslations(),
  S.getCellularNetworkWarning(),
  S.isThemeAutoSwitchAvailable(),
  S.getApplyNavBarThemeColor(),
], [true, false, true, true, true], 'B1 布尔设置项 put/get 闭环');

eq(S.hasSecurity(), false, '未设置手势密码时 hasSecurity() === false');
S.putSecurity('0123');
eq(S.hasSecurity(), true, '设置手势密码后 hasSecurity() === true');
S.putSecurity('');
eq(S.hasSecurity(), false, '清空手势密码后 hasSecurity() === false');

// XML 安全编解码：含格子 0 (\x00) 的真实图案串写入 preferences 时绝不落控制字符
const rawStore = new Map();
let flushCount = 0;
S.sPref = {
  getSync: (k, d) => (rawStore.has(k) ? rawStore.get(k) : d),
  putSync: (k, v) => { rawStore.set(k, v); },
  deleteSync: (k) => { rawStore.delete(k); },
  hasSync: (k) => rawStore.has(k),
  flush: async () => { flushCount++; },
  getAll: async () => ({}),
};
const cellPatternWithZero = String.fromCharCode(0, 1, 2, 5, 8);
S.putSecurity(cellPatternWithZero);
const persistedSecurity = rawStore.get(S.KEY_SECURITY);
let hasXmlIllegalControlChar = false;
for (let i = 0; i < persistedSecurity.length; i++) {
  if (persistedSecurity.charCodeAt(i) < 0x20) {
    hasXmlIllegalControlChar = true;
  }
}
eq(persistedSecurity, 'ehp:01258', '含格子 0 的手势串持久化为纯 ASCII ehp:01258');
eq(hasXmlIllegalControlChar, false, '持久化字符串含零个 < 0x20 控制字符，防 libxml2 毁库');
eq(S.getSecurity(), cellPatternWithZero, '读取安全码完整还原原始手势字符序列 (0..8)');
eq(S.hasSecurity(), true, '读取 encoded 图案后 hasSecurity() === true');
S.putSecurity('');
eq([rawStore.get(S.KEY_SECURITY), S.getSecurity(), S.hasSecurity()], ['', '', false],
  '清空手势密码后同步归空且 hasSecurity() === false');
S.sPref = null;

eq(S.getDarkModeStatus(), false, '未注入提供者时 getDarkModeStatus() === false');
eq(S.getDarkModeStatus(() => true), true, '直接传入回调时 getDarkModeStatus() === true');
S.setDarkModeProvider(() => true);
eq([S.getDarkModeStatus(), S.getDarkModeStatus(() => false)], [true, false],
  'sDarkModeProvider 生效且可被显式回调覆盖');
S.setDarkModeProvider(null);
eq(S.getDarkModeStatus(), false, '清除 sDarkModeProvider 后恢复 false');

eq(S.getUserImageFile(S.USER_AVATAR_IMAGE), null, '未设置路径时 getUserImageFile 返回 null');
S.saveFilePath(S.USER_AVATAR_IMAGE, '/non_existent_b1_avatar_path.png');
eq(S.getUserImageFile(S.USER_AVATAR_IMAGE), null, '不存在的文件 getUserImageFile 返回 null');
const fsCacheKey = Object.keys(require.cache).find(k => k.indexOf('@ohos.file.fs') !== -1);
const mockFsModule = fsCacheKey ? require.cache[fsCacheKey].exports : null;
const mockFs = mockFsModule && mockFsModule.default ? mockFsModule.default : mockFsModule;
if (!mockFs || typeof mockFs.openSync !== 'function') {
  throw new Error('未能从 require.cache 获取 @ohos.file.fs stub');
}
const mockBgPath = '/b1_existing_bg_test.png';
const mockFile = mockFs.openSync(mockBgPath, mockFs.OpenMode.READ_WRITE | mockFs.OpenMode.CREATE);
mockFs.writeSync(mockFile.fd, 'x');
mockFs.closeSync(mockFile);
S.saveFilePath(S.USER_BACKGROUND_IMAGE, mockBgPath);
eq(S.getUserImageFile(S.USER_BACKGROUND_IMAGE), mockBgPath, '存在的文件 getUserImageFile 返回路径');
S.saveFilePath(S.USER_BACKGROUND_IMAGE, '');

eq([S.getBetaUpdateChannel(), S.getSkipUpdateVersion(), S.getCloseAutoUpdate()],
  [false, 0, false], '更新兼容键默认值');
S.putBetaUpdateChannel(true);
S.putSkipUpdateVersion(42);
S.setKeyCloseAutoUpdates(true);
eq([S.getBetaUpdateChannel(), S.getSkipUpdateVersion(), S.getCloseAutoUpdate()],
  [true, 42, true], '更新兼容键 put/get 闭环');

const baseUpdateMs = 1700000000000;
S.putUpdateTime(baseUpdateMs);
eq([
  S.getLong(S.KEY_LAST_UPDATE_TIME, 0),
  S.getIsUpdateTime(baseUpdateMs - 100),
  S.getIsUpdateTime(baseUpdateMs + 86400000 - 1),
  S.getIsUpdateTime(baseUpdateMs + 86400000),
  S.getIsUpdateTime(baseUpdateMs + 86400000 * 2),
], [baseUpdateMs, false, false, true, true], 'putUpdateTime 与 getIsUpdateTime 24h 阈值精确匹配');

(async () => {
  flushCount = 0;
  S.sPref = {
    getSync: (k, d) => (rawStore.has(k) ? rawStore.get(k) : d),
    putSync: (k, v) => { rawStore.set(k, v); },
    deleteSync: (k) => { rawStore.delete(k); },
    hasSync: (k) => rawStore.has(k),
    flush: async () => { flushCount++; },
    getAll: async () => ({}),
  };
  await S.flush();
  eq(flushCount, 1, 'Settings.flush() 显式落盘调用 sPref.flush()');
  S.sPref = null;
  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
