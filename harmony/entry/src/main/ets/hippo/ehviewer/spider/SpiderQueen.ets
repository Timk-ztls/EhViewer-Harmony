/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/spider/SpiderQueen.java（1681 行）
 *
 * ── 分批落地（lead 指定，避免"骨架 + 大量 TODO"）──────────────────────────
 * **本文件 = 第 1 批**：常量、queen 生命周期（引用计数 + queen 表）、reading progress 重置、
 * startPage 查询。这些都是**完全可运行**的代码，不依赖 net-parse 的 `EhUrl`/`EhEngine`。
 *
 * 后续批次（不在本文件里假装实现）：
 *   第 2 批：PageLoader / 读取队列（mRequestPageQueue / decode 线程 / pToken 队列）
 *   第 3 批：下载循环（等 net-parse 的 `EhEngine`/`EhClient`，按最小接口注入）
 *   第 4 批：其余（save/恢复、备份、509 处理、listener 通知细节）
 *
 * ── 依赖与注入点 ─────────────────────────────────────────────────────────
 * 已完成（直接调用）：`Settings` / `ExceptionUtils` / `Analytics` / `GetText` / `SpiderDen` / `SpiderInfo`
 * 未完成（注入点，未注入时**抛带归属的 TODO**，绝不静默降级）：
 *   - `SpiderInfoCacheProvider` ← `EhApplication.getSpiderInfoCache()`（返回 SimpleDiskCache；
 *     注意这是 **spider_info 缓存目录**，不是下载目录里的 `.ehviewer` 文件，两者别混）
 *
 * ── 上游语义要点（容易做错的）────────────────────────────────────────────
 * 1) `obtainSpiderQueen` 必须 **@UiThread**：queen 表 `sQueenMap` 不是线程安全的
 *    （上游用 `SparseJLArray` + 主线程约束）。ArkTS 侧没有 `OSUtils.checkMainLoop()`，
 *    改为文档约束 + 可以在测试里注入主线程检查器（见 `setMainThreadChecker`）。
 * 2) `releaseSpiderQueen` 在引用计数归零时**才** stop + 从表里移除；
 *    只要还有任一模式（READ/DOWNLOAD）的引用，queen 必须活着。
 * 3) `SPIDER_INFO_FILENAME = ".ehviewer"`（下载目录里的进度文件），
 *    `"spider_info"` 是**缓存目录名**（EhApplication.java:595）。两者不同，见 SpiderInfo.ets 的说明。
 */

import { GalleryInfo } from '../client/data/GalleryInfo';
import { GalleryDetail } from '../client/data/GalleryDetail';
import { SpiderDen, MODE_READ, MODE_DOWNLOAD, SUPPORT_IMAGE_EXTENSIONS } from './SpiderDen';
import { SpiderInfo, SpiderInfoCacheProvider, SPIDER_INFO_FILENAME, SPIDER_INFO_CACHE_DIRNAME } from './SpiderInfo';
import { SimpleDiskCache, CacheOutputStreamPipe } from '../../beerbelly/SimpleDiskCache';
import { InputStreamPipe } from '../../streampipe/InputStreamPipe';
import { OutputStreamPipe, ByteSink } from '../../streampipe/OutputStreamPipe';
import { PageImageDownloader, DownloadResult } from '../../streampipe/PageImageDownloader';
import { InputStream } from '../../unifile/Contracts';
import fs from '@ohos.file.fs';
import { Image } from '../../lib/image/Image';
import { OutputStream } from '../../unifile/Contracts';
import { UniFile } from '../../unifile/UniFile';
import { EhUrl } from '../client/EhUrl';
import { PreviewSet } from '../client/data/PreviewSet';
import { GalleryPageParserResult } from '../client/parser/GalleryPageParser';
import { GalleryPageApiParserResult } from '../client/parser/GalleryPageApiParser';
import { GalleryProvider } from '../../lib/glgallery/GalleryProvider';
import { Utils } from '../../unifile/Utils';
import { GetText } from '../GetText';
import { Settings } from '../Settings';
import { MathUtils } from '../../lib/yorozuya/MathUtils';

const TAG: string = 'SpiderQueen';

/**
 * `request()` / `forceRequest()` 的三态返回值（C-18：**返回类型归生产方**，消费方 import）。
 * - `number` → 该页下载进度（0..1）
 * - `string` → 失败原因
 * - `null`   → 已入队等回调，或 queen 未启动
 */
export type PageRequestResult = number | string | null;

/** 对位 Settings 的 `preload_image` 默认值（上游 DEFAULT_PRELOAD_IMAGE = 5）。 */
export const DEFAULT_PRELOAD_NUMBER: number = 5;

/** 对位 `SpiderQueen.STATE_NONE`。 */
export const STATE_NONE: number = 0;
/** 对位 `SpiderQueen.STATE_DOWNLOADING`。 */
export const STATE_DOWNLOADING: number = 1;
/** 对位 `SpiderQueen.STATE_FINISHED`。 */
export const STATE_FINISHED: number = 2;
/** 对位 `SpiderQueen.STATE_FAILED`。 */
export const STATE_FAILED: number = 3;
/** 对位 `SpiderQueen.DECODE_THREAD_NUM`（上游固定 2 个解码线程）。 */
export const DECODE_THREAD_NUM: number = 2;

/** 对位 `SpiderQueen.SPIDER_INFO_FILENAME`（下载目录里的进度文件，`.ehviewer`）。 */
export { SPIDER_INFO_FILENAME };

/** 对位 `SpiderQueen.SPIDER_INFO_BACKUP_DIR`。 */
export const SPIDER_INFO_BACKUP_DIR: string = 'backupDir';

export { SpiderInfoCacheProvider };

/**
 * 可选详情页加载钩子：用于 `start()` 本地/缓存未命中时获取 `GalleryDetail` 以构造 `SpiderInfo`。
 * 不污染 `EhEngineLike`，保持既有实现（含 AppWiring / 测试）零返工。
 */
export interface GalleryDetailFetcher {
  getGalleryDetail(info: GalleryInfo): Promise<GalleryDetail | null>;
}

export interface PreviewSetFetcher {
  getPreviewSet(url: string): Promise<PreviewSet | null>;
}

/**
 * `EhGalleryProvider` 使用的 `SpiderQueen` 最小接口（原定义于 `EhGalleryProvider.ets`，迁至此处由 `SpiderQueen` 直接实现并消除反向依赖）。
 */
export interface SpiderQueenLike {
  addOnSpiderListener(listener: OnSpiderListener): void;

  removeOnSpiderListener(listener: OnSpiderListener): void;

  getStartPage(): number;

  putStartPage(page: number): void;

  size(): number;

  getError(): string;

  request(index: number): PageRequestResult;

  forceRequest(index: number): PageRequestResult;

  cancelRequest(index: number): void;

  saveToFile(index: number, file: UniFile): boolean;

  saveToDir(index: number, dir: UniFile, filename: string): UniFile | null;
}

class NextIndexResult {
  readonly index: number;
  readonly force: boolean;

  constructor(index: number, force: boolean) {
    this.index = index;
    this.force = force;
  }
}

class Image509Error extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'Image509Error';
  }
}

class OriginImageQuotaError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OriginImageQuotaError';
  }
}

/**
 * 下载 worker 需要的 `EhEngine` 子集（契约先行；参数类型归消费方，C-18）。
 *
 * 上游两处调用（EhEngine.java:1203 / :1232）多带 `task` 与 `okHttpClient`：
 * - `task` 是 EhClient 的取消令牌 → 这里用 `Object | null` 占位（本模块不取消单次请求）
 * - `okHttpClient` 在 ArkTS 是模块级单例 → 不传
 * 这两个取舍由 lead 裁决；net-parse 的实现签名保持不动（他要改会波及 851 条基线断言）。
 */
export interface EhEngineLike {
  getGalleryPage(task: Object | null, caller: Object | null, url: string,
    gid: number, token: string): Promise<GalleryPageParserResult>;

  getGalleryPageApi(task: Object | null, caller: Object | null, gid: number, index: number,
    pToken: string, showKey: string, previousPToken: string | null): Promise<GalleryPageApiParserResult>;
}

/**
 * 图片字节下载器（契约先行）。core-runtime 的 image HTTP client 就绪后注入。
 *
 * 为什么单独抽：`EhEngine` 只负责「解析页面拿到 imageUrl」，真正按 URL 拉字节用的是
 * 上游的 `EhApplication.getImageOkHttpClient()`。ArkTS 侧那是另一套 HTTP 栈，
 * 塞进 `EhEngineLike` 会让接口面膨胀且与 net-parse 无关。
 *
 * **未注入时**：该页显式失败并记错误（不静默、不写假下载），且**泵必须继续跑**。
 */
// PageImageDownloader 已迁到 streampipe/（与 ByteSink 同层），避免 net-parse 反向依赖本模块。
// 这里再导出一次，保持既有 `import { PageImageDownloader } from '.../SpiderQueen'` 不变。
export { PageImageDownloader } from '../../streampipe/PageImageDownloader';

/**
 * 对位上游 `SpiderQueen.OnSpiderListener`（**8 个方法，逐字对齐**）。
 *
 * 注意：我第一版凭印象写过一套 `onPagePercent`/`onPageDownloadFinish` —— 上游**没有**这两个，
 * 真实的是 `onPageDownload(index, contentLength, receivedSize, bytesRead)` 与
 * `onPageSuccess(index, finished, downloaded, total)`。这类"看起来合理的 API"最危险：
 * 能编译、能跑，只是下游实现永远收不到回调。
 */
export interface OnSpiderListener {
  onGetPages(pages: number): void;

  onGet509(index: number): void;

  /** @param contentLength 未知时为 -1（上游同）。 */
  onPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void;

  onPageSuccess(index: number, finished: number, downloaded: number, total: number): void;

  onPageFailure(index: number, error: string, finished: number, downloaded: number, total: number): void;

  /** 所有 worker 结束（上游注释：All workers end）。 */
  onFinish(finished: number, downloaded: number, total: number): void;

  onGetImageSuccess(index: number, image: Image): void;

  onGetImageFailure(index: number, error: string): void;
}

