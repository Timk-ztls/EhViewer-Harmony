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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryPageUrlParser.java
 * （inventory S0103，59 行）
 *
 * 解析阅读页 URL：`https://exhentai.org/s/91ea4b6d89/901103-12`
 *   group(1) = pToken（10 位十六进制）
 *   group(2) = gid
 *   group(3) = 页码（1 基）→ 返回时 -1 变成 0 基
 *
 * storage-db 的 `SpiderInfo.getSpiderInfo()` 依赖本类与 ParseException(S0089)，故优先交付。
 *
 * 两个正则逐字符照搬（域名交替必须包含 lofi 站）：
 *   严格：`https?://(?:exhentai.org|e-hentai.org|lofi.e-hentai.org)/s/([0-9a-f]{10})/(\d+)-(\d+)`
 *   宽松：`([0-9a-f]{10})/(\d+)-(\d+)`
 *
 * 边界行为照搬：
 *   - url == null → null
 *   - 不匹配 → null
 *   - gid < 0 或 page < 0（即 group(3) 解析失败或为 0）→ null
 *   - 数字解析用 parseLongSafely/parseIntSafely（失败给 -1 / 0，不抛）
 */
export class GalleryPageUrlParser {
  /** 严格模式：完整 URL（三个域名之一）。 */
  private static readonly URL_STRICT_PATTERN: RegExp =
    /https?:\/\/(?:exhentai\.org|e-hentai\.org|lofi\.e-hentai\.org)\/s\/([0-9a-f]{10})\/(\d+)-(\d+)/;

  /** 宽松模式：只认 `<pToken>/<gid>-<page>` 片段。 */
  private static readonly URL_PATTERN: RegExp = /([0-9a-f]{10})\/(\d+)-(\d+)/;

  /** 对齐 parse(String url)：默认严格。 */
  static parse(url: string | null): PageUrlResult | null {
    return GalleryPageUrlParser.parseWithStrict(url, true);
  }

  /** 对齐 parse(String url, boolean strict)。 */
  static parseWithStrict(url: string | null, strict: boolean): PageUrlResult | null {
    if (url === null || url === undefined) {
      return null;
    }
    const pattern: RegExp = strict
      ? GalleryPageUrlParser.URL_STRICT_PATTERN
      : GalleryPageUrlParser.URL_PATTERN;
    const m: RegExpMatchArray | null = url.match(pattern);
    if (m === null) {
      return null;
    }
    const result: PageUrlResult = new PageUrlResult();
    result.gid = GalleryPageUrlParser.parseLongSafely(m[2], -1);
    result.pToken = m[1];
    result.page = GalleryPageUrlParser.parseIntSafely(m[3], 0) - 1;
    if (result.gid < 0 || result.page < 0) {
      return null;
    }
    return result;
  }

  /** 对齐 NumberUtils.parseLongSafely(String, long)：解析失败给默认值，不抛。 */
  private static parseLongSafely(s: string, def: number): number {
    if (s === null || s === undefined || s.length === 0) {
      return def;
    }
    const v: number = Number.parseInt(s, 10);
    return Number.isNaN(v) ? def : v;
  }

  /** 对齐 NumberUtils.parseIntSafely(String, int)。 */
  private static parseIntSafely(s: string, def: number): number {
    return GalleryPageUrlParser.parseLongSafely(s, def);
  }
}

/** 对齐 GalleryPageUrlParser.Result（静态嵌套类 → 文件级）。 */
export class PageUrlResult {
  gid: number = 0;
  pToken: string = '';
  /** 0 基页码（上游 group(3) 是 1 基，解析时已 -1）。 */
  page: number = 0;
}
