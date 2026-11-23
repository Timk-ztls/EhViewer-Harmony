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

import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Call } from '../../okhttp/Call';
import { HttpUrl } from '../../okhttp/HttpUrl';
import { OkHttpClient, TimeUnit } from '../../okhttp/OkHttpClient';
import { Request } from '../../okhttp/Request';
import { Response } from '../../okhttp/Response';
import { ResponseBody } from '../../okhttp/ResponseBody';
import { AppConfig } from '../AppConfig';
import { EhApplication } from '../EhApplication';
import { EhRequestBuilder } from '../client/EhRequestBuilder';
import {
  INVALID_TASK_ID,
  ImageRequest,
  ImageRequestHost,
  ImageSource,
  LoadImageController,
} from '../../widget/LoadImageView';

/**
 * 区域裁切函数签名（默认使用 ImageKit `desiredRegion` 解码并编码为 PNG 落盘）。
 * 允许在纯 Node 单测中替换，避免依赖真机原生解码器。
 */
export type TileCropperFn = (
  rawPath: string,
  tilePath: string,
  x: number,
  y: number,
  width: number,
  height: number
) => Promise<boolean>;

class ClipBox {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

/** 队列中等待下载并发槽位的任务（LIFO 出队，保证屏幕当前可见图片优先加载）。 */
class QueuedDownloadJob {
  readonly url: string;
  readonly rawPath: string;
  cancelled: boolean = false;
  private readonly resolvers: Array<(ok: boolean) => void> = [];

  constructor(url: string, rawPath: string) {
    this.url = url;
    this.rawPath = rawPath;
  }

  addWaiter(resolve: (ok: boolean) => void): void {
    this.resolvers.push(resolve);
  }

  resolveAll(ok: boolean): void {
    for (let i = 0; i < this.resolvers.length; i++) {
      this.resolvers[i](ok);
    }
    this.resolvers.length = 0;
  }
}

/**
 * 基于 `EhApplication.getOkHttpClient(null)` + `AppConfig.getTempDir()` 的默认图片请求宿主。
 *
 * 职责：
 *   1. 对封面/预览图等 `LoadImageView` 请求走项目全局 OkHttp 链路（携带 Cookie / Proxy / Hosts / DF），
 *      限制最大并发数为 4 并以 LIFO 调度、离屏时真实取消在途 HTTP 请求；
 *   2. 维护 256 条内存 LRU 路径缓存与异步磁盘落盘缓存，合并同 URL 并发请求，避免主线程同步 fs 阻塞；
 *   3. 若 target 配有有效 `setClip(l, t, w, h)`，通过 `@kit.ImageKit` 裁出子图缓存 PNG 并置位 `preCropped`。
 */
export class DefaultImageRequestHost implements ImageRequestHost {
  private static readonly DOMAIN: number = 0x0001;
  private static readonly TAG: string = 'DefaultImageRequestHost';
  private static readonly CACHE_SUBDIR: string = 'img_cache';
  private static readonly MAX_CONCURRENT_DOWNLOADS: number = 6;
  private static readonly THUMB_TIMEOUT_MS: number = 15000;
  private static readonly MAX_MEMORY_CACHE: number = 256;

  private nextTaskId: number = 1;
  private nextTmpSeq: number = 1;
  private cachedCacheDir: string | null = null;
  private ensureDirPromise: Promise<string | null> | null = null;
  private activeDownloadCount: number = 0;
  private cachedThumbBaseClient: OkHttpClient | null = null;
  private cachedThumbClient: OkHttpClient | null = null;
  private visibleStart: number = -1;
  private visibleEnd: number = -1;

  private readonly targetLatestTask: Map<LoadImageController, number> = new Map<LoadImageController, number>();
  private readonly targetUrls: Map<LoadImageController, string> = new Map<LoadImageController, string>();
  private readonly urlWaiters: Map<string, Set<LoadImageController>> = new Map<string, Set<LoadImageController>>();
  private readonly visibleQueue: QueuedDownloadJob[] = [];
  private readonly prefetchQueue: QueuedDownloadJob[] = [];
  private readonly queuedJobsByUrl: Map<string, QueuedDownloadJob> = new Map<string, QueuedDownloadJob>();
  private readonly activeCallsByUrl: Map<string, Call> = new Map<string, Call>();
  private readonly memoryCache: Map<string, string> = new Map<string, string>();
  private readonly inFlightDownloads: Map<string, Promise<boolean>> = new Map<string, Promise<boolean>>();
  private readonly inFlightCrops: Map<string, Promise<boolean>> = new Map<string, Promise<boolean>>();

