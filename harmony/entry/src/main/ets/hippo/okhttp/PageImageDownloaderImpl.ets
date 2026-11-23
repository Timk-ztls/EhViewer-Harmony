/*
 * Copyright 2014 Hippo Seven
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

import { Call } from './Call';
import { HttpUrl } from './HttpUrl';
import { OkHttpClient, OkHttpClientBuilder, TimeUnit } from './OkHttpClient';
import { Request } from './Request';
import { Response } from './Response';
import { ResponseBody } from './ResponseBody';
import { ByteSink } from '../streampipe/OutputStreamPipe';
import { DEFAULT_CHUNK_SIZE, DownloadResult, writeInChunks } from './ChunkedSinkWriter';
import { PageDownloadProgressCallback, PageImageDownloader } from '../streampipe/PageImageDownloader';
import { EhRequestBuilder } from '../ehviewer/client/EhRequestBuilder';

/**
 * 阅读页图片字节下载器（`PageImageDownloader` 的 net-parse 侧实现）。
 *
 * ## 为什么要有这一层
 * 上游 `SpiderQueen` 拉图片字节用的是 `EhApplication.getImageOkHttpClient()` +
 * `UniFile.openOutputStream()`；ArkTS 侧两者分属不同模块（HTTP 在 net-parse、
 * 文件在 storage-db），所以抽成契约 `PageImageDownloader`（声明在 `spider/SpiderQueen.ets`），
 * 由本层实现、由 storage-db 注入。
 *
 * ## 三个设计约束（Lead 裁决）
 *   1. **不 import UniFile** —— 写端只有 `ByteSink`（`write(ArrayBuffer)` / `close()`），
 *      跨模块边界只过字节，不过文件类型
 *   2. **流式写** —— 不能把整张图读进内存再落盘；按 `CHUNK_SIZE` 分片 `write()`
 *   3. **必须暴露 HTTP 状态码** —— storage-db 侧要做 509 检测（配额超限），
 *      只看 `boolean` 分不清「509」和「网络失败」
 *
 * ## 用的哪个客户端（**普通客户端，不是 image 客户端**）
 * 上游 `getImageOkHttpClient()` **不跟随重定向 + 四路超时 20s**；而图片走的是
 * `getOkHttpClient()`（**跟随重定向 + 10s**）。core-runtime 核实过：慢图在 image 客户端上
 * 经常失败。所以这里用普通客户端配置：`followRedirects(true)` + 10s 超时。
 */
export class PageImageDownloaderImpl implements PageImageDownloader {
  /** 分片大小（64 KB）：够大不至于 syscall 过多，够小不至于一张图占满内存。 */
  static readonly CHUNK_SIZE: number = DEFAULT_CHUNK_SIZE;

  /** 普通客户端超时（上游 `getOkHttpClient()` = 10s）。 */
  static readonly TIMEOUT_SECONDS: number = 10;

  private readonly _client: OkHttpClient;

  constructor(client?: OkHttpClient) {
    this._client = client === undefined || client === null ? PageImageDownloaderImpl.createClient() : client;
  }

  /** 普通客户端配置：跟随重定向 + 10s 三路超时。 */
  static createClient(): OkHttpClient {
    return new OkHttpClientBuilder()
      .followRedirects(true)
      .connectTimeout(PageImageDownloaderImpl.TIMEOUT_SECONDS, TimeUnit.SECONDS)
      .readTimeout(PageImageDownloaderImpl.TIMEOUT_SECONDS, TimeUnit.SECONDS)
      .writeTimeout(PageImageDownloaderImpl.TIMEOUT_SECONDS, TimeUnit.SECONDS)
      .build();
  }

  /**
   * 对齐 `PageImageDownloader.download(url, sink)`。
   *
   * 返回 `true` 仅当 **HTTP 2xx 且全部字节写完**；其余一律 `false`（不抛异常给调用方，
   * 由 `lastStatus` / `lastError` 给出原因 —— 上游 SpiderQueen 的失败是要「记错误并继续泵」的）。
   */
  async download(url: string, sink: ByteSink, referer?: string): Promise<boolean> {
    const result: DownloadResult = await this.downloadWithStatus(url, sink, referer);
    return result.ok;
  }

