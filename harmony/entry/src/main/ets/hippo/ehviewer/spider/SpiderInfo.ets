/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/spider/SpiderInfo.java
 *
 * 作用：本地下载目录里 `spider_info` 文件的模型与读写（版本头 + 页数 + 每页 pToken）。
 * 这是「已下载画廊还能继续看/继续下」的核心元数据；文件格式必须与 Android 侧**逐字节兼容**，
 * 否则用户从旧 App 迁移过来的下载目录会读不出来。
 *
 * 平台对位：
 *   - `android.util.SparseArray<String>` → ArkTS 用 `Map<number, string>`。**注意 write() 里
 *     上游按 key 升序遍历**（SparseArray 天然有序），这里必须显式排序，否则写出的 pToken 行序
 *     与上游不同（虽然读侧按 index 建映射、不依赖行序，但为了"逐字节兼容"仍按升序写）。
 *   - 文件 IO：UniFile.openInputStream()/openOutputStream() → unifile/Contracts 的
 *     InputStream/OutputStream（ArkTS 无 java.io）。行读取用 IOUtils.readAsciiLine(最大长度)。
 *   - `OutputStreamWriter` → 手工拼字符串后 write 字节（UTF-8），避免依赖不存在的 Writer。
 *   - 异常：IOException/NumberFormatException → Error（ArkTS 只有 Error，方案 §5-⑧）。
 *     上游 `catch (OutOfMemoryError)` 的语义保留为 catch 全部 + 上限常量（MAX_* 四个常量原样保留）。
 *
 * 未实现的两处（**不做假实现**，都在等别人落地，方法内抛错并写明归属）：
 *   - `getSpiderInfoFromDetail(GalleryDetail)` / `readPreviews(...)`：
 *     依赖 net-parse 的 `client/data/GalleryDetail.ets`（当前只在 refactor/net-parse 分支，
 *     尚未进 main）、`client/parser/GalleryPageUrlParser.ets`、`client/exception/ParseException.ets`
 *   - `writeNewSpiderInfoToLocal()` 的缓存回写：依赖 core-runtime 的
 *     `EhApplication.getSpiderInfoCache()` + `util/ExceptionUtils`
 *     （本地文件写入部分**已实现**，只有内存缓存那条支路待接）
 */

import { UniFile } from '../../unifile/UniFile';
import { InputStream, OutputStream } from '../../unifile/Contracts';
import { Utils } from '../../unifile/Utils';
import { IOUtils, InputStreamLike } from '../../lib/yorozuya/IOUtils';
import { NumberUtils } from '../../lib/yorozuya/NumberUtils';
import { GalleryInfo } from '../client/data/GalleryInfo';
import { GalleryDetail } from '../client/data/GalleryDetail';
import { PreviewSet } from '../client/data/PreviewSet';
import { GalleryPageUrlParser, PageUrlResult } from '../client/parser/GalleryPageUrlParser';
import { SimpleDiskCache, CacheOutputStreamPipe } from '../../beerbelly/SimpleDiskCache';
import { OutputStreamPipe, ByteSink } from '../../streampipe/OutputStreamPipe';
import { CborSpiderHeader, CborSpiderHeaderFields } from './CborSpiderHeader';

/**
 * 对位 `EhApplication.getSpiderInfoCache()`：返回 spider_info 目录的 SimpleDiskCache。
 */
export interface SpiderInfoCacheProvider {
  getSpiderInfoCache(): SimpleDiskCache | null;
}

const TAG: string = 'SpiderInfo';

const VERSION_STR: string = 'VERSION';
const VERSION: number = 2;

/** 本地文件页数上限，防损坏的 spider_info 导致 OOM（上游原值）。 */
const MAX_SPIDER_INFO_PAGES: number = 100000;
/** 头部行长度上限（上游原值）。 */
const MAX_SPIDER_INFO_HEADER_LINE: number = 8192;
/** 每行 "{index} {pToken}" 的长度上限（上游原值）。 */
const MAX_PTOKEN_FILE_LINE: number = 2048;
/** 单个 pToken 最大字符数（上游原值）。 */
const MAX_STORED_PTOKEN_CHARS: number = 1024;

