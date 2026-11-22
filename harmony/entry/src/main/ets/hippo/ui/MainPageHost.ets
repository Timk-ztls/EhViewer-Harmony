/*
 * ① 场景宿主实现（D-052 的落地点）：`SceneHost` 在本仓库**此前 0 个实现者**
 *   → 任何 Scene 的 `mSceneHost` 永远是 null → 场景能 new、能 attach，
 *     但 showTip / openDrawer / updateProfile 全走空（"可装配"只是数字好看）。
 *
 * 本文件提供**唯一实现者** `MainPageHost`（纯类，可被 @Component 持有），
 * 以及一个最小 @Component `MainPageHostView`（入口页只需它 + 一行 attach）。
 *
 * 约束（Lead）：
 *   A. 18 个方法的"真接 / warn-once"逐条列表见下方 §能力表
 *   B. warn-once 用**静态标志**（UnavailableLocalFavorites 曾每次 warn → 切分类刷屏 → 淹掉真警告）
 *   C. 留**调用计数**（callCount），让测试能断言"真的调到了"，而不是只断言"没崩"
 *      —— 否则 warn-once 会让 `showTip 被调用` 恒真，测试永远通过（gl-render T-01 同族）
 *
 * §能力表（方法 | 状态 | 不接的后果 | 将来由谁承担）
 *   1  updateProfile            | 真接（转发回调） | — | ui-scene（本类）
 *   2  addAboveSnackView        | 真接（计数+转调） | — | ui-scene
 *   3  removeAboveSnackView     | 真接（计数+转调） | — | ui-scene
 *   4  setDrawerLockMode        | 真接（写状态）    | — | ui-scene
 *   5  openDrawer               | 真接（写状态）    | — | ui-scene
 *   6  closeDrawer              | 真接（写状态）    | — | ui-scene
 *   7  toggleDrawer             | 真接（写状态）    | — | ui-scene
 *   8  setDrawerGestureBlocker  | 真接（写状态）    | — | ui-scene
 *   9  isDrawersVisible         | 真接（读状态）    | — | ui-scene
 *  10  setNavCheckedItem        | 真接（写状态）    | — | ui-scene
 *  11  showTipById              | warn-once         | 用户看不到提示条（功能可用） | ui-widget（Toast/提示条构件）
 *  12  showTip(message)         | warn-once         | 同上 | ui-widget
 *  13  hideSoftInput            | warn-once         | 键盘可能不收（页面可退出） | ui-widget（输入法控制）
 *  14  showSoftInput            | warn-once         | 键盘可能不弹（用户可手点输入框） | ui-widget
 *  15  (其余 4 个由 SceneHost 未来扩展时补) | — | — | —
 *
 * 说明：编号 15 的占位是诚实的 —— 当前 `SceneHost` 实为 **14 个方法**（我 grep 过接口全文，
 * 不是 18：18 是"含注释行"的粗略计数）。**已按实际 14 条实现**，避免"表里 18 条、代码 14 个"的对不上。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GLView } from '../lib/glview/view/GLView';
import { SceneHost, BaseScene } from '../ehviewer/ui/scene/BaseScene';
import {
  SceneArgs, StageHost, SceneResultReceiver, SceneTransitionHelper
} from '../scene/SceneTypes';
import { SceneApplication } from '../scene/SceneApplication';
import { SceneFragment } from '../scene/SceneFragment';

const DOMAIN: number = 0x0000;
const TAG: string = 'MainPageHost';

/** 抽屉重力/锁定模式的占位取值（后续由 DrawerLayout 的枚举替换） */
export const DRAWER_GRAVITY_START: number = 0;
export const DRAWER_GRAVITY_END: number = 1;

/**
 * 场景宿主实现。**纯类**（不是 @Component）：@Component 不能被 `implements` 约束，
 * 而 SceneHost 需要编译期保证 14 个方法齐备。
 */
export class MainPageHost implements SceneHost {
  /** 调用计数（供测试断言"真的调到了"，不依赖日志） */
  readonly callCount: Map<string, number> = new Map<string, number>();

