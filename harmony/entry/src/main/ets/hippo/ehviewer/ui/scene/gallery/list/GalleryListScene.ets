/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/GalleryListScene.java（1980 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/GalleryListScene.ets（inventory S0242）
 *
 * ⚠ 分批移植：本文件是 **Part 1 —— 列表最小闭环**（能显示列表）：
 *   场景身份/启动 action、状态机常量、GalleryAdapter 接线、SceneDataSource 驱动 List、
 *   页码联动、首刷标记、收藏夹显示开关。
 *   Part 2 待补：搜索（SearchLayout/SearchBar/FAB/FabLayout 槽位接线）、筛选标签（filterTagList）、
 *   分页加载（加载更多/到底判定）、错误态与重试、ViewTransition 动画、抽屉箭头 Drawable 状态。
 *
 * 依赖处置（net-parse 侦察模式）：
 *   1. EhClient/解析 → net-parse 已交付，直接 import（call 由 Part 2 接入）
 *   2. GalleryInfo/GalleryDetail → net-parse 已交付（2026-10-24）
 *   3. EhDB 历史/收藏 → storage-db 已交付，可直接 await
 *   4. 控件（ContentLayout/SearchLayout/SearchBar/FabLayout）→ ui-widget 槽位注入
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../../../../scene/SceneTypes';
import { SceneFragment } from '../../../../../scene/SceneFragment';
import { Announcer } from '../../../../../scene/Announcer';
import { SceneDataSource } from '../../../../../ui/SceneDataSource';
import { GalleryInfo } from '../../../../client/data/GalleryInfo';
import { ListUrlBuilder } from '../../../../client/data/ListUrlBuilder';
import { CategoryFlags } from '../../../../client/data/Flags';
import { EhUrl } from '../../../../client/EhUrl';
import { GalleryDetailScene } from '../detail/GalleryDetailScene';
import { GalleryAdapter } from './GalleryAdapter';

export class GalleryListAction {
  static readonly KEY_ACTION: string = 'action';
  static readonly HOMEPAGE: string = 'action_homepage';
  static readonly SUBSCRIPTION: string = 'action_subscription';
  static readonly WHATS_HOT: string = 'action_whats_hot';
  static readonly TOP_LIST: string = 'action_top_list';
  static readonly LIST_URL_BUILDER: string = 'action_list_url_builder';
  static readonly KEY_LIST_URL_BUILDER: string = 'list_url_builder';
  static readonly KEY_SEARCH_KEYWORD: string = 'search_keyword';
  static readonly KEY_HAS_FIRST_REFRESH: string = 'has_first_refresh';
  static readonly KEY_STATE: string = 'state';
}

/** 上游 private @interface State */
export class GalleryListState {
  static readonly NORMAL: number = 0;
  static readonly ERROR: number = 1;
}

/**
 * Part 3：列表请求接口（EhClient 在 net-parse 尚未交付，42/94）
 * 按 Lead 指示先定接口 + 默认打 warn 实现，不 import 不存在的类（避免把主干拖红）。
 * EhClient 落地后：new GalleryListClientBridge(ehClient) 注入即可，场景代码不改。
 */
export interface EhClientLike {
  /** 上游 EhClient.getGalleryList(url, page) → List<GalleryInfo> */
  getGalleryList(url: string, page: number): Promise<GalleryInfo[] | null>;
}

/** 可选元数据/错误信息提供接口（供真实 client 暴露 lastError 与 totalPages）。 */
export interface EhClientMetaProvider {
  getLastError(): string;
  getTotalPages(): number;
  hasMorePages?(): boolean;
}

/** 默认实现：未接线时打 warn 并返回 null（同 net-parse 的 TagSyncHook 模式，待登记 D-0xx） */
export class UnavailableGalleryListClient implements EhClientLike {
  async getGalleryList(url: string, page: number): Promise<GalleryInfo[] | null> {
    console.warn('[ui-scene] EhClient 未接线：getGalleryList(url=' + url + ', page=' + page + ')');
    return null;
  }
}

export abstract class GalleryListScene extends SceneFragment {
  /** 上游 BACK_PRESSED_INTERVAL = 2000ms：连按返回退出 */
  static readonly BACK_PRESSED_INTERVAL: number = 2000;