/**
 * 对位 `SpiderQueen.SPIDER_INFO_FILENAME`（SpiderQueen.java:108）。
 *
 * **值是 `.ehviewer`，不是 `spider_info`** —— 这两个名字很容易混，我第一版就写错了：
 *   - `.ehviewer`     = **下载目录里**的进度文件（SpiderInfo.java:308 `downloadDir.createFile(...)`、
 *                       SpiderQueen.java:813/945 同），旧版 App 下载过的画廊目录里就是这个文件名
 *   - `spider_info`   = **缓存目录名**（EhApplication.java:595 `new File(context.getCacheDir(), "spider_info")`，
 *                       5MB），存的是同一个 SpiderInfo 的内存/磁盘缓存，与下载目录无关
 *
 * 写成 `spider_info` 的后果：**旧下载目录里的 `.ehviewer` 永远找不到 → 已下载的画廊被当成"没下载"
 * → 重新下载整个画廊**。不报错、不崩溃，只是流量暴涨 + 重复下载，属最典型的静默行为降级。
 *
 * 上游把该常量放在 SpiderQueen 里、SpiderInfo 静态导入；本 port 在 SpiderInfo 里单点定义，
 * SpiderQueen 落地时**必须**从这里 re-export（禁止再写一份字面量）。
 */
export const SPIDER_INFO_FILENAME: string = '.ehviewer';

/** 对位 `EhApplication` 的 SpiderInfo **缓存目录**名（`File(context.getCacheDir(), "spider_info")`，5MB）。 */
export const SPIDER_INFO_CACHE_DIRNAME: string = 'spider_info';

/**
 * 下载目录解析的注入点。
 *
 * 为什么需要它（与 D-017 同款的结构处理）：上游 `SpiderInfo.getSpiderInfo(GalleryInfo)` 静态直连
 * `SpiderDen.getGalleryDownloadDir(info)`，而 SpiderDen 依赖尚未落地的模块。为让 SpiderInfo
 * 在依赖齐备前也能**真实编译**并独立可用，把这次静态调用收敛成注入点：
 * SpiderDen 落地时 `SpiderInfo.setDownloadDirProvider(den)` 注入即可，运行时行为与上游一致。
 *
 * ── 真实依赖链（我按 `git grep` 逐个核过上游，勿凭印象改）──────────────────────
 *   SpiderInfo.getSpiderInfo(GalleryInfo)
 *     └─ SpiderDen.getGalleryDownloadDir(GalleryInfo)            SpiderDen.java:139
 *          ├─ Settings.getDownloadLocation(): UniFile|null       Settings.java:782
 *          │    · 从 5 个偏好键拼 URI：KEY_DOWNLOAD_SAVE_{SCHEME,AUTHORITY,PATH,QUERY,FRAGMENT}
 *          │      （Settings.java:776-779，第一个是 KEY_DOWNLOAD_SAVE_PATH = "image_path"）
 *          │    · `UniFile.fromUri(sContext, uri)` 失败/为空时的兜底：
 *          │      `UniFile.fromFile(AppConfig.getDefaultDownloadDir())`   Settings.java:796
 *          │         └─ AppConfig.getDefaultDownloadDir(): File;              AppConfig.java:93
 *          │            鸿蒙侧返回 string 路径（core-runtime S0035）
 *          ├─ EhDB.getDownloadDirname(long gid): String|null     EhDB.java:484
 *          │    （内部就是 DownloadDirnameDao.load(gid).getDirname()）
 *          └─ EhDB.putDownloadDirname(long gid, String dirname)  EhDB.java:497（insert-or-update）
 *
 * 结论（给 core-runtime 的接口口径）：
 *   - **`Settings.getDownloadLocation()` 是必须有的**（上游 8 处调用：EhApplication/SpiderDen×2/
 *     MainActivity/DirPicker/两处 preference/WiFiDownloadMigrationHelper），只做
 *     `AppConfig.getDefaultDownloadDir()` 会让这 8 处都没法写；
 *   - `Settings.getDownloadDir()` / `putDownloadDir()` **确实不存在**（lead 的否定核查是对的）；
 *   - `EhDB.getDownloadDirname` / `putDownloadDirname` **确实存在**，不是杜撰。
 */
