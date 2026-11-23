/*
 * 上游：.../ui/scene/gallery/list/FavoritesScene.kt（1533 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/FavoritesScene.ets（S0239）
 *
 * Part 1（本批）：三个 tab（本地收藏 / 在线收藏 / 订阅）+ 本地收藏读库 + tab 切换钩子。
 * Part 2 待补：在线收藏（EhClient 分页）、订阅列表、收藏夹分类（0-9）、排序对话框、批量操作。
 *
 * 依赖：EhDB 已由 AppWiring 接线；LocalFavorites 以接口注入（签名随 storage-db 交付演进）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../../../../scene/SceneTypes';
import { Announcer } from '../../../../../scene/Announcer';
import { SceneFragment } from '../../../../../scene/SceneFragment';
import { SceneDataSource } from '../../../../../ui/SceneDataSource';
import { EhUrl } from '../../../../client/EhUrl';
import { GalleryInfo } from '../../../../client/data/GalleryInfo';
import { FavListUrlBuilder } from '../../../../client/data/FavListUrlBuilder';
import { FavoriteListSortDialogPlan, FavoriteSortDialogPlan } from '../../../dialog/FavoriteListSortDialog';
import { FavoritesResult } from '../../../../client/parser/FavoritesParser';
import { SearchBarMoverState } from '../../../../../widget/SearchBarMover';

/**
 * ⚠ **修正（Part 1 的虚构结构，本轮修掉）**
 * 此前这里是 `FavoritesTab { LOCAL, ONLINE, SUBSCRIPTION }` 三个 tab —— **上游没有 tab**：
 *   · `grep 'TabLayout|ViewPager|TabHost|\btab\b' FavoritesScene.kt` → **0 命中**
 *   · `res/layout/scene_favorites.xml` 只有一个 `ContentLayout`（无 TabLayout / ViewPager）
 *   · 上游靠**抽屉切换 favCat**（`onItemClick`：`newFavCat = position - 2`）驱动同一个列表
 *   · 订阅列表是**独立场景** `SubscriptionsScene`（S0247），由 `SubscriptionDraw:152` 启动
 *     （`activity.startScene(new Announcer(SubscriptionsScene.class))`），**不属于本场景**
 * ⇒ 用"分类（favCat）"作为唯一维度，**没有 tab 这一层**。
 */
export class FavoritesCategory {
  /** 本地收藏（favCat = -2） */
  static readonly LOCAL: number = -2;
  /** 全部分类（favCat = -1） */
  static readonly ALL: number = -1;
}

/** 本地收藏数据访问（EhDB LocalFavorites 子集） */
export interface LocalFavoritesLike {
  getLocalFavoritesLazyList(): Promise<GalleryInfo[]>;
}

/**
 * 占位实现（未注入时的兜底）。
 *
 * ⚠ **日志必须 warn-once**：此前每次调用都 warn，而调用次数正比于用户操作（切分类就调一次）⇒
 * 日志量正比于操作次数，**真正重要的那一次警告会被自己的重复淹没**。
 * 判据：`Unavailable*` / `Noop*` / `Fallback*` 这类占位实现的日志一律 warn-once（静态标志）。
 */
export class UnavailableLocalFavorites implements LocalFavoritesLike {
  /** 进程级一次性标志（静态 → 跨实例共享，切换分类不会重复打印） */
  private static warned: boolean = false;

  async getLocalFavoritesLazyList(): Promise<GalleryInfo[]> {
    if (!UnavailableLocalFavorites.warned) {
      UnavailableLocalFavorites.warned = true;
      hilog.warn(0x0000, 'FavoritesScene',
        'EhDB LocalFavorites 未接线；后果：本地收藏显示为空（本警告只打一次）');
    }
    return [];
  }
}

/**
 * `LocalFavoritesLike` 的真实实现（W-09 的 adapter）：
 * 把已交付的 `EhDB.getAllLocalFavorites()` 适配到本场景的接口。
 *
 * C-19 核对（先读实现，不按上游猜）：
 * ```
 * EhDB.ets:509   static async getAllLocalFavorites(): Promise<LocalFavoriteInfo[]>
 *                → dao.queryBuilder().orderDesc(Properties.Time).list()   // **Time 降序**
 * LocalFavoriteInfo.ets:18   export class LocalFavoriteInfo extends GalleryInfo
 * ⇒ 返回类型 LocalFavoriteInfo[] 可直接赋给 Promise<GalleryInfo[]>（子类数组，协变安全）
 * ```
 * **`EhDB` 的读取路径在注入时用函数传入**（`db` 参数），避免本文件 import EhDB 造成
 * ui-widget → storage-db 的循环依赖（EhDB 已 import 了 dao 层，且 AppWiring 才是接线处）。
 */
export class LocalFavoritesRepoAdapter implements LocalFavoritesLike {
  /** 上游 `EhDB.getAllLocalFavorites()`（Time 降序） */
  private readonly db: () => Promise<GalleryInfo[]>;

  constructor(db: () => Promise<GalleryInfo[]>) {
    this.db = db;
  }

  async getLocalFavoritesLazyList(): Promise<GalleryInfo[]> {
    return this.db();
  }
}

export abstract class FavoritesScene extends SceneFragment {
  /** 当前分类（favCat）。**上游没有 tab 概念**，唯一维度就是 favCat */
  protected currentFavCat: number = FavoritesCategory.LOCAL;
  protected dataSource: SceneDataSource<GalleryInfo> = new SceneDataSource<GalleryInfo>();
  protected loading: boolean = false;
  protected localRepo: LocalFavoritesLike = new UnavailableLocalFavorites();
  /** 在线收藏分页加载器（内部实现；对外通过 setClient / getOnlineLoader 访问） */
  protected onlineLoader: OnlineFavoritesLoader = new OnlineFavoritesLoader();
  protected keyword: string = '';
  protected errorMessage: string = '';
  protected loadedOnce: boolean = false;
  protected favCats: string[] = [];
  protected favCounts: number[] = [];
  private localSeq: number = 0;
  private listResetSeq: number = 0;
  private onlineCallbacksWired: boolean = false;
  private onStateChangedListener: (() => void) | null = null;
  private onMetaUpdatedListener: ((cats: string[], counts: number[]) => void) | null = null;

  getSceneName(): string {
    return 'FavoritesScene';
  }

  setLocalFavoritesRepo(repo: LocalFavoritesLike): void {
    this.localRepo = repo;
  }

  setOnStateChangedListener(fn: (() => void) | null): void {
    this.onStateChangedListener = fn;
  }

  setOnMetaUpdatedListener(fn: ((cats: string[], counts: number[]) => void) | null): void {
    this.onMetaUpdatedListener = fn;
  }

  protected notifyStateChanged(): void {
    const fn: (() => void) | null = this.onStateChangedListener;
    if (fn !== null) {
      fn();
    }
  }

  setFavMeta(cats: string[], counts: number[]): void {
    this.favCats = cats.slice();
    this.favCounts = counts.slice();
  }

  getFavCats(): string[] {
    return this.favCats.slice();
  }

  getFavCounts(): number[] {
    return this.favCounts.slice();
  }

  isLoading(): boolean {
    return this.loading || this.onlineLoader.isLoading();
  }

  getErrorMessage(): string {
    return this.errorMessage;
  }

