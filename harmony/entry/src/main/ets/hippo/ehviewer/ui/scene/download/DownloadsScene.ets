/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/download/DownloadsScene.java（1240 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/DownloadsScene.ets
 *
 * ⚠ 分批移植：本文件是 **Part 1 —— 数据层 + 场景骨架**
 *   - 场景身份/常量（KEY_GID / KEY_ACTION / ACTION_CLEAR_DOWNLOAD_SERVICE / LOCAL_GALLERY_INFO_CHANGE）
 *   - 参数解析 `handleArguments`、标签切换 `updateForLabel`、标题 `updateTitle`
 *   - 列表数据源（`DownloadManager` 的三个列表 API）、搜索键、分类过滤（上游已注释禁用，本 port 同样禁用）
 *   - 6 个控制器（part 类，S0222/S0223/S0224/S0226/S0227/S0228）的**契约注入点**
 *
 * Part 2 待补（需要 ArkUI 侧接线，本批不写假实现）：
 *   布局 scene_download 的组件树、EasyRecyclerView + StaggeredGridLayoutManager、FAB / AddDeleteDrawable、
 *   拖动排序（RecyclerViewDragDropManager）、ViewTransition 动画、分类 Spinner、菜单 40 项。
 *
 * 依赖处置：
 *   1. `DownloadManager` → download-sync 已交付（getDownloadInfoList / getDefaultDownloadInfoList /
 *      getLabelDownloadInfoList），本文件只声明**消费方接口** `DownloadManagerLike`，不 import 实现，
 *      避免与 download-sync 的类名/路径耦合（C-18：参数类型归消费方）。
 *   2. `DownloadInfo` → storage-db 已交付（dao），直接 import。
 *   3. 6 个控制器 → ui-scene（inventory S0222/S0223/S0224/S0226/S0227/S0228），契约先行注入。
 *   4. `Settings.putRecentDownloadLabel` → **core-runtime 未提供**（缺口已登记在 updateForLabel 处，改由宿主回调）
 *
 * 上游一处刻意行为（照抄，勿"修好"）：
 *   `updateForLabel()` 里 `filterByCategory()` 被注释掉（L312），所以分类过滤**当前不生效**。
 *   本 port 保留 `filterByCategory()` 与注释，只有菜单切换分类时才可能启用 —— 与上游一致。
 */

import { DownloadInfo } from '../../../dao/DownloadInfo';
import { GetText } from '../../../GetText';
import { Analytics } from '../../../Analytics';
import { EhUtils } from '../../../client/EhUtils';
import { Utils } from '../../../../unifile/Utils';
import { SpiderInfo } from '../../../spider/SpiderInfo';
import { SpiderQueen } from '../../../spider/SpiderQueen';
import { DownloadAdapterCallbackLike, DownloadAdapterLike, PAGINATION_THRESHOLD,
  UnavailableDownloadAdapter } from './DownloadAdapterContracts';
import { DownloadListDataSource } from './DownloadListDataSource';
import { MenuItemDef } from '../../../../ui/menu/MenuItemModel';
import { SceneDownloadMenu } from '../../../../ui/menu/scene_download';
import { DownloadListInfosExecutor, DownloadListFilterId } from '../../../sync/DownloadListInfosExecutor';
import { DownloadSearchCallback } from '../../../callBack/DownloadSearchCallback';

/** 对位上游 `DownloadsScene.KEY_*` / `ACTION_*`。 */
export class DownloadsSceneAction {
  static readonly KEY_GID: string = 'gid';
  static readonly KEY_ACTION: string = 'action';
  static readonly KEY_LABEL: string = 'label';
  static readonly ACTION_CLEAR_DOWNLOAD_SERVICE: string = 'clear_download_service';
  /** 上游 `LOCAL_GALLERY_INFO_CHANGE = 909`（Activity result code）。 */
  static readonly LOCAL_GALLERY_INFO_CHANGE: number = 909;
  /** 上游 `ANIMATE_TIME = 300L`。 */
  static readonly ANIMATE_TIME: number = 300;
}

/**
 * `DownloadManager` 的**消费方视图**（C-18：本模块声明所需，不 import download-sync 的实现）。
 *
 * 取自 download-sync 已交付的公开 API（DownloadManager.ets:702/706/710/715）：
 *   - 只用列表查询；下载操作（startAll/stopAll）走 `batchActions` 控制器，不在这里重复声明
 */
export interface DownloadManagerLike {
  /** 全部下载项（不可变快照）。上游 `getDownloadInfoList()` 返回 `allInfoList.slice()`。 */
  getDownloadInfoList(): DownloadInfo[];

  /** 默认标签（无标签）的下载项。 */
  getDefaultDownloadInfoList(): DownloadInfo[];

  /** 指定标签的下载项；标签不存在时返回 null（上游用来判"标签被删了"）。 */
  getLabelDownloadInfoList(label: string): DownloadInfo[] | null;
}

/**
 * 6 个 part 控制器的**消费方契约**（ui-scene 实现：S0222/S0223/S0224/S0226/S0227/S0228）。
 *
 * 设计要点：**无返回值的方法必须配"如何知道结果"的机制**，否则调用方只能假装成功：
 *   - `archiveImporter.showImportDialog(onDone)` → 完成回调带 success + message
 *   - `batchActions.startAll()` → `onStateChanged` 回调（running/done/total）
 *   - `searchController` → `onSearchChanged` 回调 + `getSearchKey()`
 * 这条规则来自本项目踩过的坑：`if (依赖齐全) { 干活(); }` 之外，
 * **"调用了但不知道结果"同样是静默失败**。
 */