export class SpiderQueen implements SpiderQueenLike {
  /**
   * 对位上游 `SpiderQueen.MODE_READ` / `MODE_DOWNLOAD` 的**类静态字段**。
   *
   * 上游是 `public static final int MODE_READ = 0;`，下游写法是 `SpiderQueen.MODE_DOWNLOAD`
   * （download-sync 的 `DownloadManager:512` 就是这么用的）。模块级 `export const` 不能这样访问，
   * 所以两处都保留：模块级导出给 `import { MODE_DOWNLOAD }`，类静态字段给 `SpiderQueen.MODE_DOWNLOAD`。
   */
  static readonly MODE_READ: number = MODE_READ;
  static readonly MODE_DOWNLOAD: number = MODE_DOWNLOAD;
  static readonly STATE_NONE: number = STATE_NONE;
  static readonly STATE_DOWNLOADING: number = STATE_DOWNLOADING;
  static readonly STATE_FINISHED: number = STATE_FINISHED;
  static readonly STATE_FAILED: number = STATE_FAILED;
  // ---------------------------------------------------------------- 注入点

  private static cacheProvider: SpiderInfoCacheProvider | null = null;
  private static mainThreadChecker: (() => boolean) | null = null;
  private static detailFetcher: GalleryDetailFetcher | null = null;
  private static previewSetFetcher: PreviewSetFetcher | null = null;

  /** core-runtime 的 `EhApplication.getSpiderInfoCache()` 落地后注入（同步传给 SpiderInfo）。 */
  static setSpiderInfoCacheProvider(provider: SpiderInfoCacheProvider | null): void {
    SpiderQueen.cacheProvider = provider;
    SpiderInfo.setCacheProvider(provider);
  }

  /** 可选：注入详情加载器供 `start()` 本地未命中时拉取 `GalleryDetail` 构建 `SpiderInfo`。 */
  static setGalleryDetailFetcher(fetcher: GalleryDetailFetcher | null): void {
    SpiderQueen.detailFetcher = fetcher;
  }

  static setPreviewSetFetcher(fetcher: PreviewSetFetcher | null): void {
    SpiderQueen.previewSetFetcher = fetcher;
  }

  /**
   * 主线程检查器（对位上游 `OSUtils.checkMainLoop()`）。
   * ArkTS 没有可靠的"是否主线程"查询，故做成注入：生产由 core-runtime 注入，
   * 测试注入恒真/恒假来验证"UI 线程约束"这条上游语义确实被执行。
   */
  static setMainThreadChecker(checker: (() => boolean) | null): void {
    SpiderQueen.mainThreadChecker = checker;
  }

  private static checkMainThread(): void {
    const checker: (() => boolean) | null = SpiderQueen.mainThreadChecker;
    if (checker !== null && !checker()) {
      throw new Error(`[${TAG}] obtain/releaseSpiderQueen 必须在主线程调用（上游 @UiThread 约束）`);
    }
  }

  // ---------------------------------------------------------------- queen 表（超引用计数）

  /** 对位 `SparseJLArray<SpiderQueen> sQueenMap`：gid → queen。 */
  private static readonly sQueenMap: Map<number, SpiderQueen> = new Map<number, SpiderQueen>();

  /**
   * 对位 `obtainSpiderQueen(context, galleryInfo, mode)`。
   *
   * 已有 queen 时**只加引用并切模式**（不重建、不 restart）；没有才新建。
   * 新建后上游会 `queen.start()` —— start() 属第 2/3 批，本批 `start()` 只做"标记已启动 +
   * 记录模式"，队列与工作线程留待后续批次（见文件头）。
   */
  static obtainSpiderQueen(galleryInfo: GalleryInfo, mode: number): SpiderQueen {
    SpiderQueen.checkMainThread();
    let queen: SpiderQueen | undefined = SpiderQueen.sQueenMap.get(galleryInfo.gid);
    if (queen === undefined) {
      queen = new SpiderQueen(galleryInfo);
      SpiderQueen.sQueenMap.set(galleryInfo.gid, queen);
      queen.setMode(mode);
      queen.start();
    } else {
      queen.setMode(mode);
    }
    return queen;
  }

  /**
   * 对位 `releaseSpiderQueen(queen, mode)`：
   * 清掉该模式的引用；**只有 READ 与 DOWNLOAD 引用同时归零**才 stop 并从表里移除。
   */
  static releaseSpiderQueen(queen: SpiderQueen, mode: number): void {
    SpiderQueen.checkMainThread();
    queen.clearMode(mode);
    if (queen.mReadReference === 0 && queen.mDownloadReference === 0) {
      queen.stop();
      SpiderQueen.sQueenMap.delete(queen.getGalleryInfo().gid);
    }
  }

  /** 当前活跃 queen 数量（上游无此 API，仅供测试与内存排查）。 */
  static activeQueenCount(): number {
    return SpiderQueen.sQueenMap.size;
  }

  /** 测试用：清空 queen 表（上游无此 API；生产不应调用）。 */
  /**
   * 该 gid 是否已有打开的 queen（对位上游"在 sQueenMap 里能查到"）。
   *
   * 为什么需要公开：`resetReadingProgress(gid)` 对不存在的 queen 是**静默 no-op**
   * （上游如此），调用方无法区分"没有可重置的"与"重置了 N 个"。
   * 菜单「重置阅读进度」需要后者来给用户/日志一个有意义的结论。
   */
  static hasQueen(gid: number): boolean {
    return SpiderQueen.sQueenMap.has(gid);
  }
  static resetForTest(): void {
    SpiderQueen.sQueenMap.clear();
    SpiderQueen.previewSetFetcher = null;
  }

