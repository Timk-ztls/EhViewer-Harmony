/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : 聚合文件（D-033 拆分后的接口面）
 * 上游   : app/src/main/java/com/hippo/ehviewer/preference/ 下 14 个 Preference 类
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/preference/PreferenceActions.ets
 *
 * 【D-033】上游 14 个 `*Preference extends Preference` 是「带 UI 的设置项」。
 * ArkTS 无 Preference 体系，故拆两层：
 *   · 本文件 = **纯逻辑 + key 常量**（core-runtime，可直接单元测试）
 *   · UI = ui-widget 的 `SettingsItem<Xxx>` ArkUI 组件（标题/摘要/对话框/进度条）
 * 对接口径：**UI 层只认本文件的 key 常量与静态方法**，不自己拼 key、不自己算逻辑。
 *
 * key 常量**全部来自上游 `Settings.java`**（逐个 `git show` 核对过行号，见每个常量注释）。
 * 这些字符串是「老用户数据能否读出」的唯一依据，**改一个字符就是数据丢失**。
 */

import common from '@ohos.app.ability.common';
import { Settings } from '../Settings';
import { UniFile } from '../../unifile/UniFile';
import { CleanRedundancyPreference, CleanResult } from './CleanRedundancyPreference';
import { VersionPreference } from './VersionPreference';
import { AppConfig } from '../AppConfig';
import { ReadableTime } from '../../util/ReadableTime';

export class PreferenceActions {

  // ── key 常量（逐条对上游 Settings.java）───────────────────────────────
  /** 上游 L529 `KEY_DEFAULT_CATEGORIES = "default_categories"`，默认 `EhUtils.ALL_CATEGORY` */
  static readonly KEY_DEFAULT_CATEGORIES: string = Settings.KEY_DEFAULT_CATEGORIES;
  /** 上游 L542 `KEY_EXCLUDED_TAG_NAMESPACES = "excluded_tag_namespaces"`，默认 0 */
  static readonly KEY_EXCLUDED_TAG_NAMESPACES: string = Settings.KEY_EXCLUDED_TAG_NAMESPACES;
  /** 上游 L1256 `KEY_PROXY_TYPE = "proxy_type"`，默认 `EhProxySelector.TYPE_SYSTEM` */
  static readonly KEY_PROXY_TYPE: string = Settings.KEY_PROXY_TYPE;

  // ── 无 key 的动作项（点一下就执行）─────────────────────────────────────

  /** 对应 `VersionPreference`（S0175）：只读版本号，无 key */
  static getVersionName(): string {
    return VersionPreference.getVersionName();
  }

  /**
   * 对应 `CleanRedundancyPreference`（S0164）：清理下载目录里已无对应下载记录的文件。
   * @param contains 该 gid 是否仍在下载列表中（download-sync 的 DownloadManager.containDownloadInfo）
   * @param dirOverride 仅测试注入；生产传 undefined 走 Settings.getDownloadLocation()
   */
  static async cleanRedundancy(contains: (gid: number) => boolean,
    onProgress?: (done: number, total: number) => void,
    dirOverride?: UniFile | null): Promise<CleanResult> {
    return CleanRedundancyPreference.cleanRedundancy(contains, onProgress, dirOverride);
  }

  /**
   * 对应 `ClearDownloadPathCachePreference`（S0165）：清空 DOWNLOAD_DIRNAME 表。
   * 上游在 `onDialogClosed(positive)` 里调 `EhDB.clearDownloadDirname()`。
   * 由调用方传入 EhDB 的实现（避免 core-runtime 内部对 EhDB 的硬依赖）。
   */
  static async clearDownloadPathCache(clear: () => Promise<void>): Promise<void> {
    await clear();
  }

  // ── 有 key 的设置项（读/写都经过已落地的 Settings 基础设施）─────────────

  /** 对应 `DefaultCategoryPreference`（S0166）：默认分类位掩码 */
  static getDefaultCategories(): number {
    // 上游用 getInt/putInt（**原生 int 型 preference**，不是字符串存），由 Settings 统一管理并同步 EhConfig
    return Settings.getDefaultCategories();
  }

  static putDefaultCategories(value: number): void {
    Settings.putDefaultCategories(value);
  }

  /** `EhUtils.ALL_CATEGORY`（net-parse S0081 的常量；与 Settings.DEFAULT_DEFAULT_CATEGORIES 一致） */
  static readonly DEFAULT_DEFAULT_CATEGORIES: number = Settings.DEFAULT_DEFAULT_CATEGORIES;

  /** 对应 `ExcludedTagNamespacesPreference`（S0167）：被排除的标签命名空间位掩码 */
  static getExcludedTagNamespaces(): number {
    return Settings.getExcludedTagNamespaces();
  }

  static putExcludedTagNamespaces(value: number): void {
    Settings.putExcludedTagNamespaces(value);
  }

  static readonly DEFAULT_EXCLUDED_TAG_NAMESPACES: number = Settings.DEFAULT_EXCLUDED_TAG_NAMESPACES;

