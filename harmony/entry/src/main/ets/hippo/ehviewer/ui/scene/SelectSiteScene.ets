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
import { EhUrl } from '../../client/EhUrl';

/**
 * `com.hippo.ehviewer.ui.scene.SelectSiteScene` 的 ArkTS 等价实现（站点选择）。
 *
 * 上游 79 行：两个单选（E / EX）+ 一个「确定」。
 * - 选 E  → `putSelectSite(false)` + `putGallerySite(SITE_E)` → 继续下一检查步 → `finish()`
 * - 选 EX → 同上，站点改 `SITE_EX`
 * - 未选 → 弹提示「未选择」（**不关闭页面**，让用户重选）
 *
 * ## 平台差异
 * | 上游 | 本实现 |
 * |---|---|
 * | `RadioGroup.getCheckedRadioButtonId()` + `switch (R.id.site_e/site_ex)` | `onOk(checkedRadioButtonId)`，id 用 `SITE_E_VIEW_ID`/`SITE_EX_VIEW_ID` 常量 |
 * | `Toast.makeText(...R.string.no_select...)` | `showTipById(...)` → `SceneHost`（D-052）；宿主未接线时只打 warn |
 * | `getActivity2() == null` 时**整体 return** | 照搬：拿不到宿主就什么都不做（不写设置、不前进） |
 *
 * ## 注意：`getActivity2() == null` 的 early-return 被**保留**
 * 上游是先判 `activity == null || mRadioGroup == null` 就直接 return —— 也就是说
 * **宿主不在时连设置都不写**。这不是防御性编程，而是有意的：站点选择必须有归属页面，
 * 否则"写进去了但没界面反馈"。照搬。
 */
export class SelectSiteScene extends SolidScene {
  /** 等价上游 `R.id.site_e` / `R.id.site_ex`（ArkUI 无资源 id，用稳定的字符串常量）。 */
  static readonly SITE_E_VIEW_ID: string = 'site_e';
  static readonly SITE_EX_VIEW_ID: string = 'site_ex';

  getSceneName(): string {
    return 'SelectSiteScene';
  }

  needShowLeftDrawer(): boolean {
    return false;
  }

  /** 当前已选站点（供布局初始化单选状态；上游由 RadioGroup 自己维护）。 */
  getCheckedSite(): number {
    return this.settings().getGallerySite();
  }

  /**
   * 用户点「确定」。
   * @param checkedId 布局里被选中的 RadioButton id（`SITE_E_VIEW_ID` / `SITE_EX_VIEW_ID` / 其它=未选）
   */
  onOk(checkedId: string | null): void {
    const host = this.getActivity2();
    if (host === null) {
      return;
    }

    if (checkedId === SelectSiteScene.SITE_E_VIEW_ID) {
      this.settings().putSelectSite(false);
      this.settings().putGallerySite(EhUrl.SITE_E);
      this.startSceneForCheckStep(SolidScene.CHECK_STEP_SELECT_SITE, this.getArguments());
      this.finish();
      return;
    }

    if (checkedId === SelectSiteScene.SITE_EX_VIEW_ID) {
      this.settings().putSelectSite(false);
      this.settings().putGallerySite(EhUrl.SITE_EX);
      this.startSceneForCheckStep(SolidScene.CHECK_STEP_SELECT_SITE, this.getArguments());
      this.finish();
      return;
    }

    // default: 没选站点 → 提示，不前进（上游 Toast(LENGTH_SHORT)）
    this.showTipById(SelectSiteScene.NO_SELECT_TIP_ID, SolidScene.LENGTH_SHORT);
  }

  /** 等价 `R.string.no_select` 的资源 id（布局/宿主负责映射成真实文案）。 */
  static readonly NO_SELECT_TIP_ID: number = 0;
}