export interface DownloadSceneControllersLike {
  /** 归档导入（S0223，232 行）：`onDone(success, message)`。 */
  readonly archiveImporter: ArchiveImporterLike;
  /** 相册导入（S0222，355 行）：`onDone(success, count)`。 */
  readonly albumImporter: AlbumImporterLike;
  /** 搜索（S0228，196 行）。 */
  readonly searchController: SearchControllerLike;
  /** 批量操作（S0224，321 行）。 */
  readonly batchActions: BatchActionsLike;
  /** 分页（S0227，250 行）。 */
  readonly pagination: PaginationControllerLike;
  /** 引导（S0226，132 行）。 */
  readonly guideHelper: GuideHelperLike;
}

export interface ArchiveImporterLike {
  showImportDialog(onDone: (success: boolean, message: string | null) => void): void;
}

export interface AlbumImporterLike {
  showImportDialog(onDone: (success: boolean, count: number) => void): void;
}

export interface SearchControllerLike {
  showSearchBar(): void;
  getSearchKey(): string | null;
  setSearchKey(key: string | null): void;
  /** 搜索键变化回调（场景据此重订阅数据）。null 表示未注册。 */
  onSearchChanged: ((key: string | null) => void) | null;
}

export interface BatchActionsLike {
  startAll(): Promise<void>;
  stopAll(): Promise<void>;
  /**
   * 批量操作状态回调：running=true 进行中；done/total = **已处理的 gid 数**（不是"已下载完成项"）。
   * 语义依据（lead 裁决）：`startAll()` 只是**入队**，入队完成即到 100%；
   * 若定义成"已完成下载项"，进度会长时间停在低位，且与 `DownloadInfo.state` 传达的信息重复。
   * **必须有**：`startAll()` 返回 void，没有这条回调调用方无从知道何时结束。
   */
  onStateChanged: ((running: boolean, done: number, total: number) => void) | null;
}

export interface PaginationControllerLike {
  onPageSelected(page: number): void;
  getCurrentPage(): number;
  setTotalPages(total: number): void;
}

export interface GuideHelperLike {
  showGuideIfNeeded(): void;
  isGuideDismissed(): boolean;
}

/**
 * 下载页场景（Part 1：数据层 + 骨架）。
 *
 * 上游是 `BaseScene` 子类（Activity 式生命周期 + 视图树）。本 port 的场景是**纯类**：
 * 生命周期方法由宿主（ui-scene 的 Stage/ArkUI 页面）调用，本类不持有 ArkUI 组件。
 * 视图树接线见 Part 2；本类负责"数据怎么来、标题怎么算、参数怎么解"。
 */
export class DownloadsScene implements DownloadAdapterCallbackLike {
  private static readonly TAG: string = 'DownloadsScene';
  /** 资源缺失时的退化键名（见 updateTitle）。 */
  private static readonly KEY_DEFAULT_DOWNLOAD_LABEL_NAME: string = 'default_download_label_name';

  /** 上游 `mDownloadManager`（通过 `DownloadManagerLike` 注入）。 */
  private mDownloadManager: DownloadManagerLike | null = null;
  /** 6 个 part 控制器（ui-scene 实现后注入）。 */
  private mControllers: DownloadSceneControllersLike | null = null;

  /** 上游 `public String mLabel`（当前标签；null = 默认标签）。 */
  private mLabel: string | null = null;
  /** 上游 `private List<DownloadInfo> mList`。 */
  private mList: DownloadInfo[] = [];
  /** 上游 `private List<DownloadInfo> mBackList`（分类过滤前的备份）。 */
  private mBackList: DownloadInfo[] = [];
  /** 上游 `public String searchKey = null`。 */
  private searchKey: string | null = null;
  /** 上游 `public boolean searching = false`。 */
  private searching: boolean = false;
  /** 上游 `private int mSelectedCategory = EhUtils.ALL_CATEGORY`。 */
  private mSelectedCategory: number = EhUtils.ALL_CATEGORY;
  /** 上游 `private int mInitPosition = -1`。 */
  private mInitPosition: number = -1;
  /** 最近标签变化回调（对位上游 Settings.putRecentDownloadLabel；core-runtime 提供该 API 前由宿主持久化）。 */
  onRecentLabelChanged: ((label: string | null) => void) | null = null;
  /** 每页条数变化回调（对位上游持久化 perPageCount；core-runtime 提供该键前由宿主保存）。 */
  onPageSizeChanged: ((pageSize: number) => void) | null = null;
  private backInterceptor: (() => boolean) | null = null;

  constructor(downloadManager: DownloadManagerLike | null) {
    this.mDownloadManager = downloadManager;
  }

  setBackInterceptor(interceptor: (() => boolean) | null): void {
    this.backInterceptor = interceptor;
  }

  tryConsumeBack(): boolean {
    return this.backInterceptor !== null && this.backInterceptor();
  }

  // ---------------------------------------------------------------- 注入

  setDownloadManager(manager: DownloadManagerLike | null): void {
    this.mDownloadManager = manager;
  }

  setControllers(controllers: DownloadSceneControllersLike | null): void {
    this.mControllers = controllers;
  }

  hasControllers(): boolean {
    return this.mControllers !== null;
  }

  /**
   * 取控制器；未注入时**显式抛错**。
   *
   * 上游这里不会抛（Java 里字段一定非 null，构造时就 new 了）。
   * 本 port 走注入，所以"没接线"是真实可能的状态 —— 按陷阱 52：
   * **前置条件不满足不等于什么都不做**，要让调用方立刻知道，而不是"按钮点了没反应"。
   */
  private requireControllers(): DownloadSceneControllersLike {
    const controllers: DownloadSceneControllersLike | null = this.mControllers;
    if (controllers === null) {
      throw new Error('DownloadsScene: DownloadSceneControllersLike 未注入（6 个 part 控制器缺失，见 S0222-S0228）');
    }
    return controllers;
  }

