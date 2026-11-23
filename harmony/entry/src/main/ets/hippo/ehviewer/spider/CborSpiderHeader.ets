/*
 * Copyright 2026 BrokenDog
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

import { InputStream } from '../../unifile/Contracts';

/**
 * 已读到的 gid 与 token。gid 小于 0 或 token 为空时不会构造。
 */
export class CborSpiderHeaderFields {
  readonly gid: number;
  readonly token: string;

  constructor(gid: number, token: string) {
    this.gid = gid;
    this.token = token;
  }
}

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/spider/CborSpiderHeader.kt
 *
 * 从 CBOR map 形式的 `.ehviewer` 中只取出 gid 和 token。
 * `pTokenMap` 等嵌套内容只跳过，不放进内存。
 */
export class CborSpiderHeader {
  private static readonly MAX_TOKEN_CHARS: number = 128;
  private static readonly MAX_KEY_CHARS: number = 64;
  static readonly MAX_DEPTH: number = 16;
  static readonly MAX_BYTES: number = 32 * 1024 * 1024;
  static readonly BREAK: number = 0xFF;

  private constructor() {
  }

  /**
   * 解析顶层定长或不定长 map。gid 小于 0、token 为空，或开头不是 map 时返回 null。
   * gid 和 token 若已读到，后面的字段跳过失败仍返回这两个值。
   */
  static read(input: InputStream | null): CborSpiderHeaderFields | null {
    if (input === null) {
      return null;
    }
    const cursor: CborCursor = new CborCursor(input);
    let gid: number = -1;
    let token: string | null = null;
    try {
      const head: number = cursor.readByte();
      const major: number = head >>> 5;
      const info: number = head & 0x1F;
      if (major !== 5) {
        return null;
      }
      const indefinite: boolean = info === 31;
      const count: number = indefinite ? -1 : cursor.readArgument(info);
      let index: number = 0;
      while (indefinite || index < count) {
        if (indefinite && cursor.peekBreak()) {
          cursor.consumeBreak();
          break;
        }
        const key: string | null = cursor.readTextOrSkip(CborSpiderHeader.MAX_KEY_CHARS);
        if (key === 'gid') {
          const value: number | null = cursor.readIntegerOrSkip();
          if (value !== null) {
            gid = value;
          }
        } else if (key === 'token') {
          const value: string | null = cursor.readTextOrSkip(CborSpiderHeader.MAX_TOKEN_CHARS);
          if (value !== null && value.length > 0) {
            token = value;
          }
        } else {
          cursor.skipValue(0);
        }
        index++;
      }
    } catch (_e) {
      // gid、token 写在 pTokenMap 之前。后面的字段跳过失败时，仍保留已读到的两个值。
    }
    if (gid < 0 || token === null || token.length === 0) {
      return null;
    }
    return new CborSpiderHeaderFields(gid, token);
  }
}

/**
 * 带字节上限与单字节回退槽的 CBOR 读取游标。
 * `peekBreak()` 不计入已读字节，避免回退破坏上限判断。
 */
class CborCursor {
  private readonly inputStream: InputStream;
  private readonly skipBuffer: ArrayBuffer = new ArrayBuffer(4096);
  private pushedByte: number = -1;
  private bytesRead: number = 0;
  private lastArgWasLongMax: boolean = false;

  constructor(input: InputStream) {
    this.inputStream = input;
  }

  private readRawByte(): number {
    if (this.pushedByte >= 0) {
      const b: number = this.pushedByte;
      this.pushedByte = -1;
      return b;
    }
    return this.inputStream.read();
  }

  /**
   * 读取一个字节并计入总字节数。流结束或超过 MAX_BYTES 时中止，避免损坏文件拖垮解析。
   */
  readByte(): number {
    const value: number = this.readRawByte();
    if (value < 0) {
      throw new Error('EOF');
    }
    this.bytesRead++;
    if (this.bytesRead > CborSpiderHeader.MAX_BYTES) {
      throw new Error('cbor too large');
    }
    return value & 0xFF;
  }

  /**
   * 查看下一字节是不是 break，并保留在单字节回退槽中。不增加已读计数。
   */
  peekBreak(): boolean {
    if (this.pushedByte < 0) {
      const value: number = this.inputStream.read();
      if (value < 0) {
        throw new Error('EOF');
      }
      this.pushedByte = value & 0xFF;
    }
    return this.pushedByte === CborSpiderHeader.BREAK;
  }

  /**
   * 消费一个 break。当前位置不是 break 时说明不定长结构已经损坏。
   */
  consumeBreak(): void {
    if (this.readByte() !== CborSpiderHeader.BREAK) {
      throw new Error('expected cbor break');
    }
  }

