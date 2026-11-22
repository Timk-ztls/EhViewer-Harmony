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

import { ParseException } from '../exception/ParseException';
import { ParserUtils } from './ParserUtils';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryPageParser.java
 * （inventory S0102，66 行）
 *
 * **阅读页 HTML** 解析（与 `GalleryPageApiParser` 的区别：那个吃 api.php 的 JSON 的 i3/i6/i7，
 * 这个吃整页 HTML）。四个正则逐字符照搬，第四个是阅读页独有的 `showkey`：
 *   `<img…src="URL" style`            → imageUrl
 *   `onclick="return nl('KEY')"`      → skipHathKey
 *   `<a href="PREFIXfullimgSUFFIX">`  → originImageUrl（PREFIX + "fullimg" + SUFFIX）
 *   `var showkey="[0-9a-z]+";`        → showKey
 *
 * 结束条件照搬：**imageUrl 与 showKey 都非空**才返回，否则
 * `ParseException("Parse image url and show error", body)`。
 * 注意上游 TODO：「Not sure about the size of show keys」——showkey 只允许 [0-9a-z]。
 */
export class GalleryPageParser {
  private static readonly PATTERN_IMAGE_URL: RegExp = /<img[^>]*src="([^"]+)" style/;
  private static readonly PATTERN_SKIP_HATH_KEY: RegExp = /onclick="return nl\('([^\)]+)'\)/;
  private static readonly PATTERN_ORIGIN_IMAGE_URL: RegExp = /<a href="([^"]+)fullimg([^"]+)">/;
  private static readonly PATTERN_SHOW_KEY: RegExp = /var showkey="([0-9a-z]+)";/;

  static parse(body: string): GalleryPageParserResult {
    const result: GalleryPageParserResult = new GalleryPageParserResult();

    let m: RegExpMatchArray | null = body.match(GalleryPageParser.PATTERN_IMAGE_URL);
    if (m !== null) {
      result.imageUrl = ParserUtils.unescapeXml(m[1].trim());
    }

    m = body.match(GalleryPageParser.PATTERN_SKIP_HATH_KEY);
    if (m !== null) {
      result.skipHathKey = ParserUtils.unescapeXml(m[1].trim());
    }

    m = body.match(GalleryPageParser.PATTERN_ORIGIN_IMAGE_URL);
    if (m !== null) {
      result.originImageUrl = ParserUtils.unescapeXml(m[1]) + 'fullimg' + ParserUtils.unescapeXml(m[2]);
    }

    m = body.match(GalleryPageParser.PATTERN_SHOW_KEY);
    if (m !== null) {
      result.showKey = m[1];
    }

    if (result.imageUrl.length > 0 && result.showKey.length > 0) {
      return result;
    }
    throw new ParseException('Parse image url and show error', body);
  }
}

/**
 * 对齐 GalleryPageParser.Result（静态嵌套类 → 文件级）。
 * 类名用 `GalleryPageParserResult` 是为了让 storage-db 的 SpiderQueen 一眼对上上游类型；
 * `GalleryPageResult` 保留为别名（旧调用点不用改）。
 */
export class GalleryPageParserResult {
  imageUrl: string = '';
  skipHathKey: string = '';
  originImageUrl: string = '';
  showKey: string = '';
}

/** 旧名别名（保持已有调用点可用）。 */
export class GalleryPageResult extends GalleryPageParserResult {
}