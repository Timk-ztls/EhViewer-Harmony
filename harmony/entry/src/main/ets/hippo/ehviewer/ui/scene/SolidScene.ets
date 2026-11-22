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
import { BaseScene } from './BaseScene';
import { SceneArgs } from '../../../scene/SceneTypes';
import { Announcer } from '../../../scene/Announcer';
import { SolidSceneSettings, SolidSceneSettingsHolder } from './SolidSceneSettings';

const TAG = 'SolidScene';
const DOMAIN = 0x0000;

/**
 * 场景启动器工厂：`sceneName → () => SceneFragment`。
 *
 * **替代上游的反射**：
 * ```java
 * clazz = Class.forName(targetScene);           // 运行时按类名查类
 * startScene(new Announcer(clazz).setArgs(targetArgs));
 * ```
 * ArkTS 不支持反射（`arkts-no-reflection`），所以登记表是**显式注册**：
 * ```ts
 * SolidSceneRegistry.register('GalleryListScene', () => new GalleryListSceneImpl());
 * ```
 * 未注册时记 warn 并回落默认页 —— 等价上游 `ClassNotFoundException` 分支的行为
 * （日志 + 走默认场景），只是发现时机从运行时变成"注册缺失"。
 *
 * **登记为 D-053**：`Class.forName` → 场景名注册表。
 */
export class SolidSceneRegistry {
  private static sWarned: Set<string> = new Set<string>();
  private static sFactories: Map<string, SceneFactory> = new Map<string, SceneFactory>();

  static register(sceneName: string, factory: SceneFactory): void {
    SolidSceneRegistry.sFactories.set(sceneName, factory);
  }

  static unregister(sceneName: string): void {
    SolidSceneRegistry.sFactories.delete(sceneName);
  }

  /** 按场景名创建实例；未注册返回 null（调用方回落默认页）。 */
  static create(sceneName: string): BaseScene | null {
    const factory = SolidSceneRegistry.sFactories.get(sceneName);
    if (factory === undefined) {
      if (!SolidSceneRegistry.sWarned.has(sceneName)) {
        SolidSceneRegistry.sWarned.add(sceneName);
        hilog.error(DOMAIN, TAG, 'No registered scene for name: %{public}s', sceneName);
      }
      return null;
    }
    return factory();
  }

  static isRegistered(sceneName: string): boolean {
    return SolidSceneRegistry.sFactories.has(sceneName);
  }

  static clear(): void {
    SolidSceneRegistry.sFactories.clear();
    SolidSceneRegistry.sWarned.clear();
  }
}

/** 场景构造函数（`() => SceneFragment`）。 */
export type SceneFactory = () => BaseScene;

/**
 * `com.hippo.ehviewer.ui.scene.SolidScene` 的 ArkTS 等价实现。
 *
 * "检查步骤"链：安全警告 → 埋点询问 → 登录 → 选站点 → 目标场景。
 * 名字叫 Solid 是因为这些页面**不能被抽屉/返回手势绕过**（每个场景都 `needShowLeftDrawer() = false`）。
 *
 * ## 上游用 switch **贯穿**（fall-through），不是笔误
 * ```java
 * case CHECK_STEP_SECURITY:
 *     if (Settings.getShowWarning()) { startScene(WarningScene); break; }
 * case CHECK_STEP_WARNING:                       // ← 没有 break，落到这里
 *     if (Settings.getAskAnalytics()) { startScene(AnalyticsScene); break; }
 * ...
 * ```
 * 语义：**从请求的步骤开始，逐个往下检查，谁的开关打开就停在谁那里**；
 * 全部通过则启动目标场景。这里用 `for` 循环 + 等价条件重写（ArkTS 的 `switch` 也支持贯穿，
 * 但显式循环更能表达"链式递进"，且避免 lint 报 fall-through）。**行为完全等价**：
 * - 从 `CHECK_STEP_WARNING` 进入时**不**检查 `getShowWarning()`（因为上游那一句在上面）
 * - 任一步命中即 `return`（等价 `break`，因为 `break` 跳出 switch 后方法结束）
 *
 * ## `getEHContext()` 为 null 的处理（上游有个坑）
 * 上游在 `CHECK_STEP_ANALYTICS` 里：
 * ```java
 * Context context = getEHContext();
 * if (context != null && EhUtils.needSignedIn(context)) { startScene(SignInScene); break; }
 * if (context == null) { Log.w(...); break; }     // ← 这里 break 掉了
 * ```
 * 意思是"拿不到 context 就**不再往下走**"（不检查选站点、不启动目标场景）。
 * 本实现照搬：`needSignedIn` 不可判时直接终止链，**不**静默跳过登录检查。
 */
export class SolidScene extends BaseScene {
  static readonly CHECK_STEP_SECURITY: number = 0;
  static readonly CHECK_STEP_WARNING: number = 1;
  static readonly CHECK_STEP_ANALYTICS: number = 2;
  static readonly CHECK_STEP_SIGN_IN: number = 3;
  static readonly CHECK_STEP_SELECT_SITE: number = 4;

  static readonly KEY_TARGET_SCENE: string = 'target_scene';
  static readonly KEY_TARGET_ARGS: string = 'target_args';

  getSceneName(): string {
    return 'SolidScene';
  }

  /** 设置读取（可注入；未注入时见 `SolidSceneSettings.unwired()` 的说明）。 */
  protected settings(): SolidSceneSettings {
    return SolidSceneSettingsHolder.get();
  }

