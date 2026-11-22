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
import { Analytics } from '../Analytics';

const TAG = 'EhActivity';
const DOMAIN = 0x0000;

/**
 * `EhActivity` / `ToolbarActivity` 需要的设置项（**本项目新增的能力接口**，D-054 扩展）。
 *
 * 上游用到的 6 项，`Settings.ets` 目前**一个都没有**（只有 `getInt/putInt` + 站点/下载路径）：
 * | 上游 | 用途 |
 * |---|---|
 * | `Settings.getTheme()` / `putTheme(int)` | 主题 |
 * | `Settings.THEME_LIGHT / DARK / BLACK` | 主题常量 |
 * | `Settings.isThemeAutoSwitchAvailable()` | 是否允许跟随系统深色 |
 * | `Settings.getAppLanguage()` | 语言（`system` 或 `zh-CN` 这类） |
 * | `Settings.getEnabledSecurity()` | 是否开启防截屏 |
 */
export interface EhActivitySettings {
  THEME_LIGHT: number;

  THEME_DARK: number;

  THEME_BLACK: number;

  getTheme(): number;

  putTheme(theme: number): void;

  isThemeAutoSwitchAvailable(): boolean;

  getAppLanguage(): string | null;

  getEnabledSecurity(): boolean;
}

/**
 * 未接线实现：**默认值取上游 `Settings.java` 的 DEFAULT_*
 * - 主题 → `THEME_LIGHT`（上游默认浅色）
 * - `isThemeAutoSwitchAvailable()` → **false**（不擅自改用户主题；上游默认也是按设置项来）
 * - `getAppLanguage()` → `'system'`（跟随系统，等价上游默认）
 * - `getEnabledSecurity()` → **false**（不擅自开防截屏；上游默认 false）
 *
 * 每项调用打 warn，理由同 `UnwiredSolidSceneSettings`：**"一直是默认值"这件事必须可见**。
 */
export class UnwiredEhActivitySettings implements EhActivitySettings {
  THEME_LIGHT: number = 0;
  THEME_DARK: number = 1;
  THEME_BLACK: number = 2;

  getTheme(): number {
    return this.THEME_LIGHT;
  }

  putTheme(theme: number): void {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: putTheme(%{public}d) dropped', theme);
  }

  isThemeAutoSwitchAvailable(): boolean {
    return false;
  }

  getAppLanguage(): string | null {
    return 'system';
  }

  getEnabledSecurity(): boolean {
    return false;
  }
}

export class EhActivitySettingsHolder {
  private static sSettings: EhActivitySettings = new UnwiredEhActivitySettings();

  static set(settings: EhActivitySettings | null): void {
    EhActivitySettingsHolder.sSettings = settings === null
      ? new UnwiredEhActivitySettings() : settings;
  }

  static get(): EhActivitySettings {
    return EhActivitySettingsHolder.sSettings;
  }

  static reset(): void {
    EhActivitySettingsHolder.sSettings = new UnwiredEhActivitySettings();
  }
}

/**
 * 页面宿主能力（只声明 `EhActivity` 实际用到的两个方法 —— 依赖倒置的关键）。
 *
 * D-051：[裁剪] 不派生 `UIAbility`。鸿蒙的 Ability 是**应用级组件**（一个 Ability 承载一个
 * `windowStage`），而 `EhActivity` 上游语义是**每页都继承的基类**；
 * 派生 Ability 会让 `SplashActivity`/`ToolbarActivity` 变成独立应用入口（各自要
 * `module.json5` 声明、各开一个新窗口），与"同进程内页面切换"完全不同。
 */
export interface PageHost {
  /**
   * 等价上游 `getWindow().setFlags(FLAG_SECURE, FLAG_SECURE)` / `clearFlags(FLAG_SECURE)`。
   * 鸿蒙对应 `window.setWindowPrivacyMode(enabled: boolean): Promise<void>`。
   */
  setWindowPrivacyMode(enabled: boolean): Promise<void>;

  /** 等价上游 `((EhApplication) getApplication()).recreate()`（主题切换后重建界面）。 */
  recreate(): void;
}

/** 页面通用的常量（上游 `Settings.THEME_*` 的兜底值，接线后以注入为准）。 */
export class EhActivityTheme {
  static readonly LIGHT: number = 0;
  static readonly DARK: number = 1;
  static readonly BLACK: number = 2;
}

/** 页面状态查询结果（`PageScope` 的可用性诊断）。 */
export class PageRegistrySnapshot {
  alive: string[];

  constructor(alive: string[]) {
    this.alive = alive;
  }
}