  private readonly clientProvider: (() => OkHttpClient) | null;
  private readonly cacheDirProvider: (() => string | null) | null;
  private readonly tileCropper: TileCropperFn | null;

  constructor(
    clientProvider: (() => OkHttpClient) | null = null,
    cacheDirProvider: (() => string | null) | null = null,
    tileCropper: TileCropperFn | null = null
  ) {
    this.clientProvider = clientProvider;
    this.cacheDirProvider = cacheDirProvider;
    this.tileCropper = tileCropper;
  }

  request(target: LoadImageController, req: ImageRequest): void {
    const taskId: number = this.nextTaskId++;
    target.listIndex = req.listIndex;
    const orphanedUrl: string | null = this.detachWaiter(target);
    if (orphanedUrl !== null && orphanedUrl !== req.url) {
      this.cancelOrphanedUrl(orphanedUrl);
    }
    this.targetLatestTask.set(target, taskId);
    target.taskId = taskId;

    const clip: ClipBox | null = DefaultImageRequestHost.extractClipBox(target);
    if (req.url.length > 0) {
      const hash: string = DefaultImageRequestHost.hashKey(req.url);
      const memKey: string = DefaultImageRequestHost.buildMemoryKey(hash, clip);
      const cachedUri: string | null = this.getMemoryCache(memKey);
      if (cachedUri !== null) {
        const deliverClip: boolean = clip !== null;
        Promise.resolve().then((): void => {
          if (!this.isTaskActive(target, taskId)) {
            return;
          }
          this.clearTask(target);
          target.preCropped = deliverClip;
          target.onGetValue(cachedUri, ImageSource.MEMORY);
        });
        return;
      }
      this.attachWaiter(target, req.url);
      const existingQueued: QueuedDownloadJob | undefined = this.queuedJobsByUrl.get(req.url);
      if (existingQueued !== undefined && this.isUrlVisible(req.url)) {
        const pIdx: number = this.prefetchQueue.indexOf(existingQueued);
        if (pIdx >= 0) {
          this.prefetchQueue.splice(pIdx, 1);
          this.visibleQueue.push(existingQueued);
        }
      }
    }

    this.runTask(target, taskId, req, clip).catch((err: Object): void => {
      const msg: string = (err instanceof Error) ? err.message : String(err);
      hilog.warn(DefaultImageRequestHost.DOMAIN, DefaultImageRequestHost.TAG,
        'image task failed: %{public}s', msg);
      if (this.isTaskActive(target, taskId)) {
        this.clearTask(target);
        target.onFailure();
      }
    });
  }

  cancel(target: LoadImageController): void {
    this.targetLatestTask.delete(target);
    target.taskId = INVALID_TASK_ID;
    const orphanedUrl: string | null = this.detachWaiter(target);
    if (orphanedUrl !== null) {
      this.cancelOrphanedUrl(orphanedUrl);
    }
  }

  private attachWaiter(target: LoadImageController, url: string): void {
    this.targetUrls.set(target, url);
    let set: Set<LoadImageController> | undefined = this.urlWaiters.get(url);
    if (set === undefined) {
      set = new Set<LoadImageController>();
      this.urlWaiters.set(url, set);
    }
    set.add(target);
  }

  private detachWaiter(target: LoadImageController): string | null {
    const oldUrl: string | undefined = this.targetUrls.get(target);
    if (oldUrl === undefined) {
      return null;
    }
    this.targetUrls.delete(target);
    const set: Set<LoadImageController> | undefined = this.urlWaiters.get(oldUrl);
    if (set === undefined) {
      return oldUrl;
    }
    set.delete(target);
    if (set.size === 0) {
      this.urlWaiters.delete(oldUrl);
      return oldUrl;
    }
    return null;
  }

  private cancelOrphanedUrl(url: string): void {
    const queued: QueuedDownloadJob | undefined = this.queuedJobsByUrl.get(url);
    if (queued !== undefined) {
      queued.cancelled = true;
      this.queuedJobsByUrl.delete(url);
      const vIdx: number = this.visibleQueue.indexOf(queued);
      if (vIdx >= 0) {
        this.visibleQueue.splice(vIdx, 1);
      }
      const pIdx: number = this.prefetchQueue.indexOf(queued);
      if (pIdx >= 0) {
        this.prefetchQueue.splice(pIdx, 1);
      }
      queued.resolveAll(false);
    }
    const call: Call | undefined = this.activeCallsByUrl.get(url);
    if (call !== undefined) {
      this.activeCallsByUrl.delete(url);
      try {
        call.cancel();
      } catch (_e) {
        // ignore cancel error
      }
    }
  }

