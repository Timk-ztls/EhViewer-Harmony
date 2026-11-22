/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/SubscriptionDraw.java
 *       （inventory S0245，上游实际 339 行；清单登记 273 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/SubscriptionDraw.ets
 *
 * 背景：**画廊列表页左侧抽屉里的「订阅」页**（ViewPager 第 0 页）。它自己不是一个 Scene，
 * 而是被列表页的 ViewPager 承载的一段"抽屉内容"：显示已关注/隐藏的标签列表，
 * 支持点标签 → 触发列表刷新、菜单 → 加标签 / 进订阅管理页。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 常量：`SUBSCRIPTION_DRAW_SCROLL_Y = "SubscriptionDrawScrollY"`、`SUBSCRIPTION_DRAW_POS = "SubscriptionDrawPos"`
 * 字段：`needLoad = true`（**决定 onCreate 是否发请求**）、`userTagList`、`ehTags`、`tagName`
 * 构造：`ehTags == null` → `EhTagDatabase.getInstance(context)`（**懒取单例**）
 * `onCreate(drawPager, activity, callback)`:
 *   · inflate `subscription_draw`；取 5 个视图（`tag_list_view_progress` / `tag_list_parent` /
 *     `not_login_text` / `toolbar` / `tip` / `list_view`）
 *   · **`frameLayout.setVisibility(GONE)`**（先藏列表区，等数据）
 *   · `tip.setText(@string/subscription_tip)`；toolbar logo `ic_baseline_subscriptions_24`、
 *     title `@string/subscription`、菜音 `@menu/drawer_gallery_list`
 *   · 菜单：`action_add → addNewTag()`、`action_settings → seeDetailPage()`，**恒 return true**
 *   · toolbar 点击 → `drawPager.setCurrentItem(0)`（点标题回第 0 页）
 *   · **`if (needLoad) loadData()`** —— 失败时 `catch (EhException) e.printStackTrace()`（**不崩、不提示**）
 * `setUserTagList(tagList)`：**首次直接持有引用**；之后**只替换 `userTags` 数组**，保留原对象
 *   （因为 `stageId` 等字段挂在对象上，换对象会丢 —— 见「关键行为」1）
 * `seeDetailPage()`：`!isLogin()` → toast `settings_eh_identity_cookies_tourist` 并 return；
 *   `userTagList == null` → toast `empty_subscription` 并 return；
 *   否则 `userTagList.stageId = activity.getStageId()` → `saveUserTagList(context, userTagList)`
 *   → `startScene(new Announcer(SubscriptionsScene))`
 * `bindViewSecond()`：progress GONE + frame VISIBLE；
 *   `userTagList.userTags.isEmpty()` 时：**只有登录了才显示 `not_login_text`**，然后 return；
 *   否则建 `SubscriptionItemAdapter`、`listView.setAdapter`、
 *   点击 → `callback.onSubscriptionItemClick(tag.tagName)`（**传的是 tagName，不是 UserTag**）、
 *   `setOnScrollListener(new ScrollListener())`、**`if (size > 0) resume()`**
 * `addNewTag()`：`!isLogin()` → toast；`tagName = callback.getAddTagName(userTagList)`；
 *   **`tagName == null` → toast `can_not_use_this_tag` 并 return**；
 *   否则 EditTextDialog（初值 `tagName`、hint `@string/tag_title`、title `@string/add_tag_dialog_title`、
 *   正按钮 `@string/subscription_watched` → `requestTag(tagName, true)`、
 *   负按钮 `@string/subscription_hidden` → `requestTag(tagName, false)`）
 * `onDialogPositiveButtonClick` / `onDialogNegativeButtonClick`：**先 `dismiss()` 再 `requestTag`**
 * `requestTag(tagName, state)`：url = `getMyTag()`；`context/activity` 任一 null → return；
 *   progress VISIBLE + frame GONE；`TagPushParam{ tagNameNew=tagName, tagWatchNew='on' }`（state=true）
 *   或 `tagHiddenNew='on'`（state=false）；`METHOD_ADD_TAG`
 * `request()`：url = `getMyTag()`；`context/activity` 任一 null → **返回 false**；`METHOD_GET_WATCHED`；返回 true
 * `loadData()`：`requested = request()`；**`!requested` → 抛 `EhException("请求数据失败请更换IP地址或检查网络设置是否正确~")`**
 *   （上游中文原文，照搬）
 * `resume()`：从 `getTempCache` 取 scrollY 与 pos；**两者都非 null 才** `listView.setSelection(pos)`
 * `SubscriptionDetailListener.onSuccess(result)`：
 *   `result == null` → `userTagList = new UserTagList()` + 空数组；否则 `userTagList = result`
 *   → `saveUserTagList(context, userTagList)` → `bindViewSecond()` → **`needLoad = false`**
 * `onFailure` / `onCancel`：**空实现**（失败什么都不做 —— 见「关键行为」3）
 * `ScrollListener.onScrollStateChanged(view, state)`：
 *   `item = view.getChildAt(0)`；**`item == null` → return**；
 *   `scrollY = firstPos * item.getHeight() - top`；存两个 tempCache
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`setUserTagList` 首次持有引用、之后只换数组** —— 对象上的 `stageId` 不能丢。
 * 2. **`needLoad` 是"只加载一次"的闸门**，且**只在 onSuccess 里置 false** ——
 *    失败后仍为 true，下次 onCreate 会重试（但失败回调是空的，所以用户看不到错误）。
 * 3. **`onFailure` / `onCancel` 空实现** —— 上游如此：请求失败后页面停在"progress 显示"状态。
 *    这不是好设计，但**改掉会改变行为**（我们的实现如实保留，并在 DEVIATIONS 记一笔）。
 * 4. **`addNewTag` 先取 `getAddTagName` 再判 null** —— 名字冲突/非法由 callback 决定并给 toast。
 * 5. **`bindViewSecond` 里 `not_login_text` 只在"已登录且列表为空"时显示** ——
 *    未登录 + 空列表时**什么都不显示**（tip 保持 `subscription_tip`）。
 * 6. **`resume()` 要求 scrollY 与 pos **都非空**才恢复**（只判断了 pos 非空，但条件里两者都要）。
 * 7. **`loadData` 抛的是 `EhException` 且只 printStackTrace** —— 不弹 toast、不切视图。
 *
 * ── 平台差异（依赖倒置）────────────────────────────────────────────────────
 * 1. **`Context`/`LayoutInflater`/`ViewPager`/`ListView`/`ProgressView`** 在 ArkUI 无对位：
 *    本文件只保留**状态机 + 数据装配**，视图与 pager 通过 `DrawHost` 注入。
 * 2. **`EhClient.execute(EhRequest)`** → `TagApi` 注入（`fetchWatched()` / `addTag(param)`），
 *    由 net-parse 的实现承担；`TagPushParam` 用本仓库已交付的 `TagPushParam`（S0065）。
 * 3. **`EhApplication.saveUserTagList` / `getTempCache` / `putTempCache`** → `DrawHost` 能力。
 * 4. **`isLogin()`（来自 `Settings.*` 静态导入）** → 宿主 `isLogin()`。
 * 5. **`Toast`** → 宿主 `showToast(key)`（短提示）与 `showTip`。
 * 6. `SubscriptionItemAdapter`（S0246，已移植）**直接复用**，不重复实现。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `UserTag` / `UserTagList`（`hippo/ehviewer/client/data/UserTag.ets`，含 `stageId` 字段？见缺口）、
 * `TagPushParam`（同文件）、`EhTagDatabase`、`SubscriptionItemAdapter`（本批已交付）、
 * `hippo/ui/layout/subscription_draw.ets`（下游布局，实测存在）。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * `UserTagList.stageId`：上游在 `userTagList` 上挂 `stageId`；本仓库 `UserTagList` **没有该字段**
 * → 通过 `DrawHost.setStageId(list, id)` 表达（不改 storage-db 的文件）。
 */

