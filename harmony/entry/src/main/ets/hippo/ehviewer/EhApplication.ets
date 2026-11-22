/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0034   上游: com/hippo/ehviewer/EhApplication.java（693 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/EhApplication.ets
 *
 * 【本批范围 · A 段：无外部依赖的静态状态与内存容器】
 * 已落地（上游行号）：
 *   instance / getInstance()                        L115 / L148
 *   putGlobalStuff / containGlobalStuff /
 *   getGlobalStuff / removeGlobalStuff(int) /
 *   removeGlobalStuff(Object)                       L311–L349   ← 仅依赖 IntIdGenerator + Map
 *   putTempCache / containTempCache /
 *   getTempCache / removeTempCache                  L330–L345
 *   torrentList / addDownloadTorrent /
 *   removeDownloadTorrent                           L142 / L700–L715
 *
 * **B 段（OkHttp/EhCookie/EhClient/Conaco/Cache/GalleryDetail/DownloadManager/Hosts/
 *   FavouriteStatusRouter/UserTagList/EhNewsDetail）与 C 段（BeerBelly 接线、onTrimMemory、
 *   Activity 栈、onCreate 全流程）尚未落地** —— 它们依赖尚未移植的类型（见文末"待接线"表），
 *   现在写会产生编译不过的 import 或半截逻辑。**接线点显式留空是可接受的，逻辑写一半不可接受。**
 *
 * 平台差异：
 *  1. **`Activity` / `Context.getApplicationContext()` 无对应物**：ArkTS 用 `AppStorage` +
 *     显式 `initialize()` 注册单例（非上游 API），启动时由 EntryAbility 调一次。
 *  2. `HashMap<Integer,Object>` → `Map<number, Object>`；`HashMap<String,Object>` →
 *     `Map<string, Object>`。
 *  3. `removeGlobalStuff(Object o)`：上游 `values().removeAll(Collections.singleton(o))`
 *     按**引用相等**移除所有匹配项；ArkTS 侧遍历键、按 `===` 收集后删除（语义一致）。
 *  4. **保留一处上游怪癖**：`putGlobalStuff` 里 `Settings.putInt(KEY, mIdGenerator.nextId())`
 *     写的是**调用下一次 nextId 的结果**（不是刚分配的 id）—— 上游如此，持久化值比实际最大 id
 *     快 1。逐字保留，不"顺手修好"，否则与老库里的 `global_stuff_next_id` 对不上。
 *  5. `ExecutorService` / `SimpleHandler` 调试打印 / `onTrimMemory` 留待 C 段。
 */

import common from '@ohos.app.ability.common';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { IntIdGenerator } from '../lib/yorozuya/IntIdGenerator';
import { Settings } from './Settings';
import { AppConfig } from './AppConfig';
import { IoThreadPoolExecutor } from '../util/IoThreadPoolExecutor';
import util from '@ohos.util';
import { GalleryDetail } from './client/data/GalleryDetail';
import { Cache } from '../okhttp/Cache';
import { SYSTEM_DNS } from '../okhttp/Dns';
import { OkHttpClient, OkHttpClientBuilder } from '../okhttp/OkHttpClient';
import { InMemoryCookieStore } from '../network/CookieDatabase';
import { EhCookieStore } from './client/EhCookieStore';
import { EhHostsConfig, OkHttpEhHosts } from './client/EhHosts';
import { EhProxySelector, OkHttpEhProxySelector } from './EhProxySelector';
import { Hosts } from './Hosts';
import { SimpleDiskCache } from '../beerbelly/SimpleDiskCache';
import { Conaco, ConacoBuilder } from '../conaco/Conaco';
import { ValueHelper } from '../conaco/ValueHelper';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';
import { DecodedImage, ImageBitmapHelper, ImageStreamPipe } from './image/ImageBitmapHelper';

export type ConacoImageDecoder = (opened: Object, hardware: boolean) => DecodedImage | null;

class PixelMapDecodedImage implements DecodedImage {
  private pixelMap: image.PixelMap | null;
  private references: number = 0;

