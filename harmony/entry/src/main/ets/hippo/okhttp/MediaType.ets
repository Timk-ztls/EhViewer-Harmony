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

/**
 * okhttp3.MediaType 等价层。
 *
 * 上游用法（grep 自 origin/upstream）：
 *   MediaType.parse("file")            EhEngine.imageSearch
 *   MediaType.parse("submit")          EhEngine.imageSearch
 *   MediaType.parse("multipart/form-data")  MultipartBody.FORM
 *   MediaType.parse("application/x-www-form-urlencoded") FormBody
 *
 * OkHttp 的 parse 对非法类型返回 null；这里保持同样契约（返回 MediaType | null），
 * 调用方用 ?? 兜底，与 Java 的 null 检查语义一致。
 */
export class MediaType {
  private readonly _type: string;
  private readonly _subtype: string;
  private readonly _charset: string | null;

  constructor(type: string, subtype: string, charset: string | null = null) {
    this._type = type;
    this._subtype = subtype;
    this._charset = charset;
  }

  /**
   * 对齐 MediaType.parse(String)。
   * OkHttp 的 parse 语法：type "/" subtype *(";" parameter)。type/subtype 允许 token 字符。
   * 上游传 "file" / "submit" 这类没有斜杠的串时 OkHttp 返回 null，这里必须同样返回 null。
   */
  static parse(value: string | null | undefined): MediaType | null {
    if (value === null || value === undefined) {
      return null;
    }
    const s: string = value.trim();
    if (s.length === 0) {
      return null;
    }
    const semi: number = s.indexOf(';');
    const mime: string = (semi === -1 ? s : s.substring(0, semi)).trim();
    const slash: number = mime.indexOf('/');
    if (slash <= 0 || slash === mime.length - 1) {
      return null;
    }
    const type: string = mime.substring(0, slash).trim();
    const subtype: string = mime.substring(slash + 1).trim();
    if (!MediaType.isToken(type) || !MediaType.isToken(subtype)) {
      return null;
    }
    let charset: string | null = null;
    if (semi !== -1) {
      const params: string[] = s.substring(semi + 1).split(';');
      for (let i = 0; i < params.length; i++) {
        const p: string = params[i].trim();
        const eq: number = p.indexOf('=');
        if (eq > 0) {
          const key: string = p.substring(0, eq).trim().toLowerCase();
          if (key === 'charset') {
            let v: string = p.substring(eq + 1).trim();
            if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
              v = v.substring(1, v.length - 1);
            }
            charset = v;
          }
        }
      }
    }
    return new MediaType(type.toLowerCase(), subtype.toLowerCase(), charset);
  }

  /** RFC 7230 token 字符集，OkHttp 的静态校验同等实现。 */
  private static isToken(s: string): boolean {
    if (s.length === 0) {
      return false;
    }
    const bad: string = '()<>@,;:\\"/[]?={} \t';
    for (let i = 0; i < s.length; i++) {
      const ch: string = s.charAt(i);
      if (bad.indexOf(ch) >= 0) {
        return false;
      }
      const code: number = s.charCodeAt(i);
      if (code < 0x20 || code > 0x7e) {
        return false;
      }
    }
    return true;
  }

  type(): string {
    return this._type;
  }

  subtype(): string {
    return this._subtype;
  }

  charset(defaultValue: string | null = null): string | null {
    return this._charset !== null ? this._charset : defaultValue;
  }

  toString(): string {
    let s: string = this._type + '/' + this._subtype;
    if (this._charset !== null) {
      s += '; charset=' + this._charset;
    }
    return s;
  }
}

/** 常用常量，避免重复 new（对应 OkHttp 的静态字段）。 */
export class MediaTypes {
  static readonly FORM: MediaType = new MediaType('application', 'x-www-form-urlencoded');
  static readonly MULTIPART_FORM: MediaType = new MediaType('multipart', 'form-data');
  static readonly OCTET_STREAM: MediaType = new MediaType('application', 'octet-stream');
  static readonly PLAIN: MediaType = new MediaType('text', 'plain');

  /** MultipartBody.FORM —— 上游写 builder.setType(MultipartBody.FORM)。 */
  static readonly FORM_DATA: MediaType = new MediaType('multipart', 'form-data');
}
