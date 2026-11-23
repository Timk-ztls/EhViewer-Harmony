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
 * 移植自 app/src/main/java/com/hippo/ehviewer/download/ArchiverDownloader.kt（515 行含注释 / 478 逻辑行）。
 *
 * 职责：EhViewer 归档（`archiver.php` 返回的 zip）下载器 —— 支持暂停/继续/取消、
 * Range 断点续传、416/200 降级重下、进度与速度节流（500ms）、任务状态持久化到 Settings。
 *
 * ============================================================================
 * 关键平台决策（D-ζ，需 net-parse 知悉）
 * ============================================================================
 * 上游用 `okHttpClient.newCall(request).enqueue(...)` + `body.byteStream()` 做**流式**落盘。
 * net-parse 已落地的 `hippo/okhttp` 兼容壳里 `ResponseBody` 是**全量缓冲**实现
 * （`constructor(contentType: MediaType | null, buffer: ArrayBuffer)`、`string()` 同步返回），
 * 没有 `byteStream()`。归档 zip 动辄 10^8 字节量级，整包进 ArrayBuffer 在鸿蒙上会直接
 * 触发 OOM 且拿不到分块进度。
 *
 * 因此本文件**不走 okhttp 壳**，改用 `@ohos.net.http` 的 `requestInStream`：
 *   - `dataReceive` 事件 = 上游 `inputStream.read(buffer)` 的等价物（真实分块）
 *   - `headersReceive` 事件 = 上游 `response.code()` / `response.header("Content-Range")`
 *   - `destroy()` = 上游 `call.cancel()`
 *   - `Range: bytes=N-` 请求头、416/200 语义完全一致（服务端行为不变）
 * 这是"传输实现替换"，不是"行为替换"：可见行为（断点续传位置、重下提示、进度节流、
 * 完成/失败回调）逐条保留。
 *
 * 其余等价点：
 *   1. `activeTasks: ConcurrentHashMap<gid, ActiveTask>` → `Map<number, ActiveTask>`；
 *      ArkTS 单线程事件循环，写入串行化靠 `fs` 写入 Promise 链 + 每次回调前
 *      `task.call !== call` 身份校验（上游同款），因此不需要额外锁。
 *   2. `taskIdGenerator = AtomicLong(System.currentTimeMillis())` → 自增计数器，初值取毫秒时间戳。
 *   3. `Settings.putArchiverDownload*` 五个键的持久化顺序与时机逐个保留（含暂停标记先写）。
 *   4. `resolveTotal(response, offset, contentLength)`：优先解析 `Content-Range` 的总长度，
 *      否则 `offset + contentLength`，否则 0 —— 逐行保留。
 *   5. `PauseSignal : IOException("Paused")` → 自定义 `PauseSignal extends Error`，
 *      catch 顺序（PauseSignal 先于 Exception）保留。
 *   6. `toastOnMain(R.string.archiver_download_restart_no_range)`：鸿蒙侧无 Toast，
 *      改为 `promptAction.showToast`（UI 提示语义一致）。
 */

import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { ArchiverDownloadCompleter } from './ArchiverDownloadCompleter';
import { ArchiverDownloadService } from './ArchiverDownloadService';
import { AppConfig } from '../AppConfig';
import { Settings } from '../Settings';
import { EhUrl } from '../client/EhUrl';
import { EhUtils } from '../client/EhUtils';
import { GalleryInfo } from '../client/data/GalleryInfo';

export type ArchiverCookieProvider = (url: string) => string;

const DOMAIN: number = 0x0D0C;
const TAG: string = 'ArchiverDownloader';

/** 读缓冲（上游 `BUFFER_SIZE = 8192`；鸿蒙侧 dataReceive 分块由系统决定，这里作为写缓冲上限说明保留）。 */
const BUFFER_SIZE: number = 8192;

/** 进度节流（上游 `NOTIFY_INTERVAL_MS = 500`）。 */
const NOTIFY_INTERVAL_MS: number = 500;

/** 暂停信号：上游 `private class PauseSignal : IOException("Paused")`。 */
class PauseSignal extends Error {
  constructor() {
    super('Paused');
    this.name = 'PauseSignal';
  }
}

/** 一次活动下载的内部状态（上游 `private class ActiveTask`）。 */
class ActiveTask {
  public readonly taskId: number;
  public readonly gid: number;
  public readonly url: string;
  public readonly fileName: string;
  public readonly zipPath: string;
  public readonly galleryInfo: GalleryInfo;

  public request: http.HttpRequest | null = null;
  public downloaded: number = 0;
  public total: number = 0;
  public speed: number = 0;
  public paused: boolean = false;
  public importing: boolean = false;
  /** L-15：416 只处理一次（两条到达路径共用同一任务）。 */
  public handled416: boolean = false;

  public lastNotifyAt: number = 0;
  public lastSpeedAt: number = 0;
  public bytesSinceSpeed: number = 0;

  constructor(taskId: number, gid: number, url: string, fileName: string, zipPath: string,
    galleryInfo: GalleryInfo) {
    this.taskId = taskId;
    this.gid = gid;
    this.url = url;
    this.fileName = fileName;
    this.zipPath = zipPath;
    this.galleryInfo = galleryInfo;
  }
}

/** 活动归档任务只读快照（供「下载」列表页统一展示进行中/解压中的归档任务）。 */
export class ArchiverTaskSnapshot {
  public readonly gid: number;
  public readonly taskId: number;
  public readonly title: string;
  public readonly uploader: string;
  public readonly category: number;
  public readonly pages: number;
  public readonly rating: number;
  public readonly thumb: string;
  public readonly downloaded: number;
  public readonly total: number;
  public readonly speed: number;
  public readonly paused: boolean;
  public readonly importing: boolean;
  public readonly fileName: string;
  public readonly titleJpn: string;

  constructor(
    gid: number,
    taskId: number,
    title: string,
    uploader: string,
    category: number,
    pages: number,
    rating: number,
    thumb: string,
    downloaded: number,
    total: number,
    speed: number,
    paused: boolean,
    importing: boolean,
    fileName: string,
    titleJpn: string = ''
  ) {
    this.gid = gid;
    this.taskId = taskId;
    this.title = title;
    this.uploader = uploader;
    this.category = category;
    this.pages = pages;
    this.rating = rating;
    this.thumb = thumb;
    this.downloaded = downloaded;
    this.total = total;
    this.speed = speed;
    this.paused = paused;
    this.importing = importing;
    this.fileName = fileName;
    this.titleJpn = titleJpn;
  }
}

