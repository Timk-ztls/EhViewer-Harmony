/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0012   上游: com/hippo/conaco/ConacoTask.java（514 行）
 * 目标   : harmony/entry/src/main/ets/hippo/conaco/ConacoTask.ets
 *
 * 平台差异（每条都影响行为，逐条说明）：
 *
 * 【1】AsyncTask → 内部 async 流程（DEVIATION-CONACOTASK-ASYNC）
 *   上游 DiskLoadTask / NetworkLoadTask 是 AsyncTask<Void,Void,V>，靠
 *   doInBackground / onPostExecute / onCancelled / onProgressUpdate 四个回调编排。
 *   本实现合并为 `runDiskLoad()` / `runNetworkLoad()` 两个 async 方法，
 *   但**三个回调的顺序、短路条件、关键判空逐条照搬**：
 *     · `if (mCancelled || mStop) { onCancelled 分支 } else { ... }`
 *     · `unikery !== null && unikery.getTaskId() === mId` 才回调
 *     · `onGetValue` 返回 false → 走网络 / onFailure
 *   `cancel(false)` 的语义（**不打断运行中任务，只置标志**）→ `mCancelled` 布尔标志；
 *   不引入中断机制（上游也没有）。
 *
 * 【2】WeakReference<Unikery<V>> → 强引用 + 四条清理路径（DEVIATION-CONACOTASK-NOWEAKREF）
 *   ArkTS 无 WeakReference。**缓解（Lead 批准的四条）**：
 *     a. `finishInternal()` / `onCancelledInternal()` 每条终止路径都 `mUnikery = null`
 *     b. `stop()` 立即 `clearUnikery()`（不等任务自然结束）
 *     c. `isNotNecessary()` 增加 `mUnikery === null` 判定 —— 调用方销毁 View 但没 cancel 时，
 *        任务下次检查即自行停止
 *     d. 调用方销毁 View 后应主动 `stop()`（文档说明）
 *   **残余风险**：任务在两次 isNotNecessary 检查之间仍持有 Unikery（最长一个 4KB 处理周期）。
 *
 * 【3】OkHttp 传输是**全缓冲**的（DEVIATION-CONACOTASK-BUFFERED）
 *   上游 `body.byteStream()` + `byte[1024*4]` 循环逐段写盘并逐段 `notifyProgress`。
 *   ArkTS 侧 `Call.execute(): Promise<Response>`，`ResponseBody` 内部就是 `ArrayBuffer`
 *   （只有 `bytes()/string()`，**没有 byteStream**）→ 响应体先在内存里完整落地，
 *   然后本实现**按 4KB 切片回放**：每写 4KB 就 `notifyProgress(bytesRead, received, total)`。
 *   → **进度粒度与上游一致（每 4KB 一次，10MB ≈ 2500 次更新）**，进度条平滑度不变；
 *     代价是响应体峰值内存 = 完整对象大小（上游是流式的）。
 *
 * 【4】`Executor` → 具体执行器
 *   `mDiskExecutor: SerialThreadExecutor`（上游 LinkedList + SerialThreadExecutor(3000L)）
 *   `mNetworkExecutor: IoThreadPoolExecutor`（上游 ThreadPoolExecutor(3,3,5s)）
 *   都只暴露 `execute(task: () => void)`。
 *
 * 【5】其他：
 *   · `Log.d/Log.w` → hilog
 *   · `InputStreamPipe/OutputStreamPipe` 的 obtain/close/release 仍按已移植契约调用
 *   · `mHelper.decode(isp, hardware)` 沿用合并重载版本
 */

