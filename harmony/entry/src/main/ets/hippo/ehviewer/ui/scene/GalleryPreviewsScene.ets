/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/GalleryPreviewsScene.java
 *       （inventory S0252，上游实际 487 行；清单登记 411 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/GalleryPreviewsScene.ets
 *
 * 背景：**画廊缩略图预览页**（详情页里"预览"入口）。网格列出全部页的缩略图，点某页 → 进阅读器并定位到该页。
 * 数据来自 `METHOD_GET_PREVIEW_SET`（分页），由 `ContentLayout.ContentHelper` 承担
 * **7 态 + 分页 + 首刷 + goTo** 的通用列表状态机。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class GalleryPreviewsScene extends ToolbarScene implements OnItemClickListener`
 *   常量：`KEY_GALLERY_INFO = "gallery_info"`、`KEY_HAS_FIRST_REFRESH = "has_first_refresh"`
 *   `onCreate(savedInstanceState)`:
 *     `mClient = EhApplication.getEhClient(context)`；`onInit()`
 *     **注意**：上游把 `if (savedInstanceState == null) onInit() else onRestore()` **整段注释掉**，
 *     改成**无条件 `onInit()`** —— 即"重建时也重新从 args 读"，而不是从 savedInstanceState 恢复。
 *   `onInit()`: `args == null → return`；`mGalleryInfo = args.getParcelable(KEY_GALLERY_INFO)`
 *   `onRestore()` / `onSaveInstanceState()`: **整段注释掉**（不保存状态）
 *   `onCreateView3(...)`:
 *     · `ContentLayout scene_gallery_previews` + **`hideFastScroll()`**（预览页不显示快速滚动条）
 *     · 适配器 `GalleryPreviewAdapter`；列宽 = `@dimen(Settings.getThumbSizeResId())`；
 *       `AutoGridLayoutManager(strategy = STRATEGY_SUITABLE_SIZE)`（**按可用宽度算列数**）
 *     · `clipToPadding = false`；`itemDecoration = MarginItemDecoration(padding=dp2pix(4) ×5)`
 *     · `mHelper = new GalleryPreviewHelper()`；`contentLayout.setHelper(mHelper)`
 *     · **首次才刷新**：`if (!mHasFirstRefresh) { mHasFirstRefresh = true; mHelper.firstRefresh(); }`
 *   `onDestroyView()`:
 *     · **若当前显示的是 tip 视图（index==1）→ `mHasFirstRefresh = false`**（下次进来要重刷）
 *     · `recyclerView.stopScroll()`；`mAdapter = null`（**不置空 mHelper**）
 *   `onViewCreated` → `setTitle(@string/gallery_previews)` + 返回图标 `v_arrow_left_dark_x24`
 *   `getMenuResId()` → `R.menu.scene_gallery_previews`
 *   `onMenuItemClick(item)` → `R.id.action_go_to`：
 *     `mHelper == null → true`；`pages = mHelper.getPages()`；
 *     **`pages > 0 && mHelper.canGoTo()`** 才弹 GoTo 对话框（Slider 范围 1..pages，进度 = `getPageForTop()+1`）
 *   `onNavigationClick` → `onBackPressed()`
 *   `onItemClick(position)`:
 *     · `context/mHelper/mGalleryInfo` 任一为 null → 返回 **true**（注意：不是 false）
 *     · `p = mHelper.getDataAtEx(position)`；`p != null` 时：起 `GalleryActivity(ACTION_EH, DATA_IN_EVENT=true)`
 *       然后 `EventBus.postSticky(GalleryActivityEvent(p.getPosition(), mGalleryInfo))`
 *       —— **页码通过 sticky 事件传，不是 intent extra**（`KEY_PAGE` 那行被注释）
 *     · `catch (RuntimeException) → Analytics.recordException(e)`（**吞掉异常不让页面崩**）
 *   `GalleryPreviewAdapter.onBindViewHolder`: `preview.load(holder.image)`；`text.setText(position + 1)`（**1 起显示**）
 *   `GalleryPreviewHelper : ContentLayout.ContentHelper<GalleryPreview>`:
 *     · `getPageData(taskId, type, page)`：**无 activity/client/galleryInfo → `onGetException` + return**
 *       （`try/catch IllegalStateException ignore`）
 *     · url = `EhUrl.getGalleryDetailUrl(gid, token, page, false)`（**最后参数 false = 不带 nl**）
 *     · `request.setMethod(METHOD_GET_PREVIEW_SET)`、`setArgs(url)`、回调 `GetPreviewSetListener(taskId)`
 *     · `getPageData(..., append)` **空实现**；`getExPageData(...)` 与 `getPageData` 同体（复制粘贴）
 *     · `isDuplicate(d1, d2)` → **false**（预览页不做去重）
 *   `onGetPreviewSetSuccess(result, taskId)`:
 *     · `mHelper.isCurrentTask(taskId) && mGalleryInfo != null` 才处理（**过期任务丢弃**）
 *     · 把 `PreviewSet` 展开成 `GalleryPreview[]`：`previewSet.getGalleryPreview(gid, i)`，i ∈ [0, size)
 *     · `mHelper.onGetPageData(taskId, result.second, 0, list)` —— **nextPage 传 0**（由 ContentHelper 自行推进）
 *   `onGetPreviewSetFailure(e, taskId)` → `isCurrentTask` 才 `onGetException(taskId, e)`
 *   `GetPreviewSetListener : EhCallback<GalleryPreviewsScene, Pair<PreviewSet,Integer>>`：
 *     onSuccess/onFailure → 取 `getScene()`（**可能为 null**）后转发；`onCancel()` **空**；`isInstance` 判类
 *   `GoToDialogHelper`:
 *     · `setDialog`：start=1、end=pages、`slider.setRange(1, pages)`、`setProgress(currentPage + 1)`
 *     · `onClick`：`page = slider.getProgress() - 1`；**`0 <= page < pages`** 才 `mHelper.goTo(page)` 并 dismiss；
 *       否则 `showTip(@string/error_out_of_range, LONG)`
 *     · `onDismiss`：两字段置 null
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`onItemClick` 的三个 null 检查失败时返回 `true`**（不是 false）—— 已消费事件，避免上层再处理。
 * 2. **过期任务丢弃**：`isCurrentTask(taskId)` 才应用结果 —— 快速翻页/重刷时旧响应必须丢弃。
 * 3. **`onDestroyView` 里只有"当前是 tip 视图"才重置 `mHasFirstRefresh`** —— 有数据时保留，
 *    下次进来不重刷；空/失败时下次要重刷。
 * 4. **`onGetPageData(..., nextPage = 0, ...)`** —— 传 0 而不是 `page + 1`（推进由 ContentHelper 负责）。
 * 5. **页码显示是 `position + 1`**（用户看第 1 页起），但 `GoTo` 内部 `page = progress - 1`（0 起）。
 * 6. **`getPageData(..., append)` 是空实现**、`isDuplicate` 恒 false —— 预览页没有"追加"和"去重"语义。
 * 7. **`hideFastScroll()`** —— 预览页隐藏快速滚动条（首页/历史页是显示的）。
 * 8. **异常只记录不上抛**（`Analytics.recordException`）—— 起 Activity 失败不应崩掉预览页。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. **`ToolbarScene` 未落地** → 宿主能力走 `PreviewsSceneHost`（起阅读器 / 显示提示 / 返回 / 取 client）。
 * 2. **`ContentLayout.ContentHelper` 已在本仓落地**（`hippo/widget/ContentLayout.ets`，7 态齐全）→
 *    本文件的 Helper **复用它的 API**（`firstRefresh` / `onGetPageData` / `onGetException` / `isCurrentTask` /
 *    `getPages` / `canGoTo` / `getPageForTop` / `goTo` / `size` / `getDataAtEx`），不重写状态机。
 *    为了保持"本文件可单测"，用 `PreviewHelperPort` 接口**限定它实际调用的 10 个方法**。
 * 3. **`EventBus.postSticky(GalleryActivityEvent)`** → 调用 host 的 `openReader(gid, page)`；
 *    页码不再走 sticky 事件，而是**显式参数**（ArkTS 无 EventBus，且显式参数更可测）。
 * 4. **`AutoGridLayoutManager(columnWidth = dimen(Settings.getThumbSizeResId()))`** →
 *    本仓 `AutoWrapLayout` 承担；这里只暴露 `columnWidthKey`（设置键）+ `columnStrategy='SUITABLE_SIZE'`。
 * 5. **`Slider`**（GoTo 对话框）→ 产出 `GoToDialogSpec`（`min=1`/`max=pages`/`progress=current+1`），
 *    由页面层用 ArkUI `Slider` 渲染。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `GalleryPreview`（`position` / `getPosition()` / `load(...)`）、`PreviewSet`（`size` / `getGalleryPreview`）、
 * `hippo/ui/layout/scene_gallery_previews.ets`、`EhEngine.getGalleryDetailUrl`、`EhClient.METHOD_GET_PREVIEW_SET`、
 * `ContentLayout.ContentHelper`。
 *
 * ── 缺口（已登记，不假装有）──────────────────────────────────────────────────
 * `Settings.getThumbSizeResId()` **本仓不存在** → 用 `SettingsKeys.THUMB_SIZE` 字符串键表达（宿主解析）。
 * `item_gallery_preview` 布局：当前只在 `item_download.ets` 里被提及，**没有独立文件** → 记 TODO(ui-scene)，本文件不渲染布局。
 */

import { GalleryInfo } from '../../client/data/GalleryInfo';
import { GalleryPreview } from '../../client/data/GalleryPreview';
import { PreviewSet } from '../../client/data/PreviewSet';

/** 上游 `KEY_GALLERY_INFO`（与 HistoryScene / GalleryDetailScene 同名同义） */
export const KEY_GALLERY_INFO: string = 'gallery_info';
/** 上游 `KEY_HAS_FIRST_REFRESH` */
export const KEY_HAS_FIRST_REFRESH: string = 'has_first_refresh';
/** 上游 `R.layout.scene_gallery_previews` */
export const LAYOUT_SCENE_GALLERY_PREVIEWS: string = 'scene_gallery_previews';
/** 上游 `R.menu.scene_gallery_previews` */
export const MENU_SCENE_GALLERY_PREVIEWS: string = 'menu/scene_gallery_previews';
/** 上游 `R.id.action_go_to` */
export const ACTION_GO_TO: string = 'action_go_to';
/** 上游 `@string/gallery_previews` */
export const TITLE_GALLERY_PREVIEWS: string = 'app.string.gallery_previews';
/** 上游 `@string/error_out_of_range` */
export const TIP_OUT_OF_RANGE: string = 'app.string.error_out_of_range';
/** 上游 `@dimen(Settings.getThumbSizeResId())` 的设置键（见「缺口」） */
export const SETTING_THUMB_SIZE_KEY: string = 'thumb_size';
/** 上游 `AutoGridLayoutManager.STRATEGY_SUITABLE_SIZE` */
export const STRATEGY_SUITABLE_SIZE: string = 'SUITABLE_SIZE';
/** 上游 `LayoutUtils.dp2pix(context, 4)`（本仓以 vp 表达；4dp ≈ 4vp） */
export const ITEM_PADDING_VP: number = 4;

/**
 * 本文件对 `ContentLayout.ContentHelper<GalleryPreview>` 的**最小依赖**
 * （只列实际调用的 10 个方法，见「平台差异」2）。
 */
export interface PreviewHelperPort {
  firstRefresh(): void;
  size(): number;
  getDataAtEx(location: number): GalleryPreview | undefined;
  getPages(): number;
  canGoTo(): boolean;
  getPageForTop(): number;
  goTo(page: number): void;
  isCurrentTask(taskId: number): boolean;
  onGetPageData(taskId: number, pages: number, nextPage: number, newData: GalleryPreview[]): void;
  onGetException(taskId: number, e: Error): void;
}

/** 本页宿主能力（见「平台差异」1/3） */
export interface PreviewsSceneHost {
  /** 上游 `startActivity(GalleryActivity)` + `postSticky(GalleryActivityEvent(page, info))` */
  openReader(galleryInfo: GalleryInfo, page: number): void;
  /** 上游 `showTip(@string/error_out_of_range, LENGTH_LONG)` */
  showTip(messageKey: string, isLong: boolean): void;
  onBackPressed(): void;
  /** 上游 `Analytics.recordException(e)` */
  recordException(e: Error): void;
}

/** 上游 `GoToDialogHelper.setDialog` 的滑块配置 */
export class GoToDialogSpec {
  /** 上游 `start` 文本固定 "1" */
  start: number = 1;
  /** 上游 `end` = pages */
  end: number = 0;
  /** `slider.setRange(1, pages)` */
  rangeMin: number = 1;
  rangeMax: number = 0;
  /** `slider.setProgress(currentPage + 1)` */
  progress: number = 1;
}

/** 上游 `GalleryPreviewHolder` 的两个控件 → 绑定数据 */
export class PreviewItemViewModel {
  imageKey: string = '';
  imageUrl: string = '';
  /** `text.setText(position + 1)` —— **1 起显示**（见「关键行为」5） */
  text: string = '';
  /** 预览项的真实页码（0 起，点击时用） */
  page: number = 0;
}

export class GalleryPreviewsScene {
  private host: PreviewsSceneHost;
  private helper: PreviewHelperPort;
  private galleryInfo: GalleryInfo | null = null;
  /** 上游 `mHasFirstRefresh` */
  private hasFirstRefresh: boolean = false;
  /** 上游"当前显示的是 tip 视图"（index == 1）→ 退出时重置首刷标记 */
  private tipViewShown: boolean = false;

  constructor(host: PreviewsSceneHost, helper: PreviewHelperPort) {
    this.host = host;
    this.helper = helper;
  }

  /** 上游 `onCreate` 的 `onInit()`：从 args 取 galleryInfo（args 为空则不设置） */
  onInit(args: Map<string, Object> | null): void {
    if (args === null) {
      return;
    }
    const info: Object | undefined = args.get(KEY_GALLERY_INFO);
    this.galleryInfo = info === undefined ? null : (info as GalleryInfo);
  }

  /** 上游 `onSaveInstanceState` **整段注释掉** → 本实现同样不保存（不提供 saveState）。 */

  /**
   * 上游 `onCreateView3(...)` 的后半段：
   * ① 建 helper ② **首次才 `firstRefresh()`**（见「关键行为」3 的反面）
   */
  onCreateView(): void {
    // 上游：if (!mHasFirstRefresh) { mHasFirstRefresh = true; mHelper.firstRefresh(); }
    if (!this.hasFirstRefresh) {
      this.hasFirstRefresh = true;
      this.helper.firstRefresh();
    }
  }

  /**
   * 上游 `onDestroyView()`：
   * **只有当前显示 tip 视图时才重置 `mHasFirstRefresh`**（见「关键行为」3）。
   * @param shownViewIndex `helper.getShownViewIndex()`（本实现由 `tipViewShown` 表达）
   */
  onDestroyView(isTipViewShown: boolean): void {
    if (isTipViewShown) {
      this.hasFirstRefresh = false;
    }
    this.tipViewShown = isTipViewShown;
  }

  /** 首次刷新的标记（测试观测） */
  hasFirstRefreshed(): boolean {
    return this.hasFirstRefresh;
  }

  /** 上游 `getMenuResId()` */
  getMenuResId(): string {
    return MENU_SCENE_GALLERY_PREVIEWS;
  }

  /**
   * 上游 `onMenuItemClick(item)` 的 `action_go_to` 分支：
   * `pages > 0 && canGoTo()` 才产出 GoTo 描述；否则返回 null（**不弹**）。
   */
  buildGoToDialog(): GoToDialogSpec | null {
    const pages: number = this.helper.getPages();
    // 上游：if (pages > 0 && mHelper.canGoTo())
    if (!(pages > 0 && this.helper.canGoTo())) {
      return null;
    }
    const spec: GoToDialogSpec = new GoToDialogSpec();
    spec.start = 1;
    spec.end = pages;
    spec.rangeMin = 1;
    spec.rangeMax = pages;
    // 上游：mSlider.setProgress(mCurrentPage + 1)
    spec.progress = this.helper.getPageForTop() + 1;
    return spec;
  }

  /**
   * 上游 `GoToDialogHelper.onClick`：
   * `page = progress - 1`；**`0 <= page < pages`** 才 `goTo` 并关闭；否则 `showTip(error_out_of_range)`
   * @returns true = 已跳转（对话框应关闭）；false = 越界（已提示，对话框保持）
   */
  confirmGoTo(progress: number): boolean {
    const pages: number = this.helper.getPages();
    const page: number = progress - 1;
    if (page >= 0 && page < pages) {
      this.helper.goTo(page);
      return true;
    }
    // 上游：showTip(R.string.error_out_of_range, LENGTH_LONG)
    this.host.showTip(TIP_OUT_OF_RANGE, true);
    return false;
  }

  /** 上游 `onNavigationClick` */
  onNavigationClick(): void {
    this.host.onBackPressed();
  }

  /**
   * 上游 `onItemClick(position)`：
   * ① 三处 null 检查失败 → **返回 true**（已消费，见「关键行为」1）
   * ② `getDataAtEx` 为 undefined → 也返回 true
   * ③ 起阅读器并定位到该页；异常只记录
   */
  onItemClick(position: number): boolean {
    if (this.helper === null || this.galleryInfo === null) {
      return true;
    }
    const preview: GalleryPreview | undefined = this.helper.getDataAtEx(position);
    if (preview === undefined || preview === null) {
      return true;
    }
    try {
      // 上游：startActivity(GalleryActivity ACTION_EH) + postSticky(GalleryActivityEvent(p.getPosition(), info))
      this.host.openReader(this.galleryInfo, preview.getPosition());
    } catch (e) {
      // 上游：catch (RuntimeException e) { Analytics.recordException(e); } —— **不上抛**
      this.host.recordException(e as Error);
    }
    return true;
  }

  /** 上游 `GalleryPreviewAdapter.getItemCount()` → `helper.size()` */
  getItemCount(): number {
    return this.helper.size();
  }

  /** 上游 `onBindViewHolder`：`preview.load(image)` + 文本 `position + 1` */
  bindItem(position: number): PreviewItemViewModel | null {
    const preview: GalleryPreview | undefined = this.helper.getDataAtEx(position);
    if (preview === undefined || preview === null) {
      return null;
    }
    const vm: PreviewItemViewModel = new PreviewItemViewModel();
    vm.imageKey = preview.imageKey;
    vm.imageUrl = preview.imageUrl;
    vm.page = preview.getPosition();
    vm.text = (preview.getPosition() + 1).toString();
    return vm;
  }

  /** 上游 `GalleryPreviewHelper.getPageData(...)` 的参数装配（**不含实际网络**） */
  buildPageRequest(page: number): PreviewPageRequest {
    const req: PreviewPageRequest = new PreviewPageRequest();
    req.page = page;
    req.method = 'GET_PREVIEW_SET';
    req.galleryInfo = this.galleryInfo;
    // 上游：url = EhUrl.getGalleryDetailUrl(gid, token, page, false) —— 最后参数恒 false
    req.urlArgs = new PreviewUrlArgs(
      this.galleryInfo === null ? -1 : this.galleryInfo.gid,
      this.galleryInfo === null ? '' : this.galleryInfo.token,
      page, false);
    return req;
  }

  /** 上游 `onGetPreviewSetSuccess(result, taskId)`：展开 PreviewSet → 数组并交给 helper */
  onGetPreviewSetSuccess(previewSet: PreviewSet, pages: number, taskId: number): boolean {
    // 上游：mHelper != null && mHelper.isCurrentTask(taskId) && mGalleryInfo != null
    if (!this.helper.isCurrentTask(taskId) || this.galleryInfo === null) {
      return false;
    }
    const size: number = previewSet.size();
    const list: GalleryPreview[] = [];
    for (let i = 0; i < size; i++) {
      list.push(previewSet.getGalleryPreview(this.galleryInfo.gid, i));
    }
    // 上游：mHelper.onGetPageData(taskId, result.second, **0**, list) —— nextPage 传 0（见「关键行为」4）
    this.helper.onGetPageData(taskId, pages, 0, list);
    return true;
  }

  /** 上游 `onGetPreviewSetFailure(e, taskId)`：仅当前任务才登记异常 */
  onGetPreviewSetFailure(e: Error, taskId: number): boolean {
    if (!this.helper.isCurrentTask(taskId)) {
      return false;
    }
    this.helper.onGetException(taskId, e);
    return true;
  }

  /** 上游 `GalleryPreviewHelper.isDuplicate(d1, d2)` → **恒 false**（预览页不去重） */
  isDuplicate(): boolean {
    return false;
  }
}

/** 上游 `EhUrl.getGalleryDetailUrl(gid, token, page, nl)` 的入参快照（便于断言 `nl=false`） */
export class PreviewUrlArgs {
  readonly gid: number;
  readonly token: string;
  readonly page: number;
  /** 上游恒传 `false`（见「关键行为」外的实现细节） */
  readonly nl: boolean;

  constructor(gid: number, token: string, page: number, nl: boolean) {
    this.gid = gid;
    this.token = token;
    this.page = page;
    this.nl = nl;
  }
}

/** 一次分页请求的描述（方法名 + 入参），网络执行由宿主/net-parse 负责 */
export class PreviewPageRequest {
  page: number = 0;
  method: string = '';
  galleryInfo: GalleryInfo | null = null;
  urlArgs: PreviewUrlArgs | null = null;
}
