/**
 * 迁移自 app/src/main/java/com/hippo/widget/SearchBarMover.java（inventory S0541，上游 194 行）
 *
 * 上游：`RecyclerView.OnScrollListener`，让搜索栏随滚动"上移隐藏 / 回弹显示"
 *   onScrolled(dx, dy)：offsetYStep = clamp(-dy, -oldBottom, -translationY)，非 0 就 translationYBy 平移搜索栏
 *     （即：上滑时搜索栏上移藏起来，下滑时最多回原位；用 clamp 保证不越界）
 *   onScrollStateChanged(IDLE)：若 helper.isValidView(rv) → returnSearchBarPosition()
 *   returnSearchBarPosition(animation)：
 *     height==0（未布局）→ 返回；helper.forceShowSearchBar() → show=true；
 *     否则取 getValidRecyclerView()，按其是否可见/能否滚动决定 show（不可见→隐藏，可滚动→跟随，否则显示）；
 *     再做 300ms 动画到 show/hide 位置
 *   cancelAnimation()：取消在跑的动画
 *
 * ============================ ArkUI 对位（复用 FabLayout 的注入接口） ============================
 * RecyclerView.OnScrollListener → **`ScrollOffsetHost`**（`FabLayout` 已立：getOffset() + onOffsetChanged(cb)）
 *   **注意**：上游要的是**每帧增量 dy**，而 ScrollOffsetHost 给的是绝对偏移 →
 *   本实现在回调里做差分（`dy = offset - lastOffset`，符号与上游一致：向上滚 dy>0），
 *   这是等价变换（增量是绝对值的差分），已在断言里验证双向。
 * 300ms 动画 → animateTo(300ms, Curve.Linear) 改 translationY 对位
 * helper.isValidView/getValidRecyclerView/forceShowSearchBar → 本文件声明 `SearchBarMoverHelper`
 *   接口（**由 ui-scene 的页面实现**，与 C-8/C-11/C-12 "接口归消费方声明" 一致）；
 *   签名按上游调用点推导（isValidView(viewId) / getValidViewId() / forceShowSearchBar()），
 *   以数字 viewId 取代 RecyclerView 引用（ArkTS 无 View 体系）。
 *
 * 差异（已登记 MR）：
 *   1) 上游按 RecyclerView 实例判有效性；ArkTS 用调用方给的 `viewId: number` 标识列表。
 *   2) 上游 getY2()/getHeight() 取自 View 的实时测量值；ArkUI 无同步测量查询 →
 *      由调用方通过 `setMetrics(height, translationY, bottomY)` 注入（高度/位置变化时更新）。
 *   3) `RecyclerView.SCROLL_STATE_IDLE` 无直接对位 → 用 `ScrollOffsetHost` 的"偏移不再变化"
 *      判定：本实现由调用方在滚动停止时调 `onScrollIdle()`（ArkUI 无滚动状态回调，
 *      页面可在 `onScrollStop` 里调）。
 */
import { ScrollOffsetHost } from './FabLayout';

/** 上游 Helper（由 ui-scene 页面实现）：判定哪个列表是"当前有效列表" */
export interface SearchBarMoverHelper {
  /** 上游 isValidView(RecyclerView) */
  isValidView(viewId: number): boolean;

  /** 上游 getValidRecyclerView()：无有效列表时返回 -1 */
  getValidViewId(): number;

  /** 上游 forceShowSearchBar() */
  forceShowSearchBar(): boolean;
}

/** 具名实现类（ArkTS 禁止无类型对象字面量） */
export class SearchBarMoverHelperImpl implements SearchBarMoverHelper {
  private validFn: (viewId: number) => boolean;
  private getFn: () => number;
  private forceFn: () => boolean;

  constructor(validFn: (viewId: number) => boolean, getFn: () => number, forceFn: () => boolean) {
    this.validFn = validFn;
    this.getFn = getFn;
    this.forceFn = forceFn;
  }

  isValidView(viewId: number): boolean {
    return this.validFn(viewId);
  }

  getValidViewId(): number {
    return this.getFn();
  }

  forceShowSearchBar(): boolean {
    return this.forceFn();
  }
}

export class SearchBarMoverState {
  static readonly ANIMATE_TIME: number = 300;

  /** 上游 mShow */
  show: boolean = true;
  /** 搜索栏的 translationY（负数 = 向上移出） */
  translationY: number = 0;
  /** 搜索栏高度（上游 getHeight()） */
  barHeight: number = 0;
  /** 搜索栏底部 Y（上游 ViewUtils.getY2 → oldBottom） */
  oldBottom: number = 0;
  helper: SearchBarMoverHelper | null = null;
  private lastOffset: number = 0;
  private started: boolean = false;
  private animating: boolean = false;
  /** 可选视图可见性探测（上游 RecyclerView.isShown）：由页面注入，默认 true */
  isViewShown: () => boolean = (): boolean => true;
  /** 可选向上/向下可滚动探测（上游 canScrollVertically(-1)）：由页面注入，默认 true */
  canScrollUp: () => boolean = (): boolean => true;