import hilog from '@ohos.hilog';
import { Unikery } from './Unikery';
import { DataContainer } from './DataContainer';
import { ValueHelper } from './ValueHelper';
import { ValueCache } from './ValueCache';
import { ConacoTaskLike } from './Register';
import { SerialThreadExecutor } from '../lib/yorozuya/thread/SerialThreadExecutor';
import { IoThreadPoolExecutor } from '../util/IoThreadPoolExecutor';
import { OkHttpClient } from '../okhttp/OkHttpClient';
import { Request, RequestBuilder } from '../okhttp/Request';
import { Call } from '../okhttp/Call';
import { Response } from '../okhttp/Response';
import { ResponseBody } from '../okhttp/ResponseBody';
import { MediaType } from '../okhttp/MediaType';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';
import { OutputStreamPipe, ByteSink } from '../streampipe/OutputStreamPipe';
import { CacheOutputStreamPipe } from '../beerbelly/SimpleDiskCache';
import { InputStreamLike, IOUtils } from '../lib/yorozuya/IOUtils';
import fileIo from '@ohos.file.fs';

const TAG: string = 'ConacoTask';
const DOMAIN: number = 0x0001;

/** 上游 Conaco 的来源常量：MEMORY=0 / DISK=1 / NETWORK=2（此处重复声明避免与 Conaco.ets 循环依赖） */
const SOURCE_DISK: number = 1;
const SOURCE_NETWORK: number = 2;

/** 上游 4KB 缓冲区。**进度粒度由它决定**，映射到 ArkTS 后按同样大小切片回放（见文件头差异 3） */
const BUFFER_SIZE: number = 1024 * 4;

export class ConacoTask<V> implements ConacoTaskLike {

  private readonly mId: number;
  /** 上游 WeakReference → 强引用（见文件头差异 2） */
  private mUnikery: Unikery<V> | null;
  private readonly mKey: string | null;
  private readonly mUrl: string | null;
  private readonly mDataContainer: DataContainer | null;
  private readonly mUseMemoryCache: boolean;
  private readonly mUseDiskCache: boolean;
  private readonly mUseNetwork: boolean;
  private readonly mHelper: ValueHelper<V>;
  private readonly mCache: ValueCache<V>;
  private readonly mOkHttpClient: OkHttpClient;
  private readonly mDiskExecutor: SerialThreadExecutor;
  private readonly mNetworkExecutor: IoThreadPoolExecutor;
  private readonly mConacoFinish: (task: ConacoTask<V>) => void;

  private mCall: Call | null = null;
  private mStart: boolean = false;
  private mStop: boolean = false;
  private mCancelled: boolean = false;
  private mHardware: boolean = true;

  /** 上游是 private 构造 + Builder；ArkTS 里 Builder 是独立类，无法访问 private 构造，故放开 */
  constructor(builder: Builder<V>) {
    this.mId = builder.mId;
    this.mUnikery = builder.mUnikery;
    this.mKey = builder.mKey;
    this.mUrl = builder.mUrl;
    this.mDataContainer = builder.mDataContainer;
    this.mUseMemoryCache = builder.mUseMemoryCache;
    this.mUseDiskCache = builder.mUseDiskCache;
    this.mUseNetwork = builder.mUseNetwork;
    this.mHelper = ConacoTask.require(builder.mHelper, 'helper');
    this.mCache = ConacoTask.require(builder.mCache, 'cache');
    this.mOkHttpClient = ConacoTask.require(builder.mOkHttpClient, 'okHttpClient');
    this.mDiskExecutor = ConacoTask.require(builder.mDiskExecutor, 'diskExecutor');
    this.mNetworkExecutor = ConacoTask.require(builder.mNetworkExecutor, 'networkExecutor');
    this.mConacoFinish = builder.mConacoFinish;
    this.mHardware = builder.hardware;
  }

  /** Builder 必填项的显式校验（上游靠调用方自觉，缺了会 NPE；这里抛可诊断的错） */
  private static require<X>(v: X | null, name: string): X {
    if (v === null) {
      throw new Error('ConacoTask.Builder.' + name + ' is required');
    }
    return v;
  }

  getId(): number {    return this.mId;
  }

  /** 对应上游 getKey()（Register 契约） */
  getKey(): string | null {
    return this.mKey;
  }