  protected action: string = GalleryListAction.HOMEPAGE;
  protected listUrlBuilder: string = '';
  protected hasFirstRefresh: boolean = false;
  protected state: number = GalleryListState.NORMAL;
  /** 上游 showReadProgress（读图进度，来自 Settings） */
  protected showReadProgress: boolean = false;

  /** 列表数据源（对位上游 mAdapter.getItemCount/getDataAt） */
  protected dataSource: SceneDataSource<GalleryInfo> = new SceneDataSource<GalleryInfo>();
  protected adapter: GalleryAdapter | null = null;

  getSceneName(): string {
    return 'GalleryListScene';
  }

  /** 上游 onNewArguments(args)：读取 action / list_url_builder / has_first_refresh */
  onNewArguments(args: SceneArgs): void {
    const a: Object | undefined = args.get(GalleryListAction.KEY_ACTION);
    const hasAction: boolean = a !== undefined && typeof a === 'string';
    if (hasAction) {
      this.action = a as string;
    }
    const u: Object | undefined = args.get(GalleryListAction.KEY_LIST_URL_BUILDER);
    const hasUrlBuilder: boolean = u !== undefined && typeof u === 'string';
    if (hasUrlBuilder) {
      this.listUrlBuilder = u as string;
    }
    const k: Object | undefined = args.get(GalleryListAction.KEY_SEARCH_KEYWORD);
    const explicitKey: string = (k !== undefined && typeof k === 'string') ? (k as string).trim() : '';
    const f: Object | undefined = args.get(GalleryListAction.KEY_HAS_FIRST_REFRESH);
    if (f !== undefined && typeof f === 'boolean') {
      this.hasFirstRefresh = f as boolean;
    }
    if (hasAction || hasUrlBuilder || this.listUrl.length === 0) {
      this.pageIndex = 0;
      this.reachEnd = false;
      this.state = GalleryListState.NORMAL;
      if (this.action === GalleryListAction.LIST_URL_BUILDER && this.listUrlBuilder.length > 0) {
        this.listUrl = this.listUrlBuilder;
      } else if (this.action === GalleryListAction.WHATS_HOT) {
        this.listUrl = EhUrl.getPopularUrl();
      } else if (this.action === GalleryListAction.SUBSCRIPTION) {
        this.listUrl = EhUrl.getWatchedUrl();
      } else if (this.action === GalleryListAction.TOP_LIST) {
        this.listUrl = EhUrl.getTopListUrl();
      } else {
        this.listUrl = new ListUrlBuilder().build();
      }
      if (explicitKey.length > 0) {
        this.searchKey = explicitKey;
      } else if (this.action === GalleryListAction.LIST_URL_BUILDER) {
        this.searchKey = ListUrlBuilder.extractSearchKeywordFromUrl(this.listUrl);
      } else {
        this.searchKey = '';
      }
    } else if (explicitKey.length > 0) {
      this.searchKey = explicitKey;
    }
    this.notifyDataChanged();
  }

  /** 上游 mAdapter 接线：整段替换数据 → LazyForEach 重绘 */
  protected setGalleryList(list: GalleryInfo[]): void {
    this.dataSource.setAll(list);
  }

  protected appendGalleryList(list: GalleryInfo[]): void {
    const seen: Set<number> = new Set<number>();
    const existingCount: number = this.dataSource.totalCount();
    for (let i = 0; i < existingCount; i++) {
      const existing: GalleryInfo | null = this.dataSource.getData(i);
      if (existing !== null) {
        seen.add(existing.gid);
      }
    }
    const unique: GalleryInfo[] = [];
    for (let i = 0; i < list.length; i++) {
      const item: GalleryInfo = list[i];
      if (!seen.has(item.gid)) {
        seen.add(item.gid);
        unique.push(item);
      }
    }
    if (unique.length > 0) {
      this.dataSource.addAll(unique);
    }
  }

  /** 上游 setState(NORMAL|ERROR) */
  setListState(state: number): void {
    this.state = state;
    this.notifyDataChanged();
  }

  getListState(): number {
    return this.state;
  }

  /** 注册数据/状态变化监听，供 UI 响应式同步。 */
  setOnDataChangedListener(fn: (() => void) | null): void {
    this.onDataChangedListener = fn;
  }

  protected notifyDataChanged(): void {
    const fn: (() => void) | null = this.onDataChangedListener;
    if (fn !== null) {
      fn();
    }
  }

