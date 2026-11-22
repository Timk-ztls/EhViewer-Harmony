/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/topList/EhTopListScene.kt
 *       （inventory S0266，上游实际 269 行；清单登记 227 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/topList/EhTopListScene.ets
 *
 * 背景：**EH 排行榜（Top List）页**。顶部 Spinner 切榜单种类（"全部时间/今年/本月…"），
 * 下方列表展示该榜单条目；点标题 → 进列表页（按 follow 过滤）；点条目 → 进详情（有 token）
 * 或按 href 解析跳转，否则按关键词搜。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 顶层常量（**文件级 private**）：
 *   `STATE_INIT=-1 / STATE_NORMAL=0 / STATE_REFRESH=1 / STATE_REFRESH_HEADER=2 / STATE_FAILED=3`
 *   `BACK_PRESSED_INTERVAL=2000`（双击退出间隔 ms）
 *   `TRANSITION_ANIMATION_DISABLED=true`（**动画被关掉了** —— 见「关键行为」4）
 *   `private var mPosition = 0`（**文件级可变状态**，记录当前榜单下标）
 * 字段：`pressBackTime` / `state=STATE_INIT` / `ehTopListDetail` / `viewTransition` / `recyclerView` /
 *      `client` / `request` / `hasFirstRefresh=false`
 * `onCreateView2`：
 *   · `scene_gallery_top_list`；`spinner.setSelection(0)` + `TopListKindSelectedListener`
 *   · `viewTransition = ViewTransition(data_loading_view, page_detail_view)`
 *     —— **注意顺序：0 = loading、1 = 数据**（与 HistoryScene 的 0=content/1=tip 相反！）
 *   · `recyclerView` + `LinearLayoutManager`
 *   · **`if (!hasFirstRefresh) { hasFirstRefresh = true; try { loadData() } catch (EhException) { printStackTrace() } }`
 *     else { bindViewSecond(mPosition); adjustViewVisibility(STATE_NORMAL, true) }**
 *     —— 首刷失败**只 printStackTrace**，之后 `hasFirstRefresh` 仍为 true → **不再重试**
 * `onBackPressed()`：`checkDoubleClickExit()` 为 false 时：`state == STATE_INIT` 才 `request?.cancel()`，
 *   然后 `finish()`
 * `checkDoubleClickExit()`：**`stackIndex != 0` → 返回 false**（不是栈底就不拦）；
 *   距上次 > 2000ms → 记时间 + `showTip(@string/press_twice_exit)` + **返回 true（拦截）**；
 *   否则返回 false（放行 = 退出）
 * `request()`：`context/activity/client` 任一 null → **false**；`url = EhUrl.getTopListUrl()`；
 *   `METHOD_GET_TOP_LIST` + `GetTopListDetailListener(context, stageId, tag)`；**返回 true**
 * `loadData()`：`!requested` → 抛 `EhException("请求数据失败请更换IP地址或检查网络设置是否正确~")`
 * `onGetEhTopListDetailSuccess(detail, index)`：存 detail → `bindViewSecond(index)` → `adjustViewVisibility(STATE_NORMAL, true)`
 * `bindViewSecond(index)`：`detail == null || recyclerView == null || context == null → return`；
 *   否则建 `EhTopListAdapterView(context, rv, detail[index], this, index)`
 * `adjustViewVisibility(newState, animation)`：
 *   `state = newState`；`shouldAnimate = !TRANSITION_ANIMATION_DISABLED && animation`（**恒 false**）
 *   `STATE_INIT | STATE_REFRESH → showView(0)`；**其它（含 STATE_NORMAL/REFRESH_HEADER/FAILED）→ showView(1)**
 *
 * `GetTopListDetailListener.onSuccess(result)` → `onGetEhTopListDetailSuccess(result, 0)`
 *   —— **注意 index 恒传 0**（不是当前 spinner 位置）
 * `onFailure` / `onCancel` → **空实现**
 *
 * `EhTopListAdapterView`：
 *   · `clickTitle(urlFollow)`：`ListUrlBuilder{MODE_TOP_LIST, follow=urlFollow}` → `GalleryListScene.startScene`
 *   · `getRandomColor(position)`：**缓存到 HashMap**（同一下标颜色稳定）；`argb(160, r, g, b)`（**alpha=160**）
 *   · `onItemClick(topListItem, searchType)`：
 *       ① `searchType == 0` → `MODE_NORMAL`；否则 `MODE_UPLOADER`
 *       ② **gid 与 token 都非空** → 起 `GalleryDetailScene`，args 里带
 *          `ProgressScene.KEY_ACTION=ACTION_GALLERY_TOKEN`、`KEY_GID=gid.toLong()`、`KEY_PTOKEN=tag`
 *          （**注意：传的是 `topListItem.tag`，不是 token**）→ return
 *       ③ 否则 `href != null` → `createAnnouncerFromClipboardUrl(href)`；解析成功 → startScene + return
 *       ④ 都失败 → `urlBuilder.keyword = topListItem.value` → 列表页
 * `TopListKindSelectedListener.onItemSelected`：**写文件级 `mPosition = position`** → `bindViewSecond(mPosition)`
 *   （**不重新请求** —— 榜单数据一次性取回全部，切种类只是换 adapter）
 * companion：`KEY_ACTION = "action"` / `ACTION_TOP_LIST = "action_top_list"`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`viewTransition` 的句子是 (loading, data)**：0 = loading、1 = 数据。
 *    而 `adjustViewVisibility` 里 `STATE_INIT/REFRESH → showView(0)`、其余 `showView(1)`。
 *    **与 HistoryScene 正好相反**（那里 0=content、1=tip）—— 两个 Scene 的下标语义不能混用。
 * 2. **`mPosition` 是文件级 `var`**（不是实例字段）：多个 EhTopListScene 实例共享它。
 *    上游如此，照搬（本实现保留为**静态**字段并注明）。
 * 3. **`onSuccess` 里 index 恒传 0**，忽略当前 spinner 位置 —— 刷新后跳回第一个榜单。
 * 4. **`TRANSITION_ANIMATION_DISABLED = true`** → `shouldAnimate` **恒为 false**，
 *    `animation` 参数实际无效（陷阱 100：兼容性分支在目标平台是死代码，但要能说清为什么 ——
 *    上游把这个开关留成常量，是为了"需要时打开"）。
 * 5. **`hasFirstRefresh` 首刷失败也置 true** → 失败后不再重试（要重试只能重建 Scene）。
 * 6. **双击退出只在 `stackIndex == 0` 生效**；且**第一次返回被拦截**（返回 true）。
 * 7. **`state == STATE_INIT` 时才 cancel 请求**（其它状态直接 finish）。
 * 8. **`getRandomColor` 缓存到 HashMap**，否则每次 bind 颜色都会变（视觉抖动）。
 * 9. **详情跳转传的是 `topListItem.tag` 作为 PTOKEN**（字段名是 tag，不是 token）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `BaseScene`（`stackIndex` / `finish` / `showTip`）未落地 → `TopListSceneHost`。
 * 2. `Spinner` → ArkUI `Select`；`ViewTransition` → `adjustViewVisibility` **返回 0/1**（语义见「关键行为」1）。
 * 3. `EhClient.execute(METHOD_GET_TOP_LIST)` → `TopListApi.fetchDetail()` 注入。
 * 4. `createAnnouncerFromClipboardUrl(href)`（ClipboardUtil，本仓库未移植）→ 宿主
 *    `resolveAnnouncerFromUrl(href)`（返回 null 表示解析失败）。
 * 5. `Random` 颜色 → 宿主用 `Math.random()`；缓存策略照搬（HashMap → Map<number, number>）。
 * 6. `Intent/Announcer` → 宿主 `startDetail(gid, pToken)` / `startList(builder)`。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `EhTopListDetail` / `TopListInfo` / `TopListItem` / `ListUrlBuilder`（`hippo/ehviewer/client/data/**`）、
 * `EhUrl.getTopListUrl()`、`hippo/ui/layout/scene_gallery_top_list.ets`。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * `EhTopListAdapter`（上游 `com.hippo.ehviewer.ui.scene.topList.EhTopListAdapter`）——
 * 不在本条清单里（属另一条 inventory 行）；本文件只实现**它的三个回调**
 * （`clickTitle` / `getRandomColor` / `onItemClick`），adapter 本体由那一条交付。
 */