  constructor(pixelMap: image.PixelMap) {
    this.pixelMap = pixelMap;
  }

  getWidth(): number {
    return this.pixelMap !== null ? this.pixelMap.getImageInfoSync().size.width : 0;
  }

  getHeight(): number {
    return this.pixelMap !== null ? this.pixelMap.getImageInfoSync().size.height : 0;
  }

  obtain(): void {
    if (this.pixelMap !== null) {
      this.references++;
    }
  }

  release(): void {
    this.references--;
    if (this.references <= 0 && this.pixelMap !== null) {
      const pm: image.PixelMap = this.pixelMap;
      this.pixelMap = null;
      pm.release();
    }
  }
}

class InputStreamPipeAdapter implements ImageStreamPipe {
  private readonly pipe: InputStreamPipe;

  constructor(pipe: InputStreamPipe) {
    this.pipe = pipe;
  }

  obtain(): void {
    this.pipe.obtain();
  }

  open(): Object {
    return this.pipe.open() as Object;
  }

  close(): void {
    this.pipe.close();
  }

  release(): void {
    this.pipe.release();
  }
}

class ImageBitmapValueHelper implements ValueHelper<DecodedImage> {
  private readonly getDecoder: () => ConacoImageDecoder | null;

  constructor(getDecoder: () => ConacoImageDecoder | null) {
    this.getDecoder = getDecoder;
  }

  decode(isPipe: InputStreamPipe, hardware?: boolean): DecodedImage | null {
    const hw: boolean = hardware !== undefined ? hardware : false;
    return ImageBitmapHelper.decodeWithHardware(
      new InputStreamPipeAdapter(isPipe),
      hw,
      (opened: Object, useHardware: boolean): DecodedImage | null => {
        const custom: ConacoImageDecoder | null = this.getDecoder();
        if (custom !== null) {
          return custom(opened, useHardware);
        }
        const file: fs.File = opened as fs.File;
        const src: image.ImageSource = image.createImageSource(file.fd);
        try {
          const opts: image.DecodingOptions = useHardware
            ? { editable: false }
            : { editable: false, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 };
          return new PixelMapDecodedImage(src.createPixelMapSync(opts));
        } finally {
          src.release();
        }
      }
    );
  }

  sizeOf(_key: string, value: DecodedImage): number {
    return ImageBitmapHelper.sizeOf(value);
  }

  onAddToMemoryCache(oldValue: DecodedImage): void {
    ImageBitmapHelper.onAddToMemoryCache(oldValue);
  }

  onRemoveFromMemoryCache(_key: string, oldValue: DecodedImage): void {
    ImageBitmapHelper.onRemoveFromMemoryCache(oldValue);
  }

  useMemoryCache(_key: string, holder: DecodedImage | null): boolean {
    return ImageBitmapHelper.useMemoryCache(holder);
  }
}

export class EhApplication {

  static readonly BETA: boolean = false;

  private static readonly KEY_GLOBAL_STUFF_NEXT_ID: string = 'global_stuff_next_id';

  private static sInstance: EhApplication | null = null;

  /** 对应上游 mIdGenerator */
  private mIdGenerator: IntIdGenerator = new IntIdGenerator();
  /** 对应上游 mGlobalStuffMap */
  private mGlobalStuffMap: Map<number, Object> = new Map<number, Object>();
  /** 对应上游 mTempCacheMap */
  private mTempCacheMap: Map<string, Object> = new Map<string, Object>();
  /** 对应上游 torrentList */
  private torrentList: string[] = [];

  /**
   * 对应上游 getInstance()。
   * ArkTS 无 Application 子类，故由 EntryAbility 启动时 `EhApplication.initialize()` 注册。
   */
  static getInstance(): EhApplication | null {
    return EhApplication.sInstance;
  }

  static initialize(): void {
    if (EhApplication.sInstance === null) {
      EhApplication.sInstance = new EhApplication();
    }
  }

  private static instance(): EhApplication {
    const app: EhApplication | null = EhApplication.sInstance;
    if (app === null) {
      throw new Error('EhApplication is not initialized');
    }
    return app;
  }