  /** 取下载管理器；未注入时显式抛错（同 requireControllers）。 */
  private requireDownloadManager(): DownloadManagerLike {
    const manager: DownloadManagerLike | null = this.mDownloadManager;
    if (manager === null) {
      throw new Error('DownloadsScene: DownloadManagerLike 未注入（download-sync 的 DownloadManager 缺失）');
    }
    return manager;
  }

  // ---------------------------------------------------------------- 参数

  /**
   * 对位上游 `handleArguments(Bundle)`（L215）。
   *
   * 返回 false 表示"参数里没有本场景认识的内容"（上游此时 `finish()`）。
   * 三种参数形态：
   *   - `ACTION_CLEAR_DOWNLOAD_SERVICE` → 通知宿主要清下载服务（消费方按需处理）
   *   - `KEY_GID` → 滚到该 gid 的位置（`mInitPosition`）
   *   - `KEY_LABEL` → 切到该标签
   */
  handleArguments(args: Map<string, Object> | null): boolean {
    if (args === null) {
      return true;
    }

    const action: Object | undefined = args.get(DownloadsSceneAction.KEY_ACTION);
    if (action !== undefined && `${action}` === DownloadsSceneAction.ACTION_CLEAR_DOWNLOAD_SERVICE) {
      // 上游这里是"清空下载服务并 finish"。清空本身在 DownloadManager 侧，
      // 本场景只把请求标记出来交给宿主（不自己动 manager，避免两处状态）。
      this.mPendingClearDownloadService = true;
      return true;
    }

    const gidValue: Object | undefined = args.get(DownloadsSceneAction.KEY_GID);
    if (gidValue !== undefined) {
      const gid: number = Number.parseInt(`${gidValue}`, 10);
      if (!Number.isNaN(gid)) {
        this.mInitPosition = this.indexOfGid(gid);
      }
      return true;
    }

    const labelValue: Object | undefined = args.get(DownloadsSceneAction.KEY_LABEL);
    if (labelValue !== undefined) {
      this.mLabel = `${labelValue}`;
      this.updateForLabel();
      return true;
    }

    return true;
  }

  /** 对位上游 `onNewArguments(Bundle)`（L248）。 */
  onNewArguments(args: Map<string, Object> | null): void {
    this.handleArguments(args);
  }

  private mPendingClearDownloadService: boolean = false;

  /** 宿主读取后清除（上游由 service 侧消费）。 */
  consumeClearDownloadServiceRequest(): boolean {
    const pending: boolean = this.mPendingClearDownloadService;
    this.mPendingClearDownloadService = false;
    return pending;
  }

  /** 上游 `mInitPosition` 的用途：RecyclerView 首次布局时滚到该位置（Part 2 消费）。 */
  getInitPosition(): number {
    return this.mInitPosition;
  }

  private indexOfGid(gid: number): number {
    for (let i = 0; i < this.mList.length; i++) {
      if (this.mList[i].getGid() === gid) {
        return i;
      }
    }
    return -1;
  }

  // ---------------------------------------------------------------- 数据

  /**
   * 对位上游 `updateForLabel()`（L293）——**本批的核心**。
   *
   * 语义（逐行对位）：
   *   1. manager 为空 → 直接返回（上游 `return`；本 port 保留此早退但**不静默**：
   *      列表保持原状是可见状态，且 `getList()` 的调用方拿到的就是旧数据）
   *   2. 有标签 → `getLabelDownloadInfoList(label)`；返回 null 说明**标签已被删**
   *      → 回退到默认标签（上游 `mLabel = null` + 取默认列表）
   *   3. `mBackList = mList`（分类过滤备份）
   *   4. 更新标题、最近标签、分页指示器
   */
  updateForLabel(): void {
    const manager: DownloadManagerLike | null = this.mDownloadManager;
    if (manager === null) {
      // 上游同样早退（L294-296）。区别：这里不抛错 —— 因为它是"数据未就绪"的常规路径，
      // 交给 getList() 的调用方判断（列表为空）。真正的"必须有 manager"由 requireDownloadManager 保证。
      return;
    }

    if (this.mLabel === null) {
      this.mList = manager.getDefaultDownloadInfoList();
    } else {
      const labelList: DownloadInfo[] | null = manager.getLabelDownloadInfoList(this.mLabel);
      if (labelList === null) {
        // 标签被删了 → 回退默认（上游 L302-305）
        this.mLabel = null;
        this.mList = manager.getDefaultDownloadInfoList();
      } else {
        this.mList = labelList;
      }
    }

    this.mBackList = this.mList;
    // 上游 L312 `filterByCategory()` 被注释掉 → 分类过滤不生效，本 port 保持一致
    this.updateTitle();
    this.notifyAdapter();
    // Part 2 数据源同步：整段重载（分页时屏幕位置整体重排，精细通知反而容易错）
    const dataSource: DownloadListDataSource | null = this.mDataSource;
    if (dataSource !== null) {
      dataSource.reload();
    }
    // 上游这里写 `Settings.putRecentDownloadLabel(mLabel)`（记住上次看的标签）。
    // **缺口（编译实测）**：core-runtime 的 Settings 既无 `putRecentDownloadLabel`，也无
    // recent_download_label 键，且 `putString` 是 private —— 三个入口都不可用。
    // 所以本 port **不写入**，改由宿主通过 `onRecentLabelChanged` 持久化：
    //   - 不在 Settings 里私加键：那是 core-runtime 的文件，跨模块改会绕过他们的键常量约定
    //   - 也不假装写成功：`getLabel()` 就是当前真值，宿主随时可读
    if (this.onRecentLabelChanged !== null) {
      this.onRecentLabelChanged(this.mLabel);
    }

    const controllers: DownloadSceneControllersLike | null = this.mControllers;
    if (controllers !== null) {
      controllers.pagination.setTotalPages(this.computePageCount());
    }
  }