/** 进度快照（上游 `class Progress`）。 */
export class ArchiverProgress {
  public readonly gid: number;
  public readonly taskId: number;
  public readonly downloaded: number;
  public readonly total: number;
  public readonly speed: number;
  public readonly paused: boolean;

  constructor(gid: number, taskId: number, downloaded: number, total: number, speed: number,
    paused: boolean) {
    this.gid = gid;
    this.taskId = taskId;
    this.downloaded = downloaded;
    this.total = total;
    this.speed = speed;
    this.paused = paused;
  }
}

/** 监听器（上游 `interface Listener`）。 */
export interface ArchiverDownloaderListener {
  onProgress(gid: number, downloaded: number, total: number, speed: number, paused: boolean): void;
  onSuccess(gid: number, taskId: number, zipPath: string): void;
  onFailure(gid: number, taskId: number, e: Error): void;
  onCancel(gid: number, taskId: number): void;
}

/**
 * 断点续传的**响应判定**（对位上游 `ArchiverDownloader.onResponse` 的分支顺序）。
 *
 * 这段是全模块最危险的地方：四个分支的顺序决定"续传 / 整包重下 / 判定完成 / 失败"，
 * 顺序写反不会报错，只会：
 *   - 416 当成失败 → **文件其实已下完，却永远卡在失败**（用户点恢复还是失败）
 *   - 200 当成续传 → 在 offset>0 时把整包内容**追加**到半截文件后面 → zip 损坏
 *   - 206 走成功分支 → 只下了半包就宣告完成 → 解压必失败
 */
export class ResumeDecision {
  /** 判定类别。 */
  public static readonly KIND_SUCCESS: number = 0;
  public static readonly KIND_FAILED: number = 1;
  public static readonly KIND_COMPLETE_ALREADY: number = 2;
  /**
   * **未知**：状态码还没拿到（`headersReceive` 未触发 / 键名不匹配 → `responseCode` 仍为 0）。
   * L-11：`decide(0, *)` 原来落进 `code !== 200 && code !== 206` → `KIND_FAILED` → 调用方删文件。
   * **0 不是"确实失败"，是"还不知道"** —— 删掉一个可能完好的文件不可逆。
   */
  public static readonly KIND_UNKNOWN: number = 3;

  static readonly REASON_NONE: string = '';
  static readonly REASON_RESTART_NO_RANGE: string = 'restart_no_range';
  static readonly REASON_UNKNOWN_STATUS: string = 'unknown_status';

  /**
   * @param code    HTTP 状态码
   * @param offset  本次请求的起始偏移（> 0 表示带了 `Range: bytes=N-`）
   */
  /**
   * 服务端是否**忽略了 Range**（L-06）：`200 + 我们带了 Range(offset>0)`。
   * 抽成纯谓词：`headersReceive` 里的重置动作无法在单测里执行，但"要不要重置"必须可测。
   */
  static isRangeIgnored(code: number, offset: number): boolean {
    return code === 200 && offset > 0;
  }

  public static decide(code: number, offset: number): ResumePlan {
    const plan: ResumePlan = { kind: ResumeDecision.KIND_FAILED, reason: ResumeDecision.REASON_NONE };

    // 未知状态码（0）：headersReceive 没到 / 键名不匹配 → **绝不能当失败**（L-11）
    if (code === 0) {
      plan.kind = ResumeDecision.KIND_UNKNOWN;
      plan.reason = ResumeDecision.REASON_UNKNOWN_STATUS;
      return plan;
    }

    // 416：Range 起点超过文件末尾 = 本地文件已经完整（上游最先判这一条）
    if (code === 416) {
      plan.kind = ResumeDecision.KIND_COMPLETE_ALREADY;
      return plan;
    }
    if (code !== 200 && code !== 206) {
      plan.kind = ResumeDecision.KIND_FAILED;
      return plan;
    }
    // 200 + 带 Range：服务端不支持断点续传 → 整包重下（必须重置 offset，否则追加写坏文件）
    if (code === 200 && offset > 0) {
      plan.kind = ResumeDecision.KIND_SUCCESS;
      plan.reason = ResumeDecision.REASON_RESTART_NO_RANGE;
      return plan;
    }
    plan.kind = ResumeDecision.KIND_SUCCESS;
    return plan;
  }
}

/** `ResumeDecision.decide` 的输出（纯数据）。 */
export interface ResumePlan {
  kind: number;
  reason: string;
}
/**
 * 进度上报的**节流与速度换算**（对位上游 `publishProgress` 的前半段）。
 *
 * 为什么单独测：这段决定"通知栏多久刷新一次"和"速度数字从哪来"。
 *   1. 节流边界写错会多刷或少刷一帧；漏掉 `force` 会让"开始/暂停/完成"这些关键时刻
 *      也被压在节流里 → 用户看到通知停在旧进度；
 *   2. 速度用**本窗口**平均（`bytesSinceSpeed * 1000 / elapsed`），写成全程平均会越下越迟钝；
 *   3. `elapsed <= 0`（同一毫秒内两次调用）不能除零，否则 `Infinity B/S` 会直接显示到通知栏。
 */
export class ProgressThrottle {
  /** 是否应当上报（`force` 优先；其余按窗口判断，`>=` 语义）。 */
  static shouldNotify(force: boolean, now: number, lastNotifyAt: number, intervalMs: number): boolean {
    if (force) {
      return true;
    }
    return now - lastNotifyAt >= intervalMs;
  }

  /** 本窗口平均速度（B/s）；暂停、`elapsed <= 0`、无字节均为 0。 */
  static speed(bytesSinceSpeed: number, elapsedMs: number, paused: boolean): number {
    if (paused || elapsedMs <= 0) {
      return 0;
    }
    return bytesSinceSpeed * 1000 / elapsedMs;
  }

