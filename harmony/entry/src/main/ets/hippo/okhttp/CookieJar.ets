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
import { Cookie } from './Cookie';

/**
 * okhttp3.CookieJar 等价接口。
 *
 * 上游实现：EhCookieStore extends CookieRepository implements CookieJar
 *   saveFromResponse(HttpUrl, List<Cookie>)
 *   loadForRequest(HttpUrl): List<Cookie>
 * ArkTS 的接口方法不能有默认实现，故全抽象；List<T> → Cookie[]。
 */
export interface CookieJar {
  saveFromResponse(url: HttpUrl, cookies: Cookie[]): void;

  loadForRequest(url: HttpUrl): Cookie[];
}

/** okhttp3.CookieJar.NO_COOKIES 等价。 */
export class NoCookies implements CookieJar {
  saveFromResponse(url: HttpUrl, cookies: Cookie[]): void {
    // no-op
  }

  loadForRequest(url: HttpUrl): Cookie[] {
    return [];
  }
}