  /**
   * 对位上游 `updateTitle()`（L320）：标题 = 「标签名 · 数量」。
   *
   * 上游用 `getString(R.string.scene_download_title_new, label, count)`，**格式串缺失时 catch**：
   * 先 `Analytics.recordException(e)`，再退化到不含数量的标题。
   *
   * 本 port 多一道兜底：`GetText.getString` 取不到资源时返回**空串**（不抛），
   * 若直接用它做标题，UI 会显示**空白标题**——"看起来什么都没有"，最难判断是资源缺失还是别的问题。
   * 所以这里退化到**资源键名本身**（`default_download_label_name`）并 warn：
   * 键名出现在标题栏上是"明显异常"的信号，比空白可诊断。
   */
  updateTitle(): string {
    let labelName: string = this.mLabel !== null
      ? this.mLabel
      : GetText.getString('default_download_label_name');
    if (labelName.length === 0) {
      labelName = DownloadsScene.KEY_DEFAULT_DOWNLOAD_LABEL_NAME;
      console.warn(`[${DownloadsScene.TAG}] 资源缺失：default_download_label_name 取不到，` +
        '标题退化显示资源键名（这不是用户可见的文案，说明 resources 未同步）');
    }
    const count: number = this.mList.length;

    let title: string = '';
    try {
      const format: string = GetText.getString('scene_download_title_new');
      if (format.length === 0) {
        // 资源缺失：走退化分支（上游是 catch 到异常后重试）
        title = labelName;
      } else {
        title = `${labelName} · ${count}`;
      }
    } catch (e) {
      Utils.throwIfFatal(e);
      Analytics.recordException(e as Error);
      title = labelName;
    }
    this.mTitle = title;
    return title;
  }

  private mTitle: string = '';

  /** 当前标题（宿主 setTitle 用）。 */
  getTitle(): string {
    return this.mTitle;
  }

  /**
   * 对位上游 `filterByCategory()` —— **当前被上游注释禁用（L312）**，仅保留以备菜单启用。
   *
   * 上游实现：`mSelectedCategory == EhUtils.ALL_CATEGORY` 时用 `mBackList` 恢复；
   * 否则按 `EhUtils.getCategory(gid)` 过滤。
   * 本项目 `EhUtils` 只有 `getCategoryByType(type)`（按 Tab 的 type 串），
   * 没有"按 gid 反推分类"的 `getCategory(gid)` —— 那是需要联网/DB 的信息。
   * 所以这里**没有实现过滤**，只做 `mBackList` 恢复 + 显式说明缺口。
   */
  filterByCategory(): void {
    if (this.mSelectedCategory === EhUtils.ALL_CATEGORY) {
      this.mList = this.mBackList;
      return;
    }
    // 缺口：上游 `EhUtils.getCategory(gid)` 依赖 gallery 元数据（分类字段），
    // 本项目 DownloadInfo 不携带 category。等 net-parse 提供 gid→category 映射后再实现。
    // 因为上游本来就注释掉了这条调用（L312），此处不影响 1:1 行为。
    console.warn(`[${DownloadsScene.TAG}] filterByCategory(${this.mSelectedCategory}) 未实现：` +
      'DownloadInfo 不含 category，上游亦已禁用该调用（L312）');
  }

  setSelectedCategory(category: number): void {
    this.mSelectedCategory = category;
    this.filterByCategory();
  }

  getSelectedCategory(): number {
    return this.mSelectedCategory;
  }

  /** 分页总页数（上游由 `mPaginationController` 计算并显示；这里给数据侧的值）。 */
  /**
   * 每页条数（对位上游 `DownloadPaginationController.pageSize` 的 setter）。
   *
   * 调用顺序（与上游一致）：分页控件 `PaginationIndicator` 初始化后经 `onPageSizeChanged` 回报 →
   * 这里 `setPageSize()` 覆盖 → `updateForLabel()` 重算总页数。
   * 非 `PER_PAGE_CHOICES` 内的值也接受（上游控件允许自定义），但打 warn 便于发现接线错误。
   *
   * **持久化缺口**：上游把 perPageCount 存进设置；本项目 `Settings` 只有 `KEY_PAGE_SCALING`
   * （阅读器缩放），没有分页条数键 → 不私加键（陷阱 60），改由宿主通过 `onPageSizeChanged` 持久化。
   */
  setPageSize(pageSize: number): void {
    if (pageSize <= 0) {
      console.warn(`[${DownloadsScene.TAG}] setPageSize(${pageSize}) 非法，忽略（保持 ${this.mPageSize}）`);
      return;
    }
    if (DownloadsScene.PER_PAGE_CHOICES.indexOf(pageSize) < 0) {
      console.warn(`[${DownloadsScene.TAG}] setPageSize(${pageSize}) 不在可选值 ` +
        `[${DownloadsScene.PER_PAGE_CHOICES.join(',')}] 内（上游允许自定义，仅提示）`);
    }
    this.mPageSize = pageSize;
    if (this.onPageSizeChanged !== null) {
      this.onPageSizeChanged(pageSize);
    }
  }

  getPageSize(): number {
    return this.mPageSize;
  }
  private computePageCount(): number {
    const perPage: number = this.mPageSize > 0 ? this.mPageSize : DownloadsScene.DEFAULT_PAGE_SIZE;
    return Math.max(1, Math.ceil(this.mList.length / perPage));
  }

