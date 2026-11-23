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

import { InputStream } from '../../../unifile/Contracts';
import { ExceptionUtils } from '../../../util/ExceptionUtils';
import { DetailUrlResult, GalleryDetailUrlParser } from './GalleryDetailUrlParser';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/ComicInfoParser.java
 *
 * 从 ComicInfo.xml 的 `<Web>` 地址解析画廊 gid 和 token。
 */
export class ComicInfoParser {
  static readonly FILENAME: string = 'ComicInfo.xml';

  private static readonly MAX_BYTES: number = 256 * 1024;
  private static readonly BUFFER_SIZE: number = 4096;

  private static readonly WEB: RegExp = /<Web>\s*([^<]+?)\s*<\/Web>/i;

  private constructor() {
  }

  /**
   * 取出第一个 Web 标签中的画廊地址。没有该标签或地址不符合画廊详情格式时返回 null。
   */
  static parse(xml: string | null): DetailUrlResult | null {
    if (xml === null || xml.length === 0) {
      return null;
    }
    const matcher: RegExpMatchArray | null = xml.match(ComicInfoParser.WEB);
    if (matcher === null || matcher.length < 2) {
      return null;
    }
    return GalleryDetailUrlParser.parseWithStrict(matcher[1].trim(), true);
  }

  /**
   * 按 UTF-8 读取 ComicInfo.xml 再解析 Web。内容超过 256KB 或读取失败时返回 null。
   */
  static parseStream(input: InputStream | null): DetailUrlResult | null {
    if (input === null) {
      return null;
    }
    try {
      const chunks: Uint8Array[] = [];
      const buffer: ArrayBuffer = new ArrayBuffer(ComicInfoParser.BUFFER_SIZE);
      let total: number = 0;
      while (true) {
        const read: number = input.readBuffer(buffer);
        if (read <= 0) {
          break;
        }
        total += read;
        if (total > ComicInfoParser.MAX_BYTES) {
          return null;
        }
        const slice: Uint8Array = new Uint8Array(read);
        slice.set(new Uint8Array(buffer, 0, read));
        chunks.push(slice);
      }
      const merged: Uint8Array = new Uint8Array(total);
      let offset: number = 0;
      for (let i = 0; i < chunks.length; i++) {
        merged.set(chunks[i], offset);
        offset += chunks[i].byteLength;
      }
      return ComicInfoParser.parse(decodeUtf8Bytes(merged));
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      return null;
    }
  }
}

/** 纯 TS UTF-8 解码，确保 Node 测试与鸿蒙真机行为完全一致。 */
function decodeUtf8Bytes(bytes: Uint8Array): string {
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
