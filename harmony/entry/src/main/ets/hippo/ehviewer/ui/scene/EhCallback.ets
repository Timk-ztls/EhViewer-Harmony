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
import { StageActivity } from '../../../scene/StageActivity';
import { EhApplication } from '../../EhApplication';

const TAG = 'EhCallback';
const DOMAIN = 0x0000;

/**
 * 场景回调查找能力（**只声明 `EhCallback` 实际用到的两个方法**）。
 *
 * 上游：
 * ```java
 * StageActivity activity = mApplication.findStageActivityById(mStageId);
 * SceneFragment scene = stage.findSceneByTag(mSceneTag);
 * ```
 * `EhApplication` 的 `findStageActivityById` 目前在 ArkTS 侧**没有实现**
 * （`EhApplication.ets` 只有 globalStuff/tempCache 两组），
 * 而 `StageActivity.findSceneByTag` 有。所以把"按 id 找 Stage"这一点抽成接口注入 ——
 * 当 `EhApplication` 补上该方法时，实现一个 3 行适配器即可。
 */
export interface StageLookupHost {
  /** 等价上游 `EhApplication.findStageActivityById(int)`。 */
  findStageActivityById(stageId: number): StageActivity | null;
}

/**
 * 提示能力（**窄接口**）。
 *
 * 上游 `showTip` 分两支：宿主是 `MainActivity` 时走它的 Snackbar，否则 `Toast`。
 * 鸿蒙侧两者都是"宿主能力的两种实现"，所以只声明"按资源 id 提示"与"按文本提示"两条，
 * 由宿主决定用 SnackBar / prompt。
 */
export interface TipHost {
  showTipById(id: number, length: number): void;

  showTipByText(message: string, length: number): void;
}

/** 回调基类需要的最小网络回调形状（`EhClient.Callback<T>` 的两个方法）。 */
export interface EhCallbackLike<T> {
  onSuccess(result: T): void;

  onFailure(e: Error): void;
}

/**
 * `com.hippo.ehviewer.ui.scene.EhCallback` 的 ArkTS 等价实现。
 *
 * 一个"绑定了发起场景"的网络回调基类：请求回来时先按 `(stageId, sceneTag)` 找回场景，
 * 确认它还在（`isInstance`）才派发，避免向已销毁的页面回写。
 *
 * ## 平台差异（依赖倒置）
 * | 上游 | 本实现 |
 * |---|---|
 * | `(EhApplication) context.getApplicationContext()` | `EhApplication.getInstance()`（可能为 null → 明确失败） |
 * | `mApplication.findStageActivityById(mStageId)` | `StageLookupHost` 接口（`EhApplication` 待补该方法） |
 * | `getStageActivity() instanceof MainActivity` → `showTip` | `TipHost` 接口（由宿主注入） |
 * | `Toast.makeText(...)` | `TipHost.showTipById / showTipByText` |
 * | `isInstance(SceneFragment)` 泛型收窄 `(E)` | 抽象方法 `isInstance(scene): boolean` + `asInstance()` 返回 `SceneFragment \| null`（ArkTS 无泛型强制转换） |
 *
 * ## 一个必须保留的行为
 * `getScene()` 在**任何**一步为空时都返回 null（stage 没了 / tag 找不到 / `isInstance` 为假），
 * **不抛错**。子类回调里普遍是 `SceneFragment scene = getScene(); if (scene != null) {...}`，
 * 抛错会让"页面已关闭"这种正常情况变成崩溃。
 */
export abstract class EhCallback<E extends SceneFragment, T> implements EhCallbackLike<T> {
  /** 与 `BaseScene.LENGTH_SHORT/LONG` 同值（避免循环依赖 `BaseScene`）。 */
  static readonly LENGTH_SHORT: number = 0;
  static readonly LENGTH_LONG: number = 1;

  private static sStageLookupHost: StageLookupHost | null = null;
  private static sTipHost: TipHost | null = null;

  /** 注入"按 id 找 Stage"的能力（`EhApplication.findStageActivityById` 落地后接一次）。 */
  static setStageLookupHost(host: StageLookupHost | null): void {
    EhCallback.sStageLookupHost = host;
  }

  /** 注入提示能力。 */
  static setTipHost(host: TipHost | null): void {
    EhCallback.sTipHost = host;
  }

  private readonly mStageId: number;
  private readonly mSceneTag: string;

  constructor(stageId: number, sceneTag: string) {
    this.mStageId = stageId;
    this.mSceneTag = sceneTag;
  }

  /** 判断找回来的场景是不是"我"要的那个（上游泛型收窄）。 */
  abstract isInstance(scene: SceneFragment): boolean;

  /** 上游 `getApplication()`。 */
  getApplication(): EhApplication | null {
    return EhApplication.getInstance();
  }

  /** 上游 `getStageActivity()`。 */
  getStageActivity(): StageActivity | null {
    const host = EhCallback.sStageLookupHost;
    if (host === null) {
      hilog.warn(DOMAIN, TAG, 'StageLookupHost not injected, cannot find stage %{public}d',
        this.mStageId);
      return null;
    }
    return host.findStageActivityById(this.mStageId);
  }

  /**
   * 找回发起场景（**任一步为空都返回 null，不抛错**）。
   * 子类用 `asScene()` 拿到具体类型。
   */
  getScene(): SceneFragment | null {
    const stage = this.getStageActivity();
    if (stage === null) {
      return null;
    }
    const scene = stage.findSceneByTag(this.mSceneTag);
    if (scene === null) {
      return null;
    }
    return this.isInstance(scene) ? scene : null;
  }

  /** 上游 `(E) scene` 的显式收窄（ArkTS 无泛型强转，由调用方断言）。 */
  getSceneAs(): E | null {
    return this.getScene() as E | null;
  }

  /** 上游 `getContent()`：优先宿主页面，拿不到时退回 Application（可能同为 null）。 */
  getContent(): StageActivity | EhApplication | null {
    const stage = this.getStageActivity();
    if (stage !== null) {
      return stage;
    }
    return this.getApplication();
  }

  getStageId(): number {
    return this.mStageId;
  }

  getSceneTag(): string {
    return this.mSceneTag;
  }

  // ---------- 提示 ----------

  showTipById(id: number, length: number): void {
    const host = EhCallback.sTipHost;
    if (host === null) {
      hilog.warn(DOMAIN, TAG, 'TipHost not injected, tip %{public}d dropped', id);
      return;
    }
    host.showTipById(id, length);
  }

  showTip(message: string, length: number): void {
    const host = EhCallback.sTipHost;
    if (host === null) {
      hilog.warn(DOMAIN, TAG, 'TipHost not injected, tip dropped: %{public}s', message);
      return;
    }
    host.showTipByText(message, length);
  }

  // ---------- 子类必须实现 ----------

  abstract onSuccess(result: T): void;

  abstract onFailure(e: Error): void;
}