  getKeyword(): string {
    return this.keyword;
  }

  getListResetSeq(): number {
    return this.listResetSeq;
  }

  hasMore(): boolean {
    if (this.isLocalCategory()) {
      return false;
    }
    return this.onlineLoader.canLoadMore();
  }

  private wireOnlineCallbacks(): void {
    if (this.onlineCallbacksWired) {
      return;
    }
    this.onlineCallbacksWired = true;
    this.onlineLoader.setCallbacks(
      (res: FavoritesPageResult, append: boolean, _page: number): void => {
        if (this.isLocalCategory()) {
          return;
        }
        this.loadedOnce = true;
        this.errorMessage = '';
        if (append) {
          this.dataSource.addAll(res.items);
        } else {
          this.listResetSeq = this.listResetSeq + 1;
          this.dataSource.setAll(res.items);
        }
        if (res.catArray.length === 10 && res.countArray.length === 10) {
          this.favCats = res.catArray.slice();
          this.favCounts = res.countArray.slice();
          const cb: ((cats: string[], counts: number[]) => void) | null = this.onMetaUpdatedListener;
          if (cb !== null) {
            cb(this.favCats.slice(), this.favCounts.slice());
          }
        }
        this.notifyStateChanged();
      },
      (err: Error): void => {
        if (this.isLocalCategory()) {
          return;
        }
        this.errorMessage = err.message !== undefined && err.message.length > 0 ? err.message : String(err);
        this.notifyStateChanged();
      }
    );
  }

  /**
   * 云端收藏的客户端注入（**W-09b 方案 A**：Scene 是唯一对外面，Loader 是内部实现）。
   *
   * 为什么不在 `OnlineFavoritesLoader` 构造时注入（方案 B）：
   * ```
   * ① AppWiring 不该知道 Scene 内部用的是"分页加载器"还是别的实现 —— 它只需要"给这个场景一个客户端"
   * ② Loader 是 `FavoritesScene` 的内部协作对象；将来若换成 ContentHelper 直连，外部代码不用改
   * ③ 与 `setLocalFavoritesRepo` 对称：两个注入都在 Scene 上，接线处只认 Scene
   * ```
   * 转发给内部 `OnlineFavoritesLoader.setClient`（真实实现在那里，本方法只是对外门面）。
   */
  setClient(client: FavoritesClientLike): void {
    this.onlineLoader.setClient(client);
  }

  /** 分页加载器（对外只读；注入走 `setClient`，状态查询走这里） */
  getOnlineLoader(): OnlineFavoritesLoader {
    return this.onlineLoader;
  }

  getCurrentFavCat(): number {
    return this.currentFavCat;
  }

  /**
   * 切换分类（对位上游抽屉 `onItemClick` 的 `newFavCat = position - 2`）。
   * **切到本地收藏时读库**（异步，不在 aboutToAppear 同步 IO，D-012）；切到云分类时由分页加载器发起请求。
   * 与上游一致：同一分类重复点击**不重复加载**。
   */
  setCategory(favCat: number): void {
    if (favCat === this.currentFavCat && this.loadedOnce) {
      return;
    }
    this.currentFavCat = favCat;
    this.errorMessage = '';
    this.reload(false);
  }

  applySearch(keyword: string): void {
    this.keyword = keyword.trim();
    this.reload(true);
  }

  ensureLoaded(): void {
    if (!this.loadedOnce && !this.isLoading()) {
      this.reload(false);
    }
  }

  reload(force: boolean = true): void {
    this.errorMessage = '';
    if (this.isLocalCategory()) {
      this.loadLocalFavorites();
      return;
    }
    this.wireOnlineCallbacks();
    this.onlineLoader.setCategory(this.currentFavCat, this.keyword);
    this.onlineLoader.loadNext(force);
    this.notifyStateChanged();
  }

  loadMore(): void {
    if (this.isLocalCategory() || this.isLoading()) {
      return;
    }
    this.wireOnlineCallbacks();
    if (this.onlineLoader.loadNext(false)) {
      this.notifyStateChanged();
    }
  }

  loadLocalFavorites(): void {
    const seq: number = ++this.localSeq;
    this.loading = true;
    this.errorMessage = '';
    this.notifyStateChanged();
    this.localRepo.getLocalFavoritesLazyList().then((list: GalleryInfo[]) => {
      if (seq !== this.localSeq) {
        return;
      }
      this.loading = false;
      this.loadedOnce = true;
      this.listResetSeq = this.listResetSeq + 1;
      const kw: string = this.keyword.trim().toLowerCase();
      if (kw.length === 0) {
        this.dataSource.setAll(list);
      } else {
        const filtered: GalleryInfo[] = [];
        for (let i = 0; i < list.length; i++) {
          const item: GalleryInfo = list[i];
          const t1: string = item.title.toLowerCase();
          const t2: string = item.titleJpn.toLowerCase();
          const u: string = item.uploader.toLowerCase();
          if (t1.indexOf(kw) >= 0 || t2.indexOf(kw) >= 0 || u.indexOf(kw) >= 0) {
            filtered.push(item);
          }
        }
        this.dataSource.setAll(filtered);
      }
      this.notifyStateChanged();
    }).catch((e: Error) => {
      if (seq !== this.localSeq) {
        return;
      }
      this.loading = false;
      this.errorMessage = e.message !== undefined && e.message.length > 0 ? e.message : String(e);
      hilog.error(0x0000, 'FavoritesScene',
        'getLocalFavoritesLazyList failed: err=%{public}s; 后果：本地收藏列表为空，需下拉重试',
        this.errorMessage);
      this.notifyStateChanged();
    });
  }

  openGalleryDetail(info: GalleryInfo): void {
    if (info.gid <= 0 || info.token.length === 0) {
      return;
    }
    const args: SceneArgs = new Map<string, Object>();
    args.set('gallery_info', info);
    args.set('gid', info.gid);
    args.set('api_url', EhUrl.getGalleryDetailUrl(info.gid, info.token, 0, false));
    this.startScene(new Announcer('GalleryDetailScene').setArgs(args));
  }

  getDataSource(): SceneDataSource<GalleryInfo> {
    return this.dataSource;
  }

  isLocalCategory(): boolean {
    return this.currentFavCat === FavoritesCategory.LOCAL;
  }

  onNewArguments(args: SceneArgs): void {
    const t: Object | undefined = args.get('tab');
    if (t !== undefined && typeof t === 'number') {
      this.currentFavCat = t as number;
    }
    const cat: Object | undefined = args.get('fav_cat');
    if (cat !== undefined && typeof cat === 'number') {
      this.currentFavCat = cat as number;
    }
  }
}

/* ============================ Part 2：在线收藏 / 分类 / 排序 / 批量操作 ============================ */

/**
 * 收藏夹分类（上游 `mFavCatArray: Array<String?>` / `mFavCountArray: IntArray` / `mFavLocalCount` / `mFavCountSum`）
 *
 * 一手语义：
 *   · 分类固定 **0..9 共 10 个**（`Settings.getFavCat()` 返回长度 10 的数组，元素可为 null 表示未命名）
 *   · `Settings.getFavCount()` 与之对应（同一长度），上游另存 `mFavLocalCount`（本地收藏条数）与
 *     `mFavCountSum`（10 个在线分类条数之和）
 *   · 抽屉里分类项的可显示名 = `name`；**null 表示该分类未命名**（上游用默认文案，文案属资源）
 */