  /** 统一错误串提取（Error / BusinessError / 裸对象），供三段式日志与 UI 使用 */
  private errorToString(e: Object | null | undefined): string {
    if (e === null || e === undefined) {
      return 'Unknown error';
    }
    if (typeof e === 'string') {
      return e as string;
    }
    let codeStr: string = '';
    let msgStr: string = '';
    if (typeof e === 'object') {
      const rec: Record<string, Object> = e as Record<string, Object>;
      const rawCode: Object | undefined = rec['code'];
      if (typeof rawCode === 'number' || typeof rawCode === 'string') {
        codeStr = String(rawCode);
      }
      const rawMsg: Object | undefined = rec['message'];
      if (typeof rawMsg === 'string') {
        msgStr = rawMsg as string;
      }
    }
    if (msgStr.length === 0 && e instanceof Error && e.message !== undefined && e.message !== null) {
      msgStr = e.message;
    }
    if (codeStr.length > 0 && msgStr.length > 0) {
      return `[${codeStr}] ${msgStr}`;
    }
    if (msgStr.length > 0) {
      return msgStr;
    }
    if (codeStr.length > 0) {
      return `BusinessError ${codeStr}`;
    }
    if (typeof e === 'object') {
      try {
        const json: string = JSON.stringify(e);
        if (json !== undefined && json.length > 0 && json !== '{}') {
          return json;
        }
      } catch (_ignored) {
        // ignore unserializable object
      }
    }
    return String(e);
  }

  getDataSource(): SceneDataSource<GalleryInfo> {
    return this.dataSource;
  }

  /**
   * 最小闭环：List + LazyForEach 需要的三件套（页面在 build() 里直接取用）
   * 上游 onBindViewHolder 的字段计算已下沉到 GalleryAdapter.bind()。
   */
  getItemCount(): number {
    return this.dataSource.totalCount();
  }

  getItem(index: number): GalleryInfo | null {
    return this.dataSource.getData(index);
  }

  // ---------------- Part 2：分页 / 刷新 / 错误重试 ----------------

  /** 上游分页状态：加载中 / 到底 / 首次加载完成 */
  protected loading: boolean = false;
  protected reachEnd: boolean = false;
  protected pageIndex: number = 0;
  protected totalPages: number = 0;
  protected lastError: string = '';
  protected searchCategory: number = CategoryFlags.NONE;
  protected requestSeq: number = 0;
  private onDataChangedListener: (() => void) | null = null;

  isLoadingList(): boolean {
    return this.loading;
  }

  isReachEndList(): boolean {
    return this.reachEnd;
  }

  getLastError(): string {
    return this.lastError;
  }

  getTotalPages(): number {
    return this.totalPages;
  }

  getPageIndex(): number {
    return this.pageIndex;
  }

  getListUrl(): string {
    return this.listUrl;
  }

  getAction(): string {
    return this.action;
  }

  /** Switch drawer list action cleanly (resets category/page and refreshes). */
  switchToAction(action: string, url?: string): void {
    this.action = action;
    this.searchCategory = CategoryFlags.NONE;
    this.pageIndex = 0;
    this.reachEnd = false;
    this.state = GalleryListState.NORMAL;
    if (url !== undefined && url.length > 0) {
      this.listUrlBuilder = url;
      this.listUrl = url;
    } else if (action === GalleryListAction.WHATS_HOT) {
      this.listUrl = EhUrl.getPopularUrl();
    } else if (action === GalleryListAction.SUBSCRIPTION) {
      this.listUrl = EhUrl.getWatchedUrl();
    } else if (action === GalleryListAction.TOP_LIST) {
      this.listUrl = EhUrl.getTopListUrl();
    } else {
      this.listUrl = new ListUrlBuilder().build();
    }
    if (action === GalleryListAction.LIST_URL_BUILDER && url !== undefined && url.length > 0) {
      this.searchKey = ListUrlBuilder.extractSearchKeywordFromUrl(url);
    } else {
      this.searchKey = '';
    }
    this.notifyDataChanged();
  }

