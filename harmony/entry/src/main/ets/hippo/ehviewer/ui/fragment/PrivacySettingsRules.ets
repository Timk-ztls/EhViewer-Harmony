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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/fragment/PrivacyFragment.java（40 行）。
 *
 * ============================================================================
 * 一、拆分说明（对齐本项目 D-033 的口径：UI 剥离，行为保留）
 * ============================================================================
 * 上游是 `extends BasePreferenceFragmentCompat implements Preference.OnPreferenceChangeListener`，
 * 本体只有三件事：
 *
 *   ```java
 *   onCreatePreferences(...) {
 *       addPreferencesFromResource(R.xml.privacy_settings);                  // ← XML 膨胀，ArkUI 无对应
 *       findPreference(Settings.KEY_ENABLE_ANALYTICS).setOnPreferenceChangeListener(this);
 *   }
 *   onResume() {
 *       Preference p = findPreference("pattern_protection");
 *       p.setSummary(TextUtils.isEmpty(Settings.getSecurity())              // ← 真实行为 ①
 *           ? R.string.settings_privacy_pattern_protection_not_set
 *           : R.string.settings_privacy_pattern_protection_set);
 *   }
 *   onPreferenceChange(pref, newValue) {
 *       if (Settings.KEY_ENABLE_ANALYTICS.equals(pref.getKey())) {
 *           if (newValue instanceof Boolean && (Boolean) newValue) {
 *               Analytics.start(getActivity());                              // ← 真实行为 ②
 *           }
 *           return true;
 *       }
 *       return true;
 *   }
 *   ```
 *
 * **XML 膨胀与 Fragment 生命周期**划给组件层（ArkUI 设置页自己声明条目）；
 * **两个真实行为**留在本文件，且都是纯判定，可直接断言：
 *   ① 「图案锁」条目的副标题取决于**安全码是否为空**
 *   ② 「启用统计」开关**只在变为开启时**触发 `Analytics.start()`
 *
 * ============================================================================
 * 二、为什么 ② 只在 `true` 时不等于"少写一个分支"
 * ============================================================================
 * 上游 `if (Boolean) Analytics.start(...)`：关闭时不做事（也不做 stop —— 上游本来就没有 stop）。
 * 如果移植时"对称"地补一个 `else Analytics.stop()`，那会**新增上游没有的行为**。
 * 这里返回 `shouldStartAnalytics`，调用方据此决定是否调用 `Analytics.start()`。
 *
 * ============================================================================
 * 三、依赖状态
 * ============================================================================
 * - `Analytics.start(context)` —— 已 land（`hippo/ehviewer/Analytics.ets:35`）
 * - `Settings.KEY_ENABLE_ANALYTICS` / `Settings.getSecurity()` —— **尚未 land**
 *   （上游 `Settings.java:1193` `KEY_SECURITY = "security"`、`:1196` `getSecurity()`）
 *   因此本文件**不直接引用 Settings**：安全码是否为空由调用方作为参数传入。
 *   这样在 `Settings.getSecurity()` 落地前，本规则也能被 ArkUI 设置页使用与单测覆盖。
 */

/** 「启用统计」的开关变化结果。 */
export interface AnalyticsTogglePlan {
  /** 是否放行该变更（上游恒 `return true`，即"开关照旧生效"）。 */
  accept: boolean;
  /** 是否应调用 `Analytics.start(context)`（**仅当新值为 true**）。 */
  shouldStartAnalytics: boolean;
}

/**
 * 隐私设置页的判定规则（对位上游 `PrivacyFragment`）。
 */
export class PrivacySettingsRules {
  /** 图案锁条目的 key（上游 `private static final String KEY_PATTERN_PROTECTION = "pattern_protection"`）。 */
  public static readonly KEY_PATTERN_PROTECTION: string = 'pattern_protection';

  /**
   * 图案锁条目副标题的两种取值（上游 `R.string.settings_privacy_pattern_protection_not_set` / `..._set`）。
   *
   * 这里只给**字符串资源名**，不硬编码文案：ArkUI 侧按项目的 `$r('app.string.xxx')` 取值，
   * 与上游"用资源 id 而不是字面量"保持一致。
   */
  public static readonly RES_PATTERN_NOT_SET: string = 'settings_privacy_pattern_protection_not_set';
  public static readonly RES_PATTERN_SET: string = 'settings_privacy_pattern_protection_set';

  /**
   * 图案锁条目的副标题资源名。
   *
   * 上游判定：`TextUtils.isEmpty(Settings.getSecurity())` → 未设置；否则 → 已设置。
   * `TextUtils.isEmpty` 对 `null` 与 `""` 都算空，所以这里把二者都当"未设置"。
   *
   * @param security 安全码原值（对应 `Settings.getSecurity()`；未 land 前由调用方传入）
   */
  static patternProtectionSummaryRes(security: string | null): string {
    if (security === null || security.length === 0) {
      return PrivacySettingsRules.RES_PATTERN_NOT_SET;
    }
    return PrivacySettingsRules.RES_PATTERN_SET;
  }

  /**
   * 「启用统计」开关变化的处理（上游 `onPreferenceChange` 的 analytics 分支）。
   *
   * @param key       被改动的设置项 key
   * @param newValue  新值（上游 `Object newValue`；只有 `Boolean` 类型才可能触发 start）
   * @param enableAnalyticsKey 该设置项的 key（默认取上游 `Settings.KEY_ENABLE_ANALYTICS`，由调用方传入）
   */
  static planAnalyticsToggle(key: string, newValue: Object | null, enableAnalyticsKey: string): AnalyticsTogglePlan {
    if (key !== enableAnalyticsKey) {
      // 非本条目：上游直接 `return true`
      return { accept: true, shouldStartAnalytics: false };
    }
    // 上游 `newValue instanceof Boolean && (Boolean) newValue`
    const isTrue: boolean = typeof newValue === 'boolean'
      ? newValue
      : (newValue instanceof Boolean ? newValue.valueOf() : false);
    return { accept: true, shouldStartAnalytics: isTrue };
  }

  /**
   * 窗口隐私模式（防截屏）同步缓存序列化（`privacy_mode.cache`），供冷启动首帧提前读取。
   */
  static encodePrivacyCache(enabled: boolean): string {
    return enabled ? '1' : '0';
  }

  /**
   * 解析 `privacy_mode.cache` 内容；空串/未知值回落至 `fallback`。
   */
  static decodePrivacyCache(raw: string | null | undefined, fallback: boolean): boolean {
    if (raw === null || raw === undefined) {
      return fallback;
    }
    const trimmed: string = raw.trim();
    if (trimmed === '1' || trimmed === 'true') {
      return true;
    }
    if (trimmed === '0' || trimmed === 'false') {
      return false;
    }
    return fallback;
  }

  /**
   * 阅读器进入或退出时应保持的全局窗口隐私状态。
   * 鸿蒙全应用共用同一个主窗口，退出阅读器时严禁擅自关闭全局防截屏，始终与 `Settings.getEnabledSecurity()` 一致。
   */
  static resolveReaderPrivacyMode(enabledSecurity: boolean, _entering: boolean): boolean {
    return enabledSecurity;
  }
}