export class FavCatModel {
  /** 分类数量：上游 0..9 */
  static readonly CAT_COUNT: number = 10;

  /** 分类名（null = 未命名，调用方用默认文案） */
  names: (string | null)[] = [];
  /** 各分类条数（与 names 同长） */
  counts: number[] = [];
  /** 上游 mFavLocalCount */
  localCount: number = 0;

  constructor(names: (string | null)[], counts: number[], localCount: number) {
    this.names = names.slice(0, FavCatModel.CAT_COUNT);
    this.counts = counts.slice(0, FavCatModel.CAT_COUNT);
    this.localCount = localCount;
  }

  /** 上游 mFavCountSum：10 个在线分类之和（**不含本地收藏**） */
  sumCounts(): number {
    let sum: number = 0;
    for (let i = 0; i < this.counts.length; i++) {
      sum += this.counts[i];
    }
    return sum;
  }

  nameAt(cat: number): string | null {
    if (cat < 0 || cat >= this.names.length) {
      return null;
    }
    return this.names[cat];
  }

  hasName(cat: number): boolean {
    return this.nameAt(cat) !== null;
  }

  countAt(cat: number): number {
    if (cat < 0 || cat >= this.counts.length) {
      return 0;
    }
    return this.counts[cat];
  }

  /** 分类下标合法（0..9） */
  static isValidCat(cat: number): boolean {
    return cat >= 0 && cat < FavCatModel.CAT_COUNT;
  }
}

/**
 * 搜索栏同步（上游 `mOldFavCat` / `mOldKeyword`，注释原文：**Avoid unnecessary search bar update**）
 *
 * 一手语义：只在 `favCat` 或 `keyword` **与上次不同**时才重建搜索栏文案。
 * 这条容易漏 —— 漏了会导致每次数据刷新都重建 SpannableStringBuilder（闪烁 + 无谓分配）。
 */
export class SearchBarSync {
  private oldCat: string | null = null;
  private oldKeyword: string | null = null;

  /** @returns true 表示需要重建搜索栏 */
  shouldUpdate(cat: string | null, keyword: string | null): boolean {
    const changed: boolean = this.oldCat !== cat || this.oldKeyword !== keyword;
    this.oldCat = cat;
    this.oldKeyword = keyword;
    return changed;
  }
}

/**
 * 批量修改收藏夹（上游 `mEnableModify` / `mModifyFavCat` / `mModifyGiList` / `mModifyAdd`）
 *
 * 一手语义（四个字段的联动）：
 *   · 进入修改模式时**必须同时**确定目标分类 `mModifyFavCat` 与方向 `mModifyAdd`（加入/移出）
 *   · 选中项存在 `mModifyGiList`（按 gid 去重，**切换式**：再点一次取消）
 *   · 退出/应用后清空列表并关闭模式
 */
export class ModifyState {
  enabled: boolean = false;
  favCat: number = 0;
  /** true = 加入收藏夹；false = 移出 */
  add: boolean = true;
  private gids: number[] = [];

  /** 上游进入修改模式（重置选择） */
  enable(favCat: number, add: boolean): boolean {
    if (!FavCatModel.isValidCat(favCat)) {
      return false;
    }
    this.enabled = true;
    this.favCat = favCat;
    this.add = add;
    this.gids = [];
    return true;
  }

  /** 切换某项的选中态；未进入修改模式时返回 false（上游不可选） */
  toggle(gid: number): boolean {
    if (!this.enabled) {
      return false;
    }
    const i: number = this.gids.indexOf(gid);
    if (i >= 0) {
      this.gids.splice(i, 1);
    } else {
      this.gids.push(gid);
    }
    return true;
  }

  isSelected(gid: number): boolean {
    return this.gids.indexOf(gid) >= 0;
  }

  count(): number {
    return this.gids.length;
  }

  /** 选中项快照（应用时用） */
  selected(): number[] {
    return this.gids.slice();
  }

  /** 上游应用/取消后的收尾：清空 + 关闭模式 */
  consume(): number[] {
    const out: number[] = this.gids.slice();
    this.gids = [];
    this.enabled = false;
    return out;
  }
}

/**
 * 在线收藏分页（上游 `current: Int = 0 // -1 for error` / `limit: Int = 0 // -1 for error`）
 *
 * 一手语义：**`-1` 是错误哨兵，`0` 是合法值**（第 0 页 / 0 条上限）。
 *   ⇒ 判"是否出错"必须 `=== -1`，**不能**用 `< 0` 之外的真值判断，更不能把 0 当"未初始化"。
 */
export class PagingState {
  static readonly ERROR: number = -1;

  /** 已加载到第几页（-1 = 出错） */
  current: number = 0;
  /** 总页数（-1 = 出错） */
  limit: number = 0;

  reset(): void {
    this.current = 0;
    this.limit = 0;
  }

  /** 上游 FavoritesParser.Result 的落值 */
  set(current: number, limit: number): void {
    this.current = current;
    this.limit = limit;
  }

  isError(): boolean {
    return this.current === PagingState.ERROR || this.limit === PagingState.ERROR;
  }

  /** 还有下一页：**非错误且 current < limit**（limit=0 时恒 false） */
  hasMore(): boolean {
    if (this.isError()) {
      return false;
    }
    return this.current < this.limit;
  }

  /** 成功加载一页后前进 */
  advance(): void {
    if (this.isError()) {
      return;
    }
    this.current = this.current + 1;
  }
}
/* ============================ Part 3：分页接线 / 抽屉分类 / 批量应用 ============================ */

/**
 * 收藏夹哨兵值 —— **三个哨兵 + 10 个合法值**（一手来自 `client/data/FavListUrlBuilder.java`）
 *
 *   `FAV_CAT_LOCAL = -2`（本地收藏，**不发请求**）
 *   `FAV_CAT_ALL   = -1`（全部分类，**不加 favcat 参数**）
 *   `0..9`          = 具体收藏夹（唯一会 `addQuery("favcat", n)` 的取值）
 *
 * ⚠ 回答 Lead 的疑问：**`cat = 0` 是"第一个收藏夹"，不是"全部"。**
 *   "全部" 是 `-1`。把 0 当"全部"会让"第一个收藏夹"永远显示全部收藏。
 *
 * 抽屉位置映射（上游 `onItemClick` 注释原文：
 *   "Local favorite position is 0, All favorite position is 1, so position - 2 is OK"）：
 *   position 0 → LOCAL(-2)；position 1 → ALL(-1)；position 2..11 → 0..9
 */
export class FavCatSentinel {
  static readonly LOCAL: number = -2;
  static readonly ALL: number = -1;

  /** 位置 → favCat（上游 `position - 2`） */
  static fromDrawerPosition(position: number): number {
    return position - 2;
  }

  /** favCat → 位置（`fromDrawerPosition` 的逆；LOCAL/ALL/0..9 都有唯一位置） */
  static toDrawerPosition(favCat: number): number {
    return favCat + 2;
  }

  /** 是否要发"在线收藏"请求（LOCAL 与 ALL 都不带 favcat 参数，但 ALL 仍是在线查询） */
  static needsFavCatParam(favCat: number): boolean {
    return favCat >= 0 && favCat <= 9;
  }