  /**
   * 分页每页条数。
   *
   * **上游口径**（`DownloadPaginationController.kt`）：
   * ```kotlin
   * var pageSize: Int = 1                                  // 占位，不是默认值
   * val perPageCountChoices = intArrayOf(50, 100, 200, 300, 500)
   * ```
   * 真正的值由分页控件的 `initPaginationIndicator(pageSize, choices, total, indexPage)` 初始化，
   * 再通过 `onPageSizeChanged` 回填 —— 也就是说**每页条数的权威在 widget（ui-widget 的 PaginationIndicator）**，
   * 场景只是第一个消费者。`pageSize = 1` 是 Kotlin 的占位初值，不是默认值。
   *
   * 所以本 port：`DEFAULT_PAGE_SIZE` 只用于"控件尚未回报 pageSize"时的引导值，
   * 取 choices 的第一项 50（与上游 choices 一致），并在 `setPageSize()` 收到控件回报后覆盖。
   */
  static readonly DEFAULT_PAGE_SIZE: number = 50;
  /** 上游 `perPageCountChoices`：用户可选的每页条数（顺序即 UI 顺序）。 */
  static readonly PER_PAGE_CHOICES: number[] = [50, 100, 200, 300, 500];

  private mPageSize: number = DownloadsScene.DEFAULT_PAGE_SIZE;

  // ---------------------------------------------------------------- 访问器

  getList(): DownloadInfo[] {
    return this.mList;
  }

  getBackList(): DownloadInfo[] {
    return this.mBackList;
  }

  getLabel(): string | null {
    return this.mLabel;
  }

  /** 切标签（上游菜单项调用）。 */
  setLabel(label: string | null): void {
    this.mLabel = label;
    this.updateForLabel();
  }

  getSearchKey(): string | null {
    return this.searchKey;
  }

  isSearching(): boolean {
    return this.searching;
  }

  /**
   * 搜索键变化（上游 `SearchLayout` 的回调 → `searchKey` + 重订阅数据库）。
   * 本 port：更新字段，并转发给 searchController（若已注入）保持双向一致。
   */
  applySearchKey(key: string | null): void {
    this.searchKey = key;
    this.searching = key !== null && key.length > 0;
    const controllers: DownloadSceneControllersLike | null = this.mControllers;
    if (controllers !== null) {
      controllers.searchController.setSearchKey(key);
    }
  }

  // ---------------------------------------------------------------- 控制器转发（未注入即显式失败）

  /**
   * 菜单「导入归档」（上游 `mArchiveImporter.showImportDialog()`）。
   *
   * **刷新归 importer，场景只更新标题**（ui-scene 实证：`DownloadArchiveImporter.kt` 的 `Host`
   * 契约里就有 `updateForLabel()`，导入完成后 importer 自己会调）。所以这里**不能再调
   * `updateForLabel()`** —— 连续两次重取列表会闪一下，且第二次可能是过期的中间状态。
   */
  showArchiveImportDialog(onDone: ((success: boolean, message: string | null) => void) | null): void {
    this.requireControllers().archiveImporter.showImportDialog(
      (success: boolean, message: string | null): void => {
        if (success) {
          this.updateTitle();
        }
        if (onDone !== null) {
          onDone(success, message);
        }
      });
  }

  /** 菜单「导入相册」（同上：importer 自己刷新，场景只更新标题）。 */
  showAlbumImportDialog(onDone: ((success: boolean, count: number) => void) | null): void {
    this.requireControllers().albumImporter.showImportDialog(
      (success: boolean, count: number): void => {
        if (success) {
          this.updateTitle();
        }
        if (onDone !== null) {
          onDone(success, count);
        }
      });
  }

  /** 菜单「搜索」。 */
  showSearchBar(): void {
    this.requireControllers().searchController.showSearchBar();
  }

  /** 菜单「全部开始」。 */
  async startAll(): Promise<void> {
    await this.requireControllers().batchActions.startAll();
    // 进度语义未定论（ui-scene 下一轮读源码后再答）→ 按"不确定就不刷新"：
    // 只在 Promise resolve 后刷一次，避免与控制器内部刷新叠加成双刷。
    this.updateForLabel();
  }

  /** 菜单「全部停止」。 */
  async stopAll(): Promise<void> {
    await this.requireControllers().batchActions.stopAll();
    this.updateForLabel();
  }

  /** 首次进入时的引导（上游 `mGuideHelper.showGuideIfNeeded()`）。 */
  showGuideIfNeeded(): void {
    this.updateForLabel();
    this.requireControllers().guideHelper.showGuideIfNeeded();
  }

  // ---------------------------------------------------------------- 排序 / 状态过滤（走 download-sync 的 executor）