  updateVisibleRange(start: number, end: number): void {
    this.visibleStart = start;
    this.visibleEnd = end >= start ? end : start;
    for (let i = this.prefetchQueue.length - 1; i >= 0; i--) {
      const job: QueuedDownloadJob = this.prefetchQueue[i];
      if (this.isUrlVisible(job.url)) {
        this.prefetchQueue.splice(i, 1);
        this.visibleQueue.push(job);
      }
    }
    for (let i = this.visibleQueue.length - 1; i >= 0; i--) {
      const job: QueuedDownloadJob = this.visibleQueue[i];
      if (!this.isUrlVisible(job.url)) {
        this.visibleQueue.splice(i, 1);
        this.prefetchQueue.push(job);
      }
    }
    this.pumpDownloadQueue();
  }

  resetVisibleRange(): void {
    this.visibleStart = -1;
    this.visibleEnd = -1;
  }

  private isUrlVisible(url: string): boolean {
    if (this.visibleStart < 0 || this.visibleEnd < 0) {
      return true;
    }
    const set: Set<LoadImageController> | undefined = this.urlWaiters.get(url);
    if (set === undefined || set.size === 0) {
      return false;
    }
    let matched: boolean = false;
    set.forEach((ctrl: LoadImageController): void => {
      if (ctrl.listIndex < 0 || (ctrl.listIndex >= this.visibleStart && ctrl.listIndex <= this.visibleEnd)) {
        matched = true;
      }
    });
    return matched;
  }

  private getMemoryCache(key: string): string | null {
    const val: string | undefined = this.memoryCache.get(key);
    if (val === undefined) {
      return null;
    }
    this.memoryCache.delete(key);
    this.memoryCache.set(key, val);
    return val;
  }

  private putMemoryCache(key: string, uri: string): void {
    if (this.memoryCache.has(key)) {
      this.memoryCache.delete(key);
    } else if (this.memoryCache.size >= DefaultImageRequestHost.MAX_MEMORY_CACHE) {
      const first: IteratorResult<string> = this.memoryCache.keys().next();
      if (!first.done) {
        this.memoryCache.delete(first.value);
      }
    }
    this.memoryCache.set(key, uri);
  }

  private static buildMemoryKey(hash: string, clip: ClipBox | null): string {
    if (clip === null) {
      return `raw:${hash}`;
    }
    return `tile:${hash}_${clip.x}_${clip.y}_${clip.width}_${clip.height}`;
  }

  private isTaskActive(target: LoadImageController, taskId: number): boolean {
    return this.targetLatestTask.get(target) === taskId && target.taskId === taskId;
  }

  private clearTask(target: LoadImageController): void {
    this.targetLatestTask.delete(target);
    this.detachWaiter(target);
    target.taskId = INVALID_TASK_ID;
  }