  /** 是否本地收藏（不发请求，读库） */
  static isLocal(favCat: number): boolean {
    return favCat === FavCatSentinel.LOCAL;
  }
}

/** 抽屉条目（Local / All / 10 个分类） */
export class DrawerEntry {
  favCat: number = FavCatSentinel.ALL;
  /** 显示名（分类未命名时由调用方给默认文案） */
  label: string | null = null;
  /** 条数（Local 用 localCount，All 用 sum，分类用各自 count） */
  count: number = 0;
  isCategory: boolean = false;

  constructor(favCat: number, label: string | null, count: number, isCategory: boolean) {
    this.favCat = favCat;
    this.label = label;
    this.count = count;
    this.isCategory = isCategory;
  }
}

/**
 * 在线收藏请求参数。
 * **URL 拼接不在此处** —— 消费已交付的 `client/data/FavListUrlBuilder.ets`（`build()` / `buildForPageAction()`）。
 *
 * 上游契约（`EhClient.java` 的 dispatcher 逐字）：
 *   `case METHOD_GET_FAVORITES: EhEngine.getFavorites(this, mOkHttpClient, (String) params[0], (Boolean) params[1])`
 *   ⇒ **`params[0]` 是完整 URL 字符串，`params[1]` 是 `force`** —— 不是 (cat, page) 二元组。
 */
export class FavoritesQuery {
  favCat: number = FavCatSentinel.ALL;
  page: number = 0;
  keyword: string = '';

  constructor(favCat: number, page: number, keyword: string) {
    this.favCat = favCat;
    this.page = page;
    this.keyword = keyword;
  }

  /** 是否本地收藏（走读库，不发请求） */
  isLocal(): boolean {
    return FavCatSentinel.isLocal(this.favCat);
  }
}

/**
 * 在线收藏分页加载器 —— 对位 `GalleryInfoContentHelper` + `EhClient.METHOD_FAVORITES` 的接线。
 * 请求由 `FavoritesClientLike` 注入（net-parse 的 EhClient 形态未定，不硬等）。
 */
export interface FavoritesClientLike {
  /**
   * 对齐 `EhClient` 的 `METHOD_GET_FAVORITES`（= 8）：
   * `getFavorites(url: string, force: boolean)`。
   * @param url   由 `FavListUrlBuilder.build()` 产出
   * @param force 上游 `params[1]`
   */
  getFavorites(url: string, force: boolean): Promise<FavoritesPageResult>;
}

/** 一页结果（对位 FavoritesParser.Result 的 `current` / `limit`） */
export class FavoritesPageResult {
  /** 当前页（**0 是合法值**） */
  current: number = 0;
  /** 总页数（**0 是合法值**；-1 表示错误） */
  limit: number = 0;
  /** 本页条目数 */
  count: number = 0;
  /** 本页画廊列表 */
  items: GalleryInfo[] = [];
  /** 云端 10 个收藏夹名称 */
  catArray: string[] = [];
  /** 云端 10 个收藏夹计数 */
  countArray: number[] = [];
  prevHref: string = '';
  nextHref: string = '';
}

export class OnlineFavoritesLoader {
  paging: PagingState = new PagingState();
  query: FavoritesQuery = new FavoritesQuery(FavCatSentinel.ALL, 0, '');
  private client: FavoritesClientLike | null = null;
  /** 消费已交付的 FavListUrlBuilder（URL 拼接的唯一实现处） */
  urlBuilder: FavListUrlBuilder = new FavListUrlBuilder();
  private loading: boolean = false;
  private pageIndex: number = 0;
  private seq: number = 0;
  private onResultCb: ((result: FavoritesPageResult, append: boolean, page: number) => void) | null = null;
  private onErrorCb: ((err: Error) => void) | null = null;
  /** 上一次失败原因（null = 无错误） */
  lastError: string | null = null;

  setClient(client: FavoritesClientLike): void {
    this.client = client;
  }

  setCallbacks(
    onResult: ((result: FavoritesPageResult, append: boolean, page: number) => void) | null,
    onError: ((err: Error) => void) | null
  ): void {
    this.onResultCb = onResult;
    this.onErrorCb = onError;
  }

  setCategory(favCat: number, keyword: string): void {
    this.seq = this.seq + 1;
    this.loading = false;
    this.pageIndex = 0;
    this.query = new FavoritesQuery(favCat, 0, keyword);
    this.urlBuilder.setFavCat(favCat);
    this.urlBuilder.setKeyword(keyword.length > 0 ? keyword : null);
    this.urlBuilder.setIndex(0);
    this.paging.reset();
    this.lastError = null;
  }

  isLoading(): boolean {
    return this.loading;
  }

  /** 是否还能再拉一页：**已到末页 / 出错 / 正在加载 / 本地分类** → false */
  canLoadMore(): boolean {
    if (this.loading) {
      return false;
    }
    if (FavCatSentinel.isLocal(this.query.favCat)) {
      return false; // 本地收藏走读库，不走分页
    }
    if (this.paging.isError()) {
      return false;
    }
    if (this.pageIndex === 0 && this.paging.limit === 0) {
      return true;
    }
    return this.pageIndex < this.paging.limit || this.paging.hasMore();
  }

  /**
   * 拉下一页。返回是否发起了请求。
   * 出错时把 `PagingState` 置为 `-1/-1`（上游 `current/limit = -1 for error`）。
   */
  loadNext(force: boolean = false): boolean {
    if (!force && !this.canLoadMore()) {
      return false;
    }
    if (force && (this.loading || FavCatSentinel.isLocal(this.query.favCat))) {
      return false;
    }
    const client: FavoritesClientLike | null = this.client;
    if (client === null) {
      this.lastError = 'client_not_injected';
      this.paging.set(PagingState.ERROR, PagingState.ERROR);
      const errCb: ((err: Error) => void) | null = this.onErrorCb;
      if (errCb !== null) {
        errCb(new Error('client_not_injected'));
      }
      return false;
    }
    const reqSeq: number = ++this.seq;
    const reqPage: number = force ? 0 : this.pageIndex;
    const append: boolean = reqPage > 0;
    this.urlBuilder.setIndex(reqPage);
    this.loading = true;
    const url: string = this.urlBuilder.build();
    client.getFavorites(url, force).then((r: FavoritesPageResult) => {
      if (reqSeq !== this.seq) {
        return;
      }
      this.loading = false;
      this.lastError = null;
      this.paging.set(r.current, r.limit);
      this.pageIndex = reqPage + 1;
      this.urlBuilder.setIndex(this.pageIndex);
      this.query = new FavoritesQuery(this.query.favCat, this.pageIndex, this.query.keyword);
      const okCb: ((result: FavoritesPageResult, isAppend: boolean, page: number) => void) | null = this.onResultCb;
      if (okCb !== null) {
        okCb(r, append, reqPage);
      }
    }).catch((e: Error) => {
      if (reqSeq !== this.seq) {
        return;
      }
      this.loading = false;
      this.lastError = e.message !== undefined ? e.message : String(e);
      this.paging.set(PagingState.ERROR, PagingState.ERROR);
      // lastError 是给 UI 看的，但**日志里没有痕迹** —— 排查时只能看到"列表报错了"，
      // 不知道是网络 / 收藏夹不存在 / 解析失败。silent-failures 闸门的 B2 抓的就是这个。
      hilog.error(0x0000, 'FavoritesScene', 'loadFavorites failed: favCat=%{public}d, err=%{public}s',
        this.query.favCat, this.lastError);
      const errCb: ((err: Error) => void) | null = this.onErrorCb;
      if (errCb !== null) {
        errCb(e);
      }
    });
    return true;
  }
}

