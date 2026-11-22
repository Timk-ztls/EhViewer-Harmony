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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/ParserUtils.java
 * （inventory S0107，44 行）
 *
 * 所有 parser 的公共工具：日期格式化、XML 反转义 + trim、带千分位的数字解析。
 *
 * ArkTS 映射：
 *   SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US) → 手写 formatDate（零依赖、不受 locale 影响）
 *   StringUtils.unescapeXml                        → 本文件 unescapeXml（实体表与 jsoup 解码一致）
 *   NumberUtils.parseIntSafely/parseLongSafely/parseFloatSafely → parse* + 失败返回 defValue
 *
 * 注意：`trim()` 先反转义再 trim（上游顺序），因为 `&nbsp;` 解码成 U+00A0 后
 * `String.trim()` 不会去掉它 —— JS 的 trim 也不去 U+00A0（符合预期，行为一致）。
 */
export class ParserUtils {
  /** 对齐 formatDate(long)：本地时区，`yyyy-MM-dd HH:mm`，与上游 SimpleDateFormat 同格式。 */
  static formatDate(time: number): string {
    const d: Date = new Date(time);
    const y: string = ParserUtils.pad4(d.getFullYear());
    const mo: string = ParserUtils.pad2(d.getMonth() + 1);
    const da: string = ParserUtils.pad2(d.getDate());
    const h: string = ParserUtils.pad2(d.getHours());
    const mi: string = ParserUtils.pad2(d.getMinutes());
    return `${y}-${mo}-${da} ${h}:${mi}`;
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }

  private static pad4(n: number): string {
    let s: string = '' + n;
    while (s.length < 4) {
      s = '0' + s;
    }
    return s;
  }

  /** 对齐 trim(String)：null → ""，然后 XML 反转义 + trim。 */
  static trim(str: string | null): string {
    const s: string = str === null || str === undefined ? '' : str;
    return ParserUtils.unescapeXml(s).trim();
  }

  /** 对齐 parseInt(String, int)：先 trim + 去千分位，失败给默认值。 */
  static parseInt(str: string | null, defValue: number): number {
    const s: string = ParserUtils.trim(str).split(',').join('');
    if (s.length === 0) {
      return defValue;
    }
    const v: number = Number.parseInt(s, 10);
    return Number.isNaN(v) ? defValue : v;
  }

  /** 对齐 parseLong(String, long)。 */
  static parseLong(str: string | null, defValue: number): number {
    return ParserUtils.parseInt(str, defValue);
  }

  /** 对齐 parseFloat(String, float)。 */
  static parseFloat(str: string | null, defValue: number): number {
    const s: string = ParserUtils.trim(str).split(',').join('');
    if (s.length === 0) {
      return defValue;
    }
    const v: number = Number.parseFloat(s);
    return Number.isNaN(v) ? defValue : v;
  }

  /**
   * 对齐 StringUtils.unescapeXml：`&amp; &lt; &gt; &quot; &apos;` + 数值实体。
   * 与 jsoup 的解码不同点：这里不处理命名实体表（上游此函数也只处理这几个 + 数值）。
   */
  static unescapeXml(s: string): string {
    if (s.indexOf('&') < 0) {
      return s;
    }
    return s.replace(/&(#x?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);/g,
      (match: string, body: string): string => {
        switch (body) {
          case 'amp':
            return '&';
          case 'lt':
            return '<';
          case 'gt':
            return '>';
          case 'quot':
            return '"';
          case 'apos':
            return '\'';
          default:
            break;
        }
        if (body.charAt(0) === '#') {
          const isHex: boolean = body.charAt(1) === 'x' || body.charAt(1) === 'X';
          const code: number = Number.parseInt(isHex ? body.substring(2) : body.substring(1),
            isHex ? 16 : 10);
          if (Number.isNaN(code) || code < 0 || code > 0x10ffff) {
            return match;
          }
          return String.fromCharCode(code);
        }
        return match;
      });
  }
}