import { EhTopListDetail, TopListInfo, TopListItem } from '../../../client/data/TopList';

/** 五个状态（上游 `@IntDef`：**INIT 是 -1**，其它从 0 起） */
export const STATE_INIT: number = -1;
export const STATE_NORMAL: number = 0;
export const STATE_REFRESH: number = 1;
export const STATE_REFRESH_HEADER: number = 2;
export const STATE_FAILED: number = 3;
/** 双击退出间隔（ms） */
export const BACK_PRESSED_INTERVAL: number = 2000;
/** 上游把转场动画关掉了（见「关键行为」4） */
export const TRANSITION_ANIMATION_DISABLED: boolean = true;
/** 上游 `@string/press_twice_exit` */
export const TIP_PRESS_TWICE: string = 'app.string.press_twice_exit';
/** 上游 `loadData()` 抛的中文原文 */
export const ERR_REQUEST_FAILED: string = '请求数据失败请更换IP地址或检查网络设置是否正确~';
/** 上游 companion 的两个常量 */
export const KEY_ACTION: string = 'action';
export const ACTION_TOP_LIST: string = 'action_top_list';
/** `ProgressScene` 的三个键（详情跳转）
 *  —— 本文件只用字符串常量，避免依赖未落地的 ProgressScene */
export const PROGRESS_KEY_ACTION: string = 'action';
export const PROGRESS_KEY_GID: string = 'gid';
export const PROGRESS_KEY_PTOKEN: string = 'ptoken';
export const PROGRESS_ACTION_GALLERY_TOKEN: string = 'gallery_token';
/** 上游两种搜索模式（`ListUrlBuilder.MODE_*`） */
export const MODE_NORMAL: number = 0;
export const MODE_UPLOADER: number = 1;
export const MODE_TOP_LIST: number = 2;
/** 随机色 alpha 固定 160 */
export const RANDOM_COLOR_ALPHA: number = 160;
/** `ViewTransition` 索引：**0 = loading、1 = 数据**（见「关键行为」1，与 HistoryScene 相反） */
export const VIEW_LOADING: number = 0;
export const VIEW_DATA: number = 1;