  /**
   * 按附加信息读取无符号参数。
   * 使用乘法累加代替 32 位位运算，避免大于 2^31 的 gid 被截断。
   * 8 字节且最高位为 1（超出有符号 64-bit long）时，读完剩余字节后失败。
   */
  readArgument(info: number): number {
    this.lastArgWasLongMax = false;
    if (info < 24) {
      return info;
    }
    let width: number = 0;
    if (info === 24) {
      width = 1;
    } else if (info === 25) {
      width = 2;
    } else if (info === 26) {
      width = 4;
    } else if (info === 27) {
      width = 8;
    } else {
      throw new Error('bad cbor argument');
    }
    let value: number = 0;
    let isLongMax: boolean = width === 8;
    for (let i = 0; i < width; i++) {
      const b: number = this.readByte();
      if (i === 0 && width === 8 && (b & 0x80) !== 0) {
        for (let k = i + 1; k < width; k++) {
          this.readByte();
        }
        throw new Error('cbor integer overflow');
      }
      if (width === 8) {
        const expected: number = i === 0 ? 0x7F : 0xFF;
        if (b !== expected) {
          isLongMax = false;
        }
      }
      const next: number = value * 256 + b;
      if (next > Number.MAX_SAFE_INTEGER) {
        if (!isLongMax) {
          for (let k = i + 1; k < width; k++) {
            this.readByte();
          }
          throw new Error('cbor integer overflow');
        }
      }
      value = next;
    }
    this.lastArgWasLongMax = isLongMax;
    return value;
  }

  /**
   * 当前位置应是文本时读出内容。类型不对则整值跳过并返回 null，避免后续字段错位。
   * 超过 maxChars 字节的文本同样丢弃，防止超长 key 或 token 进内存。
   */
  readTextOrSkip(maxChars: number): string | null {
    const head: number = this.readByte();
    if ((head >>> 5) !== 3) {
      this.skipWithHead(head, 0);
      return null;
    }
    return this.readTextBody(head & 0x1F, maxChars);
  }

  /**
   * 读 CBOR 无符号或负数整数。不是整数时跳过该值并返回 null；
   * 负数编码值为 Long.MAX_VALUE 时返回 null。
   */
  readIntegerOrSkip(): number | null {
    const head: number = this.readByte();
    const major: number = head >>> 5;
    const info: number = head & 0x1F;
    if (major !== 0 && major !== 1) {
      this.skipWithHead(head, 0);
      return null;
    }
    if (info === 31) {
      throw new Error('bad cbor integer');
    }
    const unsigned: number = this.readArgument(info);
    if (major === 0) {
      return unsigned;
    }
    if (this.lastArgWasLongMax || unsigned >= Number.MAX_SAFE_INTEGER) {
      return null;
    }
    return -1 - unsigned;
  }

  /**
   * 跳过一个完整值。深度从当前层继续累加，超过 MAX_DEPTH 时中止。
   */
  skipValue(depth: number): void {
    this.skipWithHead(this.readByte(), depth);
  }

  private skipWithHead(head: number, depth: number): void {
    if (depth > CborSpiderHeader.MAX_DEPTH) {
      throw new Error('cbor too deep');
    }
    const major: number = head >>> 5;
    const info: number = head & 0x1F;
    if (major === 0 || major === 1) {
      if (info === 31) {
        throw new Error('bad cbor integer');
      }
      this.readArgument(info);
    } else if (major === 2 || major === 3) {
      this.skipString(major, info);
    } else if (major === 4) {
      this.skipContainer(info, depth, false);
    } else if (major === 5) {
      this.skipContainer(info, depth, true);
    } else if (major === 6) {
      if (info === 31) {
        throw new Error('bad cbor tag');
      }
      this.readArgument(info);
      this.skipValue(depth);
    } else if (major === 7) {
      this.skipSimple(info);
    } else {
      throw new Error('bad cbor major');
    }
  }

  private skipSimple(info: number): void {
    if (info < 24) {
      return;
    }
    if (info === 24) {
      this.readByte();
    } else if (info === 25) {
      this.skipBytes(2);
    } else if (info === 26) {
      this.skipBytes(4);
    } else if (info === 27) {
      this.skipBytes(8);
    } else {
      throw new Error('bad cbor simple');
    }
  }

  private skipString(major: number, info: number): void {
    if (info !== 31) {
      this.skipBytes(this.readArgument(info));
      return;
    }
    while (!this.peekBreak()) {
      const chunk: number = this.readByte();
      if ((chunk >>> 5) !== major || (chunk & 0x1F) === 31) {
        throw new Error('bad indefinite string');
      }
      this.skipBytes(this.readArgument(chunk & 0x1F));
    }
    this.consumeBreak();
  }

  private skipContainer(info: number, depth: number, map: boolean): void {
    const items: number = map ? 2 : 1;
    if (info === 31) {
      while (!this.peekBreak()) {
        for (let k = 0; k < items; k++) {
          this.skipValue(depth + 1);
        }
      }
      this.consumeBreak();
      return;
    }
    const count: number = this.readArgument(info);
    for (let index = 0; index < count; index++) {
      for (let k = 0; k < items; k++) {
        this.skipValue(depth + 1);
      }
    }
  }

