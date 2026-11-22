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

import util from '@ohos.util';
import fileIo from '@ohos.file.fs';
import { MediaType } from './MediaType';

/**
 * okhttp3.RequestBody 等价层。
 *
 * ArkTS 没有 InputStream/OutputStream，也没有 Object 基类的 writeTo(BufferedSink)。
 * 因此把 OkHttp 的「流式写」契约换成「一次性序列化为 ArrayBuffer」：
 *   contentLength(): number   —— 与 OkHttp 同名，返回序列化后字节数
 *   bytes(): ArrayBuffer      —— 对应 writeTo()，供传输层一次投递
 * 影响：请求体必须整体驻留内存。EhViewer 的请求体最大是 imageSearch 的图片
 * （用户选择的本地图片，MB 级），内存可接受；下载方向（响应体）才是大流量，
 * 那侧走 ResponseBody 的分块读取。
 *
 * 重载处理（ArkTS 不支持方法重载）：
 *   Java  RequestBody.create(MediaType, String)
 *   Java  RequestBody.create(MediaType, File)
 *   Java  RequestBody.create(MediaType, byte[])
 *   ArkTS RequestBody.create(mediaType, content: string)
 *         RequestBody.createFromFile(mediaType, path: string)
 *         RequestBody.createFromBytes(mediaType, content: ArrayBuffer)
 */
export abstract class RequestBody {

  /**
   * 从**当前文件指针**顺序读满 `size` 字节（F-3 修复点，`docs/f3-readsync-ruling.md`）。
   *
   * `@ohos.file.fs` 的 `ReadOptions.offset` 是「文件内起点 = filePointer + offset」，
   * **不是** Java `read(byte[] b, int off, int len)` 的「缓冲区下标」。把缓冲区进度写进
   * `offset` 的后果是「`off = 0` 时恰好对，`off > 0` 时读的是文件中间、且只读 `size - off` 字节」。
   *
   * 所以这里**不传 offset**，每次读进临时块再拷进目标缓冲。
   * 不复用 `beerbelly/Util.readFullyTo`：Util 反向 import 本文件（decodeBytes / utf8Encode），
   * 复用会形成循环依赖。
   */
  static readFullyFrom(fd: number, size: number): ArrayBuffer {
    const dst: ArrayBuffer = new ArrayBuffer(size);
    const dstView: Uint8Array = new Uint8Array(dst);
    let pos: number = 0;
    while (pos < size) {
      const want: number = Math.min(64 * 1024, size - pos);
      const chunk: ArrayBuffer = new ArrayBuffer(want);
      const n: number = fileIo.readSync(fd, chunk, { length: want });
      if (n <= 0) {
        break;
      }
      dstView.set(new Uint8Array(chunk, 0, n), pos);
      pos += n;
    }
    return dst.slice(0, pos);
  }

  /** 对齐 RequestBody.contentType()。 */
  abstract contentType(): MediaType | null;

  /** 序列化后字节数；-1 表示未知（传输层退化为 chunked）。 */
  abstract contentLength(): number;

  /** 序列化后的完整字节（代替 writeTo）。 */
  abstract bytes(): ArrayBuffer;

  /** 对齐 RequestBody.create(MediaType, String)。 */
  static create(mediaType: MediaType | null, content: string): RequestBody {
    return new StringRequestBody(mediaType, content);
  }

  /** 对齐 RequestBody.create(MediaType, File)：调用方负责保证 path 可读。 */
  static createFromFile(mediaType: MediaType | null, path: string): RequestBody {
    return new FileRequestBody(mediaType, path);
  }

  /** 对齐 RequestBody.create(MediaType, byte[])。 */
  static createFromBytes(mediaType: MediaType | null, content: ArrayBuffer): RequestBody {
    return new BytesRequestBody(mediaType, content);
  }
}

/** UTF-8 编码（对应 OkHttp 的 CharSet.UTF_8 默认编码）。 */
export function utf8Encode(s: string): ArrayBuffer {
  const enc: TextEncoderLike = new util.TextEncoder('utf-8') as TextEncoderLike;
  const u8: Uint8Array = enc.encodeInto(s);
  return u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength) as ArrayBuffer;
}

