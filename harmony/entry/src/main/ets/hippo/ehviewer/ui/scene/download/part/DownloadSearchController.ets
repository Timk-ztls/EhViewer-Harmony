/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/download/part/DownloadSearchController.java
 *       （inventory S0228，上游 248 行；清单登记 196 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/part/DownloadSearchController.ets
 *
 * 背景：下载页的**搜索与筛选控制器**（`SearchBar.Helper` + `SearchBarMover.Helper` + `OnStateChangeListener`
 * 三个接口的实现者）。它自己不画 UI，只驱动：搜索对话框 → 应用搜索 → 后台执行器。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `gotoSearch(context, helper, moverHelper)`：
 *   · **`mSearchDialog != null` → 只 `show()` 并 return**（**不重建** —— 与 DownloadLabelsScene 的
 *     "先 show 再照常重建"不同，这里是真 return）
 *   · 否则建 SearchBar：`setIsComeFromDownload(true)`、hint `@string/download_search_hint`、
 *     左图标 `@drawable/big_download`、**文本 = `host.getSearchKey()`**
 *   · **`searchKey` 非空** → `setTitle(searchKey)` + `cursorToEnd()`；**空/null** → `setTitle(hint)`
 *   · 右图标 `@drawable/v_magnify_x24`；`SearchBarMover(moverHelper, mSearchBar)`
 *   · AlertDialog：message `@string/download_search_gallery`、cancelable true、
 *     **onDismiss → `mSearchMode = false`**
 *     · 负按钮（cancel）：`setSearchKey(null)` + `setText(null)` + `setTitle(null)` +
 *       **`applySearch(true)`**（**取消也会触发一次搜索** —— 用空 key 搜，即"清除筛选"）
 *     · 正按钮（ok）：`applySearch(true)`
 *
 * `startSearching()`：
 *   ① `progressView.VISIBLE` ② `recyclerView != null → GONE`
 *   ③ **`if (mSearchMode)`** → `mSearchMode = false` + `mSearchBar.setTitle(mHost.getSearchKey())` +
 *      `setState(STATE_NORMAL)`（**退出搜索模式要恢复标题**）
 *   ④ `mSearchDialog.dismiss()`
 *   ⑤ `mHost.updateForLabel()`
 *   ⑥ 建 `DownloadListInfosExecutor(mHost.getList(), mHost.getSearchKey())` → 挂 listener → `executeSearching()`
 *
 * `gotoFilterAndSort(id)`：同样 progress VISIBLE + recycler GONE；
 *   但用 **`mHost.getBackList()` + `mHost.getDownloadManager()`** 构造执行器 → `executeFilterAndSort(id)`
 *   —— **注意用的是 backList（原始表），不是 list（已过滤的）**
 *
 * `onClickTitle()`：**`!mSearchMode` 才** `enterSearchMode(true)`（已进入不重复进入）
 * `onClickLeftIcon()`：**空实现**
 * `onClickRightIcon()`：`mSearchBar.applySearch(true)`
 * `onSearchEditTextClick()`：**空实现**
 * `onApplySearch(query)`：`setSearchKey(query)` → `hideKeyBoard()` → **`host.setSearching(true)`** → `startSearching()`
 * `onSearchEditTextBackPressed()`：`mSearchMode` → false；`setState(STATE_NORMAL, true)`
 * `onStateChange(...)`：**空实现**
 * `isValidView(recyclerView)`：**恒 false**
 * `getValidRecyclerView()`：`mHost.getRecyclerView()`
 * `forceShowSearchBar()`：**恒 false**
 *
 * `enterSearchMode(animation)`：**`mSearchMode || mSearchBar == null || mSearchBarMover == null → return`**；
 *   否则 `mSearchMode = true` → `setState(STATE_SEARCH_LIST, animation)` → `mover.returnSearchBarPosition(animation)`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`gotoSearch` 在已有对话框时直接 return**（不重建）；而 `DownloadLabelsScene` 那边是"先 show 再重建"。
 *    同一批里两种写法，**不能统一**。
 * 2. **取消按钮也会 `applySearch(true)`** —— 用空 key 搜索 = 清除筛选。取消不是"什么都不做"。
 * 3. **`onDismiss` 会把 `mSearchMode` 置 false** —— 所以对话框关闭后搜索模式一定退出。
 * 4. **`startSearching` 里"退出搜索模式"的条件是 `mSearchMode`**，且要**先用 host 的 key 恢复标题**再 `setState`。
 * 5. **`gotoFilterAndSort` 用 `getBackList()`（原始表）** 而不是 `getList()`（当前过滤结果）——
 *    筛选/排序必须基于全量，否则会越筛越少。
 * 6. **三个接口方法恒返回固定值**：`isValidView → false`、`forceShowSearchBar → false`、
 *    `getValidRecyclerView → host.getRecyclerView()`（这三个是"接口要求的噪声"，不是逻辑）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `SearchBar` / `SearchBarMover` / `AlertDialog` / `ProgressView` / `MyEasyRecyclerView`
 *    在 ArkUI 无对位 → `SearchHost`（key/searching/progress/recycler/list/backList/executor）。
 * 2. `DownloadListInfosExecutor` **已交付**（download-sync）→ 用 `ExecutorPort` 只钉本文件调用的
 *    `setDownloadSearchingListener` / `executeSearching` / `executeFilterAndSort` 三个方法。
 * 3. 对话框 → `SearchDialogSpec`（纯数据），页面层渲染。
 * 4. `Toast` 不属于本文件（本文件无 toast）。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `DownloadInfo`、`DownloadManager`、`DownloadListInfosExecutor`（`setDownloadSearchingListener` /
 * `executeSearching` / `executeFilterAndSort`）、`hoppo` 布局 `download_search_dialog`。
 */

