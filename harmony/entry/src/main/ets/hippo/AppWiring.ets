/**
 * AppWiring —— 启动接线（**非上游文件**，纯集成层）
 *
 * ## 为什么需要这个文件
 *
 * 本项目大量采用「**注入式架构**」：消费者（SpiderQueen / EhDB / Settings / EhEngine 的调用方）
 * 先写好，真正的实现由启动时注入。好处是模块可并行开发、可单测；**坏处是没人写注入者**。
 *
 * 审计员实测（2026-10-25）：
 * ```
 * EhDB.attach()          全仓 0 个真实调用 → 34 个 DB 方法在真机上全部抛 'EhDB is not attached'
 * Settings.attach()      只有 DownloadService.onCreate 一处
 *                        → 冷启动到"进下载页"之间所有设置读到的都是默认值
 *                        → getGallerySite() 返回 SITE_E（用户选了 EX 站也会静默回到 E 站）
 * SpiderQueen.setEhEngine / setPageImageDownloader   0 个注入者
 *                        → 阅读页第一张图就抛 'PageImageDownloader not injected'
 * Settings.setLoginProvider                          0 个注入者
 *                        → isLogin() 恒 false，收藏/评分/评论/EX 站全走未登录分支
 * ```
 * 逐文件 `status=ported` 全绿、`build_hap` 全绿，**但真机上一个功能都跑不起来**。
 *
 * 本文件把「谁注入什么」集中到一处，让"接线率"变成可审计的一行清单。
 *
 * ## 契约
 *
 * - **只做接线，不含业务逻辑**（不解析、不计算、不碰 UI）
 * - 幂等：`EntryAbility.onCreate` 与 `DownloadService.onCreate` 都会调，重复调用只生效一次
 * - **失败不吞**：任一必需接线失败就抛出 —— 宁可启动失败，也不要静默降级
 *   （静默降级的后果是"设置全是默认值"这种查一天都查不出来的问题）
 * - 每接一条打一行 hilog，便于真机确认接线率
 */

import { common, Want } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from './ehviewer/Settings';
import { EhDB } from './ehviewer/EhDB';
import { EhApplication } from './ehviewer/EhApplication';
import { bundleManager } from '@kit.AbilityKit';
import { SceneFragment } from './scene/SceneFragment';
import { FavoritesScene, LocalFavoritesRepoAdapter } from './ehviewer/ui/scene/gallery/list/FavoritesScene';
import { GalleryInfo } from './ehviewer/client/data/GalleryInfo';
import { FavoritesSceneConcrete } from './ehviewer/ui/scene/gallery/list/FavoritesSceneConcrete';
import {
  DownloadEnqueueLike,
  FavoritesRepositoryLike
} from './ehviewer/ui/scene/gallery/list/GalleryListScene';
import { GalleryListSceneConcrete } from './ehviewer/ui/scene/gallery/list/GalleryListSceneConcrete';
import { PreviewSet } from './ehviewer/client/data/PreviewSet';
import { DownloadsSceneShell } from './ehviewer/ui/scene/download/DownloadsSceneShell';
import { QuickSearchSceneShell } from './ehviewer/ui/scene/gallery/list/QuickSearchSceneShell';
import { HistorySceneShell } from './ehviewer/ui/scene/history/HistorySceneShell';
import { DownloadLabelsSceneShell } from './ehviewer/ui/scene/download/DownloadLabelsSceneShell';
import { EhTopListSceneShell } from './ehviewer/ui/scene/topList/EhTopListSceneShell';
import { SubscriptionsSceneShell } from './ehviewer/ui/scene/gallery/list/SubscriptionsSceneShell';
import { GalleryInfoSceneShell } from './ehviewer/ui/scene/GalleryInfoSceneShell';
import { GalleryPreviewsSceneShell } from './ehviewer/ui/scene/GalleryPreviewsSceneShell';
import { QuickSearchScene } from './ehviewer/ui/scene/gallery/list/QuickSearchScene';
import { HistoryScene } from './ehviewer/ui/scene/history/HistoryScene';
import { DownloadLabelsScene } from './ehviewer/ui/scene/download/DownloadLabelsScene';
import { EhTopListScene } from './ehviewer/ui/scene/topList/EhTopListScene';
import { SubscriptionsScene } from './ehviewer/ui/scene/gallery/list/SubscriptionsScene';
import { GalleryInfoScene } from './ehviewer/ui/scene/GalleryInfoScene';
import { GalleryPreviewsScene } from './ehviewer/ui/scene/GalleryPreviewsScene';
import { DownloadInfo } from './ehviewer/dao/DownloadInfo';
import { UConfigPageCoordinator } from './ui/p3/P3PageAdapters';
import { DownloadManager } from './ehviewer/download/DownloadManager';
import { DownloadService } from './ehviewer/download/DownloadService';
import { ArchiverDownloader } from './ehviewer/download/ArchiverDownloader';
import { ArchiverDownloadService } from './ehviewer/download/ArchiverDownloadService';
import { A7ZipArchive } from './ehviewer/gallery/A7ZipArchive';
import { createNativeA7ZipBridge } from '../native/NativeImage';
import { GetText } from './ehviewer/GetText';
import { DownloadManagerLike } from './ehviewer/ui/scene/download/DownloadsScene';
import { NullPreviewHelperPort, NullPreviewsSceneHost } from './ehviewer/ui/scene/NullSceneHosts';
import { EhClientFavoritesAdapter } from './ehviewer/ui/scene/gallery/list/FavoritesScene';
import { DaoMaster } from './ehviewer/dao/DaoMaster';
import { SpiderQueen, EhEngineLike, SpiderInfoCacheProvider, GalleryDetailFetcher, PreviewSetFetcher } from './ehviewer/spider/SpiderQueen';
import { PageImageDownloaderImpl } from './okhttp/PageImageDownloaderImpl';
import { EhEngine, EngineTask, HttpCaller, EhEngineConfig } from './ehviewer/client/EhEngine';
import { GalleryPageParserResult } from './ehviewer/client/parser/GalleryPageParser';
import { GalleryPageApiParserResult } from './ehviewer/client/parser/GalleryPageApiParser';
import { Crash } from './ehviewer/Crash';
import { CrashError } from './ehviewer/CrashObserver';
import { PacketInfo, CrashDeviceInfo, CrashMemoryInfo, CrashRuntimeInfo } from './ehviewer/CrashTypes';
import { AppConfig } from './ehviewer/AppConfig';
import { OkHttpClient } from './okhttp/OkHttpClient';
import { Cache } from './okhttp/Cache';
import { SceneApplication } from './scene/SceneApplication';
import { registerAllScenes, getDrawerRoutingReport, SceneRegResult } from './scene/SceneRegistry';
import { SceneArgs } from './scene/SceneTypes';
import { Call as OkCall } from './okhttp/Call';
import { Response as OkResponse } from './okhttp/Response';
import { ResponseBody } from './okhttp/ResponseBody';
import { Request } from './okhttp/Request';
import { EngineCall } from './ehviewer/client/EhEngine';
import { EngineResponse } from './ehviewer/client/EhEngine';
import { EngineHeaders } from './ehviewer/client/EhEngine';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import errorManager from '@ohos.app.ability.errorManager';
import { fileIo as fs } from '@kit.CoreFileKit';
import { EhCookieStore } from './ehviewer/client/EhCookieStore';
import { CookieTable } from './network/CookieDatabase';
import { RdbCookieStore, CookieDbLike } from './network/RdbCookieStore';
import { EhDbFilterStore } from './ehviewer/db/EhDbFilterStore';
import { Hosts, HostsDbLike, HostsResultSetLike, RdbHostsStore } from './ehviewer/Hosts';
import { AsyncHostsProvider, EhHostsConfig, OkHttpEhHosts } from './ehviewer/client/EhHosts';
import { EhProxySelector, OkHttpEhProxySelector } from './ehviewer/EhProxySelector';
import { EhConfig } from './ehviewer/client/EhConfig';
import { EhUrl, EhUrlSiteConfig } from './ehviewer/client/EhUrl';
import { EhRequest, EhRequestConfig } from './ehviewer/client/EhRequest';
import { EhUtils, EhUtilsConfig } from './ehviewer/client/EhUtils';
import { FavoritesParser, FavoritesParserConfig } from './ehviewer/client/parser/FavoritesParser';
import { GalleryDetailParser, GalleryDetailParserConfig, BlackListHook } from './ehviewer/client/parser/GalleryDetailParser';
import { GalleryDetail } from './ehviewer/client/data/GalleryDetail';
import { FileUtils } from './lib/yorozuya/FileUtils';
import { Image } from './lib/image/Image';
import { DecodedImage } from './ehviewer/image/ImageBitmapHelper';
import { UniFile } from './unifile/UniFile';
import { SimpleDiskCache } from './beerbelly/SimpleDiskCache';
import { PageDownloadProgressCallback, PageImageDownloader, DownloadResult } from './streampipe/PageImageDownloader';
import { ByteSink } from './streampipe/OutputStreamPipe';
import {
  SpiderDen, SyncDownloadSettingProvider, DirnameStore, GalleryTitleProvider, StartWithFilenameFilter
} from './ehviewer/spider/SpiderDen';
import { SpiderInfo, DownloadDirProvider } from './ehviewer/spider/SpiderInfo';
import { EhGalleryProvider, SpiderQueenLike } from './ehviewer/gallery/EhGalleryProvider';
import { BlackList } from './ehviewer/dao/BlackList';
import { SolidSceneHooks } from './ehviewer/ui/scene/SolidScene';
import { SolidSceneSettings, SolidSceneSettingsHolder } from './ehviewer/ui/scene/SolidSceneSettings';
import { SecuritySettings } from './ehviewer/ui/scene/SecurityScene';
import { SecuritySceneShell } from './ehviewer/ui/scene/SecuritySceneShell';
import { EhActivitySettings, EhActivitySettingsHolder } from './ehviewer/ui/EhActivity';
import { LoadImageController } from './widget/LoadImageView';
import { DefaultImageRequestHost } from './ehviewer/image/DefaultImageRequestHost';
import { HttpUrl } from './okhttp/HttpUrl';
import { CookieWriterLike, LegacyCookieStoreLike, ClipboardLike } from './ehviewer/ui/scene/sign/CookieSignInScene';
import { Cookie, CookieBuilder } from './okhttp/Cookie';
import { CookieSignInSceneConcrete } from './ehviewer/ui/scene/sign/CookieSignInSceneConcrete';
import { WebViewSignInSceneConcrete } from './ehviewer/ui/scene/sign/WebViewSignInSceneConcrete';
import { GetProfileSceneShell } from './ehviewer/ui/scene/sign/GetProfileSceneShell';
import { ProfileResult } from './ehviewer/ui/scene/sign/GetProfileScene';
import { ProgressSceneShell } from './ehviewer/ui/scene/ProgressSceneShell';
import { EhCookieStoreProfileJar, AsyncGalleryTokenRequester } from './ui/scene/AuthSecurityAdapters';
import { SignInSceneConcrete } from './ehviewer/ui/scene/sign/SignInSceneConcrete';
import { SignInClientLike } from './ehviewer/ui/scene/sign/SignInScene';
import { SignInResult } from './ehviewer/ui/scene/sign/SignInScene';
import { Announcer } from './scene/Announcer';
import { BaseScene } from './ehviewer/ui/scene/BaseScene';
import { EhCacheKeyFactory } from './ehviewer/client/EhCacheKeyFactory';
import { EhUrlOpener, OpenTarget } from './ehviewer/client/EhUrlOpener';
import { ListUrlBuilder } from './ehviewer/client/data/ListUrlBuilder';
import { EhTopListDetail } from './ehviewer/client/data/TopList';
import { GalleryCommentList } from './ehviewer/client/data/GalleryCommentList';
import { RateGalleryResult } from './ehviewer/client/parser/RateGalleryParser';
import { VoteCommentResult } from './ehviewer/client/parser/VoteCommentParser';
import { HistoryInfo } from './ehviewer/dao/HistoryInfo';
import { HistorySceneHost } from './ehviewer/ui/scene/history/HistoryScene';
import {
  TopListSceneHost,
  TopListApi,
  ListUrlBuilderSpec,
  TOP_LIST_URL,
  MODE_UPLOADER
} from './ehviewer/ui/scene/topList/EhTopListScene';
import { GalleryInfoSceneHost, KEY_GALLERY_DETAIL } from './ehviewer/ui/scene/GalleryInfoScene';
import { CommentClientLike } from './ehviewer/ui/scene/GalleryCommentsScene';
import { GalleryCommentsSceneConcrete } from './ehviewer/ui/scene/GalleryCommentsSceneConcrete';
import { GalleryListAction } from './ehviewer/ui/scene/gallery/list/GalleryListScene';
import { GalleryDetailSceneConcrete } from './ehviewer/ui/scene/gallery/detail/GalleryDetailSceneConcrete';
import {
  DetailClientLike,
  DetailActionClientLike,
  GalleryRateOutcome
} from './ehviewer/ui/scene/gallery/detail/GalleryDetailScene';
import { EhException } from './ehviewer/client/exception/EhException';
import { ParseException } from './ehviewer/client/exception/ParseException';
import { StatusCodeException } from './network/StatusCodeException';
import { DownloadLabel } from './ehviewer/dao/DownloadLabel';
import { LabelsSceneHost } from './ehviewer/ui/scene/download/DownloadLabelsScene';
import {
  SubscriptionsSceneHost,
  SubscriptionsApi,
  MY_TAG_URL
} from './ehviewer/ui/scene/gallery/list/SubscriptionsScene';
import { UserTag, UserTagList } from './ehviewer/client/data/UserTag';
import { Image1 } from './lib/image/Image1';
import { createNativeLibImageBridge } from '../native/NativeImage';
import { GalleryLayoutFactory } from './lib/glgallery/GalleryLayoutFactory';
import { GalleryView } from './lib/glgallery/GalleryView';
import { PagerLayoutManager } from './lib/glgallery/PagerLayoutManager';
import { DrawingOffscreenCanvas, DrawingTextPaintFactory } from './lib/glview/glrenderer/DrawingText';
import { RequestBuilder } from './okhttp/Request';
import { SearchHistoryKvStore, SearchHistoryPrefsStore } from './ehviewer/widget/SearchDatabase';
import { EhTagDatabaseUpdater, EhTagUpdaterConfig } from './ehviewer/client/EhTagDatabaseUpdater';
import { AppTagDatabaseIo } from './ui/p3/P3PageAdapters';