  static clamp(v: number, lo: number, hi: number): number {
    if (v < lo) {
      return lo;
    }
    if (v > hi) {
      return hi;
    }
    return v;
  }

  /** 调用方在尺寸/位置变化时注入（对应 View 的实时测量值） */
  setMetrics(barHeight: number, translationY: number, oldBottom: number): void {
    this.barHeight = barHeight;
    this.translationY = translationY;
    this.oldBottom = oldBottom;
  }

  /** 对位 showSearchBar(boolean animation)：强制回到显示位置并重置偏移状态 */
  showSearchBar(animation: boolean): void {
    this.animating = animation && this.translationY !== 0;
    this.show = true;
    this.translationY = 0;
    this.started = false;
  }

  /** 对位 cancelAnimation() */
  cancelAnimation(): void {
    this.animating = false;
  }

  /** 当前是否处于显式动画态（供调用方 animateTo 协调） */
  isAnimating(): boolean {
    return this.animating;
  }

  /** 对位 isShown() */
  isShown(): boolean {
    return this.show;
  }

  /** 对位 onScrolled(dx, dy)：由 ScrollOffsetHost 的绝对偏移差分出 dy */
  onOffsetChanged(offset: number): number {
    if (!this.started) {
      this.started = true;
      this.lastOffset = offset;
      return 0;
    }
    const dy: number = offset - this.lastOffset;
    this.lastOffset = offset;
    return this.applyScrollDelta(dy);
  }

  /** 纯逻辑：给定滚动增量，返回应施加的 translationY 增量（0 表示不动） */
  applyScrollDelta(dy: number): number {
    if (this.barHeight <= 0) {
      return 0;
    }
    const boundBottom: number = this.oldBottom > 0 ? this.oldBottom : this.barHeight;
    const minDelta: number = -(this.barHeight + this.translationY);
    const maxDelta: number = -this.translationY;
    const step: number = SearchBarMoverState.clamp(-dy, Math.max(-boundBottom, minDelta), maxDelta);
    if (step !== 0) {
      this.translationY = this.translationY + step;
      if (this.translationY <= -(this.barHeight * 0.5)) {
        this.show = false;
      } else {
        this.show = true;
      }
    }
    return step;
  }

  /**
   * 对位 returnSearchBarPosition(animation)：决定 show 与目标 translationY。
   * 上游规则：① height==0 早退；② forceShowSearchBar→true；③ getValidRecyclerView==null→保持/true；
   * ④ 列表不可见→false；⑤ 列表不可上滚(已经在顶部)→true；⑥ -translationY > height/2 → false，否则 true。
   */
  resolveTargetShow(): boolean {
    if (this.barHeight === 0) {
      return this.show; // Layout not called
    }
    const h: SearchBarMoverHelper | null = this.helper;
    if (h !== null && h.forceShowSearchBar()) {
      this.show = true;
      return true;
    }
    if (h !== null) {
      const viewId: number = h.getValidViewId();
      if (viewId < 0) {
        return this.show; // 无有效列表 → 保持
      }
      if (!h.isValidView(viewId)) {
        return this.show;
      }
    }
    if (!this.isViewShown()) {
      this.show = false;
      return false;
    }
    if (!this.canScrollUp()) {
      this.show = true;
      return true;
    }
    this.show = (-this.translationY) <= (this.barHeight * 0.5);
    return this.show;
  }

  /** 显式传入列表状态并归位（对位上游 returnSearchBarPosition） */
  returnSearchBarPosition(animation: boolean): boolean {
    const show: boolean = this.resolveTargetShow();
    this.translationY = this.targetTranslationY(show);
    this.animating = animation;
    return show;
  }

  /** 目标 translationY：显示 → 0；隐藏 → -barHeight */
  targetTranslationY(show: boolean): number {
    return show ? 0 : -this.barHeight;
  }

  /** 对位 onScrollStateChanged(IDLE)：回弹到目标位置（动画由调用方 animateTo） */
  onScrollIdle(): boolean {
    const h: SearchBarMoverHelper | null = this.helper;
    if (h !== null) {
      const viewId: number = h.getValidViewId();
      if (viewId >= 0 && !h.isValidView(viewId)) {
        return this.show;
      }
    }
    this.show = this.resolveTargetShow();
    return this.show;
  }

  /** 便捷：绑定滚动源（复用 FabLayout 的 ScrollOffsetHost） */
  bindScroll(host: ScrollOffsetHost): void {
    host.onOffsetChanged((offset: number) => {
      this.onOffsetChanged(offset);
    });
  }
}