import { DownloadInfo } from '../../../../dao/DownloadInfo';
import { DownloadManager } from '../../../../download/DownloadManager';

/** 上游 `@string/download_search_hint` / `download_search_gallery` */
export const STR_SEARCH_HINT: string = 'app.string.download_search_hint';
export const STR_SEARCH_GALLERY: string = 'app.string.download_search_gallery';
/** 上游两个图标资源名 */
export const DRAWABLE_BIG_DOWNLOAD: string = 'big_download';
export const DRAWABLE_MAGNIFY: string = 'v_magnify_x24';
/** 上游 `SearchBar.STATE_NORMAL` / `STATE_SEARCH_LIST` */
export const SEARCH_STATE_NORMAL: number = 0;
export const SEARCH_STATE_SEARCH_LIST: number = 1;

/** 执行器端口（只钉本文件实际调用的方法，见「平台差异」2） */
export interface ExecutorPort {
  setDownloadSearchingListener(callback: Object | null): void;
  executeSearching(): void;
  executeFilterAndSort(id: number): void;
}

/** 上游 `Host` 接口（照搬形状） */
export interface SearchHost {
  getSearchKey(): string | null;
  setSearchKey(key: string | null): void;
  setSearching(searching: boolean): void;
  getList(): DownloadInfo[] | null;
  /** ★ 用于筛选/排序的**原始表**（见「关键行为」5） */
  getBackList(): DownloadInfo[] | null;
  getDownloadManager(): DownloadManager | null;
  updateForLabel(): void;
  /** 上游 `getDownloadSearchCallback()`（`DownloadSearchCallback`） */
  getSearchCallback(): Object | null;
  /** 页面层能力 */
  setProgressVisible(visible: boolean): void;
  setRecyclerViewVisible(visible: boolean): void;
  /** 构造执行器（上游 `new DownloadListInfosExecutor(list, key)` / `(backList, dm)`） */
  newExecutor(list: DownloadInfo[] | null, key: string | null): ExecutorPort;
  newExecutorForFilter(list: DownloadInfo[] | null, dm: DownloadManager | null): ExecutorPort;
  /** SearchBar 视图能力 */
  setSearchBarText(text: string | null): void;
  setSearchBarTitle(text: string | null): void;
  setSearchBarState(state: number, animation: boolean): void;
  cursorToEnd(): void;
  hideKeyboard(): void;
  applySearch(animation: boolean): void;
  /** `SearchBarMover.returnSearchBarPosition(animation)` */
  returnSearchBarPosition(animation: boolean): void;
  /** 页面层"弹/关搜索对话框"（本文件只产出描述） */
  showSearchDialog(spec: SearchDialogSpec): void;
  dismissSearchDialog(): void;
}

/** 搜索对话框描述（上游 AlertDialog + SearchBar 的纯数据对位） */
export class SearchDialogSpec {
  messageKey: string = STR_SEARCH_GALLERY;
  hintKey: string = STR_SEARCH_HINT;
  /** SearchBar 的初始文本 = `host.getSearchKey()` */
  text: string = '';
  /** 标题：key 非空 → key；否则 hint */
  title: string = '';
  leftDrawable: string = DRAWABLE_BIG_DOWNLOAD;
  rightDrawable: string = DRAWABLE_MAGNIFY;
  cancelable: boolean = true;
}

export class DownloadSearchController {
  private host: SearchHost;
  /** 上游 `mSearchDialog != null` 的等价（见「关键行为」1） */
  private dialogVisible: boolean = false;
  /** 上游 `mSearchMode` */
  private searchMode: boolean = false;
  /** 上游 `mSearchBar` / `mSearchBarMover` 是否就绪 */
  private barReady: boolean = false;

  constructor(host: SearchHost) {
    this.host = host;
  }

  /** 是否处于搜索模式（测试观测） */
  isSearchMode(): boolean {
    return this.searchMode;
  }

  /**
   * 上游 `gotoSearch(...)`：
   * **已有对话框 → 只 show 并 return**（不重建）；否则产出对话框描述。
   */
  gotoSearch(): SearchDialogSpec | null {
    if (this.dialogVisible) {
      return null;   // 上游：mSearchDialog.show(); return; —— 由页面层显示已存在的那个
    }
    const spec: SearchDialogSpec = new SearchDialogSpec();
    const key: string | null = this.host.getSearchKey();
    spec.text = key === null ? '' : key;
    // 上游：key 非空 → setTitle(key) + cursorToEnd()；否则 setTitle(hint)
    if (key !== null && key.length > 0) {
      spec.title = key;
    } else {
      spec.title = STR_SEARCH_HINT;
    }
    this.barReady = true;
    this.dialogVisible = true;
    this.host.showSearchDialog(spec);
    return spec;
  }