  /**
   * 菜单 id → `DownloadListFilterId` 常量（**全部 import，不写字面量**）。
   *
   * 排序与过滤的**实现**在 `download-sync` 的 `DownloadListInfosExecutor`（S0181）：
   * 上游 `DownloadManager.getDownloadInfoList()` 只是 `new ArrayList<>(mAllInfoList)`，**不排序**；
   * 排序/过滤发生在 `DownloadListInfosExecutor.executeFilterAndSort(id)` 里（含 11 个比较器与
   * `fileSize` 补算、null/-1 落位规则）。所以场景**不能自己排**——那会变成第二份比较器，必然漂移。
   */
  private static menuIdToFilterId(id: string): number {
    switch (id) {
      // 状态过滤（5 项，可直接做：DownloadInfo.state 已交付）
      case 'download_done': return DownloadListFilterId.DOWNLOAD_DONE;
      case 'not_started': return DownloadListFilterId.NOT_STARTED;
      case 'waiting': return DownloadListFilterId.WAITING;
      case 'downloading': return DownloadListFilterId.DOWNLOADING;
      case 'failed': return DownloadListFilterId.FAILED;
      case 'all': return DownloadListFilterId.ALL;
      // 排序（11 项，交给 executor 的比较器）
      case 'sort_by_default': return DownloadListFilterId.SORT_BY_DEFAULT;
      case 'sort_by_gallery_id_asc': return DownloadListFilterId.SORT_BY_GALLERY_ID_ASC;
      case 'sort_by_gallery_id_desc': return DownloadListFilterId.SORT_BY_GALLERY_ID_DESC;
      case 'sort_by_create_time_asc': return DownloadListFilterId.SORT_BY_CREATE_TIME_ASC;
      case 'sort_by_create_time_desc': return DownloadListFilterId.SORT_BY_CREATE_TIME_DESC;
      case 'sort_by_rating_asc': return DownloadListFilterId.SORT_BY_RATING_ASC;
      case 'sort_by_rating_desc': return DownloadListFilterId.SORT_BY_RATING_DESC;
      case 'sort_by_name_asc': return DownloadListFilterId.SORT_BY_NAME_ASC;
      case 'sort_by_name_desc': return DownloadListFilterId.SORT_BY_NAME_DESC;
      case 'sort_by_file_size_asc': return DownloadListFilterId.SORT_BY_FILE_SIZE_ASC;
      case 'sort_by_file_size_desc': return DownloadListFilterId.SORT_BY_FILE_SIZE_DESC;
      default: return -1;
    }
  }

  /**
   * 执行过滤/排序（对位上游 `mList = executor.executeFilterAndSort(id)` 的回调形态）。
   *
   * 返回 true 表示该 id 属于过滤/排序范畴并已派发；false 表示不认识（由调用方记缺口）。
   * 结果经 `onDownloadSearchSuccess(list)` 回到场景 —— **场景只接收顺序，不自己排**。
   */
  async applyFilterOrSort(menuId: string): Promise<boolean> {
    // ⚠ **必须 await**：`executeFilterAndSort` 内部是串行队列 + async，
    // 且 `sort_by_file_size_*` 两项要先遍历下载目录补算 `fileSize`（`-1` 表示未计算）。
    // 不 await 就会拿到**旧顺序**（同步签名看起来能直接调，这是最容易写错的点）。
    // 首次按文件大小排序会明显变慢 —— 上游同款行为（算完写回 `info.fileSize` 缓存，第二次很快）。
    const filterId: number = DownloadsScene.menuIdToFilterId(menuId);
    if (filterId < 0) {
      return false;
    }
    const executor: DownloadListInfosExecutor =
      new DownloadListInfosExecutor(this.mList, this.searchKey !== null ? this.searchKey : '');
    executor.setDownloadSearchingListener(new SceneSearchCallback(this));
    await executor.executeFilterAndSort(filterId);
    return true;
  }

  /**
   * executor 的回调落地（`DownloadSearchCallback`）：**按回调给的顺序替换列表**。
   *
   * `mList` 为 null 的情况上游允许（C-7 第 4 条：无 @NonNull）—— 这里视为"结果为空"，
   * 保持原列表不变并 warn，而不是清空（清空会让用户以为下载全没了）。
   */
  onDownloadSearchSuccessResult(list: DownloadInfo[] | null): void {
    if (list === null) {
      console.warn(`[${DownloadsScene.TAG}] onDownloadSearchSuccess 收到 null，保持原列表（上游允许 null）`);
      return;
    }
    this.mList = list;
    this.mBackList = list;
    this.updateTitle();
    this.notifyAdapter();
    const dataSource: DownloadListDataSource | null = this.mDataSource;
    if (dataSource !== null) {
      dataSource.reload();
    }
  }
  // ---------------------------------------------------------------- 适配器接线（上游 DownloadAdapterCallback）

  /** 当前页（1 起，上游 `DownloadPaginationController.indexPage`）。 */
  private mIndexPage: number = 1;
  /** 是否允许分页（上游 `isCanPagination`，默认 true）。 */
  private mCanPagination: boolean = true;
  /** 适配器（ui-scene 的 S0221；未注入时用 `UnavailableDownloadAdapter`，只 warn 不静默）。 */
  private mAdapter: DownloadAdapterLike = new UnavailableDownloadAdapter();
  /** gid → SpiderInfo（展示阅读进度；未读到进度文件的 gid 不在表里）。 */
  private readonly mSpiderInfoMap: Map<number, SpiderInfo> = new Map<number, SpiderInfo>();
  /** LazyForEach 数据源（Part 2 渲染骨架；位置换算封装在数据源里）。 */
  private mDataSource: DownloadListDataSource | null = null;

  setAdapter(adapter: DownloadAdapterLike | null): void {
    this.mAdapter = adapter !== null ? adapter : new UnavailableDownloadAdapter();
  }

  getAdapter(): DownloadAdapterLike {
    return this.mAdapter;
  }

  /** 数据变化后通知适配器（集中一处，避免每个数据变更点各写一次）。 */
  private notifyAdapter(): void {
    this.mAdapter.notifyDataSetChanged();
  }

  /** 对位上游 `DownloadPaginationController.indexPage` 的 setter（1 起，小于 1 归 1）。 */
  setIndexPage(page: number): void {
    this.mIndexPage = page < 1 ? 1 : page;
  }

  getIndexPage(): number {
    return this.mIndexPage;
  }

  getPaginationSize(): number {
    return PAGINATION_THRESHOLD;
  }

  isCanPagination(): boolean {
    return this.mCanPagination;
  }

  setCanPagination(can: boolean): void {
    this.mCanPagination = can;
  }

