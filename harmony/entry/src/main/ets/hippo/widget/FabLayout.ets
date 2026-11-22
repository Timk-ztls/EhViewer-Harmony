/**
 * 迁移自 app/src/main/java/com/hippo/widget/FabLayout.java（inventory S0520，上游 367 行）
 *
 * ============================ 判据：这是"分叉"，不是"子集" → 自绘状态机 ============================
 * 上游 `FabLayout extends ViewGroup`，自己实现了三件 ArkUI 没有的东西：
 *   1) 子视图约束（只允许 FloatingActionButton，否则抛 IllegalStateException）
 *   2) **展开/收起动画**：primary 旋转 45°、secondary 沿垂直方向位移 + 缩放 + 淡入淡出，300ms
 *   3) **自动收起**（autoCancel）：展开状态下点空白处收起（收起状态下不拦截底层点击/滚动）
 * ArkUI 没有 Behavior/ViewGroup.onLayout 体系，故写成
 *   `FabBehaviorState`（纯状态机，可单测） + `FabLayout`（Material 圆形 FAB 渲染 + animateTo）
 */
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens
} from '../../common/theme/ThemeTokens';
import { VPlusDarkX24 } from '../ui/drawable/v_plus_dark_x24';

export interface OnExpandListener {
  onExpand(expanded: boolean): void;
}

export interface OnClickFabListener {
  onClickPrimaryFab(layout: FabBehaviorState): void;

  onClickSecondaryFab(layout: FabBehaviorState, index: number): void;
}

/** 具名实现类（ArkTS 禁止无类型对象字面量） */
export class OnExpandListenerImpl implements OnExpandListener {
  private fn: (expanded: boolean) => void;

  constructor(fn: (expanded: boolean) => void) {
    this.fn = fn;
  }

  onExpand(expanded: boolean): void {
    this.fn(expanded);
  }
}

export class OnClickFabListenerImpl implements OnClickFabListener {
  private primaryFn: (layout: FabBehaviorState) => void;
  private secondaryFn: (layout: FabBehaviorState, index: number) => void;

  constructor(primaryFn: (layout: FabBehaviorState) => void,
              secondaryFn: (layout: FabBehaviorState, index: number) => void) {
    this.primaryFn = primaryFn;
    this.secondaryFn = secondaryFn;
  }

  onClickPrimaryFab(layout: FabBehaviorState): void {
    this.primaryFn(layout);
  }

  onClickSecondaryFab(layout: FabBehaviorState, index: number): void {
    this.secondaryFn(layout, index);
  }
}

/**
 * 滚动偏移宿主（**由 ui-scene 的页面实现并注入**，ui-widget 不依赖具体滚动组件）。
 */
export interface ScrollOffsetHost {
  /** 当前滚动偏移（向上滚为正，与 AppBarLayout.getTopAndBottomOffset 的符号约定一致） */
  getOffset(): number;

  /** 注册偏移变化回调 */
  onOffsetChanged(cb: (offset: number) => void): void;
}

/** 存档（对位上游 Parcelable 的两个额外键） */
export class FabSavedState {
  autoCancel: boolean = true;
  expanded: boolean = true;
}

export class FabBehaviorState {
  static readonly ANIMATE_TIME: number = 300;
  /** 上游隐藏阈值：偏移超过该值即隐藏 primary */
  static readonly HIDE_THRESHOLD: number = 48;

  expanded: boolean = true;
  autoCancel: boolean = true;
  hidePrimaryFab: boolean = false;
  secondaryCount: number = 0;
  /** 上游 setSecondaryFabVisibilityAt 的独立可见性覆盖（-1 表示跟随 expanded） */
  secondaryVisibleOverride: number[] = [];
  expandListener: OnExpandListener | null = null;
  clickListener: OnClickFabListener | null = null;
  private scrollHost: ScrollOffsetHost | null = null;
  private viewObserver: (() => void) | null = null;

  /** 绑定 UI 视图同步回调（仅供 FabLayout 组件内部同步 @State） */
  setViewObserver(observer: (() => void) | null): void {
    this.viewObserver = observer;
  }

  private notifyView(): void {
    const obs: (() => void) | null = this.viewObserver;
    if (obs !== null) {
      obs();
    }
  }

  isExpanded(): boolean {
    return this.expanded;
  }

  toggle(): void {
    this.setExpanded(!this.expanded, true);
  }

  setExpanded(expanded: boolean, _animation: boolean = true): void {
    if (this.expanded === expanded) {
      return;
    }
    this.expanded = expanded;
    if (this.expandListener !== null) {
      this.expandListener.onExpand(expanded);
    }
    this.notifyView();
  }

