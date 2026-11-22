/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/SubscriptionsScene.java
 *       （inventory S0247，上游实际 341 行；清单登记 277 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/SubscriptionsScene.ets
 *
 * 背景：**订阅管理页**（标签列表，可拖拽排序、可删除）。与 `SubscriptionDraw`（抽屉里的那份）分工不同：
 * 抽屉是"轻量展示 + 点标签筛列表"，本页是"管理 + 删除"。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 字段：`userTagList` / `mRecyclerView` / `progressView` / `mViewTransition` / `ehTags` / `context` / `ehClient`
 * `onCreate`：`context = getEHContext()`；`ehClient == null → EhApplication.getEhClient(context)`；
 *   **`userTagList = EhApplication.getUserTagList(context)`**；`ehTags = EhTagDatabase.getInstance(context)`
 * `onDestroy`：`userTagList = null`
 * `onCreateView3`：
 *   · **复用 `R.layout.scene_label_list`**（与下载标签页同一个布局）+ `R.id/scene_label_progress`
 *   · `mViewTransition = new ViewTransition(mRecyclerView, tip)`
 *   · tip 图标 `@drawable/big_search`（图标在顶）+ 文案 **`@string/no_quick_search`**（上游文案是"没有快速搜索"——
 *     因为本页是从"快速搜索订阅"演化来的，**文案没改名**，照搬）
 *   · 拖拽 `RecyclerViewDragDropManager` + `shadow_8dp`；`adapter.setHasStableIds(true)`；
 *     动画器是 **`DraggableItemAnimator`**（注意：DownloadLabelsScene 用的是 `SwipeDismissItemAnimator`）
 *   · `LinearLayoutManager`；`updateView()`
 * `onViewCreated`：title **`@string/tag_title`**（不是 `subscriptions`）+ 返回图标
 * `onDestroyView`：`stopScroll()` → `mViewTransition = null`（**注意：不置空 mRecyclerView 之外的东西**）
 * `onNavigationClick` → `onBackPressed()`
 * `bindSecond()`：progress GONE；
 *   **`mRecyclerView == null` → Toast "描述文件未找到？？？重启试试~"（中文原文照搬）并 return**；
 *   `mRecyclerView.setVisibility(VISIBLE)`；`userTagList == null` → 新建空列表；
 *   然后**重建整套拖拽 + adapter**（与 onCreateView3 里那段几乎重复 —— 上游确实重复了两遍，照搬）
 * `updateView()`：`userTagList != null && userTags.size() > 0` → `showView(0)`，否则 `showView(1)`
 * `SubscriptionHolder`：
 *   · 三个视图 `label` / `dragHandler` / `delete`，且 `imageView = findViewById(R.id.drag_handler)`
 *     （**注意 imageView 和 dragHandler 是同一个控件** —— 上游如此，见「关键行为」3）
 *   · **只给 `delete` 绑了 onClick**（`label` / `dragHandler` 都没绑！）
 *   · `onClick`：`position == NO_POSITION || userTagList == null → return`；
 *     弹确认 `@string/delete_subscription_title` + `@string/delete_quick_search_message(tag.tagName)`
 *     → 正按钮 `deleteTag(userTag)`
 *   · `deleteTag`：**progress VISIBLE + recyclerView INVISIBLE** → `deleteRequest(tag)`
 *   · `deleteRequest`：url = `getMyTag()`；`context == null → return`；
 *     `METHOD_DELETE_WATCHED` + `setArgs(url, userTag)`
 * `QuickSearchAdapter.onBindViewHolder`：
 *   · **`Settings.getShowTagTranslations()` 为真 → `getName(ehTags)`；否则直接用 `tagName`**
 *     （与 `SubscriptionItemAdapter` 的"总是 getName"**不同** —— 见「关键行为」2）
 *   · `hidden` → off 图标；`watched` → on 图标（**两个独立 if，watched 覆盖 hidden**）
 *   · `getItemId` → `userTag.getId()`（稳定 id）；`getItemCount` → `userTags.size()`
 * `SubscriptionDetailListener.onSuccess(result)`：
 *   `userTagList == null → new UserTagList()`；
 *   **`result == null || result.userTags == null → userTags = []`** 否则 `userTags = result.userTags`
 *   → **`saveUserTagList(context, result)`（传的是 `result`，可能是 null —— 见「关键行为」1）** → `bindSecond()`
 * `onFailure` / `onCancel`：空实现
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`saveUserTagList(context, result)` 传的是 `result` 而不是 `userTagList`** ——
 *    result 为 null 时会**保存 null**（清掉缓存）。这是上游的真实行为；
 *    "顺手修成 `userTagList`"会改变"网络失败时缓存是否被清空"的语义。
 * 2. **翻译开关走两条路**：本页 `showTagTranslations ? getName(ehTags) : tagName`；
 *    而 `SubscriptionItemAdapter`（抽屉用的）**无条件 `getName`**。
 *    两者对同一开关的处理不一致 —— **上游如此，不要统一**。
 * 3. **`imageView` 与 `dragHandler` 是同一个控件**（`R.id.drag_handler`）：
 *    所以"隐藏/关注"图标画在**拖拽手柄**上。改成独立控件会改变布局表现。
 * 4. **`label` 与 `dragHandler` 没绑点击**，只有 `delete` 有 —— 点标签不触发任何动作。
 * 5. `bindSecond()` 里**重复了一套拖拽 + adapter 装配**（与 onCreateView3 相同）—— 上游代码重复，照搬。
 * 6. 删除前的 UI 状态是 **progress 显示 + 列表 INVISIBLE**（不是 GONE）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `ToolbarScene` 未落地 → `SubscriptionsSceneHost`（列表/进度/提示/删除接口/返回）。
 * 2. `ViewTransition(recyclerView, tip)` → `updateView()` 返回 0/1（同 HistoryScene 做法）。
 * 3. `RecyclerViewDragDropManager` + `DraggableItemAnimator` → ArkUI 侧由 `List` 承担；
 *    本文件只产出**拖拽判定/移动决策**（与 DownloadLabelsScene 同一套做法）。
 * 4. `Toast` 的中文原文（"描述文件未找到？？？重启试试~"）→ 宿主 `showTipRaw(text)`。
 * 5. `EhClient.execute(METHOD_DELETE_WATCHED, url, userTag)` → `SubscriptionsApi.deleteWatched(url, tag)`。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `UserTag` / `UserTagList`（`getId` / `getName` / `tagName` / `watched` / `hidden`）、`EhTagDatabase`、
 * `hippo/ui/layout/scene_label_list.ets`（与下载标签页共用）、`hippo/ui/drawable/big_search.ets`、
 * 图标组件 `ic_baseline_visibility_24` / `ic_baseline_visibility_off_24`。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * `item_subscription` 布局**没有独立文件** → `TODO(ui-scene)`，本文件只产出绑定数据。
 * `EhApplication.getUserTagList` / `saveUserTagList` → 宿主注入（storage-db 的缓存层）。
 */

