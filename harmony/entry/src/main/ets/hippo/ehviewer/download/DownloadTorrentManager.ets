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
 * 移植自 app/src/main/java/com/hippo/ehviewer/download/DownloadTorrentManager.kt（185 行含注释 / 167 逻辑行）。
 *
 * 职责：种子（`.torrent`）文件下载工具 —— 下载到归档目录、已存在则秒回 100%、
 * 逐块写盘并回报进度、失败/成功都回调 `Handler`。
 *
 * ============================================================================
 * 平台差异
 * ============================================================================
 *   D-θ-1 `Handler` + `Message` + `Bundle.putParcelable("torrent_download_message")` →
 *          导出的 `TorrentDownloadHandler` 接口（`onMessage(message)`）。
 *          上游把消息塞 Bundle 是为了跨进程/跨线程传递；鸿蒙侧回调本身就是同进程对象传递，
 *          再包一层 Bundle 没有意义（也拿不到 Bundle 的 Parcelable 语义）。
 *   D-θ-2 传输：`.torrent` 文件只有 KB 量级，用 net-parse 的 okhttp 壳即可
 *          （`call.execute()` → `body.bytes()`）。**注意**：该壳的 `ResponseBody` 是全量缓冲实现
 *          （见 `ArchiverDownloader` 文件头 D-ζ），因此进度粒度从"每 2048 字节一次"退化为
 *          "0% → 100%"两跳。对方是 KB 级小文件，可见行为（写完、返回路径、失败回调）不变；
 *          如需真实分块进度，与 D-ζ 一样走 `@ohos.net.http.requestInStream`。
 *   D-θ-3 `Environment.getExternalStorageDirectory()` → `AppConfig` 的归档/下载目录
 *          （鸿蒙无公共 SD 卡路径语义；沙箱内应用目录 + 用户授权的 DocumentViewPicker 目录）。
 *   D-θ-4 `File.mkdirs()` 失败就 `createNewFile()` 的怪逻辑保留（见 `isExistDir`）：
 *          上游这两句是为了"路径被占成文件时也能发现"，但 `createNewFile` 会抛 IOException
 *          被外层 catch 吞掉 → 等价于"尽力创建目录"。鸿蒙侧用 `fs.mkdirSync` + `accessSync` 复刻。
 *
 * 其余等价点：
 *   1. `getNameFromUrl(url)` = `url.substring(url.lastIndexOf("/") + 1)`（含无斜杠时返回整串）。
 *   2. 目标文件已存在 → `EhApplication.removeDownloadTorrent(url)` + 回 100% + `failed=false`。
 *   3. 开始前先回一条 `progress = 0`（注意上游这里传的是 `saveDir` 而不是 `savePath`，保留）。
 *   4. 成功回 `progress = 100`；异常回 `progress = -1, failed = true`。
 *   5. 失败路径（onFailure / 写盘异常 / 读取异常）都要 `removeDownloadTorrent(url)`。
 *   6. 单例 `get()`（上游 `get(okHttpClient)` 双检；这里忽略 okHttpClient 参数，
 *      由 `EhApplication` 统一持有客户端）。
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { EhApplication } from '../EhApplication';
import { AppConfig } from '../AppConfig';
import { EhRequestBuilder } from '../client/EhRequestBuilder';
import { TorrentDownloadMessage } from '../client/data/TorrentDownloadMessage';
import { FileUtils as YorozuyaFileUtils } from '../../lib/yorozuya/FileUtils';
import { Call, Callback } from '../../okhttp/Call';
import { OkHttpClient } from '../../okhttp/OkHttpClient';
import { Request } from '../../okhttp/Request';
import { Response } from '../../okhttp/Response';
import { ResponseBody } from '../../okhttp/ResponseBody';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'DownloadTorrentManager';

/** 每次从响应体读多少字节（上游 `ByteArray(2048)`）。 */
const BUFFER_SIZE: number = 2048;