  /** 对位 `contain(int[] array, int value)`：上游自己实现的数组包含判断。 */
  static contain(array: number[], value: number): boolean {
    for (const v of array) {
      if (v === value) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- 阅读进度

  /**
   * 对位 `resetReadingProgress(gid)`：把**内存里**那个 queen 的 startPage 归零。
   * 上游注释写得很明确：不改磁盘、不改缓存，只改内存对象（调用方在主线程）。
   * queen 不存在时直接返回（幂等）。
   */
  static resetReadingProgress(gid: number): void {
    const queen: SpiderQueen | undefined = SpiderQueen.sQueenMap.get(gid);
    if (queen === undefined) {
      return;
    }
    const info: SpiderInfo | null = queen.mSpiderInfo;
    if (info !== null) {
      info.startPage = 0;
    }
  }

  /**
   * 对位 `findStartPage(context, galleryInfo)`：从 **spider_info 缓存**读 startPage。
   * 上游这里只用缓存（不读下载目录），读不到就是 0。
   */
  static findStartPage(galleryInfo: GalleryInfo): number {
    const info: SpiderInfo | null = SpiderQueen.readSpiderInfoFromCache(galleryInfo.gid);
    return info !== null ? info.startPage : 0;
  }

  /** 对位 `readSpiderInfoFromCache(context, gid)`。 */
  private static readSpiderInfoFromCache(gid: number): SpiderInfo | null {
    const provider: SpiderInfoCacheProvider | null = SpiderQueen.cacheProvider;
    if (provider === null) {
      throw new Error(
        `[${TAG}] TODO(core-runtime): SpiderInfoCacheProvider 未注入` +
        '（需要 EhApplication.getSpiderInfoCache()，返回 SimpleDiskCache）');
    }
    const cache: SimpleDiskCache | null = provider.getSpiderInfoCache();
    if (cache === null) {
      return null;
    }
    const pipe: InputStreamPipe | null = cache.getInputStreamPipe(`${gid}`);
    if (pipe === null) {
      return null;
    }
    try {
      pipe.obtain();
      return SpiderInfo.readStreamInclude(new FsFileInputStream(pipe.open()), true);
    } catch (e) {
      Utils.throwIfFatal(e);
      return null;
    } finally {
      pipe.close();
      pipe.release();
    }
  }

  /** 对位 `isValidSpiderInfo(spiderInfo, galleryInfo)`：gid 与 token 都要一致。 */
  private static isValidSpiderInfo(spiderInfo: SpiderInfo | null, galleryInfo: GalleryInfo): boolean {
    return spiderInfo !== null && spiderInfo.gid === galleryInfo.gid &&
      spiderInfo.token === galleryInfo.token;
  }

  // ---------------------------------------------------------------- 实例

  private readonly mGalleryInfo: GalleryInfo;
  private readonly mSpiderDen: SpiderDen;
  private mSpiderInfo: SpiderInfo | null = null;
  private mReadReference: number = 0;
  private mDownloadReference: number = 0;
  private mMode: number = MODE_READ;
  private mStarted: boolean = false;
  private mState: number = STATE_NONE;
  private mError: string = '';
  /** 对位 List<OnSpiderListener> mSpiderListeners（上游用 synchronized 保护）。 */
  private readonly mSpiderListeners: OnSpiderListener[] = [];

  private constructor(galleryInfo: GalleryInfo) {
    this.mGalleryInfo = galleryInfo;
    this.mSpiderDen = new SpiderDen(galleryInfo);
    // 对位上游：mPreloadNumber = clamp(Settings.getPreloadImage(), 0, 100)；
    //           mWorkerMaxCount = clamp(Settings.getMultiThreadDownload(), 1, 10)。
    // 两个 getter 已由 core-runtime 交付（Settings.ets:546/558），直接读，不用默认值兜底。
    this.mPreloadNumber = MathUtils.clamp(Settings.getPreloadImage(), 0, 100);
    this.mWorkerMaxCount = MathUtils.clamp(Settings.getMultiThreadDownload(), 1, 10);
    Utils.logI(TAG, `SpiderQueen created for gid=${galleryInfo.gid}（preload=${this.mPreloadNumber} workerMax=${this.mWorkerMaxCount}）`);
  }

  getGalleryInfo(): GalleryInfo {
    return this.mGalleryInfo;
  }

  getSpiderDen(): SpiderDen {
    return this.mSpiderDen;
  }

  /** 对位 `getSpiderInfo()`（内存里那份；可能为 null）。 */
  getSpiderInfo(): SpiderInfo | null {
    return this.mSpiderInfo;
  }

  /** 由第 2/3 批的加载器回填（上游是 `mSpiderInfo.set(...)`）。 */
  setSpiderInfo(info: SpiderInfo | null): void {
    this.mSpiderInfo = info;
  }

  getState(): number {
    return this.mState;
  }

  setState(state: number): void {
    this.mState = state;
  }

  getReadReference(): number {
    return this.mReadReference;
  }

  getDownloadReference(): number {
    return this.mDownloadReference;
  }

  // ================================================================ 第 2 批：读取队列 / 页面状态 / pToken

  /**
   * `request()` / `forceRequest()` 的三态返回值（**类型归生产方**，C-18）。
   * - `number` → 该页下载进度（0..1）
   * - `string` → 失败原因
   * - `null`   → 已入队，等回调（或 queen 未启动）
   */
  // 类型定义在模块级（见文件末尾 `export type PageRequestResult`）

  /** 对位 `mPageStateArray`：每页的 STATE_*；`null` 表示还没拿到 pages（= size() 返回 STATE_WAIT）。 */
  private mPageStateArray: number[] | null = null;
  /** 对位 `mPageErrorMap`。 */
  private readonly mPageErrorMap: Map<number, string> = new Map<number, string>();
  /** 对位 `mPagePercentMap`。 */
  private readonly mPagePercentMap: Map<number, number> = new Map<number, number>();
  /** 对位 `mRequestPageQueue`。 */
  private readonly mRequestPageQueue: number[] = [];
  /** 对位 `mRequestPageQueue2`（预载邻居页）。 */
  private readonly mRequestPageQueue2: number[] = [];
  /** 对位 `mForceRequestPageQueue`。 */
  private readonly mForceRequestPageQueue: number[] = [];
  /** 对位 `mDecodeRequestQueue`。 */
  private readonly mDecodeRequestQueue: number[] = [];
  /** 对位 `mDecodeIndexArray`（DECODE_THREAD_NUM 个解码线程的当前页）。 */
  private readonly mDecodeIndexArray: number[] = [-1, -1];
  /** 对位 `mRequestPTokenQueue`。 */
  private readonly mRequestPTokenQueue: number[] = [];
  private readonly mPendingPreviewFetches: Map<number, Promise<void>> = new Map<number, Promise<void>>();
  /** 对位 `mDownloadedPages` / `mFinishedPages`。 */
  private mDownloadedPages: number = 0;
  private mFinishedPages: number = 0;
  /** 对位 `mPreloadNumber`（`Settings.getPreloadImage()`，clamp(0,100)）。 */
  private mPreloadNumber: number;
  /** 对位 mWorkerMaxCount（Settings.getMultiThreadDownload()，clamp(1,10)）。 */
  private mWorkerMaxCount: number = 3;

  /** 对位 `getPageState(index)`。 */
  getPageState(index: number): number {
    const states: number[] | null = this.mPageStateArray;
    if (states !== null && index >= 0 && index < states.length) {
      return states[index];
    }
    return STATE_NONE;
  }

  /**
   * 对位上游 `isStateDone(state)`（SpiderQueen.java:1103）：
   * `state == STATE_FINISHED || state == STATE_FAILED`。
   *
   * 为什么必须单独一个判据：`updatePageState` 的计数器维护依赖"是否**跨越**了 done 边界"，
   * 而不是"当前是不是 done" —— 同一页重复标 FINISHED 不能重复计数。
   */
  private static isStateDone(state: number): boolean {
    return state === STATE_FINISHED || state === STATE_FAILED;
  }

  /**
   * 对位 `updatePageState(index, state)`（上游 SpiderQueen.java:1109-1125）。
   *
   * 上游在这个方法里同时维护两个计数器，**按"跨越 done 边界"而不是"当前值"**：
   * ```
   * !isDone(old) && isDone(new) → mDownloadedPages++
   * isDone(old) && !isDone(new) → mDownloadedPages--
   * old !== FINISHED && new === FINISHED → mFinishedPages++
   * ```
   * 我们原来只写 `states[index] = state`，计数器靠下载成功路径 `++` —— 那会**重复计数**
   * （同一页重试成功两次就多算一页），且 `STATE_FAILED` 不计入 downloaded（上游计入）。
   */
  updatePageState(index: number, state: number): void {
    const states: number[] | null = this.mPageStateArray;
    if (states === null || index < 0 || index >= states.length) {
      return;
    }
    const oldState: number = states[index];
    states[index] = state;

    if (!SpiderQueen.isStateDone(oldState) && SpiderQueen.isStateDone(state)) {
      this.mDownloadedPages++;
    } else if (SpiderQueen.isStateDone(oldState) && !SpiderQueen.isStateDone(state)) {
      this.mDownloadedPages--;
    }
    if (oldState !== STATE_FINISHED && state === STATE_FINISHED) {
      this.mFinishedPages++;
    }
  }

  /** 对位上游 `getDownloadedPages()` 语义（已跨入 done 边界的页数）。 */
  getDownloadedPages(): number {
    return this.mDownloadedPages;
  }

  /** 对位上游 `mFinishedPages`（成功完成的页数，不含 FAILED）。 */
  getFinishedPages(): number {
    return this.mFinishedPages;
  }

  /** 预载页数（对位 `Settings.getPreloadImage()`；上游 clamp(0,100)，默认 5）。 */
  setPreloadNumber(value: number): void {
    this.mPreloadNumber = Math.min(Math.max(value, 0), 100);
  }

  getPreloadNumber(): number {
    return this.mPreloadNumber;
  }

  /**
   * 由 SpiderInfo 初始化每页状态：**已存在（缓存或下载目录）的页直接标 FINISHED**。
   *
   * 上游是在 queenThread 里读 SpiderInfo 后做的同样的事；本 port 把"读 SpiderInfo"交给调用方
   * （`SpiderInfo.getSpiderInfoByGalleryInfo` / `readHeaderFile`），这里只做状态投影，
   * 好处是可单测、且不依赖网络。
   */
  applySpiderInfo(info: SpiderInfo): void {
    this.mSpiderInfo = info;
    if (info.pTokenMap !== null && this.mPagePTokens.size === 0) {
      this.setPagePTokens(info.pTokenMap);
    }
    const states: number[] = [];
    for (let i = 0; i < info.pages; i++) {
      states.push(this.mSpiderDen.contain(i) ? STATE_FINISHED : STATE_NONE);
    }
    this.mPageStateArray = states;
    this.mFinishedPages = 0;
    for (const s of states) {
      if (s === STATE_FINISHED) {
        this.mFinishedPages++;
      }
    }
    this.mDownloadedPages = this.mFinishedPages;
    this.notifyGetPages(info.pages);
    this.tryToEnsureWorkers();
  }

  /** 设定某页下载进度（第 3 批 worker 回填；也是测试入口）。 */
  setPagePercent(index: number, percent: number | null): void {
    if (percent === null) {
      this.mPagePercentMap.delete(index);
    } else {
      this.mPagePercentMap.set(index, percent);
    }
  }

  /** 设定某页错误文案（第 3 批 worker 回填；也是测试入口）。 */
  setPageError(index: number, error: string | null): void {
    if (error === null) {
      this.mPageErrorMap.delete(index);
    } else {
      this.mPageErrorMap.set(index, error);
    }
  }
  /** 供测试/排查：当前页状态数组（null 表示未就绪）。 */
  getPageStateArray(): number[] | null {
    return this.mPageStateArray;
  }

  /** 对位 `size()`：queen 未启动 → STATE_ERROR；未拿到 pages → STATE_WAIT；否则页数。 */
  size(): number {
    if (!this.mStarted) {
      return GalleryProvider.STATE_ERROR;
    }
    const states: number[] | null = this.mPageStateArray;
    return states === null ? GalleryProvider.STATE_WAIT : states.length;
  }

  /** 对位 `getError()`：queen 未启动 → `"Error"`；已启动无错 → `""`。 */
  getError(): string {
    return !this.mStarted ? 'Error' : this.mError;
  }

  /** 对位 `getStartPage()`：优先内存 `mSpiderInfo`，缺失时从本地 `.ehviewer` 或缓存读取。 */
  getStartPage(): number {
    const info: SpiderInfo | null = this.readSpiderInfoFromLocal();
    if (info !== null) {
      if (this.mSpiderInfo === null) {
        this.mSpiderInfo = info;
      }
      return info.startPage;
    }
    return 0;
  }

  /** 对位 `putStartPage(page)`：更新内存与本地/缓存的阅读进度。 */
  putStartPage(page: number): void {
    let info: SpiderInfo | null = this.mSpiderInfo;
    if (info === null) {
      info = this.readSpiderInfoFromLocal();
      if (info !== null) {
        this.mSpiderInfo = info;
      }
    }
    if (info !== null) {
      info.startPage = page;
      this.writeSpiderInfoToLocal(info);
    }
  }

  private readSpiderInfoFromLocal(): SpiderInfo | null {
    if (this.mSpiderInfo !== null) {
      return this.mSpiderInfo;
    }
    let fromDownload: SpiderInfo | null = null;
    const downloadDir: UniFile | null = this.mSpiderDen.getDownloadDir();
    if (downloadDir !== null) {
      const file: UniFile | null = downloadDir.findFile(SPIDER_INFO_FILENAME);
      const read: SpiderInfo | null = SpiderInfo.readHeaderFile(file);
      if (SpiderQueen.isValidSpiderInfo(read, this.mGalleryInfo)) {
        fromDownload = read;
      }
    }
    let fromCache: SpiderInfo | null = SpiderQueen.cacheProvider !== null
      ? SpiderQueen.readSpiderInfoFromCache(this.mGalleryInfo.gid)
      : null;
    if (!SpiderQueen.isValidSpiderInfo(fromCache, this.mGalleryInfo)) {
      fromCache = null;
    }
    if (fromDownload === null) {
      return fromCache;
    }
    if (fromCache === null) {
      return fromDownload;
    }
    fromDownload.startPage = Math.max(fromDownload.startPage, fromCache.startPage);
    return fromDownload;
  }

  private writeSpiderInfoToLocal(info: SpiderInfo): void {
    const cache: SimpleDiskCache | null = SpiderQueen.cacheProvider !== null
      ? SpiderQueen.cacheProvider.getSpiderInfoCache()
      : null;
    info.writeNewSpiderInfoToLocal(this.mSpiderDen.getDownloadDir(), cache);
  }

  private async fetchPreviewPage(info: SpiderInfo, previewPage: number): Promise<void> {
    const fetcher: PreviewSetFetcher | null = SpiderQueen.previewSetFetcher;
    if (fetcher === null || info.gid < 0 || info.token === null || previewPage < 0) {
      return;
    }
    const token: string = info.token;
    const pending: Promise<void> | undefined = this.mPendingPreviewFetches.get(previewPage);
    if (pending !== undefined) {
      await pending;
      return;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        const url: string = EhUrl.getGalleryDetailUrl(info.gid, token, previewPage, false);
        const ps: PreviewSet | null = await fetcher.getPreviewSet(url);
        if (ps !== null && ps.size() > 0) {
          SpiderInfo.readPreviews(ps, previewPage, info);
          this.writeSpiderInfoToLocal(info);
        }
      } catch (_e) {
        // Keep pToken unknown if preview page fetch fails.
      } finally {
        this.mPendingPreviewFetches.delete(previewPage);
      }
    })();
    this.mPendingPreviewFetches.set(previewPage, task);
    await task;
  }