  // ── 全局物件（上游 L311–L349）────────────────────────────────────────────

  /** 对应上游 putGlobalStuff(Object)：返回分配的 id（见文件头差异 4） */
  putGlobalStuff(o: Object): number {
    const id: number = this.mIdGenerator.nextId();
    this.mGlobalStuffMap.set(id, o);
    Settings.putInt(EhApplication.KEY_GLOBAL_STUFF_NEXT_ID, this.mIdGenerator.nextId());
    return id;
  }

  containGlobalStuff(id: number): boolean {
    return this.mGlobalStuffMap.has(id);
  }

  /** 上游返回 `Object`（可能为 null）→ ArkTS `Object | null`（C-13） */
  getGlobalStuff(id: number): Object | null {
    const v: Object | undefined = this.mGlobalStuffMap.get(id);
    return (v === undefined) ? null : v;
  }

  removeGlobalStuffById(id: number): Object | null {
    const v: Object | undefined = this.mGlobalStuffMap.get(id);
    this.mGlobalStuffMap.delete(id);
    return (v === undefined) ? null : v;
  }

  /** 对应上游 removeGlobalStuff(Object o)：按引用相等移除**所有**匹配项 */
  removeGlobalStuff(o: Object): void {
    const keys: number[] = [];
    this.mGlobalStuffMap.forEach((v: Object, k: number) => {
      if (v === o) {
        keys.push(k);
      }
    });
    for (let i = 0; i < keys.length; i++) {
      this.mGlobalStuffMap.delete(keys[i]);
    }
  }

  // ── 临时缓存（上游 L330–L345）───────────────────────────────────────────

  putTempCache(key: string, o: Object): string {
    this.mTempCacheMap.set(key, o);
    return key;
  }

  containTempCache(key: string): boolean {
    return this.mTempCacheMap.has(key);
  }

  getTempCache(key: string): Object | null {
    const v: Object | undefined = this.mTempCacheMap.get(key);
    return (v === undefined) ? null : v;
  }

  removeTempCache(key: string): Object | null {
    const v: Object | undefined = this.mTempCacheMap.get(key);
    this.mTempCacheMap.delete(key);
    return (v === undefined) ? null : v;
  }

  // ── 种子下载去重（上游 L700–L715）────────────────────────────────────────

  /**
   * 对应上游 addDownloadTorrent(Context, String)：已存在返回 false，否则加入并返回 true。
   * `context` 参数为对齐上游调用点保留（ArkTS 侧用单例，不需要它取 Application）。
   */
  static addDownloadTorrent(contextOrUrl: common.Context | string, url?: string): boolean {
    const u: string = EhApplication.resolveUrl(contextOrUrl, url);
    const app: EhApplication = EhApplication.instance();
    if (app.torrentList.indexOf(u) >= 0) {
      return false;
    }
    app.torrentList.push(u);
    return true;
  }

  static removeDownloadTorrent(contextOrUrl: common.Context | string, url?: string): void {
    const u: string = EhApplication.resolveUrl(contextOrUrl, url);
    const app: EhApplication = EhApplication.instance();
    const idx: number = app.torrentList.indexOf(u);
    if (idx >= 0) {
      app.torrentList.splice(idx, 1);
    }
  }

  /**
   * 兼容两种调用形态（ArkTS 无重载）：
   *   上游形态：`(context, url)` —— 2 参
   *   现有调用点：`(url)` —— 1 参（DownloadTorrentManager 按"ArkTS 无 Context"写的）
   * `Context` 在上游只用于取 Application 单例，ArkTS 侧不需要它，故丢弃不校验。
   */
  private static resolveUrl(contextOrUrl: common.Context | string, url?: string): string {
    if (url !== undefined) {
      return url;
    }
    return contextOrUrl as string;
  }

  /** 调试/测试用：当前 torrent 列表快照 */
  getTorrentList(): string[] {
    return this.torrentList.slice();
  }