  useMemoryCache(): boolean {
    return this.mUseMemoryCache;
  }

  getUnikery(): Unikery<V> | null {
    return this.mUnikery;
  }

  /** 对应上游 clearUnikery()：断开与 Unikery 的引用（见文件头差异 2a） */
  clearUnikery(): void {
    this.mUnikery = null;
  }

  // ── 生命周期（上游 L109–L177）──────────────────────────────────────────

  private onFinish(): void {
    if (!this.mStop) {
      this.mConacoFinish(this);
    }
    // 对应差异 2a：终止路径一律断开
    this.mUnikery = null;
  }

  /**
   * 对应上游 start()（@UiThread）。
   * **本实现同步推导出首个异步步骤**，不额外排队（调用方已在 Conaco 的调度域内）。
   */
  start(): void {
    if (this.mStop || this.mStart) {
      return;
    }
    this.mStart = true;

    const unikery: Unikery<V> | null = this.mUnikery;
    if (unikery !== null && unikery.getTaskId() === this.mId) {
      if (this.mUseDiskCache) {
        this.mDiskExecutor.execute(() => {
          this.runDiskLoad(this.mId);
          return Promise.resolve();
        });
        return;
      } else if (this.mUseNetwork) {
        unikery.onMiss(SOURCE_DISK);
        unikery.onRequest();
        this.mNetworkExecutor.execute(() => this.runNetworkLoad(this.mId));
        return;
      } else {
        unikery.onMiss(SOURCE_DISK);
        unikery.onMiss(SOURCE_NETWORK);
        unikery.onFailure();
      }
    }

    this.onFinish();
  }

  /**
   * 对应上游 stop()（@UiThread）：
   * `cancel(false)` 两处（**不打断运行中任务**）+ `mCall.cancel()` + `unikery.onCancel()`。
   * 差异 2b：立即 clearUnikery()。
   */
  stop(): void {
    if (this.mStop) {
      return;
    }
    this.mStop = true;

    // Stop jobs（对应 cancel(false)）
    this.mCancelled = true;
    const call: Call | null = this.mCall;
    if (call !== null) {
      call.cancel();
      this.mCall = null;
    }

    const unikery: Unikery<V> | null = this.mUnikery;
    if (unikery !== null) {
      unikery.onCancel();
    }

    // 差异 2b：立刻断开，让 View 可被 GC
    this.clearUnikery();
    // Conaco handle the clean up（上游：清理由 Conaco 负责）
  }

  /**
   * 对应上游 isNotNecessary(AsyncTask)：
   * `mStop || asyncTask.isCancelled() || unikery == null || unikery.getTaskId() != mId`
   * 其中 `asyncTask.isCancelled()` 对应本实现的 `mCancelled`；
   * 差异 2c：`mUnikery === null` 也算不必要。
   */
  private isNotNecessary(): boolean {
    if (this.mStop || this.mCancelled) {
      return true;
    }
    const unikery: Unikery<V> | null = this.mUnikery;
    if (unikery === null) {
      return true;
    }
    return unikery.getTaskId() !== this.mId;
  }

  // ── 静态搬运助手（上游 L179–L213）───────────────────────────────────────

  private static putFromDiskCacheToDataContainer<V>(key: string, cache: ValueCache<V>,
    container: DataContainer): void {
    const diskCache = cache.getDiskCache();
    if (diskCache === null) {
      return;
    }
    const pipe: InputStreamPipe | null = diskCache.getInputStreamPipe(key);
    if (pipe === null) {
      return;
    }
    try {
      pipe.obtain();
      container.save(new FileInputStreamLike(pipe.open()), -1, null, null);
    } catch (e) {
      hilog.debug(DOMAIN, TAG, "Can't save value from disk cache to data container");
      container.remove();
    } finally {
      pipe.close();
      pipe.release();
    }
  }