  private async runTask(
    target: LoadImageController,
    taskId: number,
    req: ImageRequest,
    clip: ClipBox | null
  ): Promise<void> {
    if (req.url.length === 0) {
      if (this.isTaskActive(target, taskId)) {
        this.clearTask(target);
        target.onFailure();
      }
      return;
    }

    const cacheDir: string | null = await this.ensureCacheDirAsync();
    if (!this.isTaskActive(target, taskId)) {
      return;
    }
    if (cacheDir === null) {
      this.clearTask(target);
      target.onFailure();
      return;
    }

    const hash: string = DefaultImageRequestHost.hashKey(req.url);
    const rawPath: string = `${cacheDir}/img_${hash}.bin`;

    let source: number = ImageSource.DISK;
    let rawReady: boolean = await DefaultImageRequestHost.hasNonEmptyFileAsync(rawPath);
    if (!this.isTaskActive(target, taskId)) {
      return;
    }
    if (!rawReady) {
      if (!req.useNetwork) {
        this.clearTask(target);
        target.onFailure();
        return;
      }
      source = ImageSource.NETWORK;
      rawReady = await this.downloadWithDedup(req.url, rawPath);
    }

    if (!this.isTaskActive(target, taskId)) {
      return;
    }
    if (!rawReady) {
      this.clearTask(target);
      target.onFailure();
      return;
    }

    const rawUri: string = 'file://' + rawPath;
    this.putMemoryCache(DefaultImageRequestHost.buildMemoryKey(hash, null), rawUri);

    if (clip !== null) {
      const tilePath: string =
        `${cacheDir}/img_tile_${hash}_${clip.x}_${clip.y}_${clip.width}_${clip.height}.png`;
      let tileReady: boolean = await DefaultImageRequestHost.hasNonEmptyFileAsync(tilePath);
      if (!this.isTaskActive(target, taskId)) {
        return;
      }
      if (!tileReady) {
        tileReady = await this.cropWithDedup(rawPath, tilePath, clip);
      }
      if (!this.isTaskActive(target, taskId)) {
        return;
      }
      if (tileReady) {
        const tileUri: string = 'file://' + tilePath;
        this.putMemoryCache(DefaultImageRequestHost.buildMemoryKey(hash, clip), tileUri);
        this.clearTask(target);
        target.preCropped = true;
        target.onGetValue(tileUri, source);
        return;
      }
    }

    this.clearTask(target);
    target.preCropped = false;
    target.onGetValue(rawUri, source);
  }

  private async ensureCacheDirAsync(): Promise<string | null> {
    if (this.cachedCacheDir !== null) {
      return this.cachedCacheDir;
    }
    if (this.ensureDirPromise !== null) {
      return await this.ensureDirPromise;
    }
    const job: Promise<string | null> = this.initCacheDirAsync().finally((): void => {
      this.ensureDirPromise = null;
    });
    this.ensureDirPromise = job;
    return await job;
  }

  private async initCacheDirAsync(): Promise<string | null> {
    let baseDir: string | null = this.cacheDirProvider !== null
      ? this.cacheDirProvider()
      : AppConfig.getTempDir();
    if (baseDir === null || baseDir.length === 0) {
      baseDir = AppConfig.getExternalTempDir();
    }
    if (baseDir === null || baseDir.length === 0) {
      return null;
    }
    const dir: string = `${baseDir}/${DefaultImageRequestHost.CACHE_SUBDIR}`;
    try {
      const exists: boolean = await fs.access(dir);
      if (!exists) {
        await fs.mkdir(dir, true);
      }
      this.cachedCacheDir = dir;
      return dir;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      hilog.warn(DefaultImageRequestHost.DOMAIN, DefaultImageRequestHost.TAG,
        'ensureCacheDir failed: %{public}s', msg);
      return null;
    }
  }

  private async downloadWithDedup(url: string, rawPath: string): Promise<boolean> {
    const existing: Promise<boolean> | undefined = this.inFlightDownloads.get(url);
    if (existing !== undefined) {
      return await existing;
    }
    const existingQueued: QueuedDownloadJob | undefined = this.queuedJobsByUrl.get(url);
    if (existingQueued !== undefined) {
      return await new Promise<boolean>((resolve: (ok: boolean) => void): void => {
        existingQueued.addWaiter(resolve);
      });
    }
    if (this.activeDownloadCount < DefaultImageRequestHost.MAX_CONCURRENT_DOWNLOADS) {
      return await this.startDownloadSlot(url, rawPath);
    }
    const job: QueuedDownloadJob = new QueuedDownloadJob(url, rawPath);
    this.queuedJobsByUrl.set(url, job);
    if (this.isUrlVisible(url)) {
      this.visibleQueue.push(job);
    } else {
      this.prefetchQueue.push(job);
    }
    return await new Promise<boolean>((resolve: (ok: boolean) => void): void => {
      job.addWaiter(resolve);
    });
  }

  private startDownloadSlot(url: string, rawPath: string): Promise<boolean> {
    const existing: Promise<boolean> | undefined = this.inFlightDownloads.get(url);
    if (existing !== undefined) {
      return existing;
    }
    this.activeDownloadCount++;
    const job: Promise<boolean> = this.downloadToFile(url, rawPath).finally((): void => {
      this.activeDownloadCount = Math.max(0, this.activeDownloadCount - 1);
      this.inFlightDownloads.delete(url);
      this.activeCallsByUrl.delete(url);
      this.pumpDownloadQueue();
    });
    this.inFlightDownloads.set(url, job);
    return job;
  }

