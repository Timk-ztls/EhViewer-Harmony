/*
 * Copyright 2016 Hippo Seven
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

import { MediaType } from './MediaType';
import { decodeBytes } from './RequestBody';

/**
 * okhttp3.ResponseBody 等价层。
 *
 * 上游唯一用到的面就是 `response.body().string()`（EhEngine 里 60+ 处），
 * 加上 `response.body() == null` 判空。为保证 1:1，这里保留：
 *   contentType() / contentLength() / string() / bytes() / close()
 *
 * string() 的字符集解析与 OkHttp 一致：
 *   1. 取 Content-Type 的 charset 参数
 *   2. 没有则 UTF-8（OkHttp 在 Content-Type 缺 charset 时用 UTF-8 兜底）
 * 差异：OkHttp 是 BOM 检测 + Charset.forName；ArkTS 用 util.TextDecoder，
 * 遇到未知 charset 回退 utf-8（OkHttp 会抛 UnsupportedCharsetException）。
 */
export class ResponseBody {
  private readonly _contentType: MediaType | null;
  private readonly _buffer: ArrayBuffer;
  private _closed: boolean = false;

  constructor(contentType: MediaType | null, buffer: ArrayBuffer) {
    this._contentType = contentType;
    this._buffer = buffer;
  }

  /** 空 body（204/304 或 HEAD 响应）。 */
  static empty(): ResponseBody {
    return new ResponseBody(null, new ArrayBuffer(0));
  }

  contentType(): MediaType | null {
    return this._contentType;
  }

  contentLength(): number {
    return this._buffer.byteLength;
  }

  bytes(): ArrayBuffer {
    this.ensureOpen();
    return this._buffer;
  }

  /** 对齐 ResponseBody.string()。 */
  string(): string {
    this.ensureOpen();
    const charset: string = this._contentType === null
      ? 'utf-8'
      : this._contentType.charset('utf-8') as string;
    return decodeBytes(this._buffer, charset);
  }

  /**
   * 大响应路径（Lead 复核项）：对齐 OkHttp 的 byteStream()/source() 使用场景。
   * 语义：零拷贝返回底层 ArrayBuffer，调用方自己决定落盘或分片处理。
   * 大响应（> 8MB，如 Archiver 页、种子、图库归档）必须走本条而不是 string()：
   * string() 会额外做一次 charset 解码（UTF-16 副本 ≈ 2× 字节数）。
   * 传输层仍是整块返回（@ohos.net.http 的 result 一次性给出）；真正的大文件下载
   * 走 Range 分片（download-sync 侧），不经过 ResponseBody。
   */
  arrayBuffer(): ArrayBuffer {
    return this.bytes();
  }

  close(): void {
    this._closed = true;
  }

  isClosed(): boolean {
    return this._closed;
  }

  private ensureOpen(): void {
    if (this._closed) {
      throw new Error('closed');
    }
  }
}
