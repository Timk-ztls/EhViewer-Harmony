/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/fragment/SettingsHeaders.java（inventory S0207，48 行）
 *        + 上游布局 res/xml/settings_headers.xml（6 个 header）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/fragment/SettingsHeaders.ets
 *
 * 背景：设置页的**首屏**（不是具体设置项，而是 6 个分组入口）。点某一项 → 进入对应分组页，
 * 同时把 ActionBar 标题改成该分组的标题。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class SettingsHeaders extends PreferenceFragmentCompat`
 *   `onCreatePreferences()` → `setPreferencesFromResource(R.xml.settings_headers, rootKey)`
 *     即：把 XML 里的 6 个 `BasePreference` 展开成列表（见下面「6 个 header」）
 *   `onDisplayPreferenceDialog(pref)` → `super`（**只调父类，没有额外行为** → 本实现不覆盖）
 *   `onNavigateToScreen(screen)`     → `super`（同上，**不覆盖**）
 *   `onPreferenceTreeClick(pref)`:
 *     ① `if (activity == null) activity = (SettingsActivity) getActivity();`（**懒取 + 缓存**）
 *     ② 若 activity 非空：ActionBar 存在 → `setTitle(pref.getTitle())`；否则 `activity.setTitle(...)`
 *     ③ `preference.setOnPreferenceChangeListener(this::onPreferenceChange)`
 *     ④ `return super.onPreferenceTreeClick(preference)`
 *   `onPreferenceChange(pref, o)` → **`return false`**（永远拒绝 —— 见「关键行为」2）
 *
 * ── 6 个 header（上游 settings_headers.xml，顺序即显示顺序）───────────────
 *   1. `@string/settings_eh`        icon `v_sad_panda_primary_x24`   fragment `EhFragment`
 *   2. `@string/settings_read`      icon `v_book_open_primary_x24`   fragment `ReadFragment`       allowDividerAbove
 *   3. `@string/settings_download`  icon `v_download_primary_x24`    fragment `DownloadFragment`   allowDividerAbove
 *   4. `@string/settings_privacy`   icon `v_sec_primary_x24`         fragment `PrivacyFragment`    allowDividerAbove
 *   5. `@string/settings_advanced`  icon `v_adb_primary_x24`         fragment `AdvancedFragment`   allowDividerAbove
 *   6. `@string/settings_about`     icon `v_info_primary_x24`        fragment `AboutFragment`      allowDividerAbove
 * 第 1 项**没有** `allowDividerAbove`（列表顶项不画上分割线），2–6 都有 —— 这个差异要保留。
 *
 * ── 关键行为 ────────────────────────────────────────────────────────────────
 * 1. `activity` 是**懒取且只取一次**的缓存字段（`== null` 才取），不是每次点击都取。
 * 2. `onPreferenceChange` **永远返回 false** —— 这是"分组入口项不可被修改"的显式表达，
 *    不是漏写。若改成 true，Preference 的持久化逻辑会被触发（对纯跳转项无意义且会写脏值）。
 * 3. `onDisplayPreferenceDialog` / `onNavigateToScreen` **只调 super**，没有额外行为 ——
 *    本实现**不覆盖**（覆盖成空实现反而会盖掉 ArkUI 侧的分组导航）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. **`PreferenceFragmentCompat` + `PreferenceScreen` XML 在 ArkUI 不存在**：
 *    设置列表就是 `List` + `ListItem`，分组入口是**数据表**（本文件导出的 `SETTINGS_HEADERS`）。
 *    `setPreferencesFromResource` → **静态常量表**，由 `SolidSceneSettings`（已移植）渲染。
 * 2. `getSupportActionBar().setTitle()` → 通过注入的 `SettingsTitleHost.setTitle()` 表达
 *    （ArkUI 的标题栏是页面级状态，不是 ActionBar 对象）。
 * 3. `(SettingsActivity) getActivity()` → 构造时注入 `SettingsTitleHost | null`，
 *    并保留"懒取一次"语义（`resolveHost()`）。
 * 4. **`fragment` 类名字符串** → 保留上游类名（`EhFragment` 等）作为**分组标识**：
 *    这些分组页在本仓库有的已落（Privacy/Read 规则表已存在），有的未落；
 *    存类名而不是布尔值，是为了"未落的分组能明确报出缺谁"。
 *
 * ── 资源键（陷阱 90：资源键编译期不校验、运行期静默失败）──────────────────
 * 6 个 `@string/settings_*` 与 `@string/settings` 在 `base/element/strings.json`（注意：**复数是既有事实文件名**）里均已存在
 * （实测 7 个键全在 `strings.json`）。**注意不要往 `string.json`（单数）补同名键** —— 两个文件都会参与资源编译，同名键会报 `Resource 'settings' conflict`（我第一次就这么撞了）；
 * `test/ui-scene` 里有断言逐条校验"表里每个资源键都能在 `string.json` 找到"。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 宿主：`SettingsActivity`（S0270，同批移植）
 * - 渲染：`hippo/ehviewer/ui/scene/SolidSceneSettings.ets`（已存在）
 * - 图标组件：`hippo/ui/drawable/v_*.ets`（6 个全部已存在，实测确认）
 */

/**
 * 本文件对宿主的**最小**依赖（只用到「改标题」这一个能力）。
 * 为什么不直接 import SettingsActivity 的 EhActivityHost：那会形成**循环 import**
 * （SettingsActivity -> fragment/SettingsHeaders -> SettingsActivity）。
 * 用结构化类型：SettingsActivity 实例传进来也满足该接口，无需显式 implements。
 */
export interface SettingsTitleHost {
  setSettingsTitle(title: string, isResource: boolean): void;
}

/** 一个分组入口（对应上游 `<BasePreference .../>` 一项） */
export class SettingsHeader {
  /** 标题资源键（`@string/settings_eh` → `app.string.settings_eh`） */
  readonly titleKey: string;
  /**
   * 图标组件名（上游 `@drawable/v_*`；本仓库 drawable 已迁成组件 `hippo/ui/drawable/<name>.ets`）。
   * 存**组件名**而不是 `$r('app.media.*')` —— 后者在本仓库基本不存在，会编译失败。
   */
  readonly iconComponent: string;
  /** 上游 `app:fragment` 的全类名（作为分组标识，见文件头「平台差异」4） */
  readonly fragmentClass: string;
  /** 上游 `app:allowDividerAbove`（第 1 项为 false，2–6 为 true） */
  readonly allowDividerAbove: boolean;

  constructor(titleKey: string, iconComponent: string, fragmentClass: string, allowDividerAbove: boolean) {
    this.titleKey = titleKey;
    this.iconComponent = iconComponent;
    this.fragmentClass = fragmentClass;
    this.allowDividerAbove = allowDividerAbove;
  }
}

/**
 * 上游 `res/xml/settings_headers.xml` 的 6 个 header，**顺序即显示顺序**。
 * 注意第 1 项 `allowDividerAbove=false`（列表顶项不画上分割线）。
 */
export const SETTINGS_HEADERS: SettingsHeader[] = [
  new SettingsHeader('app.string.settings_eh', 'v_sad_panda_primary_x24',
    'com.hippo.ehviewer.ui.fragment.EhFragment', false),
  new SettingsHeader('app.string.settings_read', 'v_book_open_primary_x24',
    'com.hippo.ehviewer.ui.fragment.ReadFragment', true),
  new SettingsHeader('app.string.settings_download', 'v_download_primary_x24',
    'com.hippo.ehviewer.ui.fragment.DownloadFragment', true),
  new SettingsHeader('app.string.settings_privacy', 'v_sec_primary_x24',
    'com.hippo.ehviewer.ui.fragment.PrivacyFragment', true),
  new SettingsHeader('app.string.settings_advanced', 'v_adb_primary_x24',
    'com.hippo.ehviewer.ui.fragment.AdvancedFragment', true),
  new SettingsHeader('app.string.settings_about', 'v_info_primary_x24',
    'com.hippo.ehviewer.ui.fragment.AboutFragment', true)
];

export class SettingsHeaders {
  /** 上游 `private SettingsActivity activity`：懒取一次并缓存（见「关键行为」1） */
  private activity: SettingsTitleHost | null = null;
  /** 构造时注入的宿主（上游通过 `getActivity()` 取；ArkUI 侧显式注入） */
  private injectedHost: SettingsTitleHost | null;

  constructor(host: SettingsTitleHost | null = null) {
    this.injectedHost = host;
  }

  /** 上游 `onCreatePreferences()`：`setPreferencesFromResource(R.xml.settings_headers, rootKey)` */
  onCreatePreferences(): SettingsHeader[] {
    return SETTINGS_HEADERS;
  }

  /** 上游懒取：`if (activity == null) activity = (SettingsActivity) getActivity();` */
  private resolveHost(): SettingsTitleHost | null {
    if (this.activity === null) {
      this.activity = this.injectedHost;
    }
    return this.activity;
  }

  /**
   * 上游 `onPreferenceTreeClick(preference)`：
   * ① 懒取 activity ② 设置标题 ③ 挂 change listener ④ `return super.onPreferenceTreeClick(preference)`
   *
   * @returns 上游 `super.onPreferenceTreeClick(...)` 的等价物：**true = 已处理（进入分组页）**。
   *          没有宿主时上游仍会 `return super...`（通常 true），这里同样返回 true。
   */
  onPreferenceTreeClick(header: SettingsHeader): boolean {
    const host: SettingsTitleHost | null = this.resolveHost();
    if (host !== null) {
      // 上游：ActionBar 存在 → setTitle(pref.getTitle())；否则 activity.setTitle(...)
      // ArkUI 没有 ActionBar 对象，统一走 host.setSettingsTitle
      host.setSettingsTitle(header.titleKey, true);
    }
    // 上游 ③：preference.setOnPreferenceChangeListener(this::onPreferenceChange) ——
    // 注册的是"永远返回 false"的监听（见「关键行为」2），本实现直接以 onPreferenceChange() 表达
    return true;
  }

  /** 上游 `onPreferenceChange(preference, o)` → **永远 false**（纯跳转项不可被修改） */
  onPreferenceChange(header: SettingsHeader, newValue: Object | null): boolean {
    return false;
  }
}