  private static putFromDataContainerToDiskCache<V>(key: string, cache: ValueCache<V>,
    container: DataContainer): void {
    const pipe: InputStreamPipe | null = container.get();
    if (pipe === null) {
      return;
    }
    try {
      pipe.obtain();
      cache.putRawToDisk(key, pipe.open());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, "Can't save value from data container to disk cache");
      cache.removeFromDisk(key);
    } finally {
      pipe.close();
      pipe.release();
    }
  }

  // ── DiskLoadTask（上游 L215–L293）───────────────────────────────────────

  /**
   * 对应上游 DiskLoadTask.doInBackground：
   * DataContainer → disk cache 两级；命中后回填另一级；解码失败则驱逐（避免反复失败）。
   */
  private runDiskLoad(taskId: number): void {
    if (this.isNotNecessary()) {
      this.onFinish();
      return;
    }

    let value: V | null = null;

    // First check data container
    const container: DataContainer | null = this.mDataContainer;
    if (container !== null && container.isEnabled()) {
      const isp: InputStreamPipe | null = container.get();
      if (isp !== null) {
        value = this.mHelper.decode(isp, this.mHardware);
      }
      // Keep a copy in disk cache so recycled list items can reload
      // after DataContainer is dropped on view re-attach.
      if (value !== null && this.mKey !== null && this.mUseDiskCache) {
        ConacoTask.putFromDataContainerToDiskCache(this.mKey, this.mCache, container);
      }
    }

    // Then check disk cache
    if (this.mKey !== null) {
      let triedDiskCache: boolean = false;
      if (value === null && this.mUseDiskCache) {
        triedDiskCache = true;
        value = this.mCache.getFromDiskWithFlag(this.mKey, this.mHardware);
        // Put back to data container
        if (value !== null && container !== null && container.isEnabled()) {
          ConacoTask.putFromDiskCacheToDataContainer(this.mKey, this.mCache, container);
        }
      }

      if (triedDiskCache && value === null) {
        // Decode failed on existing cache entry, evict to avoid repeated failures.
        this.mCache.removeFromDisk(this.mKey);
      }

      if (value !== null && this.mUseMemoryCache && this.mHelper.useMemoryCache(this.mKey, value)) {
        this.mCache.putToMemory(this.mKey, value);
      }
    }

    this.onDiskLoadPostExecute(taskId, value);
  }

  /** 对应上游 DiskLoadTask.onPostExecute / onCancelled 的分支 */
  private onDiskLoadPostExecute(taskId: number, value: V | null): void {
    if (this.mCancelled || this.mStop) {
      this.onFinish();
      return;
    }

    const unikery: Unikery<V> | null = this.mUnikery;
    if (unikery !== null && unikery.getTaskId() === this.mId) {
      if (value === null || !unikery.onGetValue(value, SOURCE_DISK)) {
        if (this.mUseNetwork) {
          unikery.onMiss(SOURCE_DISK);
          unikery.onRequest();
          this.mNetworkExecutor.execute(() => this.runNetworkLoad(taskId));
          return;
        } else {
          unikery.onMiss(SOURCE_DISK);
          unikery.onFailure();
        }
      }
    }
    this.onFinish();
  }

  // ── NetworkLoadTask（上游 L295–L461）───────────────────────────────────

  /**
   * 对应上游 NetworkLoadTask.doInBackground。
   * `mUrl` 为空（不该发生，Builder 要求）时直接失败。
   */
  private async runNetworkLoad(taskId: number): Promise<void> {
    if (this.isNotNecessary()) {
      this.onFinish();
      return;
    }
    const url: string | null = this.mUrl;
    if (url === null) {
      this.onNetworkLoadPostExecute(taskId, null);
      return;
    }
    await this.fetchAndStore(taskId, url);
  }

  private async fetchAndStore(taskId: number, url: string): Promise<void> {
    let value: V | null = null;
    let response: Response | null = null;
    try {
      const request: Request = new RequestBuilder().url(url).get().build();
      const call: Call = this.mOkHttpClient.newCall(request);
      this.mCall = call;

      response = await call.execute();
      if (this.isNotNecessary()) {
        this.mCall = null;
        this.onFinish();
        return;
      }

      const body: ResponseBody | null = response.body();
      const container: DataContainer | null = this.mDataContainer;

      if ((container === null || !container.isEnabled()) && this.mKey !== null) {
        // 差异 3：全缓冲 → 按 4KB 回放写盘 + 逐段报进度
        const ok: boolean = await this.putToDiskCache(body);
        if (ok) {
          value = this.mCache.getFromDiskWithFlag(this.mKey, this.mHardware);
          if (value === null) {
            this.mCache.removeFromDisk(this.mKey);
          } else if (this.mUseMemoryCache && this.mHelper.useMemoryCache(this.mKey, value)) {
            this.mCache.putToMemory(this.mKey, value);
          }
        } else {
          if (!this.isNotNecessary()) {
            this.mCache.removeFromDisk(this.mKey);
          }
          value = null;
        }
      } else if (container !== null && container.isEnabled()) {
        // Check url Moved
        const responseUrl: string = response.request().url().toString();
        if (responseUrl !== url) {
          container.onUrlMoved(url, responseUrl);
        }

        if (!(await this.putToDataContainer(body, container))) {
          this.mCall = null;
          this.onNetworkLoadPostExecute(taskId, null);
          return;
        }

        const isp: InputStreamPipe | null = container.get();
        if (isp === null) {
          this.mCall = null;
          this.onNetworkLoadPostExecute(taskId, null);
          return;
        }
        value = this.mHelper.decode(isp, this.mHardware);
        if (value === null) {
          container.remove();
        } else if (this.mKey !== null) {
          ConacoTask.putFromDataContainerToDiskCache(this.mKey, this.mCache, container);
          if (this.mUseMemoryCache && this.mHelper.useMemoryCache(this.mKey, value)) {
            this.mCache.putToMemory(this.mKey, value);
          }
        }
      } else {
        value = null;
      }
    } catch (e) {
      value = null;
    } finally {
      if (response !== null) {
        try {
          response.close();
        } catch (e2) {
          // Ignore
        }
      }
      this.mCall = null;
    }

    this.onNetworkLoadPostExecute(taskId, value);
  }

  /**
   * 对应上游 putToDiskCache(InputStream, long)：写盘 + **每 4KB 一次** notifyProgress。
   * 差异 3：源是已完整落地的 ArrayBuffer，按 4KB 切片回放，进度粒度与上游一致。
   */
  private async putToDiskCache(body: ResponseBody | null): Promise<boolean> {
    const key: string | null = this.mKey;
    if (key === null || body === null) {
      return false;
    }
    const diskCache = this.mCache.getDiskCache();
    if (diskCache === null) {
      return false;
    }

    const pipe: OutputStreamPipe | null = diskCache.getOutputStreamPipe(key);
    if (pipe === null) {
      return false;
    }
    let committed: boolean = false;
    let os: ByteSink | null = null;
    try {
      pipe.obtain();
      os = pipe.open();

      const data: ArrayBuffer = body.bytes();
      const length: number = data.byteLength;
      let receivedSize: number = 0;

      while (receivedSize < length) {
        const end: number = Math.min(receivedSize + BUFFER_SIZE, length);
        const chunk: ArrayBuffer = data.slice(receivedSize, end);
        const bytesRead: number = chunk.byteLength;
        os.write(chunk);
        receivedSize += bytesRead;
        this.notifyProgress(bytesRead, receivedSize, length);
        if (this.isNotNecessary()) {
          return false;
        }
      }
      committed = true;
      return true;
    } catch (e) {
      return false;
    } finally {
      if (os !== null) {
        try {
          os.close();
        } catch (e2) {
          // Ignore
        }
      }
      if (committed) {
        pipe.close();
      } else if (pipe instanceof CacheOutputStreamPipe) {
        (pipe as CacheOutputStreamPipe).abort();
      } else {
        pipe.close();
      }
      pipe.release();
    }
  }

  /** 对应上游 putToDataContainer(InputStream, ResponseBody) */
  private async putToDataContainer(body: ResponseBody | null, container: DataContainer): Promise<boolean> {
    if (body === null) {
      return false;
    }
    // Get media type
    let mediaType: string | null = null;
    const mt: MediaType | null = body.contentType();
    if (mt !== null) {
      mediaType = `${mt.type()}/${mt.subtype()}`;
    }
    // 上游 save(is, length, mediaType, notifier)；ArkTS 侧 DataContainer.save 收 InputStreamLike，
    // 已缓冲场景用一个基于 ArrayBuffer 的只读 pipe 适配（见 DataContainer 契约）
    return container.save(this.arrayBufferToInput(body.bytes()), body.contentLength(), mediaType, null);
  }

  /** ArrayBuffer → InputStreamLike 适配（差异 3 的产物；DataContainer.save 需要它） */
  private arrayBufferToInput(data: ArrayBuffer): InputStreamLike {
    return new ArrayBufferInputStreamLike(data);
  }

  /** 对应上游 notifyProgress(long, long, long)：本实现直接驱动 Unikery（无 AsyncTask 中间层） */
  private notifyProgress(singleReceivedSize: number, receivedSize: number, totalSize: number): void {
    if (this.isNotNecessary()) {
      return;
    }
    const unikery: Unikery<V> | null = this.mUnikery;
    if (unikery !== null && unikery.getTaskId() === this.mId) {
      // 对应上游 onProgressUpdate 的判空 + mStop/mCancelled 检查
      unikery.onProgress(singleReceivedSize, receivedSize, totalSize);
    }
  }

  /** 对应上游 NetworkLoadTask.onPostExecute / onCancelled */
  private onNetworkLoadPostExecute(taskId: number, holder: V | null): void {
    if (this.mCancelled || this.mStop) {
      this.onFinish();
      return;
    }
    const unikery: Unikery<V> | null = this.mUnikery;
    if (unikery !== null && unikery.getTaskId() === this.mId) {
      if (holder === null || !unikery.onGetValue(holder, SOURCE_NETWORK)) {
        unikery.onFailure();
      }
    }
    this.onFinish();
  }
}

