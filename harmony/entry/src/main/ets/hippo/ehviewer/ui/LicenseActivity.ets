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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/LicenseActivity.java（51 行）。
 *
 * ============================================================================
 * 一、上游做什么
 * ============================================================================
 *   ```java
 *   onCreate:  mWebView = new WebView(this);
 *              mWebView.loadUrl("file:///android_asset/open_source_licenses.html");
 *              setContentView(mWebView);
 *              setNavigationIcon(R.drawable.v_arrow_left_dark_x24);
 *   onDestroy: if (mWebView != null) { mWebView.destroy(); mWebView = null; }
 *   onOptionsItemSelected: case android.R.id.home: finish(); return true;
 *   ```
 *
 * 三个要点（都不该在移植时丢）：
 *   1. 内容是**打包内的 HTML 资源**（`assets/open_source_licenses.html`），不是网络页；
 *   2. 左上角是**返回箭头**（`v_arrow_left_dark_x24`），点它等于 finish；
 *   3. `onDestroy` **必须释放 WebView**（上游显式 destroy + 置 null）。
 *
 * ============================================================================
 * 二、ArkTS 侧对应 + 一个必须记录的交付缺口
 * ============================================================================
 * - 页面本体：ArkUI `Web({ src: $rawfile('open_source_licenses.html') })`（组件层职责）。
 * - 返回：`router.back()`（对应上游 `finish()`）。
 * - 释放：`Web` 组件由框架管理生命周期，**没有** `destroy()`；`onDisappear` 里 `controller.stop()` 即可。
 *
 * ⚠️ **资产缺口（上游仓库里没有这个文件）**：
 *   `open_source_licenses.html` **不在上游 Git 仓库中** —— 它由 Android 的
 *   OSS-Licenses Gradle 插件在构建期生成到 `app/src/main/assets/`。
 *   本仓库（`origin/upstream`）的 `app/src/main/assets/` 里只有 `requestOverride.js`，
 *   所以**无法从上游直接拷这个 html**。
 *
 *   本文件因此只提供"页面契约"（资源名 + 内容类型 + 释放语义），
 *   html 本身需要由项目侧生成（列出实际引入的第三方依赖），或从 Android 构建产物里取一份。
 *   —— 这一条已在 notes 里写明，交付时不要把"契约已移植"说成"许可证页已可用"。
 */

/**
 * 开源许可证页的页面契约（对位上游 `LicenseActivity`）。
 */
export class LicenseActivity {
  /**
   * 许可证页的资源相对路径（上游 `file:///android_asset/open_source_licenses.html`）。
   *
   * ArkUI 侧用 `$rawfile('open_source_licenses.html')` 取，文件应放在
   * `harmony/entry/src/main/resources/rawfile/open_source_licenses.html`。
   */
  public static readonly ASSET_PATH: string = 'open_source_licenses.html';

  /**
   * 内容是**本地打包资源**（不是 URL）—— 上游用 `loadUrl("file:///android_asset/…")`，
   * 语义上等价于 ArkUI 的 `$rawfile`。保留这个判定，避免有人误改成 `loadUrl(http…)`。
   */
  static isLocalAsset(url: string): boolean {
    if (url.length === 0) {
      return false;
    }
    return url.startsWith('file:///android_asset/') || url.startsWith('$rawfile:');
  }

  /**
   * 构建期生成的说明：该 html 属于**构建产物**，不在源码仓库里。
   *
   * 用途：调用方/检查脚本据此判断"页打不开"是资产缺失还是路径写错。
   */
  static describeAssetSource(): string {
    return 'open_source_licenses.html 由 Android OSS-Licenses Gradle 插件在构建期生成，' +
      '不在上游 Git 仓库内（app/src/main/assets/ 只有 requestOverride.js）；' +
      '鸿蒙侧需自行生成并放入 resources/rawfile/。';
  }
}