export interface DownloadDirProvider {
  /** 对位 `SpiderDen.getGalleryDownloadDir(GalleryInfo)`：返回下载目录（不存在时由实现方创建）。 */
  getGalleryDownloadDir(info: GalleryInfo): UniFile | null;
}


export class SpiderInfo {
  public static readonly TOKEN_FAILED: string = 'failed';

  /** 下载目录解析器（见 DownloadDirProvider 注释；SpiderDen 落地时注入）。 */
  private static dirProvider: DownloadDirProvider | null = null;
  private static cacheProvider: SpiderInfoCacheProvider | null = null;

  /** 由 SpiderDen 注入下载目录解析器。 */
  static setDownloadDirProvider(provider: DownloadDirProvider | null): void {
    SpiderInfo.dirProvider = provider;
  }

  /** 注入 SpiderInfo 缓存提供者（用于回写 `SimpleDiskCache`）。 */
  static setCacheProvider(provider: SpiderInfoCacheProvider | null): void {
    SpiderInfo.cacheProvider = provider;
  }

  public startPage: number = 0;
  public gid: number = -1;
  public token: string | null = null;
  public pages: number = -1;
  public previewPages: number = -1;
  public previewPerPage: number = -1;
  /** 对位 SparseArray<String>：页号 → pToken（写入时按页号升序）。 */
  public pTokenMap: Map<number, string> | null = null;

  // ---------------------------------------------------------------- 读

  /**
   * 对位上游 `read(UniFile)` 的**原名入口**。
   *
   * 下游按上游名字调用（download-sync 的 `DownloadManager`、`DownloadSpiderInfoExecutor`）；
   * 我上一版把入口改名为 `readFile`，直接造成 2 处编译错误
   * （`Property 'read' does not exist on type 'typeof SpiderInfo'`）。
   * 这里按原名补回，`readFile` 保留为别名 —— 两个名字指向同一实现，不会再漂移。
   */
  static read(file: UniFile | null): SpiderInfo | null {
    return SpiderInfo.readFile(file);
  }

  /** 对位上游 `readHeader(UniFile)` 的原名入口（只读头部，别回写）。 */
  static readHeader(file: UniFile | null): SpiderInfo | null {
    return SpiderInfo.readHeaderFile(file);
  }

  /** 对位 `read(UniFile)`：完整读（含 pTokenMap）。 */
  static readFile(file: UniFile | null): SpiderInfo | null {
    return SpiderInfo.readFromFile(file, true);
  }

  /** 对位 `readHeader(UniFile)`：只读头部（下载列表进度显示用，别回写）。 */
  static readHeaderFile(file: UniFile | null): SpiderInfo | null {
    return SpiderInfo.readFromFile(file, false);
  }

  private static readFromFile(file: UniFile | null, includePTokens: boolean): SpiderInfo | null {
    if (file === null) {
      return null;
    }
    let is: InputStream | null = null;
    try {
      is = file.openInputStream();
      return SpiderInfo.readStreamInclude(is, includePTokens);
    } catch (e) {
      Utils.throwIfFatal(e);
      return null;
    } finally {
      Utils.closeQuietly(is);
    }
  }

  private static getStartPage(str: string | null): number {
    if (str === null) {
      return 0;
    }
    let startPage: number = 0;
    for (let i = 0; i < str.length; i++) {
      startPage *= 16;
      const ch: string = str.charAt(i);
      const code: number = str.charCodeAt(i);
      if (code >= 0x30 && code <= 0x39) {
        startPage += code - 0x30;
      } else if (code >= 0x61 && code <= 0x66) {
        startPage += code - 0x61 + 10;
      }
    }
    return Math.max(startPage, 0);
  }

