/*
 * Copyright 2016 Hippo Seven
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneFragment } from '../../../scene/SceneFragment';
import { SceneArgs } from '../../../scene/SceneTypes';
import { Analytics } from '../../Analytics';
import { GLView, SparseArrayParcelable, Parcelable } from '../../../lib/glview/view/GLView';

const TAG = 'BaseScene';
const DOMAIN = 0x0000;

/**
 * 上游 `UserTagList`（S0067，net-parse 在移植）尚未落地。
 * 这里只声明结构占位：`BaseScene.setTagList()` 是给子类覆写的空钩子，
 * 等真实类型就位后替换成 `UserTagList`（签名不变，调用点零改动）。
 */
export interface UserTagListLike {
}

/**
 * 场景侧可以要求宿主页做事的全部能力（**本项目新增的接口**，替代上游的
 * `activity instanceof MainActivity` + 直调）。
 *
 * ## 为什么需要它
 * 上游有 14 处这种写法：
 * ```java
 * FragmentActivity activity = getActivity();
 * if (activity instanceof MainActivity) {
 *     ((MainActivity) activity).openDrawer(drawerGravity);
 * }
 * ```
 * ArkTS **没有 `instanceof` 跨类型收窄**（也没有 `MainActivity` 这个类：鸿蒙侧页面是
 * Entry 装饰器组件，不是 Activity 子类，见 D-051）。所以把"宿主能做的事"提成接口：
 * - `BaseScene` 只依赖接口，宿主是 null 时**静默降级**（与上游 `instanceof` 失败等价）
 * - 将来 `MainPage`/`Index` 实现 `SceneHost`，用 `bindSceneHost()` 注入
 *
 * **登记为 D-052**：`instanceof MainActivity` → `SceneHost` 能力接口 + 宿主注入。
 */
export interface SceneHost {
  /** 上游 `MainActivity.updateProfile()`（`updateAvatar()` 用）。 */
  updateProfile(): void;

  addAboveSnackView(view: GLView): void;

  removeAboveSnackView(view: GLView): void;

  setDrawerLockMode(lockMode: number, edgeGravity: number): void;

  openDrawer(drawerGravity: number): void;

  closeDrawer(drawerGravity: number): void;

  toggleDrawer(drawerGravity: number): void;

  setDrawerGestureBlocker(gestureBlocker: number): void;

  isDrawersVisible(): boolean;

  setNavCheckedItem(resId: number): void;

  showTipById(id: number, length: number): void;

  showTip(message: string, length: number): void;

  /** 上游 `AppHelper.hideSoftInput(activity)`。 */
  hideSoftInput(): void;

  /** 上游 `AppHelper.showSoftInput(activity, view, true)`。 */
  showSoftInput(view: GLView): void;
}

/**
 * `com.hippo.ehviewer.ui.scene.BaseScene` 的 ArkTS 等价实现。
 *
 * 所有 EhViewer 场景的基类。上游 284 行分三类：
 * 1. **宿主转发**（14 个方法）→ 本实现的 `SceneHost` 接口 + null 静默降级
 * 2. **抽屉视图生命周期**（`createDrawerView`/`destroyDrawerView`/状态保存）
 * 3. **主题上下文**（`createThemeContext`/`getEHContext`/`getResources2`）
 *
 * ## 平台差异（逐条登记）
 * | 上游 | 本实现 | 原因 |
 * |---|---|---|
 * | `activity instanceof MainActivity` → 直调 | `SceneHost` 接口 + `bindSceneHost()` | ArkTS 无跨类型收窄；页面不是 Activity（D-051） |
 * | `AppHelper.hideSoftInput/showSoftInput` | `SceneHost.hideSoftInput/showSoftInput` | `AppHelper` 未移植；焦点管理属宿主 |
 * | `ContextThemeWrapper` + `createThemeContext(style)` | 只保存 `mThemeStyle` 并暴露 | Stage 模型不支持页面级换主题（D-051） |
 * | `getResources2()` → `Resources` | 返回 `null`（调用方判空） | ArkTS 无 `Resources`；资源访问走 `$r()`/`resourceManager` |
 * | `LayoutInflater` + `onCreateView2` | **不移植** | ArkUI 用声明式 `build()`，没有 inflater 概念 |
 * | `SparseArray<Parcelable>` | `Map<number, Parcelable>`（`SparseArrayParcelable`） | ArkTS 无 SparseArray |
 *
 * ## 保留的上游语义（容易被"顺手改掉"的三处）
 * 1. `needShowLeftDrawer()` 决定抽屉**锁定还是解锁**（不是"显示/隐藏"）：
 *    `true` → `LOCK_MODE_UNLOCKED`，`false` → `LOCK_MODE_LOCKED_CLOSED`
 * 2. `onSceneViewCreated` 里**先**锁抽屉、**再**设导航选中项、**最后**收软键盘（顺序影响可见跳变）
 * 3. `destroyDrawerView()` **先**保存状态再置 null（顺序反了会丢状态）
 */
