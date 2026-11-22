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

/**
 * okhttp3.Cookie 等价层。
 *
 * 上游用到的面（grep origin/upstream）：
 *   Cookie.Builder().name().value().domain().hostOnlyDomain().path().expiresAt().secure().httpOnly().build()
 *       EhCookieStore.newCookie / CookieDatabase.getCookie
 *   cookie.name() / value() / domain() / path() / expiresAt() / persistent() / hostOnly() / secure() / httpOnly()
 *       CookieRepository.addCookie / CookieSet
 *   Cookie.parse(String) —— 传输层解析 Set-Cookie（OkHttp 内部行为，本层需显式实现）
 *
 * Map 键注意：Java 用 Cookie.hashCode/equals 作 HashMap 键；ArkTS 的 Map 对对象用引用相等，
 * 所以 CookieDatabase 迁移时必须用 toKeyString() 作键（name|domain|path）。
 */
export class Cookie {
  private readonly _name: string;
  private readonly _value: string;
  private readonly _expiresAt: number;
  private readonly _domain: string;
  private readonly _path: string;
  private readonly _secure: boolean;
  private readonly _httpOnly: boolean;
  private readonly _persistent: boolean;
  private readonly _hostOnly: boolean;

  constructor(name: string, value: string, expiresAt: number, domain: string, path: string,
    secure: boolean, httpOnly: boolean, persistent: boolean, hostOnly: boolean) {
    this._name = name;
    this._value = value;
    this._expiresAt = expiresAt;
    this._domain = domain;
    this._path = path;
    this._secure = secure;
    this._httpOnly = httpOnly;
    this._persistent = persistent;
    this._hostOnly = hostOnly;
  }

  name(): string {
    return this._name;
  }

  value(): string {
    return this._value;
  }

  /** 对齐 Cookie.expiresAt()：毫秒时间戳；会话 Cookie 为 Long.MAX_VALUE。 */
  expiresAt(): number {
    return this._expiresAt;
  }

  domain(): string {
    return this._domain;
  }

  path(): string {
    return this._path;
  }

  secure(): boolean {
    return this._secure;
  }

  httpOnly(): boolean {
    return this._httpOnly;
  }

  /** 对齐 Cookie.persistent()：有明确过期时间即为持久。 */
  persistent(): boolean {
    return this._persistent;
  }

  hostOnly(): boolean {
    return this._hostOnly;
  }

  /** 供 ArkTS Map 作键用（替换 Java 的 hashCode/equals）。 */
  toKeyString(): string {
    return `${this._name}|${this._domain}|${this._path}`;
  }

  /** 对齐 Cookie.expiresDate()：已过期返回 true。 */
  isExpired(now: number = Date.now()): boolean {
    return this._expiresAt <= now;
  }

  /**
   * 对齐 Cookie.matches(HttpUrl)：RFC 6265 §5.4。
   *   host-only → 域名必须完全相同；否则必须域名后缀匹配
   *   path 前缀匹配
   *   secure cookie 只能发往 https
   */
  matches(url: HttpUrl): boolean {
    if (this._hostOnly) {
      if (url.host() !== this._domain) {
        return false;
      }
    } else if (!Cookie.domainMatch(url.host(), this._domain)) {
      return false;
    }
    if (!Cookie.pathMatch(url.encodedPath(), this._path)) {
      return false;
    }
    if (this._secure && !url.isHttps()) {
      return false;
    }
    return true;
  }

  /** okhttp3.Cookie.domainMatch(String, String) 的等价实现。 */
  static domainMatch(host: string, domain: string): boolean {
    if (host === domain) {
      return true;
    }
    if (!host.endsWith(domain)) {
      return false;
    }
    // 后缀匹配必须是 '.' 边界，且 host 不能是 IP
    if (host.charAt(host.length - domain.length - 1) !== '.') {
      return false;
    }
    return !Cookie.verifyAsIpAddress(host);
  }

  /** okhttp3.Cookie.pathMatch(String, String) 的等价实现。 */
  static pathMatch(urlPath: string, cookiePath: string): boolean {
    if (urlPath === cookiePath) {
      return true;
    }
    if (!urlPath.startsWith(cookiePath)) {
      return false;
    }
    if (cookiePath.endsWith('/')) {
      return true;
    }
    return urlPath.charAt(cookiePath.length) === '/';
  }

  private static verifyAsIpAddress(host: string): boolean {
    // IPv6：含冒号；IPv4：只有数字和点
    if (host.indexOf(':') >= 0) {
      return true;
    }
    for (let i = 0; i < host.length; i++) {
      const c: string = host.charAt(i);
      if (c !== '.' && (c < '0' || c > '9')) {
        return false;
      }
    }
    return host.length > 0;
  }

