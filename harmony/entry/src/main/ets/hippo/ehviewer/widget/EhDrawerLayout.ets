/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/EhDrawerLayout.java（S0289，上游 144 行）
 *
 * 上游 = `DrawerLayout` + 一份 **CoordinatorLayout Behavior**，做一件很具体的事：
 *   Snackbar 出现时，把登记在 `mAboveSnackViewList` 里的视图（FAB 等）向上顶，避免被 Snackbar 遮住。
 *   · addAboveSnackView / removeAboveSnackView / getAboveSnackViewCount / getAboveSnackViewAt(index)
 *     （index 越界返回 null；list 为 null 时 count=0）
 *   · Behavior.layoutDependsOn：依赖所有 **SnackbarLayout**
 *   · Behavior.onDependentViewChanged：对每个 aboveSnackView 调 updateChildTranslationForSnackbar
 *   · getChildTranslationYForSnackbar：
 *       `minOffset = 0; for each SnackbarLayout 且与 child 重叠: minOffset = min(minOffset, snackbar.translationY - snackbar.height)`
 *       ⇒ 目标位移 = **所有重叠 Snackbar 里最负的那个**（最多顶起一个 Snackbar 的高度）
 *   · updateChildTranslationForSnackbar：
 *       若 `|currentTransY - target| > child.height * 0.667` 且 child 可见 → **动画**（FAST_SLOW_IN）
 *       否则**直接设值**
 *       两种路径最后都记录 `fab_translation_y` 这个 tag（避免重复动画到同一目标）
 *
 * ============================ ArkUI 对位：Behavior 体系不存在 → 拆成"可测数学 + 调用方驱动" ============================
 * ArkUI 没有 CoordinatorLayout / Behavior / Snackbar 的自动依赖机制。
 * 因此本文件保留：① 上述 list 语义 ② **翻译量数学**（可单测）③ "是否该用动画"的阈值判定
 * 并把它暴露为 `EhDrawerLayoutState.translationForSnackbar(...)`，由 **ui-scene 在 Snackbar 显示/消失时调用**
 * （与 `FabLayout` 的 `ScrollOffsetHost`、`SearchBarMover` 的注入模式一致）。
 * `SNACKBAR_BEHAVIOR_ENABLED = SDK_INT >= 11` 在鸿蒙恒真（无该分支）。
 *
 * 差异（已登记 MR）：
 *   1) `DrawerLayout` 的抽屉拖拽 → **本文件第 8 轮补上**（见下方 `DrawerGestureMath` + `PanGesture`）：
 *      上游那 144 行里**一行抽屉代码都没有**，边缘拖拽 / scrim / 吸附 / 返回键关闭全部来自
 *      AndroidX 的 `DrawerLayout` 父类。Excel「父类给的能力」这一类最容易被 `grep 上游文件` 漏掉：
 *      判据是看 `extends` 后面的类，逐个问"它提供了哪些用户可观测行为"，再到我们的实现里核对。
 *      常量照 AOSP，不自己发明（EDGE_SIZE=20dp / MIN_DRAWER_MARGIN=64dp / 吸附 0.5 / scrim 0x99）。
 *   2) Behavior 的自动依赖 → 调用方显式调用（平台无此机制）
 *   3) 动画曲线复用 core-runtime 的 `AnimationUtils.FAST_SLOW_INTERPOLATOR`（与上游同一个插值器）
 *   4) **返回键关闭仍在宿主页**：ArkUI 的 `onBackPress` 是页面级回调，组件拿不到；
 *      宿主页应 `if (drawer.isOpen()) { drawer.requestClose(); return true; }`（见文件尾用法）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

// 纯数学层抽到 DrawerGestureMath.ets（不带装饰器才能被 TS 单测 import），此处仅转出
import { DrawerGestureMath } from './DrawerGestureMath';
export { DrawerGestureMath } from './DrawerGestureMath';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.EhDrawerLayout';

/** 对位 Snackbar 的可测几何（上游 SnackbarLayout 的 translationY / height） */
export class SnackbarGeometry {
  translationY: number = 0;
  height: number = 0;
  /** 是否与 child 重叠（上游 parent.doViewsOverlap(child, view)） */
  overlaps: boolean = true;
}

