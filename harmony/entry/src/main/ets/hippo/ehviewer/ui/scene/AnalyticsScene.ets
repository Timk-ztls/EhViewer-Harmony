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
import { Analytics } from '../../Analytics';

/**
 * `com.hippo.ehviewer.ui.scene.AnalyticsScene` 的 ArkTS 等价实现（埋点授权询问）。
 *
 * 上游 81 行：
 * - 「拒绝」→ `putEnableAnalytics(false)`
 * - 「接受」→ `putEnableAnalytics(true)` + `Analytics.start(context)`
 * - **无论选哪个**都 `putAskAnalytics(false)`（问过一次就不再问 —— 这是关键，
 *   漏了会导致每次启动都弹这个页面）
 * - 然后继续下一检查步 + `finish()`
 *
 * ## 平台差异
 * | 上游 | 本实现 |
 * |---|---|
 * | `inflate(R.layout.scene_analytics)` + 取 `reject/accept/text` | 不移植；`SceneAnalyticsLayout` 已生成（`@Prop accept/reject`） |
 * | `text.setText(Html.fromHtml(getString(R.string.analytics_explain)))` + `LinkMovementMethod2` | **不移植**：ArkUI 用 `Text` 的富文本能力渲染，场景只提供文案来源 |
 * | `v == mReject` 比较 | `onReject()` / `onAccept()` |
 * | `Context context = getEHContext(); if (null == context) return;` | `getActivity2()` 判空（D-052）；**注意上游这个 early-return 会让「已询问」标记也不写**，照搬 |
 *
 * ## 上游 `onClick` 里那个 early-return 的后果（照搬，但要写明）
 * ```java
 * Context context = getEHContext();
 * if (null == context) { return; }      // ← 后面 putAskAnalytics(false) 全被跳过
 * ```
 * 即：**拿不到 context 时，"已询问"标记不会写入**，下次启动会再问。
 * 这看起来像 bug，但改掉会改变"何时停止询问"的行为；按 1:1 口径保留，并在验收时确认
 * 鸿蒙侧 `getActivity2()` 在正常路径上确实非 null（否则会无限询问）。
 */
export class AnalyticsScene extends SolidScene {
  getSceneName(): string {
    return 'AnalyticsScene';
  }

  needShowLeftDrawer(): boolean {
    return false;
  }

  /** 说明文案的字符串资源 id（上游 `R.string.analytics_explain`，含 HTML）。 */
  static readonly ANALYTICS_EXPLAIN_RES_ID: number = 0;

  /** 供布局取文案用（上游是 `getString(R.string.analytics_explain)`）。 */
  getExplainResId(): number {
    return AnalyticsScene.ANALYTICS_EXPLAIN_RES_ID;
  }

  /** 用户点「拒绝」：关闭埋点，记「已询问」，继续链。 */
  onReject(): void {
    const host = this.getActivity2();
    if (host === null) {
      return;
    }
    this.settings().putEnableAnalytics(false);
    this.settings().putAskAnalytics(false);

    this.startSceneForCheckStep(SolidScene.CHECK_STEP_ANALYTICS, this.getArguments());
    this.finish();
  }

  /** 用户点「接受」：开启埋点并启动，记「已询问」，继续链。 */
  onAccept(): void {
    const host = this.getActivity2();
    if (host === null) {
      return;
    }
    this.settings().putEnableAnalytics(true);
    Analytics.start(host);

    this.settings().putAskAnalytics(false);

    this.startSceneForCheckStep(SolidScene.CHECK_STEP_ANALYTICS, this.getArguments());
    this.finish();
  }
}