  /** 对应 `ProxyPreference`（S0170）：代理类型（值域见 EhProxySelector.TYPE_*） */
  static getProxyType(): number {
    return Settings.getProxyType();
  }

  static putProxyType(value: number): void {
    Settings.putProxyType(value);
  }

  /** `EhProxySelector.TYPE_SYSTEM`（= 1，与 Settings.DEFAULT_PROXY_TYPE 一致） */
  static readonly DEFAULT_PROXY_TYPE: number = Settings.DEFAULT_PROXY_TYPE;

  // ── 仍待实现（D-033 队列第 2 步）───────────────────────────────────────
  //  ExportDataPreference(67)          → buildExportData(): Promise<string>
  //  RestoreDownloadPreference(267)    → 导入 .db + 迁移（依赖 EhDB.migrate，已落地）
  //  IdentityCookiePreference(92)      → 依赖 net-parse 的 EhCookieStore
  //  SignInRequiredActivityPreference(69) / SignOutPreference(66) → 依赖 EhUtils.signOut（net-parse）
  //  TaskPreference(193)               → 是上述几项的 AsyncTask 基类，属 ui-widget
  // ── ExportDataPreference(S0168) 的纯逻辑 ────────────────────────────────
  /**
   * 对应上游 `ExportDataTask.doInBackground`：
   *   dir = AppConfig.getExternalDataDir()；file = dir + "/" + getFilenamableTime(now) + ".db"
   *   export 成功 → 返回该文件路径；任何一步失败 → null
   *
   * `exportFn` 是注入的导出动作（上游 `EhDB.exportDB(Context, File)`）；
   * core-runtime 不宜反向依赖 EhDB 的具体实现，故用回调注入，语义与上游一致。
   */
  static async exportData(exportFn: (path: string) => Promise<boolean>): Promise<string | null> {
    const dir: string | null = AppConfig.getExternalDataDir();
    if (dir === null) {
      return null;
    }
    // 文件名用 ReadableTime.getFilenamableTime —— 格式必须与上游逐字一致
    const path: string = dir + '/' + ReadableTime.getFilenamableTime(Date.now()) + '.db';
    const ok: boolean = await exportFn(path);
    return ok ? path : null;
  }

  // ── SignInRequiredActivityPreference(S0172) 的纯逻辑 ────────────────────
  /**
   * 对应上游 `onClick()` 的登录态判定：任一主机上存在 `ipb_member_id` 或 `ipb_pass_hash`
   * 即视为已登录。上游查 4 次（E 站/ex 站 × 两个 key）。
   *
   * `contains(host, key)` 注入（上游是 `EhCookieStore.contains(HttpUrl, String)`），参数顺序与上游一致。
   */
  static isSignedIn(contains: (host: string, key: string) => boolean,
    hostE: string, hostEx: string): boolean {
    if (contains(hostE, PreferenceActions.COOKIE_KEY_IPD_MEMBER_ID)
      || contains(hostE, PreferenceActions.COOKIE_KEY_IPD_PASS_HASH)) {
      return true;
    }
    return contains(hostEx, PreferenceActions.COOKIE_KEY_IPD_MEMBER_ID)
      || contains(hostEx, PreferenceActions.COOKIE_KEY_IPD_PASS_HASH);
  }

  /** 上游 EhCookieStore.KEY_IPD_MEMBER_ID（net-parse；此处镜像用于判定逻辑） */
  static readonly COOKIE_KEY_IPD_MEMBER_ID: string = 'ipb_member_id';
  /** 上游 EhCookieStore.KEY_IPD_PASS_HASH */
  static readonly COOKIE_KEY_IPD_PASS_HASH: string = 'ipb_pass_hash';
  // ── SignOutPreference(S0173) ───────────────────────────────────────────
  /**
   * 对应上游 `onDialogClosed(positiveResult)`：
   *   1. `EhUtils.signOut(context)` —— 清登录 cookie（net-parse 作用域）
   *   2. Toast「已登出，请重启」
   *   3. **等 1500ms** 后带 `KEY_RESTART=true` 重启到 Splash
   *
   * 拆解：`signOutFn` 注入第 1 步；`RESTART_DELAY_MILLIS = 1500` 与上游 `Thread.sleep(1500)` 一致；
   * 「重启到 Splash」是 UI 动作（`restartFn` 注入），core-runtime 不直接碰 UIAbility。
   */
  static readonly RESTART_DELAY_MILLIS: number = 1500;

  static async signOut(signOutFn: () => Promise<void> | void, restartFn: () => void): Promise<void> {
    await signOutFn();
    // 上游用 Thread.sleep(1500) 阻塞后台线程；ArkTS 用定时器（不阻塞事件循环），delay 值一致
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, PreferenceActions.RESTART_DELAY_MILLIS);
    });
    restartFn();
  }

  // ── ClearDownloadPathCachePreference(S0165) ────────────────────────────
  // 上游 `onDialogClosed(positive)` 只有一句 `EhDB.clearDownloadDirname()`；
  // 纯逻辑即上面的 `clearDownloadPathCache(clear)`（注入 clear = EhDB.clearDownloadDirname）。
}