  /** 剩余毫秒：暂停 / 长度未知 / 速度未知 → -1；已下完 → 0（不给负数）。 */
  static remainingMillis(paused: boolean, total: number, downloaded: number, speed: number): number {
    if (paused || total <= 0 || speed <= 0) {
      return -1;
    }
    const left: number = total - downloaded;
    return left <= 0 ? 0 : left * 1000 / speed;
  }
}
export class ArchiverDownloader {
  private static sInstance: ArchiverDownloader | null = null;
  private static cookieProvider: ArchiverCookieProvider | null = null;

  static readonly CHROME_USER_AGENT: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static readonly PROXY_TYPE_DIRECT: number = 0;
  static readonly PROXY_TYPE_SYSTEM: number = 1;
  static readonly PROXY_TYPE_HTTP: number = 2;

  private taskIdGenerator: number = Date.now();
  private readonly listeners: Set<ArchiverDownloaderListener> =
    new Set<ArchiverDownloaderListener>();
  private readonly activeTasks: Map<number, ActiveTask> = new Map<number, ActiveTask>();

  private constructor() {
  }

  public static setCookieProvider(provider: ArchiverCookieProvider | null): void {
    ArchiverDownloader.cookieProvider = provider;
  }

  public static readHeaderIgnoreCase(header: Object, targetName: string): string | undefined {
    const keys: string[] = Object.keys(header);
    const wanted: string = targetName.toLowerCase();
    const record: Record<string, Object> = header as Record<string, Object>;
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (k.toLowerCase() === wanted) {
        const val: Object | undefined = record[k];
        return val !== undefined && val !== null ? String(val) : undefined;
      }
    }
    return undefined;
  }

  public static buildStreamHeaders(
    offset: number,
    cookieHeader: string,
    referer: string,
    userAgent: string
  ): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept-Encoding': 'identity',
      'User-Agent': userAgent.length > 0 ? userAgent : ArchiverDownloader.CHROME_USER_AGENT
    };
    if (offset > 0) {
      headers['Range'] = `bytes=${offset}-`;
    }
    if (cookieHeader.length > 0) {
      headers['Cookie'] = cookieHeader;
    }
    if (referer.length > 0) {
      headers['Referer'] = referer;
    }
    return headers;
  }

  public static resolveHttpProxyForStream(
    proxyType: number,
    proxyIp: string | null,
    proxyPort: number
  ): boolean | http.HttpProxy {
    if (proxyType === ArchiverDownloader.PROXY_TYPE_HTTP) {
      const trimmedHost: string = proxyIp !== null ? proxyIp.trim() : '';
      if (trimmedHost.length > 0 && proxyPort > 0 && proxyPort <= 65535) {
        const proxy: http.HttpProxy = {
          host: trimmedHost,
          port: Math.trunc(proxyPort),
          exclusionList: []
        };
        return proxy;
      }
      return true;
    }
    if (proxyType === ArchiverDownloader.PROXY_TYPE_DIRECT) {
      return false;
    }
    return true;
  }

  public static buildStreamRequestOptions(
    headers: Record<string, string>,
    usingProxy: boolean | http.HttpProxy,
    skipSslValidation: boolean
  ): http.HttpRequestOptions {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 60000,
      readTimeout: 60000,
      usingProxy: usingProxy,
      remoteValidation: skipSslValidation ? 'skip' : 'system'
    };
    return options;
  }

  public static getInstance(): ArchiverDownloader {
    if (ArchiverDownloader.sInstance === null) {
      ArchiverDownloader.sInstance = new ArchiverDownloader();
    }
    return ArchiverDownloader.sInstance;
  }

  public addListener(listener: ArchiverDownloaderListener): void {
    this.listeners.add(listener);
  }

  public removeListener(listener: ArchiverDownloaderListener): void {
    this.listeners.delete(listener);
  }

  public getProgress(gid: number): ArchiverProgress | null {
    const task: ActiveTask | undefined = this.activeTasks.get(gid);
    if (task === undefined) {
      return null;
    }
    return new ArchiverProgress(task.gid, task.taskId, task.downloaded, task.total, task.speed,
      task.paused);
  }

  private static suitableTitle(info: GalleryInfo, fallback: string): string {
    const suitable: string | null = EhUtils.getSuitableTitle(info);
    if (suitable !== null && suitable.length > 0) {
      return suitable;
    }
    if (info.title !== null && info.title !== undefined && info.title.length > 0) {
      return info.title;
    }
    if (info.titleJpn !== null && info.titleJpn !== undefined && info.titleJpn.length > 0) {
      return info.titleJpn;
    }
    return fallback;
  }

  public getActiveTasks(): ArchiverTaskSnapshot[] {
    const out: ArchiverTaskSnapshot[] = [];
    this.activeTasks.forEach((task: ActiveTask): void => {
      const info: GalleryInfo = task.galleryInfo;
      out.push(new ArchiverTaskSnapshot(
        task.gid,
        task.taskId,
        info.title !== null && info.title !== undefined && info.title.length > 0 ? info.title : task.fileName,
        info.uploader !== null && info.uploader !== undefined ? info.uploader : '',
        info.category,
        info.pages,
        info.rating,
        info.thumb !== null && info.thumb !== undefined ? info.thumb : '',
        task.downloaded,
        task.total,
        task.speed,
        task.paused,
        task.importing,
        task.fileName,
        info.titleJpn !== null && info.titleJpn !== undefined ? info.titleJpn : ''
      ));
    });
    return out;
  }

  /**
   * 对应上游 `start(context, info, url, fileName)`：先取消同 gid 的旧任务，再建新任务并持久化。
   */
  public async start(info: GalleryInfo, url: string, fileName: string): Promise<number> {
    await this.cancel(info.gid);
    this.taskIdGenerator++;
    const taskId: number = this.taskIdGenerator;
    Settings.putArchiverDownloadId(info.gid, taskId);
    Settings.putArchiverDownload(taskId, info);
    Settings.putArchiverDownloadUrl(taskId, url);
    Settings.putArchiverDownloadPaused(taskId, false);
    await this.startInternal(info, url, fileName, taskId, false);
    return taskId;
  }

  /**
   * 对应上游 `pause(gid)`：置暂停 → 写库 → 取消请求 → 强制发布一次进度。
   */
  public pause(gid: number): void {
    const task: ActiveTask | undefined = this.activeTasks.get(gid);
    if (task === undefined) {
      return;
    }
    if (task.paused) {
      return;
    }
    task.paused = true;
    task.speed = 0;
    Settings.putArchiverDownloadPaused(task.taskId, true);
    this.destroyRequest(task);
    this.publishProgress(task, true);
  }

  /**
   * 对应上游 `resume(gid)`：从当前文件长度续传。
   */
  public async resume(gid: number): Promise<void> {
    const task: ActiveTask | undefined = this.activeTasks.get(gid);
    if (task === undefined) {
      return;
    }
    if (!task.paused) {
      return;
    }
    await this.startInternal(task.galleryInfo, task.url, task.fileName, task.taskId, true);
  }

  /**
   * 对应上游 `cancel(gid)`：删文件、清设置、回调 onCancel、停通知。
   */
  public async cancel(gid: number): Promise<void> {
    const task: ActiveTask | undefined = this.activeTasks.get(gid);
    if (task === undefined) {
      return;
    }
    this.activeTasks.delete(gid);
    task.paused = false;
    this.destroyRequest(task);
    await this.deleteZipFileAsync(task.zipPath);
    await this.clearTaskSettings(gid, task.taskId);
    this.notifyCancel(gid, task.taskId);
    ArchiverDownloadService.stop();
  }

  /**
   * 对应上游 `startInternal(info, url, fileName, taskId, resumeFromFile)`。
   */
  private async startInternal(info: GalleryInfo, url: string, fileName: string, taskId: number,
    resumeFromFile: boolean): Promise<void> {
    const zipPath: string | null = this.resolveZipPath(fileName);
    if (zipPath === null) {
      await this.clearTaskSettings(info.gid, taskId);
      this.notifyFailure(info.gid, taskId, new Error('Cannot resolve archiver directory'));
      return;
    }

    let exists: boolean = false;
    let offset: number = 0;
    try {
      exists = await fs.access(zipPath);
    } catch (e) {
      exists = false;
    }
    if (!resumeFromFile && exists) {
      await this.deleteZipFileAsync(zipPath);
      exists = false;
    }
    if (resumeFromFile && exists) {
      try {
        const st: fs.Stat = await fs.stat(zipPath);
        offset = st.size;
      } catch (_e) {
        offset = 0;
      }
    }

    let task: ActiveTask | undefined = this.activeTasks.get(info.gid);
    if (task === undefined || task.taskId !== taskId) {
      task = new ActiveTask(taskId, info.gid, url, fileName, zipPath, info);
      this.activeTasks.set(info.gid, task);
    }
    const active: ActiveTask = task;
    active.paused = false;
    active.handled416 = false;
    active.downloaded = offset;
    active.speed = 0;
    active.bytesSinceSpeed = 0;
    active.lastSpeedAt = Date.now();
    active.lastNotifyAt = 0;
    Settings.putArchiverDownloadPaused(taskId, false);
    const savedTotal: number = Settings.getArchiverDownloadTotal(taskId);
    if (savedTotal > 0) {
      active.total = savedTotal;
    }

    ArchiverDownloadService.start(ArchiverDownloader.suitableTitle(info, fileName), info.gid, info.token);

    const cookieHeader: string = ArchiverDownloader.cookieProvider !== null
      ? ArchiverDownloader.cookieProvider(url)
      : '';
    const referer: string = (info.gid > 0 && info.token.length > 0)
      ? EhUrl.getGalleryDetailUrlSimple(info.gid, info.token)
      : '';
    const headers: Record<string, string> = ArchiverDownloader.buildStreamHeaders(
      offset, cookieHeader, referer, ArchiverDownloader.CHROME_USER_AGENT);
    const usingProxy: boolean | http.HttpProxy = ArchiverDownloader.resolveHttpProxyForStream(
      Settings.getProxyType(), Settings.getProxyIp(), Settings.getProxyPort());
    const options: http.HttpRequestOptions = ArchiverDownloader.buildStreamRequestOptions(
      headers, usingProxy, Settings.getDF());
    hilog.info(DOMAIN, TAG,
      'startInternal gid=%{public}d taskId=%{public}d offset=%{public}d proxyMode=%{public}d hasCookie=%{public}s url=%{public}s',
      info.gid, taskId, offset, Settings.getProxyType(), cookieHeader.length > 0 ? 'true' : 'false', url);

    // 立即推送一次初始进度，确保详情页与下载页实时呈现新建任务
    this.publishProgress(active, true);
    void this.runStream(active, options, offset, resumeFromFile);
  }

  /**
   * 真正的下载执行体：`requestInStream` + 异步分块写盘 + 代理/Cookie 注入 + dataEnd/resolve 同步收口。
   * 与上游 `call.enqueue({ onFailure, onResponse })` 一一对应。
   */
  private async runStream(task: ActiveTask, options: http.HttpRequestOptions, offset: number,
    resumeFromFile: boolean): Promise<void> {
    let fd: number = -1;
    let append: boolean = offset > 0;
    let effectiveStartOffset: number = offset;
    let writeOffset: number = offset;
    let responseCode: number = 0;
    let contentRangeTotal: number = 0;
    let contentLength: number = 0;
    let writeChain: Promise<void> = Promise.resolve();
    let failed: boolean = false;
    let dataEnded: boolean = false;
    let streamResolved: boolean = false;
    let finalized: boolean = false;

    const request: http.HttpRequest = http.createHttp();
    task.request = request;

    const ensureFdAsync = async (path: string): Promise<number> => {
      if (fd !== -1) {
        return fd;
      }
      if (append) {
        const opened: fs.File = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
        fd = opened.fd;
      } else {
        const opened: fs.File = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fd = opened.fd;
      }
      return fd;
    };

    const tryFinalize = (): void => {
      if (!dataEnded || !streamResolved || finalized) {
        return;
      }
      finalized = true;
      writeChain.then(async (): Promise<void> => {
        await this.closeFdAsync(fd);
        fd = -1;
        if (failed) {
          await this.handleStreamFailure(task, task.zipPath, new Error('Write failed'), request);
          return;
        }
        if (task.request !== request) {
          return;
        }
        if (task.paused) {
          this.publishProgress(task, true);
          return;
        }
        const resume: ResumePlan = ResumeDecision.decide(responseCode, offset);
        if (resume.kind === ResumeDecision.KIND_COMPLETE_ALREADY) {
          await this.handleRangeNotSatisfiable(task, task.zipPath);
          return;
        }
        if (resume.kind === ResumeDecision.KIND_UNKNOWN) {
          hilog.warn(DOMAIN, TAG,
            'responseCode 未知（headersReceive 未触发或键名不匹配），保留文件待重试: %{public}s', task.zipPath);
          this.toast('无法确认服务器状态，已保留已下载的部分，请稍后重试');
          this.publishProgress(task, true);
          return;
        }
        if (resume.kind === ResumeDecision.KIND_FAILED) {
          await this.handleStreamFailure(task, task.zipPath, new Error(`HTTP ${responseCode}`), request);
          return;
        }
        if (resume.reason === ResumeDecision.REASON_RESTART_NO_RANGE) {
          this.toast('服务器不支持断点续传，已从头重新下载');
        }
        const resolvedTotal: number = ArchiverDownloader.resolveTotal(contentRangeTotal, effectiveStartOffset, contentLength);
        if (resolvedTotal > 0) {
          task.total = resolvedTotal;
          Settings.putArchiverDownloadTotal(task.taskId, resolvedTotal);
        }
        if (!ArchiverDownloader.isCurrentTask(this.activeTasks, task)) {
          return;
        }
        hilog.info(DOMAIN, TAG,
          'archiver stream completed gid=%{public}d taskId=%{public}d bytes=%{public}d total=%{public}d',
          task.gid, task.taskId, writeOffset, task.total);
        task.importing = true;
        task.speed = 0;
        task.paused = false;
        this.publishProgress(task, true);
        await ArchiverDownloadCompleter.getInstance().importDownloadedZip(task.zipPath, task.galleryInfo,
          task.taskId);
        this.activeTasks.delete(task.gid);
        this.notifySuccess(task.gid, task.taskId, task.zipPath);
        await this.clearTaskSettings(task.gid, task.taskId);
        ArchiverDownloadService.stop();
      }).catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, 'finalize failed: %{public}s', this.errorToString(e));
      });
    };

    request.on('headersReceive', (header: Object): void => {
      const codeText: string | undefined = ArchiverDownloader.readHeaderIgnoreCase(header, 'responseCode');
      if (codeText !== undefined) {
        const parsedCode: number = Number(codeText);
        if (!isNaN(parsedCode) && parsedCode > 0) {
          responseCode = parsedCode;
        }
      }
      const range: string | undefined = ArchiverDownloader.readHeaderIgnoreCase(header, 'content-range');
      if (range !== undefined) {
        contentRangeTotal = ArchiverDownloader.parseContentRangeTotal(range);
      }
      const length: string | undefined = ArchiverDownloader.readHeaderIgnoreCase(header, 'content-length');
      if (length !== undefined) {
        const parsedLen: number = Number(length);
        if (!isNaN(parsedLen) && parsedLen > 0) {
          contentLength = parsedLen;
        }
      }
      const knownTotal: number = ArchiverDownloader.resolveTotal(contentRangeTotal, offset, contentLength);
      if (knownTotal > 0) {
        task.total = knownTotal;
        Settings.putArchiverDownloadTotal(task.taskId, knownTotal);
        this.publishProgress(task, true);
      }
      hilog.info(DOMAIN, TAG,
        'headersReceive gid=%{public}d code=%{public}d contentLen=%{public}d total=%{public}d',
        task.gid, responseCode, contentLength, task.total);

      // L-06：服务端忽略 Range（200 + 我们带了 Range）→ 排入写链立刻从头截断重开句柄
      if (ResumeDecision.isRangeIgnored(responseCode, offset)) {
        append = false;
        effectiveStartOffset = 0;
        writeOffset = 0;
        task.downloaded = 0;
        writeChain = writeChain.then(async (): Promise<void> => {
          if (fd !== -1) {
            await this.closeFdAsync(fd);
            fd = -1;
          }
          try {
            if (await fs.access(task.zipPath)) {
              await fs.truncate(task.zipPath, 0);
            }
          } catch (_e) {
            // ignore truncate failure
          }
        });
        hilog.warn(DOMAIN, TAG,
          'server ignored Range (200 with offset=%{public}d) → restart from 0', offset);
      }
    });

    request.on('dataReceive', (chunk: ArrayBuffer): void => {
      if (task.paused || task.request !== request) {
        return;
      }
      writeChain = writeChain.then(async (): Promise<void> => {
        if (task.paused || task.request !== request) {
          throw new PauseSignal();
        }
        const handle: number = await ensureFdAsync(task.zipPath);
        await fs.write(handle, chunk);
        writeOffset += chunk.byteLength;
        task.downloaded = writeOffset;
        task.bytesSinceSpeed += chunk.byteLength;
        this.publishProgress(task, false);
      }).catch((e: Object) => {
        if (e instanceof PauseSignal) {
          return;
        }
        failed = true;
        hilog.error(DOMAIN, TAG, 'write chunk failed: %{public}s', this.errorToString(e));
      });
    });

    request.on('dataEnd', (): void => {
      dataEnded = true;
      tryFinalize();
    });

    request.requestInStream(task.url, options).then(async (code: number): Promise<void> => {
      if (task.request !== request) {
        return;
      }
      if (task.paused) {
        this.publishProgress(task, true);
        return;
      }
      if (!ArchiverDownloader.isCurrentTask(this.activeTasks, task)) {
        return;
      }
      responseCode = code;
      streamResolved = true;
      if (code === 416) {
        finalized = true;
        await writeChain.catch((err: Object): void => {
          hilog.debug(DOMAIN, TAG, 'writeChain drain on 416 ignored: %{public}s', this.errorToString(err));
        });
        await this.closeFdAsync(fd);
        fd = -1;
        await this.handleRangeNotSatisfiable(task, task.zipPath);
        return;
      }
      if (code !== 200 && code !== 206) {
        finalized = true;
        await writeChain.catch((err: Object): void => {
          hilog.debug(DOMAIN, TAG, 'writeChain drain on HTTP error ignored: %{public}s', this.errorToString(err));
        });
        await this.closeFdAsync(fd);
        fd = -1;
        await this.handleStreamFailure(task, task.zipPath, new Error(`HTTP ${code}`), request);
        return;
      }
      tryFinalize();
    }).catch((e: BusinessError) => {
      if (task.request !== request) {
        return;
      }
      if (task.paused) {
        this.publishProgress(task, true);
        return;
      }
      if (!ArchiverDownloader.isCurrentTask(this.activeTasks, task)) {
        return;
      }
      finalized = true;
      hilog.error(DOMAIN, TAG, 'archiver request failed: gid=%{public}d, taskId=%{public}d, url=%{public}s, ' +
        'err=%{public}s; 后果：任务中止并通知失败', task.gid, task.taskId, task.url,
        this.errorToString(e));
      writeChain.catch((err: Object): void => {
        hilog.debug(DOMAIN, TAG, 'writeChain cleanup ignored: %{public}s', this.errorToString(err));
      }).finally((): void => {
        this.closeFdAsync(fd).then((): void => {
          fd = -1;
        }).catch((closeErr: Object): void => {
          hilog.debug(DOMAIN, TAG, 'closeFdAsync cleanup ignored: %{public}s', this.errorToString(closeErr));
        });
      });
      this.activeTasks.delete(task.gid);
      void this.deleteZipFileAsync(task.zipPath);
      this.clearTaskSettings(task.gid, task.taskId).catch((err: Object): void => {
        hilog.error(DOMAIN, TAG, 'cleanup settings failed: %{public}s', this.errorToString(err));
      });
      this.notifyFailure(task.gid, task.taskId, new Error(e.message));
      ArchiverDownloadService.stop();
    });

    if (resumeFromFile) {
      hilog.info(DOMAIN, TAG, 'Resumed archiver download, taskId=%{public}d, gid=%{public}d, offset=%{public}d',
        task.taskId, task.gid, offset);
    }
  }

  /**
   * 对应上游 `handleRangeNotSatisfiable(task, zipFile, info, taskId)`。
   */
  private async handleRangeNotSatisfiable(task: ActiveTask, zipPath: string): Promise<void> {
    // L-15：416 有**两条到达路径**（dataEnd 的 decide 结果 / requestInStream 的 resolve 值），
    // 本函数是唯一汇合点。靠 `activeTasks` 反查挡不住（第一次已 delete(gid)，第二次 cur===undefined
    // 反而会让其它守卫放行），所以用**任务自身的幂等标记**：同一任务只处理一次 416。
    // ① 身份判据（与 handleStreamFailure 同）：`pause → resume` 后对象被替换，
    //    旧请求的 416 若在这里放行，会 `delete(task.gid)` 删掉**新任务**的登记 + `deleteZipFile` 删掉**新任务的 zip**。
    //    放在 handled416 之前：先把"我不是当前任务"挡掉，幂等标记只服务"同一任务的两次 416"。
    // 顺序由纯谓词钉住（可断言）：**身份判据在前，幂等标记在后**。
    // 反过来写（幂等在前）也能通过"旧任务不重复处理"的断言，但会**误删新任务**的 zip 与 Settings。
    if (!ArchiverDownloader.shouldHandle416(
      ArchiverDownloader.isCurrentTask(this.activeTasks, task), task.handled416)) {
      return;
    }
    task.handled416 = true;

    const total: number = task.total > 0 ? task.total : Settings.getArchiverDownloadTotal(task.taskId);
    let size: number = 0;
    try {
      size = (await fs.stat(zipPath)).size;
    } catch (e) {
      size = 0;
    }
    if (size > 0 && total > 0 && size >= total) {
      task.importing = true;
      task.speed = 0;
      task.paused = false;
      this.publishProgress(task, true);
      await ArchiverDownloadCompleter.getInstance().importDownloadedZip(zipPath, task.galleryInfo, task.taskId);
      this.activeTasks.delete(task.gid);
      this.notifySuccess(task.gid, task.taskId, zipPath);
      await this.clearTaskSettings(task.gid, task.taskId);
      ArchiverDownloadService.stop();
      return;
    }
    if (task.paused) {
      this.publishProgress(task, true);
      return;
    }
    this.activeTasks.delete(task.gid);
    await this.deleteZipFileAsync(zipPath);
    await this.clearTaskSettings(task.gid, task.taskId);
    this.notifyFailure(task.gid, task.taskId, new Error('HTTP 416'));
    ArchiverDownloadService.stop();
  }

  /**
   * 身份判据（L-14）：`activeTasks` 里登记的、属于这个 gid 的任务，**是不是我自己**。
   *
   * 原来的判据是 `activeTasks.get(task.gid)?.taskId !== task.taskId` —— 看起来合理，
   * 但 `pause → resume` 时 **taskId 不变而对象被替换**，于是旧请求的回调会通过这道守卫，
   * 去删掉新任务的 zip 与 Settings。改成**引用比较**才真正回答"我还是当前任务吗"。
   *
   * 返回 `true` 表示"仍是当前任务，应继续处理"；`false` 表示"已是旧任务，调用方应早退"。
   */
  private static isCurrentTask(activeTasks: Map<number, ActiveTask>, task: ActiveTask): boolean {
    const cur: ActiveTask | undefined = activeTasks.get(task.gid);
    return ArchiverDownloader.isSameTask(cur, task);
  }

  /**
   * 身份判据的**核心**（可测）：`registered` 是否就是 `task` 本体。
   *
   * 为什么单列：`ActiveTask` 未导出，测试无法构造它；但"两个不同对象即使字段全等也不是同一个"
   * 这个语义必须能被断言钉住 —— 这正是 L-14 的 bug 形态（pause→resume 后 taskId 不变、对象被换）。
   */
  /**
   * 416 是否该由**本次调用**处理（顺序判据，可断言）。
   *
   * @param isCurrent   本任务是否仍是 `activeTasks` 里登记的那个（`isCurrentTask(...)`）
   * @param handled416  本任务是否已经处理过 416（幂等标记）
   *
   * **顺序必须如此**：身份在前 —— 旧任务的 416 到达时（`isCurrent=false`）必须**直接丢弃**，
   * 不能去看它的 `handled416`（那是**旧对象**上的标记，新任务根本没被标记过 → 会误删新任务）。
   * 幂等在后 —— 只服务"同一任务被两条路径各触发一次"。
   */
  static shouldHandle416(isCurrent: boolean, handled416: boolean): boolean {
    if (!isCurrent) {
      return false;
    }
    return !handled416;
  }

  static isSameTask(registered: Object | undefined, task: Object): boolean {
    return registered === task;
  }

  /** 是否应因身份过期（已取消或已被 resume 替换）而丢弃该回调。 */
  static shouldDropTaskCallback(registered: Object | undefined, task: Object): boolean {
    return !ArchiverDownloader.isSameTask(registered, task);
  }
  /** 上游 onResponse/onFailure 里共用的"失败收尾"三步 + 停通知。 */
  private async handleStreamFailure(task: ActiveTask, zipPath: string, e: Error,
    request: http.HttpRequest | null = null): Promise<void> {
    // L-14：原来是 `task.request !== task.request` —— **同一个对象自比较，恒 false**，守卫形同虚设。
    // 上游是 `task.call !== call`（两个不同来源）。这里用调用方传入的 request 比较；
    // 传 null 表示"不检查身份"（仅限不经过 runStream 的调用路径）。
    if (request !== null && task.request !== request) {
      return;
    }
    if (task.paused) {
      this.publishProgress(task, true);
      return;
    }
    if (!ArchiverDownloader.isCurrentTask(this.activeTasks, task)) {
      return;
    }
    this.activeTasks.delete(task.gid);
    await this.deleteZipFileAsync(zipPath);
    await this.clearTaskSettings(task.gid, task.taskId);
    this.notifyFailure(task.gid, task.taskId, e);
    ArchiverDownloadService.stop();
  }

  /**
   * 对应上游 `publishProgress(task, force)`：500ms 节流 + 速度换算 + 通知栏刷新。
   */
  private publishProgress(task: ActiveTask, force: boolean): void {
    const now: number = Date.now();
    if (!ProgressThrottle.shouldNotify(force, now, task.lastNotifyAt, NOTIFY_INTERVAL_MS)) {
      return;
    }
    const elapsed: number = now - task.lastSpeedAt;
    if (elapsed > 0) {
      task.speed = ProgressThrottle.speed(task.bytesSinceSpeed, elapsed, task.paused);
    }
    task.bytesSinceSpeed = 0;
    task.lastSpeedAt = now;
    task.lastNotifyAt = now;
    const remaining: number = ArchiverDownloader.remainingMillis(task);
    this.notifyProgress(task.gid, task.downloaded, task.total, task.speed, task.paused);
    ArchiverDownloadService.updateProgress(
      ArchiverDownloader.suitableTitle(task.galleryInfo, task.fileName),
      task.gid,
      task.galleryInfo.token,
      task.downloaded,
      task.total,
      task.speed,
      remaining,
      task.paused
    );
  }

  private static remainingMillis(task: ActiveTask): number {
    return ProgressThrottle.remainingMillis(task.paused, task.total, task.downloaded, task.speed);
  }

  /** 对应上游 `resolveZipFile(fileName)`：外部归档目录优先，其次内部目录。 */
  private resolveZipPath(fileName: string): string | null {
    const dir: string | null = AppConfig.getExternalArchiverDir() ?? AppConfig.getArchiverDir();
    if (dir === null) {
      return null;
    }
    return `${dir}/${fileName}.zip`;
  }

  /**
   * 清理某任务在 Settings 里的 5 个键。
   *
   * **必须 await**：core-runtime 把这 5 个 delete 改成了 `Promise<boolean>`
   * （上游删路径用 `commit()` 同步落盘，ArkTS 只有异步 `flush()`）。
   * 不 await 会拿到 Promise 对象（永远 truthy），逻辑上等价于"永远删成功" —— 比原来的 fire-and-forget 更糟。
   */
  private async clearTaskSettings(gid: number, taskId: number): Promise<void> {
    await Settings.deleteArchiverDownloadId(gid);
    await Settings.deleteArchiverDownload(taskId);
    await Settings.deleteArchiverDownloadUrl(taskId);
    await Settings.deleteArchiverDownloadPaused(taskId);
    await Settings.deleteArchiverDownloadTotal(taskId);
  }

  private async deleteZipFileAsync(zipPath: string | null): Promise<void> {
    if (zipPath === null) {
      return;
    }
    const candidates: string[] = [zipPath, `${zipPath}.part`];
    for (let i = 0; i < candidates.length; i++) {
      const target: string = candidates[i];
      try {
        if (await fs.access(target)) {
          await fs.unlink(target);
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Failed to delete zip: %{public}s', target);
      }
    }
  }

  /** 丢弃底层请求（`destroy()` = 上游 `call.cancel()`）。 */
  private destroyRequest(task: ActiveTask): void {
    const request: http.HttpRequest | null = task.request;
    if (request === null) {
      return;
    }
    try {
      request.off('dataReceive');
      request.off('dataEnd');
      request.off('headersReceive');
      request.destroy();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'destroy request failed: %{public}s', this.errorToString(e as Object));
    }
    task.request = null;
  }

  private async closeFdAsync(fd: number): Promise<void> {
    if (fd === -1) {
      return;
    }
    try {
      await fs.close(fd);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'close fd failed: %{public}s', this.errorToString(e as Object));
    }
  }

  private notifyProgress(gid: number, downloaded: number, total: number, speed: number,
    paused: boolean): void {
    this.listeners.forEach((listener: ArchiverDownloaderListener): void => {
      listener.onProgress(gid, downloaded, total, speed, paused);
    });
  }

  private notifySuccess(gid: number, taskId: number, zipPath: string): void {
    this.listeners.forEach((listener: ArchiverDownloaderListener): void => {
      listener.onSuccess(gid, taskId, zipPath);
    });
  }

  private notifyFailure(gid: number, taskId: number, e: Error): void {
    this.listeners.forEach((listener: ArchiverDownloaderListener): void => {
      listener.onFailure(gid, taskId, e);
    });
  }

  private notifyCancel(gid: number, taskId: number): void {
    this.listeners.forEach((listener: ArchiverDownloaderListener): void => {
      listener.onCancel(gid, taskId);
    });
  }

  private toast(message: string): void {
    ArchiverDownloadCompleter.showToastSafely(message, 3000);
  }

  // -------------------------------------------------------------- 静态工具

  /**
   * 对应上游 `resumePending(context)`：启动时恢复未完成任务。
   * 已下完的直接进导入流程；暂停的只登记状态；其余续传。
   *
   * **前置条件（必须）**：调用前 `Settings.attach(context)` 已完成。
   * 上游 `Settings` 的方法都是同步的；ArkTS 的 `Preferences.getAll()` 异步，core-runtime 在
   * `attach()` 时把 archiver 键值载入内存快照。**未 attach 时 `getPendingArchiverDownloadIds()`
   * 返回空数组**，本方法会静默什么都不恢复（正是最难查的那类问题），因此这里显式告警。
   *
   * 另外：`getPendingArchiverDownloadIds()` 扫的是 **`gid + "DId"` 键的值（taskId）**，
   * 不是 `Url` 键（`Url` 的值是字符串，扫它永远拿不到 id）。
   */
  public static async resumePending(): Promise<void> {
    if (!Settings.isAttached()) {
      hilog.error(DOMAIN, TAG,
        'resumePending called before Settings.attach() —— pendingIds 会是空数组，' +
        '归档断点续传将静默不恢复。请确保在 Settings.attach(context) 之后调用。');
    }
    const downloader: ArchiverDownloader = ArchiverDownloader.getInstance();
    const pendingIds: number[] = Settings.getPendingArchiverDownloadIds();
    if (pendingIds.length === 0) {
      hilog.info(DOMAIN, TAG, 'resumePending: no pending archiver download');
    }
    for (let i = 0; i < pendingIds.length; i++) {
      const taskId: number = pendingIds[i];
      const info: GalleryInfo | null = Settings.getArchiverDownload(taskId);
      if (info === null) {
        await Settings.deleteArchiverDownloadUrl(taskId);
        await Settings.deleteArchiverDownloadPaused(taskId);
        await Settings.deleteArchiverDownloadTotal(taskId);
        continue;
      }
      if (downloader.activeTasks.has(info.gid)) {
        continue;
      }
      const url: string | null = Settings.getArchiverDownloadUrl(taskId);
      const primaryTitle: string = ArchiverDownloader.suitableTitle(info, '');
      let fileName: string = ArchiverDownloadCompleter.createFileName(primaryTitle, info.gid);
      let zipPath: string | null = downloader.resolveZipPath(fileName);
      // 若用户切换过“显示日文标题”，兜底探测按英文/日文标题生成的历史未完成包名
      const altTitles: string[] = [info.title ?? '', info.titleJpn ?? ''];
      for (let t = 0; t < altTitles.length; t++) {
        const candidateName: string = ArchiverDownloadCompleter.createFileName(altTitles[t], info.gid);
        const candidatePath: string | null = downloader.resolveZipPath(candidateName);
        if (candidatePath !== null && zipPath !== candidatePath) {
          let existsZip: boolean = false;
          try {
            existsZip = (await fs.stat(candidatePath)).size > 0;
          } catch (_stErr) {
            existsZip = false;
          }
          if (!existsZip) {
            try {
              existsZip = (await fs.stat(candidatePath + '.part')).size > 0;
            } catch (_partErr) {
              existsZip = false;
            }
          }
          if (existsZip) {
            fileName = candidateName;
            zipPath = candidatePath;
            break;
          }
        }
      }
      if (zipPath === null) {
        await downloader.clearTaskSettings(info.gid, taskId);
        downloader.toast('下载失败');
        continue;
      }
      const total: number = Settings.getArchiverDownloadTotal(taskId);
      let size: number = 0;
      try {
        size = (await fs.stat(zipPath)).size;
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'stat zip failed (treat as size 0): %{public}s', zipPath);
        size = 0;
      }
      if (size > 0 && total > 0 && size >= total) {
        await ArchiverDownloadCompleter.getInstance().importDownloadedZip(zipPath, info, taskId);
        // 同修 2：这条分支也必须清，否则每次启动都会重新导入同一个归档（重复标签 + 重复记录）
        await downloader.clearTaskSettings(info.gid, taskId);
        continue;
      }
      if (url === null || url.length === 0) {
        await downloader.clearTaskSettings(info.gid, taskId);
        downloader.toast('下载失败');
        continue;
      }
      if (Settings.getArchiverDownloadPaused(taskId)) {
        const task: ActiveTask = new ActiveTask(taskId, info.gid, url, fileName, zipPath, info);
        task.paused = true;
        task.downloaded = size;
        task.total = total > 0 ? total : 0;
        downloader.activeTasks.set(info.gid, task);
        downloader.publishProgress(task, true);
        continue;
      }
      downloader.startInternal(info, url, fileName, taskId, true);
    }
  }

  /**
   * 对应上游 `resolveTotal(response, offset, contentLength)`：
   * `Content-Range: bytes a-b/total` 的 total 优先，其次 offset + contentLength。
   */
  public static resolveTotal(contentRangeTotal: number, offset: number, contentLength: number): number {
    if (contentRangeTotal > 0) {
      return contentRangeTotal;
    }
    return contentLength > 0 ? offset + contentLength : 0;
  }

  /** 从 `Content-Range: bytes 100-999/1000` 里取总长度；取不到返回 0（等价 `"*"` 分支）。 */
  public static parseContentRangeTotal(contentRange: string): number {
    const slash: number = contentRange.lastIndexOf('/');
    if (slash < 0 || slash >= contentRange.length - 1) {
      return 0;
    }
    const totalStr: string = contentRange.substring(slash + 1).trim();
    if (totalStr === '*') {
      return 0;
    }
    const parsed: number = Number(totalStr);
    if (!isNaN(parsed) && parsed > 0) {
      return parsed;
    }
    return 0;
  }

  public static getBufferSize(): number {
    return BUFFER_SIZE;
  }

  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }
}