const DOMAIN = 0x0000;
const TAG = 'AppWiring';

class SettingsSearchHistoryKvStore implements SearchHistoryKvStore {
  getString(key: string, defValue: string): string {
    return Settings.getString(key, defValue);
  }

  putString(key: string, value: string): void {
    Settings.putString(key, value);
  }
}

/**
 * `EhEngineLike` 的适配器。
 *
 * `EhEngine` 是**静态类**（`static async getGalleryPage(...)`），而 `EhEngineLike` 是实例接口 ——
 * ArkTS 没有 TS 那样宽松的结构类型互转（`arkts-no-structural-typing`），所以必须有这层薄包装。
 *
 * 为什么 `EhEngineLike` 的参数声明成 `Object | null` 而不是 `EngineTask`/`HttpCaller`：
 * 那是**故意的**，为了让 `SpiderQueen`（storage-db 的模块）不依赖 `EhEngine`（net-parse 的模块）的具体类型，
 * 避免 ui/net 两侧反向依赖。所以这层 adapter 负责把 `Object` 显式 cast 回真实类型 ——
 * 调用方传的就是这两种类型的实例，cast 是安全的。
 */
class EhEngineLikeAdapter implements EhEngineLike {
  /**
   * **必须吃掉 client、忽略传进来的 `caller`**。
   *
   * 为什么：`EhEngineLike` 的签名是 `caller: Object | null`（故意不依赖 net-parse 的具体类型），
   * 而 `SpiderQueen` 的两个调用点**永远传 null**（`SpiderQueen.ets:750` / `:766`）——
   * 它没有 client 可传。第一版把 `null as HttpCaller` 直接透传，导致 `caller.newCall()` TypeError。
   *
   * 上游 `EhEngine.getGalleryPage(Task, OkHttpClient, url, gid, token)` 的第 2 参本来就是
   * **OkHttpClient**，不是 caller —— 所以这里注入 client 才是对位，`caller` 参数应当是历史包袱。
   */
  private readonly _caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this._caller = caller;
  }

  getGalleryPage(task: Object | null, caller: Object | null, url: string, gid: number,
                 token: string): Promise<GalleryPageParserResult> {
    // 忽略入参 caller，用自己的 _caller
    return EhEngine.getGalleryPage(task as EngineTask | null, this._caller, url, gid, token);
  }

  getGalleryPageApi(task: Object | null, caller: Object | null, gid: number, index: number,
                    pToken: string, showKey: string,
                    previousPToken: string | null): Promise<GalleryPageApiParserResult> {
    return EhEngine.getGalleryPageApi(task as EngineTask | null, this._caller,
      gid, index, pToken, showKey, previousPToken);
  }
}

export class AppWiring {
  /** 上游 `DBOpenHelper` 的库名。 */
  static readonly DB_NAME: string = 'eh.db';

  private static sWired: boolean = false;

  /**
   * Cookie 存储单例（`W-019`）。
   *
   * 对位上游 `EhApplication.getEhCookieStore(Context)`。
   *
   * **为什么必须有这个访问器**：上游门 4 的判定是
   * `Settings.getNeedSignIn() && !EhApplication.getEhCookieStore(ctx).hasSignedIn()` ——
   * 没有访问器就求不出 `hasSignedIn()`，`SignInScene` 那道门永远不会触发。
   *
   * @returns 未接线时返回 `null`（**不抛** —— 让调用方显示"正在初始化"而不是崩）
   */
  static getCookieStore(): EhCookieStore | null {
    return AppWiring.sCookieStore;
  }

  private static sCookieStore: EhCookieStore | null = null;

  /**
   * 就绪信号（`whenReady()` 的 Promise）。
   *
   * **为什么需要它**（`ui-scene` 报的时序竞态）：
   * `EntryAbility.onCreate` 里的 `wire()` 是 **async fire-and-forget**（框架不 await），
   * 而 `onWindowStageCreate` → `loadContent('pages/Index')` 与它**并发**。
   * 于是页面首帧调 `MainPageHost.attachScene('DownloadsScene')` 时，
   * `SceneApplication` 里**可能还没注册过任何场景** → `createScene` 抛 `'The scene is not registered'`。
   *
   * 这条竞态有**两种表现**，都被今天验证过：
   *   - 若页面不 catch → 首帧崩（黑屏/闪退）
   *   - 若页面 catch 后静默 → 永久空白（"静默降级"那一族）
   *
   * 所以两半都要：**A 这个就绪信号（正常路径不撞）+ B 调用方 catch（撞上了有明确 UI）**。
   */
  private static sReadyPromise: Promise<void> | null = null;
  private static sReadyResolve: (() => void) | null = null;
  private static sReadyReject: ((e: Error) => void) | null = null;

  /**
   * 等接线完成。
   *
   * 语义（三条都要）：
   * - **已就绪 → 立即 resolve**（不制造无谓的一帧延迟）
   * - **未开始 → 也 resolve 一个"稍后"的 Promise**，由 `wire()` 完成时兑现
   *   （不能在这里就去触发 `wire()` —— 那需要 context，只有 `EntryAbility` 有）
   * - **`wire()` 失败 → reject**（**不能 resolve** —— 否则调用方以为"就绪了"然后撞一堆 `'EhDB is not attached'`）
   *
   * 调用方用法（`pages/Index.ets`）：
   * ```ts
   * await AppWiring.whenReady();
   * const scene = this.pageHost.attachScene('DownloadsScene');
   * ```
   * **并且仍然要 try/catch** —— 这条 Promise 只覆盖"wire 完成/失败"，
   * 不覆盖"场景没注册"（那是 `registerAllScenes` 的结果，见 `getDrawerRoutingReport`）。
   */
  static whenReady(): Promise<void> {
    if (AppWiring.sWired) { return Promise.resolve(); }
    if (AppWiring.sReadyPromise === null) {
      AppWiring.sReadyPromise = new Promise<void>((resolve: () => void, reject: (e: Error) => void): void => {
        AppWiring.sReadyResolve = resolve;
        AppWiring.sReadyReject = reject;
      });
    }
    return AppWiring.sReadyPromise;
  }

  /** `wire()` 末尾调用；幂等。 */
  private static signalReady(): void {
    const r: (() => void) | null = AppWiring.sReadyResolve;
    if (r !== null) { AppWiring.sReadyResolve = null; AppWiring.sReadyReject = null; r(); }
  }

  /** wire() 的 catch 分支调用；幂等。**不 resolve**，必须 reject。 */
  static rejectReady(e: Error): void {
    const rj: ((e: Error) => void) | null = AppWiring.sReadyReject;
    if (rj !== null) { AppWiring.sReadyResolve = null; AppWiring.sReadyReject = null; rj(e); }
  }

  /** 是否已完成接线（供诊断与 `DownloadService` 的幂等兜底使用）。 */
  static isWired(): boolean {
    return AppWiring.sWired;
  }