  private static getVersion(str: string | null): number {
    if (str === null) {
      return -1;
    }
    if (str.startsWith(VERSION_STR)) {
      return NumberUtils.parseIntSafely(str.substring(VERSION_STR.length), -1);
    }
    return 1;
  }

  /** 对位 `read(InputStream)`。 */
  static readStream(is: InputStream | null): SpiderInfo | null {
    return SpiderInfo.readStreamInclude(is, true);
  }

  /** 对位 `readHeader(InputStream)`。 */
  static readHeaderStream(is: InputStream | null): SpiderInfo | null {
    return SpiderInfo.readStreamInclude(is, false);
  }

  /**
   * 对位上游 `readCborHeader(UniFile)`：
   * 从 CBOR 格式的 `.ehviewer` 读取 gid 和 token，不加载 pTokenMap。
   */
  static readCborHeader(file: UniFile | null): SpiderInfo | null {
    if (file === null) {
      return null;
    }
    let is: InputStream | null = null;
    try {
      is = file.openInputStream();
      return SpiderInfo.readCborHeaderStream(is);
    } catch (_e) {
      // 上游明确吞 IOException | OutOfMemoryError 并返回 null
      return null;
    } finally {
      Utils.closeQuietly(is);
    }
  }

  /**
   * 对位上游 `readCborHeader(InputStream)`：
   * 返回对象只填 gid 与 token 两个字段，不能写回磁盘。
   */
  static readCborHeaderStream(is: InputStream | null): SpiderInfo | null {
    const fields: CborSpiderHeaderFields | null = CborSpiderHeader.read(is);
    if (fields === null) {
      return null;
    }
    const spiderInfo: SpiderInfo = new SpiderInfo();
    spiderInfo.gid = fields.gid;
    spiderInfo.token = fields.token;
    return spiderInfo;
  }

  static readStreamInclude(is: InputStream | null, includePTokens: boolean): SpiderInfo | null {
    if (is === null) {
      return null;
    }
    let spiderInfo: SpiderInfo | null = null;
    try {
      spiderInfo = SpiderInfo.parseHeader(is);
      if (spiderInfo === null) {
        return null;
      }
      if (includePTokens) {
        SpiderInfo.readPTokens(is, spiderInfo);
      } else {
        spiderInfo.pTokenMap = new Map<number, string>();
      }
    } catch (e) {
      Utils.throwIfFatal(e);
      return null;
    }
    if (spiderInfo.gid === -1 || spiderInfo.token === null ||
      spiderInfo.pages === -1 || spiderInfo.pTokenMap === null) {
      return null;
    }
    return spiderInfo;
  }