  setHidePrimaryFab(hide: boolean, _animation: boolean = true): void {
    if (this.hidePrimaryFab !== hide) {
      this.hidePrimaryFab = hide;
      this.notifyView();
    }
  }

  setOnClickFabListener(listener: OnClickFabListener | null): void {
    this.clickListener = listener;
  }

  setOnExpandListener(listener: OnExpandListener | null): void {
    this.expandListener = listener;
  }

  setAutoCancel(autoCancel: boolean): void {
    if (this.autoCancel !== autoCancel) {
      this.autoCancel = autoCancel;
      this.notifyView();
    }
  }

  setSecondaryFabVisibilityAt(index: number, visible: boolean): void {
    this.secondaryVisibleOverride[index] = visible ? 1 : 0;
    this.notifyView();
  }

  /** 某个 secondary 是否应显示（对位上游：mExpanded 决定，另有独立覆盖） */
  isSecondaryVisible(index: number): boolean {
    if (index < this.secondaryVisibleOverride.length && this.secondaryVisibleOverride[index] >= 0) {
      return this.secondaryVisibleOverride[index] === 1;
    }
    return this.expanded;
  }

  /**
   * 点击 primary FAB（上游 `FabLayout.java:370-382`）：无条件回调 `onClickPrimaryFab`。
   */
  onPrimaryClick(): void {
    if (this.clickListener !== null) {
      this.clickListener.onClickPrimaryFab(this);
    }
  }

  /** 点击 secondary：仅在展开态回调（对位上游 `position >= 0 && mExpanded`） */
  onSecondaryClick(index: number): void {
    if (!this.expanded) {
      return;
    }
    if (index < 0) {
      return;
    }
    if (this.clickListener !== null) {
      this.clickListener.onClickSecondaryFab(this, index);
    }
  }

  /** 点击空白：autoCancel 且展开 → 收起 */
  onBlankClick(): void {
    if (this.autoCancel && this.expanded) {
      this.setExpanded(false, true);
    }
  }

  /** 绑定滚动宿主 */
  bindScroll(host: ScrollOffsetHost): void {
    this.scrollHost = host;
    this.scrollHost.onOffsetChanged((offset: number) => {
      this.setHidePrimaryFab(offset > FabBehaviorState.HIDE_THRESHOLD);
    });
    this.setHidePrimaryFab(host.getOffset() > FabBehaviorState.HIDE_THRESHOLD);
  }

  saveState(): FabSavedState {
    const s: FabSavedState = new FabSavedState();
    s.autoCancel = this.autoCancel;
    s.expanded = this.expanded;
    return s;
  }

  restoreState(s: FabSavedState): void {
    this.autoCancel = s.autoCancel;
    this.expanded = s.expanded;
    this.notifyView();
  }
}

@Component
export struct FabLayout {
  state: FabBehaviorState = new FabBehaviorState();
  /** 尺寸（对位上游 dimens.xml: fab_size=56 / fab_min_size=40 / fab_layout_primary_margin=24 / fab_layout_secondary_margin=16） */
  @Prop fabSize: number = ThemeDimens.FAB_SIZE;
  @Prop fabMiniSize: number = ThemeDimens.FAB_MINI_SIZE;
  @Prop intervalPrimary: number = ThemeDimens.FAB_LAYOUT_PRIMARY_MARGIN;
  @Prop intervalSecondary: number = ThemeDimens.FAB_LAYOUT_SECONDARY_MARGIN;
  /** 右下角内边距（对位 scene_gallery_list.xml 的 corner_fab_margin=16vp；外层容器已给 padding 时可传 0） */
  @Prop cornerPadding: number = ThemeDimens.CORNER_FAB_MARGIN;
  /** secondary FAB 数量（对位 getChildCount()-1） */
  @Prop secondaryFabCount: number = 0;
  @Prop primaryColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @BuilderParam primaryFab: () => void = this.defaultPrimaryFab;
  @BuilderParam secondaryFab: (index: number) => void = this.defaultSecondaryFab;

  @State expanded: boolean = true;
  @State hidePrimaryFab: boolean = false;
  @State rev: number = 0;

  private resolvedPrimaryColor(): ResourceColor {
    if (typeof this.primaryColor === 'string' && this.primaryColor.length === 0) {
      return ThemeTokens.current().widgetThemePrimary;
    }
    return this.primaryColor;
  }

  private resolvedAccentColor(): ResourceColor {
    if (typeof this.accentColor === 'string' && this.accentColor.length === 0) {
      return ThemeTokens.current().widgetThemeAccent;
    }
    return this.accentColor;
  }

