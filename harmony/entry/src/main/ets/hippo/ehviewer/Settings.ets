/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0176   上游: com/hippo/ehviewer/Settings.java（1583 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/Settings.ets
 *
 * 平台差异：
 *  1. **Android SharedPreferences → @ohos.data.preferences**。上游用 `sSettingsPre`
 *     (`PreferenceManager.getDefaultSharedPreferences`)；鸿蒙需要 Context，故新增
 *     `Settings.attach(context)`（**非上游 API**，需在 EntryAbility/AbilityStage 启动时调用一次）。
 *     attach 前：读走内存快照（返回默认值或预写入值）、写落内存并记录待重放队列，attach 完成后
 *     一次性持久化，不因 `.clear()` 丢失启动早期的写入。
 *  2. **C-12 的关键坑（已按上游形态保留）**：上游 `getIntFromStr/putIntToStr` 是
 *     **"以字符串存 preference、读时 parse 成 int"**：
 *       getIntFromStr = NumberUtils.parseIntSafely(pref.getString(key, String(defValue)), defValue)
 *       putIntToStr   = pref.edit().putString(key, String(value)).apply()
 *     本实现严格保留该形态（`getString`/`putString` + `NumberUtils.parseIntSafely`）。
 *  3. `getGallerySite()` **不做范围校验**（上游直接返回 parse 结果），本实现同样不加校验。
 *  4. 写操作 `putSync` + `flush()`：flush 是异步的（fire-and-forget），语义对齐上游 `.apply()`
 *     （异步落盘、不阻塞调用线程）。
 *  5. 上游 `putEnabledSecurity` 将键错写成 `KEY_READING_FULLSCREEN`，此处已修正为 `KEY_SEC_SECURITY`。
 */

import preferences from '@ohos.data.preferences';
import hilog from '@ohos.hilog';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { NumberUtils } from '../lib/yorozuya/NumberUtils';
import { FileUtils } from '../lib/yorozuya/FileUtils';
import { AssertUtils } from '../lib/yorozuya/AssertUtils';
import { UniFile } from '../unifile/UniFile';
import { AppConfig } from './AppConfig';
import { ExceptionUtils } from '../util/ExceptionUtils';
import { GalleryInfo } from './client/data/GalleryInfo';
import { EhConfig } from './client/EhConfig';
import { ReadingRefreshRate } from './util/ReadingRefreshRate';

export class Settings {

  private static readonly TAG: string = 'Settings';
  private static readonly UNSET_SENTINEL: string = '__EH_PREF_UNSET_7F3A__';

  /** preferences 文件句柄（attach 完成后非 null） */
  private static sPref: preferences.Preferences | null = null;
  /** 归档任务偏好（上游是独立的 sArchiverPre，与 settings 分开存） */
  private static sArchiverPref: preferences.Preferences | null = null;
  /** archiver 库的键值快照（供 hasPending/getPending 这类**上游是同步**的方法用） */
  private static sArchiverMem: Map<string, string> = new Map<string, string>();
  /** attach 时一次性载入的字符串快照（对齐 SharedPreferences 的内存语义） */
  private static sMem: Map<string, string> = new Map<string, string>();
  /** attach 完成前主库待重放写入/删除（null 代表删除键） */
  private static sPendingWrites: Map<string, preferences.ValueType | null> =
    new Map<string, preferences.ValueType | null>();
  /** attach 完成前 archiver 库待重放写入/删除 */
  private static sArchiverPendingWrites: Map<string, preferences.ValueType | null> =
    new Map<string, preferences.ValueType | null>();
  /** attach 完成标志（只在 getPreferences + getAll 全完成后置 true） */
  private static sAttached: boolean = false;
  /** 并发 attach 去重句柄 */
  private static sAttachPromise: Promise<void> | null = null;
  /** 缓存的 EhConfig 实例（与上游 sEhConfig 对齐） */
  private static sEhConfig: EhConfig | null = null;
  /** 登录态提供者（上游 `Settings.isLogin()`，依赖 EhCookieStore → net-parse） */
  private static sLoginProvider: (() => boolean) | null = null;
  /** 系统深色模式提供者（对应上游 `Settings.getDarkModeStatus(Context)`） */
  private static sDarkModeProvider: (() => boolean) | null = null;
  /** 可选 .nomedia 钩子（默认直接通过 UniFile 处理） */
  private static sDownloadLocationNoMediaHook: ((location: UniFile, mediaScan: boolean) => void) | null = null;

  /**
   * 绑定 Ability 上下文并载入既有偏好值。
   * **非上游 API**：鸿蒙 preferences 必须带 Context，故需要启动时注入一次。
   * 并发调用去重；只会在 getPreferences + getAll 全完成后暴露 sPref/sArchiverPref/sAttached，
   * 并保留 attach 完成前的内存写入与删除。
   */
  static async attach(context: common.Context): Promise<void> {
    if (Settings.sAttachPromise !== null) {
      return Settings.sAttachPromise;
    }
    const task: Promise<void> = Settings.doAttach(context);
    Settings.sAttachPromise = task;
    try {
      await task;
    } finally {
      if (Settings.sAttachPromise === task) {
        Settings.sAttachPromise = null;
      }
    }
  }

  private static async doAttach(context: common.Context): Promise<void> {
    const pref: preferences.Preferences = await preferences.getPreferences(context, 'settings');
    const archiverPref: preferences.Preferences = await preferences.getPreferences(context, 'archiver');
    const allA: Object = await archiverPref.getAll();
    const all: Object = await pref.getAll();

    Settings.loadMemSnapshot(Settings.sArchiverMem, allA);
    Settings.loadMemSnapshot(Settings.sMem, all);

    const hasMainPending: boolean = Settings.applyPendingWritesSync(
      pref, Settings.sMem, Settings.sPendingWrites);
    const hasArchiverPending: boolean = Settings.applyPendingWritesSync(
      archiverPref, Settings.sArchiverMem, Settings.sArchiverPendingWrites);

    Settings.sPref = pref;
    Settings.sArchiverPref = archiverPref;
    Settings.sAttached = true;
    Settings.sEhConfig = Settings.loadEhConfig();

    if (hasMainPending) {
      await pref.flush().catch((e: Error) => {
        Settings.logFlushError('attach-pending', e);
      });
    }
    if (hasArchiverPending) {
      await archiverPref.flush().catch((e: Error) => {
        Settings.logFlushError('attach-pending-archiver', e);
      });
    }
  }