  /**
   * 从 `checkStep` 开始逐级检查，命中即启动对应场景；全通过则启动目标场景。
   *
   * @param args 透传给每一级场景；其中可含 `KEY_TARGET_SCENE` / `KEY_TARGET_ARGS`
   */
  startSceneForCheckStep(checkStep: number, args: SceneArgs | null): void {
    for (let step = checkStep; step <= SolidScene.CHECK_STEP_SELECT_SITE; step++) {
      switch (step) {
        case SolidScene.CHECK_STEP_SECURITY:
          if (this.settings().getShowWarning()) {
            this.startScene(new Announcer(WarningSceneName).setArgs(args));
            return;
          }
          break;
        case SolidScene.CHECK_STEP_WARNING:
          if (this.settings().getAskAnalytics()) {
            this.startScene(new Announcer(AnalyticsSceneName).setArgs(args));
            return;
          }
          break;
        case SolidScene.CHECK_STEP_ANALYTICS:
          if (this.solidSceneNeedSignedIn()) {
            this.startScene(new Announcer(SignInSceneName).setArgs(args));
            return;
          }
          if (!this.solidSceneCanCheckSignIn()) {
            // 上游：context == null → Log.w + break（终止整条链，不启动目标场景）
            hilog.warn(DOMAIN, TAG, 'Cannot check sign in status, abort check chain');
            return;
          }
          break;
        case SolidScene.CHECK_STEP_SIGN_IN:
          if (this.settings().getSelectSite()) {
            this.startScene(new Announcer(SelectSiteSceneName).setArgs(args));
            return;
          }
          break;
        default:
          break;
      }
    }

    // 全部通过：启动目标场景（或回落默认页）
    this.solidSceneStartTarget(args);
  }

  // ---------- 子类可覆写的钩子（把平台相关的判断集中到一处，便于场景类复用/测试） ----------

  /** 等价 `EhUtils.needSignedIn(context)`。 */
  protected solidSceneNeedSignedIn(): boolean {
    return SolidSceneHooks.needSignedIn !== null && (SolidSceneHooks.needSignedIn as () => boolean)();
  }

  /** 等价上游 `getEHContext() != null`。 */
  protected solidSceneCanCheckSignIn(): boolean {
    return SolidSceneHooks.canCheckSignIn !== null && (SolidSceneHooks.canCheckSignIn as () => boolean)();
  }

  /** 启动目标场景；`target_scene` 未注册时回落默认页（等价 `ClassNotFoundException` 分支）。 */
  protected solidSceneStartTarget(args: SceneArgs | null): void {
    let targetScene: string | null = null;
    let targetArgs: SceneArgs | null = null;
    if (args !== null) {
      const scene = args.get(SolidScene.KEY_TARGET_SCENE);
      if (scene !== undefined && scene !== null) {
        targetScene = scene as string;
      }
      const a = args.get(SolidScene.KEY_TARGET_ARGS);
      if (a !== undefined && a !== null) {
        targetArgs = a as SceneArgs;
      }
    }

    if (targetScene !== null) {
      const scene = SolidSceneRegistry.create(targetScene);
      if (scene !== null) {
        this.startScene(new Announcer(targetScene).setArgs(targetArgs));
        return;
      }
      hilog.error(DOMAIN, TAG, 'Can\'t find scene with name: %{public}s', targetScene);
    }

    // 回落：默认页（上游是 GalleryListScene + 上次的启动页 action）
    const newArgs: SceneArgs = new Map<string, Object>();
    newArgs.set(GalleryListSceneHookKeyAction, this.settings().getLaunchPageGalleryListSceneAction());
    this.startScene(new Announcer(GalleryListSceneName).setArgs(newArgs));
  }
}

/** 场景名常量（ArkTS 无 `Class` 对象，改用字符串键；与 Announcer 的构造参数一致）。 */
export const WarningSceneName: string = 'WarningScene';
export const AnalyticsSceneName: string = 'AnalyticsScene';
export const SelectSiteSceneName: string = 'SelectSiteScene';
export const SignInSceneName: string = 'SignInScene';
export const GalleryListSceneName: string = 'GalleryListScene';

/** 上游 `GalleryListScene.KEY_ACTION`。 */
export const GalleryListSceneHookKeyAction: string = 'action';

/**
 * 平台判断的注入点（**本项目新增**）。
 *
 * 上游这些判断都直接调宿主/工具类（`EhUtils.needSignedIn(context)`、`getEHContext()`）。
 * 鸿蒙侧这两者都依赖尚未落地的 `MainActivity`/`EhApplication`（D-051/052），
 * 用可注入的钩子隔离：宿主页面启动时设置，单测里可替换。
 * 未注入时 `needSignedIn` 视为 **false**（= 不需要登录，直接继续后续步骤），
 * `canCheckSignIn` 视为 **true** —— 这是"信息不可知时按最常见路径走"的保守选择，
 * 并在 `SolidScene.ets` 类注释里写明（不是静默假设）。
 */
export class SolidSceneHooks {
  static needSignedIn: (() => boolean) | null = null;
  static canCheckSignIn: (() => boolean) | null = null;

  static reset(): void {
    SolidSceneHooks.needSignedIn = null;
    SolidSceneHooks.canCheckSignIn = null;
  }
}