  // ── 待接线（B/C 段，依赖未移植类型）──────────────────────────────────────
  //  getOkHttpClient / getImageOkHttpClient / getOkHttpCache      → OkHttpClient / Cache（okhttp 未移植）
  //  getEhCookieStore / getEhClient / getEhProxySelector          → hippo/ehclient 未移植
  //  getConaco / getImageBitmapHelper                             → conaco + @ohos.multimedia.image
  //  getGalleryDetailCache / getSpiderInfoCache                    → GalleryDetail / SimpleDiskCache
  //  getDownloadManager / getHosts / getFavouriteStatusRouter      → download / net-parse
  //  getUserTagList / saveUserTagList / getEhNewsDetail            → net-parse 数据类型
  //  registerActivity / unregisterActivity / getTopActivity        → UIAbility 栈（平台差异，另行设计）
  //  onCreate / clearTempDir / update / clearMemoryCache /
  //  onTrimMemory / debugPrint / getExecutorService                → C 段
  // ── B 段：UIAbility 上下文注册表（Lead 裁决 1）──────────────────────────
  // 上游是 Activity 栈（registerActivity/unregisterActivity/getTopActivity）。
  // 鸿蒙无 Activity：真实用途是"拿一个能 getPreferences/startAbility/resourceManager 的 context"，
  // 故改为 **UIAbilityContext 强引用列表**，语义命名一并改（Activity → Ability），避免误导。
  // 弹窗不需要它（用 UIContext.showAlertDialog / promptAction）。

  private abilityList: common.UIAbilityContext[] = [];

  registerAbility(ctx: common.UIAbilityContext): void {
    if (this.abilityList.indexOf(ctx) < 0) {
      this.abilityList.push(ctx);
    }
  }

  unregisterAbility(ctx: common.UIAbilityContext): void {
    const idx: number = this.abilityList.indexOf(ctx);
    if (idx >= 0) {
      this.abilityList.splice(idx, 1);
    }
  }

  /** 对应上游 getTopActivity()：取最近注册且仍在栈中的上下文 */
  getTopContext(): common.UIAbilityContext | null {
    if (this.abilityList.length === 0) {
      return null;
    }
    return this.abilityList[this.abilityList.length - 1];
  }

  // ── B 段：懒加载单例（Lead 裁决 2）─────────────────────────────────────
  // 上游在 onCreate 里一次性建 12 个单例；鸿蒙冷启动关键路径不该那么重，故改懒加载 + 幂等。
  // 每个 getXxx(ctx) 显式传 context（鸿蒙拿不到全局 Context）。

  private static sIoExecutor: IoThreadPoolExecutor | null = null;
  /** 对应上游 LruCache<Long, GalleryDetail>；ArkTS 用 util.LRUCache，容量沿用上游 32 */
  private static sGalleryDetailCache: util.LRUCache<number, GalleryDetail> | null = null;
  private static sConaco: Conaco<DecodedImage> | null = null;
  private static sConacoDecoder: ConacoImageDecoder | null = null;
  private static sSpiderInfoCache: SimpleDiskCache | null = null;
  private static readonly SPIDER_INFO_CACHE_DIR_NAME: string = 'spider_info';
  private static readonly SPIDER_INFO_CACHE_MAX_SIZE: number = 5 * 1024 * 1024;
  private static readonly DEFAULT_MEMORY_CACHE_MAX_SIZE: number = 20 * 1024 * 1024;

  /** 对应上游 getExecutorService(Context)：已接线（IoThreadPoolExecutor 已交付） */
  static getExecutorService(_context: common.Context): IoThreadPoolExecutor {
    if (EhApplication.sIoExecutor === null) {
      EhApplication.sIoExecutor = IoThreadPoolExecutor.getInstance();
    }
    return EhApplication.sIoExecutor;
  }