/**
 * `com.hippo.ehviewer.ui.EhActivity` 的 ArkTS 等价实现。
 *
 * ## D-051 裁决：**不是 Ability，是页面基类 + 生命周期助手**
 * 上游 `abstract class EhActivity extends AppCompatActivity` 只做四件事，逐一对位：
 *
 * | 上游 | 本实现 |
 * |---|---|
 * | `getThemeResId(theme)` + `setTheme()` | 抽象方法 `getThemeResId(theme)`（纯函数，子类给资源 id）；**不调用 `setTheme`**（ArkUI 不支持页面级换主题） |
 * | `registerActivity/unregisterActivity` | **页面注册表**（静态 `Set<string>`），`registerPage/unregisterPage` |
 * | `FLAG_SECURE`（`getEnabledSecurity()` 时） | `PageHost.setWindowPrivacyMode(true/false)`（鸿蒙直接对应） |
 * | `FirebaseAnalytics.getInstance(this)` | 已移除（D-006）；只保留 `Analytics.isEnabled()` 判断 |
 * | `attachBaseContext` 包 `ContextLocalWrapper` | 语言标签解析保留为**纯函数** `parseLocaleTag()`；包裹上下文无对应物（ArkUI 用 `i18n.System.setAppPreferredLanguage`） |
 * | `onConfigurationChanged` 里深浅色自动切换 | 纯函数 `shouldSwitchTheme(isDark)` + `applyThemeSwitch()`（调 `PageHost.recreate()`） |
 *
 * ## 生命周期约定（页面侧怎么用）
 * ```ts
 * @Entry @Component struct SplashPage {
 *   private page = new SplashPageLifecycle();          // 继承 EhActivity
 *   aboutToAppear(): void {
 *     this.page.bindHost(getContext(this) as Object as PageHost);
 *     this.page.onCreate();
 *     this.page.onResume();
 *   }
 *   aboutToDisappear(): void { this.page.onDestroy(); }
 * }
 * ```
 * 因为页面 `struct` 不能继承类，所以这里用**组合**：页面持有一个 `EhActivity` 子类实例，
 * 在 `aboutToAppear/aboutToDisappear/onPageShow/onPageHide` 里转发。
 */
export abstract class EhActivity {
  /** 子类给出主题资源 id（上游 `@StyleRes protected abstract int getThemeResId(int theme)`）。 */
  protected abstract getThemeResId(theme: number): number;

  private mHost: PageHost | null = null;
  private mPageId: string = '';
  private mCreated: boolean = false;
  private mThemeResId: number = 0;

  // ---------- 页面注册表（替代 EhApplication 的 Activity 列表） ----------

  private static sAlivePages: Set<string> = new Set<string>();

  /** 注册页面（上游 `registerActivity(this)`）。同 id 重复注册是幂等的。 */
  static registerPage(pageId: string): void {
    EhActivity.sAlivePages.add(pageId);
  }

  /** 注销页面（上游 `unregisterActivity(this)`）。 */
  static unregisterPage(pageId: string): void {
    EhActivity.sAlivePages.delete(pageId);
  }

  /** 当前存活页面数（上游 `EhApplication` 用它判断"是否所有页面都关了"）。 */
  static alivePageCount(): number {
    return EhActivity.sAlivePages.size;
  }

  static isPageAlive(pageId: string): boolean {
    return EhActivity.sAlivePages.has(pageId);
  }

  static snapshotPages(): PageRegistrySnapshot {
    const alive: string[] = [];
    EhActivity.sAlivePages.forEach((id: string) => {
      alive.push(id);
    });
    return new PageRegistrySnapshot(alive);
  }

  /** 仅测试用：清空注册表。 */
  static resetPageRegistry(): void {
    EhActivity.sAlivePages.clear();
  }

  // ---------- 宿主注入 ----------

  bindHost(host: PageHost | null): void {
    this.mHost = host;
  }

  getHost(): PageHost | null {
    return this.mHost;
  }

  setPageId(pageId: string): void {
    this.mPageId = pageId;
  }

  getPageId(): string {
    return this.mPageId;
  }

  protected settings(): EhActivitySettings {
    return EhActivitySettingsHolder.get();
  }

  /** 本次页面用的主题资源 id（上游 `setTheme()` 之后由框架读取）。 */
  getAppliedThemeResId(): number {
    return this.mThemeResId;
  }

  // ---------- 生命周期（对应上游四个覆写） ----------

