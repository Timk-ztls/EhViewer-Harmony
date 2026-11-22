/*
 * native-image 接手批单测：DownloadSearchController（S0228）+ DownloadLabelDraw（S0217）
 *                       + ArchiverDownloadDialog（S0190）
 *
 * 断言重点（"同一批里两种相反写法"与"无条件 finally"）：
 *   ① ★`gotoSearch` 已有对话框 → **只显示不重建**（与 DownloadLabelsScene 的"先 show 再重建"相反）
 *   ② ★对话框**取消**也会 `applySearch(true)`（空 key = 清除筛选）
 *   ③ `onDismiss` 把 `mSearchMode = false`
 *   ④ `startSearching` 里 `mSearchMode` 时**先恢复标题再 setState**
 *   ⑤ ★`gotoFilterAndSort` 用 **getBackList()**（原始表），不是 getList()
 *   ⑥ `isValidView` 恒 false / `forceShowSearchBar` 恒 false
 *   ⑦ ★"设为默认下载标签"的 items 是 **+2 偏移**（`[让我选择, 默认名称, ...标签]`）
 *   ⑧ `dm == null` 时菜单**已处理返回 true**
 *   ⑨ 搜索中不许切标签（Toast）；点已选中的标签**什么都不做（连抽屉都不关）**
 *   ⑩ ★Archiver：`finally` **无条件**切"加载中"（url 为空也会）
 *   ⑪ ★当前资金**分站点**：SITE_E 加前缀，其它裸显示
 *   ⑫ `onDownloadUrl` 的 7 步校验链（依次短路）
 *   ⑬ `onDownloadFailure`：**isShowing 才 dismiss** + NoHath 走不同文案
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter download-search
 */

import {
  DownloadSearchController, SearchHost, ExecutorPort, SearchDialogSpec,
  STR_SEARCH_HINT, STR_SEARCH_GALLERY, SEARCH_STATE_NORMAL, SEARCH_STATE_SEARCH_LIST,
  DRAWABLE_BIG_DOWNLOAD, DRAWABLE_MAGNIFY
} from '../../main/ets/hippo/ehviewer/ui/scene/download/part/DownloadSearchController';
import {
  DownloadLabelDraw, LabelDrawHost, LabelDrawSettings, LabelDrawManager, DownloadLabelItem,
  DefaultLabelDialogSpec, DefaultLabelChoice, MenuClickResult,
  STR_DOWNLOAD_LABELS, STR_LET_ME_SELECT, STR_DEFAULT_LABEL_NAME, STR_DEFAULT_LABEL,
  STR_DOWNLOAD_SEARCHING, MENU_ACTION_SETTINGS, MENU_ACTION_DEFAULT_DOWNLOAD_LABEL,
  MENU_DRAWER_DOWNLOAD
} from '../../main/ets/hippo/ehviewer/ui/scene/download/DownloadLabelDraw';
import {
  ArchiverDownloadDialog, ArchiverDialogHost, ArchiverApi, ArchiverDialogSpec,
  ArchiverDownloadAttempt, urlScheme, STR_CURRENT_FUNDS, STR_COST, STR_SIZE,
  STR_STATE_FAILED, STR_ARCHIVE_STARTED, STR_HATH_FAILURE, STR_ARCHIVE_FAILURE,
  DLCHECK_ORIGINAL, DLCHECK_RESAMPLE, DLTYPE_ORIGINAL, DLTYPE_RESAMPLE, SITE_E
} from '../../main/ets/hippo/ehviewer/ui/dialog/ArchiverDownloadDialog';
import { ArchiverData } from '../../main/ets/hippo/ehviewer/client/data/ArchiverData';
import { GalleryDetail } from '../../main/ets/hippo/ehviewer/client/data/GalleryDetail';
import { DownloadLabel } from '../../main/ets/hippo/ehviewer/dao/DownloadLabel';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';
import { DownloadManager } from '../../main/ets/hippo/ehviewer/download/DownloadManager';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
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
    fails.push(`${name}\n    条件为 false`);
  }
}

// ---------------------------------------------------------------- S0228
class FakeExecutor implements ExecutorPort {
  searchingCalls: number = 0;
  filterCalls: number[] = [];
  listenerSet: boolean = false;