  /** Run a tag search query using ListUrlBuilder (`namespace:"tag with spaces"`). */
  searchTag(namespace: string, tag: string): void {
    const cleanTag: string = tag.trim();
    if (cleanTag.length === 0) {
      return;
    }
    const tagQuery: string = namespace.length > 0 && namespace !== 'misc'
      ? `${namespace}:${cleanTag}`
      : cleanTag;
    const ub: ListUrlBuilder = new ListUrlBuilder();
    ub.setMode(ListUrlBuilder.MODE_TAG);
    ub.setKeyword(tagQuery);
    this.action = GalleryListAction.LIST_URL_BUILDER;
    this.listUrlBuilder = ub.build();
    this.listUrl = this.listUrlBuilder;
    this.searchKey = ListUrlBuilder.wrapTagKeyword(tagQuery);
    this.searchCategory = CategoryFlags.NONE;
    this.pageIndex = 0;
    this.reachEnd = false;
    this.state = GalleryListState.NORMAL;
    this.refreshGalleryList();
  }

  getSearchCategory(): number {
    return this.searchCategory;
  }

  /** 上游 onReachEnd：滚动到底触发下一页（由 List 的 onReachEnd 调用） */
  onReachEndList(): void {
    if (this.loading || this.reachEnd || this.state === GalleryListState.ERROR) {
      return;
    }
    this.loadNextPage();
  }

  /** 上游 loadNextPage：页码 +1，请求交由子类（EhClient 调用在 Part 3） */
  protected loadNextPage(): void {
    this.loading = true;
    this.pageIndex = this.pageIndex + 1;
    this.lastError = '';
    this.notifyDataChanged();
    this.requestGalleryList(this.pageIndex, false);
  }

  /** 上游 refresh：重置页码并整段替换 */
  refreshGalleryList(): void {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.pageIndex = 0;
    this.reachEnd = false;
    this.lastError = '';
    this.notifyDataChanged();
    this.requestGalleryList(0, true);
  }