/** `ListUrlBuilder` 的等价（`GalleryListScene.startScene(scene, urlBuilder)` 的入参） */
export class ListUrlBuilderSpec {
  mode: number = MODE_NORMAL;
  /** `MODE_TOP_LIST` 时用 */
  follow: string = '';
  /** `MODE_NORMAL/UPLOADER` 时用 */
  keyword: string = '';
}

/** 本页宿主能力 */
export interface TopListSceneHost {
  /** 上游 `stackIndex`（0 = 栈底） */
  getStackIndex(): number;
  /** 上游 `System.currentTimeMillis()` */
  now(): number;
  /** 上游 `showTip(key, LENGTH_SHORT)` */
  showTip(key: string): void;
  /** 上游 `finish()` */
  finish(): void;
  /** 上游 `scene is EhTopListScene` 的等价（本实现恒匹配） */
  isThisScene(sceneTag: string): boolean;
  /** 上游 `startScene(Announcer(GalleryDetailScene))`（带 ACTION_GALLERY_TOKEN 三个键） */
  startDetail(gid: number, pToken: string): void;
  /** 上游 `GalleryListScene.startScene(scene, urlBuilder)` */
  startList(builder: ListUrlBuilderSpec): void;
  /** 上游 `createAnnouncerFromClipboardUrl(href)`；null = 解析失败 */
  resolveAnnouncerFromUrl(href: string): boolean;
}

/** 排行榜接口（`METHOD_GET_TOP_LIST`） */
export interface TopListApi {
  /** 上游 `EhUrl.getTopListUrl()` + `METHOD_GET_TOP_LIST` */
  fetchDetail(url: string): Promise<EhTopListDetail | null>;
  /** 上游 `request?.cancel()` */
  cancel(): void;
}

/** 上游 `EhUrl.getTopListUrl()` 的等价（url 拼装属 net-parse） */
export const TOP_LIST_URL: string = 'TOP_LIST_URL';

/** 一次条目点击的结果（便于断言走的是哪条分支） */
export const ITEM_CLICK_DETAIL: number = 1;
export const ITEM_CLICK_HREF: number = 2;
export const ITEM_CLICK_SEARCH: number = 3;