  // ---- 真接的状态 ----
  private drawerLockMode: number = 0;
  private drawerLockEdge: number = 0;
  private drawerOpen: boolean = false;
  private drawerGestureBlocker: number = 0;
  private navCheckedItem: number = -1;
  /** 由装配层注入：更新头像/资料（上游 MainActivity.updateProfile） */
  private profileUpdater: () => void = (): void => {};
  /** 由装配层注入：上层浮层（上游 addAboveSnackView/removeAboveSnackView） */
  private aboveSnackAdder: (view: GLView) => void = (view: GLView): void => {};
  private aboveSnackRemover: (view: GLView) => void = (view: GLView): void => {};

  // ---- warn-once 静态标志（每个方法一个）----
  private static warnedTipById: boolean = false;
  private static warnedTip: boolean = false;
  private static warnedHideIme: boolean = false;
  private static warnedShowIme: boolean = false;

  private bump(name: string): void {
    const n: number | undefined = this.callCount.get(name);
    this.callCount.set(name, n === undefined ? 1 : n + 1);
  }

  setProfileUpdater(fn: () => void): void { this.profileUpdater = fn; }
  setAboveSnackViewHandler(add: (view: GLView) => void, remove: (view: GLView) => void): void {
    this.aboveSnackAdder = add;
    this.aboveSnackRemover = remove;
  }

  // ===== 1-3：资料 / 浮层 =====
  updateProfile(): void {
    this.bump('updateProfile');
    this.profileUpdater();
  }

  addAboveSnackView(view: GLView): void {
    this.bump('addAboveSnackView');
    this.aboveSnackAdder(view);
  }

  removeAboveSnackView(view: GLView): void {
    this.bump('removeAboveSnackView');
    this.aboveSnackRemover(view);
  }

  // ===== 4-8：抽屉 =====
  setDrawerLockMode(lockMode: number, edgeGravity: number): void {
    this.bump('setDrawerLockMode');
    this.drawerLockMode = lockMode;
    this.drawerLockEdge = edgeGravity;
  }

  openDrawer(drawerGravity: number): void {
    this.bump('openDrawer');
    this.drawerOpen = true;
  }

  closeDrawer(drawerGravity: number): void {
    this.bump('closeDrawer');
    this.drawerOpen = false;
  }

  toggleDrawer(drawerGravity: number): void {
    this.bump('toggleDrawer');
    this.drawerOpen = !this.drawerOpen;
  }

  setDrawerGestureBlocker(gestureBlocker: number): void {
    this.bump('setDrawerGestureBlocker');
    this.drawerGestureBlocker = gestureBlocker;
  }

  // ===== 9-10：可视状态 / 导航选中 =====
  isDrawersVisible(): boolean {
    this.bump('isDrawersVisible');
    return this.drawerOpen;
  }

  setNavCheckedItem(resId: number): void {
    this.bump('setNavCheckedItem');
    this.navCheckedItem = resId;
  }

  // ===== 11-12：提示（warn-once；构件在 ui-widget）=====
  showTipById(id: number, length: number): void {
    this.bump('showTipById');
    if (!MainPageHost.warnedTipById) {
      MainPageHost.warnedTipById = true;
      hilog.warn(DOMAIN, TAG,
        'showTipById 未接线（提示条构件在 ui-widget）；后果：用户看不到 id=%{public}d 的提示。此告警只打印一次', id);
    }
  }

  showTip(message: string, length: number): void {
    this.bump('showTip');
    if (this.tipHandler !== null) {
      this.tipHandler(message);
      return;
    }
    if (!MainPageHost.warnedTip) {
      MainPageHost.warnedTip = true;
      hilog.warn(DOMAIN, TAG,
        'showTip 未接线（提示条构件在 ui-widget）；后果：用户看不到消息。此告警只打印一次');
    }
  }

  // ===== 13-14：输入法（warn-once）=====
  hideSoftInput(): void {
    this.bump('hideSoftInput');
    if (!MainPageHost.warnedHideIme) {
      MainPageHost.warnedHideIme = true;
      hilog.warn(DOMAIN, TAG,
        'hideSoftInput 未接线（输入法控制在 ui-widget）；后果：键盘可能不收。此告警只打印一次');
    }
  }

  showSoftInput(view: GLView): void {
    this.bump('showSoftInput');
    if (!MainPageHost.warnedShowIme) {
      MainPageHost.warnedShowIme = true;
      hilog.warn(DOMAIN, TAG,
        'showSoftInput 未接线（输入法控制在 ui-widget）；后果：键盘可能不弹。此告警只打印一次');
    }
  }