/** 批量修改的请求计划（`ModifyState.consume()` 之后交给 EhClient 的东西） */
/** 对齐 EhClient.METHOD_MODIFY_FAVORITES（= 11）：modifyFavorites(token, gids: long[], favCat, add) */
export class ModifyPlan {
  valid: boolean = false;
  reason: string = '';
  favCat: number = 0;
  add: boolean = true;
  gids: number[] = [];
  /** 上游 params[0]：页面 token（由调用方注入，本类不持有网络状态） */
  token: string = '';
}

export class ModifyApplier {
  /**
   * 上游批量修改的应用动作：
   *   · **选中为空 → 不发请求**（上游 `if (mModifyGiList.isEmpty()) return`）
   *   · **分类必须是 0..9**（`FAV_CAT_ALL`/`LOCAL` 不是合法目标，上游只让选 10 个分类之一）
   *   · 计划里带"加入/移出"方向
   */
  static buildPlan(state: ModifyState): ModifyPlan {
    const plan: ModifyPlan = new ModifyPlan();
    const gids: number[] = state.selected();
    if (gids.length === 0) {
      plan.valid = false;
      plan.reason = 'empty_selection';
      return plan;
    }
    if (!FavCatModel.isValidCat(state.favCat)) {
      plan.valid = false;
      plan.reason = 'invalid_fav_cat';
      return plan;
    }
    plan.valid = true;
    plan.favCat = state.favCat;
    plan.add = state.add;
    plan.gids = gids;
    return plan;
  }
}
/* ============================ Part 4：排序入口（消费 S0192 FavoriteListSortDialog）============================ */

/**
 * 排序入口接线 —— **消费** `ui/dialog/FavoriteListSortDialog.ets`（S0192，owner gl-render，已 ported）。
 * 本类不重写排序逻辑，只做"何时弹 / 弹出来选中哪项 / 选完做什么"。
 *
 * 上游 `FavoriteListSortDialog.kt` 的一手契约（C-19：逐字抄调用点）：
 * ```kotlin
 * class FavoriteListSortDialog(private val scene: FavoritesScene) {
 *   fun showCloudSort(mResult: FavoritesParser.Result?) {
 *     if (null == mResult || null == mResult.favOrder) return          // ← 不弹
 *     checked = if (favOrder == ORDER_BY_FAV_TIME) 0 else 1
 *     ...
 *     DialogInterface.OnClickListener { _, i ->
 *       if (i == 0) scene.updateSort("inline_set=fs_f") else scene.updateSort("inline_set=fs_p")
 *       dismiss()
 *     }
 *   }
 *   fun showLocalSort(mResult) { }                                     // ← **空方法**
 * }
 * ```
 * 场景侧：`fun updateSort(sort: String?) { if (null == mHelper) return; mHelper!!.refreshSort(sort) }`
 * → `ContentHelper.refreshSort` = `showProgressBar(); TYPE_REFRESH; page=0; getPageData(..., sort)`
 * ⇒ **排序变更 = 带 sort 重新请求第 0 页**，不是本地重排（`favOrder` 由服务端给）。
 *
 * 三个判据（决定了接线位置）：
 *   ① 何时弹：结果到达后，按 `FavoriteListSortDialogPlan.plan(result).show` 决定（未知排序值**不弹**）
 *   ② 选中项：`plan(result).checked`（0=收藏时间 / 1=发布时间）
 *   ③ 选完做什么：`sortForIndex(i)` → `refreshSort(sort)`（**重新请求**，paging 回到第 0 页）
 *   ④ 本地分类：调 `showLocalSort`（空实现）—— **不弹、不请求**
 */
export class FavoritesSortEntry {
  /** 对话框当前是否应显示（由最近一次结果决定） */
  dialogVisible: boolean = false;
  /** 对话框初始选中项（0=收藏时间 / 1=发布时间） */
  checkedIndex: number = FavoriteListSortDialogPlan.INDEX_FAV_TIME;
  /** 最近一次应用的排序串（null = 从未应用） */
  appliedSort: string | null = null;

  /**
   * 结果到达 → 决定是否弹框。**本地分类直接走 `showLocalSort`（空实现），不弹**。
   * @param isLocalFavCat 当前分类是否本地收藏
   */
  onResult(result: FavoritesResult | null, isLocalFavCat: boolean): boolean {
    if (isLocalFavCat) {
      FavoriteListSortDialogPlan.showLocalSort(result); // 上游空方法：保持调用以对齐结构
      this.dialogVisible = false;
      return false;
    }
    const plan: FavoriteSortDialogPlan = FavoriteListSortDialogPlan.plan(result);
    this.dialogVisible = plan.show;
    this.checkedIndex = plan.checked;
    return plan.show;
  }

  /** 用户点选 → 返回要回传给场景的排序串（并记录） */
  onSelected(index: number): string {
    const sort: string = FavoriteListSortDialogPlan.sortForIndex(index);
    this.appliedSort = sort;
    this.dialogVisible = false;
    return sort;
  }

  /** 是否已应用过排序（用于判断"要不要带 sort 请求"） */
  hasAppliedSort(): boolean {
    return this.appliedSort !== null;
  }
}

/** 场景侧 `updateSort` 的依赖（对位 `mHelper.refreshSort`） */
export interface SortRefreshHost {
  refreshSort(sort: string): void;
}

/**
 * 对位上游 `FavoritesScene.updateSort(sort)`：
 * `if (null == mHelper) return; mHelper.refreshSort(sort)`。
 * **helper 为空时不请求也不崩**（上游同语义）。
 */
export class FavoritesSortApplier {
  static updateSort(host: SortRefreshHost | null, sort: string | null): boolean {
    if (host === null) {
      return false;
    }
    if (sort === null || sort.length === 0) {
      return false;
    }
    host.refreshSort(sort);
    return true;
  }
}
/* ============================ Part 5：批量删除 / 移动（DeleteDialogHelper / MoveDialogHelper）============================ */

/**
 * 批量**删除**（上游 `DeleteDialogHelper`，逐字语义）：
 * ```
 * if (which != BUTTON_POSITIVE) return                       // 只有确认才删
 * outOfCustomChoiceMode()
 * if (favCat == FAV_CAT_LOCAL) {                             // 本地：直接删库
 *     EhDB.removeLocalFavorites(gidArray); mModifyGiList.clear(); mHelper.refresh()
 * } else {                                                    // 云端：走批量修改协议
 *     mEnableModify = true; mModifyFavCat = -1; mModifyAdd = false; mHelper.refresh()
 * }
 * onCancel → mModifyGiList.clear()
 * ```
 * ⚠ 云端删除的 `mModifyFavCat = **-1（FAV_CAT_ALL）**` 不是笔误 ——
 * "从全部分类里移出"就是上游表达"删除收藏"的方式（收藏必然属于某个分类，`-1` 覆盖全部）。
 */