  private async ensurePagePToken(index: number): Promise<string | null> {
    let existing: string | null = this.getPagePToken(index);
    if (existing !== null) {
      return existing;
    }
    const info: SpiderInfo | null = this.mSpiderInfo;
    if (info === null || SpiderQueen.previewSetFetcher === null || info.gid < 0 || info.token === null) {
      return null;
    }
    let fetchedZero: boolean = false;
    if (info.previewPerPage <= 0) {
      fetchedZero = true;
      await this.fetchPreviewPage(info, 0);
      existing = this.getPagePToken(index);
      if (existing !== null) {
        return existing;
      }
    }
    if (info.previewPerPage > 0) {
      const targetPreviewPage: number = Math.trunc(index / info.previewPerPage);
      const validPage: boolean = targetPreviewPage >= 0 && (info.previewPages <= 0 || targetPreviewPage < info.previewPages);
      if (validPage && !(fetchedZero && targetPreviewPage === 0)) {
        await this.fetchPreviewPage(info, targetPreviewPage);
        existing = this.getPagePToken(index);
        if (existing !== null) {
          return existing;
        }
      }
    }
    return null;
  }

  /** 对位 `forceRequest(index)`（ignoreError=true, force=true, addNeighbor=false）。 */
  forceRequest(index: number): PageRequestResult {
    return this.requestInternal(index, true, true, false, true);
  }

  /** 原生 ArkUI 阅读器专用：强制重下，不触发 GL 解码泵。 */
  forceRequestFileOnly(index: number): PageRequestResult {
    return this.requestInternal(index, true, true, false, false);
  }

  /** 对位 `request(index)`（ignoreError=true, force=false, addNeighbor=true）。 */
  request(index: number): PageRequestResult {
    return this.requestInternal(index, true, false, true, true);
  }

  /** 原生 ArkUI 阅读器专用：仅触发后台下载与预加载，跳过 JS PixelMap/GL 解码，交由 ArkUI Image 原生解码。 */
  requestFileOnly(index: number): PageRequestResult {
    return this.requestInternal(index, true, false, true, false);
  }

  /** 返回页图本地 URI；仅当该页已处于 STATE_FINISHED 或缓存中可读时返回非空 URI。 */
  getPageFileUri(index: number): string | null {
    if (!this.mStarted) {
      return null;
    }
    const state: number = this.getPageState(index);
    if (state === STATE_FINISHED) {
      return this.mSpiderDen.getImageFileUri(index);
    }
    if (this.mSpiderDen.contain(index)) {
      this.updatePageState(index, STATE_FINISHED);
      return this.mSpiderDen.getImageFileUri(index);
    }
    return null;
  }

  /**
   * 对位私有的 `request(index, ignoreError, force, addNeighbor)`。
   *
   * 三态返回值的判定顺序与上游一致：
   *   STATE_NONE → 入队 + 返回 null
   *   STATE_DOWNLOADING → 返回当前进度（number）
   *   STATE_FAILED → 返回错误文案（string）
   *   STATE_FINISHED → decodeOnFinish 为 true 时入解码队列，否则跳过解码；返回 null
   */
  private requestInternal(index: number, ignoreError: boolean, force: boolean,
    addNeighbor: boolean, decodeOnFinish: boolean): PageRequestResult {
    if (!this.mStarted) {
      return null;
    }

    let state: number = this.getPageState(index);
    // 强制/忽略错误时把 state 复位
    if ((force && (state === STATE_FINISHED || state === STATE_FAILED)) ||
      (ignoreError && state === STATE_FAILED)) {
      this.updatePageState(index, STATE_NONE);
      state = STATE_NONE;
    }

    if (state === STATE_NONE) {
      if (force) {
        this.mForceRequestPageQueue.push(index);
      } else {
        this.mRequestPageQueue.push(index);
      }
    }

    // 预载邻居页（上游只预载"后面的 mPreloadNumber 页"）
    if (addNeighbor) {
      this.mRequestPageQueue2.splice(0, this.mRequestPageQueue2.length);
      const states: number[] | null = this.mPageStateArray;
      const size: number = states !== null ? states.length : Number.MAX_SAFE_INTEGER;
      const until: number = Math.min(index + 1 + this.mPreloadNumber, size);
      for (let i = index + 1; i < until; i++) {
        if (this.getPageState(i) === STATE_NONE) {
          this.mRequestPageQueue2.push(i);
        }
      }
    }

    let result: PageRequestResult = null;
    if (state === STATE_DOWNLOADING) {
      const percent: number | undefined = this.mPagePercentMap.get(index);
      result = percent !== undefined ? percent : null;
    } else if (state === STATE_FAILED) {
      const error: string | undefined = this.mPageErrorMap.get(index);
      result = error !== undefined ? error : GetText.getString('error_unknown');
    } else if (state === STATE_FINISHED) {
      if (decodeOnFinish && this.mDecodeIndexArray.indexOf(index) < 0 &&
        this.mDecodeRequestQueue.indexOf(index) < 0) {
        this.mDecodeRequestQueue.push(index);
        // 触发解码泵（上游由 decode 线程的 wait/notify 唤醒；这里是异步泵）
        this.decodePump();
      }
      result = null;
    }

    this.tryToEnsureWorkers();
    return result;
  }

  /**
   * 对位 `tryToEnsureWorkers()`。
   *
   * **第 3 批才真正起 worker**：worker 需要 `EhEngine` 的下载调用（最小接口 `EhEngineLike`）。
   * 本批只统计"有多少次请求因为缺 worker 无法处理"，并**不假装**已启动线程 ——
   * 这样诊断时能区分"队列空"与"worker 没起来"，而不是静默不动。
   */
  private tryToEnsureWorkers(): void {
    this.mPendingWorkerStarts++;
    // 第 3 批：**无条件**起下载泵。注入缺失由 downloadPage 内部显式失败（该页标 FAILED + 文案），
    // 而不是"请求静静躺在队列里没人处理"——后者是最难查的一类静默失败：
    // 用户看到进度条永远不动，日志里什么都没有。
    // 泵本身不会被异常打死：downloadPage 的所有抛错都在同一个 try 内。
    this.workerPump();
  }

  private mPendingWorkerStarts: number = 0;

  /** 供测试/诊断：有多少次请求在等 worker（第 3 批落地后应恒为 0 增长）。 */
  getPendingWorkerStarts(): number {
    return this.mPendingWorkerStarts;
  }

  /** 对位 `cancelRequest(index)`：从三个队列里摘掉（解码中的不摘，上游同）。 */
  cancelRequest(index: number): void {
    if (!this.mStarted) {
      return;
    }
    SpiderQueen.removeFromArray(this.mRequestPageQueue, index);
    SpiderQueen.removeFromArray(this.mRequestPageQueue2, index);
    SpiderQueen.removeFromArray(this.mForceRequestPageQueue, index);
    SpiderQueen.removeFromArray(this.mDecodeRequestQueue, index);
  }

  private static removeFromArray(array: number[], value: number): void {
    const at: number = array.indexOf(value);
    if (at >= 0) {
      array.splice(at, 1);
    }
  }

  // ================================================================ 第 3 批：下载 worker（注入点驱动）

  private static ehEngine: EhEngineLike | null = null;
  private static imageDownloader: PageImageDownloader | null = null;

  /** net-parse 的 `EhEngine` 落地后注入（`getGalleryPage` / `getGalleryPageApi`）。 */
  static setEhEngine(engine: EhEngineLike | null): void {
    SpiderQueen.ehEngine = engine;
  }

  /** core-runtime 的 image HTTP client 落地后注入。 */
  static setPageImageDownloader(downloader: PageImageDownloader | null): void {
    SpiderQueen.imageDownloader = downloader;
  }

  private mWorkerCount: number = 0;
  private mDownloadPage: number = -1;
  private mStoragePrepared: boolean = false;
  private mWorkerProcessed: number = 0;
  private mWorkerFailures: number = 0;
  /** 对位 `showKey`（页 API 需要；由 `getGalleryPage` 回填）。 */
  private mShowKey: string = '';

  getShowKey(): string {
    return this.mShowKey;
  }

  setShowKey(showKey: string): void {
    this.mShowKey = showKey;
  }

  /** 配置的最大并发 worker 数（由 `Settings.getMultiThreadDownload()` 钳位到 [1, 10]）。 */
  getWorkerMaxCount(): number {
    return this.mWorkerMaxCount;
  }

  /** 当前活跃的并发 worker 数。 */
  getActiveWorkerCount(): number {
    return this.mWorkerCount;
  }

  /** 已处理的下载请求数（上游无此 API，供诊断/测试）。 */
  getWorkerProcessed(): number {
    return this.mWorkerProcessed;
  }

  /** 处理失败的页数（诊断/测试）。 */
  getWorkerFailures(): number {
    return this.mWorkerFailures;
  }

