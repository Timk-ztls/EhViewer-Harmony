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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryDetailUrlParser.java
 * （inventory S0102，58 行）
 *
 * 解析画廊详情 URL：`https://exhentai.org/g/1234567/a1b2c3d4e5` 与 `/mpv/<gid>/<token>`
 *   group(1) = gid，group(2) = token（10 位十六进制）
 *
 * 边界照搬：url == null → null；不匹配 → null；gid < 0 → null。
 * `GalleryListParser.parseGalleryInfo` 靠它取 gid/token，是列表项的必需字段。
 */
export class GalleryDetailUrlParser {
  /** 严格：三域名 + `/g|mpv/` 段。 */
  private static readonly URL_STRICT_PATTERN: RegExp =
    /https?:\/\/(?:exhentai\.org|e-hentai\.org|lofi\.e-hentai\.org)\/(?:g|mpv)\/(\d+)\/([0-9a-f]{10})/;

  /** 宽松：只看 `<gid>/<token>` 片段，并要求 token 之后不是十六进制字符（或行尾）。 */
  private static readonly URL_PATTERN: RegExp = /(\d+)\/([0-9a-f]{10})(?:[^0-9a-f]|$)/;

  static parse(url: string | null): DetailUrlResult | null {
    return GalleryDetailUrlParser.parseWithStrict(url, true);
  }

  static parseWithStrict(url: string | null, strict: boolean): DetailUrlResult | null {
    if (url === null || url === undefined) {
      return null;
    }
    const pattern: RegExp = strict
      ? GalleryDetailUrlParser.URL_STRICT_PATTERN
      : GalleryDetailUrlParser.URL_PATTERN;
    const m: RegExpMatchArray | null = url.match(pattern);
    if (m === null) {
      return null;
    }
    const result: DetailUrlResult = new DetailUrlResult();
    result.gid = GalleryDetailUrlParser.parseLongSafely(m[1], -1);
    result.token = m[2];
    if (result.gid < 0) {
      return null;
    }
    return result;
  }

  private static parseLongSafely(s: string, def: number): number {
    if (s === null || s === undefined || s.length === 0) {
      return def;
    }
    const v: number = Number.parseInt(s, 10);
    return Number.isNaN(v) ? def : v;
  }
}

/** 对齐 GalleryDetailUrlParser.Result（静态嵌套类 → 文件级）。 */
export class DetailUrlResult {
  gid: number = 0;
  token: string = '';
}