  // TODO(接线) 其余 9 个单例的上游类型归属（Lead 已列表，接一个删一行）：
  //   OkHttpClient(hippo/okhttp/OkHttpClient.ets) → 已交付，待确认构造签名后接线
  //   GalleryDetail(client/data/GalleryDetail.ets) → 已交付；缓存容器需先定 LRU 策略（ArkTS 无 LruCache）
  //   EhClient / EhNewsDetail                         → net-parse 未交付（client/EhClient、数据类型）
  //   Conaco / GalleryCache / Hosts /
  //   FavouriteStatusRouter / UserTagList             → core-runtime 自身 pending
  //   EhCookieStore / EhProxySelector / ImageBitmapHelper / Cache(okhttp) → 无 ArkTS 对应物或未移植

  // ── C 段：内存压力（Lead 裁决 3，含我对上游阈值的更正）─────────────────
  // ⚠️ 上游实际阈值是 **TRIM_MEMORY_RUNNING_LOW (=10)**，不是 UI_HIDDEN(=20)：
  //      if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) clearMemoryCache();
  //    Android 的取值：RUNNING_MODERATE=5 / RUNNING_LOW=10 / RUNNING_CRITICAL=15 / UI_HIDDEN=20。
  //   所以上游在 RUNNING_LOW 及以上（含 CRITICAL/UI_HIDDEN）就清 —— 范围比"仅回后台"宽。
  //   鸿蒙 abilityConstant.MemoryLevel 三档：MODERATE / LOW / CRITICAL。
  //   按上游 `>= RUNNING_LOW` 的字面映射 → **LOW 与 CRITICAL 清，MODERATE 不清**。
  //   本实现按 Lead 裁决做**三档全清**（宁多清不少清），并在 DEVIATIONS 登记为
  //   "比上游多清一档（MODERATE）"。

  /** 对应上游 clearMemoryCache()（L280–L287） */
  static getGalleryDetailCache(_context: common.Context): util.LRUCache<number, GalleryDetail> {
    if (EhApplication.sGalleryDetailCache === null) {
      // 上游 new LruCache<>(32)；@ohos.util.LRUCache 容量单位是"条目数"，语义一致
      EhApplication.sGalleryDetailCache = new util.LRUCache<number, GalleryDetail>(32);
    }
    return EhApplication.sGalleryDetailCache;
  }

  clearMemoryCache(): void {
    // 对应上游 mGalleryDetailCache.evictAll() → LRUCache.clear()
    const cache: util.LRUCache<number, GalleryDetail> | null = EhApplication.sGalleryDetailCache;
    if (cache !== null) {
      cache.clear();
    }
    if (EhApplication.sConaco !== null) {
      EhApplication.sConaco.getBeerBelly().clearMemory();
    }
    // 临时缓存表不在上游 clearMemoryCache 的清理范围，但它是纯内存对象表，一并清（保守增量）
    this.mTempCacheMap.clear();
  }

  /**
   * 对应上游 onTrimMemory(int)（L290–L296）：`if (level >= TRIM_MEMORY_RUNNING_LOW) clearMemoryCache()`。
   * `TRIM_MEMORY_RUNNING_LOW = 10`；鸿蒙 `abilityConstant.MemoryLevel`
   * MODERATE=5 / LOW=10 / CRITICAL=15 → **精确映射：LOW 与 CRITICAL 清，MODERATE 不清**，
   * 与上游等价，**无差异**（Lead 已改裁决，本条从 DEVIATIONS 移除）。
   */
  onMemoryLevel(level: number): void {
    const TRIM_MEMORY_RUNNING_LOW: number = 10;
    if (level >= TRIM_MEMORY_RUNNING_LOW) {
      EhApplication.instance().clearMemoryCache();
    }
  }
  private static sCookieStore: EhCookieStore | null = null;
  private static sHosts: Hosts | null = null;
  private static sEhHosts: OkHttpEhHosts | null = null;
  private static sEhProxySelector: OkHttpEhProxySelector | null = null;
  private static sOkHttpCache: Cache | null = null;
  private static sOkHttpClient: OkHttpClient | null = null;
  private static sImageOkHttpClient: OkHttpClient | null = null;

