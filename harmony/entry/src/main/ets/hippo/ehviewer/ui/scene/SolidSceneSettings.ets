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
import { Settings } from '../../Settings';

const TAG = 'SolidSceneSettings';
const DOMAIN = 0x0000;

/**
 * `SolidScene` 需要读取的四个设置项（**本项目新增的能力接口**）。
 *
 * ## 为什么不直接调 `Settings`
 * 上游这四项都是 `Settings` 的静态方法：
 * ```java
 * Settings.getShowWarning()                      // boolean
 * Settings.getAskAnalytics()                     // boolean
 * Settings.getSelectSite()                       // boolean
 * Settings.getLaunchPageGalleryListSceneAction() // String
 * ```
 * 而 `Settings.ets`（core-runtime 维护）目前**只有** `getInt/putInt` + 字符串变体 +
 * `getGallerySite/getReadCacheSize/getDownloadLocation` 等，**没有 boolean 通道，
 * 也没有这四个访问器**。跨模块加方法要去改别人的文件，所以这里用能力接口隔离：
 *
 * - 代价：多一层间接
 * - 收益：`SolidScene` 的检查链逻辑**现在就能落地并单测**（构造一个假的 settings 即可），
 *   `Settings` 补上四个访问器后，写一个 10 行适配器注入即可，场景代码零改动
 *
 * **登记为 D-054**（`Settings` 缺 boolean 通道 + 四个场景开关访问器，待 core-runtime 补齐）。
 */
export interface SolidSceneSettings {
  /** 上游 `Settings.getShowWarning()`：是否展示安全警告。 */
  getShowWarning(): boolean;

  /** 上游 `Settings.getAskAnalytics()`：是否询问埋点授权。 */
  getAskAnalytics(): boolean;

  /** 上游 `Settings.getSelectSite()`：是否需要选择站点。 */
  getSelectSite(): boolean;

  /**
   * 上游 `Settings.getNeedSignIn()`：是否需要登录（`KEY_NEED_SIGN_IN`，**默认 `true`**）。
   *
   * 🔴 **2026-10-27 补（`W-020`）**：这个访问器此前**整个接口里都没有** ——
   * 于是上游门 4 的判定 `EhUtils.needSignedIn()` 无法实现：
   *
   *     fun needSignedIn(context: Context): Boolean {
   *         return Settings.getNeedSignIn() && !EhApplication.getEhCookieStore(context).hasSignedIn()
   *     }
   *
   * **两个条件缺一不可**：少 `getNeedSignIn()` 就无法表达"用户关掉了强制登录"这一分支，
   * 门 4 会永远按"需要登录"处理（或永远不算 —— 取决于补位实现），两种都不对。
   *
   * 判据（进库）：**接口对位上游时，要按上游那行**判定表达式**里的每个访问器**去核，
   * 不能只看"我们代码里用到的那几个" —— 上游 `needSignedIn` 一行里有**两个**访问器，
   * 我们只移植了一个，接口就静默少了一个方法。
   */
  getNeedSignIn(): boolean;

  /** 上游 `Settings.getLaunchPageGalleryListSceneAction()`：默认启动页（回落用）。 */
  getLaunchPageGalleryListSceneAction(): string;

  // ---- 写侧（WarningScene / SelectSiteScene / AnalyticsScene 需要）----

  /** 上游 `Settings.putShowWarning(boolean)`：「不再显示警告」。 */
  putShowWarning(value: boolean): void;

  /** 上游 `Settings.putAskAnalytics(boolean)`：已询问过埋点授权。 */
  putAskAnalytics(value: boolean): void;

  /** 上游 `Settings.putSelectSite(boolean)`：已选择过站点。 */
  putSelectSite(value: boolean): void;

  getGallerySite(): number;

  /** 上游 `Settings.putGallerySite(int)`（`Settings.ets` 已有同名方法）。 */
  putGallerySite(value: number): void;

  /** 上游 `Settings.putEnableAnalytics(boolean)`。 */
  putEnableAnalytics(value: boolean): void;
}