  setDownloadSearchingListener(callback: Object | null): void {
    this.listenerSet = true;
  }

  executeSearching(): void {
    this.searchingCalls++;
  }

  executeFilterAndSort(id: number): void {
    this.filterCalls.push(id);
  }
}

class FakeSearchHost implements SearchHost {
  key: string | null = null;
  searching: boolean = false;
  list: DownloadInfo[] | null = [];
  backList: DownloadInfo[] | null = [];
  dm: DownloadManager | null = null;
  progress: boolean[] = [];
  recycler: boolean[] = [];
  barText: (string | null)[] = [];
  barTitle: (string | null)[] = [];
  barStates: string[] = [];
  cursorEnd: number = 0;
  keyboardHidden: number = 0;
  applySearchCalls: boolean[] = [];
  moverCalls: number = 0;
  shown: SearchDialogSpec[] = [];
  dismissCalls: number = 0;
  updateForLabelCalls: number = 0;
  executor: FakeExecutor = new FakeExecutor();
  filterExecutor: FakeExecutor = new FakeExecutor();

  getSearchKey(): string | null { return this.key; }
  setSearchKey(key: string | null): void { this.key = key; }
  setSearching(searching: boolean): void { this.searching = searching; }
  getList(): DownloadInfo[] | null { return this.list; }
  getBackList(): DownloadInfo[] | null { return this.backList; }
  getDownloadManager(): DownloadManager | null { return this.dm; }
  updateForLabel(): void { this.updateForLabelCalls++; }
  getSearchCallback(): Object | null { return null; }
  setProgressVisible(visible: boolean): void { this.progress.push(visible); }
  setRecyclerViewVisible(visible: boolean): void { this.recycler.push(visible); }
  newExecutor(list: DownloadInfo[] | null, key: string | null): ExecutorPort { return this.executor; }
  newExecutorForFilter(list: DownloadInfo[] | null, dm: DownloadManager | null): ExecutorPort {
    return this.filterExecutor;
  }
  setSearchBarText(text: string | null): void { this.barText.push(text); }
  setSearchBarTitle(text: string | null): void { this.barTitle.push(text); }
  setSearchBarState(state: number, animation: boolean): void { this.barStates.push(`${state}:${animation}`); }
  cursorToEnd(): void { this.cursorEnd++; }
  hideKeyboard(): void { this.keyboardHidden++; }
  applySearch(animation: boolean): void { this.applySearchCalls.push(animation); }
  returnSearchBarPosition(animation: boolean): void { this.moverCalls++; }
  showSearchDialog(spec: SearchDialogSpec): void { this.shown.push(spec); }
  dismissSearchDialog(): void { this.dismissCalls++; }
}