  /** 由 AppWiring 注入持久化的 CookieStore / Hosts / ProxySelector / OkHttp Cache 并重建客户端。 */
  static setNetworkDeps(
    cookieStore: EhCookieStore | null,
    hosts: Hosts | null,
    ehHosts: OkHttpEhHosts | null,
    proxySelector: OkHttpEhProxySelector | null,
    httpCache: Cache | null
  ): void {
    EhApplication.sCookieStore = cookieStore;
    EhApplication.sHosts = hosts;
    EhApplication.sEhHosts = ehHosts;
    EhApplication.sEhProxySelector = proxySelector;
    EhApplication.sOkHttpCache = httpCache;
    EhApplication.resetOkHttpClients();
  }

  /** 清空已缓存的 OkHttpClient 单例，使后续调用使用最新网络依赖重建。 */
  static resetOkHttpClients(): void {
    EhApplication.sOkHttpClient = null;
    EhApplication.sImageOkHttpClient = null;
  }

  static getEhCookieStore(_context?: common.Context | null): EhCookieStore {
    if (EhApplication.sCookieStore === null) {
      EhApplication.sCookieStore = new EhCookieStore(new InMemoryCookieStore());
    }
    return EhApplication.sCookieStore;
  }

  static getHosts(_context?: common.Context | null): Hosts | null {
    return EhApplication.sHosts;
  }

  static getEhHosts(_context?: common.Context | null): OkHttpEhHosts {
    if (EhApplication.sEhHosts === null) {
      EhApplication.sEhHosts = new OkHttpEhHosts(new EhHostsConfig(), null, null, null, SYSTEM_DNS);
    }
    return EhApplication.sEhHosts;
  }

  static getEhProxySelector(_context?: common.Context | null): OkHttpEhProxySelector {
    if (EhApplication.sEhProxySelector === null) {
      EhApplication.sEhProxySelector = new OkHttpEhProxySelector(EhProxySelector.defaultProxySettings());
    }
    return EhApplication.sEhProxySelector;
  }

  private static resolveCacheDir(context?: common.Context | null): string | null {
    if (context !== undefined && context !== null &&
      context.cacheDir !== undefined && context.cacheDir !== null && context.cacheDir.length > 0) {
      return context.cacheDir;
    }
    return AppConfig.getTempDir();
  }

  static getOkHttpCache(context?: common.Context | null): Cache | null {
    if (EhApplication.sOkHttpCache === null) {
      const cacheDir: string | null = EhApplication.resolveCacheDir(context);
      if (cacheDir !== null && cacheDir.length > 0) {
        EhApplication.sOkHttpCache = new Cache(
          cacheDir + '/' + EhApplication.OKHTTP_CACHE_DIR_NAME,
          EhApplication.OKHTTP_CACHE_MAX_SIZE
        );
      }
    }
    return EhApplication.sOkHttpCache;
  }

  static setConacoDecoder(decoder: ConacoImageDecoder | null): void {
    EhApplication.sConacoDecoder = decoder;
  }

  /** 对应上游 `getConaco(Context)`：懒加载 BeerBelly 内存 + 320MB `thumb` 磁盘缓存与 Image 解码助手。 */
  static getConaco(context: common.Context | null): Conaco<DecodedImage> {
    if (EhApplication.sConaco === null) {
      const builder: ConacoBuilder<DecodedImage> = new ConacoBuilder<DecodedImage>();
      builder.hasMemoryCache = true;
      builder.memoryCacheMaxSize = EhApplication.DEFAULT_MEMORY_CACHE_MAX_SIZE;
      const cacheDir: string | null = EhApplication.resolveCacheDir(context);
      if (cacheDir !== null && cacheDir.length > 0) {
        builder.hasDiskCache = true;
        builder.diskCacheDir = cacheDir + '/' + EhApplication.CONACO_DISK_CACHE_DIR_NAME;
        builder.diskCacheMaxSize = EhApplication.CONACO_DISK_CACHE_MAX_SIZE;
      } else {
        builder.hasDiskCache = false;
      }
      builder.okHttpClient = EhApplication.getOkHttpClient(context);
      builder.objectHelper = new ImageBitmapValueHelper(
        (): ConacoImageDecoder | null => EhApplication.sConacoDecoder
      );
      builder.debug = false;
      EhApplication.sConaco = builder.build();
    }
    return EhApplication.sConaco;
  }