/** 已缓冲数据上的 InputStreamLike（差异 3 的适配；DataContainer.save 只需要 read(buffer)） */
export class ArrayBufferInputStreamLike implements InputStreamLike {
  private readonly mData: ArrayBuffer;
  private mPos: number = 0;

  constructor(data: ArrayBuffer) {
    this.mData = data;
  }

  /** 返回本次读到的字节数；-1 (IOUtils.EOF) 表示已到末尾 */
  read(buffer: ArrayBuffer): number {
    const remain: number = this.mData.byteLength - this.mPos;
    if (remain <= 0) {
      return IOUtils.EOF;
    }
    if (buffer.byteLength <= 0) {
      return 0;
    }
    const n: number = Math.min(buffer.byteLength, remain);
    const src: Uint8Array = new Uint8Array(this.mData, this.mPos, n);
    const dst: Uint8Array = new Uint8Array(buffer, 0, n);
    dst.set(src);
    this.mPos += n;
    return n;
  }
}

/** 文件上的 InputStreamLike（container.save 从磁盘缓存 pipe 搬运时使用） */
export class FileInputStreamLike implements InputStreamLike {
  private readonly mFile: fileIo.File;
  private mClosed: boolean = false;

  constructor(f: fileIo.File) {
    this.mFile = f;
  }