  /** 上游 `onSearchDialogDismiss`：**`mSearchMode = false`**（见「关键行为」3） */
  onSearchDialogDismiss(): void {
    this.searchMode = false;
    this.dialogVisible = false;
  }

  /** 上游 `enterSearchMode(animation)`：三重防御后才进入 */
  enterSearchMode(animation: boolean): boolean {
    if (this.searchMode || !this.barReady) {
      return false;
    }
    this.searchMode = true;
    this.host.setSearchBarState(SEARCH_STATE_SEARCH_LIST, animation);
    this.host.returnSearchBarPosition(animation);
    return true;
  }

  /**
   * 上游 `startSearching()`：
   * ① progress VISIBLE ② recycler GONE ③ **`mSearchMode` 时退出并恢复标题** ④ dismiss ⑤ updateForLabel ⑥ 执行器
   */
  startSearching(): void {
    this.host.setProgressVisible(true);
    this.host.setRecyclerViewVisible(false);

    if (this.searchMode) {
      this.searchMode = false;
      // 上游：mSearchBar.setTitle(mHost.getSearchKey())
      this.host.setSearchBarTitle(this.host.getSearchKey());
      this.host.setSearchBarState(SEARCH_STATE_NORMAL, false);
    }

    this.host.dismissSearchDialog();
    this.dialogVisible = false;
    this.host.updateForLabel();

    const key: string | null = this.host.getSearchKey();
    const executor: ExecutorPort = this.host.newExecutor(this.host.getList(), key);
    executor.setDownloadSearchingListener(this.host.getSearchCallback());
    executor.executeSearching();
  }

  /** 上游 `gotoFilterAndSort(id)`：**用 getBackList()（原始表）**，见「关键行为」5 */
  gotoFilterAndSort(id: number): void {
    this.host.setProgressVisible(true);
    this.host.setRecyclerViewVisible(false);

    const executor: ExecutorPort =
      this.host.newExecutorForFilter(this.host.getBackList(), this.host.getDownloadManager());
    executor.setDownloadSearchingListener(this.host.getSearchCallback());
    executor.executeFilterAndSort(id);
  }

  /** 上游 `onClickTitle()`：**`!mSearchMode` 才**进入 */
  onClickTitle(): boolean {
    if (!this.searchMode) {
      return this.enterSearchMode(true);
    }
    return false;
  }

  /** 上游 `onClickLeftIcon()`（**空实现**） */
  onClickLeftIcon(): void {
  }

  /** 上游 `onClickRightIcon()`：触发搜索 */
  onClickRightIcon(): void {
    this.host.applySearch(true);
  }

  /** 上游 `onSearchEditTextClick()`（**空实现**） */
  onSearchEditTextClick(): void {
  }

  /**
   * 上游 `onApplySearch(query)`：
   * 存 key → 收键盘 → **`setSearching(true)`** → `startSearching()`
   */
  onApplySearch(query: string): void {
    this.host.setSearchKey(query);
    this.host.hideKeyboard();
    this.host.setSearching(true);
    this.startSearching();
  }

  /** 上游 `onSearchEditTextBackPressed()` */
  onSearchEditTextBackPressed(): void {
    if (this.searchMode) {
      this.searchMode = false;
    }
    this.host.setSearchBarState(SEARCH_STATE_NORMAL, true);
  }

  /** 上游对话框**取消**按钮：`setSearchKey(null)` + 清文本/标题 + **`applySearch(true)`**（见「关键行为」2） */
  onDialogCancel(): void {
    this.host.setSearchKey(null);
    this.host.setSearchBarText(null);
    this.host.setSearchBarTitle(null);
    // ★ 取消也会触发一次搜索（空 key = 清除筛选）
    this.host.applySearch(true);
    this.host.dismissSearchDialog();
    this.dialogVisible = false;
  }

  /** 上游对话框**确认**按钮：`applySearch(true)` */
  onDialogConfirm(): void {
    this.host.applySearch(true);
    this.host.dismissSearchDialog();
    this.dialogVisible = false;
  }

  /** 上游 `onStateChange(...)`（**空实现**） */
  onStateChange(newState: number, oldState: number, animation: boolean): void {
  }

  /** 上游 `isValidView(recyclerView)` → **恒 false**（见「关键行为」6） */
  isValidView(): boolean {
    return false;
  }

  /** 上游 `getValidRecyclerView()` */
  getValidRecyclerViewReady(): boolean {
    return true;   // host.getRecyclerView() 存在性由页面层保证
  }

  /** 上游 `forceShowSearchBar()` → **恒 false** */
  forceShowSearchBar(): boolean {
    return false;
  }
}
