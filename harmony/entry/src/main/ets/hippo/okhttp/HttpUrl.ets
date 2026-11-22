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
 * okhttp3.HttpUrl 等价层（只保留 EkViewer 用到的面 + Cookie 匹配需要的面）。
 *
 * 上游用到的面：
 *   HttpUrl.parse(String)      EhCookieStore.hasSignedIn / CookieRepository
 *   url.host()                 CookieRepository.domainMatch / VerifyAsIpAddress
 *   url.toString()             EhApplication WebView cookie 同步、EhEngine 日志
 *   url.pathSegments()/path()  Cookie 路径匹配（RFC 6265 §5.1.4）
 *   url.scheme()/isHttps()     Cookie secure 判定
 */
export class HttpUrl {
  private _scheme: string;
  private _host: string;
  private _port: number;
  private _encodedPath: string;
  private _encodedQuery: string | null;

  private constructor(scheme: string, host: string, port: number, encodedPath: string,
    encodedQuery: string | null) {
    this._scheme = scheme;
    this._host = host;
    this._port = port;
    this._encodedPath = encodedPath;
    this._encodedQuery = encodedQuery;
  }

  /**
   * 对齐 HttpUrl.parse(String)：非法 URL 返回 null（Java 侧调用方都做 null 判断）。
   * 只接受 http/https，与 OkHttp 的 HttpUrl 契约一致（非 http 协议 OkHttp 也返回 null）。
   */
  static parse(url: string | null | undefined): HttpUrl | null {
    if (url === null || url === undefined) {
      return null;
    }
    const s: string = url.trim();
    const schemeEnd: number = s.indexOf('://');
    if (schemeEnd <= 0) {
      return null;
    }
    const scheme: string = s.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') {
      return null;
    }
    let rest: string = s.substring(schemeEnd + 3);
    // 去掉 #fragment
    const hash: number = rest.indexOf('#');
    if (hash >= 0) {
      rest = rest.substring(0, hash);
    }
    // 切出 authority
    let authorityEnd: number = rest.length;
    for (let i = 0; i < rest.length; i++) {
      const c: string = rest.charAt(i);
      if (c === '/' || c === '?') {
        authorityEnd = i;
        break;
      }
    }
    const authority: string = rest.substring(0, authorityEnd);
    let tail: string = rest.substring(authorityEnd);
    if (tail.length === 0) {
      tail = '/';
    }

    // user:pass@host:port（EkViewer 不用 userinfo，但解析要能吃下去）
    let hostPort: string = authority;
    const at: number = authority.lastIndexOf('@');
    if (at >= 0) {
      hostPort = authority.substring(at + 1);
    }
    let host: string = hostPort;
    let port: number = scheme === 'https' ? 443 : 80;
    if (hostPort.startsWith('[')) {
      // IPv6：解析后去除方括号（对齐 OkHttp HttpUrl.host()）
      const close: number = hostPort.indexOf(']');
      if (close <= 1) {
        return null;
      }
      host = hostPort.substring(1, close);
      if (host.indexOf(':') < 0) {
        return null;
      }
      const after: string = hostPort.substring(close + 1);
      if (after.length > 0) {
        if (!after.startsWith(':')) {
          return null;
        }
        const portStr: string = after.substring(1);
        if (!/^\d+$/.test(portStr)) {
          return null;
        }
        port = Number.parseInt(portStr, 10);
      }
    } else {
      const colon: number = hostPort.lastIndexOf(':');
      if (colon >= 0) {
        if (hostPort.indexOf(':') !== colon) {
          return null;
        }
        host = hostPort.substring(0, colon);
        const portStr: string = hostPort.substring(colon + 1);
        if (!/^\d+$/.test(portStr)) {
          return null;
        }
        port = Number.parseInt(portStr, 10);
      }
    }
    if (host.length === 0 || port < 1 || port > 65535) {
      return null;
    }