export class EhTopListScene {
  private host: TopListSceneHost;
  private api: TopListApi;
  private state: number = STATE_INIT;
  private detail: EhTopListDetail | null = null;
  private hasFirstRefresh: boolean = false;
  private pressBackTime: number = 0;
  /** 上游 `private var mPosition = 0` 是**文件级 var**（所有实例共享，见「关键行为」2） */
  private static mPosition: number = 0;
  /** 上游 adapter 里的 `HashMap<Int, Int>`（颜色缓存） */
  private colorCache: Map<number, number> = new Map<number, number>();
  private lastError: Error | null = null;

  constructor(host: TopListSceneHost, api: TopListApi) {
    this.host = host;
    this.api = api;
  }

  /** 当前状态（测试观测） */
  getState(): number {
    return this.state;
  }

  /** 当前榜单下标（上游 `mPosition`，静态） */
  getPosition(): number {
    return EhTopListScene.mPosition;
  }

  /**
   * 上游 `onCreateView2` 的后半段：
   * ① **首次** `loadData()`（失败只记录）② 非首次 → `bindViewSecond(mPosition)` + `adjustViewVisibility(NORMAL, true)`
   * @returns 视图索引（首次返回 loading；非首次返回数据视图）
   */
  async onCreateView(): Promise<number> {
    if (!this.hasFirstRefresh) {
      this.hasFirstRefresh = true;
      try {
        await this.loadData();
      } catch (e) {
        this.lastError = e as Error;   // 上游：printStackTrace()
      }
      return this.viewIndexFor(this.state);
    }
    await this.bindViewSecond(EhTopListScene.mPosition);
    return this.adjustViewVisibility(STATE_NORMAL, true);
  }

  /** 上游 `onBackPressed()` */
  async onBackPressed(): Promise<void> {
    const handled: boolean = this.checkDoubleClickExit();
    if (!handled) {
      if (this.state === STATE_INIT) {
        this.api.cancel();
      }
      this.host.finish();
    }
  }

  /**
   * 上游 `checkDoubleClickExit()`：
   * `stackIndex != 0 → false`；距上次 > 2000ms → 记时间 + 提示 + **返回 true（拦截）**；否则 false（放行）。
   */
  checkDoubleClickExit(): boolean {
    if (this.host.getStackIndex() !== 0) {
      return false;
    }
    const time: number = this.host.now();
    if (time - this.pressBackTime > BACK_PRESSED_INTERVAL) {
      this.pressBackTime = time;
      this.host.showTip(TIP_PRESS_TWICE);
      return true;
    }
    return false;
  }

  /** 上游 `request()`：三处 null → 返回 false（→ loadData 抛异常） */
  private async request(): Promise<boolean> {
    try {
      const detail: EhTopListDetail | null = await this.api.fetchDetail(TOP_LIST_URL);
      if (detail !== null) {
        this.onGetEhTopListDetailSuccess(detail, 0);
      }
    } catch (e) {
      this.lastError = e as Error;
    }
    return true;
  }

  /** 上游 `loadData()`：`!requested` → 抛中文原文异常 */
  private async loadData(): Promise<void> {
    const requested: boolean = await this.request();
    if (!requested) {
      throw new Error(ERR_REQUEST_FAILED);
    }
  }

  /** 上游 `onGetEhTopListDetailSuccess(detail, index)` */
  onGetEhTopListDetailSuccess(detail: EhTopListDetail, index: number): void {
    this.detail = detail;
    this.bindViewSecond(index);
    this.adjustViewVisibility(STATE_NORMAL, true);
  }

  /** 上游 `bindViewSecond(index)`：三个 null 防御 → 建 adapter */
  async bindViewSecond(index: number): Promise<boolean> {
    const detail: EhTopListDetail | null = this.detail;
    if (detail === null) {
      return false;
    }
    const info: TopListInfo | null = detail.get(index);
    if (info === null) {
      return false;
    }
    EhTopListScene.mPosition = index;
    return true;
  }

  /**
   * 上游 `adjustViewVisibility(newState, animation)`：
   * **`STATE_INIT/REFRESH → 0(loading)`，其余 → 1(数据)**；
   * `shouldAnimate` 因 `TRANSITION_ANIMATION_DISABLED = true` **恒为 false**。
   * @returns 视图索引
   */
  adjustViewVisibility(newState: number, animation: boolean): number {
    this.state = newState;
    const shouldAnimate: boolean = !TRANSITION_ANIMATION_DISABLED && animation;
    // 上游：when (newState) { INIT, REFRESH -> showView(0); else -> showView(1) }
    // shouldAnimate 恒 false（见「关键行为」4）—— 保留变量以免"看起来漏了动画参数"
    if (shouldAnimate) {
      // 不可达（TRANSITION_ANIMATION_DISABLED = true）
      return this.viewIndexFor(newState);
    }
    return this.viewIndexFor(newState);
  }