  read(buffer: ArrayBuffer): number {
    if (this.mClosed) {
      return IOUtils.EOF;
    }
    try {
      const n: number = fileIo.readSync(this.mFile.fd, buffer);
      return n <= 0 ? IOUtils.EOF : n;
    } catch (e) {
      return IOUtils.EOF;
    }
  }

  close(): void {
    if (!this.mClosed) {
      this.mClosed = true;
      try {
        fileIo.closeSync(this.mFile);
      } catch (e) {
        // Ignore
      }
    }
  }
}

/** Builder（上游 L463–L514 逐条照搬，含默认值） */
export class Builder<T> {

  mId: number = 0;
  mUnikery: Unikery<T> | null = null;
  mKey: string | null = null;
  mUrl: string | null = null;
  mDataContainer: DataContainer | null = null;
  mUseMemoryCache: boolean = true;
  mUseDiskCache: boolean = true;
  mUseNetwork: boolean = true;
  mHelper: ValueHelper<T> | null = null;
  mCache: ValueCache<T> | null = null;
  mOkHttpClient: OkHttpClient | null = null;
  mDiskExecutor: SerialThreadExecutor | null = null;
  mNetworkExecutor: IoThreadPoolExecutor | null = null;
  mConacoFinish: (task: ConacoTask<T>) => void = () => {
  };
  hardware: boolean = true;