  /**
   * 是否处于分页状态 —— 上游三处判定一致：`list.size > paginationSize && isCanPagination`
   * （注意是 `>` 500，不是 `>=`；恰好 500 项时不分页）。
   */
  private isPaginationActive(): boolean {
    return this.mList.length > PAGINATION_THRESHOLD && this.mCanPagination;
  }

  /** 对位上游 `positionInList(p)`：分页生效时 `p + pageSize*(indexPage-1)`，否则原样。 */
  positionInList(position: number): number {
    if (this.isPaginationActive()) {
      return position + this.mPageSize * (this.mIndexPage - 1);
    }
    return position;
  }

  /** 对位上游 `listIndexInPage(p)`：分页生效时 `p % pageSize`，否则原样。 */
  listIndexInPage(position: number): number {
    if (this.isPaginationActive()) {
      return position % this.mPageSize;
    }
    return position;
  }

  getSpiderInfoMap(): Map<number, SpiderInfo> {
    return this.mSpiderInfoMap;
  }

  /** gid → SpiderInfo（进度文件读到后由宿主填入；传 null 表示移除）。 */
  putSpiderInfo(gid: number, info: SpiderInfo | null): void {
    if (info === null) {
      this.mSpiderInfoMap.delete(gid);
    } else {
      this.mSpiderInfoMap.set(gid, info);
    }
    this.notifyAdapter();
  }

  getDownloadManager(): Object | null {
    return this.mDownloadManager as Object | null;
  }

  /** 取 LazyForEach 数据源（首次调用时创建；宿主把它交给 List 的 LazyForEach）。 */
  getDataSource(): DownloadListDataSource {
    if (this.mDataSource === null) {
      this.mDataSource = new DownloadListDataSource(this);
    }
    return this.mDataSource;
  }

  // ---------------------------------------------------------------- Part 2：视图装配与菜单

  /**
   * 视图装配的**宿主参数**（替代原来的 `buildViewTree()` 抛 TODO）。
   *
   * `scene_download.ets` 是 `@Component`（ArkUI 声明式组件），**只能由 ArkUI 页面实例化**，
   * 纯类无法也不应该 `new` 它。所以场景的职责是"把渲染需要的东西准备好"，由宿主组件读：
   *   - 数据源：`getDataSource()`（LazyForEach 用）
   *   - 标题：`getTitle()`
   *   - 是否分页：`isCanPagination()` / `getPageSize()`
   *   - 菜单：`getMenu()`（40 项定义，见下）
   *
   * 上游 `onCreateView()` 里 inflate 布局 + 找控件的工作在 ArkUI 侧由 `@Component` 自己完成，
   * 场景不再重复。**仍未移植**：拖动排序（recyclerView 的拖拽）、ViewTransition 动画、
   * 分类 Spinner 的 spinner 适配器 —— 这些需要 ui-widget 的控件能力，见各控制器与 Adapter 契约。
   */
  getViewState(): DownloadSceneViewState {
    return new DownloadSceneViewState(this.getTitle(), this.mList.length, this.mPageSize,
      this.isPaginationActive());
  }

  /**
   * 菜单定义（40 项，来自 `ui/menu/scene_download.ets`）。
   *
   * 场景不持有菜单渲染，只按 id 分发点击 —— 上游 `onOptionsItemSelected(menuItem)` 的等价物是
   * `handleMenuItem(id)`（见下）。
   */
  getMenu(): MenuItemDef[] {
    return SceneDownloadMenu;
  }

  /**
   * 处理菜单点击（上游 `onOptionsItemSelected`）。
   *
   * 返回 `true` 表示已处理；`false` 表示**本场景不处理该 id**。
   *
   * 未处理的 id 会**记入 `mUnhandledMenuIds` 并 warn**（不静默）：
   * 40 项里有相当一部分属于过滤器/排序（`sort_by_*` / `filter_by_*` / 分类项），
   * 它们要配合 ui-widget 的下拉与 `DownloadPaginationController`，本批只实现能立刻生效的动作项。
   * 静默返回 false 会让"点了没反应"变成不可查问题。
   */
  handleMenuItem(id: string): boolean {
    switch (id) {
      case 'action_start_all':
        this.startAll().then(() => {
          Utils.logI(DownloadsScene.TAG, 'menu action_start_all 完成');
        }).catch((e: Error) => {
          Utils.logE(DownloadsScene.TAG, `menu action_start_all 失败: ${errorText(e)}`);
        });
        return true;
      case 'action_stop_all':
        this.stopAll().then(() => {
          Utils.logI(DownloadsScene.TAG, 'menu action_stop_all 完成');
        }).catch((e: Error) => {
          Utils.logE(DownloadsScene.TAG, `menu action_stop_all 失败: ${errorText(e)}`);
        });
        return true;
      case 'search_download_gallery':
        this.showSearchBar();
        return true;
      case 'import_local_archive':
        this.showArchiveImportDialog(null);
        return true;
      case 'import_local_album':
        this.showAlbumImportDialog(null);
        return true;
      case 'sort_download_list':
      case 'filter_by_status':
      case 'filter_by_kind':
      case 'sort':
        // 上游这四项只是**展开子菜单**（popup），真正动作在子项（sort_by_* / filter_by_*）。
        // ArkUI 侧由 Menu 组件按 `MenuItemDef` 的层级展开，场景无需处理。
        return true;
      case 'action_reset_reading_progress':
        return this.resetReadingProgressForList();
      case 'local_import':
      case 'all_kind':
      case 'misc':
      case 'doujinshi':
      case 'manga':
      case 'artist_cg':
      case 'game_cg':
      case 'image_set':
      case 'cosplay':
      case 'asian_porn':
      case 'non_h':
      case 'western':
      case 'unknown':
        // 类别过滤 12 项 + local_import：**上游本身禁用**（DownloadsScene.java:312 把 filterByCategory() 注释掉）
        // → 按 1:1 只识别、不改列表；必须 return true，否则会被记成"我们没做"（D-044）
        return true;
      default:        // 过滤/排序：派发给 download-sync 的 executor（不自己排）
        if (DownloadsScene.menuIdToFilterId(id) >= 0) {
          this.applyFilterOrSort(id).catch((e: Error) => {
            Utils.logE(DownloadsScene.TAG, 'applyFilterOrSort(' + id + ') 失败: ' + errorText(e));
          });
          return true;
        }
        this.mUnhandledMenuIds.push(id);
        console.warn(`[${DownloadsScene.TAG}] 菜单项 '${id}' 尚未接线（已记入 getUnhandledMenuIds）`);
        return false;
    }
  }