  private viewIndexFor(newState: number): number {
    if (newState === STATE_INIT || newState === STATE_REFRESH) {
      return VIEW_LOADING;
    }
    return VIEW_DATA;
  }

  /** 上游 spinner 选择：**只切 adapter，不重新请求**（见「关键行为」3 的对偶） */
  onKindSelected(position: number): void {
    EhTopListScene.mPosition = position;
    this.bindViewSecond(EhTopListScene.mPosition);
  }

  /** 上游 `EhTopListAdapterView.clickTitle(urlFollow)` */
  clickTitle(urlFollow: string): void {
    const b: ListUrlBuilderSpec = new ListUrlBuilderSpec();
    b.mode = MODE_TOP_LIST;
    b.follow = urlFollow;
    this.host.startList(b);
  }

  /**
   * 上游 `getRandomColor(position)`：**缓存到 HashMap**（见「关键行为」8）。
   * `Color.argb(160, r, g, b)` → ArkTS 用 `0xAARRGGBB` 整数表达。
   * @param rand 0..4 的随机源（便于断言）；缺省用 Math.random
   */
  getRandomColor(position: number, randR?: number, randG?: number, randB?: number): number {
    const cached: number | undefined = this.colorCache.get(position);
    if (cached !== undefined) {
      return cached;
    }
    const r: number = randR === undefined ? Math.floor(Math.random() * 256) : randR;
    const g: number = randG === undefined ? Math.floor(Math.random() * 256) : randG;
    const b: number = randB === undefined ? Math.floor(Math.random() * 256) : randB;
    const color: number = argb(RANDOM_COLOR_ALPHA, r, g, b);
    this.colorCache.set(position, color);
    return color;
  }

  /**
   * 上游 `onItemClick(topListItem, searchType)`：三条分支（见「关键行为」9）。
   * @returns `ITEM_CLICK_DETAIL` / `ITEM_CLICK_HREF` / `ITEM_CLICK_SEARCH`
   */
  onItemClick(item: TopListItem, searchType: number): number {
    const b: ListUrlBuilderSpec = new ListUrlBuilderSpec();
    b.mode = searchType === 0 ? MODE_NORMAL : MODE_UPLOADER;

    // ② gid 与 token 都非空 → 详情
    // 本仓 `TopListItem` 的这些字段是**非空 string**（空串表示上游 null）→ 判 length > 0
    const gid: string = item.gid;
    const token: string = item.token;
    if (gid.length > 0 && token.length > 0) {
      // ★ 上游传的是 topListItem.tag 作为 PTOKEN（见「关键行为」9）
      this.host.startDetail(Number(gid), item.tag);
      return ITEM_CLICK_DETAIL;
    }
    // ③ href 可解析 → 按解析结果跳转（空串 = 上游 null，直接跳过）
    const href: string = item.href;
    if (href.length > 0) {
      if (this.host.resolveAnnouncerFromUrl(href)) {
        return ITEM_CLICK_HREF;
      }
    }
    // ④ 兜底：按关键词搜
    b.keyword = item.value;
    this.host.startList(b);
    return ITEM_CLICK_SEARCH;
  }

  /** 是否需要首次刷新（测试观测） */
  isHasFirstRefresh(): boolean {
    return this.hasFirstRefresh;
  }

  /** 最近一次错误 */
  getLastError(): Error | null {
    return this.lastError;
  }

  /** 当前榜单信息（测试观测） */
  getCurrentInfo(): TopListInfo | null {
    const d: EhTopListDetail | null = this.detail;
    if (d === null) {
      return null;
    }
    return d.get(EhTopListScene.mPosition);
  }
}

/** 上游 `Color.argb(a, r, g, b)` → `0xAARRGGBB` */
export function argb(a: number, r: number, g: number, b: number): number {
  const av: number = (a & 0xFF) << 24;
  const rv: number = (r & 0xFF) << 16;
  const gv: number = (g & 0xFF) << 8;
  const bv: number = b & 0xFF;
  return (av | rv | gv | bv) >>> 0;
}