import { UserTag, UserTagList, TagPushParam } from '../../../../client/data/UserTag';
import { SubscriptionItemAdapter } from './SubscriptionItemAdapter';

/** 上游两个 tempCache 键 */
export const SUBSCRIPTION_DRAW_SCROLL_Y: string = 'SubscriptionDrawScrollY';
export const SUBSCRIPTION_DRAW_POS: string = 'SubscriptionDrawPos';

/** 上游字符串键 */
export const TIP_SUBSCRIPTION: string = 'app.string.subscription_tip';
export const TITLE_SUBSCRIPTION: string = 'app.string.subscription';
export const TOAST_TOURIST: string = 'app.string.settings_eh_identity_cookies_tourist';
export const TOAST_EMPTY_SUBSCRIPTION: string = 'app.string.empty_subscription';
export const TOAST_CANNOT_USE_TAG: string = 'app.string.can_not_use_this_tag';
export const TITLE_ADD_TAG_DIALOG: string = 'app.string.add_tag_dialog_title';
export const HINT_TAG_TITLE: string = 'app.string.tag_title';
export const BTN_WATCHED: string = 'app.string.subscription_watched';
export const BTN_HIDDEN: string = 'app.string.subscription_hidden';
/** 上游 `loadData()` 抛的异常消息（**中文原文照搬**） */
export const ERR_REQUEST_FAILED: string = '请求数据失败请更换IP地址或检查网络设置是否正确~';