  private static parseHeader(raw: InputStream): SpiderInfo | null {
    const is: InputStreamLike = new StreamAdapter(raw);
    const spiderInfo: SpiderInfo = new SpiderInfo();
    let line: string = IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE);
    const version: number = SpiderInfo.getVersion(line);
    if (version === VERSION) {
      line = IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE);
    } else if (version !== 1) {
      return null;
    }
    spiderInfo.startPage = SpiderInfo.getStartPage(line);
    spiderInfo.gid = Number.parseInt(IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE), 10);
    spiderInfo.token = IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE);
    // 该行（"1"）上游读出即丢弃
    IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE);
    spiderInfo.previewPages = Number.parseInt(IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE), 10);
    line = IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE);
    if (version !== 1) {
      spiderInfo.previewPerPage = Number.parseInt(line, 10);
    }
    spiderInfo.pages = Number.parseInt(IOUtils.readAsciiLine(is, MAX_SPIDER_INFO_HEADER_LINE), 10);
    if (spiderInfo.pages <= 0 || spiderInfo.pages > MAX_SPIDER_INFO_PAGES) {
      return null;
    }
    return spiderInfo;
  }

  private static readPTokens(raw: InputStream, spiderInfo: SpiderInfo): void {
    const is: InputStreamLike = new StreamAdapter(raw);
    const map: Map<number, string> = new Map<number, string>();
    spiderInfo.pTokenMap = map;
    for (let linesRead = 0; linesRead < spiderInfo.pages; linesRead++) {
      let line: string;
      try {
        line = IOUtils.readAsciiLine(is, MAX_PTOKEN_FILE_LINE);
      } catch (e) {
        // 对位上游 catch (EOFException) → break（IOUtils.readAsciiLine 在 EOF 抛 EOFException）
        break;
      }
      const parsed: PTokenLine | null = SpiderInfo.tryParsePTokenLine(line);
      if (parsed !== null) {
        map.set(parsed.index, parsed.pToken);
      } else if (line.indexOf(' ') <= 0) {
        Utils.logE(TAG, `Can't parse index and pToken, index = ${line.indexOf(' ')}`);
      } else {
        // 损坏的行：跳过，保留已解析的头部
        Utils.logW(TAG, `Skip bad pToken line: ${line}`);
      }
    }
  }

  /**
   * 对位 `tryParsePTokenLine(String, int[])`。
   * ArkTS 没有出参，改为返回 `PTokenLine | null`（null = 跳过该行）。
   */
  static tryParsePTokenLine(line: string): PTokenLine | null {
    const pos: number = line.indexOf(' ');
    if (pos <= 0) {
      return null;
    }
    const index: number = Number.parseInt(line.substring(0, pos), 10);
    if (Number.isNaN(index)) {
      return null;
    }
    const pToken: string = line.substring(pos + 1);
    if (pToken.length === 0 || pToken.length > MAX_STORED_PTOKEN_CHARS) {
      return null;
    }
    return new PTokenLine(index, pToken);
  }

  // ---------------------------------------------------------------- 写

  /** 对位 `write(OutputStream)`：格式与上游逐字节一致（含 %08x 的 startPage）。 */
  write(os: OutputStream): void {
    const sb: string[] = [];
    sb.push(VERSION_STR);
    sb.push(`${VERSION}`);
    sb.push('\n');
    // 上游用 %08x（小写十六进制、宽度 8、左补零）
    sb.push(padHex8(Math.max(this.startPage, 0)));
    sb.push('\n');
    sb.push(`${this.gid}`);
    sb.push('\n');
    sb.push(this.token !== null ? this.token : '');
    sb.push('\n');
    sb.push('1');
    sb.push('\n');
    sb.push(`${this.previewPages}`);
    sb.push('\n');
    sb.push(`${this.previewPerPage}`);
    sb.push('\n');
    sb.push(`${this.pages}`);
    sb.push('\n');
    const map: Map<number, string> | null = this.pTokenMap;
    if (map !== null) {
      // 上游 SparseArray 按 key 升序迭代 → 这里显式排序
      const keys: number[] = [];
      map.forEach((value: string, key: number) => {
        keys.push(key);
      });
      keys.sort((a: number, b: number): number => a - b);
      for (const key of keys) {
        const value: string = map.get(key) as string;
        if (SpiderInfo.TOKEN_FAILED === value || value.length === 0) {
          continue;
        }
        sb.push(`${key}`);
        sb.push(' ');
        sb.push(value);
        sb.push('\n');
      }
    }
    try {
      const bytes: Uint8Array = utf8Encode(sb.join(''));
      const buf: ArrayBuffer = bytes.buffer.slice(0, bytes.byteLength);
      os.write(buf);
      os.flush();
    } catch (e) {
      Utils.throwIfFatal(e);
      // 上游 catch (IOException) 后忽略
    } finally {
      Utils.closeQuietly(os);
    }
  }

  /** 对位 `updateSpiderInfo(SpiderInfo)`：整体覆盖头部 + pTokenMap。 */
  updateSpiderInfo(newInfo: SpiderInfo): void {
    this.pages = newInfo.pages;
    this.gid = newInfo.gid;
    this.token = newInfo.token;
    this.pTokenMap = newInfo.pTokenMap;
    this.previewPerPage = newInfo.previewPerPage;
    this.previewPages = newInfo.previewPages;
  }

  /**
   * 对位 `writeNewSpiderInfoToLocal(SpiderDen, Context)`：
   * ① `downloadDir` 非空时写下载目录 `.ehviewer`；
   * ② 同步回写 `SpiderInfoCache`（key 为 `gid`）。
   */
  writeNewSpiderInfoToLocal(downloadDir: UniFile | null, cacheOverride?: SimpleDiskCache | null): void {
    if (downloadDir !== null) {
      const file: UniFile | null = downloadDir.createFile(SPIDER_INFO_FILENAME);
      if (file !== null) {
        try {
          this.write(file.openOutputStream());
        } catch (e) {
          Utils.throwIfFatal(e);
        }
      }
    }
    const cache: SimpleDiskCache | null = cacheOverride !== undefined
      ? cacheOverride
      : (SpiderInfo.cacheProvider !== null ? SpiderInfo.cacheProvider.getSpiderInfoCache() : null);
    if (cache === null || this.gid < 0) {
      return;
    }
    const pipe: OutputStreamPipe | null = cache.getOutputStreamPipe(`${this.gid}`);
    if (pipe === null) {
      return;
    }
    let committed: boolean = false;
    let obtained: boolean = false;
    try {
      pipe.obtain();
      obtained = true;
      const sink: ByteSink = pipe.open();
      this.write(new ByteSinkOutputStream(sink));
      committed = true;
    } catch (e) {
      Utils.throwIfFatal(e);
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
    }
  }

  // ---------------------------------------------------------------- 工厂

  /**
   * 对位 `getSpiderInfo(GalleryInfo)`：从下载目录读头部，并校验 gid/token 与图库一致。
   * 不一致（图库被改过）返回 null —— 上游行为一致。
   */
  static getSpiderInfoByGalleryInfo(info: GalleryInfo): SpiderInfo | null {
    const provider: DownloadDirProvider | null = SpiderInfo.dirProvider;
    if (provider === null) {
      throw new Error(
        '[SpiderInfo] DownloadDirProvider 未注入：SpiderDen（S0178）落地后需在其 initialize() 里调用 ' +
        'SpiderInfo.setDownloadDirProvider(...)');
    }
    const downloadDir: UniFile | null = provider.getGalleryDownloadDir(info);
    if (downloadDir !== null && downloadDir.isDirectory()) {
      const file: UniFile | null = downloadDir.findFile(SPIDER_INFO_FILENAME);
      const spiderInfo: SpiderInfo | null = SpiderInfo.readHeaderFile(file);
      if (spiderInfo !== null && spiderInfo.gid === info.gid &&
        spiderInfo.token === info.token) {
        return spiderInfo;
      }
    }
    return null;
  }

  /**
   * 对位 `getSpiderInfo(GalleryDetail)`：从详情页的 SpiderInfoPages / PreviewPages / PreviewSet 构造，
   * 并调用 `GalleryPageUrlParser.parse()` 提取首屏 pToken。
   */
  static getSpiderInfoByGalleryDetail(info?: GalleryDetail | null): SpiderInfo | null {
    if (info === null || info === undefined) {
      return null;
    }
    const pages: number = info.SpiderInfoPages > 0 ? info.SpiderInfoPages : info.pages;
    if (pages <= 0 || pages > MAX_SPIDER_INFO_PAGES) {
      return null;
    }
    const spiderInfo: SpiderInfo = new SpiderInfo();
    spiderInfo.gid = info.gid;
    spiderInfo.token = info.token;
    spiderInfo.pages = pages;
    spiderInfo.previewPages = info.SpiderInfoPreviewPages > 0
      ? info.SpiderInfoPreviewPages
      : info.previewPages;
    spiderInfo.pTokenMap = new Map<number, string>();
    const previewSet: PreviewSet | null = info.SpiderInfoPreviewSet !== null
      ? info.SpiderInfoPreviewSet
      : info.previewSet;
    if (previewSet !== null) {
      SpiderInfo.readPreviews(previewSet, 0, spiderInfo);
    }
    return spiderInfo;
  }

  /** 对位上游 `readPreviews(GalleryDetail, int index, SpiderInfo)`：写入每页预览 pToken 与每页预览数。 */
  static readPreviews(previewSet: PreviewSet, index: number, spiderInfo: SpiderInfo): void {
    const count: number = previewSet.size();
    if (count > 0) {
      if (index === 0) {
        spiderInfo.previewPerPage = count;
      } else {
        spiderInfo.previewPerPage = Math.trunc(previewSet.getPosition(0) / index);
      }
    }
    if (spiderInfo.pTokenMap === null) {
      spiderInfo.pTokenMap = new Map<number, string>();
    }
    for (let i = 0; i < count; i++) {
      const result: PageUrlResult | null = GalleryPageUrlParser.parse(previewSet.getPageUrlAt(i));
      if (result !== null) {
        spiderInfo.pTokenMap.set(result.page, result.pToken);
      }
    }
  }

  // ---------------------------------------------------------------- 工具

  /** 当前已成功获取的 pToken 数量（对位下游常用 `pTokenMap.size()` 的只读入口）。 */
  getPTokenCount(): number {
    const map: Map<number, string> | null = this.pTokenMap;
    return map !== null ? map.size : 0;
  }
}