  /**
   * 完成全部启动接线。幂等。
   *
   * @param context `EntryAbility.onCreate` 的 `this.context`
   * @param isLogin 登录态提供者（来自 net-parse 的 `EhCookieStore`）。
   *                不传则不注入 —— `Settings.isLogin()` 会返回 false，
   *                所有需要登录的功能（收藏/评分/评论/EX 站）会走未登录分支。
   *                传 null 是**显式选择不注入**，便于分阶段上线。
   */
  static async wire(context: common.Context, isLogin?: (() => boolean) | null,
                    installCrash?: ((onCrash: (t: CrashError) => void) => number | void) | null): Promise<void> {
    if (AppWiring.sWired) {
      hilog.info(DOMAIN, TAG, 'wire: already wired, skip');
      return;
    }

    // **运行期观测面（check_init_order.ps1 判据 F 会查这两条字面量）**。
    // 为什么必须有：本方法在 `EntryAbility.onCreate` 里是 **fire-and-forget**（没有 await），
    // 而"wire 完成前读到默认设置"这类事故**静态扫不出来**（W-01 / R-01 都是这个形态）。
    // 有 begin/done 两条日志，才能从真机 hilog 里判断"某次读设置发生在 wired 之前还是之后"。
    hilog.info(DOMAIN, TAG, 'wire begin (0/7)');

    // ① AppConfig —— 必须最先。`sFilesDir` / `sCacheDir` 是**所有目录的唯一来源**。
    //
    // 审计 W-01（P0）：我第一版漏了这一步，后果是 7 个目录 getter 全返回 null：
    //   getExternalAppDir / getDefaultDownloadDir / getTempDir / getArchiverDir
    //   / getExternalTempDir / getExternalCrashDir / getExternalArchiverDir
    // 表现为"功能静默不工作"（正是本文件头注释说要消灭的那种）：
    //   下载功能整体不可用（Settings.getDownloadLocation 的 fallback 是 null）
    //   归档下载第一次请求前就 notifyFailure('Cannot resolve archiver directory')
    //   归档导入直接 handleFailedTask
    //   Crash.saveCrashLog 返回 null（连 warn 都没有）→ D-006 承诺的崩溃日志仍然落空
    AppConfig.initialize(context);
    if (!AppConfig.isInitialized()) {
      // 宁可启动期硬失败，也不要运行期拿到 null 目录后静默降级
      throw new Error('AppConfig.initialize failed: filesDir/cacheDir not set');
    }
    hilog.info(DOMAIN, TAG, 'wired: 1/7 AppConfig');

    // ② Settings —— 所有读路径的源头；未 attach 时读到的全是默认值。
    await Settings.attach(context);
    if (!GetText.isInitialized()) {
      GetText.initialize(context);
    }
    hilog.info(DOMAIN, TAG, 'wired: 2/7 Settings');

    // ③ EhDB —— 34 个 DB 方法的前置条件。
    //    上游在 `DBOpenHelper extends DaoMaster.OpenHelper` 里自建 DaoMaster/DaoSession：
    //      onCreate  → createAllTables(db, false)
    //      onUpgrade → upgradeDB(db, oldVersion, newVersion)
    //    ArkTS 侧 relationalStore 全是 Promise，没有 OpenHelper 的自动回调，所以这里显式编排。
    const config: relationalStore.StoreConfig = {
      name: AppWiring.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    // 审计 W-03（P1）：第一版直接 `createAllTables(store, true)` 就完了，
    // 既不设 `store.version` 也不调 `EhDB.migrate` —— 存量库（如从 Android EhViewer 导入的 .db）
    // 的 `CREATE TABLE IF NOT EXISTS` 不会补新列 → DAO 查询引用新列（DOWNLOADS.ARCHIVE_URI、
    // Gallery_Tags.LOCATION）→ 运行期 SQL 报错。
    const oldVersion: number = store.version;   // PRAGMA user_version
    if (oldVersion === 0) {
      // 建表。
      //
      // ⚠ **必须传 true（IF NOT EXISTS），不能传 false。**
      // 这是 auditor-logic 的 R-01（P0，只在**升级设备**上复现 —— 最难查的那一类）：
      //   本项目早于 version 化的构建（`2104f5a2` / `23502405`）调的是 `createAllTables(store, true)`
      //   **且从不写 `store.version`** → 那些设备上 10 张表齐全、`user_version` 仍是 0。
      //   升级到当前版本 → `oldVersion === 0` 成立 → 走"全新库"分支 → 第一张表就是
      //   `CREATE TABLE "Gallery_Tags" (...)`（无 IF NOT EXISTS）→ `table Gallery_Tags already exists`
      //   → `store.executeSql` reject → 异常冒出 `wire()` → `sWired` 永远 false
      //   → `EhDB.attach` / 两个注入器 / `MAX_HISTORY_COUNT` 全没执行，而用户侧只有一行 error 日志。
      //
      // 上游为什么安全：Android `SQLiteOpenHelper` 里 `version == 0` **⟺ 文件是新建的**
      // （Android 每次建库都会写 user_version）。我们这个 port 第一版没写 version，
      // **把这个不变量破坏了** —— 所以 `version === 0` 在本项目不再等价于"全新库"。
      //
      // 幂等建表对全新库语义完全一致，所以 `true` 是安全的。
      await DaoMaster.createAllTables(store, true);
      hilog.info(DOMAIN, TAG, 'EhDB: fresh db (version=0), tables ensured');
    } else if (oldVersion < DaoMaster.SCHEMA_VERSION) {
      // 存量库：走六级迁移链（`EhDB.migrate` 已实现含事务 + "列已存在"容错）
      await EhDB.migrate(store, oldVersion);
      hilog.info(DOMAIN, TAG, 'EhDB: migrated %{public}d -> %{public}d',
        oldVersion, DaoMaster.SCHEMA_VERSION);
    } else if (oldVersion > DaoMaster.SCHEMA_VERSION) {
      // 降级：事务内重建全部表并强制写回 SCHEMA_VERSION，防止每次启动重复清空
      hilog.warn(DOMAIN, TAG, 'EhDB: db version %{public}d > schema %{public}d, recreating',
        oldVersion, DaoMaster.SCHEMA_VERSION);
      store.beginTransaction();
      try {
        await DaoMaster.dropAllTables(store, true);
        await DaoMaster.createAllTables(store, false);
        store.version = DaoMaster.SCHEMA_VERSION;
        store.commit();
      } catch (recreateErr) {
        store.rollBack();
        throw recreateErr as Error;
      }
    }
    // 与 SQLiteOpenHelper.setVersion 对位：迁移/降级完成后无条件校正版本号
    if (store.version !== DaoMaster.SCHEMA_VERSION) {
      store.version = DaoMaster.SCHEMA_VERSION;
    }
    const dbDir: string | null = (context.databaseDir !== undefined && context.databaseDir !== null &&
      context.databaseDir.length > 0) ? context.databaseDir : null;
    EhDB.attach(new DaoMaster(store).newSession(), context, dbDir);
    // 历史裁剪阈值：上游在 DBOpenHelper 里赋 `MAX_HISTORY_COUNT = Settings.getHistoryInfoSize()`。
    // 注意 `getHistoryInfoSize` 是**副作用型 getter**：读到 <100 的值会自愈写回 100（上游 L1541 如此）。
    EhDB.MAX_HISTORY_COUNT = Settings.getHistoryInfoSize();
    hilog.info(DOMAIN, TAG,
      'wired: 3/7 EhDB (store=%{public}s, version=%{public}d, maxHistory=%{public}d)',
      AppWiring.DB_NAME, store.version, EhDB.MAX_HISTORY_COUNT);

    // ③b 确保 Cookie 与 Hosts 表存在后再打开 RdbCookieStore 与 Hosts（防全新安装 SQL 崩）
    await store.executeSql(CookieTable.createTableSql(), []);
    await store.executeSql(Hosts.buildCreateTableSql(), []);

    const cookieBackend: RdbCookieStore = new RdbCookieStore();
    await cookieBackend.open(new RdbCookieDbAdapter(store));
    const cookieStore: EhCookieStore = new EhCookieStore(cookieBackend);
    AppWiring.sCookieStore = cookieStore;
    hilog.info(DOMAIN, TAG,
      'wired: 3b/7 EhCookieStore（Rdb，isLoaded=%{public}s hasSignedIn=%{public}s flushFailures=%{public}d）',
      String(cookieBackend.isLoaded()), String(cookieStore.hasSignedIn()), cookieBackend.flushFailures());
    if (Settings.isAttached() && !Settings.hasShowJpnTitle()) {
      const fromUConfig: boolean | null = UConfigPageCoordinator.syncShowJpnTitleFromCookieStore(cookieStore);
      if (fromUConfig === true) {
        Settings.putShowJpnTitle(true);
        void Settings.flush();
        hilog.info(DOMAIN, TAG, 'wired: auto-enabled show_jpn_title from existing uconfig cookie (tl_j)');
      }
    }

    const hosts: Hosts = new Hosts(new RdbHostsStore(new RdbHostsDbAdapter(store)));
    const ehHosts: OkHttpEhHosts = new OkHttpEhHosts(
      new SettingsEhHostsConfig(), null, new HostsAsyncAdapter(hosts));
    const proxySelector: OkHttpEhProxySelector =
      new OkHttpEhProxySelector(EhProxySelector.defaultProxySettings());
    proxySelector.updateProxy();
    const cacheDir: string | undefined = context.cacheDir;
    const httpCache: Cache | null = (cacheDir !== undefined && cacheDir !== null && cacheDir.length > 0)
      ? new Cache(cacheDir + '/' + EhApplication.OKHTTP_CACHE_DIR_NAME, EhApplication.OKHTTP_CACHE_MAX_SIZE)
      : null;
    EhApplication.setNetworkDeps(cookieStore, hosts, ehHosts, proxySelector, httpCache);
    hilog.info(DOMAIN, TAG,
      'wired: 3c/7 NetworkDeps builtInHosts=%{public}s builtExHosts=%{public}s doh=%{public}s df=%{public}s proxyType=%{public}d',
      String(Settings.getBuiltInHosts()), String(Settings.getBuiltEXHosts()),
      String(Settings.getDoH()), String(Settings.getDF()), Settings.getProxyType());

    if (isLogin !== undefined && isLogin !== null) {
      Settings.setLoginProvider(isLogin);
      hilog.info(DOMAIN, TAG, 'wired: 6/7 Settings.setLoginProvider (override)');
    } else {
      Settings.setLoginProvider((): boolean => cookieStore.hasSignedIn());
      hilog.info(DOMAIN, TAG, 'wired: 6/7 Settings.setLoginProvider (cookieStore)');
    }

    // ③c 注入 Client/Parser/UI 静态设置与默认图片请求宿主（必须在 getOkHttpClient 前完成）
    EhUrl.setSiteConfig(new SettingsEhUrlSiteConfig());
    EhEngine.setConfig(new SettingsEhEngineConfig(context));
    EhRequest.setConfig(new SettingsEhRequestConfig());
    EhUtils.setConfig(new SettingsEhUtilsConfig(cookieStore));
    FavoritesParser.setConfig(new SettingsFavoritesParserConfig(context));
    GalleryDetailParser.setConfig(new SettingsGalleryDetailParserConfig());
    SolidSceneSettingsHolder.set(new SettingsSolidSceneAdapter());
    SolidSceneHooks.needSignedIn = (): boolean => Settings.getNeedSignIn() && !cookieStore.hasSignedIn();
    SolidSceneHooks.canCheckSignIn = (): boolean => true;
    EhActivitySettingsHolder.set(new SettingsEhActivityAdapter());
    LoadImageController.setDefaultRequestHost(new DefaultImageRequestHost());

    EhApplication.setConacoDecoder((opened: Object, hardware: boolean): DecodedImage | null => {
      return Image.decodeStream(opened as fs.File, hardware) as Object as DecodedImage | null;
    });
    EhApplication.getConaco(context);
    EhApplication.getSpiderInfoCache(context);

    const imageCacheDir: string = (cacheDir !== undefined && cacheDir !== null && cacheDir.length > 0)
      ? (cacheDir + '/image')
      : 'image';
    SpiderDen.initialize(imageCacheDir, Settings.getReadCacheSize());
    SpiderDen.setSyncDownloadSettingProvider(new SettingsSyncDownloadProvider());
    SpiderDen.setDirnameStore(new EhDbDirnameStoreAdapter());
    SpiderDen.setTitleProvider(new EhUtilsTitleProvider());
    SpiderInfo.setDownloadDirProvider(new AppDownloadDirProvider());
    SpiderQueen.setSpiderInfoCacheProvider(new AppSpiderInfoCacheProvider(context));
    EhGalleryProvider.setSpiderQueenFactory(
      (info: GalleryInfo, mode: number): SpiderQueenLike =>
        SpiderQueen.obtainSpiderQueen(info, mode) as Object as SpiderQueenLike
    );
    EhGalleryProvider.setSpiderQueenReleaser(
      (queen: SpiderQueenLike): void => {
        SpiderQueen.releaseSpiderQueen(queen as Object as SpiderQueen, SpiderQueen.MODE_READ);
      }
    );

    const dynamicCaller: HttpCaller = new OkHttpCallerAdapter(
      (): OkHttpClient => EhApplication.getOkHttpClient(context));

    // ④ 图片字节下载器 —— 动态取当前 OkHttpClient（Proxy / DF 热更后立即生效）。
    SpiderQueen.setPageImageDownloader(new DynamicPageImageDownloader(context));
    hilog.info(DOMAIN, TAG, 'wired: 4/7 SpiderQueen.setPageImageDownloader');

    // ⑤ 阅读页解析引擎 —— 使用动态 OkHttpClient 适配器，并注入详情与预览集拉取器供下载阶段补全 SpiderInfo。
    SpiderQueen.setEhEngine(new EhEngineLikeAdapter(dynamicCaller));
    SpiderQueen.setGalleryDetailFetcher(new EhEngineGalleryDetailFetcher(dynamicCaller));
    SpiderQueen.setPreviewSetFetcher(new EhEnginePreviewSetFetcher(dynamicCaller));
    hilog.info(DOMAIN, TAG, 'wired: 5/7 SpiderQueen.setEhEngine (+OkHttpCallerAdapter +DetailFetcher +PreviewSetFetcher)');

    // ⑥c 过滤器与黑名单注入（先完成异步 reload 再暴露给引擎与详情解析器）
    const filterStore: EhDbFilterStore = new EhDbFilterStore();
    await filterStore.reload();
    EhEngine.setFilterStore(filterStore);
    hilog.info(DOMAIN, TAG, 'wired: 6c/7 EhEngine.setFilterStore(EhDbFilterStore)');

    const blackListHook: CachedBlackListHook = new CachedBlackListHook();
    await blackListHook.reload();
    EhDB.setBlackListChangeListener((): void => {
      blackListHook.reload().catch((err: Object): void => {
        hilog.error(DOMAIN, TAG, 'CachedBlackListHook reload failed: %{public}s', (err as Error).message);
      });
    });
    GalleryDetailParser.setBlackListHook(blackListHook);
    hilog.info(DOMAIN, TAG, 'wired: 6d/7 GalleryDetailParser.setBlackListHook');

    // ⑥e 下载管理器与服务上下文绑定（不主动拉起空闲前台通知，仅挂载监听与动作入口）
    A7ZipArchive.setBridge(createNativeA7ZipBridge());
    const downloadManager: DownloadManager = await DownloadManager.getInstance();
    await DownloadService.getInstance().bindContext(context as common.UIAbilityContext, downloadManager);
    ArchiverDownloadService.getInstance().attach(context as common.UIAbilityContext);
    ArchiverDownloader.setCookieProvider((rawUrl: string): string => {
      const parsed: HttpUrl | null = HttpUrl.parse(rawUrl);
      if (parsed === null) {
        return '';
      }
      return cookieStore.getCookieHeader(parsed);
    });
    ArchiverDownloader.resumePending().catch((err: Object): void => {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'ArchiverDownloader.resumePending failed: %{public}s', msg);
    });
    hilog.info(DOMAIN, TAG, 'wired: 6e/7 DownloadManager + DownloadService + ArchiverDownloadService + A7ZipArchive');

    // ⑥f GL 阅读器与原生图像桥（D-020 Image1 bridge + GalleryLayoutFactory + 文字纹理）
    Image.initialize();
    Image1.setBridge(createNativeLibImageBridge());
    GalleryLayoutFactory.setPagerCreator((gv: GalleryView, scaleMode: number,
      startPosition: number, pagerInterval: number): PagerLayoutManager =>
      new PagerLayoutManager(gv, scaleMode, startPosition, 1.0, pagerInterval));
    GalleryLayoutFactory.install();
    GalleryView.setTextRendering(DrawingTextPaintFactory.getInstance(), DrawingOffscreenCanvas.getInstance());
    hilog.info(DOMAIN, TAG, 'wired: 6f/7 Image + Image1 + GalleryLayoutFactory + GalleryView text');

    // ⑦ 场景工厂注册
    const sceneApp: SceneApplication = SceneApplication.get();
    const sceneCaller: HttpCaller = dynamicCaller;
    const sceneOverrides: Map<string, () => SceneFragment> = new Map<string, () => SceneFragment>();

    // **GalleryListScene** —— 本地收藏与下载入队真实接线
    sceneOverrides.set('GalleryListScene', (): SceneFragment => {
      const listScene: GalleryListSceneConcrete = new GalleryListSceneConcrete();
      listScene.setDownloadEnqueuer(new RealDownloadEnqueuer(downloadManager));
      listScene.setFavoritesRepository(new RealLocalFavoritesRepo());
      return listScene;
    });

    // **FavoritesScene** —— 本地收藏真实接线 + 云端收藏拉取
    sceneOverrides.set('FavoritesScene', (): SceneFragment => {
      const fav: FavoritesSceneConcrete = new FavoritesSceneConcrete();
      fav.setLocalFavoritesRepo(new LocalFavoritesRepoAdapter(
        (): Promise<GalleryInfo[]> => EhDB.getAllLocalFavorites()));
      fav.setFavMeta(Settings.getFavCat(), Settings.getFavCount());
      fav.setOnMetaUpdatedListener((cats: string[], counts: number[]): void => {
        Settings.putFavCat(cats);
        Settings.putFavCount(counts);
      });
      fav.setClient(new EhClientFavoritesAdapter(
        (url: string, force: boolean) => EhEngine.getFavorites(null, sceneCaller, url, force)));
      return fav;
    });

    sceneOverrides.set('SecurityScene', (): SceneFragment =>
      new SecuritySceneShell(new SettingsSecurityAdapter()));
    sceneOverrides.set('DownloadsScene', (): SceneFragment =>
      new WiredDownloadsSceneShell(downloadManager));
    sceneOverrides.set('SignInScene', (): SceneFragment => {
      const signInPage: SignInSceneConcrete = new SignInSceneConcrete();
      signInPage.setSignInClient(new EhEngineSignInClient(sceneCaller));
      signInPage.setSkipSignInHandler((): void => {
        Settings.putNeedSignIn(false);
      });
      return signInPage;
    });
    sceneOverrides.set('CookieSignInScene', (): SceneFragment => {
      const signIn: CookieSignInSceneConcrete = new CookieSignInSceneConcrete();
      signIn.setCookieWriter(new EhCookieWriter(cookieStore));
      signIn.setLegacyStore(new SettingsLegacyCookieAdapter());
      signIn.setClipboard(new SystemPasteboardAdapter());
      return signIn;
    });
    sceneOverrides.set('WebViewSignInScene', (): SceneFragment => {
      const wv: WebViewSignInSceneConcrete = new WebViewSignInSceneConcrete();
      wv.setCookieJar(new EhCookieStoreProfileJar(cookieStore));
      wv.setSignInUrl(EhUrl.URL_SIGN_IN);
      return wv;
    });
    sceneOverrides.set('GetProfileScene', (): SceneFragment => {
      const shell: GetProfileSceneShell = new GetProfileSceneShell(null, new EhCookieStoreProfileJar(cookieStore));
      shell.setOnProfileLoadedListener((profile: ProfileResult): void => {
        Settings.putDisplayName(profile.displayName);
        Settings.putAvatar(profile.avatar);
      });
      return shell;
    });
    sceneOverrides.set('ProgressScene', (): SceneFragment => {
      const shell: ProgressSceneShell = new ProgressSceneShell(null);
      shell.setRequester(new AsyncGalleryTokenRequester(
        (gid: number, pToken: string, page: number): Promise<string> =>
          EhEngine.getGalleryToken(null, sceneCaller, gid, pToken, page),
        (token: string): void => { shell.onGetGalleryTokenSuccess(token); },
        (err: string): void => { shell.onGetGalleryTokenFailure(err, true); }
      ));
      return shell;
    });
    sceneOverrides.set('GalleryDetailScene', (): SceneFragment => {
      const detail: GalleryDetailSceneConcrete = new GalleryDetailSceneConcrete();
      detail.setDetailClient(new EhEngineDetailClient(sceneCaller));
      detail.setDetailActionClient(new RealDetailActionClient(sceneCaller, downloadManager));
      return detail;
    });
    sceneOverrides.set('GalleryCommentsScene', (): SceneFragment => {
      const commentsScene: GalleryCommentsSceneConcrete = new GalleryCommentsSceneConcrete();
      commentsScene.setCommentClient(new RealCommentClient(sceneCaller));
      return commentsScene;
    });
    sceneOverrides.set('QuickSearchScene', (): SceneFragment =>
      new QuickSearchSceneShell(new QuickSearchScene()));
    sceneOverrides.set('HistoryScene', (): SceneFragment => {
      const ref: ShellSceneRef = new ShellSceneRef();
      const host: RealHistorySceneHost = new RealHistorySceneHost(ref, downloadManager);
      const shell: WiredHistorySceneShell = new WiredHistorySceneShell(new HistoryScene(host));
      ref.scene = shell;
      return shell;
    });
    sceneOverrides.set('DownloadLabelsScene', (): SceneFragment => {
      const ref: ShellSceneRef = new ShellSceneRef();
      const host: RealLabelsSceneHost = new RealLabelsSceneHost(ref, downloadManager);
      const shell: DownloadLabelsSceneShell = new DownloadLabelsSceneShell(new DownloadLabelsScene(host));
      ref.scene = shell;
      return shell;
    });
    sceneOverrides.set('EhTopListScene', (): SceneFragment => {
      const ref: ShellSceneRef = new ShellSceneRef();
      const host: RealTopListSceneHost = new RealTopListSceneHost(ref);
      const shell: WiredTopListSceneShell =
        new WiredTopListSceneShell(new EhTopListScene(host, new RealTopListApi(sceneCaller)));
      ref.scene = shell;
      return shell;
    });
    sceneOverrides.set('SubscriptionsScene', (): SceneFragment => {
      const ref: ShellSceneRef = new ShellSceneRef();
      const host: RealSubscriptionsSceneHost = new RealSubscriptionsSceneHost(ref);
      const api: RealSubscriptionsApi = new RealSubscriptionsApi(sceneCaller);
      const shell: SubscriptionsSceneShell =
        new SubscriptionsSceneShell(new SubscriptionsScene(host, api));
      ref.scene = shell;
      return shell;
    });
    sceneOverrides.set('GalleryInfoScene', (): SceneFragment => {
      const ref: ShellSceneRef = new ShellSceneRef();
      const host: RealGalleryInfoSceneHost = new RealGalleryInfoSceneHost(ref, context);
      const shell: WiredGalleryInfoSceneShell = new WiredGalleryInfoSceneShell(new GalleryInfoScene(host));
      ref.scene = shell;
      return shell;
    });
    sceneOverrides.set('GalleryPreviewsScene', (): SceneFragment =>
      new WiredGalleryPreviewsSceneShell(new GalleryPreviewsScene(
        new NullPreviewsSceneHost(), new NullPreviewHelperPort())));

    const regResults: SceneRegResult[] = registerAllScenes(sceneApp, sceneOverrides);
    const registered: number = regResults.filter((r: SceneRegResult): boolean => r.registered).length;
    hilog.info(DOMAIN, TAG, 'wired: 7/7 SceneRegistry —— %{public}d/%{public}d 场景可装配',
      registered, regResults.length);
    // 抽屉 9 项的装配状态逐条打出来 —— 这是"用户点哪个会崩"的唯一可观测面
    for (const line of getDrawerRoutingReport(regResults)) {
      hilog.warn(DOMAIN, TAG, 'scene-routing: %{public}s', line);
    }

    SearchHistoryPrefsStore.configureStore(new SettingsSearchHistoryKvStore());
    const tagClient: OkHttpClient = EhApplication.getOkHttpClient(context);
    EhTagDatabaseUpdater.configure(new EhTagUpdaterConfig(
      new AppTagDatabaseIo(),
      (): string | null => AppConfig.getFilesDir('tag-translations'),
      (): boolean => Settings.getShowTagTranslations(),
      async (url: string): Promise<ArrayBuffer | null> => {
        try {
          const req: Request = new RequestBuilder().url(url).get().build();
          const resp: OkResponse = await tagClient.newCall(req).execute();
          if (resp.code() < 200 || resp.code() >= 300) {
            return null;
          }
          const body: ResponseBody | null = resp.body();
          return body !== null ? body.bytes() : null;
        } catch (e) {
          const msg: string = e instanceof Error ? e.message : String(e);
          hilog.warn(DOMAIN, TAG, 'tag-db fetch failed for %{public}s: %{public}s', url, msg);
          return null;
        }
      }
    ));

    AppWiring.sWired = true;
    hilog.info(DOMAIN, TAG, 'wire done (sWired=true)');
    // **就绪信号**：让 `AppWiring.whenReady()` 的等待者继续（含"wire 才开始就被 await"的情况）
    AppWiring.signalReady();

    // ⑧ **版本跟踪（`core-runtime` 报的真缺口②）** —— 对应上游 `EhApplication.onCreate` 里的
    //      `update(); … Settings.putVersionCode(versionCode)`。
    //
    //      没有这两句时：`EhApplication.update()` **全仓 0 调用者** →
    //      "从 <52 升级上来的用户首次看到画廊引导"这条路径是**惰性的**（永远不触发）。
    //
    //      **顺序不能反**（`core-runtime` 特别标注）：
    //        ① `update(Settings.getVersionCode())` —— 用**上次运行**的版本判断 < 52
    //        ② `Settings.putVersionCode(current)` —— 再写本次版本
    //      反过来第一次启动就写成本次版本，"从旧版本升级"的分支永远不成立。
    //
    //      `previousVersionCode === 0` 表示**首次安装**（从未记录）——
    //      上游同样走 `0 < 52` 的升级分支，所以首次安装也会显示一次引导（照搬，不"优化"）。
    const previousVersionCode: number = Settings.getVersionCode();
    EhApplication.update(previousVersionCode);
    // 本次版本号从 bundle 信息取。`getBundleInfoForSelfSync` 在 `@kit.AbilityKit` 的 `bundleManager` 下；
    // 取不到（异常 / 字段缺失）时**不写 0** —— 写 0 会让下次启动误判"从旧版本升级"从而重复显示引导。
    let currentVersionCode: number = previousVersionCode;
    try {
      const selfInfo: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      currentVersionCode = selfInfo.versionCode;
    } catch (e) {
      hilog.error(DOMAIN, TAG, '读 versionCode 失败（保持上次值，不写 0）: %{public}s', (e as Error).message);
    }
    Settings.putVersionCode(currentVersionCode);
    hilog.info(DOMAIN, TAG,
      'wired: 8/8 版本跟踪 previous=%{public}d current=%{public}d（<52 → 显示画廊引导）',
      previousVersionCode, currentVersionCode);

    // ⑥ 崩溃捕获 —— 对应上游 `EhApplication.onCreate` 第一段
    //      `Thread.setDefaultUncaughtExceptionHandler(...)` 里的
    //      `if (!initialized || Settings.getSaveCrashLog()) Crash.saveCrashLog(...)`
    //
    //      **必须在 `sWired = true` 之后安装**：`Crash.shouldSave` 的判据是
    //      `!wiringCompleted || saveEnabled` —— 接线完成前的崩溃**无条件记录**（那是最容易崩的时段），
    //      之后才受用户开关约束。core-runtime 的 `Crash.shouldSave` 每次崩溃时重新求值，
    //      所以这里只需把 `AppWiring.isWired()` 传进去。
    // 崩溃捕获安装：由 core-runtime 的 `CrashObserver.installCrashHandler` 提供（他已交付 23 条断言）。
    // 我这边只提供接入点 —— 传进来的 `installCrash(handleCrash)` 会把 `AppWiring.handleCrash` 挂上。
    // 未传时**明确打 warn**，不要假装已接线（审计 W-04 指出第一版日志虚报 6/6）。
    if (installCrash !== undefined && installCrash !== null) {
      installCrash((t: CrashError): void => { AppWiring.handleCrash(t); });
      hilog.info(DOMAIN, TAG, 'wired: crash handler installed');
    } else {
      hilog.warn(DOMAIN, TAG, 'crash handler NOT installed (caller 未提供 installCrash)');
    }
    hilog.info(DOMAIN, TAG, 'wired: 7/7 (crash handler wired=%{public}s)', String(installCrash !== undefined && installCrash !== null));
    EhTagDatabaseUpdater.update(false).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'tag-db startup update failed: %{public}s', e.message);
    });
  }

  /** 安全读取 string 资源（测试/无 resourceManager 环境返回 fallback）。 */
  static readResString(context: common.Context | null, resName: string, fallback: string): string {
    if (context === null || context === undefined) {
      return fallback;
    }
    try {
      const rm: Object | undefined = context.resourceManager as Object | undefined;
      if (rm !== undefined && rm !== null) {
        const val: string = context.resourceManager.getStringByNameSync(resName);
        if (val !== undefined && val !== null && val.length > 0) {
          return val;
        }
      }
    } catch (_e) {
      // Fallback when resource name is absent in isolated unit tests
    }
    return fallback;
  }

  /**
   * 写文本文件（建目录 + 写）。
   *
   * 崩溃路径上**不能用 async 链**（进程可能马上死了），所以这里同步写。
   *
   * @internal 供崩溃观察者调用
   */
  static writeText(path: string, text: string): Promise<void> {
    try {
      const dir: string = path.substring(0, path.lastIndexOf('/'));
      if (dir.length > 0) {
        try {
          fs.accessSync(dir);
        } catch (e) {
          fs.mkdirSync(dir, true);
        }
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      // 审计 W-06：`writeSync` 抛错时下面的 closeSync 不执行 → fd 泄漏。
      // `handleCrash` 可能被 errorManager 多次回调，每次泄漏一个 → 用 finally 兜住。
      try {
        fs.writeSync(file.fd, text);
      } finally {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 关不上不影响原始崩溃记录
        }
      }
    } catch (e) {
      return Promise.reject(e as Error);
    }
    return Promise.resolve();
  }

  /**
   * 一次崩溃的处理体。拆出来是为了让观察者的两个入口共用。
   *
   * 每次崩溃**重新求值**开关（不能安装时求一次）：
   * 否则「启动期要记录」与「稳定期关掉开关就不记」无法同时成立。
   */
  static handleCrash(t: Object): void {
    const errMsg: string = t instanceof Error ? t.message : String(t);
    const errStack: string = t instanceof CrashError
      ? (t as CrashError).stackText
      : ((t instanceof Error && t.stack !== undefined) ? t.stack : '');
    hilog.error(DOMAIN, TAG, 'uncaught error: %{public}s stack=%{public}s', errMsg, errStack);
    if (!Crash.shouldSave(AppWiring.sWired, Settings.getSaveCrashLog())) {
      hilog.info(DOMAIN, TAG, 'crash: 用户已关闭崩溃日志，跳过');
      return;
    }
    Crash.saveCrashLog(t, AppWiring.pkgInfo, AppWiring.deviceInfo, AppWiring.memoryInfo,
      (): string | null => null, new CrashRuntimeInfo('', null),
      (x: Object): string => {
        if (x instanceof CrashError) {
          return (x as CrashError).stackText;
        }
        const e: Error = x as Error;
        return (e !== null && e !== undefined && e.stack !== undefined) ? e.stack : '';
      },
      (path: string, text: string): Promise<void> => AppWiring.writeText(path, text),
      (path: string): void => {
        try {
          fs.unlinkSync(path);
        } catch (e) {
          // 删半截文件失败不掩盖原始崩溃
        }
      }).then((written: string | null): void => {
        if (written !== null) {
          hilog.info(DOMAIN, TAG, 'crash log written: %{public}s', written);
        }
      }).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'crash log write failed: %{public}s', e.message);
      });
  }

  // 崩溃日志的四个采集入参。当前留空占位 —— 上游从 `PackageManager` / `Build` / `ActivityManager` 取，
  // 鸿蒙侧对应 `bundleManager` / `deviceInfo` / `hiAppEvent`，属 core-runtime 的采集面。
  // **先让链路通**（日志能落盘、格式对、失败删半截），采集补全后只改这四个常量。
  private static readonly pkgInfo: PacketInfo | null = null;
  private static readonly deviceInfo: CrashDeviceInfo = new CrashDeviceInfo();
  private static readonly memoryInfo: CrashMemoryInfo = new CrashMemoryInfo();
}