  private static loadMemSnapshot(target: Map<string, string>, allObj: Object): void {
    target.clear();
    const map: Record<string, Object> = allObj as Record<string, Object>;
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      target.set(k, `${map[k]}`);
    }
  }

  private static applyPendingWritesSync(pref: preferences.Preferences,
    mem: Map<string, string>,
    pending: Map<string, preferences.ValueType | null>): boolean {
    if (pending.size === 0) {
      return false;
    }
    pending.forEach((value: preferences.ValueType | null, key: string) => {
      if (value === null) {
        mem.delete(key);
        try {
          pref.deleteSync(key);
        } catch (e) {
          Settings.logReadError(key, e as Object);
        }
      } else {
        mem.set(key, `${value}`);
        pref.putSync(key, value);
      }
    });
    pending.clear();
    return true;
  }

  /** 是否已绑定 Context（storage-db 可据此判断要不要等启动完成） */
  static isAttached(): boolean {
    return Settings.sAttached && Settings.sPref !== null;
  }

  // ── 底层偏好读写（对齐上游 getBoolean/getInt/getLong/getFloat/getString/getIntFromStr）──

  private static writeMainPref(key: string, memValue: string, prefValue: preferences.ValueType): void {
    Settings.sMem.set(key, memValue);
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref === null) {
      Settings.sPendingWrites.set(key, prefValue);
      return;
    }
    pref.putSync(key, prefValue);
    // 对应上游 .apply()：异步落盘，不阻塞调用线程
    pref.flush().catch((e: Error) => {
      Settings.logFlushError(key, e);
    });
  }

  private static writeArchiverPref(key: string, memValue: string, prefValue: preferences.ValueType): void {
    Settings.sArchiverMem.set(key, memValue);
    const pref: preferences.Preferences | null = Settings.sArchiverPref;
    if (pref === null) {
      Settings.sArchiverPendingWrites.set(key, prefValue);
      return;
    }
    pref.putSync(key, prefValue);
    pref.flush().catch((e: Error) => {
      Settings.logFlushError(key, e);
    });
  }

  private static logReadError(key: string, e: Object): void {
    const msg: string = (e instanceof Error) ? e.message : String(e);
    hilog.debug(0x0001, Settings.TAG, 'Get ClassCastException when get %{public}s value: %{public}s', key, msg);
  }

  /** 对齐上游 getBoolean(String, boolean) */
  static getBoolean(key: string, defValue: boolean): boolean {
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref === null) {
      const v: string | undefined = Settings.sMem.get(key);
      if (v === undefined) {
        return defValue;
      }
      if (v === 'true') {
        return true;
      }
      if (v === 'false') {
        return false;
      }
      return defValue;
    }
    try {
      const v: preferences.ValueType = pref.getSync(key, defValue);
      return (typeof v === 'boolean') ? (v as boolean) : defValue;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return defValue;
    }
  }

  /** 对齐上游 putBoolean(String, boolean) */
  static putBoolean(key: string, value: boolean): void {
    Settings.writeMainPref(key, value ? 'true' : 'false', value);
  }

  /** 对齐上游 getInt(String, int)（原生 int 型 preference，不是字符串存） */
  static getInt(key: string, defValue: number): number {
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref === null) {
      const v: string | undefined = Settings.sMem.get(key);
      return (v === undefined) ? defValue : NumberUtils.parseIntSafely(v, defValue);
    }
    try {
      const v: preferences.ValueType = pref.getSync(key, defValue);
      return (typeof v === 'number') ? Math.trunc(v as number) : defValue;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return defValue;
    }
  }

  /** 对齐上游 putInt(String, int) */
  static putInt(key: string, value: number): void {
    Settings.writeMainPref(key, `${value}`, value);
  }

  /** 对齐上游 getLong(String, long) */
  static getLong(key: string, defValue: number): number {
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref === null) {
      const v: string | undefined = Settings.sMem.get(key);
      return (v === undefined) ? defValue : NumberUtils.parseLongSafely(v, defValue);
    }
    try {
      const v: preferences.ValueType = pref.getSync(key, defValue);
      return (typeof v === 'number') ? Math.trunc(v as number) : defValue;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return defValue;
    }
  }

  /** 对齐上游 putLong(String, long) */
  static putLong(key: string, value: number): void {
    Settings.writeMainPref(key, `${value}`, value);
  }

  /** 对齐上游 getFloat(String, float) */
  static getFloat(key: string, defValue: number): number {
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref === null) {
      const v: string | undefined = Settings.sMem.get(key);
      if (v === undefined) {
        return defValue;
      }
      const parsed: number = Number.parseFloat(v);
      return Number.isNaN(parsed) ? defValue : parsed;
    }
    try {
      const v: preferences.ValueType = pref.getSync(key, defValue);
      return (typeof v === 'number') ? (v as number) : defValue;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return defValue;
    }
  }

  /** 对齐上游 putFloat(String, float) */
  static putFloat(key: string, value: number): void {
    Settings.writeMainPref(key, `${value}`, value);
  }

  /** 对齐上游 getString(String, String)（非空默认值） */
  static getString(key: string, defValue: string): string {
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref !== null) {
      try {
        const v: preferences.ValueType = pref.getSync(key, defValue);
        return (typeof v === 'string') ? (v as string) : defValue;
      } catch (e) {
        Settings.logReadError(key, e as Object);
        return defValue;
      }
    }
    const v: string | undefined = Settings.sMem.get(key);
    return (v === undefined) ? defValue : v;
  }

  /** 对齐上游 putString(String, String) */
  static putString(key: string, value: string): void {
    Settings.writeMainPref(key, value, value);
  }

  /** 对齐上游 `getString(key, null)`（可空默认） */
  private static getStringNullable(key: string, defValue: string | null = null): string | null {
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref !== null) {
      try {
        const v: preferences.ValueType = pref.getSync(key, Settings.UNSET_SENTINEL);
        if (v === Settings.UNSET_SENTINEL) {
          return defValue;
        }
        return (typeof v === 'string') ? (v as string) : defValue;
      } catch (e) {
        Settings.logReadError(key, e as Object);
        return defValue;
      }
    }
    const v: string | undefined = Settings.sMem.get(key);
    return (v === undefined) ? defValue : v;
  }

  /** 对齐上游 `putString(key, value)`（value 为 null 时删键） */
  private static putStringNullable(key: string, value: string | null): void {
    if (value === null) {
      Settings.removeKey(key);
      return;
    }
    Settings.putString(key, value);
  }

  /**
   * 删除一个键（对应 SharedPreferences "写 null" 的可空语义）。
   */
  private static removeKey(key: string): void {
    Settings.sMem.delete(key);
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref === null) {
      Settings.sPendingWrites.set(key, null);
      return;
    }
    try {
      pref.deleteSync(key);
      pref.flush().catch((e: Error) => {
        Settings.logFlushError(key, e);
      });
    } catch (e) {
      hilog.error(0x0001, Settings.TAG, 'removeKey(%{public}s) failed: %{public}s', key,
        `${(e as Error).message}`);
    }
  }

  /** 对齐上游 getIntFromStr（见文件头差异 2） */
  static getIntFromStr(key: string, defValue: number): number {
    return NumberUtils.parseIntSafely(Settings.getString(key, `${defValue}`), defValue);
  }

  /** 对齐上游 putIntToStr（见文件头差异 2） */
  static putIntToStr(key: string, value: number): void {
    Settings.putString(key, `${value}`);
  }

  // ── EhConfig 缓存（上游 L68 / L98–L106 / L339–L341）──────────────────────

  private static loadEhConfig(): EhConfig {
    const ehConfig: EhConfig = new EhConfig();
    ehConfig.imageSize = Settings.getImageResolution();
    const exclLang: string | null = Settings.getExcludedLanguages();
    ehConfig.excludedLanguages = exclLang === null ? '' : exclLang;
    ehConfig.defaultCategories = Settings.getDefaultCategories();
    ehConfig.excludedNamespaces = Settings.getExcludedTagNamespaces();
    ehConfig.setDirty();
    return ehConfig;
  }

  static getEhConfig(): EhConfig {
    if (Settings.sEhConfig === null) {
      Settings.sEhConfig = Settings.loadEhConfig();
    }
    return Settings.sEhConfig;
  }

  // ── 站点 / 启动门 / 账户（上游 L284–L450）────────────────────────────────

  static readonly KEY_VERSION_CODE: string = 'version_code';
  static readonly DEFAULT_VERSION_CODE: number = 0;

  static getVersionCode(): number {
    return Settings.getInt(Settings.KEY_VERSION_CODE, Settings.DEFAULT_VERSION_CODE);
  }

  static putVersionCode(value: number): void {
    Settings.putInt(Settings.KEY_VERSION_CODE, value);
  }

  static readonly KEY_DISPLAY_NAME: string = 'display_name';
  static readonly DEFAULT_DISPLAY_NAME: string | null = null;

  static getDisplayName(): string | null {
    return Settings.getStringNullable(Settings.KEY_DISPLAY_NAME, Settings.DEFAULT_DISPLAY_NAME);
  }

  static putDisplayName(value: string | null): void {
    Settings.putStringNullable(Settings.KEY_DISPLAY_NAME, value);
  }

  static readonly KEY_AVATAR: string = 'avatar';
  static readonly DEFAULT_AVATAR: string | null = null;

  static getAvatar(): string | null {
    return Settings.getStringNullable(Settings.KEY_AVATAR, Settings.DEFAULT_AVATAR);
  }

  static putAvatar(value: string | null): void {
    Settings.putStringNullable(Settings.KEY_AVATAR, value);
  }

  static readonly KEY_SHOW_WARNING: string = 'show_warning';
  static readonly DEFAULT_SHOW_WARNING: boolean = true;

  static getShowWarning(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_WARNING, Settings.DEFAULT_SHOW_WARNING);
  }

  static putShowWarning(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_WARNING, value);
  }

  static readonly KEY_REMOVE_IMAGE_FILES: string = 'include_pic';
  static readonly DEFAULT_REMOVE_IMAGE_FILES: boolean = true;

  static getRemoveImageFiles(): boolean {
    return Settings.getBoolean(Settings.KEY_REMOVE_IMAGE_FILES, Settings.DEFAULT_REMOVE_IMAGE_FILES);
  }

  static putRemoveImageFiles(value: boolean): void {
    Settings.putBoolean(Settings.KEY_REMOVE_IMAGE_FILES, value);
  }

  static readonly KEY_NEED_SIGN_IN: string = 'need_sign_in';
  static readonly DEFAULT_NEED_SIGN_IN: boolean = true;

  static getNeedSignIn(): boolean {
    return Settings.getBoolean(Settings.KEY_NEED_SIGN_IN, Settings.DEFAULT_NEED_SIGN_IN);
  }

  static putNeedSignIn(value: boolean): void {
    Settings.putBoolean(Settings.KEY_NEED_SIGN_IN, value);
  }

  static readonly KEY_SELECT_SITE: string = 'select_site';
  static readonly DEFAULT_SELECT_SITE: boolean = true;

  static getSelectSite(): boolean {
    return Settings.getBoolean(Settings.KEY_SELECT_SITE, Settings.DEFAULT_SELECT_SITE);
  }

  static putSelectSite(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SELECT_SITE, value);
  }

  static readonly KEY_QUICK_SEARCH_TIP: string = 'quick_search_tip';
  static readonly DEFAULT_QUICK_SEARCH_TIP: boolean = true;

  static getQuickSearchTip(): boolean {
    return Settings.getBoolean(Settings.KEY_QUICK_SEARCH_TIP, Settings.DEFAULT_QUICK_SEARCH_TIP);
  }

  static putQuickSearchTip(value: boolean): void {
    Settings.putBoolean(Settings.KEY_QUICK_SEARCH_TIP, value);
  }

  static readonly KEY_GALLERY_SITE: string = 'gallery_site';
  static readonly DEFAULT_GALLERY_SITE: number = 0;

  /**
   * C-12 冻结：返回 number（int32 语义），key `"gallery_site"`，默认 0（== SITE_E），不做范围校验。
   */
  static getGallerySite(): number {
    return Settings.getIntFromStr(Settings.KEY_GALLERY_SITE, Settings.DEFAULT_GALLERY_SITE);
  }

  static putGallerySite(value: number): void {
    Settings.putIntToStr(Settings.KEY_GALLERY_SITE, value);
  }

  static readonly KEY_LAUNCH_PAGE: string = 'launch_page';
  static readonly DEFAULT_LAUNCH_PAGE: number = 0;
  static readonly ACTION_HOMEPAGE: string = 'action_homepage';
  static readonly ACTION_SUBSCRIPTION: string = 'action_subscription';
  static readonly ACTION_WHATS_HOT: string = 'action_whats_hot';

  static getLaunchPage(): number {
    return Settings.getIntFromStr(Settings.KEY_LAUNCH_PAGE, Settings.DEFAULT_LAUNCH_PAGE);
  }

  static putLaunchPage(value: number): void {
    Settings.putIntToStr(Settings.KEY_LAUNCH_PAGE, value);
  }

  static getLaunchPageGalleryListSceneAction(): string {
    const value: number = Settings.getLaunchPage();
    switch (value) {
      case 1:
        return Settings.ACTION_SUBSCRIPTION;
      case 2:
        return Settings.ACTION_WHATS_HOT;
      case 0:
      default:
        return Settings.ACTION_HOMEPAGE;
    }
  }

  // ── 列表 / 缩略图 / 搜索默认（上游 L451–L580）────────────────────────────

  static readonly KEY_LIST_MODE: string = 'list_mode';
  static readonly DEFAULT_LIST_MODE: number = 0;

  static getListMode(): number {
    return Settings.getIntFromStr(Settings.KEY_LIST_MODE, Settings.DEFAULT_LIST_MODE);
  }

  static putListMode(value: number): void {
    Settings.putIntToStr(Settings.KEY_LIST_MODE, value);
  }

  static readonly KEY_DETAIL_SIZE: string = 'detail_size';
  static readonly DEFAULT_DETAIL_SIZE: number = 0;

  static getDetailSize(): number {
    return Settings.getIntFromStr(Settings.KEY_DETAIL_SIZE, Settings.DEFAULT_DETAIL_SIZE);
  }

  static putDetailSize(value: number): void {
    Settings.putIntToStr(Settings.KEY_DETAIL_SIZE, value);
  }

  static getDetailSizeResId(): string {
    switch (Settings.getDetailSize()) {
      case 1:
        return 'app.float.gallery_list_column_width_short';
      case 0:
      default:
        return 'app.float.gallery_list_column_width_long';
    }
  }

  static readonly KEY_THUMB_SIZE: string = 'thumb_size';
  static readonly DEFAULT_THUMB_SIZE: number = 1;

  static getThumbSize(): number {
    return Settings.getIntFromStr(Settings.KEY_THUMB_SIZE, Settings.DEFAULT_THUMB_SIZE);
  }

  static putThumbSize(value: number): void {
    Settings.putIntToStr(Settings.KEY_THUMB_SIZE, value);
  }

  static getThumbSizeResId(): string {
    switch (Settings.getThumbSize()) {
      case 0:
        return 'app.float.gallery_grid_column_width_large';
      case 2:
        return 'app.float.gallery_grid_column_width_small';
      case 1:
      default:
        return 'app.float.gallery_grid_column_width_middle';
    }
  }

  static readonly KEY_FIX_THUMB_URL: string = 'fix_thumb_url';
  static readonly DEFAULT_FIX_THUMB_URL: boolean = false;

  static getFixThumbUrl(): boolean {
    return Settings.getBoolean(Settings.KEY_FIX_THUMB_URL, Settings.DEFAULT_FIX_THUMB_URL);
  }

  static putFixThumbUrl(value: boolean): void {
    Settings.putBoolean(Settings.KEY_FIX_THUMB_URL, value);
  }

  static readonly KEY_SHOW_TAG_TRANSLATIONS: string = 'show_tag_translations';
  static readonly DEFAULT_SHOW_TAG_TRANSLATIONS: boolean = true;

  static getShowTagTranslations(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_TAG_TRANSLATIONS, Settings.DEFAULT_SHOW_TAG_TRANSLATIONS);
  }

  static putShowTagTranslations(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_TAG_TRANSLATIONS, value);
  }

  static readonly KEY_DEFAULT_CATEGORIES: string = 'default_categories';
  static readonly DEFAULT_DEFAULT_CATEGORIES: number = 0x3ff;

  static getDefaultCategories(): number {
    return Settings.getInt(Settings.KEY_DEFAULT_CATEGORIES, Settings.DEFAULT_DEFAULT_CATEGORIES);
  }

  static putDefaultCategories(value: number): void {
    const cfg: EhConfig | null = Settings.sEhConfig;
    if (cfg !== null) {
      cfg.defaultCategories = value;
      cfg.setDirty();
    }
    Settings.putInt(Settings.KEY_DEFAULT_CATEGORIES, value);
  }

  static readonly KEY_EXCLUDED_TAG_NAMESPACES: string = 'excluded_tag_namespaces';
  static readonly DEFAULT_EXCLUDED_TAG_NAMESPACES: number = 0;

  static getExcludedTagNamespaces(): number {
    return Settings.getInt(Settings.KEY_EXCLUDED_TAG_NAMESPACES, Settings.DEFAULT_EXCLUDED_TAG_NAMESPACES);
  }

  static putExcludedTagNamespaces(value: number): void {
    const cfg: EhConfig | null = Settings.sEhConfig;
    if (cfg !== null) {
      cfg.excludedNamespaces = value;
      cfg.setDirty();
    }
    Settings.putInt(Settings.KEY_EXCLUDED_TAG_NAMESPACES, value);
  }

  static readonly KEY_EXCLUDED_LANGUAGES: string = 'excluded_languages';
  static readonly DEFAULT_EXCLUDED_LANGUAGES: string | null = null;

  static getExcludedLanguages(): string | null {
    return Settings.getStringNullable(Settings.KEY_EXCLUDED_LANGUAGES, Settings.DEFAULT_EXCLUDED_LANGUAGES);
  }

  static putExcludedLanguages(value: string | null): void {
    const cfg: EhConfig | null = Settings.sEhConfig;
    if (cfg !== null) {
      cfg.excludedLanguages = (value === null) ? '' : value;
      cfg.setDirty();
    }
    Settings.putStringNullable(Settings.KEY_EXCLUDED_LANGUAGES, value);
  }

  static readonly KEY_CELLULAR_NETWORK_WARNING: string = 'cellular_network_warning';
  static readonly DEFAULT_CELLULAR_NETWORK_WARNING: boolean = false;

  static getCellularNetworkWarning(): boolean {
    return Settings.getBoolean(Settings.KEY_CELLULAR_NETWORK_WARNING, Settings.DEFAULT_CELLULAR_NETWORK_WARNING);
  }

  static putCellularNetworkWarning(value: boolean): void {
    Settings.putBoolean(Settings.KEY_CELLULAR_NETWORK_WARNING, value);
  }

  // ── 阅读缓存大小（上游 L1214–L1218）─────────────────────────────────────

  static readonly KEY_READ_CACHE_SIZE: string = 'read_cache_size';
  static readonly DEFAULT_READ_CACHE_SIZE: number = 160;

  static getReadCacheSize(): number {
    return Settings.getIntFromStr(Settings.KEY_READ_CACHE_SIZE, Settings.DEFAULT_READ_CACHE_SIZE);
  }

  static putReadCacheSize(value: number): void {
    Settings.putIntToStr(Settings.KEY_READ_CACHE_SIZE, value);
  }

  // ── 下载位置（上游 L775–L806）─────────────────────────────────────────────

  static readonly KEY_DOWNLOAD_SAVE_SCHEME: string = 'image_scheme';
  static readonly KEY_DOWNLOAD_SAVE_AUTHORITY: string = 'image_authority';
  static readonly KEY_DOWNLOAD_SAVE_PATH: string = 'image_path';
  static readonly KEY_DOWNLOAD_SAVE_QUERY: string = 'image_query';
  static readonly KEY_DOWNLOAD_SAVE_FRAGMENT: string = 'image_fragment';

  /** 测试/宿主可注入 `.nomedia` 处理钩子；不注入时直接对 UniFile 执行 `.nomedia` 维护 */
  static setDownloadLocationNoMediaHook(hook: ((location: UniFile, mediaScan: boolean) => void) | null): void {
    Settings.sDownloadLocationNoMediaHook = hook;
  }

  static getDownloadLocation(): UniFile | null {
    let dir: UniFile | null = null;
    try {
      const scheme: string | undefined = Settings.getStringOrNone(Settings.KEY_DOWNLOAD_SAVE_SCHEME);
      const authority: string | undefined = Settings.getStringOrNone(Settings.KEY_DOWNLOAD_SAVE_AUTHORITY);
      const path: string | undefined = Settings.getStringOrNone(Settings.KEY_DOWNLOAD_SAVE_PATH);
      const query: string | undefined = Settings.getStringOrNone(Settings.KEY_DOWNLOAD_SAVE_QUERY);
      const fragment: string | undefined = Settings.getStringOrNone(Settings.KEY_DOWNLOAD_SAVE_FRAGMENT);
      const uri: string = Settings.buildUri(scheme, authority, path, query, fragment);
      if (uri.length > 0) {
        dir = UniFile.fromUri(uri);
      }
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      // Ignore
    }
    if (dir !== null) {
      return dir;
    }
    return UniFile.fromFile(AppConfig.getDefaultDownloadDir());
  }

  /** 对应上游 putDownloadLocation(UniFile)（L799–L806） */
  static putDownloadLocation(location: UniFile): void {
    const uri: string = location.getUri();
    Settings.putStringNullable(Settings.KEY_DOWNLOAD_SAVE_SCHEME, Settings.uriPart(uri, 'scheme'));
    Settings.putStringNullable(Settings.KEY_DOWNLOAD_SAVE_AUTHORITY, Settings.uriPart(uri, 'authority'));
    Settings.putStringNullable(Settings.KEY_DOWNLOAD_SAVE_PATH, Settings.uriPart(uri, 'path'));
    Settings.putStringNullable(Settings.KEY_DOWNLOAD_SAVE_QUERY, Settings.uriPart(uri, 'query'));
    Settings.putStringNullable(Settings.KEY_DOWNLOAD_SAVE_FRAGMENT, Settings.uriPart(uri, 'fragment'));

    const mediaScan: boolean = Settings.getMediaScan();
    if (Settings.sDownloadLocationNoMediaHook !== null) {
      Settings.sDownloadLocationNoMediaHook(location, mediaScan);
      return;
    }
    try {
      if (mediaScan) {
        if (typeof location.subFile === 'function') {
          const noMedia: UniFile | null = location.subFile('.nomedia');
          if (noMedia !== null && noMedia.isFile()) {
            noMedia.delete();
          }
        }
      } else if (typeof location.createFile === 'function') {
        location.createFile('.nomedia');
      }
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      // Ignore IO/mock unavailability on non-file UniFile
    }
  }

  /** `getString(key, null)` 的等价（仅缺省时为 undefined；保留空串 authority） */
  private static getStringOrNone(key: string): string | undefined {
    const v: string | null = Settings.getStringNullable(key, null);
    return v === null ? undefined : v;
  }

  /** 按 Android Uri.Builder 的输出格式拼：scheme://authority + path [?query][#fragment] */
  private static buildUri(scheme: string | undefined, authority: string | undefined,
    path: string | undefined, query: string | undefined, fragment: string | undefined): string {
    const hasQuery: boolean = query !== undefined && query.length > 0;
    const hasFragment: boolean = fragment !== undefined && fragment.length > 0;
    if (scheme === undefined && authority === undefined && path === undefined
      && !hasQuery && !hasFragment) {
      return '';
    }
    let uri: string = '';
    if (scheme !== undefined && scheme.length > 0) {
      uri += scheme + ':';
    }
    if (authority !== undefined) {
      uri += '//' + authority;
    } else if (scheme === 'file' && path !== undefined && path.startsWith('/')) {
      uri += '//';
    }
    if (path !== undefined) {
      uri += path;
    }
    if (hasQuery) {
      uri += '?' + (query as string);
    }
    if (hasFragment) {
      uri += '#' + (fragment as string);
    }
    return uri;
  }

  /** 从 URI 字符串取分量（对应 Uri.getScheme/getEncodedAuthority/getEncodedPath/…） */
  private static uriPart(uri: string, part: string): string | null {
    let rest: string = uri;
    let fragmentPart: string | undefined = undefined;
    let queryPart: string | undefined = undefined;
    const hashIdx: number = rest.indexOf('#');
    if (hashIdx >= 0) {
      fragmentPart = rest.substring(hashIdx + 1);
      rest = rest.substring(0, hashIdx);
    }
    const queryIdx: number = rest.indexOf('?');
    if (queryIdx >= 0) {
      queryPart = rest.substring(queryIdx + 1);
      rest = rest.substring(0, queryIdx);
    }
    const colonIdx: number = rest.indexOf(':');
    const schemePart: string | undefined = colonIdx >= 0 ? rest.substring(0, colonIdx) : undefined;
    let authorityPart: string | undefined = undefined;
    let pathPart: string | undefined = undefined;
    if (colonIdx >= 0 && rest.substring(colonIdx + 1).startsWith('//')) {
      const afterScheme: string = rest.substring(colonIdx + 3);
      const slashIdx: number = afterScheme.indexOf('/');
      if (slashIdx >= 0) {
        authorityPart = afterScheme.substring(0, slashIdx);
        pathPart = afterScheme.substring(slashIdx);
      } else {
        authorityPart = afterScheme;
      }
    } else if (colonIdx >= 0) {
      pathPart = rest.substring(colonIdx + 1);
    }

    if (part === 'scheme') {
      return schemePart === undefined ? null : schemePart;
    } else if (part === 'authority') {
      return authorityPart === undefined ? null : authorityPart;
    } else if (part === 'path') {
      return pathPart === undefined ? null : pathPart;
    } else if (part === 'query') {
      return queryPart === undefined ? null : queryPart;
    } else {
      return fragmentPart === undefined ? null : fragmentPart;
    }
  }

  // ── 归档任务（上游用独立的 sArchiverPre，L102–L204）────────────────────────

  private static aGetString(key: string, defValue: string): string {
    const pref: preferences.Preferences | null = Settings.sArchiverPref;
    if (pref === null) {
      return Settings.sArchiverMem.get(key) ?? defValue;
    }
    try {
      const v: preferences.ValueType = pref.getSync(key, defValue);
      return (typeof v === 'string') ? (v as string) : defValue;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return defValue;
    }
  }

  private static aPutString(key: string, value: string): void {
    Settings.writeArchiverPref(key, value, value);
  }

  private static aGetNumber(key: string, defValue: number): number {
    const pref: preferences.Preferences | null = Settings.sArchiverPref;
    if (pref === null) {
      const v: string | undefined = Settings.sArchiverMem.get(key);
      return (v === undefined) ? defValue : NumberUtils.parseIntSafely(v, defValue);
    }
    try {
      const v: preferences.ValueType = pref.getSync(key, defValue);
      return (typeof v === 'number') ? (v as number) : defValue;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return defValue;
    }
  }

  private static aPutNumber(key: string, value: number): void {
    Settings.writeArchiverPref(key, `${value}`, value);
  }

  private static aGetBoolean(key: string, defValue: boolean): boolean {
    const pref: preferences.Preferences | null = Settings.sArchiverPref;
    if (pref === null) {
      const v: string | undefined = Settings.sArchiverMem.get(key);
      if (v === undefined) {
        return defValue;
      }
      if (v === 'true') {
        return true;
      }
      if (v === 'false') {
        return false;
      }
      return defValue;
    }
    try {
      const v: preferences.ValueType = pref.getSync(key, defValue);
      return (typeof v === 'boolean') ? (v as boolean) : defValue;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return defValue;
    }
  }

  private static aPutBoolean(key: string, value: boolean): void {
    Settings.writeArchiverPref(key, value ? 'true' : 'false', value);
  }

  /** 对应上游 getArchiverDownloadId(long gid)：默认 -1 */
  static getArchiverDownloadId(gid: number): number {
    return Settings.aGetNumber(`${gid}DId`, -1);
  }

  static putArchiverDownloadId(gid: number, taskId: number): void {
    Settings.aPutNumber(`${gid}DId`, taskId);
  }

  static async deleteArchiverDownloadId(gid: number): Promise<boolean> {
    return Settings.aDelete(`${gid}DId`);
  }

  /** 对应上游 getArchiverDownloadUrl(long taskId)：默认 "" */
  static getArchiverDownloadUrl(taskId: number): string {
    return Settings.aGetString(`${taskId}Url`, '');
  }

  static putArchiverDownloadUrl(taskId: number, url: string): void {
    Settings.aPutString(`${taskId}Url`, url);
  }

  /** 对应上游 getArchiverDownloadPaused(long taskId) */
  static getArchiverDownloadPaused(taskId: number): boolean {
    return Settings.aGetBoolean(`${taskId}Paused`, false);
  }

  static putArchiverDownloadPaused(taskId: number, paused: boolean): void {
    Settings.aPutBoolean(`${taskId}Paused`, paused);
  }

  /** 对应上游 getArchiverDownloadTotal(long taskId)：默认 -1 */
  static getArchiverDownloadTotal(taskId: number): number {
    return Settings.aGetNumber(`${taskId}Total`, -1);
  }

  static putArchiverDownloadTotal(taskId: number, total: number): void {
    Settings.aPutNumber(`${taskId}Total`, total);
  }

  /** 删除一个归档任务的四个键（对应上游 deleteArchiverDownload/Paused/Total/Url，返回是否删掉了） */
  static async deleteArchiverDownload(taskId: number): Promise<boolean> {
    const a: boolean = await Settings.aDelete(`${taskId}`);
    const b: boolean = await Settings.aDelete(`${taskId}Paused`);
    const c: boolean = await Settings.aDelete(`${taskId}Total`);
    const d: boolean = await Settings.aDelete(`${taskId}Url`);
    return a || b || c || d;
  }

  /** 对应上游 getArchiverDownload(long taskId)（Settings.java L109） */
  static getArchiverDownload(taskId: number): GalleryInfo | null {
    const s: string = Settings.aGetString(`${taskId}`, '');
    if (s.length === 0) {
      return null;
    }
    try {
      return GalleryInfo.fromJson(s);
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      return null;
    }
  }

  /** 对应上游 putArchiverDownload(long taskId, GalleryInfo info)（L117） */
  static putArchiverDownload(taskId: number, info: GalleryInfo): void {
    Settings.aPutString(`${taskId}`, info.toJson());
  }

  // ── 下载顺序 / 分页 / 标签（上游 L819–L875 / L1492–L1515）──────────────

  static readonly KEY_DOWNLOAD_ORDER_ASC: string = 'download_order_asc';

  /** 对应上游 getDownloadOrder()：返回 boolean，默认 true */
  static getDownloadOrder(): boolean {
    return Settings.getBoolean(Settings.KEY_DOWNLOAD_ORDER_ASC, true);
  }

  /** 对应上游 setDownloadOrder(boolean) */
  static setDownloadOrder(value: boolean): void {
    Settings.putBoolean(Settings.KEY_DOWNLOAD_ORDER_ASC, value);
  }

  static readonly KEY_DOWNLOAD_LIST_PAGINATION: string = 'download_list_pagination';
  static readonly IS_DOWNLOAD_LIST_PAGINATION: boolean = true;

  static getDownloadPagination(): boolean {
    return Settings.getBoolean(Settings.KEY_DOWNLOAD_LIST_PAGINATION, Settings.IS_DOWNLOAD_LIST_PAGINATION);
  }

  static setDownloadPagination(value: boolean): void {
    Settings.putBoolean(Settings.KEY_DOWNLOAD_LIST_PAGINATION, value);
  }

  static readonly KEY_RECENT_DOWNLOAD_LABEL: string = 'recent_download_label';
  static readonly DEFAULT_RECENT_DOWNLOAD_LABEL: string | null = null;

  static getRecentDownloadLabel(): string | null {
    return Settings.getStringNullable(Settings.KEY_RECENT_DOWNLOAD_LABEL, Settings.DEFAULT_RECENT_DOWNLOAD_LABEL);
  }

  static putRecentDownloadLabel(value: string | null): void {
    Settings.putStringNullable(Settings.KEY_RECENT_DOWNLOAD_LABEL, value);
  }

  static readonly KEY_HAS_DEFAULT_DOWNLOAD_LABEL: string = 'has_default_download_label';
  static readonly DEFAULT_HAS_DOWNLOAD_LABEL: boolean = false;

  static getHasDefaultDownloadLabel(): boolean {
    return Settings.getBoolean(Settings.KEY_HAS_DEFAULT_DOWNLOAD_LABEL, Settings.DEFAULT_HAS_DOWNLOAD_LABEL);
  }

  static putHasDefaultDownloadLabel(hasDefaultDownloadLabel: boolean): void {
    Settings.putBoolean(Settings.KEY_HAS_DEFAULT_DOWNLOAD_LABEL, hasDefaultDownloadLabel);
  }

  static readonly KEY_DEFAULT_DOWNLOAD_LABEL: string = 'default_download_label';
  static readonly DEFAULT_DOWNLOAD_LABEL: string | null = null;

  static getDefaultDownloadLabel(): string | null {
    return Settings.getStringNullable(Settings.KEY_DEFAULT_DOWNLOAD_LABEL, Settings.DEFAULT_DOWNLOAD_LABEL);
  }

  static putDefaultDownloadLabel(value: string | null): void {
    Settings.putStringNullable(Settings.KEY_DEFAULT_DOWNLOAD_LABEL, value);
  }

  // ── 归档 pending 扫描（上游 L174–L204）───────────────────────────────────

  /** 对应上游 hasPendingArchiverDownloads()：只要存在 "DId" 键即 true */
  static hasPendingArchiverDownloads(): boolean {
    let found: boolean = false;
    Settings.sArchiverMem.forEach((_v: string, k: string) => {
      if (k.endsWith('DId')) {
        found = true;
      }
    });
    return found;
  }

  /** 对应上游 getPendingArchiverDownloadIds(): long[] → number[]（值即 taskId） */
  static getPendingArchiverDownloadIds(): number[] {
    const ids: number[] = [];
    Settings.sArchiverMem.forEach((v: string, k: string) => {
      if (k.endsWith('DId')) {
        const id: number = NumberUtils.parseLongSafely(v, -1);
        if (id !== -1) {
          ids.push(id);
        }
      }
    });
    return ids;
  }

  // ── 归档键分项删除（上游 L145/L157/L169）──────────────────────────────────

  static async deleteArchiverDownloadUrl(taskId: number): Promise<boolean> {
    return Settings.aDelete(`${taskId}Url`);
  }

  static async deleteArchiverDownloadPaused(taskId: number): Promise<boolean> {
    return Settings.aDelete(`${taskId}Paused`);
  }

  static async deleteArchiverDownloadTotal(taskId: number): Promise<boolean> {
    return Settings.aDelete(`${taskId}Total`);
  }

  /** 删除一个 archiver 键（区分未 attach 抛错 / 不存在返回 false / 落盘成功返回 true / 失败抛错） */
  static async aDelete(key: string): Promise<boolean> {
    const pref: preferences.Preferences | null = Settings.sArchiverPref;
    if (pref === null) {
      throw new Error('Settings not attached: call Settings.attach(context) before deleting preferences');
    }
    try {
      if (!pref.hasSync(key)) {
        Settings.sArchiverMem.delete(key);
        return false;
      }
      pref.deleteSync(key);
      await pref.flush();
      Settings.sArchiverMem.delete(key);
      return true;
    } catch (e) {
      hilog.error(0x0001, Settings.TAG, 'aDelete(%{public}s) failed: %{public}s', key, `${(e as Error).message}`);
      throw e as Error;
    }
  }

  // ── 图片预载 / 多线程下载（上游 L896–L916）─────────────────────────────

  static readonly KEY_MULTI_THREAD_DOWNLOAD: string = 'download_thread';
  static readonly DEFAULT_MULTI_THREAD_DOWNLOAD: number = 3;

  static getMultiThreadDownload(): number {
    return Settings.getIntFromStr(Settings.KEY_MULTI_THREAD_DOWNLOAD, Settings.DEFAULT_MULTI_THREAD_DOWNLOAD);
  }

  static putMultiThreadDownload(value: number): void {
    Settings.putIntToStr(Settings.KEY_MULTI_THREAD_DOWNLOAD, value);
  }

  static readonly KEY_PRELOAD_IMAGE: string = 'preload_image';
  static readonly DEFAULT_PRELOAD_IMAGE: number = 5;

  static getPreloadImage(): number {
    return Settings.getIntFromStr(Settings.KEY_PRELOAD_IMAGE, Settings.DEFAULT_PRELOAD_IMAGE);
  }

  static putPreloadImage(value: number): void {
    Settings.putIntToStr(Settings.KEY_PRELOAD_IMAGE, value);
  }

  // ── 阅读设置（GalleryActivity，上游 L584–L765）────────────────────────────

  static readonly LAYOUT_LEFT_TO_RIGHT: number = 0;
  static readonly LAYOUT_RIGHT_TO_LEFT: number = 1;
  static readonly LAYOUT_TOP_TO_BOTTOM: number = 2;

  static readonly SCALE_ORIGIN: number = 0;
  static readonly SCALE_FIT_WIDTH: number = 1;
  static readonly SCALE_FIT_HEIGHT: number = 2;
  static readonly SCALE_FIT: number = 3;
  static readonly SCALE_FIXED: number = 4;

  static readonly START_POSITION_TOP_LEFT: number = 0;
  static readonly START_POSITION_TOP_RIGHT: number = 1;
  static readonly START_POSITION_BOTTOM_LEFT: number = 2;
  static readonly START_POSITION_BOTTOM_RIGHT: number = 3;
  static readonly START_POSITION_CENTER: number = 4;

  static readonly KEY_SCREEN_ROTATION: string = 'screen_rotation';
  static readonly DEFAULT_SCREEN_ROTATION: number = 0;

  static getScreenRotation(): number {
    return Settings.getIntFromStr(Settings.KEY_SCREEN_ROTATION, Settings.DEFAULT_SCREEN_ROTATION);
  }

  static putScreenRotation(value: number): void {
    Settings.putIntToStr(Settings.KEY_SCREEN_ROTATION, value);
  }

  static readonly KEY_READING_REFRESH_RATE: string = 'reading_refresh_rate';
  static readonly DEFAULT_READING_REFRESH_RATE: number = 0;

  static getReadingRefreshRateHz(): number {
    return ReadingRefreshRate.sanitize(
      Settings.getIntFromStr(Settings.KEY_READING_REFRESH_RATE, Settings.DEFAULT_READING_REFRESH_RATE));
  }

  static putReadingRefreshRateHz(value: number): void {
    Settings.putIntToStr(Settings.KEY_READING_REFRESH_RATE, ReadingRefreshRate.sanitize(value));
  }

  static readonly KEY_READING_DIRECTION: string = 'reading_direction';
  static readonly DEFAULT_READING_DIRECTION: number = Settings.LAYOUT_RIGHT_TO_LEFT;

  static getReadingDirection(): number {
    return Settings.sanitizeLayoutMode(
      Settings.getIntFromStr(Settings.KEY_READING_DIRECTION, Settings.DEFAULT_READING_DIRECTION));
  }

  static putReadingDirection(value: number): void {
    Settings.putIntToStr(Settings.KEY_READING_DIRECTION, value);
  }

  static readonly KEY_PAGE_SCALING: string = 'page_scaling';
  static readonly DEFAULT_PAGE_SCALING: number = Settings.SCALE_FIT;

  static getPageScaling(): number {
    return Settings.sanitizeScaleMode(
      Settings.getIntFromStr(Settings.KEY_PAGE_SCALING, Settings.DEFAULT_PAGE_SCALING));
  }

  static putPageScaling(value: number): void {
    Settings.putIntToStr(Settings.KEY_PAGE_SCALING, value);
  }

  static readonly KEY_START_POSITION: string = 'start_position';
  static readonly DEFAULT_START_POSITION: number = Settings.START_POSITION_TOP_RIGHT;

  static getStartPosition(): number {
    return Settings.sanitizeStartPosition(
      Settings.getIntFromStr(Settings.KEY_START_POSITION, Settings.DEFAULT_START_POSITION));
  }

  static putStartPosition(value: number): void {
    Settings.putIntToStr(Settings.KEY_START_POSITION, value);
  }

  static sanitizeLayoutMode(layoutMode: number): number {
    if (layoutMode !== Settings.LAYOUT_LEFT_TO_RIGHT && layoutMode !== Settings.LAYOUT_RIGHT_TO_LEFT
      && layoutMode !== Settings.LAYOUT_TOP_TO_BOTTOM) {
      return Settings.LAYOUT_LEFT_TO_RIGHT;
    }
    return layoutMode;
  }

  static sanitizeScaleMode(scaleMode: number): number {
    if (scaleMode !== Settings.SCALE_ORIGIN && scaleMode !== Settings.SCALE_FIT_WIDTH
      && scaleMode !== Settings.SCALE_FIT_HEIGHT && scaleMode !== Settings.SCALE_FIT
      && scaleMode !== Settings.SCALE_FIXED) {
      return Settings.SCALE_FIT;
    }
    return scaleMode;
  }

  static sanitizeStartPosition(startPosition: number): number {
    if (startPosition !== Settings.START_POSITION_TOP_LEFT
      && startPosition !== Settings.START_POSITION_TOP_RIGHT
      && startPosition !== Settings.START_POSITION_BOTTOM_LEFT
      && startPosition !== Settings.START_POSITION_BOTTOM_RIGHT
      && startPosition !== Settings.START_POSITION_CENTER) {
      return Settings.START_POSITION_TOP_RIGHT;
    }
    return startPosition;
  }

  static readonly KEY_START_TRANSFER_TIME: string = 'start_transfer_time';
  static readonly DEFAULT_START_TRANSFER_TIME: number = 2;

  static getStartTransferTime(): number {
    return Settings.getInt(Settings.KEY_START_TRANSFER_TIME, Settings.DEFAULT_START_TRANSFER_TIME);
  }

  static putStartTransferTime(value: number): void {
    Settings.putInt(Settings.KEY_START_TRANSFER_TIME, value);
  }

  static readonly KEY_KEEP_SCREEN_ON: string = 'keep_screen_on';
  static readonly DEFAULT_KEEP_SCREEN_ON: boolean = false;

  static getKeepScreenOn(): boolean {
    return Settings.getBoolean(Settings.KEY_KEEP_SCREEN_ON, Settings.DEFAULT_KEEP_SCREEN_ON);
  }

  static putKeepScreenOn(value: boolean): void {
    Settings.putBoolean(Settings.KEY_KEEP_SCREEN_ON, value);
  }

  static readonly KEY_SHOW_CLOCK: string = 'gallery_show_clock';
  static readonly DEFAULT_SHOW_CLOCK: boolean = true;

  static getShowClock(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_CLOCK, Settings.DEFAULT_SHOW_CLOCK);
  }

  static putShowClock(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_CLOCK, value);
  }

  static readonly KEY_SHOW_PROGRESS: string = 'gallery_show_progress';
  static readonly DEFAULT_SHOW_PROGRESS: boolean = true;

  static getShowProgress(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_PROGRESS, Settings.DEFAULT_SHOW_PROGRESS);
  }

  static putShowProgress(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_PROGRESS, value);
  }

  static readonly KEY_SHOW_BATTERY: string = 'gallery_show_battery';
  static readonly DEFAULT_SHOW_BATTERY: boolean = true;

  static getShowBattery(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_BATTERY, Settings.DEFAULT_SHOW_BATTERY);
  }

  static putShowBattery(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_BATTERY, value);
  }

  static readonly KEY_SHOW_PAGE_INTERVAL: string = 'gallery_show_page_interval';
  static readonly DEFAULT_SHOW_PAGE_INTERVAL: boolean = true;

  static getShowPageInterval(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_PAGE_INTERVAL, Settings.DEFAULT_SHOW_PAGE_INTERVAL);
  }

  static putShowPageInterval(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_PAGE_INTERVAL, value);
  }

  static readonly KEY_PAGE_TURN_ANIMATION: string = 'gallery_page_turn_animation';
  static readonly DEFAULT_PAGE_TURN_ANIMATION: boolean = false;

  static getPageTurnAnimation(): boolean {
    return Settings.getBoolean(Settings.KEY_PAGE_TURN_ANIMATION, Settings.DEFAULT_PAGE_TURN_ANIMATION);
  }

  static putPageTurnAnimation(value: boolean): void {
    Settings.putBoolean(Settings.KEY_PAGE_TURN_ANIMATION, value);
  }

  static readonly KEY_VOLUME_PAGE: string = 'volume_page';
  static readonly DEFAULT_VOLUME_PAGE: boolean = false;

  static getVolumePage(): boolean {
    return Settings.getBoolean(Settings.KEY_VOLUME_PAGE, Settings.DEFAULT_VOLUME_PAGE);
  }

  static putVolumePage(value: boolean): void {
    Settings.putBoolean(Settings.KEY_VOLUME_PAGE, value);
  }

  static readonly KEY_REVERSE_VOLUME_PAGE: string = 'reverse_volume_page';
  static readonly DEFAULT_REVERSE_VOLUME_PAGE: boolean = false;

  static getReverseVolumePage(): boolean {
    return Settings.getBoolean(Settings.KEY_REVERSE_VOLUME_PAGE, Settings.DEFAULT_REVERSE_VOLUME_PAGE);
  }

  static putReverseVolumePage(value: boolean): void {
    Settings.putBoolean(Settings.KEY_REVERSE_VOLUME_PAGE, value);
  }

  static readonly KEY_READING_FULLSCREEN: string = 'reading_fullscreen';
  static readonly VALUE_READING_FULLSCREEN: boolean = true;

  static getReadingFullscreen(): boolean {
    return Settings.getBoolean(Settings.KEY_READING_FULLSCREEN, Settings.VALUE_READING_FULLSCREEN);
  }

  static putReadingFullscreen(value: boolean): void {
    Settings.putBoolean(Settings.KEY_READING_FULLSCREEN, value);
  }

  static readonly KEY_CUSTOM_SCREEN_LIGHTNESS: string = 'custom_screen_lightness';
  static readonly DEFAULT_CUSTOM_SCREEN_LIGHTNESS: boolean = false;

  static getCustomScreenLightness(): boolean {
    return Settings.getBoolean(Settings.KEY_CUSTOM_SCREEN_LIGHTNESS, Settings.DEFAULT_CUSTOM_SCREEN_LIGHTNESS);
  }

  static putCustomScreenLightness(value: boolean): void {
    Settings.putBoolean(Settings.KEY_CUSTOM_SCREEN_LIGHTNESS, value);
  }

  static readonly KEY_SCREEN_LIGHTNESS: string = 'screen_lightness';
  static readonly DEFAULT_SCREEN_LIGHTNESS: number = 50;

  static getScreenLightness(): number {
    return Settings.getInt(Settings.KEY_SCREEN_LIGHTNESS, Settings.DEFAULT_SCREEN_LIGHTNESS);
  }

  static putScreenLightness(value: number): void {
    Settings.putInt(Settings.KEY_SCREEN_LIGHTNESS, value);
  }

  // ── 隐私与安全（上游 L767–L775 / L1197–L1213）────────────────────────────

  static readonly KEY_SEC_SECURITY: string = 'enable_secure';
  static readonly VALUE_SEC_SECURITY: boolean = false;

  static getEnabledSecurity(): boolean {
    return Settings.getBoolean(Settings.KEY_SEC_SECURITY, Settings.VALUE_SEC_SECURITY);
  }

  /** 已修正上游误写 `KEY_READING_FULLSCREEN` 的缺陷，写入 `KEY_SEC_SECURITY` */
  static putEnabledSecurity(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SEC_SECURITY, value);
  }

  static readonly KEY_SECURITY: string = 'security';
  static readonly DEFAULT_SECURITY: string = '';
  private static readonly SECURITY_PATTERN_PREFIX: string = 'ehp:';
  private static readonly SECURITY_HEX_PREFIX: string = 'ehx:';

  /**
   * Encodes lock pattern strings (`\x00`..`\x08`) into XML-safe ASCII before writing to
   * `@ohos.data.preferences` (libxml2 rejects `< 0x20` control chars and drops the whole store).
   */
  static encodeSecurityForPref(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    let allCells: boolean = true;
    let hasControlOrPrefix: boolean =
      raw.startsWith(Settings.SECURITY_PATTERN_PREFIX) ||
      raw.startsWith(Settings.SECURITY_HEX_PREFIX);
    for (let i = 0; i < raw.length; i++) {
      const code: number = raw.charCodeAt(i);
      if (code < 0 || code > 8) {
        allCells = false;
      }
      if (code < 0x20) {
        hasControlOrPrefix = true;
      }
    }
    if (allCells) {
      let digits: string = '';
      for (let i = 0; i < raw.length; i++) {
        digits += `${raw.charCodeAt(i)}`;
      }
      return Settings.SECURITY_PATTERN_PREFIX + digits;
    }
    if (hasControlOrPrefix) {
      let hex: string = '';
      for (let i = 0; i < raw.length; i++) {
        hex += raw.charCodeAt(i).toString(16).toUpperCase().padStart(4, '0');
      }
      return Settings.SECURITY_HEX_PREFIX + hex;
    }
    return raw;
  }

  /** Decodes `ehp:` / `ehx:` encoded security strings back to raw LockPatternUtils chars. */
  static decodeSecurityFromPref(stored: string): string {
    if (stored.length === 0) {
      return '';
    }
    if (stored.startsWith(Settings.SECURITY_PATTERN_PREFIX)) {
      const body: string = stored.substring(Settings.SECURITY_PATTERN_PREFIX.length);
      let decoded: string = '';
      for (let i = 0; i < body.length; i++) {
        const ch: number = body.charCodeAt(i);
        if (ch >= 48 && ch <= 56) {
          decoded += String.fromCharCode(ch - 48);
        }
      }
      return decoded;
    }
    if (stored.startsWith(Settings.SECURITY_HEX_PREFIX)) {
      const body: string = stored.substring(Settings.SECURITY_HEX_PREFIX.length);
      if (body.length % 4 !== 0) {
        return stored;
      }
      let decoded: string = '';
      for (let i = 0; i < body.length; i += 4) {
        const parsed: number = Number.parseInt(body.substring(i, i + 4), 16);
        if (Number.isNaN(parsed)) {
          return stored;
        }
        decoded += String.fromCharCode(parsed);
      }
      return decoded;
    }
    return stored;
  }

  static getSecurity(): string {
    const raw: string = Settings.getString(Settings.KEY_SECURITY, Settings.DEFAULT_SECURITY);
    return Settings.decodeSecurityFromPref(raw);
  }

  static putSecurity(value: string): void {
    const encoded: string = Settings.encodeSecurityForPref(value);
    Settings.putString(Settings.KEY_SECURITY, encoded);
  }

  /** Flushes pending main preferences writes to disk immediately when immediate durability is required. */
  static async flush(): Promise<void> {
    const pref: preferences.Preferences | null = Settings.sPref;
    if (pref === null) {
      return;
    }
    try {
      await pref.flush();
    } catch (e) {
      Settings.logFlushError('flush', e as Error);
    }
  }

  /** 对齐上游是否有手势锁（`!TextUtils.isEmpty(getSecurity())`） */
  static hasSecurity(): boolean {
    return Settings.getSecurity().length > 0;
  }

  static readonly KEY_ENABLE_FINGERPRINT: string = 'enable_fingerprint';
  static readonly DEFAULT_ENABLE_FINGERPRINT: boolean = false;

  static getEnableFingerprint(): boolean {
    return Settings.getBoolean(Settings.KEY_ENABLE_FINGERPRINT, Settings.DEFAULT_ENABLE_FINGERPRINT);
  }

  static putEnableFingerprint(value: boolean): void {
    Settings.putBoolean(Settings.KEY_ENABLE_FINGERPRINT, value);
  }

  // ── 收藏配置（上游 L926–L1064）──────────────────────────────────────────

  private static readonly FAV_CAT_COUNT: number = 10;
  static readonly INVALID_DEFAULT_FAV_SLOT: number = -2;
  private static readonly KEY_DEFAULT_FAV_SLOT: string = 'default_favorite_2';
  private static readonly DEFAULT_DEFAULT_FAV_SLOT: number = Settings.INVALID_DEFAULT_FAV_SLOT;
  private static readonly KEY_RECENT_FAV_CAT: string = 'recent_fav_cat';
  private static readonly DEFAULT_RECENT_FAV_CAT: number = -1; // FavListUrlBuilder.FAV_CAT_ALL
  private static readonly KEY_FAV_LOCAL: string = 'fav_local';
  private static readonly KEY_FAV_CLOUD: string = 'fav_cloud';
  private static readonly DEFAULT_FAV_COUNT: number = 0;

  static getFavCat(): string[] {
    const favCat: string[] = [];
    for (let i = 0; i < Settings.FAV_CAT_COUNT; i++) {
      favCat.push(Settings.getString(`fav_cat_${i}`, `Favorites ${i}`));
    }
    return favCat;
  }

  static putFavCat(value: string[]): void {
    AssertUtils.assertEquals(Settings.FAV_CAT_COUNT, value.length);
    for (let i = 0; i < Settings.FAV_CAT_COUNT; i++) {
      Settings.putString(`fav_cat_${i}`, value[i]);
    }
  }

  static getFavCount(): number[] {
    const favCount: number[] = [];
    for (let i = 0; i < Settings.FAV_CAT_COUNT; i++) {
      favCount.push(Settings.getInt(`fav_count_${i}`, Settings.DEFAULT_FAV_COUNT));
    }
    return favCount;
  }

  static putFavCount(count: number[]): void {
    AssertUtils.assertEquals(Settings.FAV_CAT_COUNT, count.length);
    for (let i = 0; i < Settings.FAV_CAT_COUNT; i++) {
      Settings.putInt(`fav_count_${i}`, count[i]);
    }
  }

  static getFavLocalCount(): number {
    return Settings.getInt(Settings.KEY_FAV_LOCAL, Settings.DEFAULT_FAV_COUNT);
  }

  static putFavLocalCount(count: number): void {
    Settings.putInt(Settings.KEY_FAV_LOCAL, count);
  }

  static getFavCloudCount(): number {
    return Settings.getInt(Settings.KEY_FAV_CLOUD, Settings.DEFAULT_FAV_COUNT);
  }

  static putFavCloudCount(count: number): void {
    Settings.putInt(Settings.KEY_FAV_CLOUD, count);
  }

  static getRecentFavCat(): number {
    return Settings.getInt(Settings.KEY_RECENT_FAV_CAT, Settings.DEFAULT_RECENT_FAV_CAT);
  }

  static putRecentFavCat(value: number): void {
    Settings.putInt(Settings.KEY_RECENT_FAV_CAT, value);
  }

  static getDefaultFavSlot(): number {
    return Settings.getInt(Settings.KEY_DEFAULT_FAV_SLOT, Settings.DEFAULT_DEFAULT_FAV_SLOT);
  }

  static putDefaultFavSlot(value: number): void {
    Settings.putInt(Settings.KEY_DEFAULT_FAV_SLOT, value);
  }

  // ── 统一落盘失败日志 ─────────────────────────────────────────────────────

  /**
   * fire-and-forget 落盘失败的统一日志（对应上游 `apply()` 失败时系统的日志）。
   */
  private static logFlushError(key: string, e: Error): void {
    hilog.error(0x0001, Settings.TAG,
      'flush failed: key=%{public}s err=%{public}s, writes may not persist', key, e.message);
  }

  // ── 引导 / 登录态 / 事件横幅 / 限额 ──────────────────────────────────────

  static readonly KEY_GUIDE_QUICK_SEARCH: string = 'guide_quick_search';
  static readonly DEFAULT_GUIDE_QUICK_SEARCH: boolean = true;

  static getGuideQuickSearch(): boolean {
    return Settings.getBoolean(Settings.KEY_GUIDE_QUICK_SEARCH, Settings.DEFAULT_GUIDE_QUICK_SEARCH);
  }

  static putGuideQuickSearch(value: boolean): void {
    Settings.putBoolean(Settings.KEY_GUIDE_QUICK_SEARCH, value);
  }

  static readonly KEY_GUIDE_COLLECTIONS: string = 'guide_collections';
  static readonly DEFAULT_GUIDE_COLLECTIONS: boolean = true;

  static getGuideCollections(): boolean {
    return Settings.getBoolean(Settings.KEY_GUIDE_COLLECTIONS, Settings.DEFAULT_GUIDE_COLLECTIONS);
  }

  static putGuideCollections(value: boolean): void {
    Settings.putBoolean(Settings.KEY_GUIDE_COLLECTIONS, value);
  }

  static readonly KEY_GUIDE_GALLERY: string = 'guide_gallery';
  static readonly DEFAULT_GUIDE_GALLERY: boolean = true;

  /** 对应上游 `getGuideGallery()` */
  static getGuideGallery(): boolean {
    return Settings.getBoolean(Settings.KEY_GUIDE_GALLERY, Settings.DEFAULT_GUIDE_GALLERY);
  }

  /** 对应上游 `putGuideGallery(boolean)` */
  static putGuideGallery(value: boolean): void {
    Settings.putBoolean(Settings.KEY_GUIDE_GALLERY, value);
  }

  static readonly KEY_CLIPBOARD_TEXT_HASH_CODE: string = 'clipboard_text_hash_code';
  static readonly DEFAULT_CLIPBOARD_TEXT_HASH_CODE: number = 0;

  static getClipboardTextHashCode(): number {
    return Settings.getInt(Settings.KEY_CLIPBOARD_TEXT_HASH_CODE, Settings.DEFAULT_CLIPBOARD_TEXT_HASH_CODE);
  }

  static putClipboardTextHashCode(value: number): void {
    Settings.putInt(Settings.KEY_CLIPBOARD_TEXT_HASH_CODE, value);
  }

  static readonly KEY_IS_LOGIN: string = 'is_login';
  private static readonly IS_LOGIN: boolean = false;

  /** 由 net-parse 在 EhCookieStore 就绪后注入（对应上游 `Settings.isLogin()`） */
  static setLoginProvider(provider: (() => boolean) | null): void {
    Settings.sLoginProvider = provider;
  }

  /** 优先查已注入的 cookie provider；未注入时回退偏好键 `is_login` */
  static isLogin(isLoginOverride?: () => boolean): boolean {
    if (isLoginOverride !== undefined) {
      return isLoginOverride();
    }
    if (Settings.sLoginProvider !== null) {
      return Settings.sLoginProvider();
    }
    return Settings.getBoolean(Settings.KEY_IS_LOGIN, Settings.IS_LOGIN);
  }

  static setLoginState(value: boolean): void {
    Settings.putBoolean(Settings.KEY_IS_LOGIN, value);
  }

  static readonly KEY_SHOW_EH_EVENTS: string = 'show_eh_events';
  /** 上游 `private static boolean IS_SHOW_EH_EVENTS = true`（编译期总开关） */
  static readonly IS_SHOW_EH_EVENTS: boolean = true;

  /**
   * 对应上游 `getShowEhEvents()`：`开关 && isLogin()`。
   * @param isLogin 可选覆盖（测试用）；不传则走 `Settings.isLogin()`
   */
  static getShowEhEvents(isLogin?: () => boolean): boolean {
    const enabled: boolean = Settings.getBoolean(Settings.KEY_SHOW_EH_EVENTS, Settings.IS_SHOW_EH_EVENTS);
    if (!enabled) {
      return false;
    }
    return Settings.isLogin(isLogin);
  }

  /** 对应上游 `setKeyShowEhEvents(boolean)` */
  static setKeyShowEhEvents(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_EH_EVENTS, value);
  }

  static readonly KEY_SHOW_EH_LIMITS: string = 'show_eh_limits';
  static readonly IS_SHOW_EH_LIMITS: boolean = true;

  static getShowEhLimits(isLogin?: () => boolean): boolean {
    const enabled: boolean = Settings.getBoolean(Settings.KEY_SHOW_EH_LIMITS, Settings.IS_SHOW_EH_LIMITS);
    if (!enabled) {
      return false;
    }
    return Settings.isLogin(isLogin);
  }

  static setKeyShowEhLimits(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_EH_LIMITS, value);
  }

  // ── 网络 / Hosts / DoH ───────────────────────────────────────────────────

  static readonly KEY_BUILT_IN_HOSTS: string = 'built_in_hosts';
  static readonly DEFAULT_BUILT_IN_HOSTS: boolean = true;

  static getBuiltInHosts(): boolean {
    return Settings.getBoolean(Settings.KEY_BUILT_IN_HOSTS, Settings.DEFAULT_BUILT_IN_HOSTS);
  }

  static putBuiltInHosts(value: boolean): void {
    Settings.putBoolean(Settings.KEY_BUILT_IN_HOSTS, value);
  }

  static readonly KEY_BUILT_EX_HOSTS: string = 'built_ex_hosts';
  static readonly DEFAULT_BUILT_EX_HOSTS: boolean = true;

  static getBuiltEXHosts(): boolean {
    return Settings.getBoolean(Settings.KEY_BUILT_EX_HOSTS, Settings.DEFAULT_BUILT_EX_HOSTS);
  }

  static putBuiltEXHosts(value: boolean): void {
    Settings.putBoolean(Settings.KEY_BUILT_EX_HOSTS, value);
  }

  static readonly KEY_DOH: string = 'dns_over_https';
  static readonly DEFAULT_DOH: boolean = false;

  static getDoH(): boolean {
    return Settings.getBoolean(Settings.KEY_DOH, Settings.DEFAULT_DOH);
  }

  static putDoH(value: boolean): void {
    Settings.putBoolean(Settings.KEY_DOH, value);
  }

  static readonly KEY_DOMAIN_FRONTING: string = 'domain_fronting';
  static readonly DEFAULT_FRONTING: boolean = true;

  /** 对应上游 L1379：Domain Fronting 开关，默认 true */
  static getDF(): boolean {
    return Settings.getBoolean(Settings.KEY_DOMAIN_FRONTING, Settings.DEFAULT_FRONTING);
  }

  static putDF(value: boolean): void {
    Settings.putBoolean(Settings.KEY_DOMAIN_FRONTING, value);
  }

  // ── 下载（SpiderQueen / SpiderDen / DownloadService）──────────────────────

  static readonly KEY_DOWNLOAD_ORIGIN_IMAGE: string = 'download_origin_image';
  static readonly DEFAULT_DOWNLOAD_ORIGIN_IMAGE: boolean = false;

  static getDownloadOriginImage(): boolean {
    return Settings.getBoolean(Settings.KEY_DOWNLOAD_ORIGIN_IMAGE, Settings.DEFAULT_DOWNLOAD_ORIGIN_IMAGE);
  }

  static putDownloadOriginImage(value: boolean): void {
    Settings.putBoolean(Settings.KEY_DOWNLOAD_ORIGIN_IMAGE, value);
  }

  static readonly KEY_DOWNLOAD_DELAY: string = 'download_delay';
  static readonly DEFAULT_DOWNLOAD_DELAY: number = 0;

  static getDownloadDelay(): number {
    return Settings.getIntFromStr(Settings.KEY_DOWNLOAD_DELAY, Settings.DEFAULT_DOWNLOAD_DELAY);
  }

  static putDownloadDelay(value: number): void {
    Settings.putIntToStr(Settings.KEY_DOWNLOAD_DELAY, value);
  }

  static readonly KEY_DOWNLOAD_TIMEOUT: string = 'download_timeout';
  static readonly DEFAULT_DOWNLOAD_TIMEOUT: number = 0;

  static getDownloadTimeout(): number {
    const size: number = Settings.getIntFromStr(Settings.KEY_DOWNLOAD_TIMEOUT, Settings.DEFAULT_DOWNLOAD_TIMEOUT);
    return Math.max(size, Settings.DEFAULT_DOWNLOAD_TIMEOUT);
  }

  static putDownloadTimeout(value: number): void {
    Settings.putIntToStr(Settings.KEY_DOWNLOAD_TIMEOUT, value);
  }

  static setDownloadTimeout(value: number): void {
    Settings.putIntToStr(Settings.KEY_DOWNLOAD_TIMEOUT, value);
  }

  static readonly KEY_SYNC_DOWNLOAD_WHILE_READING: string = 'sync_download_while_reading';
  static readonly DEFAULT_SYNC_DOWNLOAD_WHILE_READING: boolean = false;

  static getSyncDownloadWhileReading(): boolean {
    return Settings.getBoolean(Settings.KEY_SYNC_DOWNLOAD_WHILE_READING,
      Settings.DEFAULT_SYNC_DOWNLOAD_WHILE_READING);
  }

  static putSyncDownloadWhileReading(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SYNC_DOWNLOAD_WHILE_READING, value);
  }

  // ── 历史 / 统计 / 用户 ID ─────────────────────────────────────────────────

  static readonly KEY_HISTORY_INFO_SIZE: string = 'history_info_size';
  static readonly DEFAULT_HISTORY_INFO_SIZE: number = 100;

  static getHistoryInfoSize(): number {
    const size: number = Settings.getIntFromStr(Settings.KEY_HISTORY_INFO_SIZE,
      Settings.DEFAULT_HISTORY_INFO_SIZE);
    if (size < Settings.DEFAULT_HISTORY_INFO_SIZE) {
      Settings.putIntToStr(Settings.KEY_HISTORY_INFO_SIZE, Settings.DEFAULT_HISTORY_INFO_SIZE);
      return Settings.DEFAULT_HISTORY_INFO_SIZE;
    }
    return size;
  }

  static setHistoryInfoSize(value: number): void {
    Settings.putIntToStr(Settings.KEY_HISTORY_INFO_SIZE, value);
  }

  static readonly KEY_ASK_ANALYTICS: string = 'ask_analytics';
  // D-006: 鸿蒙版已永久移除统计 SDK，默认不再询问收集数据
  static readonly DEFAULT_ASK_ANALYTICS: boolean = false;

  static getAskAnalytics(): boolean {
    return Settings.getBoolean(Settings.KEY_ASK_ANALYTICS, Settings.DEFAULT_ASK_ANALYTICS);
  }

  static putAskAnalytics(value: boolean): void {
    Settings.putBoolean(Settings.KEY_ASK_ANALYTICS, value);
  }

  static readonly KEY_ENABLE_ANALYTICS: string = 'enable_analytics';
  static readonly DEFAULT_ENABLE_ANALYTICS: boolean = false;

  static getEnableAnalytics(): boolean {
    return Settings.getBoolean(Settings.KEY_ENABLE_ANALYTICS, Settings.DEFAULT_ENABLE_ANALYTICS);
  }

  static putEnableAnalytics(value: boolean): void {
    Settings.putBoolean(Settings.KEY_ENABLE_ANALYTICS, value);
  }

  private static readonly KEY_USER_ID: string = 'user_id';
  private static readonly FILENAME_USER_ID: string = '.user_id';
  private static readonly LENGTH_USER_ID: number = 32;
  private static readonly USER_ID_ALPHABET: string = '0123456789abcdefghijklmnopqrstuvwxyz';

  static getUserID(): string {
    let writePref: boolean = false;
    let writeFile: boolean = false;
    let userID: string | null = Settings.getStringNullable(Settings.KEY_USER_ID, null);
    const filePath: string | null = AppConfig.getFileInExternalAppDir(Settings.FILENAME_USER_ID);
    if (userID === null || !Settings.isValidUserID(userID)) {
      writePref = true;
      userID = (filePath !== null) ? FileUtils.read(filePath) : null;
      if (userID === null || !Settings.isValidUserID(userID)) {
        writeFile = true;
        userID = Settings.generateUserID();
      }
    } else {
      writeFile = true;
    }

    if (writePref) {
      Settings.putString(Settings.KEY_USER_ID, userID);
    }
    if (writeFile && filePath !== null) {
      FileUtils.write(filePath, userID);
    }
    return userID;
  }

  private static generateUserID(): string {
    let result: string = '';
    const chars: string = Settings.USER_ID_ALPHABET;
    for (let i = 0; i < Settings.LENGTH_USER_ID; i++) {
      const idx: number = Math.floor(Math.random() * chars.length);
      result += chars.charAt(idx);
    }
    return result;
  }

  private static isValidUserID(userID: string | null): boolean {
    if (userID === null || userID.length !== Settings.LENGTH_USER_ID) {
      return false;
    }
    for (let i = 0; i < Settings.LENGTH_USER_ID; i++) {
      const ch: string = userID.charAt(i);
      const isDigit: boolean = ch >= '0' && ch <= '9';
      const isLower: boolean = ch >= 'a' && ch <= 'z';
      if (!isDigit && !isLower) {
        return false;
      }
    }
    return true;
  }

  // ── 崩溃 / 相册扫描 / 列表与详情显示 ─────────────────────────────────────

  static readonly KEY_SAVE_CRASH_LOG: string = 'save_crash_log';
  static readonly DEFAULT_SAVE_CRASH_LOG: boolean = false;

  static getSaveCrashLog(): boolean {
    return Settings.getBoolean(Settings.KEY_SAVE_CRASH_LOG, Settings.DEFAULT_SAVE_CRASH_LOG);
  }

  static putSaveCrashLog(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SAVE_CRASH_LOG, value);
  }

  static readonly KEY_MEDIA_SCAN: string = 'media_scan';
  static readonly DEFAULT_MEDIA_SCAN: boolean = false;

  static getMediaScan(): boolean {
    return Settings.getBoolean(Settings.KEY_MEDIA_SCAN, Settings.DEFAULT_MEDIA_SCAN);
  }

  static putMediaScan(value: boolean): void {
    Settings.putBoolean(Settings.KEY_MEDIA_SCAN, value);
  }

  static readonly KEY_SHOW_GALLERY_PAGES: string = 'show_gallery_pages';
  static readonly DEFAULT_SHOW_GALLERY_PAGES: boolean = false;

  static getShowGalleryPages(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_GALLERY_PAGES, Settings.DEFAULT_SHOW_GALLERY_PAGES);
  }

  static putShowGalleryPages(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_GALLERY_PAGES, value);
  }

  static readonly KEY_SHOW_JPN_TITLE: string = 'show_jpn_title';
  static readonly DEFAULT_SHOW_JPN_TITLE: boolean = false;

  static getShowJpnTitle(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_JPN_TITLE, Settings.DEFAULT_SHOW_JPN_TITLE);
  }

  static hasShowJpnTitle(): boolean {
    return Settings.sMem.has(Settings.KEY_SHOW_JPN_TITLE);
  }

  static putShowJpnTitle(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_JPN_TITLE, value);
  }

  static readonly KEY_SHOW_GALLERY_COMMENT: string = 'show_gallery_comment';
  static readonly IS_SHOW_GALLERY_COMMENT: boolean = true;

  static getShowGalleryComment(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_GALLERY_COMMENT, Settings.IS_SHOW_GALLERY_COMMENT);
  }

  static putShowGalleryComment(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_GALLERY_COMMENT, value);
  }

  static setShowGalleryComment(value: boolean): void {
    Settings.putShowGalleryComment(value);
  }

  static readonly KEY_SHOW_GALLERY_RATING: string = 'show_gallery_rating';
  static readonly IS_SHOW_GALLERY_RATING: boolean = true;

  static getShowGalleryRating(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_GALLERY_RATING, Settings.IS_SHOW_GALLERY_RATING);
  }

  static setShowGalleryRating(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_GALLERY_RATING, value);
  }

  static readonly KEY_SHOW_READ_PROGRESS: string = 'show_read_progress';
  static readonly IS_SHOW_READ_PROGRESS: boolean = true;

  static getShowReadProgress(): boolean {
    return Settings.getBoolean(Settings.KEY_SHOW_READ_PROGRESS, Settings.IS_SHOW_READ_PROGRESS);
  }

  static setShowReadProgress(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SHOW_READ_PROGRESS, value);
  }

  static readonly KEY_DRAG_DOWNLOAD_GALLERY: string = 'drag_download_gallery';
  static readonly DEFAULT_DRAG_DOWNLOAD_GALLERY: boolean = false;

  static getDragDownloadGallery(): boolean {
    return Settings.getBoolean(Settings.KEY_DRAG_DOWNLOAD_GALLERY, Settings.DEFAULT_DRAG_DOWNLOAD_GALLERY);
  }

  static setDragDownloadGallery(value: boolean): void {
    Settings.putBoolean(Settings.KEY_DRAG_DOWNLOAD_GALLERY, value);
  }

  static readonly KEY_SAVE_PARSE_ERROR_BODY: string = 'save_parse_error_body';
  static readonly DEFAULT_SAVE_PARSE_ERROR_BODY: boolean = false;

  static getSaveParseErrorBody(): boolean {
    return Settings.getBoolean(Settings.KEY_SAVE_PARSE_ERROR_BODY, Settings.DEFAULT_SAVE_PARSE_ERROR_BODY);
  }

  static putSaveParseErrorBody(value: boolean): void {
    Settings.putBoolean(Settings.KEY_SAVE_PARSE_ERROR_BODY, value);
  }

  // ── 画质 / 主题 / 语言（上游 L380–L505 / L890–L925 / L1245–L1255）────────

  static readonly KEY_THUMB_RESOLUTION: string = 'thumb_resolution';
  static readonly DEFAULT_THUMB_RESOLUTION: number = 0;

  static getThumbResolution(): number {
    return Settings.getIntFromStr(Settings.KEY_THUMB_RESOLUTION, Settings.DEFAULT_THUMB_RESOLUTION);
  }

  static putThumbResolution(value: number): void {
    Settings.putIntToStr(Settings.KEY_THUMB_RESOLUTION, value);
  }

  static readonly KEY_IMAGE_RESOLUTION: string = 'image_size';
  static readonly DEFAULT_IMAGE_RESOLUTION: string = 'a';
  static readonly IMAGE_SIZE_AUTO: string = 'a';
  static readonly IMAGE_SIZE_780X: string = '780';
  static readonly IMAGE_SIZE_980X: string = '980';
  static readonly IMAGE_SIZE_1280X: string = '1280';
  static readonly IMAGE_SIZE_1600X: string = '1600';
  static readonly IMAGE_SIZE_2400X: string = '2400';

  /**
   * 对应上游 L890：读到 980X 时自动迁移到 780X 并同步更新 sEhConfig。
   */
  static getImageResolution(): string {
    const result: string = Settings.getString(Settings.KEY_IMAGE_RESOLUTION,
      Settings.DEFAULT_IMAGE_RESOLUTION);
    if (result === Settings.IMAGE_SIZE_980X) {
      Settings.putImageResolution(Settings.IMAGE_SIZE_780X);
      return Settings.IMAGE_SIZE_780X;
    }
    return result;
  }

  static putImageResolution(value: string): void {
    if (value === null || value === undefined) {
      return;
    }
    const cfg: EhConfig | null = Settings.sEhConfig;
    if (cfg !== null) {
      cfg.imageSize = value;
      cfg.setDirty();
    }
    Settings.putString(Settings.KEY_IMAGE_RESOLUTION, value);
  }

  static readonly KEY_THEME: string = 'theme';
  static readonly KEY_THEME_DARK: string = 'theme';
  static readonly DEFAULT_THEME: number = 0;
  static readonly THEME_LIGHT: number = 0;
  static readonly THEME_DARK: number = 1;
  static readonly THEME_BLACK: number = 2;

  static getTheme(): number {
    return Settings.getIntFromStr(Settings.KEY_THEME, Settings.DEFAULT_THEME);
  }

  static putTheme(theme: number): void {
    Settings.putIntToStr(Settings.KEY_THEME, theme);
  }

  /** 注入系统深色模式状态提供者（对应上游 `Settings.getDarkModeStatus(Context)`） */
  static setDarkModeProvider(provider: (() => boolean) | null): void {
    Settings.sDarkModeProvider = provider;
  }

  /** 对齐上游 `getDarkModeStatus(Context)`（支持直接传入回调或使用已注入提供者） */
  static getDarkModeStatus(isDarkMode?: () => boolean): boolean {
    if (isDarkMode !== undefined) {
      return isDarkMode();
    }
    if (Settings.sDarkModeProvider !== null) {
      return Settings.sDarkModeProvider();
    }
    return false;
  }

  static readonly KEY_THEME_AUTO_SWITCH: string = 'theme_auto_switch';
  static readonly DEFAULT_THEME_AUTO_SWITCH: boolean = false;

  static isThemeAutoSwitchAvailable(): boolean {
    return Settings.getBoolean(Settings.KEY_THEME_AUTO_SWITCH, Settings.DEFAULT_THEME_AUTO_SWITCH);
  }

  static putThemeAutoSwitchAvailable(value: boolean): void {
    Settings.putBoolean(Settings.KEY_THEME_AUTO_SWITCH, value);
  }

  static readonly KEY_THEME_DARK_VARIANT: string = 'theme_dark_variant';
  static readonly DEFAULT_THEME_DARK_VARIANT: number = Settings.THEME_DARK;

  static getThemeDarkVariant(): number {
    const raw: number = Settings.getIntFromStr(
      Settings.KEY_THEME_DARK_VARIANT,
      Settings.DEFAULT_THEME_DARK_VARIANT
    );
    return raw === Settings.THEME_BLACK ? Settings.THEME_BLACK : Settings.THEME_DARK;
  }

  static putThemeDarkVariant(theme: number): void {
    const normalized: number = theme === Settings.THEME_BLACK ? Settings.THEME_BLACK : Settings.THEME_DARK;
    Settings.putIntToStr(Settings.KEY_THEME_DARK_VARIANT, normalized);
  }

  static readonly KEY_APPLY_NAV_BAR_THEME_COLOR: string = 'apply_nav_bar_theme_color';
  static readonly DEFAULT_APPLY_NAV_BAR_THEME_COLOR: boolean = false;

  static getApplyNavBarThemeColor(): boolean {
    return Settings.getBoolean(Settings.KEY_APPLY_NAV_BAR_THEME_COLOR, Settings.DEFAULT_APPLY_NAV_BAR_THEME_COLOR);
  }

  static putApplyNavBarThemeColor(value: boolean): void {
    Settings.putBoolean(Settings.KEY_APPLY_NAV_BAR_THEME_COLOR, value);
  }

  static readonly KEY_APP_LANGUAGE: string = 'app_language';
  static readonly DEFAULT_APP_LANGUAGE: string = 'system';

  static getAppLanguage(): string {
    return Settings.getString(Settings.KEY_APP_LANGUAGE, Settings.DEFAULT_APP_LANGUAGE);
  }

  static putAppLanguage(value: string): void {
    Settings.putString(Settings.KEY_APP_LANGUAGE, value);
  }

  // ── 下载页引导（上游 L1317–L1334，`DownloadGuideHelper` 用）────────────────

  static readonly KEY_GUIDE_DOWNLOAD_THUMB: string = 'guide_download_thumb';
  static readonly DEFAULT_GUIDE_DOWNLOAD_THUMB: boolean = true;

  static getGuideDownloadThumb(): boolean {
    return Settings.getBoolean(Settings.KEY_GUIDE_DOWNLOAD_THUMB,
      Settings.DEFAULT_GUIDE_DOWNLOAD_THUMB);
  }

  static putGuideDownloadThumb(value: boolean): void {
    Settings.putBoolean(Settings.KEY_GUIDE_DOWNLOAD_THUMB, value);
  }

  static readonly KEY_GUIDE_DOWNLOAD_LABELS: string = 'guide_download_labels';
  static readonly DEFAULT_GUIDE_DOWNLOAD_LABELS: boolean = true;

  static getGuideDownloadLabels(): boolean {
    return Settings.getBoolean(Settings.KEY_GUIDE_DOWNLOAD_LABELS,
      Settings.DEFAULT_GUIDE_DOWNLOAD_LABELS);
  }

  /**
   * 对应上游 L1332 `puttGuideDownloadLabels` —— 上游方法名就是三个 t，不能替换。
   */
  static puttGuideDownloadLabels(value: boolean): void {
    Settings.putBoolean(Settings.KEY_GUIDE_DOWNLOAD_LABELS, value);
  }

  // ── 代理（上游 KEY_PROXY_TYPE / KEY_PROXY_IP / KEY_PROXY_PORT）──────────────

  static readonly KEY_PROXY_TYPE: string = 'proxy_type';
  static readonly DEFAULT_PROXY_TYPE: number = 1;
  static readonly KEY_PROXY_IP: string = 'proxy_ip';
  static readonly DEFAULT_PROXY_IP: string | null = null;
  static readonly KEY_PROXY_PORT: string = 'proxy_port';
  static readonly DEFAULT_PROXY_PORT: number = -1;

  static getProxyType(): number {
    return Settings.getInt(Settings.KEY_PROXY_TYPE, Settings.DEFAULT_PROXY_TYPE);
  }

  static putProxyType(value: number): void {
    Settings.putInt(Settings.KEY_PROXY_TYPE, value);
  }

  static getProxyIp(): string | null {
    const v: string | undefined = Settings.getStringOrNone(Settings.KEY_PROXY_IP);
    return (v === undefined) ? Settings.DEFAULT_PROXY_IP : v;
  }

  static putProxyIp(value: string | null): void {
    if (value === null) {
      Settings.removeKey(Settings.KEY_PROXY_IP);
      return;
    }
    Settings.putString(Settings.KEY_PROXY_IP, value);
  }

  static getProxyPort(): number {
    return Settings.getInt(Settings.KEY_PROXY_PORT, Settings.DEFAULT_PROXY_PORT);
  }

  static putProxyPort(value: number): void {
    Settings.putInt(Settings.KEY_PROXY_PORT, value);
  }

  // ── 侧栏用户背景 / 头像路径（上游 L1472–L1490）───────────────────────────

  static readonly USER_BACKGROUND_IMAGE: string = 'background_image_path';
  static readonly USER_AVATAR_IMAGE: string = 'avatar_image_path';

  /** 对齐上游 `getUserImageFile(String)`：路径为空或不存在返回 null，存在则原样返回路径 */
  static getUserImageFile(key: string): string | null {
    const path: string = Settings.getString(key, '');
    if (path.length === 0) {
      return null;
    }
    try {
      return fs.accessSync(path) ? path : null;
    } catch (e) {
      Settings.logReadError(key, e as Object);
      return null;
    }
  }

  /** 对齐上游 `saveFilePath(String, String)` */
  static saveFilePath(key: string, path: string): void {
    Settings.putString(key, path);
  }

  // ── 更新检查历史键兼容（见 DEVIATIONS D-003：AppUpdater 已删，保留设置键读写）──

  static readonly KEY_BETA_UPDATE_CHANNEL: string = 'beta_update_channel';
  static readonly DEFAULT_BETA_UPDATE_CHANNEL: boolean = false;
  static readonly KEY_SKIP_UPDATE_VERSION: string = 'skip_update_version';
  static readonly DEFAULT_SKIP_UPDATE_VERSION: number = 0;
  static readonly KEY_CLOSE_AUTO_UPDATES: string = 'close_auto_updates';
  static readonly IS_CLOSE_AUTO_UPDATES: boolean = false;
  static readonly KEY_LAST_UPDATE_TIME: string = 'last_update_time';
  static readonly DEFAULT_LAST_UPDATE_TIME: number = 0;
  private static readonly UPDATE_CHECK_INTERVAL_MS: number = 1000 * 60 * 60 * 24;

  static getBetaUpdateChannel(): boolean {
    return Settings.getBoolean(Settings.KEY_BETA_UPDATE_CHANNEL, Settings.DEFAULT_BETA_UPDATE_CHANNEL);
  }

  static putBetaUpdateChannel(value: boolean): void {
    Settings.putBoolean(Settings.KEY_BETA_UPDATE_CHANNEL, value);
  }

  static getSkipUpdateVersion(): number {
    return Settings.getInt(Settings.KEY_SKIP_UPDATE_VERSION, Settings.DEFAULT_SKIP_UPDATE_VERSION);
  }

  static putSkipUpdateVersion(value: number): void {
    Settings.putInt(Settings.KEY_SKIP_UPDATE_VERSION, value);
  }

  static getCloseAutoUpdate(): boolean {
    return Settings.getBoolean(Settings.KEY_CLOSE_AUTO_UPDATES, Settings.IS_CLOSE_AUTO_UPDATES);
  }

  static setKeyCloseAutoUpdates(value: boolean): void {
    Settings.putBoolean(Settings.KEY_CLOSE_AUTO_UPDATES, value);
  }

  /** 对齐上游 `getIsUpdateTime()`：距上次检查满 24 小时返回 true；支持注入 nowMs 便于单测 */
  static getIsUpdateTime(nowMs?: number): boolean {
    const lastUpdateTime: number = Settings.getLong(Settings.KEY_LAST_UPDATE_TIME, Settings.DEFAULT_LAST_UPDATE_TIME);
    const nowTime: number = nowMs !== undefined ? nowMs : Date.now();
    const msNum: number = nowTime - lastUpdateTime;
    return msNum >= Settings.UPDATE_CHECK_INTERVAL_MS;
  }

  static putUpdateTime(updateTime: number): void {
    Settings.putLong(Settings.KEY_LAST_UPDATE_TIME, updateTime);
  }

  // ── 隐藏实验项：旧版 OpenGL 阅读器（默认关闭，主阅读器为原生 ArkUI 阅读器）──

  static readonly KEY_EXPERIMENTAL_GL_READER: string = 'experimental_gl_reader';
  static readonly DEFAULT_EXPERIMENTAL_GL_READER: boolean = false;

  static getExperimentalGlReader(): boolean {
    return Settings.getBoolean(Settings.KEY_EXPERIMENTAL_GL_READER, Settings.DEFAULT_EXPERIMENTAL_GL_READER);
  }

  static putExperimentalGlReader(value: boolean): void {
    Settings.putBoolean(Settings.KEY_EXPERIMENTAL_GL_READER, value);
  }
}