  private syncFromState(): void {
    this.expanded = this.state.expanded;
    this.hidePrimaryFab = this.state.hidePrimaryFab;
    this.rev = this.rev + 1;
  }

  @Builder
  defaultPrimaryFab(): void {
    VPlusDarkX24({
      iconSize: ThemeDimens.ICON_SIZE_STANDARD,
      fillColor: ThemeTokens.current().fabIconColor
    })
  }

  @Builder
  defaultSecondaryFab(_index: number): void {
    VPlusDarkX24({
      iconSize: ThemeDimens.ICON_SIZE_STANDARD,
      fillColor: ThemeTokens.current().fabIconColor
    })
  }

  aboutToAppear(): void {
    this.state.secondaryCount = this.secondaryFabCount;
    this.syncFromState();
    this.state.setViewObserver((): void => {
      this.syncFromState();
    });
  }

  aboutToDisappear(): void {
    this.state.setViewObserver(null);
  }

  private isSecondaryRendered(index: number): boolean {
    if (index < this.state.secondaryVisibleOverride.length && this.state.secondaryVisibleOverride[index] === 0) {
      return false;
    }
    return true;
  }

  private isSecondaryClickable(index: number): boolean {
    return this.expanded && this.state.isSecondaryVisible(index);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // 仅展开且开启 autoCancel 时挂载全屏点击遮罩，收起态绝不拦截底层列表触控
      if (this.expanded && this.state.autoCancel) {
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.state.onBlankClick();
          })
      }

      // 实际右下角 FAB 堆栈（受 cornerPadding 定位）
      Stack({ alignContent: Alignment.BottomEnd }) {
        // secondary FAB 自上而下对应 0..N-1，居中对齐于 primary FAB 上方
        Column({ space: this.intervalSecondary }) {
          ForEach(this.secondaryIndices(), (index: number) => {
            if (this.isSecondaryRendered(index)) {
              Stack({ alignContent: Alignment.Center }) {
                this.secondaryFab(index)
              }
              .width(this.fabMiniSize)
              .height(this.fabMiniSize)
              .borderRadius(this.fabMiniSize / 2)
              .backgroundColor(this.resolvedAccentColor())
              .shadow(ThemeElevation.fab())
              .opacity(this.isSecondaryClickable(index) ? 1.0 : 0.0)
              .scale({
                x: this.isSecondaryClickable(index) ? 1.0 : 0.5,
                y: this.isSecondaryClickable(index) ? 1.0 : 0.5
              })
              .animation({ duration: FabBehaviorState.ANIMATE_TIME, curve: Curve.EaseOut })
              .visibility(this.isSecondaryClickable(index) ? Visibility.Visible : Visibility.Hidden)
              .hitTestBehavior(this.isSecondaryClickable(index) ? HitTestMode.Default : HitTestMode.None)
              .onClick(() => {
                this.state.onSecondaryClick(index);
              })
            }
          }, (index: number) => `${index}`)
        }
        .margin({
          right: Math.max(0, (this.fabSize - this.fabMiniSize) / 2),
          bottom: this.fabSize + this.intervalPrimary
        })
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(this.expanded ? HitTestMode.Transparent : HitTestMode.None)

        // primary FAB：56x56 Material 圆形，展开时旋转 45°（+ -> ×）
        Stack({ alignContent: Alignment.Center }) {
          this.primaryFab()
        }
        .width(this.fabSize)
        .height(this.fabSize)
        .borderRadius(this.fabSize / 2)
        .backgroundColor(this.resolvedPrimaryColor())
        .shadow(ThemeElevation.fab())
        .rotate({ angle: this.expanded ? 45 : 0 })
        .scale({ x: this.hidePrimaryFab ? 0.0 : 1.0, y: this.hidePrimaryFab ? 0.0 : 1.0 })
        .opacity(this.hidePrimaryFab ? 0.0 : 1.0)
        .animation({ duration: FabBehaviorState.ANIMATE_TIME, curve: Curve.EaseInOut })
        .visibility(this.hidePrimaryFab ? Visibility.Hidden : Visibility.Visible)
        .hitTestBehavior(this.hidePrimaryFab ? HitTestMode.None : HitTestMode.Default)
        .onClick(() => {
          this.state.onPrimaryClick();
        })
      }
      .padding({ right: this.cornerPadding, bottom: this.cornerPadding })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .clip(false)
    .hitTestBehavior(this.expanded && this.state.autoCancel ? HitTestMode.Default : HitTestMode.Transparent)
  }

  private secondaryIndices(): number[] {
    const arr: number[] = [];
    for (let i = 0; i < this.secondaryFabCount; i++) {
      arr.push(i);
    }
    return arr;
  }
}