  private estimatedWorkCount(): number {
    const queued: number = this.mForceRequestPageQueue.length +
      this.mRequestPageQueue.length + this.mRequestPageQueue2.length;
    const states: number[] | null = this.mPageStateArray;
    const remainingDownload: number = (states !== null && this.mDownloadPage >= 0 &&
      this.mDownloadPage < states.length) ? (states.length - this.mDownloadPage) : 0;
    return queued + remainingDownload;
  }

  /**
   * 并发下载泵：按 `Settings.getMultiThreadDownload()` 限制的 `mWorkerMaxCount` 启动并发 worker。
   * 取页顺序对位上游 SpiderWorker：强制队列 → 普通队列 → 预载队列 → `mDownloadPage`。
   */
  private workerPump(): void {
    if (!this.mStarted) {
      return;
    }
    const targetWorkers: number = Math.min(this.mWorkerMaxCount, this.estimatedWorkCount());
    while (this.mWorkerCount < targetWorkers) {
      this.mWorkerCount++;
      this.workerLoop();
    }
  }

  private async workerLoop(): Promise<void> {
    let shouldFinish: boolean = false;
    try {
      await Promise.resolve();
      if (this.mMode === MODE_DOWNLOAD && !this.mStoragePrepared) {
        this.mStoragePrepared = true;
        try {
          await this.mSpiderDen.prepareDownloadStorage();
        } catch (e) {
          Utils.throwIfFatal(e);
        }
      }
      while (this.mStarted) {
        const picked: NextIndexResult | null = this.nextDownloadTask();
        if (picked === null) {
          break;
        }
        await this.downloadPage(picked.index);
        this.mWorkerProcessed++;
      }
    } finally {
      this.mWorkerCount--;
      if (this.mWorkerCount < 0) {
        this.mWorkerCount = 0;
      }
      shouldFinish = this.mWorkerCount === 0;
    }
    if (shouldFinish && this.mStarted) {
      this.notifyFinish(this.mFinishedPages, this.mDownloadedPages, this.getPageCount());
    }
  }

  /** 上游 SpiderWorker 的取页与去重逻辑：force → request → request2 → mDownloadPage。 */
  private nextDownloadTask(): NextIndexResult | null {
    while (this.mStarted) {
      let index: number = -1;
      let force: boolean = false;
      const fromForce: number | undefined = this.mForceRequestPageQueue.shift();
      if (fromForce !== undefined) {
        index = fromForce;
        force = true;
      } else {
        const fromRequest: number | undefined = this.mRequestPageQueue.shift();
        if (fromRequest !== undefined) {
          index = fromRequest;
        } else {
          const fromPreload: number | undefined = this.mRequestPageQueue2.shift();
          if (fromPreload !== undefined) {
            index = fromPreload;
          } else {
            const states: number[] | null = this.mPageStateArray;
            if (states !== null && this.mDownloadPage >= 0 && this.mDownloadPage < states.length) {
              index = this.mDownloadPage;
              this.mDownloadPage++;
            } else {
              return null;
            }
          }
        }
      }

      const states: number[] | null = this.mPageStateArray;
      const size: number = states !== null ? states.length : 0;
      if (states !== null && (index < 0 || index >= size)) {
        continue;
      }

      const state: number = this.getPageState(index);
      if (state === STATE_DOWNLOADING || (!force && (state === STATE_FINISHED || state === STATE_FAILED))) {
        continue;
      }

      if (!force && this.mSpiderDen.contain(index)) {
        this.updatePageState(index, STATE_FINISHED);
        this.notifyPageSuccess(index, this.mFinishedPages, this.mDownloadedPages, this.getPageCount());
        continue;
      }

      this.updatePageState(index, STATE_DOWNLOADING);
      return new NextIndexResult(index, force);
    }
    return null;
  }

  /**
   * 下载一页。
   *
   * **关键（刚踩过的坑）**：所有可能抛错的动作都在**同一个 try** 里，失败就
   * `notifyPageFailure` 并返回 —— 绝不让异常逃出 `workerLoop`（否则整个泵永久停摆，
   * 且没有任何日志，比静默返回错误值更难查）。
   */
  private async downloadPage(index: number): Promise<void> {
    try {
      // ① 未注入下载器：显式失败（不写假下载），泵继续
      const downloader: PageImageDownloader | null = SpiderQueen.imageDownloader;
      if (downloader === null) {
        throw new Error('PageImageDownloader not injected（net-parse 的 okhttp 实现未接入；接口本身是我们自建的，上游无同名文件）');
      }
      const engine: EhEngineLike | null = SpiderQueen.ehEngine;
      if (engine === null) {
        throw new Error('EhEngineLike not injected（net-parse 的 getGalleryPageApi 未接入）');
      }

      // ② pToken 未知：上游会先抓 pToken 再拿图。本 port 要求 SpiderInfo 已提供
      //    （`setPagePTokens`）；没有就显式失败，并把该页登记到待抓队列。
      let pToken: string | null = this.getPagePToken(index);
      if (pToken === null) {
        pToken = await this.ensurePagePToken(index);
      }
      if (pToken === null) {
        this.mRequestPTokenQueue.push(index);
        throw new Error('pToken unknown（需要先抓页面 pToken；见 mRequestPTokenQueue）');
      }

      this.updatePageState(index, STATE_DOWNLOADING);
      this.notifyPageDownload(index, -1, 0, 0);
      Utils.logI(TAG, `downloadPage start gid=${this.mGalleryInfo.gid} index=${index}`);

      // ③ 取 imageUrl —— 对位上游 SpiderQueen.java:1275-1349 的 **5 次重试循环**
      //
      // 上游的重试循环是**唯一**的重试机制，包含三件事，缺一就会"永久失败"：
      //   a) showKey 为空 / forceHtml → 走 HTML 页面路径重取（顺带拿 skipHathKey）
      //   b) ParseException "Key mismatch" → 作废 showKey 后 **continue 重试**（不是 break）
      //   c) imageUrl 为 null → 用 otherImageUrl 旁路（换 H@H 节点时会发生）
      //
      // 不重试的后果（审计员报的 P1）：showKey 过期是**必然发生**的，
      // 单次调用会让该页永久失败；`mShowKey` 初值 '' 时**首屏全失败**。
      let imageUrl: string = '';
      let skipHathKey: string | null = null;
      let localShowKey: string = this.mShowKey;
      let pageUrl: string | null = null;
      // 上游 forceHtml：纯文本错误页命中后置 true，下一轮强制走 HTML 路径重取 showKey
      let forceHtml: boolean = false;

      for (let attempt = 0; attempt < SpiderQueen.MAX_RETRY_COUNT; attempt++) {
        // R-06：上游在 for 体内每轮声明 `String imageUrl = null` —— 必须每轮重置。
        // 不重置的话：第 1 轮取到 URL 但下载失败 → 第 2 轮因 `imageUrl.length > 0` 跳过 API 调用
        // → **5 次重试全打同一个（可能已失效的）URL**。
        imageUrl = '';
        let originImageUrl: string = '';
        try {
          // a) 没有 showKey（或本页强制 HTML）→ 走 HTML 路径
          if (localShowKey.length === 0 || forceHtml) {
            forceHtml = false;
            pageUrl = SpiderQueen.buildPageUrl(this.mGalleryInfo.gid, index, pToken, pageUrl, skipHathKey);
            const htmlResult: GalleryPageParserResult = await engine.getGalleryPage(
              null, null, pageUrl, this.mGalleryInfo.gid, this.mGalleryInfo.token);
            skipHathKey = htmlResult.skipHathKey.length > 0 ? htmlResult.skipHathKey : null;
            this.mShowKey = htmlResult.showKey;
            localShowKey = this.mShowKey;
            originImageUrl = htmlResult.originImageUrl;
            // ⚠ 上游会用 HTML 结果里的 imageUrl（SpiderQueen.java:1279-1305）：
            //   `imageUrl = result.imageUrl;` 然后 **只有 imageUrl == null 才打 API**。
            // 我们的 GalleryPageParser 也产出 imageUrl（GalleryPageParser.ets:46-49），所以直接复用，
            // 避免"每个新画廊首页白打一次 showKey API"，以及 API 失败时明明有可用 URL 却判 FAILED。
            if (htmlResult.imageUrl.length > 0) {
              imageUrl = htmlResult.imageUrl;
            }
          }

          // b) 只有 HTML 没给出 imageUrl 时才走 API 路径
          if (imageUrl.length === 0) {
            const api: GalleryPageApiParserResult = await engine.getGalleryPageApi(
              null, null, this.mGalleryInfo.gid, index, pToken, localShowKey, null);
            imageUrl = api.imageUrl;
            if (imageUrl.length === 0) {
              // c) 旁路：换 H@H 节点时 imageUrl 为空，用 otherImageUrl
              imageUrl = api.otherImageUrl;
            }
            if (originImageUrl.length === 0) {
              originImageUrl = api.originImageUrl;
            }
          }
          if (imageUrl.length === 0) {
            throw new Error('empty imageUrl（imageUrl 与 otherImageUrl 都为空）');
          }

          // ③a 原图直链解析（开启 download_origin_image 且拿到 `/fullimg` 地址时解析 302；GP 不足立即报错）
          if (Settings.getDownloadOriginImage() &&
            originImageUrl.length > 0 && downloader.resolveRedirectUrl !== undefined) {
            const originReferer: string = pageUrl !== null
              ? pageUrl
              : EhUrl.getPageUrl(this.mGalleryInfo.gid, index, pToken);
            const resolvedOrigin: string | null = await downloader.resolveRedirectUrl(originImageUrl, originReferer);
            if (resolvedOrigin === null) {
              throw new OriginImageQuotaError('GP不足 / Insufficient GP');
            }
            imageUrl = resolvedOrigin;
          }

          // ③b 509 限流检测（上游 SpiderQueen.java:1242 / :1254，写盘前判）
          if (SpiderQueen.is509Url(imageUrl)) {
            this.notifyGet509(index);
            throw new Image509Error(`509 限流（imageUrl=${imageUrl}）`);
          }

          // ④ 拉字节写盘（C-18：显式传阅读页 URL 作为 Referer）
          const referer: string = pageUrl !== null
            ? pageUrl
            : EhUrl.getPageUrl(this.mGalleryInfo.gid, index, pToken);
          await this.writePageImage(index, imageUrl, downloader, referer);

          // ④b 纯文本 body 检出（上游 SpiderQueen.java:1544-1563）—— 必须在**循环内**：
          //      上游命中后 `forceHtml = true; continue;`，下一轮强制走 HTML 路径取新 showKey 重试。
          //      放在循环外会让"服务端偶发返回文本错误页"直接判 FAILED（叠加 P1 还永久写盘）。
          if (await this.isPlainTextPage(index)) {
            this.mSpiderDen.remove(index);      // 删掉这份错误页，别让它冒充有效图片
            forceHtml = true;
            imageUrl = '';
            continue;
          }

          // 走到这里说明本页成功
          break;
        } catch (e) {
          Utils.throwIfFatal(e);
          if (e instanceof Image509Error || e instanceof OriginImageQuotaError) {
            throw e as Error;
          }
          const msg: string = SpiderQueen.errorMessage(e) !== null ? (SpiderQueen.errorMessage(e) as string) : '';
          // b') "Key mismatch" → 作废 showKey 并重试（上游 `showKey.compareAndSet(local, null); continue;`）
          if (msg.indexOf('Key mismatch') >= 0) {
            this.mShowKey = '';
            localShowKey = '';
            continue;
          }
          // 其它错误：最后一次尝试后抛出，由外层 catch 标 FAILED
          if (attempt === SpiderQueen.MAX_RETRY_COUNT - 1) {
            throw e as Error;
          }
          // 非致命错误也重试（上游同：循环内 continue）
          localShowKey = this.mShowKey;
        }
      }

      if (imageUrl.length === 0) {
        throw new Error(`重试 ${SpiderQueen.MAX_RETRY_COUNT} 次仍未取到 imageUrl`);
      }

      // ⑤ 成功
      this.updatePageState(index, STATE_FINISHED);
      this.mPageErrorMap.delete(index);
      Utils.logI(TAG, `downloadPage finished gid=${this.mGalleryInfo.gid} index=${index} url=${imageUrl}`);
      // 计数器由 updatePageState 按「跨越 done 边界」维护（对位上游 L1113），此处不再手工 ++

      this.notifyPageSuccess(index, this.mFinishedPages, this.mDownloadedPages, this.getPageCount());
    } catch (e) {
      Utils.throwIfFatal(e);
      this.mWorkerFailures++;
      // ⚠ P1（审计员实测证据链）：上游 SpiderQueen.java:1603-1607 在标记失败前先删文件：
      //   `mSpiderDen.remove(index);`
      // 不删的后果：写盘前已 createFile（SpiderDen.ets:547），失败留下空/坏文件；
      // 重启时 applySpiderInfo 按 contain()=文件存在 判定 STATE_FINISHED →
      // **一次失败 = 永久坏图，且「保存图片」会把坏图存进相册**。
      this.mSpiderDen.remove(index);
      this.updatePageState(index, STATE_FAILED);
      const msg: string | null = SpiderQueen.errorMessage(e);
      const resolvedMsg: string = msg !== null ? msg : GetText.getString('error_unknown');
      Utils.logW(TAG, `downloadPage failed gid=${this.mGalleryInfo.gid} index=${index}: ${resolvedMsg}`);
      this.mPageErrorMap.set(index, resolvedMsg);
      this.notifyPageFailure(index, resolvedMsg,
        this.mFinishedPages, this.mDownloadedPages, this.getPageCount());
    }
  }

