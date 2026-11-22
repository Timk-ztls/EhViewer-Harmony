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

import { MediaType, MediaTypes } from './MediaType';
import { RequestBody, utf8Encode } from './RequestBody';
import { Headers } from './Headers';

/**
 * okhttp3.MultipartBody 等价（multipart/form-data）。
 *
 * 上游唯一使用点：EhEngine.imageSearch 的以图搜图。
 *   MultipartBody.Builder b = new MultipartBody.Builder();
 *   b.setType(MultipartBody.FORM);
 *   b.addPart(Headers.of("Content-Disposition", "form-data; name=\"sfile\"; filename=\"x.jpg\"; size=\"40\""),
 *             RequestBody.create(MediaType.parse("file"), imageFile));
 *   ...
 * 注意 OkHttp 的 addPart(Headers, RequestBody) 是「按给定的头原样写出」，
 * 不会因为 body.contentType() 非空就补 Content-Type；而 addFormDataPart(name, value)
 * 会补。这里逐字节对齐：addPart 不补头，addFormDataPart 才补。
 *
 * 序列化（RFC 7578）：
 *   --{boundary}\r\n
 *   {headers}\r\n
 *   \r\n
 *   {content}\r\n
 *   ...
 *   --{boundary}--\r\n
 */
export class MultipartBody extends RequestBody {
  /** 对齐 MultipartBody.FORM。 */
  static readonly FORM: MediaType = MediaTypes.MULTIPART_FORM;

  private readonly _type: MediaType;
  private readonly _boundary: string;
  private readonly _parts: Part[];
  private _cachedBytes: ArrayBuffer | null = null;

  constructor(type: MediaType, boundary: string, parts: Part[]) {
    super();
    this._type = type;
    this._boundary = boundary;
    this._parts = parts;
  }

  type(): MediaType {
    return this._type;
  }

  boundary(): string {
    return this._boundary;
  }

  parts(): Part[] {
    return this._parts;
  }

  size(): number {
    return this._parts.length;
  }

  part(index: number): Part {
    return this._parts[index];
  }

  /**
   * OkHttp 的 MultipartBody.contentType() 返回带 boundary 参数的 MediaType。
   * 本层 MediaType 不承载任意参数，故 contentType() 只返回基础类型，
   * 需要 boundary 时用 contentTypeHeader()（传输层对 MultipartBody 走这个分支）。
   */
  contentType(): MediaType | null {
    return new MediaType(this._type.type(), this._type.subtype(), null);
  }

  /** 实际写出的 Content-Type 头：type + `; boundary=...`。 */
  contentTypeHeader(): string {
    return `${this._type.toString()}; boundary=${this._boundary}`;
  }

  contentLength(): number {
    return this.bytes().byteLength;
  }

  bytes(): ArrayBuffer {
    if (this._cachedBytes !== null) {
      return this._cachedBytes;
    }
    const chunks: Uint8Array[] = [];
    const boundaryBytes: ArrayBuffer = utf8Encode('--' + this._boundary + '\r\n');

    for (let i = 0; i < this._parts.length; i++) {
      const part: Part = this._parts[i];
      chunks.push(new Uint8Array(boundaryBytes));

      // 头部块：按 part.headers 的顺序原样写出
      const h: Headers = part.headers;
      for (let k = 0; k < h.size(); k++) {
        chunks.push(new Uint8Array(utf8Encode(`${h.name(k)}: ${h.value(k)}\r\n`)));
      }
      // OkHttp 在 addFormDataPart 里才会写 Content-Type；addPart 保持原样
      if (part.writeContentType) {
        const ct: MediaType | null = part.body.contentType();
        if (ct !== null) {
          chunks.push(new Uint8Array(utf8Encode(`Content-Type: ${ct.toString()}\r\n`)));
        }
      }
      chunks.push(new Uint8Array(utf8Encode('\r\n')));
      chunks.push(new Uint8Array(part.body.bytes()));
      chunks.push(new Uint8Array(utf8Encode('\r\n')));
    }
    chunks.push(new Uint8Array(utf8Encode('--' + this._boundary + '--\r\n')));

    let total: number = 0;
    for (let i = 0; i < chunks.length; i++) {
      total += chunks[i].byteLength;
    }
    const out: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (let i = 0; i < chunks.length; i++) {
      out.set(chunks[i], offset);
      offset += chunks[i].byteLength;
    }
    const buf: ArrayBuffer = out.buffer as ArrayBuffer;
    this._cachedBytes = buf;
    return buf;
  }
}

/** multipart 的单个分片。 */
export class Part {
  readonly headers: Headers;
  readonly body: RequestBody;
  /** true 表示该分片的 Content-Type 由 addFormDataPart 自动补写。 */
  readonly writeContentType: boolean;

  constructor(headers: Headers, body: RequestBody, writeContentType: boolean) {
    this.headers = headers;
    this.body = body;
    this.writeContentType = writeContentType;
  }
}

/** okhttp3.MultipartBody.Builder 等价。 */
export class MultipartBodyBuilder {
  private _type: MediaType = MultipartBody.FORM;
  private _boundary: string | null = null;
  private _parts: Part[] = [];

  /** 对齐 setType(MediaType)。 */
  setType(type: MediaType): MultipartBodyBuilder {
    if (type === null) {
      throw new Error('type == null');
    }
    this._type = type;
    return this;
  }

  /** 对齐 setBoundary(String)：固定 boundary，便于金样本逐字节比对。 */
  setBoundary(boundary: string): MultipartBodyBuilder {
    this._boundary = boundary;
    return this;
  }

  /** 对齐 addPart(Headers, RequestBody)：不补 Content-Type。 */
  addPart(headers: Headers, body: RequestBody): MultipartBodyBuilder {
    this._parts.push(new Part(headers, body, false));
    return this;
  }

  /** 对齐 addFormDataPart(String, String)。 */
  addFormDataPart(name: string, value: string): MultipartBodyBuilder {
    return this.addFormDataPartWithFilename(name, null, RequestBody.create(null, value));
  }

  /** 对齐 addFormDataPart(String, String, RequestBody)。 */
  addFormDataPartWithFilename(name: string, filename: string | null, body: RequestBody): MultipartBodyBuilder {
    let disposition: string = `form-data; name="${MultipartBodyBuilder.escape(name)}"`;
    if (filename !== null) {
      disposition += `; filename="${MultipartBodyBuilder.escape(filename)}"`;
    }
    const headers: Headers = Headers.of('Content-Disposition', disposition);
    this._parts.push(new Part(headers, body, true));
    return this;
  }

  build(): MultipartBody {
    if (this._parts.length === 0) {
      throw new Error('Multipart body must have at least one part.');
    }
    const boundary: string = this._boundary !== null ? this._boundary : MultipartBodyBuilder.generateBoundary();
    return new MultipartBody(this._type, boundary, this._parts);
  }

  /** OkHttp 用 UUID 去横线（32 位十六进制）作 boundary。 */
  static generateBoundary(): string {
    let s: string = '';
    for (let i = 0; i < 32; i++) {
      s += '0123456789abcdef'.charAt(Math.floor(Math.random() * 16));
    }
    return s;
  }

  private static escape(s: string): string {
    return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }
}