/**
 * 上游 `Handler` 的等价物：调用方实现 `onMessage` 接收进度/结果。
 * `message.key` 恒为 `TorrentDownloadMessage.KEY`（上游 `data.putParcelable("torrent_download_message", ...)`）。
 */
export interface TorrentDownloadHandler {
  onMessage(message: TorrentDownloadMessage): void;
}

export class DownloadTorrentManager {
  private static instance: DownloadTorrentManager | null = null;

  private okHttpClient: OkHttpClient | null = null;
  private readonly usesAppClient: boolean;
  private handler: TorrentDownloadHandler | null = null;

  private constructor(okHttpClient: OkHttpClient | null, usesAppClient: boolean) {
    this.okHttpClient = okHttpClient;
    this.usesAppClient = usesAppClient;
  }

  /** 对应上游 `companion object { fun get(okHttpClient) }`（单例）。 */
  public static get(okHttpClient: OkHttpClient | null): DownloadTorrentManager {
    if (DownloadTorrentManager.instance === null) {
      const usesApp: boolean = okHttpClient === null;
      DownloadTorrentManager.instance = new DownloadTorrentManager(
        usesApp ? EhApplication.getOkHttpClient(null) : okHttpClient, usesApp);
    }
    return DownloadTorrentManager.instance;
  }

  /**
   * 对应上游 `download(url, saveDir, name, handler, context)`。
   *
   * @param url 种子文件地址
   * @param saveDir 保存目录
   * @param name 文件名
   * @param handler 进度/结果回调
   */
  public download(url: string, saveDir: string, name: string, handler: TorrentDownloadHandler | null): void {
    this.handler = handler;
    const request: Request = EhRequestBuilder.of(url).build();

    let savePath: string | null = null;
    try {
      savePath = this.isExistDir(saveDir);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'isExistDir failed: %{public}s', this.errorToString(e as Object));
    }
    const dir: string | null = savePath;
    const targetPath: string = dir === null ? name : `${dir}/${name}`;

    if (dir !== null && this.exists(targetPath)) {
      EhApplication.removeDownloadTorrent(url);
      this.sendMessage(targetPath, dir, name, 100, false);
      return;
    }

    // 上游这里传的是 saveDir（不是 savePath），保留
    this.sendMessage(targetPath, saveDir, name, 0, false);

    const client: OkHttpClient | null = this.usesAppClient
      ? EhApplication.getOkHttpClient(null)
      : this.okHttpClient;
    if (client === null) {
      EhApplication.removeDownloadTorrent(url);
      this.sendMessage(url, dir, name, -1, true);
      return;
    }

