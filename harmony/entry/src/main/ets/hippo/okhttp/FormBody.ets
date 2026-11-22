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

/**
 * okhttp3.FormBody 等价（x-www-form-urlencoded）。
 *
 * 上游用法：EhEngine.signIn / commentGallery / addFavorites / modifyFavorites /
 *           downloadArchive / downloadArchiver / rateGallery / resetLimit
 * 全部是 `new FormBody.Builder().add(k, v).build()`。
 *
 * 编码按 OkHttp 的 FormBody 规则：`+` 表示空格，其它非安全字符 %XX 大写十六进制。
 * 这一点对 e-hentai 的 `submit=Search`、`dlcheck` 等参数是必需的，
 * 不能直接用 encodeURIComponent（会把空格编成 %20；服务端仍接受，但为了
 * 逐字节等价，这里按 OkHttp 规则实现）。
 */
export class FormBody extends RequestBody {
  private readonly _names: string[];
  private readonly _values: string[];
  private _encoded: ArrayBuffer | null;

  constructor(names: string[], values: string[], encoded: ArrayBuffer | null = null) {
    super();
    this._names = names;
    this._values = values;
    this._encoded = encoded;
  }

  contentType(): MediaType | null {
    return MediaTypes.FORM;
  }

  contentLength(): number {
    return this.bytes().byteLength;
  }

  bytes(): ArrayBuffer {
    if (this._encoded !== null) {
      return this._encoded;
    }
    const sb: string[] = [];
    for (let i = 0; i < this._names.length; i++) {
      if (i > 0) {
        sb.push('&');
      }
      sb.push(this._names[i]);
      sb.push('=');
      sb.push(this._values[i]);
    }
    const buf: ArrayBuffer = utf8Encode(sb.join(''));
    this._encoded = buf;
    return buf;
  }

  size(): number {
    return this._names.length;
  }

  /** 对齐 okhttp FormBody.name(int)：返回**已解码**的名字。 */
  name(index: number): string {
    return this._names[index];
  }

  /** 对齐 okhttp FormBody.value(int)：返回已编码的值（add 时即编码）。 */
  value(index: number): string {
    return this._values[index];
  }

}

/** okhttp3.FormBody.Builder 等价。 */
export class FormBodyBuilder {
  private names: string[] = [];
  private values: string[] = [];

  /** 对齐 add(String, String)：名字与值都按表单规则编码。 */
  add(name: string, value: string): FormBodyBuilder {
    this.names.push(FormBodyBuilder.canonicalize(name, false));
    this.values.push(FormBodyBuilder.canonicalize(value, false));
    return this;
  }

  /** 对齐 addEncoded(String, String)：调用方已编码，原样写入。 */
  addEncoded(name: string, value: string): FormBodyBuilder {
    this.names.push(FormBodyBuilder.canonicalize(name, true));
    this.values.push(FormBodyBuilder.canonicalize(value, true));
    return this;
  }

  build(): FormBody {
    return new FormBody(this.names.slice(), this.values.slice());
  }

  /**
   * OkHttp FormBody 的 canonicalize：
   *   - ' ' → '+'（仅在 alreadyEncoded 为 false 时）
   *   - 保留字符集外的字节 → %XX（大写）
   *   - alreadyEncoded 为 true 时，遇到 '%' 且后跟两位十六进制视为合法并原样保留
   */
  static canonicalize(s: string, alreadyEncoded: boolean): string {
    let out: string = '';
    for (let i = 0; i < s.length; i++) {
      const ch: string = s.charAt(i);
      const code: number = s.charCodeAt(i);
      if (code < 0x80 && (code === 0x20)) {
        out += '+';
        continue;
      }
      if (code < 0x80 && FormBodyBuilder.isFormSafe(code)) {
        out += ch;
        continue;
      }
      if (alreadyEncoded && ch === '%' && i + 2 < s.length &&
        FormBodyBuilder.isHex(s.charAt(i + 1)) && FormBodyBuilder.isHex(s.charAt(i + 2))) {
        out += '%' + s.charAt(i + 1) + s.charAt(i + 2);
        i += 2;
        continue;
      }
      // 多字节字符按 UTF-8 编码后逐字节转义
      const bytes: Uint8Array = new Uint8Array(utf8Encode(ch));
      for (let b = 0; b < bytes.byteLength; b++) {
        out += '%';
        out += FormBodyBuilder.HEX.charAt((bytes[b] >> 4) & 0xf);
        out += FormBodyBuilder.HEX.charAt(bytes[b] & 0xf);
      }
    }
    return out;
  }

  private static HEX: string = '0123456789ABCDEF';

  private static isHex(c: string): boolean {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
  }

  /**
   * OkHttp 的 FORM_ENCODE_SET 取反：允许 A-Z a-z 0-9 以及 -._*~ 之外全部转义。
   * （OkHttp 实际允许集：ALPHA / DIGIT / "-" / "." / "_" / "~" / "*" / "'" / "(" / ")"）
   */
  private static isFormSafe(code: number): boolean {
    if (code >= 0x30 && code <= 0x39) {
      return true;
    }
    if (code >= 0x41 && code <= 0x5a) {
      return true;
    }
    if (code >= 0x61 && code <= 0x7a) {
      return true;
    }
    return code === 0x2d || code === 0x2e || code === 0x5f || code === 0x7e ||
      code === 0x2a || code === 0x27 || code === 0x28 || code === 0x29;
  }
}