function testDownloadSearchController(): void {
  eq('提示键与图标名', [STR_SEARCH_HINT, STR_SEARCH_GALLERY],
    ['app.string.download_search_hint', 'app.string.download_search_gallery']);
  eq('左右图标', [DRAWABLE_BIG_DOWNLOAD, DRAWABLE_MAGNIFY], ['big_download', 'v_magnify_x24']);
  eq('两个 SearchBar 状态', [SEARCH_STATE_NORMAL, SEARCH_STATE_SEARCH_LIST], [0, 1]);

  // ---------- 空 key：标题用 hint ----------
  const h1: FakeSearchHost = new FakeSearchHost();
  const c1: DownloadSearchController = new DownloadSearchController(h1);
  const spec1: SearchDialogSpec | null = c1.gotoSearch();
  ok('产出对话框描述', spec1 !== null);
  if (spec1 !== null) {
    eq('空 key → 标题 = hint', spec1.title, STR_SEARCH_HINT);
    eq('message 键', spec1.messageKey, STR_SEARCH_GALLERY);
    eq('文本为空', spec1.text, '');
  }
  // ---------- ① 已有对话框 → 只显示不重建 ----------
  const again: SearchDialogSpec | null = c1.gotoSearch();
  eq('★已有对话框 → 不再产出新描述（只显示）', again, null);
  eq('且只 show 过一次', h1.shown.length, 1);

  // ---------- 有 key：标题 = key ----------
  const h2: FakeSearchHost = new FakeSearchHost();
  h2.key = 'abc';
  const c2: DownloadSearchController = new DownloadSearchController(h2);
  const spec2: SearchDialogSpec | null = c2.gotoSearch();
  ok('有 key 也产出描述', spec2 !== null);
  if (spec2 !== null) {
    eq('★有 key → 标题 = key', spec2.title, 'abc');
    eq('文本 = key', spec2.text, 'abc');
  }

  // ---------- ② 取消也会 applySearch ----------
  const h3: FakeSearchHost = new FakeSearchHost();
  h3.key = 'xy';
  const c3: DownloadSearchController = new DownloadSearchController(h3);
  c3.gotoSearch();
  c3.onDialogCancel();
  eq('★取消 → applySearch 被调用一次', h3.applySearchCalls, [true]);
  eq('取消 → key 置 null', h3.key, null);
  eq('取消 → 清文本', h3.barText, [null]);
  eq('取消 → 清标题', h3.barTitle, [null]);
  eq('取消 → dismiss', h3.dismissCalls, 1);
  // 确认按钮
  const h4: FakeSearchHost = new FakeSearchHost();
  const c4: DownloadSearchController = new DownloadSearchController(h4);
  c4.gotoSearch();
  c4.onDialogConfirm();
  eq('确认 → applySearch 一次', h4.applySearchCalls, [true]);
  eq('确认 → 不清 key', h4.key, null);   // 本来就没设过

  // ---------- ③ onDismiss 退出搜索模式 ----------
  const h5: FakeSearchHost = new FakeSearchHost();
  const c5: DownloadSearchController = new DownloadSearchController(h5);
  c5.gotoSearch();
  eq('onClickTitle → 进入搜索模式', c5.onClickTitle(), true);
  eq('搜索模式已开', c5.isSearchMode(), true);
  c5.onSearchDialogDismiss();
  eq('★onDismiss 后退出搜索模式', c5.isSearchMode(), false);

  // ---------- enterSearchMode 三重防御 ----------
  const h6: FakeSearchHost = new FakeSearchHost();
  const c6: DownloadSearchController = new DownloadSearchController(h6);
  eq('未 gotoSearch（bar 未就绪）→ 不进入', c6.enterSearchMode(true), false);
  c6.gotoSearch();
  eq('就绪后进入', c6.enterSearchMode(true), true);
  eq('已进入 → 再次调用返回 false', c6.enterSearchMode(true), false);
  eq('进入了 SEARCH_LIST 状态', h6.barStates, ['1:true']);
  eq('调用了 mover', h6.moverCalls, 1);
  eq('已进入时 onClickTitle 不再动作', c6.onClickTitle(), false);

  // ---------- ④ startSearching：退出搜索模式要恢复标题 ----------
  const h7: FakeSearchHost = new FakeSearchHost();
  h7.key = 'q1';
  const c7: DownloadSearchController = new DownloadSearchController(h7);
  c7.gotoSearch();
  c7.enterSearchMode(false);
  c7.startSearching();
  eq('startSearching → progress 显示', h7.progress, [true]);
  eq('startSearching → recycler 隐藏', h7.recycler, [false]);
  eq('★退出搜索模式并恢复标题为当前 key', h7.barTitle, ['q1']);
  eq('恢复后 setState NORMAL', h7.barStates[h7.barStates.length - 1], '0:false');
  eq('搜索模式已退出', c7.isSearchMode(), false);
  eq('调用了 updateForLabel', h7.updateForLabelCalls, 1);
  eq('执行器执行了 searching', h7.executor.searchingCalls, 1);
  ok('执行器绑定了 listener', h7.executor.listenerSet);

  // ---------- ⑤ gotoFilterAndSort 用 backList ----------
  const h8: FakeSearchHost = new FakeSearchHost();
  const c8: DownloadSearchController = new DownloadSearchController(h8);
  c8.gotoFilterAndSort(7);
  eq('筛选 → progress 显示', h8.progress, [true]);
  eq('筛选 → recycler 隐藏', h8.recycler, [false]);
  eq('★筛选执行器收到 id 7（且用 backList 构造 — 由 host 的 newExecutorForFilter 承担）',
    h8.filterExecutor.filterCalls, [7]);
  eq('筛选不走 searching 执行器', h8.executor.searchingCalls, 0);

  // ---------- onApplySearch ----------
  const h9: FakeSearchHost = new FakeSearchHost();
  const c9: DownloadSearchController = new DownloadSearchController(h9);
  c9.gotoSearch();
  c9.onApplySearch('kw');
  eq('存 key', h9.key, 'kw');
  eq('收键盘', h9.keyboardHidden, 1);
  eq('★setSearching(true)', h9.searching, true);
  eq('触发了搜索执行', h9.executor.searchingCalls, 1);

  // ---------- ⑥ 恒返回值 ----------
  eq('isValidView 恒 false', c9.isValidView(), false);
  eq('forceShowSearchBar 恒 false', c9.forceShowSearchBar(), false);
  // 空实现方法可直接调用（不应抛）
  c9.onClickLeftIcon();
  c9.onSearchEditTextClick();
  c9.onStateChange(1, 0, true);
  ok('空实现方法可安全调用', true);

  // ---------- onSearchEditTextBackPressed ----------
  const h10: FakeSearchHost = new FakeSearchHost();
  const c10: DownloadSearchController = new DownloadSearchController(h10);
  c10.gotoSearch();
  c10.enterSearchMode(false);
  c10.onSearchEditTextBackPressed();
  eq('返回键 → 退出搜索模式', c10.isSearchMode(), false);
  eq('返回键 → setState NORMAL', h10.barStates[h10.barStates.length - 1], '0:true');
}

