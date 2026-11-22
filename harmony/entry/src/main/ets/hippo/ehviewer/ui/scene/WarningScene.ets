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

import { SolidScene } from './SolidScene';

/**
 * `com.hippo.ehviewer.ui.scene.WarningScene` 的 ArkTS 等价实现（安全警告）。
 *
 * 上游 69 行，全部逻辑就两件事：
 * 1. **拒绝** → `finishStage()`（直接结束整个 Stage，不给任何回退机会 —— 这是"安全检查"的语义）
 * 2. **接受** → `putShowWarning(false)` + 继续下一检查步 + `finish()`
 *
 * ## 平台差异（按项目既有约定：场景类是纯逻辑，布局由 `@Component struct` 承担）
 * | 上游 | 本实现 |
 * |---|---|
 * | `inflater.inflate(R.layout.scene_warning)` + `ViewUtils.$$(view, R.id.reject/accept)` | 不移植；`SceneWarningLayout` 已生成，含 `@Prop accept/reject` |
 * | `View.OnClickListener` + `v == mReject` 比较 | `onReject()` / `onAccept()` 两个显式方法（ArkUI 没有 `View` 身份比较） |
 * | `onDestroyView()` 置 null | 不需要（没有 View 引用） |
 * | `MainActivity activity = getActivity2(); if (null != activity)` | `getActivity2()` 返回 `SceneHost \| null`（D-052），结构与上游一致 |
 *
 * ## 一个容易改错的地方
 * `onAccept()` 里 `startSceneForCheckStep(CHECK_STEP_WARNING, ...)` —— 传的是
 * **下一个**步骤（`CHECK_STEP_WARNING` 而非 `CHECK_STEP_SECURITY`）。因为"安全警告"这一步
 * 已经通过，链要继续从"埋点询问"开始。上游如此，照搬。
 */
export class WarningScene extends SolidScene {
  getSceneName(): string {
    return 'WarningScene';
  }

  /** 安全警告页**不允许**抽屉（否则可绕过检查）。 */
  needShowLeftDrawer(): boolean {
    return false;
  }

  /** 用户点「拒绝」：结束整个 Stage（上游 `finishStage()`）。 */
  onReject(): void {
    this.finishStage();
  }

  /** 用户点「接受」：记住不再提示，继续检查链，然后关闭自身。 */
  onAccept(): void {
    // Never show this warning anymore
    this.settings().putShowWarning(false);

    // Start new scene and finish it self
    const host = this.getActivity2();
    if (host !== null) {
      this.startSceneForCheckStep(SolidScene.CHECK_STEP_WARNING, this.getArguments());
    }
    this.finish();
  }
}