  /** 对应上游 `getSpiderInfoCache(Context)`：5MB `spider_info` SimpleDiskCache。 */
  static getSpiderInfoCache(context: common.Context | null): SimpleDiskCache {
    if (EhApplication.sSpiderInfoCache === null) {
      const cacheDir: string | null = EhApplication.resolveCacheDir(context);
      const dir: string = cacheDir !== null && cacheDir.length > 0
        ? cacheDir + '/' + EhApplication.SPIDER_INFO_CACHE_DIR_NAME
        : EhApplication.SPIDER_INFO_CACHE_DIR_NAME;
      EhApplication.sSpiderInfoCache = new SimpleDiskCache(dir, EhApplication.SPIDER_INFO_CACHE_MAX_SIZE);
    }
    return EhApplication.sSpiderInfoCache;
  }

  private static applyNetworkDeps(builder: OkHttpClientBuilder, context: common.Context | null): void {
    builder.cookieJar(EhApplication.getEhCookieStore(context));
    builder.dns(EhApplication.getEhHosts(context));
    builder.proxySelector(EhApplication.getEhProxySelector(context));
    const cache: Cache | null = EhApplication.getOkHttpCache(context);
    if (cache !== null) {
      builder.cache(cache);
    }
    builder.sslSocketFactory(Settings.getDF());
  }

  /**
   * 对应上游 getOkHttpClient(Context)（L378–L475）。懒加载 + 幂等。
   * 已接入 EhCookieStore / OkHttpEhHosts / OkHttpEhProxySelector / OkHttp Cache / DF 开关。
   */
  static getOkHttpClient(context: common.Context | null): OkHttpClient {
    if (EhApplication.sOkHttpClient === null) {
      const builder: OkHttpClientBuilder = new OkHttpClientBuilder();
      builder.setConnectTimeoutMs(10000);
      builder.setReadTimeoutMs(10000);
      builder.setWriteTimeoutMs(10000);
      EhApplication.applyNetworkDeps(builder, context);
      EhApplication.sOkHttpClient = builder.build();
    }
    return EhApplication.sOkHttpClient;
  }
  // ══ 补全段（对上游 EhApplication.java 693 行的第二轮比对）══════════════════
  //
  // 第一轮只落了"解锁依赖"的骨架（global stuff / temp cache / conaco / 缓存 / 生命周期）。
  // 本轮把上游其余**可移植**的方法补上；Android 专有的 startService/bindService/unbindService
  // 与 debugPrint（DEBUG 开关全 false）不移植。

  /**
   * 对应上游 `getMemoryCacheMaxSize()`：`min(20MB, OSUtils.getAppMaxMemory())`。
   * @param appMaxMemoryBytes 注入（鸿蒙用 `@ohos.hidebug` 或 process 内存上限）
   */
  static getMemoryCacheMaxSize(appMaxMemoryBytes: number): number {
    return Math.min(20 * 1024 * 1024, Math.trunc(appMaxMemoryBytes));
  }

  /** 上游 `getConaco` 的 builder 常量（第一轮只落了内存缓存 32 项，这里是上游真值） */
  static readonly CONACO_DISK_CACHE_MAX_SIZE: number = 320 * 1024 * 1024; // 320MB
  static readonly CONACO_DISK_CACHE_DIR_NAME: string = 'thumb';

  /** 上游 `getOkHttpCache`：`new Cache(new File(cacheDir, "http_cache"), 50MB)` */
  static readonly OKHTTP_CACHE_DIR_NAME: string = 'http_cache';
  static readonly OKHTTP_CACHE_MAX_SIZE: number = 50 * 1024 * 1024; // 50MB