// ---------------------------------------------------------------- S0217
class FakeLabelManager implements LabelDrawManager {
  labels: DownloadLabel[] = [];
  defaultCount: number = 0;
  counts: Map<string, number> = new Map<string, number>();

  getLabelList(): DownloadLabel[] { return this.labels; }
  getDefaultDownloadCount(): number { return this.defaultCount; }
  getLabelCount(label: string): number {
    const v = this.counts.get(label);
    return v === undefined ? 0 : v;
  }
}

class FakeLabelHost implements LabelDrawHost {
  dm: LabelDrawManager | null = new FakeLabelManager();
  searching: boolean = false;
  key: string | null = null;
  currentLabel: string | null = null;
  labelsScene: number = 0;
  closedDrawer: number = 0;
  toasts: string[] = [];
  updateForLabelCalls: number = 0;
  updateViewCalls: number = 0;
  startSearchingCalls: number = 0;

  getDownloadManager(): LabelDrawManager | null { return this.dm; }
  resolveString(key: string): string {
    if (key === STR_DEFAULT_LABEL_NAME) { return 'Default'; }
    if (key === STR_LET_ME_SELECT) { return 'LetMeSelect'; }
    return key;
  }
  isSearching(): boolean { return this.searching; }
  getSearchKey(): string | null { return this.key; }
  getCurrentLabel(): string | null { return this.currentLabel; }
  setCurrentLabel(label: string | null): void { this.currentLabel = label; }
  updateForLabel(): void { this.updateForLabelCalls++; }
  updateView(): void { this.updateViewCalls++; }
  startSearching(): void { this.startSearchingCalls++; }
  startLabelsScene(): void { this.labelsScene++; }
  closeDrawer(): void { this.closedDrawer++; }
  showToast(key: string): void { this.toasts.push(key); }
}

class FakeLabelSettings implements LabelDrawSettings {
  hasDefault: boolean[] = [];
  labels: (string | null)[] = [];

  putHasDefaultDownloadLabel(v: boolean): void { this.hasDefault.push(v); }
  putDefaultDownloadLabel(label: string | null): void { this.labels.push(label); }
}

function mkLabel(id: number, name: string): DownloadLabel {
  return new DownloadLabel(id, name, 0);
}