  // ===== 场景挂载 + 场景内导航（StageHost 实现）=====

  /** 已挂载的场景（tag → 实例），模拟 StageActivity 的 `scenes` 表 */
  private readonly mounted: Map<string, SceneFragment> = new Map<string, SceneFragment>();
  /** 场景顺序（栈），tag 列表 */
  private readonly mountedOrder: string[] = [];
  private readonly finishingTags: Set<string> = new Set<string>();
  private nextTag: number = 1;
  /** 导航回调：由 MainPageHostView 注册，场景内 startScene 时切渲染分支 */
  private navigator: (sceneName: string, scene: SceneFragment | null) => void = (): void => {};
  /** 栈空回调：当根场景 finish() 后通知入口页重新判定门控或切到首页 */
  private onEmptyStack: (() => void) | null = null;
  private tipHandler: ((message: string) => void) | null = null;

  setNavigator(fn: (sceneName: string, scene: SceneFragment | null) => void): void {
    this.navigator = fn;
  }

  setOnEmptyStack(fn: (() => void) | null): void {
    this.onEmptyStack = fn;
  }

  setTipHandler(fn: ((message: string) => void) | null): void {
    this.tipHandler = fn;
  }

  canGoBack(): boolean {
    return this.mountedOrder.length > 1;
  }

  getStackDepth(): number {
    return this.mountedOrder.length;
  }

  goBack(): boolean {
    const topTag: string = this.mountedOrder.length > 0
      ? this.mountedOrder[this.mountedOrder.length - 1]
      : '';
    const top: SceneFragment | undefined = topTag.length > 0 ? this.mounted.get(topTag) : undefined;
    if (top !== undefined && top.tryConsumeBack()) {
      return true;
    }
    if (this.mountedOrder.length <= 1) {
      return false;
    }
    if (top !== undefined) {
      top.onBackPressed();
      return true;
    }
    this.finishSceneByTag(topTag, null);
    return true;
  }

  private clearMountedStack(): void {
    for (let i = this.mountedOrder.length - 1; i >= 0; i--) {
      const oldTag: string = this.mountedOrder[i];
      const old: SceneFragment | undefined = this.mounted.get(oldTag);
      if (old !== undefined) {
        old.onSceneViewDestroyed();
        old.onSceneDestroyed();
        old.bindHost(null);
        if (old instanceof BaseScene) {
          old.bindSceneHost(null);
        }
      }
    }
    this.mounted.clear();
    this.mountedOrder.splice(0, this.mountedOrder.length);
  }

  /**
   * 按名字创建根场景并**同时绑定两个宿主** + 压栈作为根场景（pushToStack=true）。
   */
  attachScene(sceneName: string, args: SceneArgs | null = null): SceneFragment | null {
    this.bump('attachScene');
    this.clearMountedStack();
    const created: SceneFragment | null = this.attachInternal(sceneName, true);
    if (created !== null) {
      if (args !== null) {
        created.setArguments(args);
        created.onNewArguments(args);
      }
      created.onSceneViewCreated();
    }
    return created;
  }

  private attachInternal(sceneName: string, pushToStack: boolean): SceneFragment | null {
    const created: SceneFragment = SceneApplication.get().createScene(sceneName);
    // 分配 tag（上游 StageActivity 用自增整数做 Fragment tag）
    const tag: string = String(this.nextTag);
    this.nextTag = this.nextTag + 1;
    created.setTag(tag);

    // ① StageHost：场景内导航/结束的必需项
    created.bindHost(this as Object as StageHost);
    // ② SceneHost：页级能力（仅 BaseScene 子类具备）
    if (created instanceof BaseScene) {
      created.bindSceneHost(this);
    } else {
      hilog.info(DOMAIN, TAG,
        'attachScene: %{public}s 不是 BaseScene 子类（无 bindSceneHost）；后果：该场景宿主能力走兜底', sceneName);
    }

    if (pushToStack) {
      this.mounted.set(tag, created);
      this.mountedOrder.push(tag);
    }
    return created;
  }

  // ===== StageHost 实现（7 个方法）=====

