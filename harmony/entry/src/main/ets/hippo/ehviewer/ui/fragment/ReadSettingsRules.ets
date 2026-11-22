/*
 * Copyright 2026 ehviewer-harmony contributors
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

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/fragment/ReadFragment.java（39 行）。
 *
 * ============================================================================
 * 一、上游做什么（39 行里只有一件事）
 * ============================================================================
 *   ```java
 *   onCreatePreferences(...) {
 *       addPreferencesFromResource(R.xml.read_settings);          // XML 膨胀 → 组件层
 *       if (!ReadingRefreshRate.isSupported()) {
 *           Preference p = findPreference(Settings.KEY_READING_REFRESH_RATE);
 *           if (p != null) {
 *               getPreferenceScreen().removePreference(p);        // ← 唯一真实行为
 *           }
 *       }
 *   }
 *   ```
 *
 * 语义重点：**设备不支持可变刷新率时，"阅读界面刷新率"这一项根本不出现**（不是置灰、不是禁用）。
 * 如果移植成"置灰"，用户在设置里会看到一个永远点不动的项 —— 与上游不同。
 *
 * ============================================================================
 * 二、ArkTS 侧
 * ============================================================================
 * `ReadingRefreshRate.isSupported()` **已 land**（`hippo/ehviewer/util/ReadingRefreshRate.ets`）。
 * 本文件只提供"这一项该不该出现"的判定，供 ArkUI 设置页在构建列表时过滤；
 * 同时把 `Settings.KEY_READING_REFRESH_RATE` 的 key 字符串单点化，避免页面上写裸字符串。
 */

import { ReadingRefreshRate } from '../../util/ReadingRefreshRate';

/**
 * 阅读设置页的判定规则（对位上游 `ReadFragment`）。
 */
export class ReadSettingsRules {
  /**
   * 「阅读界面刷新率」设置项的 key。
   *
   * 上游用 `Settings.KEY_READING_REFRESH_RATE`（`Settings.java`）；ArkTS 侧 Settings 尚未导出该常量，
   * 因此在这里单点声明 —— **若将来 Settings 导出同名常量，应改为从 Settings 引用**，
   * 保持"key 只有一处定义"（本项目在 `SPIDER_INFO_FILENAME` 上踩过两处定义漂移）。
   */
  public static readonly KEY_READING_REFRESH_RATE: string = 'reading_refresh_rate';

  /**
   * 「阅读界面刷新率」这一项是否应出现在设置页。
   *
   * 上游：`if (!ReadingRefreshRate.isSupported()) removePreference(...)` → 不支持时**移除**。
   * 返回 `false` 表示调用方**不应渲染**该项（而不是渲染成 disabled）。
   */
  static shouldShowReadingRefreshRate(): boolean {
    return ReadingRefreshRate.isSupported();
  }
}