    let encodedPath: string = tail;
    let encodedQuery: string | null = null;
    const q: number = tail.indexOf('?');
    if (q >= 0) {
      encodedPath = tail.substring(0, q);
      encodedQuery = tail.substring(q + 1);
    }
    if (encodedPath.length === 0) {
      encodedPath = '/';
    }
    return new HttpUrl(scheme, host.toLowerCase(), port, encodedPath, encodedQuery);
  }

  /** 便捷构造：一定成功，非法输入直接抛错（对应 HttpUrl.get）。 */
  static get(url: string): HttpUrl {
    const u: HttpUrl | null = HttpUrl.parse(url);
    if (u === null) {
      throw new Error(`Invalid URL: ${url}`);
    }
    return u;
  }

  scheme(): string {
    return this._scheme;
  }

  host(): string {
    return this._host;
  }

  port(): number {
    return this._port;
  }

  isHttps(): boolean {
    return this._scheme === 'https';
  }

  /** 对齐 HttpUrl.pathSegments()：RFC 3986 的路径段（已解码）。 */
  pathSegments(): string[] {
    const raw: string = this._encodedPath;
    const segs: string[] = [];
    let start: number = 0;
    for (let i = 0; i < raw.length; i++) {
      if (raw.charAt(i) === '/') {
        if (i > start) {
          segs.push(decodeURIComponentSafe(raw.substring(start, i)));
        }
        start = i + 1;
      }
    }
    if (start < raw.length) {
      segs.push(decodeURIComponentSafe(raw.substring(start)));
    }
    return segs;
  }

  /** 对齐 HttpUrl.encodedPath()。 */
  encodedPath(): string {
    return this._encodedPath;
  }

  /** Cookie 路径匹配使用的解码后路径。 */
  path(): string {
    return decodeURIComponentSafe(this._encodedPath);
  }

  encodedQuery(): string | null {
    return this._encodedQuery;
  }

  query(): string | null {
    return this._encodedQuery;
  }

  /** 对齐 HttpUrl.queryParameter(String)：同名参数取最后一个（OkHttp 行为）。 */
  queryParameter(name: string): string | null {
    if (this._encodedQuery === null) {
      return null;
    }
    const parts: string[] = this._encodedQuery.split('&');
    let result: string | null = null;
    for (let i = 0; i < parts.length; i++) {
      const part: string = parts[i];
      const eq: number = part.indexOf('=');
      const key: string = eq < 0 ? part : part.substring(0, eq);
      if (decodeURIComponentSafe(key.replace(PLUS, ' ')) === name) {
        result = eq < 0 ? '' : decodeURIComponentSafe(part.substring(eq + 1).replace(PLUS, ' '));
      }
    }
    return result;
  }

  queryParameterNames(): string[] {
    const out: string[] = [];
    if (this._encodedQuery === null) {
      return out;
    }
    const parts: string[] = this._encodedQuery.split('&');
    for (let i = 0; i < parts.length; i++) {
      const part: string = parts[i];
      const eq: number = part.indexOf('=');
      const key: string = decodeURIComponentSafe((eq < 0 ? part : part.substring(0, eq)).replace(PLUS, ' '));
      if (out.indexOf(key) === -1) {
        out.push(key);
      }
    }
    return out;
  }

  /** 对齐 HttpUrl.resolve(String link)：相对链接按 RFC 3986 解析。 */
  resolve(link: string | null | undefined): HttpUrl | null {
    if (link === null || link === undefined) {
      return null;
    }
    const s: string = link.trim();
    if (s.length === 0) {
      return null;
    }
    if (s.indexOf('://') > 0) {
      return HttpUrl.parse(s);
    }
    if (s.startsWith('//')) {
      return HttpUrl.parse(this._scheme + ':' + s);
    }
    if (s.startsWith('/')) {
      return HttpUrl.parse(this._scheme + '://' + this.authority() + s);
    }
    if (s.startsWith('?')) {
      return HttpUrl.parse(this._scheme + '://' + this.authority() + this._encodedPath + s);
    }
    // 相对路径：以当前目录为基准
    const base: string = this._encodedPath;
    const slash: number = base.lastIndexOf('/');
    const dir: string = slash < 0 ? '/' : base.substring(0, slash + 1);
    return HttpUrl.parse(this._scheme + '://' + this.authority() + normalizePath(dir + s));
  }

  private authority(): string {
    const defaultPort: number = this._scheme === 'https' ? 443 : 80;
    const hostPart: string = this._host.indexOf(':') >= 0 ? `[${this._host}]` : this._host;
    return this._port === defaultPort ? hostPart : `${hostPart}:${this._port}`;
  }

  newBuilder(): HttpUrlBuilder {
    return new HttpUrlBuilder(this);
  }

  toString(): string {
    let s: string = this._scheme + '://' + this.authority() + this._encodedPath;
    if (this._encodedQuery !== null) {
      s += '?' + this._encodedQuery;
    }
    return s;
  }

  equals(other: HttpUrl): boolean {
    return this.toString() === other.toString();
  }
}

const PLUS: RegExp = /\+/g;

function decodeURIComponentSafe(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch (e) {
    return s;
  }
}