  private getPageCount(): number {
    const states: number[] | null = this.mPageStateArray;
    return states !== null ? states.length : 0;
  }
  // ---------------------------------------------------------------- 解码 worker（第 3 批的一半：不带网络）

  private mDecodePumping: boolean = false;
  private mDecodedPages: number = 0;

  /**
   * 解码泵：把 `mDecodeRequestQueue` 里的页逐个解码并回调。
   *
   * 上游是 `DECODE_THREAD_NUM = 2` 个线程 + `wait()/notify()`；这里用**单线程异步泵**
   * （与 DirGalleryProvider/RequestPump 同一模式，D-024）：
   * `Image.decodeStream` 本身是异步 API，`await` 之间让出事件循环，不阻塞 UI。
   * 语义仍是「同一页不会被两个消费者解码」（`mDecodeIndexArray` 记录当前解码页）。
   *
   * 上游的两个解码线程共享同一个队列；本 port 的泵是单消费者，等价于「把线程数当 1」——
   * 解码本身是 IO/CPU 混合且 PixelMap 不可跨线程，多线程收益有限。
   */
  private decodePump(): void {
    if (this.mDecodePumping || !this.mStarted) {
      return;
    }
    this.mDecodePumping = true;
    this.decodeLoop();
  }

  private async decodeLoop(): Promise<void> {
    try {
      while (this.mStarted) {
        const index: number | undefined = this.mDecodeRequestQueue.shift();
        if (index === undefined) {
          break;
        }
        this.mDecodeIndexArray[0] = index;
        await this.decodePage(index);
        this.mDecodeIndexArray[0] = -1;
      }
    } finally {
      this.mDecodePumping = false;
      this.mDecodeIndexArray[0] = -1;
    }
  }

  private async decodePage(index: number): Promise<void> {
    // 注意：`openInputStreamPipe` 也可能抛（例如 SpiderDen 的"边读边存"设置未注入时是显式抛错）。
    // 所以取 pipe 必须在 try 之内 —— 否则异常会击穿 decodeLoop，让整个解码泵停摆（上游等价于线程死掉）。
    let pipe: InputStreamPipe | null = null;
    try {
      pipe = this.mSpiderDen.openInputStreamPipe(index);
    } catch (e) {
      Utils.throwIfFatal(e);
      this.notifyGetImageFailure(index, SpiderQueen.errorMessage(e));
      this.mDecodedPages++;
      return;
    }
    if (pipe === null) {
      this.notifyGetImageFailure(index, null);
      this.mDecodedPages++;
      return;
    }
    try {
      pipe.obtain();
      const image: Image | null = Image.decodeStream(SpiderQueen.pipeFile(pipe), false);
      if (image !== null) {
        this.notifyGetImageSuccess(index, image);
      } else {
        this.notifyGetImageFailure(index, null);
      }
    } catch (e) {
      Utils.throwIfFatal(e);
      this.notifyGetImageFailure(index, SpiderQueen.errorMessage(e));
    } finally {
      pipe.close();
      pipe.release();
      this.mDecodedPages++;
    }
  }

  /** 上游 `SpiderWorker` 的重试上限（`for (int i = 0; i < 5; i++)`，SpiderQueen.java:1275）。 */
  static readonly MAX_RETRY_COUNT: number = 5;

  /**
   * 对位上游 `getPageUrl(gid, index, pToken, oldPageUrl, skipHathKey)`（SpiderQueen.java:)
   * —— 在页 URL 上追加 `?nl=<skipHathKey>`（或 `&nl=`，若已有 `?`）。
   */
  static buildPageUrl(gid: number, index: number, pToken: string,
    oldPageUrl: string | null, skipHathKey: string | null): string {
    let pageUrl: string = oldPageUrl !== null ? oldPageUrl : EhUrl.getPageUrl(gid, index, pToken);
    if (skipHathKey !== null) {
      pageUrl += (pageUrl.indexOf('?') >= 0 ? '&nl=' : '?nl=') + skipHathKey;
    }
    return pageUrl;
  }

  /** 从图片 URL 提取合法扩展名（忽略 query/fragment），未识别返回 null。 */
  static extractImageExtension(url: string): string | null {
    let clean: string = url;
    const q: number = clean.indexOf('?');
    if (q >= 0) {
      clean = clean.substring(0, q);
    }
    const h: number = clean.indexOf('#');
    if (h >= 0) {
      clean = clean.substring(0, h);
    }
    const slash: number = clean.lastIndexOf('/');
    const tail: string = slash >= 0 ? clean.substring(slash + 1) : clean;
    const dot: number = tail.lastIndexOf('.');
    if (dot < 0 || dot >= tail.length - 1) {
      return null;
    }
    const ext: string = tail.substring(dot).toLowerCase();
    return SUPPORT_IMAGE_EXTENSIONS.indexOf(ext) >= 0 ? ext : null;
  }

  /**
   * 把 imageUrl 的字节写进 SpiderDen：
   * - 透传 C-18 Referer 并检查 HTTP 509 与 0 字节响应
   * - 失败/异常时通过 `abort()`（或清理 SpiderDen 文件）丢弃脏数据，
   *   `close()/abort()` 始终在 `release()` 之前执行，防止 FD 与锁泄漏
   * - URL 无扩展名时在落盘后按文件头魔数修正扩展名
   */
  private async writePageImage(index: number, imageUrl: string,
    downloader: PageImageDownloader, referer: string): Promise<void> {
    const urlExt: string | null = SpiderQueen.extractImageExtension(imageUrl);
    const pipe: OutputStreamPipe | null = await this.mSpiderDen.openOutputStreamPipeAsync(index, urlExt);
    if (pipe === null) {
      throw new Error('openOutputStreamPipe returned null');
    }
    let obtained: boolean = false;
    let committed: boolean = false;
    let lastNotifyMs: number = -1;
    let lastNotifyPct: number = -1;
    try {
      pipe.obtain();
      obtained = true;
      const sink: ByteSink = pipe.open();
      const result: DownloadResult = await downloader.downloadWithStatus(
        imageUrl,
        sink,
        referer,
        (contentLength: number, receivedSize: number, bytesRead: number): void => {
          if (!Number.isFinite(contentLength) || contentLength <= 0 ||
            !Number.isFinite(receivedSize) || receivedSize < 0) {
            return;
          }
          const ratio: number = Math.max(0, Math.min(1, receivedSize / contentLength));
          this.mPagePercentMap.set(index, ratio);
          const pct: number = Math.max(0, Math.min(100, Math.round(ratio * 100)));
          const now: number = Date.now();
          if (pct !== lastNotifyPct &&
            (lastNotifyPct < 0 || pct >= 100 || (now - lastNotifyMs) >= 85 ||
              (Math.abs(pct - lastNotifyPct) >= 2 && (now - lastNotifyMs) >= 32))) {
            lastNotifyMs = now;
            lastNotifyPct = pct;
            this.notifyPageDownload(index, contentLength, receivedSize, bytesRead);
          }
        }
      );
      if (result.status === 509) {
        this.notifyGet509(index);
        throw new Image509Error(`509 限流（status=509, url=${imageUrl}）`);
      }
      if (!result.ok) {
        throw new Error(result.error.length > 0
          ? result.error
          : `downloader failed (status=${result.status})`);
      }
      if (result.received <= 0) {
        throw new Error('empty image payload (0 bytes)');
      }
      committed = true;
    } finally {
      try {
        if (committed) {
          pipe.close();
        } else if (pipe instanceof CacheOutputStreamPipe) {
          (pipe as CacheOutputStreamPipe).abort();
        } else {
          pipe.close();
        }
      } finally {
        if (obtained) {
          pipe.release();
        }
      }
      if (!committed) {
        this.mSpiderDen.remove(index);
      } else if (urlExt === null) {
        this.mSpiderDen.fixDownloadedExtension(index);
      }
    }
  }
  /** 对位上游 `URL_509_SUFFIX_ARRAY = { "/509.gif", "/509s.gif" }`（SpiderQueen.java:115-117）。 */
  static readonly URL_509_SUFFIX_ARRAY: string[] = ['/509.gif', '/509s.gif'];