    client.newCall(request).enqueue(new TorrentCallback(this, url, targetPath, dir, name));
  }

  /**
   * 对应上游 `isExistDir(saveDir)`：目录不存在则创建；返回绝对路径。
   * D-θ-4：上游 `mkdirs()` 失败后调 `createNewFile()`（会抛 IOException，被调用方 catch），
   * 这里保留"创建成功或已存在都返回路径，否则抛错"的净效果。
   */
  private isExistDir(saveDir: string): string {
    try {
      if (!fs.accessSync(saveDir)) {
        fs.mkdirSync(saveDir);
      }
    } catch (e) {
      // 上游同样把这里当异常往上抛（由 download() 的 catch 吞掉）
      throw e as Error;
    }
    return saveDir;
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private sendMessage(path: string, dir: string | null, name: string, progress: number,
    failed: boolean): void {
    const handler: TorrentDownloadHandler | null = this.handler;
    if (handler === null) {
      return;
    }
    const message: TorrentDownloadMessage = new TorrentDownloadMessage();
    message.failed = failed;
    message.progress = progress;
    // 上游 `TorrentDownloadMessage.dir` 是 Kotlin `String?`（`var dir: String? = null`）；
    // net-parse 的 ArkTS 端口把它收成了非空 `dir: string = ''`，于是"无目录"只能用空串表达。
    // 这里 `?? ''` 在两种实现下都能编译：net-parse 若改回 `string | null`，此行依旧成立。
    message.dir = dir ?? '';
    message.path = path;
    message.name = name;
    handler.onMessage(message);
  }

  /** 供回调类访问（ArkTS 无内部类，故通过包内方法转发）。 */
  public onResponseBody(url: string, body: ResponseBody, targetPath: string, dir: string | null,
    name: string): void {
    let fd: number = -1;
    try {
      const total: number = body.contentLength();
      const bytes: ArrayBuffer = body.bytes();
      if (bytes.byteLength <= 0) {
        EhApplication.removeDownloadTorrent(url);
        this.sendMessage(targetPath, dir, name, -1, true);
        return;
      }
      // API 20 起 fs.openSync 返回 File 对象（fd 在 .fd 上）
      const opened: fs.File = fs.openSync(targetPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fd = opened.fd;

      let sum: number = 0;
      const totalBytes: number = bytes.byteLength;
      // 上游用 2048 字节缓冲循环读；这里用 bytes.slice(offset, end) 取独立分块落盘，
      // 不能对 subarray 直接取 .buffer（subarray.buffer 仍指向完整底层 ArrayBuffer，会重复写整份内容）。
      for (let offset = 0; offset < totalBytes; offset += BUFFER_SIZE) {
        const end: number = Math.min(offset + BUFFER_SIZE, totalBytes);
        const slice: ArrayBuffer = DownloadTorrentManager.sliceChunk(bytes, offset, end);
        fs.writeSync(fd, slice);
        sum += slice.byteLength;
        const progress: number = total > 0 ? Math.floor(sum * 100 / total) : 100;
        this.sendMessage(targetPath, dir, name, progress, false);
      }

      EhApplication.removeDownloadTorrent(url);
      this.sendMessage(targetPath, dir, name, 100, false);
    } catch (e) {
      // 三段式：操作 + 关键标识 + 后果（只写"失败"排查时无从下手）
      hilog.error(DOMAIN, TAG, 'torrent write failed: url=%{public}s, path=%{public}s, err=%{public}s; ' +
        '后果：种子未落盘，已回滚通知并上报 failed 消息', url, targetPath,
        this.errorToString(e as Object));
      EhApplication.removeDownloadTorrent(url);
      this.sendMessage(targetPath, dir, name, -1, true);
    } finally {
      if (fd !== -1) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'close fd failed');
        }
      }
      try {
        body.close();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'close body failed');
      }
    }
  }

  public onFailure(url: string, dir: string | null, name: string): void {
    EhApplication.removeDownloadTorrent(url);
    this.sendMessage(url, dir, name, -1, true);
  }

  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }

  // -------------------------------------------------------------- 静态工具

  /**
   * 对应上游 `getNameFromUrl(url)`：取最后一个 `/` 之后的部分。
   * 没有 `/` 时 `lastIndexOf` 返回 -1，`substring(0)` = 整串（上游同款）。
   */
  public static getNameFromUrl(url: string): string {
    return url.substring(url.lastIndexOf('/') + 1);
  }

  /** 按 [offset, end) 切出独立分块 ArrayBuffer（避免 subarray.buffer 写出整包）。 */
  public static sliceChunk(bytes: ArrayBuffer, offset: number, end: number): ArrayBuffer {
    return bytes.slice(offset, end);
  }

  /** 对应上游 `sDCardPath`：公共"外部存储"根目录（鸿蒙侧取应用文件目录）。 */
  public static getSDCardPath(): string {
    const dir: string | null = AppConfig.getArchiverDir();
    return dir === null ? '' : dir;
  }

  private static readonly TORRENT_SUFFIX: string = '.torrent';
  // ".torrent" 的 UTF-8 字节长度固定为 8
  private static readonly MAX_TORRENT_BASENAME_UTF8_BYTES: number = 255 - 8;

  /**
   * 对应上游 `DownloadTorrentManager.createTorrentFileName(displayName, url)`：
   * 先去掉非法字符，再保证标题加 `.torrent` 不超过 255 UTF-8 字节（保持代理对完整）并 trim；
   * 清洗后为空时直接使用下载地址末段（该末段本身已带 `.torrent`，不再追加后缀）。
   */
  public static createTorrentFileName(displayName: string | null | undefined, url: string): string {
    const sanitized: string = YorozuyaFileUtils.sanitizeFilename(
      displayName !== null && displayName !== undefined ? displayName : ''
    );
    const base: string = DownloadTorrentManager.truncateUtf8ToMaxBytes(
      sanitized,
      DownloadTorrentManager.MAX_TORRENT_BASENAME_UTF8_BYTES
    ).trim();
    if (base.length === 0) {
      return DownloadTorrentManager.getNameFromUrl(url);
    }
    return base + DownloadTorrentManager.TORRENT_SUFFIX;
  }

  /**
   * 按 UTF-8 字节截断标题，并保持代理对完整，给 `.torrent` 留出后缀空间。
   */
  private static truncateUtf8ToMaxBytes(s: string | null | undefined, maxBytes: number): string {
    if (s === null || s === undefined || s.length === 0 || maxBytes <= 0) {
      return '';
    }
    let byteCount: number = 0;
    let cutCharEnd: number = 0;
    let i: number = 0;
    while (i < s.length) {
      const code: number = s.charCodeAt(i);
      let charUtf8Bytes: number = 3;
      let charWidth: number = 1;
      if (code <= 0x7F) {
        charUtf8Bytes = 1;
        charWidth = 1;
      } else if (code <= 0x7FF) {
        charUtf8Bytes = 2;
        charWidth = 1;
      } else if (code >= 0xD800 && code <= 0xDBFF) {
        charUtf8Bytes = 4;
        charWidth = 2;
        if (i + 1 >= s.length) {
          break;
        }
      } else {
        charUtf8Bytes = 3;
        charWidth = 1;
      }
      if (byteCount + charUtf8Bytes > maxBytes) {
        break;
      }
      byteCount += charUtf8Bytes;
      i += charWidth;
      cutCharEnd = i;
    }
    return cutCharEnd < s.length ? s.substring(0, cutCharEnd) : s;
  }
}