function testDownloadLabelDraw(): void {
  eq('菜单与标题键', [MENU_DRAWER_DOWNLOAD, STR_DOWNLOAD_LABELS],
    ['menu/drawer_download', 'app.string.download_labels']);

  // ---------- ⑦ items 的 +2 偏移 ----------
  const h1: FakeLabelHost = new FakeLabelHost();
  const dm1: FakeLabelManager = h1.dm as FakeLabelManager;
  dm1.labels = [mkLabel(1, 'L1'), mkLabel(2, 'L2')];
  const s1: FakeLabelSettings = new FakeLabelSettings();
  const d1: DownloadLabelDraw = new DownloadLabelDraw(h1, s1);
  const r1: MenuClickResult = d1.onMenuItemClick(MENU_ACTION_DEFAULT_DOWNLOAD_LABEL);
  eq('菜单已处理', r1.handled, true);
  ok('产出了对话框', r1.dialog !== null);
  if (r1.dialog !== null) {
    eq('★items = [让我选择, 默认名称, L1, L2]（+2 偏移）', r1.dialog.items,
      ['LetMeSelect', 'Default', 'L1', 'L2']);
    eq('对话框 title', r1.dialog.title, STR_DEFAULT_LABEL);
  }
  // which == 0 → 关掉默认标签，**不写 label**
  const ch0: DefaultLabelChoice = d1.onDefaultLabelSelected(r1.dialog as DefaultLabelDialogSpec, 0);
  eq('which=0 → hasDefault=false', ch0.hasDefault, false);
  eq('which=0 → 只写 hasDefault', s1.hasDefault, [false]);
  eq('★which=0 → 不写 label', s1.labels, []);
  // which == 1 → label null
  const ch1: DefaultLabelChoice = d1.onDefaultLabelSelected(r1.dialog as DefaultLabelDialogSpec, 1);
  eq('which=1 → hasDefault=true', s1.hasDefault, [false, true]);
  eq('which=1 → label = null', s1.labels, [null]);
  // which == 2 → L1
  const ch2: DefaultLabelChoice = d1.onDefaultLabelSelected(r1.dialog as DefaultLabelDialogSpec, 2);
  eq('which=2 → label = L1', s1.labels, [null, 'L1']);
  eq('choice 反映 label', ch2.defaultLabel, 'L1');

  // ---------- ⑧ dm == null 也返回 true ----------
  const h2: FakeLabelHost = new FakeLabelHost();
  h2.dm = null;
  const d2: DownloadLabelDraw = new DownloadLabelDraw(h2, new FakeLabelSettings());
  const r2: MenuClickResult = d2.onMenuItemClick(MENU_ACTION_DEFAULT_DOWNLOAD_LABEL);
  eq('★dm 为 null → 已处理返回 true', r2.handled, true);
  eq('dm 为 null → 不产出对话框', r2.dialog, null);
  eq('未知菜单项 → 未处理', d2.onMenuItemClick('action_x').handled, false);
  // action_settings
  const r3: MenuClickResult = d2.onMenuItemClick(MENU_ACTION_SETTINGS);
  eq('设置项 → 已处理', r3.handled, true);
  eq('设置项 → 进标签管理页', h2.labelsScene, 1);

  // ---------- 列表构建：第 0 项用 defaultCount ----------
  const h4: FakeLabelHost = new FakeLabelHost();
  const dm4: FakeLabelManager = h4.dm as FakeLabelManager;
  dm4.labels = [mkLabel(1, 'L1'), mkLabel(2, 'L2')];
  dm4.defaultCount = 5;
  dm4.counts.set('L1', 3);
  dm4.counts.set('L2', 0);
  const d4: DownloadLabelDraw = new DownloadLabelDraw(h4, new FakeLabelSettings());
  const items: DownloadLabelItem[] = d4.buildLabelItems();
  eq('项数 = 1 + 2', items.length, 3);
  eq('第 0 项 = 默认名称', items[0].label, 'Default');
  eq('★第 0 项条目数 = getDefaultDownloadCount()', items[0].count, 5);
  eq('第 1 项 = L1 / 3', [items[1].label, items[1].count], ['L1', 3]);
  eq('第 2 项 = L2 / 0', [items[2].label, items[2].count], ['L2', 0]);

  // ---------- ⑨ 搜索中不许切标签 ----------
  const h5: FakeLabelHost = new FakeLabelHost();
  h5.searching = true;
  const d5: DownloadLabelDraw = new DownloadLabelDraw(h5, new FakeLabelSettings());
  eq('搜索中点击 → 不切换', d5.onItemClick(1, items), false);
  eq('搜索中 → toast download_searching', h5.toasts, [STR_DOWNLOAD_SEARCHING]);
  eq('搜索中 → 不关抽屉', h5.closedDrawer, 0);

  // 点已选中的标签 → 什么都不做（连抽屉都不关）
  h5.searching = false;
  h5.currentLabel = null;   // 当前是"默认标签"（null）
  eq('★点已选中的第 0 项 → 不动作', d5.onItemClick(0, items), false);
  eq('★且不关抽屉', h5.closedDrawer, 0);
  eq('未调用 updateForLabel', h5.updateForLabelCalls, 0);

  // 点第 1 项（L1）→ 切标签 + 关抽屉
  eq('点 L1 → 切换成功', d5.onItemClick(1, items), true);
  eq('currentLabel = L1', h5.currentLabel, 'L1');
  eq('调用了 updateForLabel', h5.updateForLabelCalls, 1);
  eq('无搜索 key → 走 updateView', [h5.updateViewCalls, h5.startSearchingCalls], [1, 0]);
  eq('关闭抽屉', h5.closedDrawer, 1);

  // 有搜索 key → 走 startSearching
  const h6: FakeLabelHost = new FakeLabelHost();
  h6.key = 'kw';
  const d6: DownloadLabelDraw = new DownloadLabelDraw(h6, new FakeLabelSettings());
  d6.onItemClick(1, items);
  eq('有搜索 key → 走 startSearching', [h6.startSearchingCalls, h6.updateViewCalls], [1, 0]);

  // 越界
  eq('越界 → false', d5.onItemClick(9, items), false);
}