  /** 该 URL 是否为 509 限流图（上游用 `StringUtils.endsWith(url, URL_509_SUFFIX_ARRAY)`）。 */
  static is509Url(url: string): boolean {
    for (const suffix of SpiderQueen.URL_509_SUFFIX_ARRAY) {
      if (url.length >= suffix.length && url.substring(url.length - suffix.length) === suffix) {
        return true;
      }
    }
    return false;
  }

  /**
   * 对位上游「纯文本 body 检出」（SpiderQueen.java:1544-1563）：下载完成后回读，
   * **所有字节 <= 126** 则判为错误页（服务器返回了文本错误而非图片）。
   *
   * 与上游的差别（有意）：上游逐字节读到 EOF 再下结论；这里按 8KB 块流式读，
   * 遇到任一 > 126 立即返回 false（短路）。**判据等价**，只是大图不必读完。
   * 读失败时返回 false（不把"读不出来"误判成"纯文本"）——失败会在上层按 IO 错误处理。
   */
  private async isPlainTextPage(index: number): Promise<boolean> {
    const pipe: InputStreamPipe | null = this.mSpiderDen.openInputStreamPipe(index);
    if (pipe === null) {
      return false;
    }
    try {
      pipe.obtain();
      const file: fs.File = pipe.open();
      const buf: ArrayBuffer = new ArrayBuffer(8192);
      const view: Uint8Array = new Uint8Array(buf);
      let anyByte: boolean = false;
      while (true) {
        const n: number = await fs.read(file.fd, buf, { length: 8192 });
        if (n <= 0) {
          break;
        }
        anyByte = true;
        for (let i = 0; i < n; i++) {
          if (view[i] > 126) {
            return false;
          }
        }
      }
      // 空文件不算"纯文本错误页"（上游同样：没有任何字节时 isPlainTxt 初始为 true，
      // 但空文件会在解码阶段失败，走另一条错误路径）
      return anyByte;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    } finally {
      pipe.close();
      pipe.release();
    }
  }
  /** 从 catch 参数里取文案（ArkTS 的 catch 参数是 unknown；取不到就 null → 调用方替换成"未知错误"）。 */
  private static errorMessage(e: Object): string | null {
    if (e instanceof Error) {
      return e.message !== undefined ? e.message : null;
    }
    return null;
  }

  /** InputStreamPipe.open() 给的是 fs.File（streampipe 契约），直接转交解码。 */
  private static pipeFile(pipe: InputStreamPipe): fs.File {
    return pipe.open();
  }

  /** 已解码页数（上游无此 API，供诊断/测试）。 */
  getDecodedPages(): number {
    return this.mDecodedPages;
  }

  /** 供诊断：当前解码中的页（-1 表示空闲）。 */
  getDecodingIndex(): number {
    return this.mDecodeIndexArray[0];
  }
  /** 各队列长度（上游无此 API，供测试/诊断）。 */
  getQueueSizes(): number[] {
    return [this.mRequestPageQueue.length, this.mRequestPageQueue2.length,
      this.mForceRequestPageQueue.length, this.mDecodeRequestQueue.length];
  }

  // ---------------------------------------------------------------- pToken / 页 URL

  /** 已知 pToken（页号 → pToken）。上游用 `mPagePTokens`（SparseArray）。 */
  private mPagePTokens: Map<number, string> = new Map<number, string>();

  /** 由 SpiderInfo 的 pTokenMap 填充（对位上游读 spider_info 后填 `mPagePTokens`）。 */
  setPagePTokens(map: Map<number, string> | null): void {
    this.mPagePTokens = map !== null ? map : new Map<number, string>();
  }

  /** 取某页 pToken（未知名返回 null）。 */
  getPagePToken(index: number): string | null {
    const token: string | undefined = this.mPagePTokens.get(index);
    return token !== undefined ? token : null;
  }

  /**
   * 对位 `getPageUrl(index)` → `EhUrl.getPageUrl(gid, index, pToken)`。
   * pToken 未知时**返回 null**（上游也要先取 pToken 才能拼 URL），不编造占位值。
   */
  getPageUrl(index: number): string | null {
    const pToken: string | null = this.getPagePToken(index);
    if (pToken === null) {
      return null;
    }
    return EhUrl.getPageUrl(this.mGalleryInfo.gid, index, pToken);
  }

  /** 需要抓 pToken 的页（上游 `mRequestPTokenQueue`）。 */
  getPendingPTokenRequests(): number[] {
    return this.mRequestPTokenQueue;
  }

  // ---------------------------------------------------------------- 另存为（对位 save(int, UniFile) / save(int, UniFile, String)）

  /** 对位 `save(index, file)`：仅 FINISHED 页可存。 */
  saveToFile(index: number, file: UniFile): boolean {
    if (this.getPageState(index) !== STATE_FINISHED) {
      return false;
    }
    const pipe: InputStreamPipe | null = this.mSpiderDen.openInputStreamPipe(index);
    if (pipe === null) {
      return false;
    }
    let os: OutputStream | null = null;
    try {
      pipe.obtain();
      os = file.openOutputStream();
      const input: InputStream = new FsFileInputStream(pipe.open());
      const buf: ArrayBuffer = new ArrayBuffer(64 * 1024);
      while (true) {
        const n: number = input.readBuffer(buf);
        if (n <= 0) {
          break;
        }
        os.writeBytes(buf, 0, n);
      }
      os.flush();
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    } finally {
      pipe.close();
      pipe.release();
      Utils.closeQuietly(os);
    }
  }

  /**
   * 对位 `save(index, dir, filename)`：保留原扩展名。
   * 上游用 `BitmapFactory.inJustDecodeBounds` + `MimeTypeMap` 嗅探 MIME；
   * 鸿蒙 API 20 的 `image.ImageInfo` 没有 mimeType → 复用 `SpiderDen.sniffImageExtension`（魔数）。
   */
  saveToDir(index: number, dir: UniFile, filename: string): UniFile | null {
    if (this.getPageState(index) !== STATE_FINISHED) {
      return null;
    }
    const pipe: InputStreamPipe | null = this.mSpiderDen.openInputStreamPipe(index);
    if (pipe === null) {
      return null;
    }
    let os: OutputStream | null = null;
    try {
      pipe.obtain();
      // 1) 嗅探扩展名
      const handle: fs.File = pipe.open();
      const head: ArrayBuffer = new ArrayBuffer(16);
      let read: number = 0;
      try {
        read = fs.readSync(handle.fd, head, { offset: 0, length: 16 });
      } catch (e) {
        Utils.throwIfFatal(e);
      }
      pipe.close();
      const extension: string | null = read > 0
        ? SpiderDen.sniffImageExtension(head.slice(0, read))
        : null;
      const dstName: string = extension !== null ? `${filename}${extension}` : filename;
      const dst: UniFile | null = dir.subFile(dstName);
      if (dst === null) {
        return null;
      }
      // 2) 整段拷贝
      os = dst.openOutputStream();
      const input: InputStream = new FsFileInputStream(pipe.open());
      const buf: ArrayBuffer = new ArrayBuffer(64 * 1024);
      while (true) {
        const n: number = input.readBuffer(buf);
        if (n <= 0) {
          break;
        }
        os.writeBytes(buf, 0, n);
      }
      os.flush();
      return dst;
    } catch (e) {
      Utils.throwIfFatal(e);
      return null;
    } finally {
      pipe.close();
      pipe.release();
      Utils.closeQuietly(os);
    }
  }
  // ---------------------------------------------------------------- 监听器（对位上游 OnSpiderListener）

  /** 对位 `addOnSpiderListener`。重复添加会重复回调（上游 ArrayList 语义）。 */
  addOnSpiderListener(listener: OnSpiderListener): void {
    this.mSpiderListeners.push(listener);
  }

  /** 对位 `removeOnSpiderListener`（只移除第一个匹配项，与上游 ArrayList.remove 一致）。 */
  removeOnSpiderListener(listener: OnSpiderListener): void {
    const at: number = this.mSpiderListeners.indexOf(listener);
    if (at >= 0) {
      this.mSpiderListeners.splice(at, 1);
    }
  }

  /** 当前监听器数量（上游无此 API，供测试与排查）。 */
  getSpiderListenerCount(): number {
    return this.mSpiderListeners.length;
  }

  // —— notify* 系列：上游是 private，逐个薄封装。
  //    本批**没有任何路径会调用它们**（读取/下载循环在批 2/3），但先落地是为了：
  //    ① 让下游（download-sync 的 DownloadManager）可以立刻 addOnSpiderListener 而不报错；
  //    ② 把 8 个回调的形状钉死，第 2/3 批只需在正确位置调用，不需要改接口。

  /** 对位 `notifyGetPages`。 */
  private notifyGetPages(pages: number): void {
    for (const listener of this.mSpiderListeners) {
      listener.onGetPages(pages);
    }
  }