  private readTextBody(info: number, maxChars: number): string | null {
    if (info === 31) {
      const parts: string[] = [];
      let totalLen: number = 0;
      let tooLong: boolean = false;
      while (!this.peekBreak()) {
        const chunk: number = this.readByte();
        if ((chunk >>> 5) !== 3 || (chunk & 0x1F) === 31) {
          throw new Error('bad indefinite text');
        }
        const length: number = this.readArgument(chunk & 0x1F);
        if (tooLong || totalLen + length > maxChars) {
          tooLong = true;
          this.skipBytes(length);
        } else {
          const piece: string = this.readUtf8(length);
          parts.push(piece);
          totalLen += piece.length;
        }
      }
      this.consumeBreak();
      return tooLong ? null : parts.join('');
    }
    const length: number = this.readArgument(info);
    if (length > maxChars) {
      this.skipBytes(length);
      return null;
    }
    return this.readUtf8(length);
  }

  private readUtf8(length: number): string {
    if (length < 0 || length > CborSpiderHeader.MAX_BYTES) {
      throw new Error('cbor text too large');
    }
    if (length === 0) {
      return '';
    }
    const raw: ArrayBuffer = new ArrayBuffer(length);
    const data: Uint8Array = new Uint8Array(raw);
    let offset: number = 0;
    if (this.pushedByte >= 0) {
      data[0] = this.pushedByte;
      this.pushedByte = -1;
      offset = 1;
      this.bytesRead++;
      if (this.bytesRead > CborSpiderHeader.MAX_BYTES) {
        throw new Error('cbor too large');
      }
    }
    while (offset < length) {
      const read: number = this.inputStream.readBytes(raw, offset, length - offset);
      if (read <= 0) {
        throw new Error('EOF');
      }
      offset += read;
      this.bytesRead += read;
      if (this.bytesRead > CborSpiderHeader.MAX_BYTES) {
        throw new Error('cbor too large');
      }
    }
    return decodeCborUtf8(data);
  }

  private skipBytes(length: number): void {
    if (length < 0) {
      throw new Error('negative cbor length');
    }
    let left: number = length;
    if (left > 0 && this.pushedByte >= 0) {
      this.pushedByte = -1;
      left -= 1;
      this.bytesRead++;
      if (this.bytesRead > CborSpiderHeader.MAX_BYTES) {
        throw new Error('cbor too large');
      }
    }
    while (left > 0) {
      const want: number = left < this.skipBuffer.byteLength ? left : this.skipBuffer.byteLength;
      const read: number = this.inputStream.readBytes(this.skipBuffer, 0, want);
      if (read <= 0) {
        throw new Error('EOF');
      }
      left -= read;
      this.bytesRead += read;
      if (this.bytesRead > CborSpiderHeader.MAX_BYTES) {
        throw new Error('cbor too large');
      }
    }
  }
}

function decodeCborUtf8(bytes: Uint8Array): string {
  const parts: string[] = [];
  const len: number = bytes.length;
  let i: number = 0;
  while (i < len) {
    const b0: number = bytes[i];
    if (b0 < 0x80) {
      parts.push(String.fromCharCode(b0));
      i += 1;
    } else if ((b0 & 0xE0) === 0xC0) {
      if (i + 1 >= len) {
        parts.push('\uFFFD');
        break;
      }
      const b1: number = bytes[i + 1];
      if ((b1 & 0xC0) !== 0x80) {
        parts.push('\uFFFD');
        i += 1;
        continue;
      }
      const cp: number = ((b0 & 0x1F) << 6) | (b1 & 0x3F);
      parts.push(cp < 0x80 ? '\uFFFD' : String.fromCharCode(cp));
      i += 2;
    } else if ((b0 & 0xF0) === 0xE0) {
      if (i + 2 >= len) {
        parts.push('\uFFFD');
        break;
      }
      const b1: number = bytes[i + 1];
      const b2: number = bytes[i + 2];
      if ((b1 & 0xC0) !== 0x80 || (b2 & 0xC0) !== 0x80) {
        parts.push('\uFFFD');
        i += 1;
        continue;
      }
      const cp: number = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
      if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) {
        parts.push('\uFFFD');
      } else {
        parts.push(String.fromCharCode(cp));
      }
      i += 3;
    } else if ((b0 & 0xF8) === 0xF0) {
      if (i + 3 >= len) {
        parts.push('\uFFFD');
        break;
      }
      const b1: number = bytes[i + 1];
      const b2: number = bytes[i + 2];
      const b3: number = bytes[i + 3];
      if ((b1 & 0xC0) !== 0x80 || (b2 & 0xC0) !== 0x80 || (b3 & 0xC0) !== 0x80) {
        parts.push('\uFFFD');
        i += 1;
        continue;
      }
      const cp: number = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
      if (cp < 0x10000 || cp > 0x10FFFF) {
        parts.push('\uFFFD');
      } else {
        const adj: number = cp - 0x10000;
        parts.push(String.fromCharCode(0xD800 + (adj >> 10), 0xDC00 + (adj & 0x3FF)));
      }
      i += 4;
    } else {
      parts.push('\uFFFD');
      i += 1;
    }
  }
  return parts.join('');
}