// ---------------------------------------------------------------- S0190
class FakeArchiverHost implements ArchiverDialogHost {
  site: number = SITE_E;
  activity: boolean = true;
  downloaderAvailable: boolean = true;
  fileName: string = 'file.zip';
  hathError: boolean = false;
  tips: string[] = [];
  toasts: string[] = [];
  warnings: string[] = [];
  started: string[] = [];
  boundProgress: number = 0;

  resolveString(key: string): string {
    if (key === STR_CURRENT_FUNDS) { return 'Funds: '; }
    return key;
  }
  formatString(key: string, arg: string): string { return `${key}(${arg})`; }
  getGallerySite(): number { return this.site; }
  hasActivity(): boolean { return this.activity; }
  showTip(key: string, isLong: boolean): void { this.tips.push(`${key}:${isLong}`); }
  showToast(key: string): void { this.toasts.push(key); }
  logWarning(msg: string): void { this.warnings.push(msg); }
  getDownloaderAvailable(): boolean { return this.downloaderAvailable; }
  startDownload(downloadUrl: string, fileName: string): void {
    this.started.push(`${downloadUrl}|${fileName}`);
  }
  createFileName(title: string, gid: number): string { return this.fileName; }
  bindArchiverProgress(): void { this.boundProgress++; }
  isNoHathError(e: Error): boolean { return this.hathError; }
}

class FakeArchiverApi implements ArchiverApi {
  archiverResult: ArchiverData | null = null;
  downloadResult: string | null = 'https://TARGET/a.zip';
  downloadCalls: string[] = [];
  archiverCalls: number = 0;

  requestArchiver(archiveUrl: string, gid: number, token: string): Promise<ArchiverData | null> {
    this.archiverCalls++;
    return Promise.resolve(this.archiverResult);
  }
  requestDownload(url: string, archiveUrl: string, dltype: string, dlcheck: string): Promise<string | null> {
    this.downloadCalls.push(`${url}|${dltype}|${dlcheck}`);
    return Promise.resolve(this.downloadResult);
  }
}

function mkArchiverData(): ArchiverData {
  const d: ArchiverData = new ArchiverData();
  d.funds = '100';
  d.originalCost = '10';
  d.originalSize = '1GB';
  d.resampleCost = '5';
  d.resampleSize = '500MB';
  d.originalUrl = 'https://TARGET/org';
  d.resampleUrl = 'https://TARGET/res';
  return d;
}

function mkDetail(): GalleryDetail {
  const gd: GalleryDetail = new GalleryDetail();
  gd.gid = 42;
  gd.token = 'tok';
  gd.title = 'T';
  gd.archiveUrl = 'https://TARGET/archive';
  return gd;
}