export class DeletePlan {
  /** 是否执行（取消/无选择 → false） */
  valid: boolean = false;
  /** 本地删除：直接删库 */
  localDelete: boolean = false;
  /** 本地删除的 gid 列表 */
  gids: number[] = [];
  /** 云端删除：交给批量修改协议的 (favCat, add) */
  modifyFavCat: number = FavCatSentinel.ALL;
  modifyAdd: boolean = false;
}

/**
 * 批量**移动**（上游 `MoveDialogHelper`，逐字语义）：
 * ```
 * srcCat = mUrlBuilder.getFavCat()
 * dstCat = if (which == 0) FAV_CAT_LOCAL else which - 1     // ← 注意是 **which - 1**
 * if (srcCat == dstCat) return                              // 同分类不动
 * outOfCustomChoiceMode()
 * 本地 → 云端：removeLocalFavorites(gids); modifyFavCat = dstCat; modifyAdd = true;  refresh()
 * 云端 → 本地：putLocalFavorites(giList);   modifyFavCat = -1;     modifyAdd = false; refresh()
 * 云端 → 云端：                             modifyFavCat = dstCat; modifyAdd = false; refresh()
 * ```
 * ⚠⚠ **同一场景里有三套 `which` 映射，各不相同，不能统一**：
 *   · 默认收藏夹对话框：`putDefaultFavSlot(which - 2)`（0=让我选, 1=本地, 2..11=分类）
 *   · 移动对话框      ：`which == 0 ? LOCAL : which - 1`（0=本地, 1..10=分类）
 *   · 抽屉位置        ：`newFavCat = position - 2`（0=本地, 1=全部, 2..11=分类）
 */
export class MovePlan {
  valid: boolean = false;
  reason: string = '';
  /** 源分类（当前 favCat） */
  srcCat: number = FavCatSentinel.ALL;
  /** 目标分类 */
  dstCat: number = FavCatSentinel.ALL;
  /** 本地 → 云端：先删本地 */
  removeLocal: boolean = false;
  /** 云端 → 本地：先写本地 */
  putLocal: boolean = false;
  /** 交给批量修改协议的目标分类（云端→本地时是 -1） */
  modifyFavCat: number = FavCatSentinel.ALL;
  /** 交给批量修改协议的方向 */
  modifyAdd: boolean = false;
  /** 需要移动到云端的 gid（本地→云端用） */
  gids: number[] = [];
}

export class FavoritesBatchOps {
  /** 上游移动对话框的 `which` → `dstCat`（**与默认收藏夹对话框的 `which - 2` 不同**） */
  static moveDstCat(which: number): number {
    return which === 0 ? FavCatSentinel.LOCAL : which - 1;
  }

  /** 上游删除：`which != BUTTON_POSITIVE` 直接 return（本实现用 confirmed 表达） */
  static buildDeletePlan(confirmed: boolean, srcCat: number, selected: number[]): DeletePlan {
    const plan: DeletePlan = new DeletePlan();
    if (!confirmed || selected.length === 0) {
      return plan;
    }
    plan.valid = true;
    if (srcCat === FavCatSentinel.LOCAL) {
      plan.localDelete = true;
      plan.gids = selected.slice();
      return plan;
    }
    // 云端删除 = 从全部分类移出（-1 覆盖全部）
    plan.localDelete = false;
    plan.modifyFavCat = FavCatSentinel.ALL;
    plan.modifyAdd = false;
    return plan;
  }

  /**
   * 上游移动。
   * @param confirmed 是否确认（取消时清空选择，见上游 onCancel）
   */
  static buildMovePlan(confirmed: boolean, srcCat: number, which: number, selected: number[]): MovePlan {
    const plan: MovePlan = new MovePlan();
    plan.srcCat = srcCat;
    if (!confirmed || selected.length === 0) {
      plan.reason = 'not_confirmed_or_empty';
      return plan;
    }
    const dstCat: number = FavoritesBatchOps.moveDstCat(which);
    plan.dstCat = dstCat;
    if (srcCat === dstCat) {
      plan.reason = 'same_category'; // 上游 `if (srcCat == dstCat) return`
      return plan;
    }
    if (dstCat !== FavCatSentinel.LOCAL && dstCat !== FavCatSentinel.ALL && !FavCatModel.isValidCat(dstCat)) {
      plan.reason = 'invalid_dst_cat';
      return plan;
    }
    plan.valid = true;
    if (srcCat === FavCatSentinel.LOCAL) {
      // 本地 → 云端
      plan.removeLocal = true;
      plan.gids = selected.slice();
      plan.modifyFavCat = dstCat;
      plan.modifyAdd = true;
    } else if (dstCat === FavCatSentinel.LOCAL) {
      // 云端 → 本地
      plan.putLocal = true;
      plan.modifyFavCat = FavCatSentinel.ALL;
      plan.modifyAdd = false;
    } else {
      // 云端 → 云端
      plan.modifyFavCat = dstCat;
      plan.modifyAdd = false;
    }
    return plan;
  }
}
/* ============================ Part 6：FAB 槽位 / 返回键顺序 / 跳转日期接线 ============================ */

/**
 * FAB 槽位（上游 `FabLayout` 的 8 个次级 FAB + 第 8 号"全选"槽）
 *
 * 一手语义（`showNormalFabsRunnable` / `showSelectionFabs` / `onClickSecondaryFab`）：
 * ```
 * 普通态可见：0,1,5,6,7    隐藏：2,3,4,8      ← 且 **延迟 300ms** 再显示（上游注释 "Delay showing normal fabs to avoid mutation"）
 * 多选态可见：2,3,4,8      隐藏：0,1,5,6,7
 *
 * 普通态点击：0 → canGoTo 时弹跳页对话框 · 1 → refresh · 5 → RandomFavorite(context) · 6 → RandomFavorite().random()
 *             7 → 排序对话框（本地 → showLocalSort；云端 → showCloudSort）· 之后 `view.setExpanded(false)`
 * 多选态点击：2 → 下载（CommonOperations.startDownload + 清空选择 + 退出多选）
 *             3 → 删除（DeleteDialogHelper）· 4 → 移动（MoveDialogHelper）· 8 → 全选/取消全选
 * ```
 * ⚠ 槽位 **8** 不是第 9 个次级 FAB，而是 `mFabLayout.get(8)` 的全选按钮（图标在
 * `v_check_dark_x24` / `v_check_all_dark_x24` 之间切换，见 `checkedAll()`）。
 */
export class FabSlot {
  static readonly GOTO: number = 0;
  static readonly REFRESH: number = 1;
  static readonly DOWNLOAD: number = 2;
  static readonly DELETE: number = 3;
  static readonly MOVE: number = 4;
  static readonly RANDOM_FIRST: number = 5;
  static readonly RANDOM: number = 6;
  static readonly SORT: number = 7;
  static readonly SELECT_ALL: number = 8;

  static readonly SLOT_COUNT: number = 9;
  /** 上游 `postDelayed(showNormalFabsRunnable, 300)` */
  static readonly NORMAL_FABS_DELAY_MS: number = 300;

  /** 普通态可见槽位 */
  static readonly NORMAL_VISIBLE: number[] = [0, 1, 5, 6, 7];
  /** 多选态可见槽位 */
  static readonly SELECTION_VISIBLE: number[] = [2, 3, 4, 8];