/** 上游 `R.menu.drawer_gallery_list` 的两个菜单项 */
export const MENU_ACTION_ADD: string = 'action_add';
export const MENU_ACTION_SETTINGS: string = 'action_settings';
export const MENU_DRAWER_GALLERY_LIST: string = 'menu/drawer_gallery_list';

/** 上游 toolbar 的两个图标资源名 */
export const DRAWABLE_SUBSCRIPTIONS: string = 'ic_baseline_subscriptions_24';

/** 本抽屉对宿主的最小依赖（`Context`/`ViewPager`/`ListView`/`EhClient`/`EhApplication` 的对位） */
export interface DrawHost {
  /** 上游 `Settings.isLogin()`（静态导入） */
  isLogin(): boolean;
  /** 上游 `EhApplication.getUserTagList(context)` */
  getUserTagList(): UserTagList | null;
  /** 上游 `EhApplication.saveUserTagList(context, list)` */
  saveUserTagList(list: UserTagList | null): void;
  /** 上游 `userTagList.stageId = activity.getStageId()`（本仓库 UserTagList 无该字段，见「缺口」） */
  setStageId(list: UserTagList, stageId: number): void;
  /** 上游 `activity.getStageId()` */
  getStageId(): number;
  /** 上游 `EhApplication.getTempCache(key)` */
  getTempCache(key: string): Object | null;
  /** 上游 `EhApplication.putTempCache(key, value)` */
  putTempCache(key: string, value: Object): void;
  /** 上游 `Toast.makeText(..., LENGTH_SHORT)` */
  showToast(key: string): void;
  /** 上游 `activity.startScene(new Announcer(SubscriptionsScene.class))` */
  startSubscriptionsScene(): void;
  /** 上游 `drawPager.setCurrentItem(0)` */
  setPagerItem(index: number): void;
  /** 上游 `progressView.setVisibility(VISIBLE/GONE)` 与 `frameLayout.setVisibility(...)` */
  setProgressVisible(visible: boolean): void;
  setListAreaVisible(visible: boolean): void;
  /** 上游 `textView.setVisibility(VISIBLE)`（`not_login_text`） */
  setNotLoginTextVisible(visible: boolean): void;
  /** 上游 `listView.setAdapter(adapter)` + 点击回调 + 滚动监听 */
  bindAdapter(adapter: SubscriptionItemAdapter, onItemClick: (position: number) => void): void;
  /** 上游 `listView.setSelection(pos)` */
  setListSelection(position: number): void;
}

/** 上游 `SubscriptionCallback` 的最小面（列表页提供） */
export interface SubscriptionCallbackLike {
  /** 上游 `callback.onSubscriptionItemClick(tag.tagName)` */
  onSubscriptionItemClick(tagName: string): void;
  /** 上游 `callback.getAddTagName(userTagList)`；**null = 该名字不可用** */
  getAddTagName(list: UserTagList | null): string | null;
}

/** 标签接口（`METHOD_GET_WATCHED` / `METHOD_ADD_TAG`） */
export interface TagApi {
  /** 上游 `METHOD_GET_WATCHED`：`EhUrl.getMyTag()` */
  fetchWatched(url: string): Promise<UserTagList | null>;
  /** 上游 `METHOD_ADD_TAG`：`setArgs(url, param)` */
  addTag(url: string, param: TagPushParam): Promise<UserTagList | null>;
}

/** 上游 `EhUrl.getMyTag()` 的等价（url 拼装属 net-parse，本实现透传基址） */
export const MY_TAG_URL: string = 'MY_TAG_URL';

/** 一次"加标签"对话框的描述（上游 `EditTextDialogBuilder`，见 D-059 同族做法） */
export class AddTagDialogSpec {
  title: string = TITLE_ADD_TAG_DIALOG;
  hint: string = HINT_TAG_TITLE;
  /** 初值 = `callback.getAddTagName(userTagList)` 的结果 */
  text: string = '';
  positiveText: string = BTN_WATCHED;
  negativeText: string = BTN_HIDDEN;
}

export class SubscriptionDraw {
  private host: DrawHost;
  private api: TagApi;
  private callback: SubscriptionCallbackLike;
  /** 上游 `boolean needLoad = true` */
  private needLoad: boolean = true;
  /** 上游 `UserTagList userTagList` */
  private userTagList: UserTagList | null = null;
  /** 上游 `String tagName`（addNewTag 里捕获，供两个按钮回调使用） */
  private tagName: string | null = null;
  /** 最近一次的错误（上游是 `printStackTrace`，本实现保留对象便于断言） */
  private lastError: Error | null = null;