  /** 切换到首页列表并刷新。 */
  switchToHome(): void {
    this.action = GalleryListAction.HOMEPAGE;
    this.searchKey = '';
    this.searchCategory = CategoryFlags.NONE;
    this.totalPages = 0;
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_NORMAL);
    this.listUrl = builder.build();
    this.loading = false;
    this.refreshGalleryList();
  }

  /** 切换到热门（What's hot）并刷新。 */
  switchToPopular(): void {
    this.action = GalleryListAction.WHATS_HOT;
    this.searchKey = '';
    this.searchCategory = CategoryFlags.NONE;
    this.totalPages = 1;
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_WHATS_HOT);
    this.listUrl = builder.build();
    this.loading = false;
    this.refreshGalleryList();
  }

  /** 按关键词与分类掩码构建列表 URL 并从第 0 页刷新。 */
  applySearchAndCategory(keyword: string, category: number): void {
    const trimmed: string = keyword.trim();
    this.action = GalleryListAction.LIST_URL_BUILDER;
    this.searchKey = trimmed;
    this.searchCategory = category;
    this.totalPages = 0;
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_NORMAL);
    builder.setKeyword(trimmed.length > 0 ? trimmed : null);
    builder.setCategory(category);
    this.listUrl = builder.build();
    this.loading = false;
    this.refreshGalleryList();
  }

  /** 打开画廊详情场景。 */
  openGalleryDetail(info: GalleryInfo): void {
    const args: SceneArgs = new Map<string, Object>();
    args.set(GalleryDetailScene.KEY_GID, info.gid);
    args.set(GalleryDetailScene.KEY_GALLERY_INFO, info);
    if (info.gid > 0 && info.token.length > 0) {
      args.set(GalleryDetailScene.KEY_API_URL, EhUrl.getGalleryDetailUrl(info.gid, info.token, 0, false));
    }
    this.startScene(new Announcer('GalleryDetailScene').setArgs(args));
  }

  /** 列表请求客户端：默认未接线（打 warn 返回 null），EhClient 交付后由页面注入 */
  protected client: EhClientLike = new UnavailableGalleryListClient();
  protected clientMeta: EhClientMetaProvider | null = null;
  /** 列表 URL（上游 EhUrl.getGalleryListUrl / topList / search 的结果） */
  protected listUrl: string = '';
  /** 上游 PAGE_SIZE */
  protected static readonly PAGE_SIZE: number = 25;

  setGalleryListClient(client: EhClientLike): void {
    this.client = client;
  }

  setClientMetaProvider(meta: EhClientMetaProvider | null): void {
    this.clientMeta = meta;
  }

  setListUrl(url: string): void {
    this.listUrl = url;
  }

  /** 请求钩子：Part 3 已接接口（默认实现 warn），EhClient 落地后换实现即可 */
  protected requestGalleryList(page: number, refresh: boolean): void {
    const seq: number = ++this.requestSeq;
    if (this.listUrl.length === 0) {
      this.onGalleryListError('Gallery list URL is empty');
      return;
    }
    this.client.getGalleryList(this.listUrl, page).then((list: GalleryInfo[] | null) => {
      if (seq !== this.requestSeq) {
        return;
      }
      if (list === null) {
        const metaErr: string = this.clientMeta !== null ? this.clientMeta.getLastError() : '';
        this.onGalleryListError(metaErr.length > 0 ? metaErr : 'Gallery list client unavailable');
        return;
      }
      if (this.clientMeta !== null) {
        this.totalPages = this.clientMeta.getTotalPages();
      }
      this.onGalleryListLoaded(list, refresh, GalleryListScene.PAGE_SIZE);
    }).catch((e: Object) => {
      if (seq !== this.requestSeq) {
        return;
      }
      const rawMsg: string = this.errorToString(e);
      const metaErr: string = this.clientMeta !== null ? this.clientMeta.getLastError() : '';
      const errMsg: string = metaErr.length > 0 ? metaErr : rawMsg;
      hilog.error(0x0000, 'GalleryListScene', 'getGalleryList failed: url=%{public}s page=%{public}d err=%{public}s; 后果：列表停在当前内容并显示重试',
        this.listUrl, page, errMsg);
      this.onGalleryListError(errMsg);
    });
  }

  /** 请求结束回调（成功）：追加或替换 + 到底判定（上游 items.size < pageSize） */
  protected onGalleryListLoaded(list: GalleryInfo[], refresh: boolean, pageSize: number): void {
    this.loading = false;
    this.lastError = '';
    if (refresh) {
      this.setGalleryList(list);
    } else {
      this.appendGalleryList(list);
    }
    const hasMetaPagination: boolean = this.clientMeta !== null && this.clientMeta.hasMorePages !== undefined;
    if (hasMetaPagination && this.clientMeta !== null && this.clientMeta.hasMorePages !== undefined) {
      if (list.length === 0 || !this.clientMeta.hasMorePages() || this.action === GalleryListAction.WHATS_HOT) {
        this.reachEnd = true;
      }
    } else if (list.length < pageSize ||
      (this.totalPages > 0 && this.pageIndex + 1 >= this.totalPages) ||
      this.action === GalleryListAction.WHATS_HOT) {
      this.reachEnd = true;
    }
    this.state = GalleryListState.NORMAL;
    this.hasFirstRefresh = true;
    this.notifyDataChanged();
  }

  /** 请求失败：保留已加载数据，仅置错误态（上游 setState(ERROR) + 重试按钮） */
  protected onGalleryListError(errorMsg?: string): void {
    this.loading = false;
    this.state = GalleryListState.ERROR;
    if (errorMsg !== undefined && errorMsg.length > 0) {
      this.lastError = errorMsg;
    } else if (this.lastError.length === 0) {
      this.lastError = 'Failed to load gallery list';
    }
    this.notifyDataChanged();
  }

  // ---------------- Part 4：筛选标签 / 抽屉 / 跳页 ----------------

  /** 上游 filterOpen + filterTagList */
  protected filterOpen: boolean = false;
  protected filterTagList: string[] = [];

  isFilterOpen(): boolean {
    return this.filterOpen;
  }

  setFilterOpen(open: boolean): void {
    this.filterOpen = open;
  }

  getFilterTagCount(): number {
    return this.filterTagList.length;
  }

  isFilterTagEnabled(): boolean {
    return this.filterTagList.length > 0;
  }

  /** 上游 addFilterTag：已存在则不重复添加（保持顺序） */
  addFilterTag(tag: string): void {
    if (tag.length === 0 || this.filterTagList.indexOf(tag) >= 0) {
      return;
    }
    this.filterTagList.push(tag);
    this.onFilterChanged();
  }

  /** 上游 removeFilterTag */
  removeFilterTag(tag: string): void {
    const i: number = this.filterTagList.indexOf(tag);
    if (i < 0) {
      return;
    }
    this.filterTagList.splice(i, 1);
    this.onFilterChanged();
  }

  clearFilterTags(): void {
    if (this.filterTagList.length === 0) {
      return;
    }
    this.filterTagList = [];
    this.onFilterChanged();
  }

  /** 上游 filterTag 变化 → 重新按新条件请求第一页 */
  protected onFilterChanged(): void {
    this.refreshGalleryList();
  }

  /** 上游跳页：跳到指定页码（1-based，上游 jumpTo 语义），从该页整段替换 */
  jumpToPage(page: number): void {
    if (page < 1 || this.loading) {
      return;
    }
    this.loading = true;
    this.pageIndex = page - 1;
    this.reachEnd = false;
    this.lastError = '';
    this.notifyDataChanged();
    this.requestGalleryList(this.pageIndex, true);
  }

  /** 上游长按菜单项（GalleryListScene 的 gallery_list_menu_entries：下载 / 加入收藏） */
  static readonly MENU_DOWNLOAD: number = 0;
  static readonly MENU_ADD_FAVOURITE: number = 1;

  /** 长按选中项的回调入口；具体动作在 Part 5（下载走 download-sync、收藏走 EhDB） */

  // ---------------- Part 5：收藏 / 下载动作（依赖以接口注入，不猜 EhDB 签名） ----------------

  /**
   * 收藏数据访问接口。EhDB 的 LocalFavorites 系列由 storage-db 维护且签名仍在变
   * （getAllLocalFavorites/searchLocalFavorites/containLocalFavorites/putLocalFavorites…），
   * 按其交付节奏以接口注入，避免把两侧签名绑死。
   */
  setFavoritesRepository(repo: FavoritesRepositoryLike): void {
    this.favoritesRepo = repo;
  }

  /** 下载入队接口（download-sync 的 DownloadManager），未接线时 warn 兜底 */
  setDownloadEnqueuer(enqueuer: DownloadEnqueueLike): void {
    this.downloadEnqueuer = enqueuer;
  }

  /** 上游 GalleryListScene 的菜单分发 */
  onGalleryListMenuItem(position: number, menuId: number): void {
    const info: GalleryInfo | null = this.getItem(position);
    if (info === null) {
      return;
    }
    if (menuId === GalleryListScene.MENU_DOWNLOAD) {
      this.enqueueDownload(info);
      return;
    }
    if (menuId === GalleryListScene.MENU_ADD_FAVOURITE) {
      this.addToFavourites(info);
    }
  }

  /** 上游：已在收藏夹则提示，否则加入（EhDB.containLocalFavorites → putLocalFavorite） */
  protected addToFavourites(info: GalleryInfo): void {
    this.favoritesRepo.containLocalFavorites(info.gid).then((contained: boolean) => {
      if (contained) {
        this.onFavouriteAlreadyExists(info);
        return;
      }
      this.favoritesRepo.putLocalFavorite(info).then((ok: boolean) => {
        // 刷新该项的收藏角标（不整表重绘）
        this.refreshFavouriteIndicator(info.gid, ok);
      }).catch((e: Error) => {
        hilog.error(0x0000, 'GalleryListScene', 'putLocalFavorite failed: gid=%{public}s, err=%{public}s; 后果：收藏未写入，角标保持未收藏',
          String(info.gid), this.errorToString(e));
        this.onFavouriteFailed(info);
      });
    }).catch((e: Error) => {
      hilog.error(0x0000, 'GalleryListScene', 'containLocalFavorites failed: gid=%{public}s, err=%{public}s; 后果：无法判断是否已收藏，已跳过加入',
        String(info.gid), this.errorToString(e));
      this.onFavouriteFailed(info);
    });
  }

  /** 上游：下载入队（startDownloadRange / 单项） */
  protected enqueueDownload(info: GalleryInfo): void {
    this.downloadEnqueuer.enqueue(info).then((ok: boolean) => {
      if (!ok) {
        this.onDownloadEnqueueFailed(info);
      }
    }).catch((e: Error) => {
      hilog.error(0x0000, 'GalleryListScene', 'enqueueDownload failed: gid=%{public}s, err=%{public}s; 后果：该项未入下载队列',
        String(info.gid), this.errorToString(e));
      this.onDownloadEnqueueFailed(info);
    });
  }

  // 子类可覆盖的反馈钩子。
  //
  // ⚠ 三个 `onXxx` 钩子（onFavouriteAlreadyExists / onFavouriteFailed / onDownloadEnqueueFailed）
  //   **只在下方 Part 6 里定义一次**（那一版会调 `this.toast(...)`）。
  //   这里原本还有三个空实现，与 Part 6 的同名方法冲突 →
  //   `Duplicate function implementation`（6 处，编译红）。
  //   空实现与带实现的版本同时存在时，**必须删空的那一份**：
  //   若反过来删掉带实现的，行为就静默退化为"什么也不提示"。
  protected refreshFavouriteIndicator(gid: number, favourited: boolean): void {
  }

  protected favoritesRepo: FavoritesRepositoryLike = new UnavailableFavoritesRepository();
  protected downloadEnqueuer: DownloadEnqueueLike = new UnavailableDownloadEnqueuer();

  // ---------------- Part 6：搜索栏 / 反馈（收尾） ----------------

  /** 上游 SearchLayout/SearchBar 的开关与关键字（ui-widget 槽位注入，此处只持状态） */
  protected searchBarOpen: boolean = false;
  protected searchKey: string = '';

  isSearchBarOpen(): boolean {
    return this.searchBarOpen;
  }

  /** 上游 showSearchBar：打开并把焦点交给控件（控件接管焦点） */
  showSearchBar(): void {
    this.searchBarOpen = true;
  }

  hideSearchBar(): void {
    this.searchBarOpen = false;
  }

  getSearchKey(): string {
    return this.searchKey;
  }

  /** 上游 setSearchKey：关键字变化后按新条件重拉第一页（空串等于清空搜索） */
  setSearchKey(key: string): void {
    if (key === this.searchKey) {
      return;
    }
    this.applySearchAndCategory(key, this.searchCategory);
  }

  /** 上游搜索提交：构造搜索 URL 由 Part 3 的 client 使用（此处只切状态） */
  submitSearch(key: string): void {
    const trimmed: string = key.trim();
    this.searchBarOpen = false;
    this.setSearchKey(trimmed);
  }

  // ---- 反馈（Part 5 留空的钩子接到这里；上游用 Toast/Snackbar） ----

  protected onFavouriteAlreadyExists(info: GalleryInfo): void {
    this.toast('already_in_favourites');
  }

  protected onFavouriteFailed(info: GalleryInfo): void {
    this.toast('add_to_favourites_failed');
  }

  protected onDownloadEnqueueFailed(info: GalleryInfo): void {
    this.toast('download_enqueue_failed');
  }

  /**
   * 统一提示出口。参数是**提示标识**而不是文案：具体文案要取上游 strings.xml 的键
   * （本轮未在 base/element/strings.json 中确认对应键名，不编造资源名）。
   * 页面 @Component 覆盖本方法 → promptAction.showToast($r('app.string.<上游键>'))。
   */
  protected toast(hintId: string): void {
    hilog.info(0x0000, 'GalleryListScene', 'toast hint=%{public}s（文案待接上游资源键）', hintId);
  }
}

/** 收藏仓库接口（storage-db 的 EhDB LocalFavorites 子集） */
export interface FavoritesRepositoryLike {
  containLocalFavorites(gid: number): Promise<boolean>;
  putLocalFavorite(info: GalleryInfo): Promise<boolean>;
}

/** 下载入队接口（download-sync 的 DownloadManager 子集） */
export interface DownloadEnqueueLike {
  enqueue(info: GalleryInfo): Promise<boolean>;
}

export class UnavailableFavoritesRepository implements FavoritesRepositoryLike {
  async containLocalFavorites(gid: number): Promise<boolean> {
    console.warn('[ui-scene] EhDB LocalFavorites 未接线: containLocalFavorites(' + gid + ')');
    return false;
  }
  async putLocalFavorite(info: GalleryInfo): Promise<boolean> {
    console.warn('[ui-scene] EhDB LocalFavorites 未接线: putLocalFavorite(gid=' + info.gid + ')');
    return false;
  }
}

export class UnavailableDownloadEnqueuer implements DownloadEnqueueLike {
  async enqueue(info: GalleryInfo): Promise<boolean> {
    console.warn('[ui-scene] DownloadManager 未接线: enqueue(gid=' + info.gid + ')');
    return false;
  }

}
