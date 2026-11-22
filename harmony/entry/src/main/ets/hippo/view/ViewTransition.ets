/**
 * 迁移自 app/src/main/java/com/hippo/view/ViewTransition.java（inventory S0509，上游 122 行）
 *
 * 上游是"多视图交叉淡入淡出"的小状态机：
 *   ANIMATE_TIME = 300ms
 *   构造：views.length < 2 抛 IllegalStateException；含 null 抛；然后 showView(0, false)
 *   showView(index, animation)：
 *     越界 → IndexOutOfBoundsException
 *     同一 index → 返回 false（不做事）
 *     否则：记住 oldShowen，取消未完成动画；animation=true 时把"既非 old 也非 new"的视图 alpha=0 且 GONE，
 *           然后对 old 做 alpha→0（结束后 GONE）、对 new 做 alpha 0→1；false 时直接摆好 alpha/可见性；
 *           最后回调 OnShowViewListener.onShowView(old, new)，返回 true
 *   交叉淡入用的是 ObjectAnimator 默认插值器（AccelerateDecelerate）→ ArkUI `Curve.EaseInOut`。
 *
 * ArkUI 对位：
 *   View[]           → 槽位数量 count + `@BuilderParam slot: (index: number) => void`
 *   交叉淡入          → `animateTo({duration: 300, curve: Curve.EaseInOut}, ...)` 改两个槽位的 opacity
 *   动画结束置 GONE   → AnimateParam.onFinish 里把旧槽位 visibility 设为 None
 *   取消未完成动画    → animateTo 会打断同属性上正在跑的隐式动画（等价 cancel），并用 onFinish 里的代数校验防串台
 *   监听器            → OnShowViewListener（具名实现类，ArkTS 禁止对象字面量）
 *
 * 差异：
 *   1) 上游可传任意数量 View；ArkUI 组件无法接收变长 builder 列表，故用 (index)=>void 的 slot 回调，
 *      槽位数量由 controller 的 count 决定（调用方自己按 index 分支渲染）。
 *   2) 上游 hiddenView.setVisibility(GONE) 在 onAnimationEnd 同步执行；ArkUI 在 onFinish 回调里执行，语义相同。
 */
export interface OnShowViewListener {
  /** 上游 onShowView(View hiddenView, View shownView) —— 此处用槽位下标表达 */
  onShowView(hiddenIndex: number, shownIndex: number): void;
}

/** 具名实现类：ArkTS 禁止无类型对象字面量 */
export class OnShowViewListenerImpl implements OnShowViewListener {
  private fn: (hiddenIndex: number, shownIndex: number) => void;

  constructor(fn: (hiddenIndex: number, shownIndex: number) => void) {
    this.fn = fn;
  }

  onShowView(hiddenIndex: number, shownIndex: number): void {
    this.fn(hiddenIndex, shownIndex);
  }
}

/** 组件向控制器回吐的宿主能力 */
export interface ViewTransitionHost {
  applyTransition(oldIndex: number, newIndex: number, animation: boolean): void;
}

export class ViewTransitionHostBridge implements ViewTransitionHost {
  private fn: (oldIndex: number, newIndex: number, animation: boolean) => void;

  constructor(fn: (oldIndex: number, newIndex: number, animation: boolean) => void) {
    this.fn = fn;
  }

  applyTransition(oldIndex: number, newIndex: number, animation: boolean): void {
    this.fn(oldIndex, newIndex, animation);
  }
}

/** 上游 ViewTransition 的状态机（与 View 无关，可独立测试） */
export class ViewTransitionController {
  static readonly ANIMATE_TIME: number = 300;

  readonly count: number;
  shownView: number = -1;
  private listener: OnShowViewListener | null = null;
  private host: ViewTransitionHost | null = null;

  constructor(count: number) {
    if (count < 2) {
      throw new Error('You must pass view to ViewTransition');
    }
    this.count = count;
    this.showView(0, false);
  }