  /** 场景内 `startScene(announcer)` 的落点：记录请求方 + 创建目标场景 + 传参 + 通知渲染层切换 */
  startSceneByName(sceneName: string, args: SceneArgs | null, requestFromTag: string | null,
    requestCode: number): void {
    this.bump('startSceneByName');
    hilog.info(DOMAIN, TAG,
      'startSceneByName: %{public}s（from=%{public}s code=%{public}d）',
      sceneName, requestFromTag === null ? '-' : requestFromTag, requestCode);
    try {
      const scene: SceneFragment | null = this.attachInternal(sceneName, true);
      if (scene === null) {
        return;
      }
      if (requestFromTag !== null && requestFromTag.length > 0) {
        scene.addRequest(requestFromTag, requestCode);
      }
      if (args !== null) {
        scene.setArguments(args);
        scene.onNewArguments(args);
      }
      scene.onSceneViewCreated();
      this.navigator(sceneName, scene);
    } catch (e) {
      hilog.error(DOMAIN, TAG,
        'startSceneByName 抛出: %{public}s；后果：场景未切换，用户停留在当前页', (e as Error).message);
    }
  }

  /** 场景内 `finish()` 的落点：先回传结果，再出栈清理，切回栈顶或通知空栈 */
  finishSceneByTag(tag: string, transitionHelper: SceneTransitionHelper | null): void {
    this.bump('finishSceneByTag');
    const idx: number = this.mountedOrder.indexOf(tag);
    if (idx < 0) {
      hilog.warn(DOMAIN, TAG, 'finishSceneByTag: 未知 tag=%{public}s；后果：无动作', tag);
      return;
    }
    const scene: SceneFragment | undefined = this.mounted.get(tag);
    this.finishingTags.add(tag);
    try {
      if (scene !== undefined) {
        scene.returnResult(this as Object as StageHost);
      }
    } finally {
      this.finishingTags.delete(tag);
    }
    const curIdx: number = this.mountedOrder.indexOf(tag);
    if (curIdx >= 0) {
      this.mountedOrder.splice(curIdx, 1);
    }
    this.mounted.delete(tag);
    if (scene !== undefined) {
      scene.onSceneViewDestroyed();
      scene.onSceneDestroyed();
      scene.bindHost(null);
      if (scene instanceof BaseScene) {
        scene.bindSceneHost(null);
      }
    }
    // 回退到栈顶；栈空则通知空（入口页负责重判门或落首页）
    if (this.mountedOrder.length > 0) {
      const topTag: string = this.mountedOrder[this.mountedOrder.length - 1];
      if (!this.finishingTags.has(topTag)) {
        const top: SceneFragment | undefined = this.mounted.get(topTag);
        if (top !== undefined) {
          this.navigator(top.getSceneName(), top);
        }
      }
      return;
    }
    this.navigator('', null);
    if (this.onEmptyStack !== null) {
      this.onEmptyStack();
    }
  }

  getSceneIndexByTag(tag: string): number {
    return this.mountedOrder.indexOf(tag);
  }

  notifySceneViewCreated(scene: SceneResultReceiver): void {
    this.bump('notifySceneViewCreated');
  }

  notifySceneViewDestroyed(scene: SceneResultReceiver): void {
    this.bump('notifySceneViewDestroyed');
  }

  notifySceneDestroyed(scene: SceneResultReceiver): void {
    this.bump('notifySceneDestroyed');
  }

  findSceneByTag(tag: string): SceneResultReceiver | null {
    const scene: SceneFragment | undefined = this.mounted.get(tag);
    return scene === undefined ? null : scene as Object as SceneResultReceiver;
  }

  // ===== 滑动防误触节流 =====
  private static lastSwipeEndMs: number = 0;

  static markSwipeGesture(): void {
    MainPageHost.lastSwipeEndMs = Date.now();
  }

  static shouldSuppressClick(windowMs: number = 300): boolean {
    return Date.now() - MainPageHost.lastSwipeEndMs < windowMs;
  }

  // ===== 供测试/装配层读状态 =====
  getDrawerLockMode(): number { return this.drawerLockMode; }
  getDrawerLockEdge(): number { return this.drawerLockEdge; }
  getNavCheckedItem(): number { return this.navCheckedItem; }
  getDrawerGestureBlocker(): number { return this.drawerGestureBlocker; }
  getCallCount(name: string): number {
    const n: number | undefined = this.callCount.get(name);
    return n === undefined ? 0 : n;
  }
}
