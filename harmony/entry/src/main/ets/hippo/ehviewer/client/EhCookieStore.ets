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

import { Cookie, CookieBuilder } from '../../okhttp/Cookie';
import { HttpUrl } from '../../okhttp/HttpUrl';
import { CookieRepository, CookieStoreBackend } from '../../network/CookieRepository';
import { EhConfig } from './EhConfig';
import { EhUrl } from './EhUrl';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhCookieStore.java
 * （inventory S0072，113 行）
 *
 * 在 `CookieRepository` 上加 ehviewer 的三条业务规则：
 *   1. 登录判定 = 同时存在 `ipb_member_id` 与 `ipb_pass_hash`
 *   2. 每次 loadForRequest 时，若目标是 E 站域，**补一条内容警告 cookie**
 *      （`nw=1`，domain=e-hentai.org，path=/，永不过期）
 *   3. `newCookie(...)`：把 cookie 改写域/持久性时的固定规则（forceLongLive / forcePersistent /
 *      forceNotHostOnly 的组合顺序照搬）
 *
 * `Long.MAX_VALUE` 在本层用 `Number.MAX_SAFE_INTEGER`（Cookie.expiresAt 是毫秒数，
 * 两者在「永不过期」的语义上等价，且不会丢精度）。
 */
export class EhCookieStore extends CookieRepository {
  static readonly KEY_IPD_MEMBER_ID: string = 'ipb_member_id';
  static readonly KEY_IPD_PASS_HASH: string = 'ipb_pass_hash';
  static readonly KEY_IGNEOUS: string = 'igneous';

  static readonly MAX_EXPIRES: number = Number.MAX_SAFE_INTEGER;

  constructor(db: CookieStoreBackend) {
    super(db);
  }

  /** 对齐 `signOut()`：清空全部 cookie（内存 + 库）。 */
  signOut(): void {
    this.clear();
  }

  /** 对齐 `hasSignedIn()`：E 站域下同时有两个登录 cookie。 */
  hasSignedIn(): boolean {
    const url: HttpUrl = HttpUrl.parse(EhUrl.HOST_E) as HttpUrl;
    return this.contains(url, EhCookieStore.KEY_IPD_MEMBER_ID) &&
      this.contains(url, EhCookieStore.KEY_IPD_PASS_HASH);
  }

  /** 对齐 `sTipsCookie`：内容警告「不再提示」cookie。 */
  static tipsCookie(): Cookie {
    return new CookieBuilder()
      .name(EhConfig.KEY_CONTENT_WARNING)
      .value(EhConfig.CONTENT_WARNING_NOT_SHOW)
      .domain(EhUrl.DOMAIN_E)
      .path('/')
      .expiresAt(EhCookieStore.MAX_EXPIRES)
      .build();
  }

  /**
   * 对齐 `newCookie(cookie, newDomain, forcePersistent, forceLongLive, forceNotHostOnly)`。
   * 判定顺序照搬：forceLongLive > 原持久性 > forcePersistent。
   */
  static newCookie(cookie: Cookie, newDomain: string, forcePersistent: boolean,
    forceLongLive: boolean, forceNotHostOnly: boolean): Cookie {
    const builder: CookieBuilder = new CookieBuilder();
    builder.name(cookie.name());
    builder.value(cookie.value());
    if (forceLongLive) {
      builder.expiresAt(EhCookieStore.MAX_EXPIRES);
    } else if (cookie.persistent()) {
      builder.expiresAt(cookie.expiresAt());
    } else if (forcePersistent) {
      builder.expiresAt(EhCookieStore.MAX_EXPIRES);
    }
    if (cookie.hostOnly() && !forceNotHostOnly) {
      builder.hostOnlyDomain(newDomain);
    } else {
      builder.domain(newDomain);
    }
    builder.path(cookie.path());
    if (cookie.secure()) {
      builder.secure();
    }
    if (cookie.httpOnly()) {
      builder.httpOnly();
    }
    return builder.build();
  }

  /**
   * 对齐 `loadForRequest(HttpUrl)`：先取仓储结果，若目标匹配 E 站域则过滤
   * `nw`/`uconfig` 后再在末尾追加内容警告 cookie（`sTipsCookie`），且不落库。
   */
  loadForRequest(url: HttpUrl): Cookie[] {
    const cookies: Cookie[] = super.loadForRequest(url);
    const checkTips: boolean = CookieRepository.domainMatch(url, EhUrl.DOMAIN_E);
    if (!checkTips) {
      return cookies;
    }
    const result: Cookie[] = [];
    for (let i = 0; i < cookies.length; i++) {
      const cookie: Cookie = cookies[i];
      const name: string = cookie.name();
      if (name === EhConfig.KEY_CONTENT_WARNING || name === EhConfig.KEY_UCONFIG) {
        continue;
      }
      result.push(cookie);
    }
    result.push(EhCookieStore.tipsCookie());
    return result;
  }

  /** 向后兼容包装：委托给 `loadForRequest`。 */
  loadForRequestWithTips(url: HttpUrl): Cookie[] {
    return this.loadForRequest(url);
  }
}