/**
 * 未接线时的占位实现。
 *
 * **取值策略：严格照抄上游 `Settings.java` 的 `DEFAULT_*`，一个都不改。**
 *
 * 🔴 **2026-10-27 修**：此前这里对 `getAskAnalytics` / `getSelectSite` 返回 `false`，
 * 注释还写"上游默认为 false，这两步是可选询问" —— **那句话是错的**。
 * 上游 `Settings.java` 实测：
 *
 *     private static final boolean DEFAULT_SHOW_WARNING   = true;
 *     private static final boolean DEFAULT_SELECT_SITE    = true;   ← 不是 false
 *     private static final boolean DEFAULT_ASK_ANALYTICS  = true;   ← 不是 false
 *
 * **后果（真机已验）**：首次安装时 Analytics / SelectSite 两道门**根本不会弹** ——
 * 与用户观察到的"安卓会弹，华为这个没有"完全一致。
 *
 * **判据（进库）**：**占位实现的默认值必须逐个对上游 `DEFAULT_*` 常量，不能凭"这步该不该问"判断。**
 * "可选询问"描述的是**用户的感受**，不是**上游的默认值** —— 上游默认值是 `true`，
 * 用户在第一次被问到之后才 `put*(false)`。
 *
 * **每次调用都会打一次 warn**（带 `TAG`，便于在日志里定位"还没接线"）。
 */
export class UnwiredSolidSceneSettings implements SolidSceneSettings {
  getShowWarning(): boolean {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: using DEFAULT_SHOW_WARNING=true');
    return true;
  }

  getAskAnalytics(): boolean {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: using DEFAULT_ASK_ANALYTICS=true');
    return true;
  }

  getSelectSite(): boolean {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: using DEFAULT_SELECT_SITE=true');
    return true;
  }

  /**
   * 上游 `DEFAULT_NEED_SIGN_IN = true` —— 首次安装**必须**走登录门。
   *
   * 注意：这只是"是否需要登录"这一半。另一半是 `EhCookieStore.hasSignedIn()`
   * （`EhCookieStore.ets:55`，已 1:1 实现）。两者一起才等于上游的
   * `EhUtils.needSignedIn()` —— 而它还没有调用者（`W-019` 的 `new EhCookieStore` 为 0 处）。
   */
  getNeedSignIn(): boolean {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: using DEFAULT_NEED_SIGN_IN=true');
    return true;
  }

  getLaunchPageGalleryListSceneAction(): string {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: launch page action is empty');
    return '';
  }

  putShowWarning(value: boolean): void {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: putShowWarning(%{public}s) dropped',
      value ? 'true' : 'false');
  }

  putAskAnalytics(value: boolean): void {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: putAskAnalytics(%{public}s) dropped',
      value ? 'true' : 'false');
  }

  putSelectSite(value: boolean): void {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: putSelectSite(%{public}s) dropped',
      value ? 'true' : 'false');
  }

  getGallerySite(): number {
    // Settings.ets 已有真实实现，直接转发
    return Settings.getGallerySite();
  }

  putGallerySite(value: number): void {
    // 这一项 Settings.ets 已有真实实现，即使其它项未接线也应写入
    Settings.putGallerySite(value);
  }

  putEnableAnalytics(value: boolean): void {
    hilog.warn(DOMAIN, TAG, 'Settings not wired: putEnableAnalytics(%{public}s) dropped',
      value ? 'true' : 'false');
  }
}

/** 全局持有（场景实例是短命的，设置读取是应用级的，所以放静态）。 */
export class SolidSceneSettingsHolder {
  private static sSettings: SolidSceneSettings = new UnwiredSolidSceneSettings();

  /** 宿主/测试注入。传 null 恢复未接线实现。 */
  static set(settings: SolidSceneSettings | null): void {
    SolidSceneSettingsHolder.sSettings = settings === null
      ? new UnwiredSolidSceneSettings() : settings;
  }

  static get(): SolidSceneSettings {
    return SolidSceneSettingsHolder.sSettings;
  }

  static reset(): void {
    SolidSceneSettingsHolder.sSettings = new UnwiredSolidSceneSettings();
  }
}
