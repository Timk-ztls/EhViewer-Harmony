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

import { ChromeRequestBuilder } from '../../okhttp/ChromeRequestBuilder';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhRequestBuilder.java
 * （inventory S0077，53 行）
 *
 * 就是 `ChromeRequestBuilder` + 可选的 Referer / Origin 头（exhentai 需要 Referer 才不返回 sadpanda）。
 *
 * 上游四个构造器（ArkTS 无重载）→ 本层四个静态工厂：
 *   EhRequestBuilder.of(url)
 *   EhRequestBuilder.ofReferer(url, referer)
 *   EhRequestBuilder.ofRefererOrigin(url, referer, origin)
 *   EhRequestBuilder.ofHeaders(url, headers)                     // 顺序按 Map 迭代序
 *
 * 注意：**空字符串和 null 不等价** —— 上游判的是 `referer != null`，
 * 所以传 "" 也会加一个空的 Referer 头。照搬。
 */
export class EhRequestBuilder extends ChromeRequestBuilder {
  constructor(url: string) {
    super(url);
  }

  static of(url: string): EhRequestBuilder {
    return new EhRequestBuilder(url);
  }

  static ofReferer(url: string, referer: string | null): EhRequestBuilder {
    const b: EhRequestBuilder = new EhRequestBuilder(url);
    if (referer !== null) {
      b.addHeader('Referer', referer);
    }
    return b;
  }

  static ofRefererOrigin(url: string, referer: string | null, origin: string | null): EhRequestBuilder {
    const b: EhRequestBuilder = new EhRequestBuilder(url);
    if (referer !== null) {
      b.addHeader('Referer', referer);
    }
    if (origin !== null) {
      b.addHeader('Origin', origin);
    }
    return b;
  }

  /** 对齐 `EhRequestBuilder(Map<String,String> headers, String url)`：按传入顺序逐条加头。 */
  static ofHeaders(url: string, headers: Map<string, string>): EhRequestBuilder {
    const b: EhRequestBuilder = new EhRequestBuilder(url);
    headers.forEach((value: string, key: string): void => {
      b.addHeader(key, value);
    });
    return b;
  }
}