/** 按 charset 解码；未知 charset 回退 utf-8（与 OkHttp ResponseBody.string() 的兜底一致）。 */
export function decodeBytes(buf: ArrayBuffer, charset: string): string {
  let dec: TextDecoderLike;
  try {
    dec = util.TextDecoder.create(charset.toLowerCase(), { fatal: false, ignoreBOM: false }) as TextDecoderLike;
  } catch (e) {
    dec = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: false }) as TextDecoderLike;
  }
  return dec.decodeToString(new Uint8Array(buf));
}

/** String 请求体。 */
export class StringRequestBody extends RequestBody {
  private readonly _mediaType: MediaType | null;
  private readonly _content: ArrayBuffer;

  constructor(mediaType: MediaType | null, content: string) {
    super();
    this._mediaType = mediaType;
    this._content = utf8Encode(content);
  }

  contentType(): MediaType | null {
    return this._mediaType;
  }

  contentLength(): number {
    return this._content.byteLength;
  }

  bytes(): ArrayBuffer {
    return this._content;
  }
}

/** byte[] 请求体。 */
export class BytesRequestBody extends RequestBody {
  private readonly _mediaType: MediaType | null;
  private readonly _content: ArrayBuffer;

  constructor(mediaType: MediaType | null, content: ArrayBuffer) {
    super();
    this._mediaType = mediaType;
    this._content = content;
  }

  contentType(): MediaType | null {
    return this._mediaType;
  }

  contentLength(): number {
    return this._content.byteLength;
  }

  bytes(): ArrayBuffer {
    return this._content;
  }
}

/**
 * File 请求体（对齐 OkHttp FileBody：写时读盘）。
 * ArkTS 侧第一次 bytes() 时才读文件，读后缓存，语义与 OkHttp「每次 writeTo 重读」不同：
 * 上游只在 imageSearch 用一次，且写完立即删除临时文件，缓存不影响行为。
 */
export class FileRequestBody extends RequestBody {
  private readonly _mediaType: MediaType | null;
  private readonly _path: string;
  private _cached: ArrayBuffer | null = null;

  constructor(mediaType: MediaType | null, path: string) {
    super();
    this._mediaType = mediaType;
    this._path = path;
  }

  contentType(): MediaType | null {
    return this._mediaType;
  }

  contentLength(): number {
    return this.bytes().byteLength;
  }


  bytes(): ArrayBuffer {
    if (this._cached !== null) {
      return this._cached;
    }
    const size: number = fileIo.statSync(this._path).size;
    // 不写显式类型注解：让 TS 推断为 fileIo.File（ArkTS 真实类型），
    // 测试脚手架下 @ohos.file.fs 是 any 桩也能编译（显式注解会把命名空间类型带进来）
    const file = fileIo.openSync(this._path, fileIo.OpenMode.READ_ONLY);
    let buf: ArrayBuffer;
    try {
      // F-3：ReadOptions.offset 是「文件内起点（filePointer + offset）」，不是缓冲区下标。
      // 这里要的是「从头读满整个文件」，不传 offset，让 filePointer 顺序前进。
      buf = RequestBody.readFullyFrom(file.fd, size);
    } finally {
      fileIo.closeSync(file);
    }
    this._cached = buf;
    return buf;
  }
}

/**
 * 平台类型的最小结构（解耦 @ohos.util / @ohos.file.fs 的命名空间类型）。
 * 原因：纯逻辑单测要在 node 下用 tsc 编译，@ohos.* 只有类型桩，
 * 而 util.TextEncoder 这类「命名空间里的类型」无法被 default import 带进来。
 * 用窄接口替换后 ArkTS 编译不变（结构一致），测试脚手架也能编译。
 */
interface TextEncoderLike {
  encodeInto(s: string): Uint8Array;
}

interface TextDecoderLike {
  decodeToString(u8: Uint8Array): string;
}

interface FileHandleLike {
  fd: number;
  path: string;
}