  private pumpDownloadQueue(): void {
    while (this.activeDownloadCount < DefaultImageRequestHost.MAX_CONCURRENT_DOWNLOADS &&
      (this.visibleQueue.length > 0 || this.prefetchQueue.length > 0)) {
      const job: QueuedDownloadJob | undefined = this.visibleQueue.length > 0
        ? this.visibleQueue.pop()
        : this.prefetchQueue.pop();
      if (job === undefined) {
        break;
      }
      this.queuedJobsByUrl.delete(job.url);
      if (job.cancelled) {
        job.resolveAll(false);
        continue;
      }
      const waitSet: Set<LoadImageController> | undefined = this.urlWaiters.get(job.url);
      if (waitSet === undefined || waitSet.size === 0) {
        job.resolveAll(false);
        continue;
      }
      this.startDownloadSlot(job.url, job.rawPath).then((ok: boolean): void => {
        job.resolveAll(ok);
      }).catch((err: Object): void => {
        const msg: string = (err instanceof Error) ? err.message : String(err);
        hilog.warn(DefaultImageRequestHost.DOMAIN, DefaultImageRequestHost.TAG,
          'queued image slot failed for %{public}s: %{public}s', job.url, msg);
        job.resolveAll(false);
      });
    }
  }

  private getThumbClient(): OkHttpClient {
    const baseClient: OkHttpClient = this.clientProvider !== null
      ? this.clientProvider()
      : EhApplication.getOkHttpClient(null);
    if (this.cachedThumbClient === null || this.cachedThumbBaseClient !== baseClient) {
      this.cachedThumbBaseClient = baseClient;
      this.cachedThumbClient = (baseClient instanceof OkHttpClient)
        ? baseClient.newBuilder()
          .connectTimeout(DefaultImageRequestHost.THUMB_TIMEOUT_MS, TimeUnit.MILLISECONDS)
          .readTimeout(DefaultImageRequestHost.THUMB_TIMEOUT_MS, TimeUnit.MILLISECONDS)
          .writeTimeout(DefaultImageRequestHost.THUMB_TIMEOUT_MS, TimeUnit.MILLISECONDS)
          .build()
        : baseClient;
    }
    return this.cachedThumbClient;
  }

  private async downloadToFile(url: string, rawPath: string): Promise<boolean> {
    if (await DefaultImageRequestHost.hasNonEmptyFileAsync(rawPath)) {
      return true;
    }
    if (!this.urlWaiters.has(url)) {
      return false;
    }
    const parsed: HttpUrl | null = HttpUrl.parse(url);
    if (parsed === null) {
      return false;
    }
    const client: OkHttpClient = this.getThumbClient();
    let response: Response | null = null;
    let body: ResponseBody | null = null;
    try {
      const request: Request = EhRequestBuilder.of(parsed.toString())
        .header('Cache-Control', 'no-store')
        .build();
      const call: Call = client.newCall(request);
      this.activeCallsByUrl.set(url, call);
      response = await call.execute();
      const code: number = response.code();
      body = response.body();
      if (code < 200 || code >= 300 || body === null) {
        return false;
      }
      const bytes: ArrayBuffer = body.bytes();
      if (bytes.byteLength <= 0) {
        return false;
      }
      return await this.writeBytesAtomicallyAsync(rawPath, bytes);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      hilog.warn(DefaultImageRequestHost.DOMAIN, DefaultImageRequestHost.TAG,
        'download failed for %{public}s: %{public}s', url, msg);
      return false;
    } finally {
      this.activeCallsByUrl.delete(url);
      if (body !== null) {
        try {
          body.close();
        } catch (_e) {
          // ignore body close failure
        }
      }
    }
  }

  private async cropWithDedup(rawPath: string, tilePath: string, clip: ClipBox): Promise<boolean> {
    const existing: Promise<boolean> | undefined = this.inFlightCrops.get(tilePath);
    if (existing !== undefined) {
      return await existing;
    }
    const job: Promise<boolean> = this.runCrop(rawPath, tilePath, clip).finally((): void => {
      this.inFlightCrops.delete(tilePath);
    });
    this.inFlightCrops.set(tilePath, job);
    return await job;
  }

  private async runCrop(rawPath: string, tilePath: string, clip: ClipBox): Promise<boolean> {
    if (await DefaultImageRequestHost.hasNonEmptyFileAsync(tilePath)) {
      return true;
    }
    if (this.tileCropper !== null) {
      return await this.tileCropper(rawPath, tilePath, clip.x, clip.y, clip.width, clip.height);
    }
    return await this.cropTileWithImageKit(rawPath, tilePath, clip);
  }