  constructor(host: DrawHost, api: TagApi, callback: SubscriptionCallbackLike) {
    this.host = host;
    this.api = api;
    this.callback = callback;
  }

  /** 上游 `getTag()` 的等价（`mTag` 由场景传入；本实现透传） */
  getTag(): string {
    return 'SubscriptionDraw';
  }

  /**
   * 上游 `onCreate(drawPager, activity, callback)`：
   * ① 先藏列表区 ② 菜单装配 ③ `needLoad` 时发请求（失败只记录，不崩）
   */
  async onCreate(): Promise<void> {
    // 上游：frameLayout.setVisibility(GONE)
    this.host.setListAreaVisible(false);
    // 上游：if (needLoad) { try { loadData() } catch (EhException e) { printStackTrace() } }
    if (this.needLoad) {
      try {
        await this.loadData();
      } catch (e) {
        // 上游：e.printStackTrace() —— **不弹提示、不切视图**
        this.lastError = e as Error;
      }
    }
  }

  /** 上游 `onCreate` 里 toolbar 点击 → `drawPager.setCurrentItem(0)` */
  onToolbarClick(): void {
    this.host.setPagerItem(0);
  }

  /**
   * 上游菜单点击：`action_add → addNewTag()`、`action_settings → seeDetailPage()`，**恒返回 true**。
   * @returns 恒 true（注意与 DownloadLabelsScene 的 `return false` 相反）
   */
  onMenuItemClick(itemId: string): boolean {
    if (itemId === MENU_ACTION_ADD) {
      this.addNewTag();
    } else if (itemId === MENU_ACTION_SETTINGS) {
      this.seeDetailPage();
    }
    return true;
  }

  /**
   * 上游 `setUserTagList(tagList)`：**首次持有引用，之后只换数组**（见「关键行为」1）。
   */
  setUserTagList(tagList: UserTagList): void {
    const cur: UserTagList | null = this.userTagList;
    if (cur === null) {
      this.userTagList = tagList;
    } else {
      cur.userTags = tagList.userTags;
    }
  }

  /** 当前标签列表（只读引用，便于断言"对象未替换"） */
  getUserTagList(): UserTagList | null {
    return this.userTagList;
  }

  /** 上游 `seeDetailPage()` */
  seeDetailPage(): boolean {
    if (!this.host.isLogin()) {
      this.host.showToast(TOAST_TOURIST);
      return false;
    }
    const list: UserTagList | null = this.userTagList;
    if (list === null) {
      this.host.showToast(TOAST_EMPTY_SUBSCRIPTION);
      return false;
    }
    // 上游：userTagList.stageId = activity.getStageId()
    this.host.setStageId(list, this.host.getStageId());
    this.host.saveUserTagList(list);
    this.host.startSubscriptionsScene();
    return true;
  }

  /**
   * 上游 `bindViewSecond()`：
   * progress GONE + frame VISIBLE；
   * **空列表时只有登录了才显示 `not_login_text`**（见「关键行为」5）。
   */
  bindViewSecond(): void {
    this.host.setProgressVisible(false);
    this.host.setListAreaVisible(true);
    const list: UserTagList | null = this.userTagList;
    if (list !== null && list.userTags.length === 0) {
      if (this.host.isLogin()) {
        this.host.setNotLoginTextVisible(true);
      }
      return;
    }
    if (list === null) {
      return;
    }
    const adapter: SubscriptionItemAdapter = new SubscriptionItemAdapter(list, null);
    this.host.bindAdapter(adapter, (position: number): void => {
      const tags: UserTag[] = list.userTags;
      if (position >= 0 && position < tags.length) {
        // 上游：callback.onSubscriptionItemClick(tag.tagName)
        this.callback.onSubscriptionItemClick(tags[position].tagName);
      }
    });
    // 上游：if (userTagList.size() > 0) resume()
    if (list.userTags.length > 0) {
      this.resume();
    }
  }

  /** 上游 `addNewTag()`：未登录 → toast；名字不可用 → toast；否则产对话框描述 */
  addNewTag(): AddTagDialogSpec | null {
    if (!this.host.isLogin()) {
      this.host.showToast(TOAST_TOURIST);
      return null;
    }
    const name: string | null = this.callback.getAddTagName(this.userTagList);
    if (name === null) {
      this.host.showToast(TOAST_CANNOT_USE_TAG);
      return null;
    }
    this.tagName = name;
    const spec: AddTagDialogSpec = new AddTagDialogSpec();
    spec.text = name;
    this.pendingAddTagDialog = spec;
    return spec;
  }