import { UserTag, UserTagList, UserTagConfig } from '../../../../client/data/UserTag';

/** 上游 `R.layout.scene_label_list`（与下载标签页共用） */
export const LAYOUT_SCENE_LABEL_LIST: string = 'scene_label_list';
/** 上游 `@string/tag_title`（**注意不是 subscriptions**） */
export const TITLE_TAG: string = 'app.string.tag_title';
/** 上游 `@string/no_quick_search`（文案从"快速搜索"演化来，未改名） */
export const TIP_NO_QUICK_SEARCH: string = 'app.string.no_quick_search';
/** 上游 `@string/delete_subscription_title` / `@string/delete_quick_search_message` */
export const TITLE_DELETE_SUBSCRIPTION: string = 'app.string.delete_subscription_title';
export const MESSAGE_DELETE_SUBSCRIPTION: string = 'app.string.delete_quick_search_message';
/** 上游 `@drawable/big_search` */
export const DRAWABLE_BIG_SEARCH: string = 'big_search';
/** 上游 `bindSecond()` 里 `mRecyclerView == null` 时的 Toast 文案（**中文原文**） */
export const TOAST_RECYCLER_MISSING: string = '描述文件未找到？？？重启试试~';
/** 上游两个状态图标 */
export const ICON_VISIBILITY: string = 'ic_baseline_visibility_24';
export const ICON_VISIBILITY_OFF: string = 'ic_baseline_visibility_off_24';
/** `ViewTransition` 索引 */
export const VIEW_LIST: number = 0;
export const VIEW_TIP: number = 1;
/** 上游 `RecyclerView.NO_POSITION` */
export const NO_POSITION: number = -1;