  setId(id: number): Builder<T> {
    this.mId = id;
    return this;
  }

  setUnikery(unikery: Unikery<T>): Builder<T> {
    this.mUnikery = unikery;
    return this;
  }

  getUnikery(): Unikery<T> | null {
    return this.mUnikery;
  }

  setKey(key: string | null): Builder<T> {
    this.mKey = key;
    return this;
  }

  getKey(): string | null {
    return this.mKey;
  }

  setUrl(url: string): Builder<T> {
    this.mUrl = url;
    return this;
  }

  getUrl(): string | null {
    return this.mUrl;
  }

  setDataContainer(dataContainer: DataContainer | null): Builder<T> {
    this.mDataContainer = dataContainer;
    return this;
  }

  setUseMemoryCache(useMemoryCache: boolean): Builder<T> {
    this.mUseMemoryCache = useMemoryCache;
    return this;
  }

  setUseDiskCache(useDiskCache: boolean): Builder<T> {
    this.mUseDiskCache = useDiskCache;
    return this;
  }

  setUseNetwork(useNetwork: boolean): Builder<T> {
    this.mUseNetwork = useNetwork;
    return this;
  }

  setHelper(helper: ValueHelper<T>): Builder<T> {
    this.mHelper = helper;
    return this;
  }

  setCache(cache: ValueCache<T>): Builder<T> {
    this.mCache = cache;
    return this;
  }

  setOkHttpClient(client: OkHttpClient): Builder<T> {
    this.mOkHttpClient = client;
    return this;
  }

  setDiskExecutor(executor: SerialThreadExecutor): Builder<T> {
    this.mDiskExecutor = executor;
    return this;
  }

  setNetworkExecutor(executor: IoThreadPoolExecutor): Builder<T> {
    this.mNetworkExecutor = executor;
    return this;
  }

  setConaco(finish: (task: ConacoTask<T>) => void): Builder<T> {
    this.mConacoFinish = finish;
    return this;
  }

  setHardware(hardware: boolean): Builder<T> {
    this.hardware = hardware;
    return this;
  }

  /** 对应上游 Builder.isValid()：必填项缺失时抛可诊断错误 */
  isValid(): void {
    if (this.mUnikery === null) {
      throw new Error('ConacoTask.Builder.unikery is required');
    }
    if (this.mHelper === null) {
      throw new Error('ConacoTask.Builder.helper is required');
    }
    if (this.mCache === null) {
      throw new Error('ConacoTask.Builder.cache is required');
    }
    if (this.mOkHttpClient === null) {
      throw new Error('ConacoTask.Builder.okHttpClient is required');
    }
    if (this.mDiskExecutor === null) {
      throw new Error('ConacoTask.Builder.diskExecutor is required');
    }
    if (this.mNetworkExecutor === null) {
      throw new Error('ConacoTask.Builder.networkExecutor is required');
    }
  }

  build(): ConacoTask<T> {
    return new ConacoTask<T>(this);
  }
}