  /** 等价上游 `onCreate`：定主题 → 注册页面 → 埋点检查。 */
  onCreate(): void {
    if (this.mCreated) {
      return;
    }
    this.mCreated = true;

    // setTheme(getThemeResId(Settings.getTheme()))
    const theme = this.settings().getTheme();
    this.mThemeResId = this.getThemeResId(theme);

    // registerActivity(this)
    if (this.mPageId.length === 0) {
      hilog.warn(DOMAIN, TAG, 'onCreate without pageId, registry entry skipped');
    } else {
      EhActivity.registerPage(this.mPageId);
    }

    // if (Analytics.isEnabled()) FirebaseAnalytics.getInstance(this);
    // Firebase 已移除（D-006），保留判断以维持调用形状
    if (Analytics.isEnabled()) {
      hilog.debug(DOMAIN, TAG, 'analytics enabled (Firebase removed per D-006)');
    }
  }

  /** 等价上游 `onDestroy`：注销页面。 */
  onDestroy(): void {
    if (this.mPageId.length > 0) {
      EhActivity.unregisterPage(this.mPageId);
    }
    this.mCreated = false;
  }

  /** 等价上游 `onResume`：按设置开/关防截屏。 */
  onResume(): void {
    const enabled = this.settings().getEnabledSecurity();
    this.applyPrivacyMode(enabled);
  }

  /**
   * 等价上游 `getWindow().setFlags/clearFlags(FLAG_SECURE)`。
   * 宿主未注入时只打 warn（**不假装成功**）。
   */
  applyPrivacyMode(enabled: boolean): void {
    const host = this.mHost;
    if (host === null) {
      hilog.warn(DOMAIN, TAG, 'applyPrivacyMode(%{public}s): no host bound',
        enabled ? 'true' : 'false');
      return;
    }
    host.setWindowPrivacyMode(enabled).catch((err: Object) => {
      hilog.error(DOMAIN, TAG, 'setWindowPrivacyMode failed: %{public}s', JSON.stringify(err));
    });
  }

  /**
   * 等价上游 `attachBaseContext` 里的语言解析：
   * ```java
   * String[] split = language.split("-");
   * split.length == 1 → new Locale(split[0])
   *               == 2 → new Locale(split[0], split[1])
   *               == 3 → new Locale(split[0], split[1], split[2])
   * ```
   * 返回 BCP-47 标签（`zh-CN` / `zh-Hans-CN`）；`system` / null / 空串 → null（跟随系统）。
   * **注意上游 `split.length > 3` 时不设 locale**（回落系统），这里同样返回 null。
   */
  static parseLocaleTag(language: string | null): string | null {
    if (language === null || language.length === 0 || language === 'system') {
      return null;
    }
    const split = language.split('-');
    if (split.length < 1 || split.length > 3) {
      return null;
    }
    // 过滤空段（`zh--CN` 这类脏数据）
    for (let i = 0; i < split.length; i++) {
      if (split[i].length === 0) {
        return null;
      }
    }
    return split.join('-');
  }

  /**
   * 等价上游 `onConfigurationChanged` 里的判定：
   * ```java
   * if (Settings.isThemeAutoSwitchAvailable()) {
   *     boolean isDark = (newConfig.uiMode & UI_MODE_NIGHT_MASK) == UI_MODE_NIGHT_YES;
   *     if ((Settings.getTheme() == 0) == isDark) { ... 切主题 ... }
   * }
   * ```
   * 语义（**容易理解反**）：`Settings.getTheme() == 0` 表示"当前是浅色"。
   * 于是 `(当前是浅色) == (系统是深色)` 成立时，说明**两者不一致** → 需要切换。
   * 即：浅色设置 + 系统变深 → 切深色；深色设置 + 系统变浅 → 切浅色。
   */
  shouldSwitchTheme(isSystemDark: boolean): boolean {
    const s = this.settings();
    if (!s.isThemeAutoSwitchAvailable()) {
      return false;
    }
    const currentIsLight = s.getTheme() === s.THEME_LIGHT;
    return currentIsLight === isSystemDark;
  }

  /** 执行主题切换（上游 `Settings.putTheme(...)` + `((EhApplication) getApplication()).recreate()`）。 */
  applyThemeSwitch(isSystemDark: boolean): void {
    const s = this.settings();
    s.putTheme(isSystemDark ? s.THEME_DARK : s.THEME_LIGHT);
    const host = this.mHost;
    if (host !== null) {
      host.recreate();
    } else {
      hilog.warn(DOMAIN, TAG, 'applyThemeSwitch: no host bound, page not recreated');
    }
  }
}
