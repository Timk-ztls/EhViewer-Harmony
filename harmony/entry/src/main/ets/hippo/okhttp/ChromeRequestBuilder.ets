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

import { HttpUrl } from './HttpUrl';
import { RequestBuilder } from './Request';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/okhttp/ChromeRequestBuilder.java
 * （inventory S0444）
 *
 * 行为逐行保持：
 *   1) 取 url.split("/")[2] 作为 Host 头（domain fronting 需求：EhViewer 用 IP 直连 + Host 头）
 *   2) 固定的 Chrome UA / Accept / Accept-Language
 *   3) 被注释掉的头（Accept-Encoding、Source-App、Sec-Fetch-*、sec-ch-ua*）保持注释状态，
 *      不主动发送 —— 这是上游的刻意选择（发了会触发 Cloudflare 的浏览器指纹校验）
 *
 * ArkTS 差异（仅类层次）：
 *   Java:  class ChromeRequestBuilder extends Request.Builder
 *   ArkTS: class ChromeRequestBuilder extends RequestBuilder
 * 方法链（url/addHeader/post/build）与字段顺序完全一致。
 */
export class ChromeRequestBuilder extends RequestBuilder {
  private static readonly CHROME_USER_AGENT: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
    'Chrome/118.0.0.0 Safari/537.36';

  private static readonly CHROME_ACCEPT: string =
    'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8';

  private static readonly CHROME_ACCEPT_ENCODING: string = 'gzip, deflate, br, zstd';

  private static readonly CHROME_ACCEPT_LANGUAGE: string = 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';

  private static readonly CHROME_SEC_FETCH_DEST: string = 'empty';
  private static readonly CHROME_SEC_FETCH_MODE: string = 'cors';
  private static readonly CHROME_SEC_FETCH_SITE: string = 'same-site';
  private static readonly CHROME_SEC_CH_UA: string =
    '"Chromium";v="118", "Google Chrome";v="118", "Not=A?Brand";v="99"';
  private static readonly CHROME_SEC_CH_UA_MOBILE: string = '?0';
  private static readonly CHROME_SEC_CH_UA_PLATFORM: string = 'Windows';

  constructor(url: string) {
    super();
    // 与上游一致的 host 抽取方式：先解析成 HttpUrl 校验，再按 split("/")[2] 取 authority
    const parsed: HttpUrl | null = HttpUrl.parse(url);
    if (parsed === null) {
      throw new Error(`unexpected url: ${url}`);
    }
    const segments: string[] = url.split('/');
    const host: string = segments.length > 2 ? segments[2] : parsed.host();
    // domain fronting
    this.url(url);
    this.addHeader('Host', host);
    this.addHeader('User-Agent', ChromeRequestBuilder.CHROME_USER_AGENT);
    this.addHeader('Accept', ChromeRequestBuilder.CHROME_ACCEPT);
    // this.addHeader('Accept-Encoding', CHROME_ACCEPT_ENCODING);  // 上游注释掉：压缩由网络栈协商
    this.addHeader('Accept-Language', ChromeRequestBuilder.CHROME_ACCEPT_LANGUAGE);
    // this.addHeader('Source-App', 'Ehviewer');
    // this.addHeader('Sec-Fetch-Dest', CHROME_SEC_FETCH_DEST);
    // this.addHeader('Sec-Fetch-Mode', CHROME_SEC_FETCH_MODE);
    // this.addHeader('Sec-Fetch-Site', CHROME_SEC_FETCH_SITE);
    // this.addHeader('sec-ch-ua', CHROME_SEC_CH_UA);
    // this.addHeader('sec-ch-ua-mobile', CHROME_SEC_CH_UA_MOBILE);
    // this.addHeader('sec-ch-ua-platform', CHROME_SEC_CH_UA_PLATFORM);
  }
}