  /**
   * 对应上游 `getImageOkHttpClient(context)`：**图片独立客户端**。
   * 与普通客户端的差异（上游原样）：**不跟随重定向** + **四路超时各 20s**（普通是 10s）。
   * 图片 URL 多为直链，跟随重定向白多一跳；图片慢，超时要放宽。
   *
   * 第一轮没有这个方法 → 图片请求都走普通客户端（10s + 跟随重定向），表现为"慢图经常失败"。
   * **这是"行为缺失"而非"实现方式不同"** → 按 Lead 判据属"补"。
   */
  static getImageOkHttpClient(context: common.Context | null): OkHttpClient {
    if (EhApplication.sImageOkHttpClient === null) {
      const builder: OkHttpClientBuilder = new OkHttpClientBuilder();
      builder.setFollowRedirects(false);
      builder.setFollowSslRedirects(false);
      builder.setConnectTimeoutMs(20000);
      builder.setReadTimeoutMs(20000);
      builder.setWriteTimeoutMs(20000);
      builder.setCallTimeoutMs(20000);
      EhApplication.applyNetworkDeps(builder, context);
      EhApplication.sImageOkHttpClient = builder.build();
    }
    return EhApplication.sImageOkHttpClient;
  }

  /**
   * 对应上游 `clearTempDir()`：清空内部 + 外部临时目录，再给外部临时目录补 `.nomedia`
   * （防止相册扫描到解码中间产物）。
   * @param deleteContent 注入（`FileUtils.deleteContent`）
   * @param ensureNoMedia 注入（`CommonOperations.ensureNoMediaFile`）
   */
  static async clearTempDir(deleteContent: (dir: string) => Promise<void>,
    ensureNoMedia: (dir: string) => Promise<void>): Promise<void> {
    const dir: string | null = AppConfig.getTempDir();
    if (dir !== null) {
      await deleteContent(dir);
    }
    const extDir: string | null = AppConfig.getExternalTempDir();
    if (extDir !== null) {
      await deleteContent(extDir);
      // Add .nomedia to external temp dir
      await ensureNoMedia(extDir);
    }
  }

  /**
   * 对应上游 `update()`：`if (Settings.getVersionCode() < 52) Settings.putGuideGallery(true)` ——
   * 从 52 之前升级上来的用户首次看到画廊引导。**阈值 52 是上游硬编码**，照搬。
   */
  static update(versionCode: number): void {
    if (versionCode < EhApplication.GUIDE_GALLERY_VERSION_CODE) {
      Settings.putGuideGallery(true);
    }
  }

  /** 上游 `update()` 里的硬编码阈值 */
  static readonly GUIDE_GALLERY_VERSION_CODE: number = 52;

  /** 上游 `getDeveloperEmail()`：源码是 `"xiaojieonly$foxmail.com".replace('$','@')` 的防爬写法 */
  static getDeveloperEmail(): string {
    return 'xiaojieonly' + String.fromCharCode(64) + 'foxmail.com';
  }

  // ── 用户订阅标签列表（上游 L721–L733，纯内存）──────────────────────────

  private static sUserTagList: Object | null = null;

  /** 对应上游 `saveUserTagList(context, list)` —— **只写内存不落盘**。UserTagList 属 net-parse → Object 占位 */
  static saveUserTagList(userTagList: Object | null): void {
    EhApplication.sUserTagList = userTagList;
  }

  /** 对应上游 `getUserTagList(context)`：只从内存取 */
  static getUserTagList(): Object | null {
    return EhApplication.sUserTagList;
  }

  // ── 事件横幅（上游 L735 起）────────────────────────────────────────────

  /**
   * 对应上游 `showEventPane(html)` 的**前两道守卫**（其余是 AlertDialog → ui-widget）：
   *   1. `Settings.getShowEhEvents()` 为 false → 不显示
   *   2. `html == null` → 不显示
   * 顺序照搬：先查开关再判空（开关关时连 null 都不看）。
   */
  static shouldShowEventPane(html: string | null): boolean {
    if (!Settings.getShowEhEvents()) {
      return false;
    }
    if (html === null) {
      return false;
    }
    return true;
  }
}