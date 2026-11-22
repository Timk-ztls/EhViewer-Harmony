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

import { ByteSink } from '../streampipe/OutputStreamPipe';

/**
 * 分片写盘 + 下载结果值对象（**不依赖 okhttp 栈**，便于纯逻辑单测）。
 *
 * 为什么单独成文件：`PageImageDownloaderImpl` 依赖 `OkHttpClient`，会把整条 HTTP 栈
 * （传输层 / DNS / 缓存）拉进编译图；而「分片写」和「结果字段语义」是可以脱离网络测的，
 * 所以拆到本文件，让测试只编译这一层。
 */

/** 默认分片大小（64 KB）。 */
export const DEFAULT_CHUNK_SIZE: number = 64 * 1024;

/**
 * 把 `all` 按 `chunkSize` 分片写进 `sink`，返回实际写入的字节数。
 *
 * 两条硬要求：
 *   1. **每片都是独立副本**（`slice` 拷贝）—— sink 侧可能异步消费，
 *      共享同一块底层内存会让它看到后续写入改过的数据
 *   2. **不 close sink** —— close 的时机由调用方决定（失败路径也要 close，但语义不同）
 */
export function writeInChunks(all: ArrayBuffer, sink: ByteSink, chunkSize: number = DEFAULT_CHUNK_SIZE): number {
  const total: number = all.byteLength;
  let pos: number = 0;
  while (pos < total) {
    const n: number = Math.min(chunkSize, total - pos);
    sink.write(all.slice(pos, pos + n));
    pos += n;
  }
  return total;
}

/** 下载结果（`PageImageDownloader` 的富返回值）。 */
export class DownloadResult {
  /** 是否成功（2xx 且全部写进 sink）。 */
  readonly ok: boolean;
  /** HTTP 状态码；**连接未建立为 -1**（借此区分「509 配额超限」与「连不上」）。 */
  readonly status: number;
  /** 实际写入字节数。 */
  readonly received: number;
  /** 失败原因；成功为空串（不是 null）。 */
  readonly error: string;
  /**
   * 是否**疑似被劫持**（C-18）。
   *
   * 上游判定在 `SpiderQueen.java:1427-1433`：`!targetImageUrl.equals(responseUrl)`。
   * 本层在 `PageImageDownloaderImpl` 内部就能算出来，**不需要 storage-db 参与**，
   * 所以直接放在结果里，避免下一批各自加一个字段。
   */
  readonly hijacked: boolean;

  constructor(ok: boolean, status: number, received: number, error: string,
    hijacked: boolean = false) {
    this.ok = ok;
    this.status = status;
    this.received = received;
    this.error = error;
    this.hijacked = hijacked;
  }
}