export abstract class BaseScene extends SceneFragment {
  static readonly LENGTH_SHORT: number = 0;
  static readonly LENGTH_LONG: number = 1;

  static readonly KEY_DRAWER_VIEW_STATE: string =
    'com.hippo.ehviewer.ui.scene.BaseScene:DRAWER_VIEW_STATE';

  /** 抽屉锁定模式（等价上游 `DrawerLayout.LOCK_MODE_*`）。 */
  static readonly LOCK_MODE_UNLOCKED: number = 0;
  static readonly LOCK_MODE_LOCKED_CLOSED: number = 1;

  /** 等价上游 `Gravity.LEFT` / `Gravity.RIGHT`（只用到左右两条边）。 */
  static readonly EDGE_LEFT: number = 3;
  static readonly EDGE_RIGHT: number = 5;

  private mSceneHost: SceneHost | null = null;

  /** 等价上游 `mThemeContext`，这里只保留 style 值（Stage 模型不支持页面级主题）。 */
  private mThemeStyle: number = 0;

  private mDrawerView: GLView | null = null;
  private mDrawerViewState: SparseArrayParcelable | null = null;

  // ==========================================================================
  // 宿主注入（替代上游的 instanceof 收窄）
  // ==========================================================================

  /** 由宿主页在场景创建后注入；传 null 表示解绑（所有能力降级为 no-op）。 */
  bindSceneHost(host: SceneHost | null): void {
    this.mSceneHost = host;
  }

  getSceneHost(): SceneHost | null {
    return this.mSceneHost;
  }

  /** 等价上游 `getActivity2()`：拿不到 MainActivity 时返回 null（子类判空）。 */
  getActivity2(): SceneHost | null {
    return this.mSceneHost;
  }

  // ==========================================================================
  // 宿主转发（上游 14 个方法，全部 null 静默降级）
  // ==========================================================================