  /** 给定模式下的 9 个槽位可见性数组（下标 = 槽位号） */
  static visibility(inCustomChoice: boolean): boolean[] {
    const out: boolean[] = [];
    for (let i = 0; i < FabSlot.SLOT_COUNT; i++) {
      out.push(false);
    }
    const visible: number[] = inCustomChoice ? FabSlot.SELECTION_VISIBLE : FabSlot.NORMAL_VISIBLE;
    for (let i = 0; i < visible.length; i++) {
      out[visible[i]] = true;
    }
    return out;
  }
}

/** FAB 点击后的意图（纯数据，UI 由 scene 体系渲染） */
export class FabIntent {
  /** 是否有动作（false = 空操作，例如 canGoTo 为假时的槽位 0） */
  action: boolean = false;
  /** 动作种类（见 FabIntentKind） */
  kind: string = '';
}

export class FabIntentKind {
  static readonly GOTO: string = 'goto';
  static readonly REFRESH: string = 'refresh';
  static readonly DOWNLOAD: string = 'download';
  static readonly DELETE: string = 'delete';
  static readonly MOVE: string = 'move';
  static readonly RANDOM_FIRST: string = 'random_first';
  static readonly RANDOM: string = 'random';
  static readonly SORT: string = 'sort';
  static readonly SELECT_ALL: string = 'select_all';
}

export class FabDispatcher {
  /**
   * 上游 `onClickSecondaryFab` 的净效果。
   * @param inCustomChoice 当前是否多选态
   * @param canGoTo        `mHelper.canGoTo()`（槽位 0 / 5 的前置）
   */
  static dispatch(position: number, inCustomChoice: boolean, canGoTo: boolean): FabIntent {
    const r: FabIntent = new FabIntent();
    if (inCustomChoice) {
      if (position === FabSlot.DOWNLOAD) {
        r.action = true;
        r.kind = FabIntentKind.DOWNLOAD;
      } else if (position === FabSlot.DELETE) {
        r.action = true;
        r.kind = FabIntentKind.DELETE;
      } else if (position === FabSlot.MOVE) {
        r.action = true;
        r.kind = FabIntentKind.MOVE;
      } else if (position === FabSlot.SELECT_ALL) {
        r.action = true;
        r.kind = FabIntentKind.SELECT_ALL;
      }
      return r;
    }
    if (position === FabSlot.GOTO) {
      if (canGoTo) {
        r.action = true;
        r.kind = FabIntentKind.GOTO;
      }
      return r;
    }
    if (position === FabSlot.REFRESH) {
      r.action = true;
      r.kind = FabIntentKind.REFRESH;
    } else if (position === FabSlot.RANDOM_FIRST) {
      if (canGoTo) {
        r.action = true;
        r.kind = FabIntentKind.RANDOM_FIRST;
      }
    } else if (position === FabSlot.RANDOM) {
      r.action = true;
      r.kind = FabIntentKind.RANDOM;
    } else if (position === FabSlot.SORT) {
      r.action = true;
      r.kind = FabIntentKind.SORT;
    }
    return r;
  }
}

/** 返回键处理结果 */
export class BackDecision {
  /** 是否已消费（true = 不再向上传递 / 不 finish） */
  consumed: boolean = false;
  /** 是否应 finish 场景 */
  finish: boolean = false;
  /** 消费者的名字（便于断言与日志） */
  by: string = '';
}

export class BackHandler {
  /**
   * 上游 `onBackPressed` 的**四级顺序**（逐字）：
   * ```
   * if (null != mShowcaseView) return                       // ① 引导层开着 → 吞掉
   * if (isInCustomChoice) outOfCustomChoice()               // ② 退出多选
   * else if (mFabLayout.isExpanded()) mFabLayout.toggle()   // ③ 收起 FAB
   * else if (mSearchMode) exitSearchMode(true)              // ④ 退出搜索
   * else finish()                                           // ⑤ 结束场景
   * ```
   * ⚠ ① 的引导层（`ShowcaseView`）**已按 D-073 删除** ⇒ 该分支在本仓库恒为假。
   *   保留形参与判据是为了**让顺序可测**，且将来若引入引导层只需把 flag 置真。
   */
  static onBackPressed(guideVisible: boolean, inCustomChoice: boolean, fabExpanded: boolean,
                       searchMode: boolean): BackDecision {
    const d: BackDecision = new BackDecision();
    if (guideVisible) {
      d.consumed = true;
      d.by = 'guide';
      return d;
    }
    if (inCustomChoice) {
      d.consumed = true;
      d.by = 'customChoice';
      return d;
    }
    if (fabExpanded) {
      d.consumed = true;
      d.by = 'fab';
      return d;
    }
    if (searchMode) {
      d.consumed = true;
      d.by = 'search';
      return d;
    }
    d.consumed = false;
    d.finish = true;
    d.by = 'finish';
    return d;
  }
}

/**
 * 跳转日期接线（上游 `onTimeSelected(urlAppend)`）：
 * ```
 * if (urlAppend.isEmpty() || mHelper == null || jumpSelectorDialog == null || mUrlBuilder == null) return
 * jumpSelectorDialog.dismiss()
 * mHelper.nextHref = mUrlBuilder.jumpHrefBuild(mHelper.nextHref, urlAppend)
 * mHelper.goTo(-996)                                    // ← **-996 是哨兵**
 * ```
 * ⚠ `goTo(-996)` 是上游的"不要改页码、按 nextHref 重新取"的哨兵值（不是页码）。
 *   断言把它钉住：**把它当页码会跳到第 -997 页**。
 */
export class JumpDateWiring {
  static readonly GOTO_SENTINEL: number = -996;

  /** 是否应执行（空串/依赖缺失 → false） */
  static canApply(urlAppend: string, hasHelper: boolean, hasDialog: boolean, hasUrlBuilder: boolean): boolean {
    return urlAppend.length > 0 && hasHelper && hasDialog && hasUrlBuilder;
  }

  /** 上游的净效果：先拼 nextHref，再用 -996 触发重取 */
  static apply(urlAppend: string, nextHref: string,
               build: (nextHref: string, append: string) => string,
               goTo: (page: number) => void): boolean {
    if (urlAppend.length === 0) {
      return false;
    }
    const built: string = build(nextHref, urlAppend);
    goTo(JumpDateWiring.GOTO_SENTINEL);
    return built.length > 0 || built === '';
  }
}
/* ============================ Part 7：拖拽处理器 / 跳页对话框决策 ============================ */

/**
 * 拖拽处理器（上游 `onStartDragHandler` / `onEndDragHandler`，逐字）：
 * ```
 * onStartDragHandler: setDrawerLockMode(LOCK_MODE_LOCKED_CLOSED, Gravity.RIGHT)      // 锁右抽屉
 * onEndDragHandler:   if (mRecyclerView != null && !isInCustomChoice())
 *                         setDrawerLockMode(LOCK_MODE_UNLOCKED, Gravity.RIGHT)       // 解锁右抽屉
 *                     if (mSearchBarMover != null) returnSearchBarPosition()         // 搜索栏归位
 * ```
 * ⚠ 两个不对称点（容易写错）：
 *   ① **开始拖拽无条件锁**；结束拖拽**只在"非多选态"时解锁** —— 多选态下拖拽结束后右抽屉保持锁定
 *   ② **搜索栏归位无条件执行**（与抽屉解锁的守卫无关）
 */