// 崩溃捕获的安装（`errorManager.on('error', new AppErrorObserver())`）留待 core-runtime 交付
// `ErrorObserver` 子类后接入 —— 该类的模块路径 `@ohos.app.ability.ErrorObserver` 在 SDK 20 解析不到
// （d.ts 实际位置 `api/application/ErrorObserver.d.ts`），强行绕过会变成"运行期静默不回调"。
// 可复用的两半已在上面：`AppWiring.writeText`（同步落盘）与 `AppWiring.handleCrash`（编排 + 开关求值）。

/**
 * `okhttp/Response` → `EngineResponse`（`EhEngine` 只取 code / headers / body 字符串）。
 *
 * 形状差异（不能 cast，必须真 adapter）：
 *   `EngineResponse.body(): string`        ↔ `okhttp Response.body(): ResponseBody | null`
 *   `EngineResponse.headers(): EngineHeaders` ↔ `okhttp Headers`（都是 `get(name): string|null`，形状兼容）
 */
class OkHttpEngineResponse implements EngineResponse {
  private readonly _r: OkResponse;
  private readonly _body: string;

  readonly urlHost: string;

  constructor(r: OkResponse) {
    this._r = r;
    this.urlHost = r.request().url().host();
    const b: ResponseBody | null = r.body();
    // 先读 body 再缓存：`EhEngine` 拿到 EngineResponse 后会多次调 body()，只能读一次。
    //
    // ⚠ `close` 必须放 finally（R-03）：`EhEngine.runApi` 的容错链会**故意**抛 ParseException
    //   （`EhEngine.ets:318-321` 的 catch 里再 throwException），所以"string() 抛"是
    //   **常规路径**而不是异常路径 → 不 finally 的话每个失败响应都泄漏一个 body 句柄。
    try {
      this._body = (b !== null) ? b.string() : '';
    } finally {
      if (b !== null) {
        try {
          b.close();
        } catch (e) {
          // 关不上不掩盖原始错误
        }
      }
    }
  }

