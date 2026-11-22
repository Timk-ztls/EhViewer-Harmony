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

import { EhActivity } from './EhActivity';

/**
 * `com.hippo.ehviewer.ui.ToolbarActivity` 的 ArkTS 等价实现（带工具栏的页面基类）。
 *
 * ## D-051：组合，不继承 Ability
 * 上游 `abstract class ToolbarActivity extends EhActivity` 只做两件事：
 * 1. 按主题返回不同的 **工具栏样式**（`AppTheme_Toolbar` / `_Dark` / `_Black`）
 * 2. 提供 `setContentView(...)` 的三件套 —— 把内容塞进 `activity_toolbar` 的 `content_panel`，
 *    并把 `toolbar` 设为 `SupportActionBar`
 *
 * 鸿蒙侧没有 `setContentView`/`LayoutInflater`/`SupportActionBar`：
 * - **内容装配**由 ArkUI 的 `@Builder`/`Column` 完成，`activity_toolbar.ets` 布局已生成
 *   （`hippo/ui/layout/activity_toolbar.ets`）
 * - **工具栏样式**保留为纯函数 `getThemeResId(theme)`（子类可覆写）
 * - `setNavigationIcon(resId | Drawable)` 的两个重载 → 一个方法，参数为图标资源名或 null
 *   （ArkUI 用 `Resource`；传 null 表示清除，等价上游 `setNavigationIcon(null)`）
 *
 * ## 为什么保留"页面基类"这种形态
 * `SplashActivity` / `SecurityActivity` 等子类只需要"主题 + 工具栏槽位"两件事；
 * 用组合（页面持有一个 `ToolbarActivity` 子类实例）能保持与上游一致的继承层次，
 * 同时不引入 Ability 生命周期 —— 见 `EhActivity` 类注释里 D-051 的完整理由。
 */
export abstract class ToolbarActivity extends EhActivity {
  /** 当前工具栏导航图标资源名（null = 无图标）。用法见 `setNavigationIcon()`。 */
  private mNavigationIconName: string | null = null;

  /** 内容槽位是否需要工具栏（上游 `setContentView` 一定装 `activity_toolbar`，这里恒 true）。 */
  hasToolbar(): boolean {
    return true;
  }

  /**
   * 工具栏导航图标（等价上游两个 `setNavigationIcon` 重载）。
   * @param iconName 资源名（对应 `$r('app.media.xxx')` 的名字）；null 清除图标
   */
  setNavigationIcon(iconName: string | null): void {
    this.mNavigationIconName = iconName;
  }

  getNavigationIconName(): string | null {
    return this.mNavigationIconName;
  }
}