export class DragHandlerState {
  /** 右抽屉是否处于锁定关闭 */
  rightDrawerLocked: boolean = false;

  /** 上游 onStartDragHandler：无条件锁 */
  onStartDrag(): void {
    this.rightDrawerLocked = true;
  }

  /**
   * 上游 onEndDragHandler。
   *
   * ⚠ **接线修正（C-19）**：上游调的是 `mSearchBarMover.returnSearchBarPosition()`，
   * 但本仓库 `hippo/widget/SearchBarMover.ets` 的对位方法名是 **`onScrollIdle()`**
   * （它的 doc 写着"对位 onScrollStateChanged(IDLE)：回弹到目标位置"，文件里**没有**叫
   * `returnSearchBarPosition` 的方法）—— 按上游名字猜会编译不过。
   *
   * @param mover 搜索栏 mover；`null` 表示未注入（上游 `if (mSearchBarMover != null)`）
   * @returns 归位后"搜索栏是否应显示"（上游由 mover 内部状态决定）
   */
  onEndDrag(inCustomChoice: boolean, mover: SearchBarMoverState | null): boolean {
    if (!inCustomChoice) {
      this.rightDrawerLocked = false;
    }
    if (mover === null) {
      return false;
    }
    return mover.onScrollIdle();
  }
}

/** 跳页对话框的决策结果 */
export class GoToDialogPlan {
  /** 无动作（context/helper 缺失，或日期跳转时 nextHref 为空 → 只弹 toast） */
  none: boolean = false;
  /** 用"日期跳转"（上游 `mHelper.mPages < 0` 时） */
  dateJump: boolean = false;
  /** 用"页码跳转" */
  pageJump: boolean = false;
  /** 只弹 toast（`gallery_list_no_more_data`） */
  toastNoMoreData: boolean = false;
  /** 页码跳转的提示文案参数：当前页（0 基）与总页数 */
  pageForTop: number = 0;
  pages: number = 0;
}

export class GoToDialogMath {
  /**
   * 上游 `showGoToDialog`：**`mHelper.mPages < 0` → 日期跳转，否则页码跳转**。
   * ⚠ `mPages < 0` 是"页数未知"的哨兵（上游 `mPages` 初始 -1）—— 不是"0 页"。
   */
  static plan(hasContext: boolean, hasHelper: boolean, pages: number, pageForTop: number): GoToDialogPlan {
    const p: GoToDialogPlan = new GoToDialogPlan();
    if (!hasContext || !hasHelper) {
      p.none = true;
      return p;
    }
    if (pages < 0) {
      p.dateJump = true;
      return p;
    }
    p.pageJump = true;
    p.pageForTop = pageForTop;
    p.pages = pages;
    return p;
  }

  /**
   * 上游 `showPageJumpDialog` 的输入校验（逐字）：
   * ```
   * text = builder.text.trim()
   * try { goTo = text.toInt() - 1 } catch (NumberFormatException) { setError(error_invalid_number); return }
   * if (goTo < 0 || goTo >= pages) { setError(error_out_of_range); return }
   * setError(null); mHelper.goTo(goTo)
   * ```
   * ⇒ 用户输入是 **1 基**，内部页码 **0 基**；**越界检查在减 1 之后**。
   * @returns 目标页码；-1 表示非法（调用方按 reason 给错误文案）
   */
  static parsePageInput(raw: string, pages: number): PageInputResult {
    const r: PageInputResult = new PageInputResult();
    const text: string = raw.trim();
    // 上游 Integer.parseInt：只接受可选符号 + 十进制数字（不接受空、不接受小数）
    if (!GoToDialogMath.isInteger(text)) {
      r.reason = 'invalid_number';
      return r;
    }
    const goTo: number = Number.parseInt(text, 10) - 1;
    if (goTo < 0 || goTo >= pages) {
      r.reason = 'out_of_range';
      return r;
    }
    r.valid = true;
    r.page = goTo;
    return r;
  }

  /** 上游 Integer.parseInt 的可接受形态（"+12" 也合法，"-3" 合法但会被越界检查拦下） */
  static isInteger(text: string): boolean {
    if (text.length === 0) {
      return false;
    }
    let i: number = 0;
    if (text.charAt(0) === '+' || text.charAt(0) === '-') {
      i = 1;
    }
    if (i >= text.length) {
      return false;
    }
    for (; i < text.length; i++) {
      const c: string = text.charAt(i);
      if (c < '0' || c > '9') {
        return false;
      }
    }
    return true;
  }
}

export class PageInputResult {
  valid: boolean = false;
  page: number = -1;
  /** 'invalid_number' | 'out_of_range' | '' */
  reason: string = '';
}
/**
 * `FavoritesClientLike` 的真实实现（W-09 云端侧）。
 *
 * C-19 核对（先读实现）：
 * ```
 * FavoritesParser.ets  export class FavoritesResult {
 *                        catArray / countArray / pages / nextPage / resultCount /
 *                        firstHref / prevHref / nextHref / lastHref / favOrder / galleryInfoList }
 * EhEngine.ets:634     static async getFavorites(task, caller, url, callApi): Promise<FavoritesResult>
 * ```
 * **`FavoritesResult` 里没有 `current` / `limit`** —— 分页信息是 `nextPage` / `pages`。
 * （上游 `FavoritesScene.kt:148-149` 确实声明了 `var current = 0 // -1 for error` 与
 *  `var limit = 0 // -1 for error`，但**全文件再无赋值或读取** —— 是遗留的死字段。
 *  本 adapter 用 `nextPage/pages` 映射到本类的 `current/limit`，语义等价且是**实际在用**的那一对。）
 *
 * 注入方式用函数（不 import net-parse 的 `EhEngine`）—— 与 `LocalFavoritesRepoAdapter` 同模式，
 * `AppWiring` 是唯一知道"谁实现谁"的地方（C-13）。
 * 接线示例（AppWiring）：
 * ```
 * scene.setClient(new EhClientFavoritesAdapter(
 *   (url, force) => EhEngine.getFavorites(null, caller, url, force)));
 * ```
 */
export interface FavoritesResultLike {
  /** 总页数 */
  pages: number;
  /** 下一页页码 */
  nextPage: number;
  /** 本页条目 */
  galleryInfoList: GalleryInfo[];
  catArray?: string[];
  countArray?: number[];
  prevHref?: string;
  nextHref?: string;
}

export class EhClientFavoritesAdapter implements FavoritesClientLike {
  private readonly fetch: (url: string, force: boolean) => Promise<FavoritesResultLike>;

  constructor(fetch: (url: string, force: boolean) => Promise<FavoritesResultLike>) {
    this.fetch = fetch;
  }

  async getFavorites(url: string, force: boolean): Promise<FavoritesPageResult> {
    const r: FavoritesResultLike = await this.fetch(url, force);
    const out: FavoritesPageResult = new FavoritesPageResult();
    out.current = r.nextPage;
    out.limit = r.pages;
    out.count = r.galleryInfoList.length;
    out.items = r.galleryInfoList.slice();
    out.catArray = r.catArray !== undefined ? r.catArray.slice() : [];
    out.countArray = r.countArray !== undefined ? r.countArray.slice() : [];
    out.prevHref = r.prevHref !== undefined ? r.prevHref : '';
    out.nextHref = r.nextHref !== undefined ? r.nextHref : '';
    return out;
  }
}