  attach(host: ViewTransitionHost): void {
    this.host = host;
  }

  detach(): void {
    this.host = null;
  }

  setOnShowViewListener(listener: OnShowViewListener | null): void {
    this.listener = listener;
  }

  getShownViewIndex(): number {
    return this.shownView;
  }

  showView(shownView: number, animation: boolean = true): boolean {
    if (shownView >= this.count || shownView < 0) {
      throw new Error(`Only ${this.count} view(s) in the ViewTransition, but attempt to show ${shownView}`);
    }
    if (this.shownView !== shownView) {
      const oldShownView: number = this.shownView;
      this.shownView = shownView;
      if (this.host !== null) {
        this.host.applyTransition(oldShownView, shownView, animation);
      }
      if (this.listener !== null) {
        this.listener.onShowView(oldShownView, shownView);
      }
      return true;
    }
    return false;
  }
}

@Component
export struct ViewTransition {
  controller: ViewTransitionController = new ViewTransitionController(2);
  /** 槽位渲染回调：调用方按 index 返回该槽位内容 */
  @BuilderParam slot: (index: number) => void = this.emptySlot;

  @State shownIndex: number = 0;
  @State oldIndex: number = -1;
  @State shownAlpha: number = 1.0;
  @State oldAlpha: number = 0.0;
  @State oldVisible: boolean = false;
  @State indices: number[] = [];
  private generation: number = 0;

  @Builder
  emptySlot(index: number): void {
  }

  aboutToAppear(): void {
    const arr: number[] = [];
    for (let i = 0; i < this.controller.count; i++) {
      arr.push(i);
    }
    this.indices = arr;
    this.shownIndex = this.controller.getShownViewIndex();
    this.controller.attach(new ViewTransitionHostBridge((oldIndex: number, newIndex: number, animation: boolean) => {
      this.runTransition(oldIndex, newIndex, animation);
    }));
  }

  aboutToDisappear(): void {
    this.controller.detach();
  }

  private runTransition(oldIndex: number, newIndex: number, animation: boolean): void {
    this.generation++;
    const gen: number = this.generation;
    if (!animation) {
      this.oldVisible = false;
      this.oldAlpha = 0.0;
      this.oldIndex = oldIndex;
      this.shownIndex = newIndex;
      this.shownAlpha = 1.0;
      return;
    }
    // 上游：其余槽位 alpha=0 + GONE；老槽位淡出、新槽位淡入（交叉淡入 300ms，AccelerateDecelerate ≈ Curve.EaseInOut）
    this.oldIndex = oldIndex;
    this.oldVisible = true;
    this.oldAlpha = 1.0;
    this.shownIndex = newIndex;
    this.shownAlpha = 0.0;
    animateTo({
      duration: ViewTransitionController.ANIMATE_TIME,
      curve: Curve.EaseInOut,
      onFinish: () => {
        if (gen !== this.generation) {
          return; // 被新的切换打断，忽略（对位上游 Animator.cancel 后的旧回调不生效）
        }
        // 对位 hiddenView.setVisibility(View.GONE)，并复位 alpha
        this.oldVisible = false;
        this.oldAlpha = 0.0;
        this.shownAlpha = 1.0;
      }
    }, () => {
      this.oldAlpha = 0.0;
      this.shownAlpha = 1.0;
    });
  }

  build() {
    Stack() {
      ForEach(this.indices, (i: number) => {
        Column() {
          this.slot(i)
        }
        .width('100%')
        .height('100%')
        .opacity(i === this.shownIndex ? this.shownAlpha : (i === this.oldIndex && this.oldVisible ? this.oldAlpha : 0.0))
        .visibility(i === this.shownIndex ? Visibility.Visible : (i === this.oldIndex && this.oldVisible ? Visibility.Visible : Visibility.None))
      }, (i: number) => `${i}`)
    }
    .width('100%')
    .height('100%')
  }
}