  code(): number {
    return this._r.code();
  }

  headers(): EngineHeaders {
    // `okhttp Headers.get(name): string | null` 与 `EngineHeaders` 形状完全一致，可安全 cast
    return this._r.headers() as Object as EngineHeaders;
  }

  body(): string {
    return this._body;
  }
}

/** `okhttp/Call` → `EngineCall`。 */
class OkHttpEngineCall implements EngineCall {
  private readonly _c: OkCall;

  constructor(c: OkCall) {
    this._c = c;
  }

  async execute(): Promise<EngineResponse> {
    const r: OkResponse = await this._c.execute();
    return new OkHttpEngineResponse(r);
  }

  isCanceled(): boolean {
    return this._c.isCanceled();
  }

  cancel(): void {
    this._c.cancel();
  }
}

/**
 * `OkHttpClient` → `HttpCaller`。
 *
 * **这是 `HttpCaller` 在生产代码里的第一个实现** —— 审计 W-02 查明此前 `implements HttpCaller`
 * 只存在于 7 个测试文件的 `Fake*` 里，意味着 `EhEngine` 的 19 个 API
 * （signIn / getGalleryList / getGalleryDetail / getAllFavorites / downloadArchive …）
 * 全仓没有一条可用的传输层。
 */
export class OkHttpCallerAdapter implements HttpCaller {
  private readonly _client: OkHttpClient | null;
  private readonly _clientProvider: (() => OkHttpClient) | null;

  constructor(client: OkHttpClient | (() => OkHttpClient)) {
    if (typeof client === 'function') {
      this._client = null;
      this._clientProvider = client;
    } else {
      this._client = client;
      this._clientProvider = null;
    }
  }

  newCall(request: Request): EngineCall {
    const client: OkHttpClient = this._clientProvider !== null
      ? this._clientProvider()
      : (this._client as OkHttpClient);
    return new OkHttpEngineCall(client.newCall(request));
  }
}

class DynamicPageImageDownloader implements PageImageDownloader {
  private readonly _context: common.Context;
  private _lastClient: OkHttpClient | null = null;
  private _impl: PageImageDownloaderImpl | null = null;

  constructor(context: common.Context) {
    this._context = context;
  }