  /**
   * 带状态码的下载（storage-db 的 509 检测用它）。
   *
   * 语义与 `download()` 相同，只是把「为什么失败」也交出去：
   *   - `status`：HTTP 状态码；**连接都没建立时为 -1**（区分「509」与「连不上」）
   *   - `error`：失败原因（成功时为空串）
   *   - `received`：实际写进 sink 的字节数
   */
  async downloadWithStatus(url: string, sink: ByteSink, referer?: string,
    onProgress?: PageDownloadProgressCallback): Promise<DownloadResult> {
    let response: Response;
    let parsed: HttpUrl | null = null;
    let targetUrl: string = url;
    try {
      parsed = HttpUrl.parse(url);
      if (parsed === null) {
        return new DownloadResult(false, -1, 0, 'invalid url: ' + url);
      }
      targetUrl = parsed.toString();
      // C-18：空串/undefined/null 均不设 Referer；使用 EhRequestBuilder 保留 Chrome UA/Accept/Host 头
      const refArg: string | null = (referer !== undefined && referer !== null && referer.length > 0)
        ? referer : null;
      const request: Request = EhRequestBuilder.ofReferer(targetUrl, refArg).build();
      // 禁用 @ohos.net.http 的隐式自动重定向，确保 30x 能暴露给反劫持校验
      const execClient: OkHttpClient = (this._client instanceof OkHttpClient && this._client.followRedirects())
        ? this._client.newBuilder().followRedirects(false).build()
        : this._client;
      const call: Call = execClient.newCall(request, onProgress);
      response = await call.execute();
    } catch (e) {
      return new DownloadResult(false, -1, 0, (e as Error).message);
    }

    // 反劫持校验（上游 SpiderQueen.java:1427-1433）：最终 URL 必须与目标一致。
    // 1) 若拦截器链已跟随重定向，则 response.request().url() 不同于 targetUrl；
    // 2) 若因 followRedirects=false 直接收到带 Location 的 30x 响应，同样视为被重定向劫持。
    const responseUrl: string = response.request().url().toString();
    const redirectLocation: string | null = response.isRedirect() ? response.headers().get('Location') : null;
    const redirectedTarget: HttpUrl | null = (redirectLocation !== null && parsed !== null)
      ? parsed.resolve(redirectLocation) : null;
    const wasRedirected: boolean = responseUrl !== targetUrl ||
      (redirectedTarget !== null && redirectedTarget.toString() !== targetUrl);
    if (wasRedirected) {
      const hijacked: ResponseBody | null = response.body();
      if (hijacked !== null) {
        hijacked.close();
      }
      return new DownloadResult(false, -1, 0,
        '链接疑似被劫持\nThe link is suspected to be hijacked', true);
    }

    const code: number = response.code();
    if (code < 200 || code >= 300) {
      // 509 = 配额超限，调用方要能识别；这里原样把状态码交出去
      const empty: ResponseBody | null = response.body();
      if (empty !== null) {
        empty.close();
      }
      return new DownloadResult(false, code, 0, 'HTTP ' + code);
    }

    const body: ResponseBody | null = response.body();
    if (body === null) {
      return new DownloadResult(false, code, 0, 'empty body');
    }
    let received: number = 0;
    try {
      const all: ArrayBuffer = body.bytes();
      received = writeInChunks(all, sink, PageImageDownloaderImpl.CHUNK_SIZE);
      sink.close();
      if (onProgress !== undefined && received > 0) {
        const clRaw: string | null = response.headers().get('Content-Length');
        const cl: number = (clRaw !== null && /^\d+$/.test(clRaw.trim()))
          ? Number.parseInt(clRaw.trim(), 10)
          : -1;
        if (cl > 0) {
          onProgress(cl, Math.max(received, cl), 0);
        }
      }
      return new DownloadResult(true, code, received, '');
    } catch (e) {
      try {
        sink.close();
      } catch (ignored) {
        // close 失败不覆盖原始错误
      }
      return new DownloadResult(false, code, received, (e as Error).message);
    } finally {
      body.close();
    }
  }
}