  /**
   * 对齐 Cookie.parse(HttpUrl, String)：解析一条 Set-Cookie 头。
   * 返回 null 表示该头不可用（name/value 非法、Domain 不匹配或为空等），OkHttp 同样返回 null。
   */
  static parse(url: HttpUrl | null, setCookie: string): Cookie | null {
    if (setCookie === null || setCookie.length === 0) {
      return null;
    }
    const parts: string[] = setCookie.split(';');
    const nameValue: string = parts[0].trim();
    const eq: number = nameValue.indexOf('=');
    if (eq <= 0) {
      return null;
    }
    const name: string = nameValue.substring(0, eq).trim();
    let value: string = nameValue.substring(eq + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (name.length === 0) {
      return null;
    }

    let expiresAt: number = LongMaxValue;
    let hasExpires: boolean = false;
    let deltaSeconds: number = -1;
    let hasMaxAge: boolean = false;
    let domain: string | null = null;
    let path: string | null = null;
    let secure: boolean = false;
    let httpOnly: boolean = false;

    for (let i = 1; i < parts.length; i++) {
      const attr: string = parts[i].trim();
      if (attr.length === 0) {
        continue;
      }
      const aeq: number = attr.indexOf('=');
      const key: string = (aeq < 0 ? attr : attr.substring(0, aeq)).trim().toLowerCase();
      const val: string = aeq < 0 ? '' : attr.substring(aeq + 1).trim();
      if (key === 'expires') {
        const t: number | null = Cookie.parseExpires(val);
        if (t !== null) {
          hasExpires = true;
          expiresAt = t <= 0 ? Number.MIN_SAFE_INTEGER : Math.min(t, MaxCookieDate);
        }
      } else if (key === 'max-age') {
        if (/^-?\d+$/.test(val)) {
          const secs: number = Number(val);
          if (!Number.isNaN(secs)) {
            hasMaxAge = true;
            deltaSeconds = secs;
          }
        }
      } else if (key === 'domain') {
        const d: string = (val.startsWith('.') ? val.substring(1) : val).toLowerCase();
        if (d.length === 0 || d.startsWith('.') || d.endsWith('.')) {
          return null;
        }
        domain = d;
      } else if (key === 'path') {
        path = val;
      } else if (key === 'secure') {
        secure = true;
      } else if (key === 'httponly') {
        httpOnly = true;
      }
    }

    const persistent: boolean = hasMaxAge || hasExpires;
    // RFC 6265 §5.3 step 3：无论属性出现顺序如何，Max-Age 始终优先于 Expires
    if (hasMaxAge) {
      if (deltaSeconds <= 0) {
        expiresAt = Number.MIN_SAFE_INTEGER;
      } else {
        const now: number = Date.now();
        const maxDelta: number = Math.floor((MaxCookieDate - now) / 1000);
        expiresAt = deltaSeconds >= maxDelta ? MaxCookieDate : now + deltaSeconds * 1000;
      }
    }

    const hostOnly: boolean = domain === null;
    if (domain === null) {
      if (url === null) {
        return null;
      }
      domain = url.host();
    }
    if (url !== null && !Cookie.domainMatch(url.host(), domain)) {
      return null;
    }

    // RFC 6265 §5.1.4：缺省或非 '/' 开头的 Path 从请求 url.encodedPath() 推导默认路径
    if (path === null || !path.startsWith('/')) {
      const encodedPath: string = url !== null ? url.encodedPath() : '/';
      const lastSlash: number = encodedPath.lastIndexOf('/');
      path = lastSlash > 0 ? encodedPath.substring(0, lastSlash) : '/';
    }

    return new Cookie(name, value, expiresAt, domain, path, secure, httpOnly, persistent, hostOnly);
  }

  /** 对齐 OkHttp 的 HttpDate.parse（支持 RFC 1123 / RFC 850 / asctime 格式，失败返回 null）。 */
  private static parseExpires(s: string): number | null {
    if (s.length === 0) {
      return null;
    }
    const months: string[] = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    let day: number = -1;
    let mon: number = -1;
    let year: number = -1;
    let hour: number = -1;
    let min: number = -1;
    let sec: number = -1;

    // RFC 1123 / RFC 850: "Wed, 09 Jun 2021 10:18:14 GMT" or "Wednesday, 09-Jun-21 10:18:14 GMT"
    const m1: RegExpMatchArray | null = s.match(
      /^(?:[A-Za-z]+,?\s+)?(\d{1,2})[\s-]+([A-Za-z]{3})[\s-]+(\d{2,4})\s+(\d{1,2}):(\d{2}):(\d{2})(?:\s+\S+)?$/);
    if (m1 !== null) {
      day = Number.parseInt(m1[1], 10);
      mon = months.indexOf(m1[2].toLowerCase());
      year = Number.parseInt(m1[3], 10);
      if (m1[3].length === 2) {
        year += year >= 70 ? 1900 : 2000;
      }
      hour = Number.parseInt(m1[4], 10);
      min = Number.parseInt(m1[5], 10);
      sec = Number.parseInt(m1[6], 10);
    } else {
      // asctime: "Wed Jun  9 10:18:14 2021"
      const m2: RegExpMatchArray | null = s.match(
        /^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(\d{4})$/);
      if (m2 === null) {
        return null;
      }
      mon = months.indexOf(m2[1].toLowerCase());
      day = Number.parseInt(m2[2], 10);
      hour = Number.parseInt(m2[3], 10);
      min = Number.parseInt(m2[4], 10);
      sec = Number.parseInt(m2[5], 10);
      year = Number.parseInt(m2[6], 10);
    }

    if (mon < 0 || year < 1601 || day < 1 || day > 31 || hour > 23 || min > 59 || sec > 59) {
      return null;
    }
    const t: number = Date.UTC(year, mon, day, hour, min, sec);
    return Number.isNaN(t) ? null : t;
  }

  /** 对齐 OkHttp 的 HttpDate.parse（失败返回 -1）。 */
  static parseHttpDate(s: string): number {
    const t: number | null = Cookie.parseExpires(s);
    return t === null ? -1 : t;
  }

  toString(): string {
    return `${this._name}=${this._value}; domain=${this._domain}; path=${this._path}` +
      (this._persistent ? `; expiresAt=${this._expiresAt}` : '') +
      (this._secure ? '; secure' : '') + (this._httpOnly ? '; httpOnly' : '');
  }
}

/** Java 的 Long.MAX_VALUE：会话 Cookie 的 expiresAt 哨兵值。 */
export const LongMaxValue: number = 9223372036854775807;

/** OkHttp HttpDate.MAX_DATE（9999-12-31T23:59:59.999Z）。 */
const MaxCookieDate: number = 253402300799999;

/** okhttp3.Cookie.Builder 等价。 */
export class CookieBuilder {
  private _name: string | null = null;
  private _value: string = '';
  private _expiresAt: number = LongMaxValue;
  private _domain: string | null = null;
  private _path: string = '/';
  private _secure: boolean = false;
  private _httpOnly: boolean = false;
  private _persistent: boolean = false;
  private _hostOnly: boolean = false;