/** 对位上游 `tryParsePTokenLine` 的 `int[] indexOut` 出参（ArkTS 用值对象）。 */
export class PTokenLine {
  readonly index: number;
  readonly pToken: string;

  constructor(index: number, pToken: string) {
    this.index = index;
    this.pToken = pToken;
  }
}

/** Java `String.format("%08x", v)` 的等价实现（小写十六进制、宽度 8、左补 0）。 */
function padHex8(value: number): string {
  let hex: string = Math.trunc(value).toString(16);
  while (hex.length < 8) {
    hex = `0${hex}`;
  }
  return hex;
}

/** 字符串 → UTF-8 字节（ArkTS 无 OutputStreamWriter）。 */
function utf8Encode(s: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let c: number = s.charCodeAt(i);
    if (c < 0x80) {
      bytes.push(c);
    } else if (c < 0x800) {
      bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      const c2: number = s.charCodeAt(i + 1);
      const cp: number = 0x10000 + ((c - 0xd800) << 10) + (c2 - 0xdc00);
      bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
      i++;
    } else {
      bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  const out: Uint8Array = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] & 0xff;
  }
  return out;
}


/**
 * 把 `unifile/Contracts.InputStream` 适配成 `IOUtils.InputStreamLike`。
 *
 * 为什么需要：两份契约的方法名不同 ——
 *   Contracts.InputStream : read() / readBuffer(ArrayBuffer) / readBytes(b, off, len)
 *   IOUtils.InputStreamLike: read(buffer: ArrayBuffer): number
 * ArkTS 没有结构化类型，不能直接把前者传给 `IOUtils.readAsciiLine`；
 * 这个适配器是唯一的转换点（一行委托，无缓冲、无拷贝）。
 */
class StreamAdapter implements InputStreamLike {
  private readonly src: InputStream;

  constructor(src: InputStream) {
    this.src = src;
  }

  read(buffer: ArrayBuffer): number {
    return this.src.readBuffer(buffer);
  }
}

/** 将 SimpleDiskCache 的 ByteSink 适配为 unifile 的 OutputStream（用于回写 SpiderInfoCache）。 */
class ByteSinkOutputStream implements OutputStream {
  private readonly sink: ByteSink;

  constructor(sink: ByteSink) {
    this.sink = sink;
  }

  write(buffer: ArrayBuffer): void {
    this.sink.write(buffer);
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    const avail: number = buffer.byteLength - off;
    const realLen: number = len < avail ? len : avail;
    if (realLen <= 0) {
      return;
    }
    this.sink.write(buffer.slice(off, off + realLen));
  }

  flush(): void {
  }

  close(): void {
    this.sink.close();
  }
}