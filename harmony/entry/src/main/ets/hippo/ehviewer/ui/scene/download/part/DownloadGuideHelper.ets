/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/download/part/DownloadGuideHelper.kt
 *       （inventory S0226，上游 132 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/part/DownloadGuideHelper.ets
 *
 * 背景：**下载页新手引导**（两步 show-case 气泡）：
 *   ① `guide_download_thumb_*` —— 指向第一条下载项的**缩略图**
 *   ② `guide_download_labels_*` —— 指向屏幕**上三分之一处**（提示右侧抽屉里有标签）
 * 两步都是"一次性的"（关掉即把对应 Settings 开关置 false），并且**串联**：第一步关掉后才进第二步。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class DownloadGuideHelper(private val mHost: Host)`
 * `interface Host`：`activity2: MainActivity?` / `recyclerView: MyEasyRecyclerView?` /
 *   `layoutManager: AutoStaggeredGridLayoutManager?` / `openDrawer(gravity: Int)`
 * 字段：`mShowcaseView: ShowcaseView?`
 * `isShowing` **getter** → `mShowcaseView != null`（**不是字段**，是即时计算）
 * `destroy()`：`mShowcaseView != null` → `removeFromParent` + 置 null
 * `guide()`：
 *   · **`Settings.getGuideDownloadThumb() && recyclerView != null`** →
 *     `getViewTreeObserver().addOnGlobalLayoutListener { ... }`
 *     · 回调里：**再判一次** `getGuideDownloadThumb()` → `guideDownloadThumb()`
 *     · 然后 `current = mHost.recyclerView`（**重新取**）；非 null → `removeOnGlobalLayoutListener(..., this)`
 *   · **否则** → 直接 `guideDownloadLabels()`
 * `guideDownloadThumb()`（**四条前置，任一不满足就跳第二步**）：
 *   ① `activity == null || !Settings.getGuideDownloadThumb() || layoutManager == null || recyclerView == null`
 *      → `guideDownloadLabels(); return`
 *   ② `position = layoutManager.findFirstCompletelyVisibleItemPositions(null)[0]`；**`position < 0`** → 跳第二步
 *   ③ `holder = recyclerView.findViewHolderForAdapterPosition(position)`；**null** → 跳第二步
 *   ④ 建 ShowcaseView：target = `ViewTarget((holder as DownloadHolder).thumb)`、
 *      **`blockAllTouches()`**、title/text、`replaceEndButton(button_guide)`、
 *      监听 `onShowcaseViewDidHide`：
 *      **`mShowcaseView = null` → `removeFromParent(showcaseView)` → `putGuideDownloadThumb(false)`
 *        → `guideDownloadLabels()`**（★ 串联的交接点）
 * `guideDownloadLabels()`：
 *   ① **`activity == null || !Settings.getGuideDownloadLabels()` → return**（**不抛错、不 continuation**）
 *   ② `display.getSize(point)` → target = `PointTarget(point.x, point.y / 3)`（**屏幕宽度、高度的 1/3**）
 *   ③ 建 ShowcaseView；监听 `onShowcaseViewDidHide`：
 *      `mShowcaseView = null` → `removeFromParent` → **`puttGuideDownloadLabels(false)`**（★ 见「关键行为」1）
 *        → **`mHost.openDrawer(Gravity.RIGHT)`**（★ 第二步结束时自动拉开右侧抽屉）
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. ★ **第二步用的是 `puttGuideDownloadLabels`（三个 t）** —— 上游 typo，但**它确实存在**（`Settings.puttGuideDownloadLabels`）。
 *    如果 ArkTS 侧写成 `putGuideDownloadLabels`，编译能过（我们自造的方法），但**行为可能不同**
 *    （上游另有一个正确的 `putGuideDownloadLabels`，两者是否同义需按 `Settings` 实现确认）。
 *    本实现**保留三个 t 的语义**：`GuideSettings.puttGuideDownloadLabels`，并另提供
 *    `putGuideDownloadLabels` 仅用于对比测试。**不要合并成一个。**
 * 2. ★ **两步是串联的**：第一步 hide → 关开关 → **立刻**进第二步（不是等下次进入页面）。
 * 3. ★ **第二步结束时 `openDrawer(Gravity.RIGHT)`** —— 引导的最后一步会主动拉开抽屉（教学闭环）。
 * 4. **`guide()` 用 `OnGlobalLayoutListener` 等布局完成**，而不是立刻 show ——
 *    因为要 `findViewHolderForAdapterPosition`（列表还没布局时取不到 holder）。
 *    回调里**重新取 `recyclerView`**（可能已被销毁），并**主动移除监听**（只跑一次）。
 * 5. **`isShowing` 是 getter 不是字段** —— 每次读都算。
 * 6. **每条前置失败都"降级到下一步"而不是"放弃"** —— `guideDownloadThumb` 的四条前置全部走 `guideDownloadLabels()`。
 *    只有 `guideDownloadLabels` 自己的前置失败才是真 `return`。
 * 7. **`destroy()` 只移除视图不关开关** —— 用户以后再进还会看到（若开关仍为 true）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `ShowcaseView`（第三方库，Android 专属）→ ArkUI 用 `Popup`/`bindPopup` 或自定义覆盖层。
 *    本文件把 ShowcaseView 抽象成 `GuideStep`（纯数据：target/文案/是否拦截触摸），
 *    **渲染由页面层负责**。注意 `FavoritesScene.ets` 里有同名 `ShowcaseView` 引用（`ui-widget` 的实现），
 *    但那是"收藏页引导"，与本文件的下载页引导**不是同一处**，不要复用。
 * 2. `ViewTreeObserver` → 宿主 `whenLaidOut(callback)`（ArkUI 用 `onAreaChange`/`onAppear` 等价）。
 * 3. `AutoStaggeredGridLayoutManager.findFirstCompletelyVisibleItemPositions(null)[0]` →
 *    宿主 `findFirstCompletelyVisiblePosition()`（返回 -1 表示没有）。
 * 4. `findViewHolderForAdapterPosition(position)` → 宿主 `getItemThumbAnchor(position)`（null = 取不到）。
 * 5. `Settings.getGuideDownloadThumb/putGuideDownloadThumb/getGuideDownloadLabels/puttGuideDownloadLabels`
 *    **本仓 `Settings` 全缺** → `GuideSettings` 注入（见「缺口」）。
 * 6. `Display.getSize` → 宿主 `getScreenSize()`（宽, 高）。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `DownloadHolder`（`download/part/DownloadAdapterContracts.ets`）、
 * 四个字符串键 `guide_download_thumb_title/_text` / `guide_download_labels_title/_text`（都在）。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * 五个 `Settings` 方法在本仓不存在（已 grep 确认）→ `GuideSettings` 接口；
 * 补进 `Settings` 是 core-runtime 的活（与 `S0176 Settings.ets` 同批）。
 */

/** 上游四个字符串键 */
export const STR_THUMB_TITLE: string = 'app.string.guide_download_thumb_title';
export const STR_THUMB_TEXT: string = 'app.string.guide_download_thumb_text';
export const STR_LABELS_TITLE: string = 'app.string.guide_download_labels_title';
export const STR_LABELS_TEXT: string = 'app.string.guide_download_labels_text';
/** 上游 `R.style.Guide` / `R.layout.button_guide` */
export const STYLE_GUIDE: string = 'Guide';
export const LAYOUT_BUTTON_GUIDE: string = 'button_guide';
/** 上游 `Gravity.RIGHT`（第二步结束后拉开右侧抽屉） */
export const DRAWER_GRAVITY_RIGHT: number = 5;

/** 引导步骤（ShowcaseView 的纯数据对位） */
export class GuideStep {
  /** `thumb` = 指向列表项缩略图；`point` = 指向屏幕坐标 */
  kind: string = '';
  /** `kind == 'point'` 时的坐标 */
  x: number = 0;
  y: number = 0;
  /** `kind == 'thumb'` 时的列表位置 */
  position: number = -1;
  titleKey: string = '';
  textKey: string = '';
  /** `blockAllTouches()` —— 上游两步都设了 true */
  blockAllTouches: boolean = true;
  endButtonLayout: string = LAYOUT_BUTTON_GUIDE;
  style: string = STYLE_GUIDE;
}

export const STEP_THUMB: string = 'thumb';
export const STEP_POINT: string = 'point';

/** 引导开关（见「缺口」：本仓 Settings 缺这五个方法） */
export interface GuideSettings {
  getGuideDownloadThumb(): boolean;
  putGuideDownloadThumb(v: boolean): void;
  getGuideDownloadLabels(): boolean;
  /** ★ 上游 typo：三个 t（见「关键行为」1） */
  puttGuideDownloadLabels(v: boolean): void;
}

/** 宿主能力 */
export interface GuideHost {
  /** 上游 `mHost.activity2` */
  hasActivity(): boolean;
  /** 上游 `mHost.recyclerView`（可能为 null = 已销毁） */
  hasRecyclerView(): boolean;
  /** 上游 `mHost.layoutManager` */
  hasLayoutManager(): boolean;
  /** 上游 `recyclerView.getViewTreeObserver().addOnGlobalLayoutListener(...)` */
  whenLaidOut(callback: () => void): void;
  /** 主动移除布局监听（上游 `removeOnGlobalLayoutListener`） */
  removeLayoutListener(): void;
  /** 上游 `findFirstCompletelyVisibleItemPositions(null)[0]`；-1 = 没有 */
  findFirstCompletelyVisiblePosition(): number;
  /** 上游 `findViewHolderForAdapterPosition(position)` 且能取到 `.thumb`；null = 取不到 */
  getItemThumbAnchor(position: number): Object | null;
  /** 上游 `display.getSize(point)` → (宽, 高) */
  getScreenWidth(): number;
  getScreenHeight(): number;
  /** 上游 `mHost.openDrawer(Gravity.RIGHT)` */
  openDrawer(gravity: number): void;
  /** 页面层"显示一个引导气泡" */
  showStep(step: GuideStep): void;
  /** 上游 `ViewUtils.removeFromParent(showcaseView)` */
  removeStepView(): void;
  /** 上游 `activity.getString(key)` */
  resolveString(key: string): string;
}

export class DownloadGuideHelper {
  private host: GuideHost;
  private settings: GuideSettings;
  /** 上游 `mShowcaseView: ShowcaseView?`（本实现只记"是否有活跃步骤"） */
  private activeStep: GuideStep | null = null;

  constructor(host: GuideHost, settings: GuideSettings) {
    this.host = host;
    this.settings = settings;
  }

  /** 上游 `isShowing` **getter**（见「关键行为」5）：每次读都算 */
  isShowing(): boolean {
    return this.activeStep !== null;
  }

  /** 上游 `destroy()`：移除视图并置 null，**不关开关**（见「关键行为」7） */
  destroy(): void {
    if (this.activeStep !== null) {
      this.host.removeStepView();
      this.activeStep = null;
    }
  }

  /**
   * 上游 `guide()`：
   * 缩略图引导开关为真且有 recyclerView → **等布局完成**再进；否则直接进标签引导。
   */
  guide(): void {
    if (this.settings.getGuideDownloadThumb() && this.host.hasRecyclerView()) {
      // 上游：addOnGlobalLayoutListener —— 回调里再判一次开关，并主动移除监听
      this.host.whenLaidOut((): void => {
        if (this.settings.getGuideDownloadThumb()) {
          this.guideDownloadThumb();
        }
        // 上游：current = mHost.recyclerView；非 null 才移除监听
        if (this.host.hasRecyclerView()) {
          this.host.removeLayoutListener();
        }
      });
      return;
    }
    this.guideDownloadLabels();
  }

  /**
   * 上游 `guideDownloadThumb()`：**四条前置，任一不满足都降级到第二步**（见「关键行为」6）。
   * @returns 是否真的弹出了第一步
   */
  guideDownloadThumb(): boolean {
    // ① 四条前置
    if (!this.host.hasActivity() || !this.settings.getGuideDownloadThumb()
      || !this.host.hasLayoutManager() || !this.host.hasRecyclerView()) {
      this.guideDownloadLabels();
      return false;
    }
    // ② 第一个完全可见的位置
    const position: number = this.host.findFirstCompletelyVisiblePosition();
    if (position < 0) {
      this.guideDownloadLabels();
      return false;
    }
    // ③ 取 holder
    const anchor: Object | null = this.host.getItemThumbAnchor(position);
    if (anchor === null) {
      this.guideDownloadLabels();
      return false;
    }
    // ④ 建步骤
    const step: GuideStep = new GuideStep();
    step.kind = STEP_THUMB;
    step.position = position;
    step.titleKey = STR_THUMB_TITLE;
    step.textKey = STR_THUMB_TEXT;
    step.blockAllTouches = true;
    this.activeStep = step;
    this.host.showStep(step);
    return true;
  }

  /**
   * 上游第一步的 `onShowcaseViewDidHide`：
   * **置 null → 移除 → 关开关 → ★串联进第二步**。
   */
  onThumbStepHidden(): void {
    this.activeStep = null;
    this.host.removeStepView();
    this.settings.putGuideDownloadThumb(false);
    // ★ 串联（见「关键行为」2）
    this.guideDownloadLabels();
  }

  /**
   * 上游 `guideDownloadLabels()`：**这一层的失败是真 return**（不降级）。
   * 结束时的 `onShowcaseViewDidHide`：置 null → 移除 → **`puttGuideDownloadLabels(false)`**
   * → **`openDrawer(RIGHT)`**。
   * @returns 是否真的弹出了第二步
   */
  guideDownloadLabels(): boolean {
    if (!this.host.hasActivity() || !this.settings.getGuideDownloadLabels()) {
      return false;
    }
    const step: GuideStep = new GuideStep();
    step.kind = STEP_POINT;
    // 上游：PointTarget(point.x, point.y / 3)
    step.x = this.host.getScreenWidth();
    step.y = Math.floor(this.host.getScreenHeight() / 3);
    step.titleKey = STR_LABELS_TITLE;
    step.textKey = STR_LABELS_TEXT;
    step.blockAllTouches = true;
    this.activeStep = step;
    this.host.showStep(step);
    return true;
  }

  /**
   * 上游第二步的 `onShowcaseViewDidHide`：
   * 置 null → 移除 → **`puttGuideDownloadLabels`（三 t）** → **`openDrawer(RIGHT)`**。
   */
  onLabelsStepHidden(): void {
    this.activeStep = null;
    this.host.removeStepView();
    // ★ 三 t 的 typo 照搬（见「关键行为」1）
    this.settings.puttGuideDownloadLabels(false);
    this.host.openDrawer(DRAWER_GRAVITY_RIGHT);
  }

  /** 当前步骤（测试观测） */
  getActiveStep(): GuideStep | null {
    return this.activeStep;
  }
}