  /** 对位 `notifyGet509`。 */
  private notifyGet509(index: number): void {
    for (const listener of this.mSpiderListeners) {
      listener.onGet509(index);
    }
  }

  /** 对位 `notifyPageDownload(index, contentLength, receivedSize, bytesRead)`。 */
  private notifyPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void {
    for (const listener of this.mSpiderListeners) {
      listener.onPageDownload(index, contentLength, receivedSize, bytesRead);
    }
  }

  /** 对位 `notifyPageSuccess(index, finished, downloaded, total)`。 */
  private notifyPageSuccess(index: number, finished: number, downloaded: number, total: number): void {
    for (const listener of this.mSpiderListeners) {
      listener.onPageSuccess(index, finished, downloaded, total);
    }
  }

  /** 对位 `notifyPageFailure(index, error, finished, downloaded, total)`。 */
  private notifyPageFailure(index: number, error: string, finished: number, downloaded: number,
    total: number): void {
    for (const listener of this.mSpiderListeners) {
      listener.onPageFailure(index, error, finished, downloaded, total);
    }
  }

  /** 对位 `notifyFinish(finished, downloaded, total)`。 */
  private notifyFinish(finished: number, downloaded: number, total: number): void {
    for (const listener of this.mSpiderListeners) {
      listener.onFinish(finished, downloaded, total);
    }
  }

  /** 对位 `notifyGetImageSuccess(index, image)`。 */
  private notifyGetImageSuccess(index: number, image: Image): void {
    for (const listener of this.mSpiderListeners) {
      listener.onGetImageSuccess(index, image);
    }
  }

  /** 对位 `notifyGetImageFailure(index, error)`（上游 error 为 null 时替换成"未知错误"文案）。 */
  private notifyGetImageFailure(index: number, error: string | null): void {
    const msg: string = error !== null ? error : GetText.getString('error_unknown');
    for (const listener of this.mSpiderListeners) {
      listener.onGetImageFailure(index, msg);
    }
  }
  /** 对位 `setMode(mode)`：加对应引用计数；切入 DOWNLOAD 时触发下载泵。 */
  setMode(mode: number): void {
    if (mode === MODE_READ) {
      this.mReadReference++;
    } else if (mode === MODE_DOWNLOAD) {
      this.mDownloadReference++;
    }
    this.updateEffectiveMode();
  }

  /** 对位 `clearMode(mode)`：减对应引用计数（不低于 0）。 */
  clearMode(mode: number): void {
    if (mode === MODE_READ && this.mReadReference > 0) {
      this.mReadReference--;
    } else if (mode === MODE_DOWNLOAD && this.mDownloadReference > 0) {
      this.mDownloadReference--;
    }
    this.updateEffectiveMode();
  }

  private updateEffectiveMode(): void {
    const nextMode: number = this.mDownloadReference > 0 ? MODE_DOWNLOAD : MODE_READ;
    this.mMode = nextMode;
    this.mSpiderDen.setMode(nextMode);
    if (nextMode === MODE_DOWNLOAD) {
      if (this.mDownloadPage < 0) {
        this.mDownloadPage = 0;
        const states: number[] | null = this.mPageStateArray;
        if (states !== null) {
          for (let i = 0; i < states.length; i++) {
            if (states[i] !== STATE_DOWNLOADING && states[i] !== STATE_FINISHED) {
              states[i] = STATE_NONE;
            }
          }
        }
        this.tryToEnsureWorkers();
      }
    } else {
      this.mDownloadPage = -1;
    }
  }

  getMode(): number {
    return this.mMode;
  }

  /**
   * 对位 `start()`：标记启动并异步初始化下载存储、读取/拉取 `SpiderInfo`、启动并发 worker。
   */
  start(): void {
    if (this.mStarted) {
      throw new IllegalStateError(`[${TAG}] start() 被重复调用（上游同样抛错）`);
    }
    this.mStarted = true;
    this.mError = '';
    this.mSpiderDen.setMode(this.mMode);
    this.startAsync();
    Utils.logI(TAG, `start() gid=${this.mGalleryInfo.gid} mode=${this.mMode}`);
  }

  private async startAsync(): Promise<void> {
    try {
      await Promise.resolve();
      if (!this.mStarted) {
        return;
      }
      if (this.mMode === MODE_DOWNLOAD && !this.mStoragePrepared) {
        this.mStoragePrepared = true;
        try {
          await this.mSpiderDen.prepareDownloadStorage();
        } catch (e) {
          Utils.throwIfFatal(e);
        }
      }
      if (!this.mStarted) {
        return;
      }
      if (this.mSpiderInfo === null && this.mPageStateArray === null) {
        let info: SpiderInfo | null = null;
        try {
          info = this.readSpiderInfoFromLocal();
        } catch (e) {
          Utils.throwIfFatal(e);
          info = null;
        }
        if (!this.mStarted) {
          return;
        }
        if (info === null && SpiderQueen.detailFetcher !== null) {
          try {
            const detail: GalleryDetail | null =
              await SpiderQueen.detailFetcher.getGalleryDetail(this.mGalleryInfo);
            info = SpiderInfo.getSpiderInfoByGalleryDetail(detail);
          } catch (e) {
            Utils.throwIfFatal(e);
            info = null;
          }
        }
        if (!this.mStarted) {
          return;
        }
        if (info === null) {
          if (this.mSpiderInfo === null && this.mPageStateArray === null &&
            SpiderQueen.detailFetcher !== null) {
            const localized: string = GetText.getString('error_get_spider_info');
            this.mError = localized.length > 0 ? localized : 'Failed to load SpiderInfo';
            this.notifyFinish(this.mFinishedPages, this.mDownloadedPages, this.getPageCount());
          }
          return;
        }
        if (this.mSpiderInfo === null && this.mPageStateArray === null) {
          try {
            this.writeSpiderInfoToLocal(info);
          } catch (e) {
            Utils.throwIfFatal(e);
          }
          this.applySpiderInfo(info);
        }
      } else {
        this.tryToEnsureWorkers();
      }
    } catch (e) {
      Utils.throwIfFatal(e);
      if (this.mStarted) {
        const msg: string | null = SpiderQueen.errorMessage(e);
        this.mError = msg !== null ? msg : GetText.getString('error_unknown');
        this.notifyFinish(this.mFinishedPages, this.mDownloadedPages, this.getPageCount());
      }
    }
  }

  /** 对位 `stop()`：停掉一切并释放。 */
  stop(): void {
    this.mStarted = false;
    this.mError = '';
    this.mDownloadPage = -1;
    this.mStoragePrepared = false;
    // 清空四个请求队列（对位上游 `Thread.interrupt()` + 各队列在 stop 后不再被消费）
    this.mRequestPageQueue.splice(0, this.mRequestPageQueue.length);
    this.mRequestPageQueue2.splice(0, this.mRequestPageQueue2.length);
    this.mForceRequestPageQueue.splice(0, this.mForceRequestPageQueue.length);
    this.mDecodeRequestQueue.splice(0, this.mDecodeRequestQueue.length);
    // queen 从表里移除后会被丢弃；显式清监听器避免下游（如 DownloadManager）被长期持有
    this.mSpiderListeners.splice(0, this.mSpiderListeners.length);
    this.mSpiderInfo = null;
    this.mState = STATE_NONE;
    this.mReadReference = 0;
    this.mDownloadReference = 0;
    Utils.logI(TAG, `stop() gid=${this.mGalleryInfo.gid}`);
  }

  isStarted(): boolean {
    return this.mStarted;
  }

  /** 对位 `SPIDER_INFO_FILENAME` 在下载目录里的进度文件（供第 2 批的加载器使用）。 */
  getSpiderInfoFilename(): string {
    return SPIDER_INFO_FILENAME;
  }

  /** 对位缓存目录名（`cacheDir/spider_info`），仅供排查与测试断言。 */
  getSpiderInfoCacheDirname(): string {
    return SPIDER_INFO_CACHE_DIRNAME;
  }

  /** 对位 `isValid` 的对外入口（第 2 批加载完成时用它校验）。 */
  hasValidSpiderInfo(info: SpiderInfo | null): boolean {
    return SpiderQueen.isValidSpiderInfo(info, this.mGalleryInfo);
  }
}

/** ArkTS 无内置 IllegalStateException：用一个可识别的自定义错误。 */
export class IllegalStateError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'IllegalStateError';
  }
}

/**
 * 把 `fs.File`（缓存 pipe `open()` 的产物）适配成 unifile 的 `InputStream`。
 *
 * 为什么需要：`SpiderInfo.readStreamInclude(is: InputStream, ...)` 要的是 unifile 名义类型，
 * 而缓存 pipe 给的是 `fs.File`；`Contracts.FsInputStream` 只接受**路径**（缓存 pipe 不暴露路径）。
 * 结构相似的接口在 ArkTS 里不能互相赋值（`arkts-no-structural-typing`），所以必须显式适配。
 */
class FsFileInputStream implements InputStream {
  private readonly file: fs.File;
  private readonly one: ArrayBuffer = new ArrayBuffer(1);
  private closed: boolean = false;

  constructor(file: fs.File) {
    this.file = file;
  }

  read(): number {
    const n: number = fs.readSync(this.file.fd, this.one, { length: 1 });
    if (n <= 0) {
      return -1;
    }
    return new Uint8Array(this.one)[0];
  }

  readBuffer(buffer: ArrayBuffer): number {
    const n: number = fs.readSync(this.file.fd, buffer, { length: buffer.byteLength });
    return n <= 0 ? -1 : n;
  }

  readBytes(buffer: ArrayBuffer, off: number, len: number): number {
    const n: number = fs.readSync(this.file.fd, buffer, { length: len });
    return n <= 0 ? -1 : n;
  }

  skip(n: number): number {
    const tmp: ArrayBuffer = new ArrayBuffer(n);
    const got: number = fs.readSync(this.file.fd, tmp, { length: n });
    return got <= 0 ? 0 : got;
  }

  available(): number {
    return 0; // 缓存 pipe 不提供长度；SpiderInfo 的读取是按行推进，不依赖 available()
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      fs.closeSync(this.file);
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }
}