/** 本页宿主能力 */
export interface SubscriptionsSceneHost {
  /** 上游 `EhApplication.getUserTagList(context)` */
  getUserTagList(): UserTagList | null;
  /** 上游 `saveUserTagList(context, result)`（**传 null 表示清空缓存**，见「关键行为」1） */
  saveUserTagList(result: UserTagList | null): void;
  /** 上游 `progressView.setVisibility` */
  setProgressVisible(visible: boolean): void;
  /** 上游 `mRecyclerView.setVisibility(VISIBLE/INVISIBLE)` */
  setRecyclerViewVisible(visible: boolean): void;
  /** 上游 `Toast.makeText(context, "描述文件未找到？？？重启试试~", LENGTH_LONG)` */
  showTipRaw(text: string): void;
  /** 上游 `Settings.getShowTagTranslations()` */
  getShowTagTranslations(): boolean;
  /** 上游 `EhTagDatabase.getInstance(context)` */
  getEhTagDatabase(): Object | null;
  onBackPressed(): void;
}

/** 标签接口（`METHOD_DELETE_WATCHED`） */
export interface SubscriptionsApi {
  deleteWatched(url: string, tag: UserTag): Promise<UserTagList | null>;
}

/** 上游 `EhUrl.getMyTag()` 的等价（url 拼装属 net-parse；本实现透传基址） */
export const MY_TAG_URL: string = 'MY_TAG_URL';

/** 列表项绑定数据（上游 `SubscriptionHolder` 的 label/图标） */
export class SubscriptionRowViewModel {
  /** `getItemId` 的稳定 id */
  id: number = 0;
  /** `holder.label.setText(...)` */
  label: string = '';
  /** 状态图标名（null = 不显示） */
  stateIcon: string | null = null;
  tagName: string = '';
}

export class SubscriptionsScene {
  private host: SubscriptionsSceneHost;
  private api: SubscriptionsApi;
  private userTagList: UserTagList | null = null;
  private lastError: Error | null = null;

  constructor(host: SubscriptionsSceneHost, api: SubscriptionsApi) {
    this.host = host;
    this.api = api;
  }

  /** 上游 `onCreate()`：取缓存里的标签列表 */
  onCreate(): void {
    this.userTagList = this.host.getUserTagList();
  }

  /** 上游 `onDestroy()`：`userTagList = null` */
  onDestroy(): void {
    this.userTagList = null;
  }

  /** 上游 `onNavigationClick` */
  onNavigationClick(): void {
    this.host.onBackPressed();
  }

  /** 上游 `updateView()`：非空 → 列表视图；否则 tip */
  updateView(): number {
    const list: UserTagList | null = this.userTagList;
    if (list !== null && list.userTags.length > 0) {
      return VIEW_LIST;
    }
    return VIEW_TIP;
  }

  /**
   * 上游 `bindSecond()`：
   * ① progress GONE ② **`mRecyclerView == null` → 中文 Toast 并 return**
   * ③ 列表 VISIBLE ④ `userTagList == null` → 新建空列表
   * （上游此处重复装配 drag&drop + adapter，本实现由宿主 bindAdapter 承担）
   */
  bindSecond(hasRecyclerView: boolean): boolean {
    this.host.setProgressVisible(false);
    if (!hasRecyclerView) {
      this.host.showTipRaw(TOAST_RECYCLER_MISSING);
      return false;
    }
    this.host.setRecyclerViewVisible(true);
    if (this.userTagList === null) {
      const empty: UserTagList = new UserTagList();
      empty.userTags = [];
      this.userTagList = empty;
    }
    return true;
  }

  /** 上游 `getItemCount()` */
  getItemCount(): number {
    const list: UserTagList | null = this.userTagList;
    return list === null ? 0 : list.userTags.length;
  }

  /** 上游 `getItemId(position)` → `userTag.getId()`；**null 时 0** */
  getItemId(position: number): number {
    const list: UserTagList | null = this.userTagList;
    if (list === null || position < 0 || position >= list.userTags.length) {
      return 0;
    }
    return list.userTags[position].getId();
  }