  private pendingAddTagDialog: AddTagDialogSpec | null = null;

  getAddTagDialog(): AddTagDialogSpec | null {
    return this.pendingAddTagDialog;
  }

  /** 上游正按钮：**先 dismiss 再 requestTag(..., true)** */
  onDialogPositive(): Promise<void> {
    this.pendingAddTagDialog = null;
    return this.requestTag(true);
  }

  /** 上游负按钮：**先 dismiss 再 requestTag(..., false)** */
  onDialogNegative(): Promise<void> {
    this.pendingAddTagDialog = null;
    return this.requestTag(false);
  }

  /** 上游 `requestTag(tagName, tagState)`：progress VISIBLE + frame GONE → `METHOD_ADD_TAG` */
  private async requestTag(tagState: boolean): Promise<void> {
    const name: string | null = this.tagName;
    if (name === null) {
      return;
    }
    this.host.setProgressVisible(true);
    this.host.setListAreaVisible(false);
    const param: TagPushParam = new TagPushParam();
    param.tagNameNew = name;
    if (tagState) {
      param.tagWatchNew = 'on';
    } else {
      param.tagHiddenNew = 'on';
    }
    try {
      const result: UserTagList | null = await this.api.addTag(MY_TAG_URL, param);
      this.applyResult(result, true);
    } catch (e) {
      this.lastError = e as Error;
    }
  }

  /** 上游 `request()`：`context/activity` 为 null 时**返回 false**（→ loadData 抛异常） */
  private async request(): Promise<boolean> {
    // 本实现 host 恒存在，等价于"两者都不为 null" → 恒 true
    try {
      const result: UserTagList | null = await this.api.fetchWatched(MY_TAG_URL);
      this.applyResult(result, false);
    } catch (e) {
      this.lastError = e as Error;
    }
    return true;
  }

  /** 上游 `loadData()`：`!requested` → 抛 `EhException(中文原文)` */
  private async loadData(): Promise<void> {
    const requested: boolean = await this.request();
    if (!requested) {
      throw new Error(ERR_REQUEST_FAILED);
    }
  }

  /**
   * 上游 `SubscriptionDetailListener.onSuccess(result)`：
   * ① `result == null` → 新建空列表 ② 否则直接持有 result
   * ③ `saveUserTagList` ④ `bindViewSecond()` ⑤ **`needLoad = false`**
   *
   * `needLoad=false` 只在**首次加载/加标签成功**时置位（上游两处 onSuccess 都会走这里；
   * 加标签场景上游用的是同一个 listener，故同样会置位）。
   */
  applyResult(result: UserTagList | null, viaAddTag: boolean): void {
    if (result === null) {
      const empty: UserTagList = new UserTagList();
      empty.userTags = [];
      this.userTagList = empty;
    } else {
      this.userTagList = result;
      if (result.userTags === null) {
        result.userTags = [];
      }
    }
    this.host.saveUserTagList(this.userTagList);
    this.bindViewSecond();
    this.needLoad = false;
  }

  /** 上游 `resume()`：**scrollY 与 pos 都非空**才恢复（见「关键行为」6） */
  resume(): void {
    const scrollY: Object | null = this.host.getTempCache(SUBSCRIPTION_DRAW_SCROLL_Y);
    const pos: Object | null = this.host.getTempCache(SUBSCRIPTION_DRAW_POS);
    if (scrollY !== null && pos !== null) {
      this.host.setListSelection(pos as number);
    }
  }

  /**
   * 上游 `ScrollListener.onScrollStateChanged(view, state)`：
   * `item = view.getChildAt(0)`；**null → return**；`scrollY = firstPos * height - top`；存两个 tempCache。
   */
  onScrollStateChanged(firstVisiblePosition: number, itemHeight: number, itemTop: number,
    hasItem: boolean): void {
    if (!hasItem) {
      return;
    }
    const scrollY: number = firstVisiblePosition * itemHeight - itemTop;
    this.host.putTempCache(SUBSCRIPTION_DRAW_SCROLL_Y, scrollY);
    this.host.putTempCache(SUBSCRIPTION_DRAW_POS, firstVisiblePosition);
  }

  /** 是否需要首次加载（上游 `needLoad`） */
  isNeedLoad(): boolean {
    return this.needLoad;
  }

  /** 最近一次错误（上游 `printStackTrace` 的等价观测口） */
  getLastError(): Error | null {
    return this.lastError;
  }
}