/**
 * okhttp `Callback` 实现（上游匿名 `object : Callback`）。
 * 放在文件作用域是因为 ArkTS 没有匿名类；成员与上游逐条对应。
 */
class TorrentCallback implements Callback {
  private readonly manager: DownloadTorrentManager;
  private readonly url: string;
  private readonly targetPath: string;
  private readonly dir: string | null;
  private readonly name: string;

  constructor(manager: DownloadTorrentManager, url: string, targetPath: string, dir: string | null,
    name: string) {
    this.manager = manager;
    this.url = url;
    this.targetPath = targetPath;
    this.dir = dir;
    this.name = name;
  }

  public onFailure(call: Call, e: Error): void {
    hilog.error(DOMAIN, TAG, 'torrent download failed: %{public}s', e.message);
    this.manager.onFailure(this.url, this.dir, this.name);
  }

  public onResponse(call: Call, response: Response): void {
    const code: number = response.code();
    if (code < 200 || code >= 300) {
      hilog.error(DOMAIN, TAG, 'torrent HTTP error: code=%{public}d url=%{public}s', code, this.url);
      response.close();
      this.manager.onFailure(this.url, this.dir, this.name);
      return;
    }
    const body: ResponseBody | null = response.body();
    if (body === null) {
      this.manager.onFailure(this.url, this.dir, this.name);
      return;
    }
    this.manager.onResponseBody(this.url, body, this.targetPath, this.dir, this.name);
  }
}

