/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/history/HistoryScene.java
 *       （inventory S0253，409 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/history/HistoryScene.ets
 *
 * 背景：**浏览历史**列表页。一屏分两部分：`content`（RecyclerView 列表）与 `tip`（空态提示图标+文字），
 * 由 `ViewTransition` 二选一显示。列表项支持：点击进详情（带共享元素转场）、长按弹菜单（下载/收藏）、
 * 左滑删除；工具栏菜单有"清空全部历史"。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class HistoryScene extends ToolbarScene implements OnItemClickListener, OnItemLongClickListener`
 *   `getNavCheckedItem()` → `R.id.nav_history`（侧边栏高亮项）
 *   `onCreateView3(inflater, container, savedInstanceState)`:
 *     · `inflate(R.layout.scene_history)` → `content = R.id.content` / `recyclerView = R.id.recycler_view`
 *       / `fastScroller = R.id.fast_scroller` / `tip = R.id.tip`
 *     · `mViewTransition = new ViewTransition(content, tip)` → **只有这两个视图互切**
 *     · `tip` 的 drawable = `@drawable/big_history`（上/下/左/右 = null/null/null/null → **图标在顶**）
 *     · 列表：`HistoryAdapter` + `setHasStableIds(true)` + 包装成 swipe 适配器
 *     · 布局管理器 `AutoStaggeredGridLayoutManager(0, VERTICAL)` + `setColumnSize(@dimen 由 Settings.getDetailSizeResId() 决定)`
 *       + `STRATEGY_MIN_SIZE`（**自适应列宽**：列宽由设置里的详情尺寸决定）
 *     · `MarginItemDecoration(interval=gallery_list_interval, paddingH=margin_h, paddingV=margin_v, …)`
 *       —— **四边间距来自 3 个 dimen**，不是固定值
 *     · `fastScroller.attachToRecyclerView`；`HandlerDrawable` 颜色 = `?attr/widgetColorThemeAccent`
 *     · `updateLazyList(); updateView(false);`  （**建视图时就加载并定型**）
 *   `onViewCreated` → `setTitle(@string/history)` + `setNavigationIcon(@drawable/v_arrow_left_dark_x24)`
 *   `onDestroyView` → **先 close LazyList 再置 null**，然后 `notifyDataSetChanged()`；`recyclerView.stopScroll()`；三段置 null
 *   `updateLazyList()` → `EhDB.getHistoryLazyList()`；**旧 LazyList 必须先 close**（上游注释 "Remember to notify"）
 *   `updateView(animation)`:
 *     · `mAdapter == null || mViewTransition == null` → **直接 return**（防御）
 *     · `mAdapter.getItemCount() == 0` → `showView(1)`（tip）否则 `showView(0)`（content）
 *   `onNavigationClick` → `onBackPressed()`
 *   `getMenuResId()` → `R.menu.scene_history`
 *   `showClearAllDialog()` → AlertDialog(`@string/clear_all_history`) + 正按钮(`@string/clear_all`)：
 *     **`which != BUTTON_POSITIVE` 或 `mAdapter == null` → return**；否则
 *     `EhDB.clearHistoryInfo()` → `updateLazyList()` → `notifyDataSetChanged()` → `updateView(true)`
 *   `onMenuItemClick(item)` → `R.id.action_clear_all` → `showClearAllDialog()` + true；其它 false
 *   `onItemClick(position)`:
 *     · `mLazyList == null` → false
 *     · args: `KEY_ACTION = ACTION_GALLERY_INFO`、`KEY_GALLERY_INFO = mLazyList.get(position)`
 *     · `announcer = Announcer(GalleryDetailScene).setArgs(args)`
 *     · **若该行能找到 `R.id.thumb` 视图** → `announcer.setTranHelper(EnterGalleryDetailTransaction(thumb))`
 *     · `startScene(announcer)` → true
 *   `onItemLongClick(position)`:
 *     · `context/activity/mLazyList` 任一为 null → **false**
 *     · 弹 `@array/gallery_list_menu_entries`：`0 → startDownload(activity, gi, false)`
 *       `1 → addToFavorites(activity, gi, addToFavoriteListener(...), false)`
 *   `HistoryHolder`（7 个控件：card/thumb/title/uploader/rating/category/posted/simpleLanguage）
 *   `HistoryAdapter`:
 *     · 缩略图尺寸：**先 inflate `item_gallery_list_thumb_height` 测量高度**，`width = height * 2 / 3`（**3:2 竖图**）
 *     · `getItemId(position)` → `mLazyList.get(position).gid`（**稳定 id = gid**）
 *     · `onBindViewHolder`：`thumb.load(EhCacheKeyFactory.getThumbKey(gid), gi.thumb)`、标题 `getSuitableTitle`、
 *       `uploader`、`rating`、`category`：**只有文本变化时才 setText + setBackgroundColor**（避免重复着色）、
 *       `posted`、`simpleLanguage`
 *     · **转场名**：`ViewCompat.setTransitionName(thumb, TransitionNameFactory.getThumbTransitionName(gid))`
 *       —— 仅 API ≥ 21（本项目 minSdk 23，恒真）
 *     · 滑出反应：只允许 **左滑**（`REACTION_CAN_SWIPE_LEFT`）；`RESULT_SWIPED_LEFT` → `SwipeResultActionClear`
 *   `SwipeResultActionClear.onPerformAction()` → `EhDB.deleteHistoryInfo(info)` → `updateLazyList()` → notify → `updateView(true)`
 *   `addToFavoriteListener : EhCallback<HistoryScene, Void>` → 成功 `showTip(@string/add_to_favorite_success, SHORT)`；
 *     失败 `showTip(@string/add_to_favorite_failure, LONG)`；取消无动作；`isInstance(scene) = scene is HistoryScene`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`updateView` 的两道 null 防御在先**（adapter / transition 任一为 null 直接 return）。
 * 2. **`updateLazyList` 必须先 close 旧的再换新的** —— 上游注释写明 "Remember to notify"，
 *    因为 LazyList 持有游标；不 close 会泄漏（鸿蒙侧用普通数组 + 重新查询，语义等价但**不能缓存旧数组引用**）。
 * 3. **清空确认框里 `which != BUTTON_POSITIVE` 就 return** —— 取消/返回键不会清空（看似显然，但很多实现漏这一步）。
 * 4. **`category` 只在文本变化时才 setText + setBackgroundColor** —— 避免每次 bind 都重设背景（会造成闪烁）。
 * 5. **缩略图宽高比 `width = height * 2 / 3`** 由 `item_gallery_list_thumb_height` 实测得出，**不是写死的**。
 * 6. **左滑才删**（右滑 `RESULT_SWIPED_RIGHT` 走默认，即不动）。
 * 7. **长按菜单只有两项**：下载（`startDownload(..., false)`，第二个参数 = 不是从"归档"入口）、收藏。
 *
 * ── 平台差异（依赖倒置 + ArkUI 载体）────────────────────────────────────────
 * 1. **`ToolbarScene` 未落地**（ui-scene 仍在做）→ 本文件只声明实际用到的宿主能力为 `HistorySceneHost`：
 *    `loadHistory` / `clearHistory` / `deleteHistory` / `startScene` / `showTip` / `onBackPressed` /
 *    `startDownload` / `addToFavorites`。Scene 基类落地后 `implements` 即接入。
 * 2. **`EhDB.getHistoryLazyList()` 在本仓库是 `async`**（上游是同步 `LazyList`）→
 *    引入**四态**：`LOADING` / `READY(有数据)` / `EMPTY` / `FAILURE`。
 *    **视图决策仍与上游一致**：只有"有数据"显示 content(0)，其余三种都显示 tip(1)
 *    （上游只有"空/非空"两态，因为它是同步查询，不存在加载中/失败）。
 * 3. **`ViewTransition(content, tip)`** → `updateView()` 返回 **0/1 的视图索引**（照搬语义），
 *    由 ArkUI 侧用 `if/else` 或 `visibility` 渲染。
 * 4. **`RecyclerView` + `ItemTouchHelper` 侧滑** → ArkUI `List` + `ListItem` 的 `swipeAction`；
 *    本文件只产出 `SwipeOutcome`（`DELETE` / `NONE`），由页面层执行。
 * 4b. **`EasyRecyclerView` 的四个滑动回调在 ArkUI 无一对位**（`ItemTouchHelper` 框架胶水）——
 *     语义已由 `ListItem.swipeAction` 承担，映射如下（**不新增回调**，见 DEVIATIONS）：
 *       `onGetSwipeReactionType` → `swipeAction` 只配 **end 侧**（= 等价 `REACTION_CAN_SWIPE_LEFT`）
 *       `onSetSwipeBackground`   → `swipeAction` 的 builder 背景色
 *       `onSwipeItemStarted`     → `ListItem.onSwipeActionStateChange`（框架保证同时只开一个）
 *       `onCancel`               → 框架回弹，无需实现
 *       **右滑不配 start 侧** = 等价 `REACTION_CAN_NOT_SWIPE_RIGHT_WITH_RUBBER_BAND_EFFECT`
 *       （"右滑不动"是上游**显式语义**（`RESULT_SWIPED_RIGHT` 走默认不处理），此句防读者误判为漏做）
 * 5. **`AutoStaggeredGridLayoutManager(列宽=dimen(Settings.getDetailSizeResId()))`** →
 *    本仓库已有 `AutoWrapLayout`/`FlowLayout`（ui-widget）承担自适应列宽；这里暴露 `columnSizeKey` 与
 *    `columnStrategy='MIN_SIZE'`，不自己算宽度。
 * 6. **`CommonOperations` 未落地** → `startDownload` / `addToFavorites` 走宿主注入（见 1）。
 * 7. **`HistoryInfo` 已存在**（`hippo/ehviewer/dao/HistoryInfo.ets`：`mode` / `time` + 继承 `GalleryInfo`）。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `EhDB.getHistoryLazyList()` / `clearHistoryInfo()` / `deleteHistoryInfo(info)`（均 async）、
 * `HistoryInfo`、`hippo/ui/layout/scene_history.ets`、`hippo/ui/drawable/big_history.ets`、
 * `TransitionNameFactory.getThumbTransitionName(gid)`、`EnterGalleryDetailTransaction`、
 * `EhUtils.getSuitableTitle` / `getCategory` / `getCategoryColor`。
 *
 * ── 缺口（已登记，不假装有）──────────────────────────────────────────────────
 * `EhCacheKeyFactory.getThumbKey(gid)` **本仓库不存在** → 缩略图键改由宿主提供
 * （`HistorySceneHost.thumbCacheKey(gid)`），不硬编码键格式（键格式属 net-parse 的缓存层）。
 */

import { HistoryInfo } from '../../../dao/HistoryInfo';
import { GalleryInfo } from '../../../client/data/GalleryInfo';
import { EhUtils } from '../../../client/EhUtils';
import { Announcer } from '../../../../scene/Announcer';
import { SceneArgs, SceneTransitionHelper } from '../../../../scene/SceneTypes';
import { TransitionNameFactory } from '../TransitionNameFactory';
import { EnterGalleryDetailTransaction } from '../gallery/list/EnterGalleryDetailTransaction';

/** 上游 `R.id.nav_history` —— 侧边栏高亮项（页面层用） */
export const NAV_HISTORY_ID: string = 'nav_history';
/** 上游 `R.layout.scene_history` */
export const LAYOUT_SCENE_HISTORY: string = 'scene_history';
/** 上游 `R.menu.scene_history` */
export const MENU_SCENE_HISTORY: string = 'menu/scene_history';
/** 上游 `R.id.action_clear_all` */
export const ACTION_CLEAR_ALL: string = 'action_clear_all';
/** 上游 `GalleryDetailScene.KEY_ACTION` / `ACTION_GALLERY_INFO` */
export const KEY_ACTION: string = 'action';
export const ACTION_GALLERY_INFO: string = 'gallery_info';
/** 上游 `GalleryDetailScene.KEY_GALLERY_INFO` */
export const KEY_GALLERY_INFO: string = 'gallery_info';

/** 上游 `ViewTransition(content, tip)` 的两个索引（**0 = content、1 = tip**） */
export const VIEW_CONTENT: number = 0;
export const VIEW_TIP: number = 1;

/** 上游 `SwipeableItemConstants.RESULT_SWIPED_LEFT` 等 → 本实现的滑出结果 */
export const SWIPE_NONE: number = 0;
export const SWIPE_DELETE: number = 1;

/** 上游同步 LazyList → 本仓库 async 查询，故引入四态（见「平台差异」2） */
export const STATE_LOADING: number = 0;
export const STATE_READY: number = 1;
export const STATE_EMPTY: number = 2;
export const STATE_FAILURE: number = 3;

/** 本页对宿主（Scene 基类 + EhDB + CommonOperations）的最小依赖（见「平台差异」1/6） */
export interface HistorySceneHost {
  loadHistory(): Promise<HistoryInfo[]>;
  clearHistory(): Promise<void>;
  deleteHistory(info: HistoryInfo): Promise<void>;
  startScene(announcer: Announcer): void;
  showTip(messageKey: string, isLong: boolean): void;
  onBackPressed(): void;
  startDownload(info: GalleryInfo): void;
  addToFavorites(info: GalleryInfo, onSuccess: () => void, onFailure: (e: Error) => void): void;
  /** 上游 `EhCacheKeyFactory.getThumbKey(gid)`（见「缺口」） */
  thumbCacheKey(gid: number): string;
}

/** 一行数据（上游 `HistoryHolder` 的 7 个控件 + 缩略图加载键） */
export class HistoryItemViewModel {
  gid: number = 0;
  /** `holder.thumb.load(key, gi.thumb)` 的两个入参 */
  thumbCacheKey: string = '';
  thumbUrl: string = '';
  title: string = '';
  uploader: string = '';
  rating: number = 0;
  /** `EhUtils.getCategory(gi.category)` */
  categoryText: string = '';
  /** `EhUtils.getCategoryColor(gi.category)` */
  categoryColor: number = 0;
  posted: string = '';
  simpleLanguage: string = '';
  /** `TransitionNameFactory.getThumbTransitionName(gid)` */
  transitionName: string = '';
}

/** 清空确认框描述（上游 `AlertDialog` + 两个字符串） */
export class ClearAllDialogSpec {
  messageKey: string = 'app.string.clear_all_history';
  positiveButtonKey: string = 'app.string.clear_all';
}

/** 长按菜单（上游 `R.array.gallery_list_menu_entries` 的两项） */
export const LONG_PRESS_DOWNLOAD: number = 0;
export const LONG_PRESS_FAVORITES: number = 1;
export class LongPressMenuSpec {
  title: string = '';
  entries: string[] = ['app.string.gallery_list_menu_download', 'app.string.gallery_list_menu_favorites'];
}

export class HistoryScene {
  private host: HistorySceneHost;
  private items: HistoryInfo[] = [];
  private state: number = STATE_LOADING;
  private lastError: Error | null = null;

  constructor(host: HistorySceneHost) {
    this.host = host;
  }

  /** 上游 `getNavCheckedItem()` */
  getNavCheckedItem(): string {
    return NAV_HISTORY_ID;
  }

  /** 上游 `getMenuResId()` */
  getMenuResId(): string {
    return MENU_SCENE_HISTORY;
  }

  /**
   * 上游 `onCreateView3(...)` 的后半段：`updateLazyList(); updateView(false);`
   * （布局/适配器/装饰器在 ArkUI 侧由 `scene_history.ets` + 页面层承担）
   */
  async onCreateView(): Promise<number> {
    await this.updateLazyList();
    return this.updateView(false);
  }

  /**
   * 上游 `updateLazyList()`：`EhDB.getHistoryLazyList()`；
   * **旧的必须先释放**（上游 `mLazyList.close()`，见「关键行为」2）。
   * 这里用"整表替换"表达：旧数组引用不保留。
   */
  private async updateLazyList(): Promise<void> {
    this.state = STATE_LOADING;
    try {
      const list: HistoryInfo[] = await this.host.loadHistory();
      this.items = list;
      this.state = list.length === 0 ? STATE_EMPTY : STATE_READY;
      this.lastError = null;
    } catch (e) {
      this.items = [];
      this.state = STATE_FAILURE;
      this.lastError = e as Error;
    }
  }

  /**
   * 上游 `updateView(animation)`：
   * ① 防御：适配器/过渡为空 → 直接 return（本实现无对应概念，用 host 恒存在替代）
   * ② `getItemCount() == 0` → `showView(1)`；否则 `showView(0)`
   * 本实现按四态映射（见「平台差异」2）：只有 READY 显示 content。
   */
  updateView(animation: boolean): number {
    if (this.state === STATE_READY && this.items.length > 0) {
      return VIEW_CONTENT;
    }
    return VIEW_TIP;
  }

  /** 上游 `onNavigationClick(view)` → `onBackPressed()` */
  onNavigationClick(): void {
    this.host.onBackPressed();
  }

  /** 上游 `onMenuItemClick(item)`：只有 `action_clear_all` 返回 true */
  onMenuItemClick(itemId: string): boolean {
    if (itemId === ACTION_CLEAR_ALL) {
      // 上游：showClearAllDialog()
      this.pendingClearDialog = new ClearAllDialogSpec();
      return true;
    }
    return false;
  }

  /** 待确认的清空对话框（`null` = 未弹） */
  private pendingClearDialog: ClearAllDialogSpec | null = null;

  /** 当前是否有待确认的清空对话框（页面层渲染 AlertDialog 用） */
  getClearAllDialog(): ClearAllDialogSpec | null {
    return this.pendingClearDialog;
  }

  /**
   * 上游 `showClearAllDialog()` 正按钮回调：
   * **`which != BUTTON_POSITIVE` 或适配器为空 → return**（见「关键行为」3）；
   * 否则 `clearHistoryInfo()` → `updateLazyList()` → `notifyDataSetChanged()` → `updateView(true)`。
   */
  async confirmClearAll(which: number): Promise<boolean> {
    // 上游：if (DialogInterface.BUTTON_POSITIVE != which || null == mAdapter) return;
    if (which !== BUTTON_POSITIVE) {
      this.pendingClearDialog = null;
      return false;
    }
    if (this.state === STATE_LOADING) {
      // mAdapter == null 的等价物：还没建好列表
      this.pendingClearDialog = null;
      return false;
    }
    await this.host.clearHistory();
    await this.updateLazyList();
    this.pendingClearDialog = null;
    this.updateView(true);
    return true;
  }

  /**
   * 上游 `onItemClick(position)`：
   * `mLazyList == null → false`；否则构造 announcer（ACTION_GALLERY_INFO + galleryInfo），
   * **有 thumb 时**挂 `EnterGalleryDetailTransaction`，再 `startScene`。
   */
  onItemClick(position: number, hasThumb: boolean): boolean {
    if (this.state !== STATE_READY) {
      return false;
    }
    if (position < 0 || position >= this.items.length) {
      return false;
    }
    const info: HistoryInfo = this.items[position];
    const announcer: Announcer = new Announcer('GalleryDetailScene');
    const args: SceneArgs = new Map<string, Object>();
    args.set(KEY_ACTION, ACTION_GALLERY_INFO);
    args.set(KEY_GALLERY_INFO, info as Object);
    announcer.setArgs(args);
    if (hasThumb) {
      // 上游：announcer.setTranHelper(new EnterGalleryDetailTransaction(thumb))
      // 这里的 thumb 用共享元素名表达（ArkUI 侧 geometryTransition）
      const helper: SceneTransitionHelper =
        new EnterGalleryDetailTransaction(TransitionNameFactory.getThumbTransitionName(info.gid));
      announcer.tranHelper = helper;
    }
    this.host.startScene(announcer);
    return true;
  }

  /** 上游 `onItemLongClick(position)`：返回菜单描述并执行所选动作 */
  onItemLongClick(position: number): LongPressMenuSpec | null {
    if (this.state !== STATE_READY || position < 0 || position >= this.items.length) {
      return null;
    }
    const info: HistoryInfo = this.items[position];
    const spec: LongPressMenuSpec = new LongPressMenuSpec();
    spec.title = EhUtils.getSuitableTitle(info) !== null ? (EhUtils.getSuitableTitle(info) as string) : '';
    this.pendingLongPress = new PendingLongPress(this, info);
    return spec;
  }

  private pendingLongPress: PendingLongPress | null = null;

  /** 长按菜单点击（上游 switch(which)：0 下载 / 1 收藏） */
  onLongPressMenuClick(which: number): boolean {
    const pending: PendingLongPress | null = this.pendingLongPress;
    if (pending === null) {
      return false;
    }
    if (which === LONG_PRESS_DOWNLOAD) {
      // 上游：CommonOperations.startDownload(activity, gi, false)
      this.host.startDownload(pending.info);
      this.pendingLongPress = null;
      return true;
    }
    if (which === LONG_PRESS_FAVORITES) {
      // 上游：CommonOperations.addToFavorites(activity, gi, addToFavoriteListener(...), false)
      // 监听器语义：成功 showTip(add_to_favorite_success, SHORT)；失败 showTip(add_to_favorite_failure, LONG)
      const host: HistorySceneHost = this.host;
      host.addToFavorites(pending.info, (): void => {
        host.showTip('app.string.add_to_favorite_success', false);
      }, (_e: Error): void => {
        host.showTip('app.string.add_to_favorite_failure', true);
      });
      this.pendingLongPress = null;
      return true;
    }
    return false;
  }

  /**
   * 上游 `onSwipeItem(...)`：`RESULT_SWIPED_LEFT` → 删除；右滑/取消 → 不动。
   * @param result `SWIPE_DELETE` 表示左滑
   */
  async onSwipeItem(position: number, result: number): Promise<boolean> {
    if (result !== SWIPE_DELETE) {
      return false;   // 右滑/取消：走默认（不删）
    }
    if (this.state !== STATE_READY || position < 0 || position >= this.items.length) {
      return false;
    }
    const info: HistoryInfo = this.items[position];
    await this.host.deleteHistory(info);
    await this.updateLazyList();
    this.updateView(true);
    return true;
  }

  /** 上游 `HistoryAdapter.getItemCount()` */
  getItemCount(): number {
    return this.items.length;
  }

  /** 上游 `HistoryAdapter.getItemId(position)` → **`mLazyList.get(position).gid`**（稳定 id） */
  getItemId(position: number): number {
    if (position < 0 || position >= this.items.length) {
      return -1;
    }
    return this.items[position].gid;
  }

  /**
   * 上游 `onBindViewHolder` 的字段映射（**视觉部分**）：
   * `thumb.load(key, thumb)` / `title=getSuitableTitle` / `uploader` / `rating` /
   * `categoryText=getCategory` + `categoryColor=getCategoryColor` / `posted` / `simpleLanguage` /
   * `transitionName=getThumbTransitionName(gid)`。
   */
  bindItem(position: number): HistoryItemViewModel | null {
    if (position < 0 || position >= this.items.length) {
      return null;
    }
    const gi: HistoryInfo = this.items[position];
    const vm: HistoryItemViewModel = new HistoryItemViewModel();
    vm.gid = gi.gid;
    vm.thumbCacheKey = this.host.thumbCacheKey(gi.gid);
    vm.thumbUrl = gi.thumb;
    const title: string | null = EhUtils.getSuitableTitle(gi);
    vm.title = title === null ? '' : title;
    vm.uploader = gi.uploader;
    vm.rating = gi.rating;
    vm.categoryText = EhUtils.getCategoryByValue(gi.category);
    vm.categoryColor = EhUtils.getCategoryColor(gi.category);
    vm.posted = gi.posted;
    vm.simpleLanguage = gi.simpleLanguage === null ? '' : gi.simpleLanguage;
    vm.transitionName = TransitionNameFactory.getThumbTransitionName(gi.gid);
    return vm;
  }

  /**
   * 上游 `category` 的**条件更新**（见「关键行为」4）：
   * 只有文本变化时才同时更新文本与背景色 —— 避免每次 bind 重设背景造成闪烁。
   * @returns true = 需要更新（文本变了）
   */
  shouldUpdateCategory(previousText: string, nextText: string): boolean {
    return previousText !== nextText;
  }

  /** 四态（见「平台差异」2） */
  getState(): number {
    return this.state;
  }

  /** 最近一次加载的错误（仅 STATE_FAILURE 时非空） */
  getLastError(): Error | null {
    return this.lastError;
  }

  /** 当前列表（只读副本，避免外部改内部状态） */
  getItems(): HistoryInfo[] {
    return this.items.slice();
  }
}

/** 上游 `DialogInterface.BUTTON_POSITIVE = -1` */
export const BUTTON_POSITIVE: number = -1;


/** 长按菜单的"待执行项"（上游用闭包捕获 gi；ArkTS 用显式对象避免箭头函数捕获歧义） */
class PendingLongPress {
  owner: HistoryScene;
  info: HistoryInfo;

  constructor(owner: HistoryScene, info: HistoryInfo) {
    this.owner = owner;
    this.info = info;
  }
}