  private current(): PageImageDownloaderImpl {
    const client: OkHttpClient = EhApplication.getOkHttpClient(this._context);
    if (this._impl === null || this._lastClient !== client) {
      this._lastClient = client;
      this._impl = new PageImageDownloaderImpl(client);
    }
    return this._impl;
  }

  download(url: string, sink: ByteSink, referer?: string): Promise<boolean> {
    return this.current().download(url, sink, referer);
  }

  downloadWithStatus(url: string, sink: ByteSink, referer?: string,
    onProgress?: PageDownloadProgressCallback): Promise<DownloadResult> {
    return this.current().downloadWithStatus(url, sink, referer, onProgress);
  }
}

class SettingsSyncDownloadProvider implements SyncDownloadSettingProvider {
  getSyncDownloadWhileReading(): boolean {
    return Settings.getSyncDownloadWhileReading();
  }
}

class EhDbDirnameStoreAdapter implements DirnameStore {
  getDownloadDirname(gid: number): Promise<string | null> {
    return EhDB.getDownloadDirname(gid);
  }

  putDownloadDirname(gid: number, dirname: string): Promise<void> {
    return EhDB.putDownloadDirname(gid, dirname);
  }
}

class EhUtilsTitleProvider implements GalleryTitleProvider {
  getSuitableTitle(info: GalleryInfo): string {
    const t: string | null = EhUtils.getSuitableTitle(info);
    return t !== null ? t : '';
  }
}

class AppDownloadDirProvider implements DownloadDirProvider {
  getGalleryDownloadDir(info: GalleryInfo): UniFile | null {
    const baseDir: UniFile | null = Settings.getDownloadLocation();
    if (baseDir === null) {
      return null;
    }
    const prefix: string = `${info.gid}-`;
    const files: UniFile[] | null = baseDir.listFilesFiltered(new StartWithFilenameFilter(prefix));
    if (files !== null) {
      let best: UniFile | null = null;
      let maxLen: number = -1;
      for (let i = 0; i < files.length; i++) {
        const candidate: UniFile = files[i];
        if (candidate.isDirectory()) {
          const name: string | undefined = candidate.getName();
          if (name !== undefined && name.length > maxLen) {
            maxLen = name.length;
            best = candidate;
          }
        }
      }
      if (best !== null) {
        return best;
      }
    }
    const title: string | null = EhUtils.getSuitableTitle(info);
    const safeName: string = FileUtils.sanitizeFilename(`${info.gid}-${title !== null ? title : ''}`);
    return baseDir.findFile(safeName);
  }
}

class AppSpiderInfoCacheProvider implements SpiderInfoCacheProvider {
  private readonly _context: common.Context;

  constructor(context: common.Context) {
    this._context = context;
  }

  getSpiderInfoCache(): SimpleDiskCache | null {
    return EhApplication.getSpiderInfoCache(this._context);
  }
}

class CachedBlackListHook implements BlackListHook {
  private readonly blockedUsers: Set<string> = new Set<string>();

  async reload(): Promise<void> {
    const rows: BlackList[] = await EhDB.getAllBlackList();
    this.blockedUsers.clear();
    for (let i = 0; i < rows.length; i++) {
      const name: string | null = rows[i].badgayname;
      if (name !== null) {
        this.blockedUsers.add(name);
      }
    }
  }

  inBlackList(user: string): boolean {
    return this.blockedUsers.has(user);
  }
}



/**
 * `relationalStore.RdbStore` → `CookieDbLike` 的显式适配器（`W-022`）。
 *
 * **为什么需要它**：ArkTS 的 `arkts-no-untyped-obj-literals` 禁止
 * `const x: CookieDbLike = { querySql: …, executeSql: … }` ——
 * 对象字面量必须对应**显式声明的类或接口实现**。这不是风格问题，是编译错误。
 *
 * `RdbStore` 的 `querySql` / `executeSql` 与 `CookieDbLike` 的方法名和签名一致，
 * 所以这里只是**转发**，不做任何改写（不引入第二层语义）。
 */
class RdbCookieDbAdapter implements CookieDbLike {
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  querySql(sql: string): Promise<relationalStore.ResultSet> {
    return this.store.querySql(sql);
  }

  executeSql(sql: string, args: (string | number)[]): Promise<void> {
    return this.store.executeSql(sql, args);
  }
}

/**
 * `CookieWriterLike` → `EhCookieStore` 的真实实现（`W-017`，2026-10-27）。
 *
 * **为什么必须有它**：`CookieSignInScene` 的默认写入器是 `UnavailableCookieWriter` ——
 * 它只打一条 warn，**cookie 一个字都不会落盘**。于是用户填完表单点「确定」、
 * 页面 `finish()`、看起来"登录成功"，但 `hasSignedIn()` 仍是 false，
 * 下一次启动又弹登录页。**这是"看起来成功但什么都没发生"的最坏形态。**
 *
 * 上游对位：`WebCookieManager.setCookie(url, cookie)`（Android 的 `CookieManager`）。
 *
 * **实现方式**：把 `setCookie` 收到的 `"name=value; name2=value2"` 串**逐段解析**，
 * 每段构一个 `Cookie`（域取 URL 的 host）后 `addCookie`。`CookieRepository.addCookie`
 * 会把它同时写进内存和 `RdbCookieStore`（`W-022` 的持久化后端）。
 *
 * ⚠️ **只处理上游登录真正用到的三个键**（`ipb_member_id` / `ipb_pass_hash` / `igneous`）——
 * 不是通用 cookie 解析器。上游 `storeCookie` 也只写这三个。
 */
class EhCookieWriter implements CookieWriterLike {
  private store: EhCookieStore;

  constructor(store: EhCookieStore) {
    this.store = store;
  }

  setCookie(url: string, cookie: string): void {
    const httpUrl: HttpUrl | null = HttpUrl.parse(url);
    if (httpUrl === null) {
      hilog.warn(DOMAIN, TAG, 'EhCookieWriter.setCookie: URL 解析失败，cookie 未写入: %{public}s', url);
      return;
    }
    const host: string = httpUrl.host();
    const domains: string[] = [EhUrl.DOMAIN_E, EhUrl.DOMAIN_EX];
    if (host !== EhUrl.DOMAIN_E && host !== EhUrl.DOMAIN_EX) {
      domains.push(host);
    }
    let written: number = 0;
    for (const part of cookie.split(';')) {
      const seg: string = part.trim();
      if (seg.length === 0) { continue; }
      const eq: number = seg.indexOf('=');
      if (eq <= 0) { continue; }
      const name: string = seg.substring(0, eq).trim();
      const value: string = seg.substring(eq + 1).trim();
      if (name !== EhCookieStore.KEY_IPD_MEMBER_ID
        && name !== EhCookieStore.KEY_IPD_PASS_HASH
        && name !== EhCookieStore.KEY_IGNEOUS) {
        continue;
      }
      for (let i = 0; i < domains.length; i++) {
        const c: Cookie = new CookieBuilder()
          .name(name)
          .value(value)
          .domain(domains[i])
          .path('/')
          .expiresAt(EhCookieStore.MAX_EXPIRES)
          .build();
        this.store.addCookie(c);
      }
      written++;
    }
    const signedIn: boolean = this.store.hasSignedIn();
    if (signedIn) {
      Settings.setLoginState(true);
    }
    hilog.info(DOMAIN, TAG, 'EhCookieWriter.setCookie: 写入 %{public}d 个键到 %{public}d 个域名（hasSignedIn=%{public}s）',
      written, domains.length, String(signedIn));
  }

  getCookie(url: string): string {
    const httpUrl: HttpUrl | null = HttpUrl.parse(url);
    if (httpUrl === null) { return ''; }
    return this.store.getCookieHeader(httpUrl);
  }
}

class EhEngineSignInClient implements SignInClientLike {
  private caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  async signIn(username: string, password: string): Promise<SignInResult> {
    try {
      const displayName: string = await EhEngine.signIn(null, this.caller, username, password);
      Settings.setLoginState(true);
      if (displayName.length > 0) {
        Settings.putDisplayName(displayName);
      }
      hilog.info(DOMAIN, TAG, 'signIn 成功：displayName=%{public}s', displayName);
      return new SignInResult(true, 0, displayName, '');
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      let code: number = -2;
      // **顺序敏感**：ParseException 必须早于 EhException
      if (e instanceof ParseException) {
        code = -3;
      } else if (e instanceof StatusCodeException) {
        // 上游 StatusCodeException.getResponseCode()（**属性名不是 code**）
        code = (e as StatusCodeException).getResponseCode();
        if (code <= 0) { code = -2; }
      } else if (e instanceof EhException) {
        code = -4;
      }
      hilog.warn(DOMAIN, TAG, 'signIn 失败：code=%{public}d msg=%{public}s', code, msg);
      return new SignInResult(false, code, '', msg);
    }
  }
}

/** `relationalStore.RdbStore` → `HostsDbLike` 适配器。 */
class RdbHostsDbAdapter implements HostsDbLike {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  querySql(sql: string, bindArgs?: Array<string | number>): Promise<HostsResultSetLike> {
    return this.store.querySql(sql, bindArgs);
  }

  executeSql(sql: string, args?: Array<string | number>): Promise<void> {
    return this.store.executeSql(sql, args);
  }
}

/** 将 `Hosts.getList` 的 `Uint8Array[]` 转换为 IP 字符串列表供 `OkHttpEhHosts` 消费。 */
class HostsAsyncAdapter implements AsyncHostsProvider {
  private readonly hosts: Hosts;

  constructor(hosts: Hosts) {
    this.hosts = hosts;
  }

  async getList(hostname: string): Promise<string[] | null> {
    const raw: Uint8Array[] | null = await this.hosts.getList(hostname);
    if (raw === null || raw.length === 0) {
      return null;
    }
    const ips: string[] = [];
    for (let i = 0; i < raw.length; i++) {
      const addr: Uint8Array = raw[i];
      if (addr.length === 4) {
        ips.push(`${addr[0]}.${addr[1]}.${addr[2]}.${addr[3]}`);
      } else if (addr.length === 16) {
        const parts: string[] = [];
        for (let g = 0; g < 16; g += 2) {
          parts.push(((addr[g] << 8) | addr[g + 1]).toString(16));
        }
        ips.push(parts.join(':'));
      }
    }
    return ips.length > 0 ? ips : null;
  }
}

class SettingsEhHostsConfig extends EhHostsConfig {
  getBuiltInHosts(): boolean {
    return Settings.getBuiltInHosts();
  }

  getBuiltEXHosts(): boolean {
    return Settings.getBuiltEXHosts();
  }

  getDoH(): boolean {
    return Settings.getDoH();
  }
}

class SettingsEhUrlSiteConfig extends EhUrlSiteConfig {
  getGallerySite(): number {
    return Settings.getGallerySite();
  }
}

class SettingsEhEngineConfig extends EhEngineConfig {
  private readonly ctx: common.Context | null;

  constructor(ctx: common.Context | null) {
    super();
    this.ctx = ctx;
  }

  isLogin(): boolean {
    return Settings.isLogin();
  }

  getShowGalleryPages(): boolean {
    return Settings.getShowGalleryPages();
  }

  getSaveParseErrorBody(): boolean {
    return Settings.getSaveParseErrorBody();
  }

  kokomadeTip(): string {
    return AppWiring.readResString(this.ctx, 'kokomade_tip', 'Kokomade tip');
  }

  errorEmptyHtml(): string {
    return AppWiring.readResString(this.ctx, 'error_empty_html', 'Empty html');
  }

  errorParseError(): string {
    return AppWiring.readResString(this.ctx, 'error_parse_error', 'Parse error');
  }

  errorIgneousWrong(): string {
    return AppWiring.readResString(this.ctx, 'error_igneous_wrong', 'Igneous wrong');
  }

