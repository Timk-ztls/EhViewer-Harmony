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

import { Document, Element, Jsoup } from '../../../jsoup/index';
import { EhUrl } from '../EhUrl';
import { ParseException } from '../exception/ParseException';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/ForumsParser.java
 * （inventory S0095，39 行）
 *
 * 从论坛页 `#userlinks` 取「用户控制面板」链接（三级 child(0) 下钻）。
 * 上游 `Jsoup.parse(body, EhUrl.URL_FORUMS)` 的 baseUri 只影响 `absUrl`，
 * 本方法取原始 href，故 base 不影响结果；为便于后续 `absUrl` 使用，常量仍从 EhUrl 取。
 *
 * 失败 → `ParseException("Parse forums error", body)`（含 userlinks 缺失/结构不符）。
 */
export class ForumsParser {
  static parse(body: string): string {
    try {
      const d: Document = Jsoup.parse(body);
      const userlinks: Element | null = d.getElementById('userlinks');
      if (userlinks === null) {
        throw new Error('userlinks is null');
      }
      const c0: Element | null = userlinks.child(0);
      const c1: Element | null = c0 === null ? null : c0.child(0);
      const c2: Element | null = c1 === null ? null : c1.child(0);
      if (c2 === null) {
        throw new Error('userlinks structure unexpected');
      }
      return c2.attr('href');
    } catch (e) {
      throw new ParseException('Parse forums error', body, e as Error);
    }
  }

  /** 上游解析时使用的 baseUri（供需要 absUrl 的调用方使用）。 */
  static baseUri(): string {
    return EhUrl.URL_FORUMS;
  }
}