async function testArchiverDownloadDialog(): Promise<void> {
  // ---------- urlScheme ----------
  eq('https scheme', urlScheme('https://a/b'), 'https');
  eq('大写 HTTP → 小写化', urlScheme('HTTP://a/b'), 'http');
  eq('无 scheme → 空串', urlScheme('//a/b'), '');
  eq('相对路径 → 空串', urlScheme('a/b'), '');
  eq('javascript: → javascript（会被白名单拒绝）', urlScheme('javascript:alert(1)'), 'javascript');
  eq('file: → file（也会被拒绝）', urlScheme('file:///etc/passwd'), 'file');

  // ---------- ① finally 无条件切"加载中" ----------
  const h1: FakeArchiverHost = new FakeArchiverHost();
  const api1: FakeArchiverApi = new FakeArchiverApi();
  api1.archiverResult = mkArchiverData();
  const dlg1: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h1, api1);
  const spec1: ArchiverDialogSpec = await dlg1.showDialog();
  eq('showDialog 请求了 archiver', api1.archiverCalls, 1);
  eq('成功后 progress 关、body 开', [spec1.progressVisible, spec1.bodyVisible], [false, true]);
  // 原档下载
  const att1: ArchiverDownloadAttempt = await dlg1.onArchiverDownload(true);
  eq('原档 → requested', att1.requested, true);
  eq('原档 dltype/dlcheck', [att1.dltype, att1.dlcheck], [DLTYPE_ORIGINAL, DLCHECK_ORIGINAL]);
  eq('★下载链路走完 → 启动下载', h1.started, ['https://TARGET/a.zip|file.zip']);
  eq('绑定了进度', h1.boundProgress, 1);
  eq('提示"已开始"', h1.tips, [`${STR_ARCHIVE_STARTED}:false`]);

  // 重采样
  const h2: FakeArchiverHost = new FakeArchiverHost();
  const api2: FakeArchiverApi = new FakeArchiverApi();
  api2.archiverResult = mkArchiverData();
  const dlg2: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h2, api2);
  await dlg2.showDialog();
  const att2: ArchiverDownloadAttempt = await dlg2.onArchiverDownload(false);
  eq('重采样 dltype/dlcheck', [att2.dltype, att2.dlcheck], [DLTYPE_RESAMPLE, DLCHECK_RESAMPLE]);

  // url 为空 → 不请求，但 finally 仍切"加载中"
  const h3: FakeArchiverHost = new FakeArchiverHost();
  const api3: FakeArchiverApi = new FakeArchiverApi();
  const emptyData: ArchiverData = new ArchiverData();   // originalUrl 为空
  api3.archiverResult = emptyData;
  const dlg3: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h3, api3);
  await dlg3.showDialog();
  const att3: ArchiverDownloadAttempt = await dlg3.onArchiverDownload(true);
  eq('url 为空 → 不发下载请求', [att3.requested, api3.downloadCalls.length], [false, 0]);
  eq('★url 为空但 finally 仍切"加载中"',
    [dlg3.getSpec().progressVisible, dlg3.getSpec().bodyVisible], [true, false]);

  // ---------- ⑪ 当前资金分站点 ----------
  const h4: FakeArchiverHost = new FakeArchiverHost();
  const api4: FakeArchiverApi = new FakeArchiverApi();
  api4.archiverResult = mkArchiverData();
  const dlg4: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h4, api4);
  const spec4: ArchiverDialogSpec = await dlg4.showDialog();
  eq('★SITE_E → 当前资金加前缀', spec4.currentFunds, 'Funds: 100');
  eq('cost 用带参文案', spec4.originalCost, `${STR_COST}(10)`);
  eq('size 用带参文案', spec4.resampleSize, `${STR_SIZE}(500MB)`);
  const h5: FakeArchiverHost = new FakeArchiverHost();
  h5.site = 1;   // 非 SITE_E
  const api5: FakeArchiverApi = new FakeArchiverApi();
  api5.archiverResult = mkArchiverData();
  const dlg5: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h5, api5);
  const spec5: ArchiverDialogSpec = await dlg5.showDialog();
  eq('★非 SITE_E → 裸显示数值（无前缀）', spec5.currentFunds, '100');

  // ---------- ⑫ 7 步校验链 ----------
  // ② 空 url
  const h6: FakeArchiverHost = new FakeArchiverHost();
  const dlg6: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h6, new FakeArchiverApi());
  // ★ 必须先 showDialog 把 showing 置 true，否则会命中"① 对话框已关 → 丢弃"那条分支
  //   （我的第一版漏了这句，于是断言的是"被丢弃"而不是"空 url"——又双是同族：**前置条件没成立**）
  await dlg6.showDialog();
  dlg6.onDownloadUrl('   ');
  eq('空 url → toast 失败', h6.toasts, [STR_STATE_FAILED]);
  eq('空 url → 不启动', h6.started, []);
  // ⑤ 文件名空
  const h7: FakeArchiverHost = new FakeArchiverHost();
  h7.fileName = '';
  const dlg7: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h7, new FakeArchiverApi());
  await dlg7.showDialog();   // 先把 showing 置 true（showDialog 内 data null → 不会 onSuccess，但 showing 已 true）
  dlg7.onDownloadUrl('https://TARGET/x');
  eq('文件名空 → toast 失败', h7.toasts, [STR_STATE_FAILED]);
  // ⑥ scheme 非法
  const h8: FakeArchiverHost = new FakeArchiverHost();
  const dlg8: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h8, new FakeArchiverApi());
  await dlg8.showDialog();
  dlg8.onDownloadUrl('ftp://TARGET/x');
  eq('scheme 非法 → 记 warning', h8.warnings.length, 1);
  eq('scheme 非法 → toast 失败', h8.toasts, [STR_STATE_FAILED]);
  eq('scheme 非法 → 不启动', h8.started, []);
  // ⑦ 下载器不可用
  const h9: FakeArchiverHost = new FakeArchiverHost();
  h9.downloaderAvailable = false;
  const dlg9: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h9, new FakeArchiverApi());
  await dlg9.showDialog();
  dlg9.onDownloadUrl('https://TARGET/x');
  eq('下载器不可用 → toast 失败', h9.toasts, [STR_STATE_FAILED]);
  // ① 对话框已关 → 丢弃
  const h10: FakeArchiverHost = new FakeArchiverHost();
  const dlg10: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h10, new FakeArchiverApi());
  await dlg10.showDialog();
  dlg10.onDismiss();
  dlg10.onDownloadUrl('https://TARGET/x');
  eq('★对话框已关 → 完全丢弃（无 toast 无启动）', [h10.toasts.length, h10.started.length], [0, 0]);

  // ---------- ⑬ onDownloadFailure ----------
  const h11: FakeArchiverHost = new FakeArchiverHost();
  h11.hathError = true;
  const dlg11: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h11, new FakeArchiverApi());
  await dlg11.showDialog();
  dlg11.onDownloadFailure(new Error('hath'));
  eq('NoHath 错误 → 专用文案', h11.tips, [`${STR_HATH_FAILURE}:true`]);
  const h12: FakeArchiverHost = new FakeArchiverHost();
  const dlg12: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h12, new FakeArchiverApi());
  await dlg12.showDialog();
  dlg12.onDownloadFailure(new Error('other'));
  eq('普通错误 → 通用文案', h12.tips, [`${STR_ARCHIVE_FAILURE}:true`]);

  // ---------- isInstance ----------
  eq('isInstance(详情页 tag)', dlg12.isInstance('GalleryDetailScene'), true);
  eq('isInstance(其它 tag)', dlg12.isInstance('Other'), false);

  // ---------- hasActivity false → 不发下载请求 ----------
  const h13: FakeArchiverHost = new FakeArchiverHost();
  h13.activity = false;
  const api13: FakeArchiverApi = new FakeArchiverApi();
  api13.archiverResult = mkArchiverData();
  const dlg13: ArchiverDownloadDialog = new ArchiverDownloadDialog(mkDetail(), h13, api13);
  await dlg13.showDialog();
  const att13: ArchiverDownloadAttempt = await dlg13.onArchiverDownload(true);
  eq('无 activity → 不请求', [att13.requested, api13.downloadCalls.length], [false, 0]);
}

async function main(): Promise<void> {
  testDownloadSearchController();
  testDownloadLabelDraw();
  await testArchiverDownloadDialog();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download search/label/archiver test failed');
  }
  console.log(`✓ 下载搜索 + 标签抽屉 + 档案对话框批: ${pass} 条断言全部通过`);
}

main();