  name(name: string): CookieBuilder {
    if (name.length === 0) {
      throw new Error('name is empty');
    }
    this._name = name;
    return this;
  }

  value(value: string): CookieBuilder {
    this._value = value;
    return this;
  }

  /** 对齐 expiresAt(long)：显式过期时间 → persistent。 */
  expiresAt(expiresAt: number): CookieBuilder {
    this._expiresAt = expiresAt;
    this._persistent = true;
    return this;
  }

  /** 对齐 domain(String)：共享域 cookie。 */
  domain(domain: string): CookieBuilder {
    this._domain = CookieBuilder.normalizeDomain(domain);
    this._hostOnly = false;
    return this;
  }

  /** 对齐 hostOnlyDomain(String)：仅当前 host。 */
  hostOnlyDomain(domain: string): CookieBuilder {
    this._domain = CookieBuilder.normalizeDomain(domain);
    this._hostOnly = true;
    return this;
  }

  path(path: string): CookieBuilder {
    this._path = path.length === 0 ? '/' : path;
    return this;
  }

  secure(): CookieBuilder {
    this._secure = true;
    return this;
  }

  httpOnly(): CookieBuilder {
    this._httpOnly = true;
    return this;
  }

  build(): Cookie {
    if (this._name === null) {
      throw new Error('name == null');
    }
    if (this._domain === null) {
      throw new Error('domain == null');
    }
    return new Cookie(this._name, this._value, this._expiresAt, this._domain, this._path,
      this._secure, this._httpOnly, this._persistent, this._hostOnly);
  }

  private static normalizeDomain(domain: string): string {
    let d: string = domain.toLowerCase();
    if (d.startsWith('.')) {
      d = d.substring(1);
    }
    if (d.length === 0) {
      throw new Error('domain is empty');
    }
    return d;
  }
}