  saveParseErrorBody(e: ParseException): void {
    const dir: string | null = AppConfig.getExternalParseErrorDir();
    const body: string | null = e.getBody();
    if (dir === null || body === null) {
      return;
    }
    const path: string = `${dir}/${Date.now()}.txt`;
    const content: string = `${e.message}\n\n${body}`;
    AppWiring.writeText(path, content).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'saveParseErrorBody failed (%{public}s): %{public}s',
        path, err instanceof Error ? err.message : String(err));
    });
  }
}

class SettingsEhRequestConfig extends EhRequestConfig {
  getEhConfig(): EhConfig {
    return Settings.getEhConfig();
  }
}

class SettingsEhUtilsConfig extends EhUtilsConfig {
  private readonly cookieStore: EhCookieStore;

  constructor(cookieStore: EhCookieStore) {
    super();
    this.cookieStore = cookieStore;
  }

  getShowJpnTitle(): boolean {
    return Settings.getShowJpnTitle();
  }

  getThumbResolution(): number {
    return Settings.getThumbResolution();
  }

  signOut(): void {
    this.cookieStore.signOut();
    Settings.putAvatar(null);
    Settings.putDisplayName(null);
    Settings.setLoginState(false);
  }

  needSignedIn(): boolean {
    return Settings.getNeedSignIn() && !this.cookieStore.hasSignedIn();
  }
}

class SettingsFavoritesParserConfig extends FavoritesParserConfig {
  private readonly ctx: common.Context | null;

  constructor(ctx: common.Context | null) {
    super();
    this.ctx = ctx;
  }

  getNeedSignInMessage(): string {
    return AppWiring.readResString(this.ctx, 'need_sign_in', 'Need sign in');
  }
}

class SettingsGalleryDetailParserConfig extends GalleryDetailParserConfig {
  getFixThumbUrl(): boolean {
    return Settings.getFixThumbUrl();
  }
}

class SettingsSolidSceneAdapter implements SolidSceneSettings {
  getShowWarning(): boolean {
    return Settings.getShowWarning();
  }

  getAskAnalytics(): boolean {
    return Settings.getAskAnalytics();
  }

  getSelectSite(): boolean {
    return Settings.getSelectSite();
  }

  getNeedSignIn(): boolean {
    return Settings.getNeedSignIn();
  }

  getLaunchPageGalleryListSceneAction(): string {
    return Settings.getLaunchPageGalleryListSceneAction();
  }

  putShowWarning(value: boolean): void {
    Settings.putShowWarning(value);
  }

  putAskAnalytics(value: boolean): void {
    Settings.putAskAnalytics(value);
  }

  putSelectSite(value: boolean): void {
    Settings.putSelectSite(value);
  }

  getGallerySite(): number {
    return Settings.getGallerySite();
  }

  putGallerySite(value: number): void {
    Settings.putGallerySite(value);
  }

  putEnableAnalytics(value: boolean): void {
    Settings.putEnableAnalytics(value);
  }
}

class SettingsSecurityAdapter implements SecuritySettings {
  getSecurity(): string | null {
    return Settings.getSecurity();
  }

  putSecurity(value: string): void {
    Settings.putSecurity(value);
  }

  getEnableFingerprint(): boolean {
    return Settings.getEnableFingerprint();
  }
}

class SettingsEhActivityAdapter implements EhActivitySettings {
  readonly THEME_LIGHT: number = Settings.THEME_LIGHT;
  readonly THEME_DARK: number = Settings.THEME_DARK;
  readonly THEME_BLACK: number = Settings.THEME_BLACK;

  getTheme(): number {
    return Settings.getTheme();
  }

  putTheme(theme: number): void {
    Settings.putTheme(theme);
  }

  isThemeAutoSwitchAvailable(): boolean {
    return Settings.isThemeAutoSwitchAvailable();
  }

  getAppLanguage(): string | null {
    return Settings.getAppLanguage();
  }

  getEnabledSecurity(): boolean {
    return Settings.getEnabledSecurity();
  }
}

class SettingsLegacyCookieAdapter implements LegacyCookieStoreLike {
  getString(key: string): string {
    return Settings.getString(key, '');
  }
}

class SystemPasteboardAdapter implements ClipboardLike {
  getText(): string {
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = board.getDataSync();
      const text: string = data.getPrimaryText();
      return text !== undefined && text !== null ? text : '';
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'SystemPasteboard read skipped: %{public}s', msg);
      return '';
    }
  }
}

const gDetailCache: Map<string, GalleryDetail> = new Map<string, GalleryDetail>();

function rememberGalleryDetail(url: string, detail: GalleryDetail): void {
  if (gDetailCache.size >= 64) {
    const firstKey: IteratorResult<string> = gDetailCache.keys().next();
    if (!firstKey.done && firstKey.value !== undefined) {
      gDetailCache.delete(firstKey.value);
    }
  }
  gDetailCache.set(url, detail);
  if (detail.gid > 0 && detail.token.length > 0) {
    gDetailCache.set(EhUrl.getGalleryDetailUrl(detail.gid, detail.token, 0, false), detail);
  }
}

class EhEngineDetailClient implements DetailClientLike {
  private readonly caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  async getGalleryDetail(url: string): Promise<GalleryDetail | null> {
    const detail: GalleryDetail | null = await EhEngine.getGalleryDetail(null, this.caller, url);
    if (detail !== null) {
      rememberGalleryDetail(url, detail);
      EhDB.putHistoryInfo(detail).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'putHistoryInfo skipped: %{public}s', e.message);
      });
    }
    return detail;
  }
}

class RealDetailActionClient implements DetailActionClientLike {
  private readonly caller: HttpCaller;
  private readonly downloadManager: DownloadManager;

  constructor(caller: HttpCaller, downloadManager: DownloadManager) {
    this.caller = caller;
    this.downloadManager = downloadManager;
  }

  async addToFavorite(galleryInfo: GalleryInfo, slot: number, note: string): Promise<boolean> {
    try {
      if (slot === -2) {
        await EhDB.putLocalFavorite(galleryInfo);
        return true;
      }
      if (slot >= 0 && slot <= 9) {
        await EhEngine.addFavorites(
          null,
          this.caller,
          galleryInfo.gid,
          galleryInfo.token,
          slot,
          note.length > 0 ? note : null
        );
        return true;
      }
      return false;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'addToFavorite failed: %{public}s', msg);
      return false;
    }
  }

  async removeFromFavorite(galleryInfo: GalleryInfo): Promise<boolean> {
    try {
      await EhDB.removeLocalFavorites(galleryInfo.gid);
      if (galleryInfo.favoriteSlot >= 0) {
        try {
          await EhEngine.addFavorites(null, this.caller, galleryInfo.gid, galleryInfo.token, -1, null);
        } catch (remoteErr) {
          const rMsg: string = remoteErr instanceof Error ? remoteErr.message : String(remoteErr);
          hilog.warn(DOMAIN, TAG, 'remote removeFromFavorite failed: %{public}s', rMsg);
        }
      }
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'removeFromFavorite failed: %{public}s', msg);
      return false;
    }
  }

  async rateGallery(detail: GalleryDetail, rating: number): Promise<GalleryRateOutcome | null> {
    if (detail.apiUid <= 0 || detail.apiKey === null || detail.apiKey.length === 0) {
      hilog.warn(DOMAIN, TAG, 'rateGallery skipped: apiUid=%{public}d missing apiKey', detail.apiUid);
      return null;
    }
    try {
      const res: RateGalleryResult = await EhEngine.rateGallery(
        null,
        this.caller,
        detail.apiUid,
        detail.apiKey,
        detail.gid,
        detail.token,
        rating
      );
      const outcome: GalleryRateOutcome = new GalleryRateOutcome();
      outcome.rating = res.rating;
      outcome.ratingCount = res.ratingCount;
      outcome.ratingCls = res.ratingCls;
      return outcome;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'rateGallery failed: %{public}s', msg);
      return null;
    }
  }

  async downloadGallery(galleryInfo: GalleryInfo): Promise<boolean> {
    try {
      await this.downloadManager.startDownload(galleryInfo, null);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'downloadGallery failed: %{public}s', msg);
      return false;
    }
  }

  async isDownloaded(gid: number): Promise<boolean> {
    return this.downloadManager.containDownloadInfo(gid);
  }

  async isLocalFavorited(gid: number): Promise<boolean> {
    try {
      return await EhDB.containLocalFavorites(gid);
    } catch (_e) {
      return false;
    }
  }
}

class RealCommentClient implements CommentClientLike {
  private readonly caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  private withShowAll(apiUrl: string, showAll: boolean): string {
    if (!showAll || apiUrl.indexOf('hc=1') >= 0) {
      return apiUrl;
    }
    const sep: string = apiUrl.indexOf('?') >= 0 ? '&' : '?';
    return `${apiUrl}${sep}hc=1`;
  }

  async getGalleryCommentList(apiUrl: string, showAll: boolean): Promise<GalleryCommentList | null> {
    try {
      const url: string = this.withShowAll(apiUrl, showAll);
      const detail: GalleryDetail | null = await EhEngine.getGalleryDetail(null, this.caller, url);
      if (detail !== null) {
        rememberGalleryDetail(apiUrl, detail);
        return detail.comments;
      }
      return null;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'getGalleryCommentList failed: %{public}s', msg);
      return null;
    }
  }

  async postComment(apiUrl: string, content: string, replyToId: number): Promise<boolean> {
    try {
      const editId: string | null = replyToId > 0 ? String(replyToId) : null;
      const updated: GalleryCommentList = await EhEngine.commentGallery(null, this.caller, apiUrl, content, editId);
      const cached: GalleryDetail | undefined = gDetailCache.get(apiUrl);
      if (cached !== undefined) {
        cached.comments = updated;
      }
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'postComment failed: %{public}s', msg);
      return false;
    }
  }

  async voteComment(apiUrl: string, commentId: number, up: boolean): Promise<number> {
    try {
      let detail: GalleryDetail | undefined = gDetailCache.get(apiUrl);
      if (detail === undefined) {
        const fetched: GalleryDetail | null = await EhEngine.getGalleryDetail(null, this.caller, apiUrl);
        if (fetched !== null) {
          rememberGalleryDetail(apiUrl, fetched);
          detail = fetched;
        }
      }
      if (detail === undefined || detail.apiUid <= 0 || detail.apiKey === null) {
        return -1;
      }
      const res: VoteCommentResult = await EhEngine.voteComment(
        null,
        this.caller,
        detail.apiUid,
        detail.apiKey,
        detail.gid,
        detail.token,
        commentId,
        up ? 1 : -1
      );
      return res.score;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'voteComment failed: %{public}s', msg);
      return -1;
    }
  }
}

class ShellSceneRef {
  scene: BaseScene | null = null;
}

function resolveAppStringKey(key: string): string {
  const clean: string = key.startsWith('app.string.') ? key.substring('app.string.'.length) : key;
  const resolved: string = GetText.getString(clean);
  return resolved.length > 0 ? resolved : clean;
}

class WiredHistorySceneShell extends HistorySceneShell {
  // BaseScene already exposes startScene / finish / showTip via StageHost & SceneHost
}

class RealHistorySceneHost implements HistorySceneHost {
  private readonly ref: ShellSceneRef;
  private readonly downloadManager: DownloadManager;

  constructor(ref: ShellSceneRef, downloadManager: DownloadManager) {
    this.ref = ref;
    this.downloadManager = downloadManager;
  }

  loadHistory(): Promise<HistoryInfo[]> {
    return EhDB.getHistoryLazyList();
  }

  clearHistory(): Promise<void> {
    return EhDB.clearHistoryInfo();
  }

  deleteHistory(info: HistoryInfo): Promise<void> {
    return EhDB.deleteHistoryInfo(info);
  }