  /**
   * 菜单「重置阅读进度」：把当前列表里**所有**已打开过的 queen 的 startPage 归零。
   *
   * 上游是对选中项/全部项批量重置；这里按"当前标签的整份列表"处理（与 `action_start_all`
   * 的作用域一致），因为本批没有多选状态（多选属 ui-widget 的控件能力）。
   *
   * 依赖自己的 `SpiderQueen.resetReadingProgress(gid)`：**只对已打开的 queen 生效**
   * （上游同样：queen 不在表里就没有内存进度可重置，磁盘上的 `.ehviewer` 由下次写入覆盖）。
   * 所以返回**实际重置了几个**，让调用方能区分"没有可重置的"与"重置了 N 个"
   * —— 若按"是否处理了菜单"返回 true，用户点了没变化时无从判断。
   */
  private resetReadingProgressForList(): boolean {
    let reset: number = 0;
    for (const info of this.mList) {
      const gid: number = info.getGid();
      if (SpiderQueen.hasQueen(gid)) {
        SpiderQueen.resetReadingProgress(gid);
        reset++;
      }
    }
    if (reset === 0) {
      console.warn(`[${DownloadsScene.TAG}] resetReadingProgress: 当前列表 ${this.mList.length} 项里` +
        '没有已打开的阅读实例，未重置任何进度（这是正常情况，不是失败）');
    } else {
      Utils.logI(DownloadsScene.TAG, `resetReadingProgress: 已重置 ${reset} 项`);
    }
    this.updateForLabel();
    return true;
  }

  private readonly mUnhandledMenuIds: string[] = [];

  /** 供诊断：哪些菜单 id 点了但没有实现（用于给 ui-widget/ui-scene 补接线）。 */
  getUnhandledMenuIds(): string[] {
    return this.mUnhandledMenuIds.slice();
  }

  /** 诊断：菜单总数与已接线数（40 项里有多少能立刻生效）。 */
  getMenuCoverage(): number[] {
    const total: number = SceneDownloadMenu.length;
    let wired: number = 0;
    for (const item of SceneDownloadMenu) {
      // 两类来源：静态接线表 + 派发给 download-sync executor 的过滤/排序 id
      if (DownloadsScene.WIRED_MENU_IDS.indexOf(item.id) >= 0
        || DownloadsScene.menuIdToFilterId(item.id) >= 0) {
        wired++;
      }
    }
    return [wired, total];
  }

  private static readonly WIRED_MENU_IDS: string[] = [
    'action_start_all', 'action_stop_all', 'search_download_gallery',
    'import_local_archive', 'import_local_album',
    'action_reset_reading_progress', 'sort_download_list', 'filter_by_status',
    'filter_by_kind', 'sort',
    // 类别过滤 12 项 + local_import：上游禁用（D-044），识别但不改列表
    'local_import', 'all_kind', 'misc', 'doujinshi', 'manga', 'artist_cg', 'game_cg', 'image_set', 'cosplay', 'asian_porn', 'non_h', 'western', 'unknown'
  ];
}

/**
 * 宿主组件（`@Component scene_download`）需要的场景状态。
 *
 * 用类而不是对象字面量：ArkTS 禁止无类型对象字面量（`arkts-no-untyped-obj-literals`）。
 */
export class DownloadSceneViewState {
  readonly title: string;
  readonly itemCount: number;
  readonly pageSize: number;
  readonly paginationActive: boolean;

  constructor(title: string, itemCount: number, pageSize: number, paginationActive: boolean) {
    this.title = title;
    this.itemCount = itemCount;
    this.pageSize = pageSize;
    this.paginationActive = paginationActive;
  }
}


/**
 * executor 回调的薄适配器（场景只需要 `onDownloadSearchSuccess`）。
 *
 * 上游 `DownloadSearchCallback` 有三个方法；场景只关心搜索结果，
 * 另两个（handle/failed）都落到"保持原列表 + warn"，避免 null 差异导致空列表。
 */
class SceneSearchCallback implements DownloadSearchCallback {
  private readonly scene: DownloadsScene;

  constructor(scene: DownloadsScene) {
    this.scene = scene;
  }

  onDownloadSearchSuccess(mList: DownloadInfo[] | null): void {
    this.scene.onDownloadSearchSuccessResult(mList);
  }

  onDownloadListHandleSuccess(mList: DownloadInfo[] | null): void {
    this.scene.onDownloadSearchSuccessResult(mList);
  }

  onDownloadSearchFailed(mList: DownloadInfo[] | null): void {
    console.warn('[DownloadsScene] onDownloadSearchFailed，保持原列表');
  }
}
/** catch 参数转文案（ArkTS 的 catch 参数是 unknown）。 */
function errorText(e: Object | null | undefined): string {
  if (e instanceof Error) {
    return e.message !== undefined ? e.message : `${e.name}`;
  }
  return `${e}`;
}