function normalizePath(p: string): string {
  const segs: string[] = p.split('/');
  const out: string[] = [];
  for (let i = 0; i < segs.length; i++) {
    const seg: string = segs[i];
    if (seg === '..') {
      if (out.length > 0) {
        out.pop();
      }
    } else if (seg !== '.' && !(seg.length === 0 && i !== 0 && i !== segs.length - 1)) {
      out.push(seg);
    } else if (seg.length === 0 && i === segs.length - 1) {
      out.push(seg);
    }
  }
  let r: string = out.join('/');
  if (!r.startsWith('/')) {
    r = '/' + r;
  }
  return r;
}

/** okhttp3.HttpUrl.Builder 等价（只暴露 EkViewer 需要的链式方法）。 */
export class HttpUrlBuilder {
  private _scheme: string;
  private _host: string;
  private _port: number;
  private _pathSegments: string[];
  private _queryParams: string[];

  constructor(base: HttpUrl | null) {
    if (base === null) {
      this._scheme = 'https';
      this._host = '';
      this._port = 443;
      this._pathSegments = [];
      this._queryParams = [];
    } else {
      this._scheme = base.scheme();
      this._host = base.host();
      this._port = base.port();
      this._pathSegments = base.pathSegments();
      this._queryParams = [];
      const q: string | null = base.query();
      if (q !== null && q.length > 0) {
        const parts: string[] = q.split('&');
        for (let i = 0; i < parts.length; i++) {
          this._queryParams.push(parts[i]);
        }
      }
    }
  }

  scheme(scheme: string): HttpUrlBuilder {
    this._scheme = scheme.toLowerCase();
    if (this._scheme === 'https' && this._port === 80) {
      this._port = 443;
    } else if (this._scheme === 'http' && this._port === 443) {
      this._port = 80;
    }
    return this;
  }

  host(host: string): HttpUrlBuilder {
    let h: string = host.trim();
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }
    this._host = h.toLowerCase();
    return this;
  }

  port(port: number): HttpUrlBuilder {
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      throw new Error(`unexpected port: ${port}`);
    }
    this._port = port;
    return this;
  }

  addPathSegment(segment: string): HttpUrlBuilder {
    this._pathSegments.push(segment);
    return this;
  }

  setPathSegment(index: number, segment: string): HttpUrlBuilder {
    this._pathSegments[index] = segment;
    return this;
  }

  addQueryParameter(name: string, value: string | null): HttpUrlBuilder {
    const enc: string = encodeURIComponent(name);
    this._queryParams.push(value === null ? enc : `${enc}=${encodeQueryComponent(value)}`);
    return this;
  }

  setQueryParameter(name: string, value: string | null): HttpUrlBuilder {
    this._queryParams = this._queryParams.filter((p: string) => {
      const eq: number = p.indexOf('=');
      const k: string = eq < 0 ? p : p.substring(0, eq);
      return k !== encodeURIComponent(name);
    });
    return this.addQueryParameter(name, value);
  }

  removeAllQueryParameters(name: string): HttpUrlBuilder {
    this._queryParams = this._queryParams.filter((p: string) => {
      const eq: number = p.indexOf('=');
      const k: string = eq < 0 ? p : p.substring(0, eq);
      return k !== encodeURIComponent(name);
    });
    return this;
  }

  build(): HttpUrl {
    let path: string = '';
    for (let i = 0; i < this._pathSegments.length; i++) {
      path += '/' + encodePathSegment(this._pathSegments[i]);
    }
    if (path.length === 0) {
      path = '/';
    }
    const query: string | null = this._queryParams.length === 0 ? null : this._queryParams.join('&');
    const hostPart: string = this._host.indexOf(':') >= 0 ? `[${this._host}]` : this._host;
    const u: HttpUrl | null = HttpUrl.parse(`${this._scheme}://${hostPart}:${this._port}${path}` +
      (query === null ? '' : `?${query}`));
    if (u === null) {
      throw new Error('Invalid URL built');
    }
    return u;
  }
}

/** OkHttp 的 QUERY_COMPONENT_ENCODE_SET：空格编 '%20'，保留 !$&'()*+,;=:@/? 之外字符原样。 */
function encodeQueryComponent(s: string): string {
  return encodeURIComponent(s).replace(/%2C/g, ',').replace(/%3A/g, ':')
    .replace(/%40/g, '@').replace(/%2B/g, '+').replace(/%3D/g, '=');
}

function encodePathSegment(s: string): string {
  return encodeURIComponent(s).replace(/%3A/g, ':').replace(/%40/g, '@')
    .replace(/%26/g, '&').replace(/%3D/g, '=').replace(/%2B/g, '+')
    .replace(/%24/g, '$').replace(/%2C/g, ',');
}