  /**
   * 上游 `QuickSearchAdapter.onBindViewHolder`：
   * **翻译开关走两条路**（见「关键行为」2）：开 → `getName(ehTags)`；关 → **直接用 `tagName`**。
   * 图标：`hidden` 先设 off、`watched` 后设 on（**watched 覆盖 hidden**）。
   */
  bindItem(position: number): SubscriptionRowViewModel | null {
    const list: UserTagList | null = this.userTagList;
    if (list === null || position < 0 || position >= list.userTags.length) {
      return null;
    }
    const tag: UserTag = list.userTags[position];
    const vm: SubscriptionRowViewModel = new SubscriptionRowViewModel();
    vm.id = tag.getId();
    vm.tagName = tag.tagName;
    if (this.host.getShowTagTranslations()) {
      // 上游：getName(ehTags)（本仓库签名是 getName(config, ehTags)）
      vm.label = tag.getName(new UserTagConfig(), this.host.getEhTagDatabase());
    } else {
      // ★ 上游关翻译时**直接用 tagName**，不调 getName
      vm.label = tag.tagName;
    }
    let icon: string | null = null;
    if (tag.hidden) {
      icon = ICON_VISIBILITY_OFF;
    }
    if (tag.watched) {
      icon = ICON_VISIBILITY;
    }
    vm.stateIcon = icon;
    return vm;
  }

  /**
   * 上游 `SubscriptionHolder.onClick`（**只有 delete 有监听**，见「关键行为」4）：
   * `position == NO_POSITION || userTagList == null → null`；
   * 否则产出确认对话框描述（title + message 带 `tag.tagName`）。
   */
  buildDeleteDialog(position: number): SubscriptionDeleteDialogSpec | null {
    if (position === NO_POSITION) {
      return null;
    }
    const list: UserTagList | null = this.userTagList;
    if (list === null || position < 0 || position >= list.userTags.length) {
      return null;
    }
    const tag: UserTag = list.userTags[position];
    const spec: SubscriptionDeleteDialogSpec = new SubscriptionDeleteDialogSpec();
    spec.title = TITLE_DELETE_SUBSCRIPTION;
    // 上游 `getString(@string/delete_quick_search_message, tagName)`：占位替换由宿主本地化层做，这里传原值
    spec.message = tag.tagName;
    spec.tagName = tag.tagName;
    this.pendingDelete = new PendingDeleteTag(tag);
    return spec;
  }

  private pendingDelete: PendingDeleteTag | null = null;

  /**
   * 上游 `deleteTag(userTag)`：**progress VISIBLE + 列表 INVISIBLE** → 发删除请求（见「关键行为」6）。
   */
  async deleteTag(): Promise<boolean> {
    const pending: PendingDeleteTag | null = this.pendingDelete;
    if (pending === null) {
      return false;
    }
    this.host.setProgressVisible(true);
    this.host.setRecyclerViewVisible(false);
    try {
      const result: UserTagList | null = await this.api.deleteWatched(MY_TAG_URL, pending.tag);
      this.applyResult(result);
    } catch (e) {
      this.lastError = e as Error;
    }
    return true;
  }

  /**
   * 上游 `SubscriptionDetailListener.onSuccess(result)`：
   * ★ **`saveUserTagList(context, result)` 传的是 result**（可能 null → 清空缓存，见「关键行为」1）；
   * `result == null || result.userTags == null` → 本地 userTags = []。
   */
  applyResult(result: UserTagList | null): void {
    if (this.userTagList === null) {
      this.userTagList = new UserTagList();
      this.userTagList.userTags = [];
    }
    if (result === null || result.userTags === null) {
      this.userTagList.userTags = [];
    } else {
      this.userTagList.userTags = result.userTags;
    }
    // ★ 上游保存的是 result（不是 userTagList）
    this.host.saveUserTagList(result);
    this.bindSecond(true);
  }

  /** 最近一次错误 */
  getLastError(): Error | null {
    return this.lastError;
  }

  /** 当前列表（只读副本，便于断言"缓存保存的是 result 而不是 userTagList"） */
  getUserTagList(): UserTagList | null {
    return this.userTagList;
  }

  /**
   * 上游 `onCheckCanStartDrag` / `onMoveItem` 的对位（本页上游**没有实现拖拽回调** —— 它只用
   * `DraggableItemAnimator` 与 `attachRecyclerView`，**没有 `DraggableItemAdapter` 实现**，
   * 所以拖拽实际不会触发移动。见 DEVIATIONS 记录）。
   */
  canStartDrag(): boolean {
    return false;
  }
}

/** 删除确认对话框描述 */
export class SubscriptionDeleteDialogSpec {
  title: string = TITLE_DELETE_SUBSCRIPTION;
  /** `getString(@string/delete_quick_search_message, tag.tagName)` 的结果（宿主本地化层替换） */
  message: string = '';
  tagName: string = '';
}

/** 待删除的标签（上游用闭包捕获 UserTag） */
class PendingDeleteTag {
  tag: UserTag;

  constructor(tag: UserTag) {
    this.tag = tag;
  }
}