export class EhDrawerLayoutState {
  /** 上游 mAboveSnackViewList（这里用 string 标识代替 View 引用） */
  private aboveSnackViews: string[] = [];
  /** 上游 fab_translation_y tag：已动画到的目标值 */
  targetTranslationY: number[] = [];
  private currentValues: number[] = [];

  addAboveSnackView(viewId: string): void {
    this.aboveSnackViews.push(viewId);
    this.currentValues.push(0);
    this.targetTranslationY.push(0);
  }

  removeAboveSnackView(viewId: string): void {
    const i: number = this.aboveSnackViews.indexOf(viewId);
    if (i < 0) {
      return;
    }
    this.aboveSnackViews.splice(i, 1);
    this.currentValues.splice(i, 1);
    this.targetTranslationY.splice(i, 1);
  }

  getAboveSnackViewCount(): number {
    return this.aboveSnackViews.length;
  }

  /** 上游 getAboveSnackViewAt：越界返回 null */
  getAboveSnackViewAt(index: number): string | null {
    if (index < 0 || index >= this.aboveSnackViews.length) {
      return null;
    }
    return this.aboveSnackViews[index];
  }

  /**
   * 上游 getChildTranslationYForSnackbar：
   *   `minOffset = 0`，对每个"重叠的 Snackbar"取 `min(minOffset, snackbar.translationY - snackbar.height)`。
   * ⇒ 结果**恒 <= 0**（不上顶时为 0）。
   */
  static translationForSnackbar(snackbars: SnackbarGeometry[]): number {
    let minOffset: number = 0;
    for (let i = 0; i < snackbars.length; i++) {
      const s: SnackbarGeometry = snackbars[i];
      if (s.overlaps) {
        minOffset = Math.min(minOffset, s.translationY - s.height);
      }
    }
    return minOffset;
  }

  /**
   * 上游 updateChildTranslationForSnackbar 的分支判定：
   * `child.isShown() && |current - target| > child.height * 0.667` → 动画；否则直接设值。
   */
  static shouldAnimate(current: number, target: number, childHeight: number, childShown: boolean): boolean {
    if (!childShown) {
      return false;
    }
    return Math.abs(current - target) > childHeight * 0.667;
  }

  /** 记录/查询某 aboveSnack 视图当前位移（对位 child.setTag(fab_translation_y)） */
  setCurrent(index: number, value: number): void {
    if (index >= 0 && index < this.currentValues.length) {
      this.currentValues[index] = value;
    }
  }

  getCurrent(index: number): number {
    return index >= 0 && index < this.currentValues.length ? this.currentValues[index] : 0;
  }
}

@Component
export struct EhDrawerLayout {
  state: EhDrawerLayoutState = new EhDrawerLayoutState();
  @Prop drawerWidth: number = 280;
  /** 外部受控开关（页面可直接改它）；手势拖动结束后通过 onOpenChange 回写 */
  @Prop @Watch('onOpenChanged') open: boolean = false;
  @BuilderParam drawer: () => void = this.empty;
  @BuilderParam content: () => void = this.empty;

  /** 抽屉位移（0 = 全关，drawerWidth = 全开）。手势与动画都改它 */
  @State drawerOffset: number = 0;
  /** 本次手势是否真的在拖抽屉（决定 onActionUpdate 要不要吃位移） */
  @State dragging: boolean = false;
  /** 手势起手时的 offset（跟手位移的基准） */
  private dragBaseOffset: number = 0;
  /** 抽屉/遮罩滑动时长（AOSP DrawerLayout 的关闭动画约 250ms，此处取 250） */
  private static readonly SLIDE_DURATION: number = 250;

  /** 手势结束/程序化开关后通知外部（对位 DrawerLayout.DrawerListener 的 onDrawerOpened/Closed） */
  onOpenChange: (open: boolean) => void = (open: boolean): void => {
  };

  openDuration(): number {
    return EhDrawerLayout.SLIDE_DURATION;
  }

  @Builder
  empty(): void {
  }