  updateAvatar(): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.updateProfile();
    }
  }

  addAboveSnackView(view: GLView): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.addAboveSnackView(view);
    }
  }

  removeAboveSnackView(view: GLView): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.removeAboveSnackView(view);
    }
  }

  setDrawerLockMode(lockMode: number, edgeGravity: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.setDrawerLockMode(lockMode, edgeGravity);
    }
  }

  openDrawer(drawerGravity: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.openDrawer(drawerGravity);
    }
  }

  closeDrawer(drawerGravity: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.closeDrawer(drawerGravity);
    }
  }

  toggleDrawer(drawerGravity: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.toggleDrawer(drawerGravity);
    }
  }

  setDrawerGestureBlocker(gestureBlocker: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.setDrawerGestureBlocker(gestureBlocker);
    }
  }

  isDrawersVisible(): boolean {
    const host = this.mSceneHost;
    return host !== null ? host.isDrawersVisible() : false;
  }

  /** `resId = 0` 表示清除选中（上游注释）。 */
  setNavCheckedItem(resId: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.setNavCheckedItem(resId);
    }
  }

  showTipById(id: number, length: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.showTipById(id, length);
    }
  }

  showTip(message: string, length: number): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.showTip(message, length);
    }
  }

  hideSoftInput(): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.hideSoftInput();
    }
  }

  showSoftInput(view: GLView): void {
    const host = this.mSceneHost;
    if (host !== null) {
      host.showSoftInput(view);
    }
  }

  // ==========================================================================
  // 子类钩子
  // ==========================================================================

  /** 是否允许左抽屉被手势拉出（**不是**"是否显示"）。子类可覆写。 */
  needShowLeftDrawer(): boolean {
    return true;
  }

  getNavCheckedItem(): number {
    return 0;
  }

  /** 子类覆写以提供抽屉内容视图。 */
  onCreateDrawerView(args: SceneArgs | null): GLView | null {
    return null;
  }

  /** 抽屉视图销毁回调（上游空实现）。 */
  onDestroyDrawerView(): void {
  }

  /** 上游 `setTagList(UserTagList)` 空钩子；类型待 S0067 落地后替换。 */
  setTagList(result: UserTagListLike | null): void {
  }

  // ==========================================================================
  // 抽屉视图生命周期（上游 final 方法）
  // ==========================================================================

  /** 创建抽屉视图并恢复层级状态（上游 `final`）。 */
  createDrawerView(args: SceneArgs | null): GLView | null {
    this.mDrawerView = this.onCreateDrawerView(args);

    const view = this.mDrawerView;
    if (view !== null) {
      let saved = this.mDrawerViewState;
      if (saved === null && args !== null) {
        saved = BaseScene.readDrawerViewState(args);
      }
      if (saved !== null) {
        view.restoreHierarchyState(saved);
      }
    }

    return this.mDrawerView;
  }

  /** 保存并销毁抽屉视图（上游 `final`）：**先存状态再置 null**。 */
  destroyDrawerView(): void {
    const view = this.mDrawerView;
    if (view !== null) {
      const state: SparseArrayParcelable = new Map<number, Parcelable>();
      view.saveHierarchyState(state);
      this.mDrawerViewState = state;
    }

    this.onDestroyDrawerView();

    this.mDrawerView = null;
  }

  /** 诊断/子类访问：当前抽屉视图。 */
  getDrawerView(): GLView | null {
    return this.mDrawerView;
  }

  // ==========================================================================
  // 主题上下文（平台受限，见类注释）
  // ==========================================================================

  createThemeContext(style: number): void {
    this.mThemeStyle = style;
  }

  destroyThemeContext(): void {
    this.mThemeStyle = 0;
  }

  /** 等价上游 `getEHContext()`：这里只反映"是否已设置主题样式"。 */
  hasThemeContext(): boolean {
    return this.mThemeStyle !== 0;
  }

  getThemeStyle(): number {
    return this.mThemeStyle;
  }

  /**
   * 上游返回 `Resources`，供 `getString`/`getDimension` 等使用。
   * ArkTS 里资源访问走 `$r()` / `resourceManager`，**不提供该入口**（返回 null 让调用方判空）。
   */
  getResources2(): Object | null {
    return null;
  }

  // ==========================================================================
  // 生命周期
  // ==========================================================================

  /**
   * 等价上游 `onViewCreated` 的三步（**顺序不能换**）：
   * 1. 按 `needShowLeftDrawer()` 锁/解锁左抽屉
   * 2. 设置导航选中项
   * 3. 收起软键盘
   */
  onSceneViewCreated(): void {
    super.onSceneViewCreated();

    if (this.needShowLeftDrawer()) {
      this.setDrawerLockMode(BaseScene.LOCK_MODE_UNLOCKED, BaseScene.EDGE_LEFT);
    } else {
      this.setDrawerLockMode(BaseScene.LOCK_MODE_LOCKED_CLOSED, BaseScene.EDGE_LEFT);
    }

    this.setNavCheckedItem(this.getNavCheckedItem());

    this.hideSoftInput();
  }

  /** 等价上游 `onResume`：上报场景可见（埋点）。 */
  onSceneResume(): void {
    Analytics.onSceneView(this.getSceneName());
  }

  /** 等价上游 `onSaveInstanceState`：把抽屉状态塞进场景参数。 */
  onSaveSceneState(outState: SceneArgs): void {
    const view = this.mDrawerView;
    if (view !== null) {
      const state: SparseArrayParcelable = new Map<number, Parcelable>();
      view.saveHierarchyState(state);
      this.mDrawerViewState = state;
      BaseScene.writeDrawerViewState(outState, state);
    }
  }

  // ==========================================================================
  // 场景参数里的抽屉状态（上游是 Bundle.putSparseParcelableArray）
  // ==========================================================================

  /** `SceneArgs` 是 `Map<string, Object>`（等价 Bundle），所以抽屉状态按 Object 存取再收窄。 */
  private static readDrawerViewState(args: SceneArgs): SparseArrayParcelable | null {
    const raw = args.get(BaseScene.KEY_DRAWER_VIEW_STATE);
    if (raw === undefined || raw === null) {
      return null;
    }
    return raw as SparseArrayParcelable;
  }

  private static writeDrawerViewState(args: SceneArgs, state: SparseArrayParcelable): void {
    args.set(BaseScene.KEY_DRAWER_VIEW_STATE, state);
  }
}