  private async cropTileWithImageKit(rawPath: string, tilePath: string, clip: ClipBox): Promise<boolean> {
    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      imageSource = image.createImageSource(rawPath);
      const info: image.ImageInfo = await imageSource.getImageInfo();
      const imgW: number = info.size.width;
      const imgH: number = info.size.height;
      if (imgW <= 0 || imgH <= 0 || clip.x >= imgW || clip.y >= imgH) {
        return false;
      }
      const cropW: number = Math.min(clip.width, imgW - clip.x);
      const cropH: number = Math.min(clip.height, imgH - clip.y);
      if (cropW <= 0 || cropH <= 0) {
        return false;
      }
      const regionSize: image.Size = { width: cropW, height: cropH };
      const region: image.Region = { x: clip.x, y: clip.y, size: regionSize };
      const decodeOpts: image.DecodingOptions = { desiredRegion: region };
      pixelMap = await imageSource.createPixelMap(decodeOpts);
      packer = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/png', quality: 95 };
      const packed: ArrayBuffer = await packer.packToData(pixelMap, packOpts);
      if (packed.byteLength <= 0) {
        return false;
      }
      return await this.writeBytesAtomicallyAsync(tilePath, packed);
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      hilog.warn(DefaultImageRequestHost.DOMAIN, DefaultImageRequestHost.TAG,
        'cropTileWithImageKit failed: %{public}s', msg);
      return false;
    } finally {
      if (packer !== null) {
        try {
          await packer.release();
        } catch (_e) {
          // ignore
        }
      }
      if (pixelMap !== null) {
        try {
          await pixelMap.release();
        } catch (_e) {
          // ignore
        }
      }
      if (imageSource !== null) {
        try {
          await imageSource.release();
        } catch (_e) {
          // ignore
        }
      }
    }
  }

  private async writeBytesAtomicallyAsync(destPath: string, data: ArrayBuffer): Promise<boolean> {
    const seq: number = this.nextTmpSeq++;
    const tmpPath: string = `${destPath}.${seq}.tmp`;
    let file: fs.File | null = null;
    try {
      const flags: number = fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC;
      file = await fs.open(tmpPath, flags);
      await fs.write(file.fd, data);
      await fs.close(file);
      file = null;
      await fs.rename(tmpPath, destPath);
      return true;
    } catch (e) {
      const msg: string = (e instanceof Error) ? e.message : String(e);
      hilog.warn(DefaultImageRequestHost.DOMAIN, DefaultImageRequestHost.TAG,
        'writeBytesAtomically failed: %{public}s', msg);
      if (file !== null) {
        try {
          await fs.close(file);
        } catch (_e) {
          // ignore
        }
      }
      try {
        if (await fs.access(tmpPath)) {
          await fs.unlink(tmpPath);
        }
      } catch (_e) {
        // ignore
      }
      return false;
    }
  }

  private static extractClipBox(target: LoadImageController): ClipBox | null {
    if (!target.hasClip() || target.offsetX < 0 || target.offsetY < 0) {
      return null;
    }
    const x: number = Math.floor(target.offsetX);
    const y: number = Math.floor(target.offsetY);
    const width: number = Math.floor(target.clipWidth);
    const height: number = Math.floor(target.clipHeight);
    if (x < 0 || y < 0 || width <= 0 || height <= 0) {
      return null;
    }
    return new ClipBox(x, y, width, height);
  }

  private static async hasNonEmptyFileAsync(path: string): Promise<boolean> {
    try {
      if (!(await fs.access(path))) {
        return false;
      }
      const stat: fs.Stat = await fs.stat(path);
      return stat.size > 0;
    } catch (_e) {
      return false;
    }
  }

  private static hashKey(input: string): string {
    let h1: number = 0x811c9dc5;
    let h2: number = 0x9e3779b9;
    for (let i = 0; i < input.length; i++) {
      const ch: number = input.charCodeAt(i);
      h1 ^= ch;
      h1 = Math.imul(h1, 0x01000193);
      h2 ^= (ch + i);
      h2 = Math.imul(h2, 0x85ebca6b);
    }
    return (h1 >>> 0).toString(16).padStart(8, '0') + (h2 >>> 0).toString(16).padStart(8, '0');
  }
}