  aboutToAppear(): void {
    this.drawerOffset = this.open ? this.drawerWidth : 0;
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '%{public}s', 'Behavior auto-dependency is not available on ArkUI; callers drive translationForSnackbar()');
  }

  /** 外部改 open → 平滑跟到目标位（对位 DrawerLayout.openDrawer/closeDrawer 的动画） */
  onOpenChanged(): void {
    const target: number = this.open ? this.drawerWidth : 0;
    if (target === this.drawerOffset) {
      return;
    }
    animateTo({ duration: EhDrawerLayout.SLIDE_DURATION, curve: Curve.FastOutSlowIn }, (): void => {
      this.drawerOffset = target;
    });
  }

  /** 当前是否（部分）打开：返回键/宿主页用它决定要不要吞掉 back */
  isOpen(): boolean {
    return this.drawerOffset > 0;
  }

  /** 程序化关闭（宿主页 onBackPress 调；带滑动动画） */
  requestClose(): void {
    if (this.drawerOffset === 0) {
      return;
    }
    animateTo({ duration: EhDrawerLayout.SLIDE_DURATION, curve: Curve.FastOutSlowIn }, (): void => {
      this.drawerOffset = 0;
    });
    this.open = false;
    this.onOpenChange(false);
  }

  /** 程序化打开（等价 DrawerLayout.openDrawer(Gravity.LEFT)） */
  requestOpen(): void {
    if (this.drawerOffset === this.drawerWidth) {
      return;
    }
    animateTo({ duration: EhDrawerLayout.SLIDE_DURATION, curve: Curve.FastOutSlowIn }, (): void => {
      this.drawerOffset = this.drawerWidth;
    });
    this.open = true;
    this.onOpenChange(true);
  }

  /** 松手：吸附到 0 或 drawerWidth，并回写 open + 通知外部 */
  private settle(): void {
    const target: number = DrawerGestureMath.snapTarget(this.drawerOffset, this.drawerWidth);
    const opened: boolean = target > 0;
    animateTo({ duration: EhDrawerLayout.SLIDE_DURATION, curve: Curve.FastOutSlowIn }, (): void => {
      this.drawerOffset = target;
    });
    if (this.open !== opened) {
      this.open = opened;
      this.onOpenChange(opened);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1) 内容层（铺满，最底）
      Column() {
        this.content()
      }
      .width('100%')
      .height('100%')

      // 2) 遮罩：不透明度跟抽屉进度线性联动（AOSP：progress × 0x99/0xFF，最大 0.6）
      //    点击遮罩关抽屉（对位 DrawerLayout 点内容区关闭）
      if (this.drawerOffset > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(`rgba(0,0,0,${DrawerGestureMath.scrimAlpha(this.drawerOffset, this.drawerWidth)})`)
          .onClick((): void => {
            this.requestClose();
          })
      }

      // 3) 抽屉：位移 = offset - drawerWidth（offset=0 时整块在屏外左侧）
      Column() {
        this.drawer()
      }
      .width(this.drawerWidth)
      .height('100%')
      .backgroundColor('#FFFFFFFF')
      .translate({ x: this.drawerOffset - this.drawerWidth })
    }
    .width('100%')
    .height('100%')
    // 4) 边缘拖拽：关闭态只有左 EDGE_SIZE(20vp) 内起手；打开态任意位置起手即关
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
        .onActionStart((event: GestureEvent): void => {
          const x: number = event.fingerList.length > 0 ? event.fingerList[0].localX : 0;
          this.dragging = DrawerGestureMath.shouldStartDrag(x, this.drawerOffset > 0, this.drawerWidth);
          this.dragBaseOffset = this.drawerOffset;
        })
        .onActionUpdate((event: GestureEvent): void => {
          if (!this.dragging) {
            return;
          }
          // offsetX 是"自手势开始起的累计位移"，加到起手时的 offset 上 → 跟手
          this.drawerOffset = DrawerGestureMath.clampOffset(this.dragBaseOffset + event.offsetX, this.drawerWidth);
        })
        .onActionEnd((): void => {
          if (!this.dragging) {
            return;
          }
          this.dragging = false;
          this.settle();
        })
        .onActionCancel((): void => {
          if (!this.dragging) {
            return;
          }
          this.dragging = false;
          this.settle();
        })
    )
  }
}

// 用法（宿主页：返回键关闭 + 程序化打开）：
//   @State drawerOpen: boolean = false;
//   build() { EhDrawerLayout({ open: this.drawerOpen, onOpenChange: (o) => { this.drawerOpen = o; }, … }) }
//   onBackPress(): boolean {
//     if (this.drawerOpen) { this.drawerOpen = false; return true; }   // ← 对位 DrawerLayout 的返回键关闭
//     return false;
//   }

