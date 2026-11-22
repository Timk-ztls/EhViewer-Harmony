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
import { JsonArray, JsonObject } from './Json';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryPageApiParser.java
 * （inventory S0101，87 行）
 *
 * 阅读页 API（`api.php?method=gtimg` 之类）的 `i3/i6/i7` 三个 HTML 片段 →
 *   imageUrl（当前页图片）、skipHathKey（跳过 H@H 的 key）、otherImageUrl、originImageUrl
 *
 * 四个正则逐字符照搬；`i7` 为 null 时回落到 `i6` 里找原图链接（上游如此）。
 * 结束条件照搬：`imageUrl` 为空 → `ParseException("Parse image url and skip hath key error")`。
 * JSON 异常 → `ParseException("Can't parse json")`（cause 挂原异常）。
 */
export class GalleryPageApiParser {
  private static readonly PATTERN_IMAGE_URL: RegExp = /<img[^>]*src="([^"]+)" style/;
  private static readonly PATTERN_SKIP_HATH_KEY: RegExp = /onclick="return nl\('([^\)]+)'\)/;
  private static readonly PATTERN_ORIGIN_IMAGE_URL: RegExp = /<a href="([^"]+)fullimg([^"]+)">/;
  private static readonly PATTERN_ORIGIN_IMAGE_URL_NEW: RegExp =
    /<a href="#" onclick="prompt\('Copy the URL below.', '([^"]+)'\)/;

  static parse(body: string): GalleryPageApiParserResult {
    try {
      const result: GalleryPageApiParserResult = new GalleryPageApiParserResult();
      const jo: JsonObject = JsonObject.parse(body);
      if (jo.has('error')) {
        throw new ParseException(jo.getString('error'), body);
      }

      const i3: string = jo.getString('i3');
      let m: RegExpMatchArray | null = i3.match(GalleryPageApiParser.PATTERN_IMAGE_URL);
      if (m !== null) {
        result.imageUrl = ParserUtils.unescapeXml(GalleryPageApiParser.trimStr(m[1]));
      }

      const i6: string = jo.getString('i6');
      m = i6.match(GalleryPageApiParser.PATTERN_SKIP_HATH_KEY);
      if (m !== null) {
        result.skipHathKey = ParserUtils.unescapeXml(GalleryPageApiParser.trimStr(m[1]));
      }

      m = i6.match(GalleryPageApiParser.PATTERN_ORIGIN_IMAGE_URL_NEW);
      if (m !== null) {
        result.otherImageUrl = ParserUtils.unescapeXml(m[1]);
      }

      // i7 为 null → 从 i6 找原图；否则从 i7 找
      if (jo.isNull('i7')) {
        m = i6.match(GalleryPageApiParser.PATTERN_ORIGIN_IMAGE_URL);
      } else {
        const i7: string = jo.getString('i7');
        m = i7.match(GalleryPageApiParser.PATTERN_ORIGIN_IMAGE_URL);
      }
      if (m !== null) {
        result.originImageUrl =
          ParserUtils.unescapeXml(m[1]) + 'fullimg' + ParserUtils.unescapeXml(m[2]);
      }

      if (result.imageUrl.length > 0) {
        return result;
      }
      throw new ParseException('Parse image url and skip hath key error', body);
    } catch (e) {
      if (e instanceof ParseException) {
        throw e as ParseException;
      }
      throw new ParseException("Can't parse json", body, e as Error);
    }
  }

  private static trimStr(s: string | null): string {
    return s === null || s === undefined ? '' : s.trim();
  }
}

/**
 * 对齐 GalleryPageApiParser.Result。
 * 类名用 `GalleryPageApiParserResult` 以便与上游类型名一致；`PageApiResult` 保留为别名。
 */
export class GalleryPageApiParserResult {
  imageUrl: string = '';
  otherImageUrl: string = '';
  skipHathKey: string = '';
  originImageUrl: string = '';
}

/** 旧名别名（保持已有调用点可用）。 */
export class PageApiResult extends GalleryPageApiParserResult {
}