  startScene(announcer: Announcer): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.startScene(announcer);
    }
  }

  showTip(messageKey: string, isLong: boolean): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.showTip(resolveAppStringKey(messageKey), isLong ? 1 : 0);
    }
  }

  onBackPressed(): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.finish();
    }
  }

  startDownload(info: GalleryInfo): void {
    this.downloadManager.startDownload(info, null).then((): void => {
      this.showTip('app.string.added_to_download_list', false);
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'History startDownload failed: %{public}s', e.message);
    });
  }

  addToFavorites(info: GalleryInfo, onSuccess: () => void, onFailure: (e: Error) => void): void {
    EhDB.putLocalFavorite(info).then((): void => {
      onSuccess();
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'History addToFavorites failed: %{public}s', e.message);
      onFailure(e);
    });
  }

  thumbCacheKey(gid: number): string {
    return EhCacheKeyFactory.getThumbKey(gid);
  }
}

class WiredTopListSceneShell extends EhTopListSceneShell {
}

class RealTopListApi implements TopListApi {
  private readonly caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  async fetchDetail(url: string): Promise<EhTopListDetail | null> {
    const targetUrl: string = url === TOP_LIST_URL ? EhUrl.getTopListUrl() : url;
    return await EhEngine.getTopList(null, this.caller, targetUrl);
  }

  cancel(): void {
    // One-shot HttpCaller request does not retain cancellable handle
  }
}

class RealTopListSceneHost implements TopListSceneHost {
  private readonly ref: ShellSceneRef;

  constructor(ref: ShellSceneRef) {
    this.ref = ref;
  }

  getStackIndex(): number {
    return 1;
  }

  now(): number {
    return Date.now();
  }

  showTip(key: string): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.showTip(resolveAppStringKey(key), 0);
    }
  }

  finish(): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.finish();
    }
  }

  isThisScene(sceneTag: string): boolean {
    return sceneTag === 'EhTopListScene';
  }

  startDetail(gid: number, pToken: string): void {
    const s: BaseScene | null = this.ref.scene;
    if (s === null || gid <= 0) {
      return;
    }
    const args: SceneArgs = new Map<string, Object>();
    args.set('gid', gid);
    if (/^[0-9a-f]{10}$/i.test(pToken)) {
      args.set('api_url', EhUrl.getGalleryDetailUrl(gid, pToken, 0, false));
    }
    s.startScene(new Announcer('GalleryDetailScene').setArgs(args));
  }

  startList(builder: ListUrlBuilderSpec): void {
    const s: BaseScene | null = this.ref.scene;
    if (s === null) {
      return;
    }
    const ub: ListUrlBuilder = new ListUrlBuilder();
    if (builder.mode === MODE_UPLOADER) {
      ub.setMode(ListUrlBuilder.MODE_UPLOADER);
      ub.setKeyword(builder.keyword);
    } else if (builder.keyword.length > 0) {
      ub.setMode(ListUrlBuilder.MODE_NORMAL);
      ub.setKeyword(builder.keyword);
    }
    const listUrl: string = builder.follow.length > 0 && builder.follow.startsWith('http')
      ? builder.follow
      : ub.build();
    const args: SceneArgs = new Map<string, Object>();
    args.set(GalleryListAction.KEY_ACTION, GalleryListAction.LIST_URL_BUILDER);
    args.set(GalleryListAction.KEY_LIST_URL_BUILDER, listUrl);
    s.startScene(new Announcer('GalleryListScene').setArgs(args));
  }

  resolveAnnouncerFromUrl(href: string): boolean {
    const s: BaseScene | null = this.ref.scene;
    if (s === null) {
      return false;
    }
    const target: OpenTarget | null = EhUrlOpener.parseUrl(href);
    if (target === null) {
      return false;
    }
    if (target.kind === 'detail' && target.gid > 0 && target.token.length > 0) {
      const args: SceneArgs = new Map<string, Object>();
      args.set('gid', target.gid);
      args.set('api_url', EhUrl.getGalleryDetailUrl(target.gid, target.token, 0, false));
      s.startScene(new Announcer('GalleryDetailScene').setArgs(args));
      return true;
    }
    if (target.kind === 'list' && target.listUrlBuilder !== null) {
      const args: SceneArgs = new Map<string, Object>();
      args.set(GalleryListAction.KEY_ACTION, GalleryListAction.LIST_URL_BUILDER);
      args.set(GalleryListAction.KEY_LIST_URL_BUILDER, target.listUrlBuilder.build());
      s.startScene(new Announcer('GalleryListScene').setArgs(args));
      return true;
    }
    return false;
  }
}

class WiredGalleryInfoSceneShell extends GalleryInfoSceneShell {
  onNewArguments(args: SceneArgs): void {
    this.setArguments(args);
    super.onNewArguments(args);
    const rawDetail: Object | undefined = args.get(KEY_GALLERY_DETAIL);
    const detail: GalleryDetail | null = rawDetail !== undefined && rawDetail !== null && rawDetail instanceof GalleryDetail
      ? rawDetail as GalleryDetail
      : null;
    this.getLogic().onInit(detail);
  }
}

class RealGalleryInfoSceneHost implements GalleryInfoSceneHost {
  private readonly ref: ShellSceneRef;
  private readonly context: common.Context;

  constructor(ref: ShellSceneRef, context: common.Context) {
    this.ref = ref;
    this.context = context;
  }

  copyToClipboard(text: string): void {
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      board.setDataSync(data);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'copyToClipboard failed: %{public}s', msg);
    }
  }

  rememberClipboardHash(hash: number): void {
    Settings.putClipboardTextHashCode(hash);
  }

  openUrlExternally(url: string): void {
    if (url.length === 0) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    (this.context as common.UIAbilityContext).startAbility(want).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'openUrlExternally failed: %{public}s', e.message);
    });
  }

  showTip(key: string): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.showTip(resolveAppStringKey(key), 0);
    }
  }

  onBackPressed(): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.finish();
    }
  }

  resolveString(key: string): string {
    return resolveAppStringKey(key);
  }
}

class WiredGalleryPreviewsSceneShell extends GalleryPreviewsSceneShell {
  onNewArguments(args: SceneArgs): void {
    this.setArguments(args);
    super.onNewArguments(args);
    this.getLogic().onInit(args);
  }
}

class WiredDownloadsSceneShell extends DownloadsSceneShell {
  constructor(manager: DownloadManager) {
    super(new DownloadManagerSceneAdapter(manager));
  }

  onNewArguments(args: SceneArgs): void {
    this.setArguments(args);
    super.onNewArguments(args);
    this.getLogic().onNewArguments(args);
  }
}

class RealLabelsSceneHost implements LabelsSceneHost {
  private readonly ref: ShellSceneRef;
  private readonly manager: DownloadManager;

  constructor(ref: ShellSceneRef, manager: DownloadManager) {
    this.ref = ref;
    this.manager = manager;
  }

  getLabelList(): DownloadLabel[] {
    return this.manager.getLabelList();
  }

  containLabel(text: string): boolean {
    return this.manager.containLabel(text);
  }

  addLabel(text: string): Promise<void> {
    return this.manager.addLabel(text);
  }

  renameLabel(from: string, to: string): Promise<void> {
    return this.manager.renameLabel(from, to);
  }

  deleteLabel(label: string): Promise<void> {
    return this.manager.deleteLabel(label);
  }

  moveLabel(from: number, to: number): Promise<void> {
    return this.manager.moveLabel(from, to);
  }

  getDefaultLabelName(): string {
    return resolveAppStringKey('default_download_label_name');
  }

  formatDeleteLabelMessage(label: string): string {
    const tmpl: string = resolveAppStringKey('delete_label_message');
    if (tmpl.indexOf('%1$s') >= 0) {
      return tmpl.replace('%1$s', label);
    }
    if (tmpl.indexOf('%s') >= 0) {
      return tmpl.replace('%s', label);
    }
    return tmpl + ': ' + label;
  }

  onBackPressed(): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.finish();
    }
  }
}

class RealSubscriptionsSceneHost implements SubscriptionsSceneHost {
  private readonly ref: ShellSceneRef;

  constructor(ref: ShellSceneRef) {
    this.ref = ref;
  }

  getUserTagList(): UserTagList | null {
    const cached: Object | null = EhApplication.getUserTagList();
    if (cached !== null && cached instanceof UserTagList) {
      return cached as UserTagList;
    }
    return null;
  }

  saveUserTagList(result: UserTagList | null): void {
    EhApplication.saveUserTagList(result);
  }

  setProgressVisible(_visible: boolean): void {
  }

  setRecyclerViewVisible(_visible: boolean): void {
  }

  showTipRaw(text: string): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.showTip(text, 0);
    }
  }

  getShowTagTranslations(): boolean {
    return Settings.getShowTagTranslations();
  }

  getEhTagDatabase(): Object | null {
    return null;
  }

  onBackPressed(): void {
    const s: BaseScene | null = this.ref.scene;
    if (s !== null) {
      s.finish();
    }
  }
}

class RealSubscriptionsApi implements SubscriptionsApi {
  private readonly caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  async deleteWatched(url: string, tag: UserTag): Promise<UserTagList | null> {
    const targetUrl: string = url === MY_TAG_URL ? EhUrl.getMyTag() : url;
    return await EhEngine.deleteWatchedTag(null, this.caller, targetUrl, tag);
  }
}

class DownloadManagerSceneAdapter implements DownloadManagerLike {
  private readonly manager: DownloadManager;

  constructor(manager: DownloadManager) {
    this.manager = manager;
  }

  getDownloadInfoList(): DownloadInfo[] {
    return this.manager.getDownloadInfoList();
  }

  getDefaultDownloadInfoList(): DownloadInfo[] {
    return this.manager.getDefaultDownloadInfoList();
  }

  getLabelDownloadInfoList(label: string): DownloadInfo[] | null {
    return this.manager.getLabelDownloadInfoList(label);
  }
}

class EhEngineGalleryDetailFetcher implements GalleryDetailFetcher {
  private readonly caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  async getGalleryDetail(info: GalleryInfo): Promise<GalleryDetail | null> {
    const url: string = EhUrl.getGalleryDetailUrlSimple(info.gid, info.token);
    const cached: GalleryDetail | undefined = gDetailCache.get(url);
    if (cached !== undefined) {
      return cached;
    }
    const fullUrl: string = EhUrl.getGalleryDetailUrl(info.gid, info.token, 0, false);
    const fullCached: GalleryDetail | undefined = gDetailCache.get(fullUrl);
    if (fullCached !== undefined) {
      return fullCached;
    }
    let gidCached: GalleryDetail | null = null;
    gDetailCache.forEach((value: GalleryDetail): void => {
      if (gidCached === null && value.gid === info.gid) {
        gidCached = value;
      }
    });
    if (gidCached !== null) {
      return gidCached;
    }
    const fetched: GalleryDetail | null = await EhEngine.getGalleryDetail(null, this.caller, url);
    if (fetched !== null) {
      rememberGalleryDetail(url, fetched);
    }
    return fetched;
  }
}

class EhEnginePreviewSetFetcher implements PreviewSetFetcher {
  private readonly caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  async getPreviewSet(url: string): Promise<PreviewSet | null> {
    const res = await EhEngine.getPreviewSet(null, this.caller, url);
    return res.previewSet;
  }
}

class RealDownloadEnqueuer implements DownloadEnqueueLike {
  private readonly manager: DownloadManager;

  constructor(manager: DownloadManager) {
    this.manager = manager;
  }

  async enqueue(info: GalleryInfo): Promise<boolean> {
    try {
      await this.manager.startDownload(info, null);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'RealDownloadEnqueuer.enqueue failed: gid=%{public}d err=%{public}s', info.gid, msg);
      return false;
    }
  }
}

class RealLocalFavoritesRepo implements FavoritesRepositoryLike {
  async containLocalFavorites(gid: number): Promise<boolean> {
    return EhDB.containLocalFavorites(gid);
  }

  async putLocalFavorite(info: GalleryInfo): Promise<boolean> {
    await EhDB.putLocalFavorite(info);
    return true;
  }
}

