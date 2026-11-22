/*
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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { CallAbortController, Chain, Interceptor } from './Interceptor';
import { Cookie } from './Cookie';
import { CookieJar } from './CookieJar';
import { Dns, InetAddress, OverrideAwareDns, SYSTEM_DNS, toNetworkError } from './Dns';
import { Headers } from './Headers';
import { HttpUrl } from './HttpUrl';
import { Proxy, ProxySelector, ProxyType } from './ProxySelector';
import { Request } from './Request';
import { Response } from './Response';
import { RequestBody } from './RequestBody';
import { Transport, TransportExecuteOptions, TransportProgressCallback } from './SystemHttpTransport';
import { PoolLike } from './ConnectionPool';

/**
 * OkHttp 内建（非用户可见）拦截器组，顺序与 OkHttp 3.14 的 RealCall.getResponseWithInterceptorChain() 对齐：
 *   用户应用拦截器 → RetryAndFollowUp(本文件 RedirectInterceptor)
 *   → Bridge(CookieInterceptor + 头处理) → CacheInterceptor → Connect(传输层)
 *   → 用户网络拦截器（由 OkHttpClient 组装在 Connect 之内）
 *
 * 之所以要拆成独立的类：EhApplication 的两个 addNetworkInterceptor 依赖
 * 「拿到服务端原始头」的位置，顺序错了 Set-Cookie 同步会失效。
 */

/** 对应 OkHttp 的 RetryAndFollowUpInterceptor：只保留重定向部分（EhViewer 不配置认证挑战）。 */
export class RedirectInterceptor implements Interceptor {
  private readonly _followRedirects: boolean;
  private readonly _followSslRedirects: boolean;
  private readonly _maxFollowUps: number = 20;

  constructor(followRedirects: boolean, followSslRedirects: boolean) {
    this._followRedirects = followRedirects;
    this._followSslRedirects = followSslRedirects;
  }

  async intercept(chain: Chain): Promise<Response> {
    let request: Request = chain.request();
    let response: Response = await chain.proceed(request);
    let followUps: number = 0;

    while (true) {
      if (chain.isCancelled()) {
        response.close();
        throw new Error('Canceled');
      }
      const next: Request | null = this.followUpRequest(request, response);
      if (next === null) {
        return response;
      }
      followUps++;
      if (followUps > this._maxFollowUps) {
        response.close();
        throw new Error(`Too many follow-up requests: ${followUps}`);
      }
      request = next;
      response.close();
      response = await chain.proceed(request);
    }
  }

  /** 对齐 OkHttp 的 followUpRequest：判定是否跟随，并构造下一跳请求。 */
  private followUpRequest(request: Request, response: Response): Request | null {
    const code: number = response.code();
    if (code !== 300 && code !== 301 && code !== 302 && code !== 303 &&
      code !== 307 && code !== 308) {
      return null;
    }
    if (!this._followRedirects) {
      return null;
    }
    const method: string = request.method();
    if ((code === 307 || code === 308) && method !== 'GET' && method !== 'HEAD') {
      return null;
    }
    const location: string | null = response.headers().get('Location');
    if (location === null) {
      return null;
    }
    const url: HttpUrl | null = request.url().resolve(location);
    if (url === null) {
      return null;
    }
    // 跨 scheme 需要 followSslRedirects
    if (!this._followSslRedirects && url.isHttps() !== request.url().isHttps()) {
      return null;
    }
    let nextMethod: string = method;
    if (code !== 307 && code !== 308 && method !== 'GET' && method !== 'HEAD' && method !== 'PROPFIND') {
      nextMethod = 'GET';
    }
    return this.buildRedirectRequest(request, url, nextMethod);
  }

  private buildRedirectRequest(request: Request, url: HttpUrl, method: string): Request {
    const builder: RequestBuilderLike = new RequestBuilderLike(url, request.tag());
    const sameHost: boolean = url.host() === request.url().host();
    const samePort: boolean = url.port() === request.url().port();
    const body: RequestBody | null = method === 'GET' || method === 'HEAD' ? null : request.body();
    const droppingBody: boolean = request.body() !== null && body === null;
    const src: Headers = request.headers();
    for (let i = 0; i < src.size(); i++) {
      const name: string = src.name(i);
      const lower: string = name.toLowerCase();
      if (!sameHost && (lower === 'authorization' || lower === 'cookie' || lower === 'host')) {
        continue;
      }
      if (sameHost && !samePort && lower === 'host') {
        continue;
      }
      if (droppingBody && (lower === 'host' || lower === 'content-length' ||
        lower === 'content-type' || lower === 'transfer-encoding')) {
        continue;
      }
      builder.addHeader(name, src.value(i));
    }
    builder.method(method, body);
    return builder.build();
  }
}

/** RedirectInterceptor 内部用的小包装，避免 import 循环。 */
class RequestBuilderLike {
  private readonly _url: HttpUrl;
  private readonly _tag: string | null;
  private readonly _headers: string[] = [];
  private readonly _values: string[] = [];
  private _method: string = 'GET';
  private _body: RequestBody | null = null;

  constructor(url: HttpUrl, tag: string | null) {
    this._url = url;
    this._tag = tag;
  }

  addHeader(name: string, value: string): void {
    this._headers.push(name);
    this._values.push(value);
  }

  method(method: string, body: RequestBody | null): void {
    this._method = method;
    this._body = body;
  }

  build(): Request {
    const h: Headers = new Headers(this._headers.slice(), this._values.slice());
    return new Request(this._url, this._method, h, this._body, this._tag);
  }
}

/**
 * 对应 OkHttp 的 BridgeInterceptor + CookieInterceptor。
 * 职责：
 *   1) 请求侧：把 CookieJar.loadForRequest(url) 拼成 Cookie 头
 *   2) 响应侧：解析全部 Set-Cookie 交给 CookieJar.saveFromResponse
 * 与 OkHttp 一致，Cookie 处理发生在「网络拦截器之内」，所以用户网络拦截器看到的是
 * 带 Cookie 头的请求与带 Set-Cookie 的原始响应。
 */
export class CookieInterceptor implements Interceptor {
  private readonly _cookieJar: CookieJar;

  constructor(cookieJar: CookieJar) {
    this._cookieJar = cookieJar;
  }

  async intercept(chain: Chain): Promise<Response> {
    let request: Request = chain.request();
    const url: HttpUrl = request.url();

    const cookies: Cookie[] = this._cookieJar.loadForRequest(url);
    if (cookies.length > 0) {
      const sb: string[] = [];
      for (let i = 0; i < cookies.length; i++) {
        if (i > 0) {
          sb.push('; ');
        }
        sb.push(`${cookies[i].name()}=${cookies[i].value()}`);
      }
      request = request.newBuilder().header('Cookie', sb.join('')).build();
    }

    const response: Response = await chain.proceed(request);

    const setCookies: string[] = response.headersOf('Set-Cookie');
    if (setCookies.length > 0) {
      const parsed: Cookie[] = [];
      for (let i = 0; i < setCookies.length; i++) {
        const c: Cookie | null = Cookie.parse(url, setCookies[i]);
        if (c !== null) {
          parsed.push(c);
        }
      }
      if (parsed.length > 0) {
        this._cookieJar.saveFromResponse(url, parsed);
      }
    }
    return response;
  }
}

/** ConnectInterceptor 配置（承载代理/DNS/超时/重试/TLS 策略与取消控制）。 */
export interface ConnectConfig {
  httpTransport: Transport;
  socketTransport: Transport;
  connectTimeoutMs: number;
  readTimeoutMs: number;
  writeTimeoutMs: number;
  callTimeoutMs: number;
  followRedirects: boolean;
  dns: Dns;
  proxySelector: ProxySelector;
  pool: PoolLike;
  sslSocketFactoryInstalled: boolean;
  retryOnConnectionFailure: boolean;
  abort: CallAbortController | null;
  onProgress?: TransportProgressCallback;
}

/** 传输层节点：OkHttp 的 ConnectInterceptor + CallServerInterceptor 合并，负责逐跳选择代理/DNS/传输引擎。 */
export class ConnectInterceptor implements Interceptor {
  private readonly _httpTransport: Transport;
  private readonly _socketTransport: Transport;
  private readonly _connectTimeoutMs: number;
  private readonly _readTimeoutMs: number;
  private readonly _writeTimeoutMs: number;
  private readonly _callTimeoutMs: number;
  private readonly _followRedirects: boolean;
  private readonly _dns: Dns;
  private readonly _proxySelector: ProxySelector;
  private readonly _pool: PoolLike;
  private readonly _sslSocketFactoryInstalled: boolean;
  private readonly _retryOnConnectionFailure: boolean;
  private readonly _abort: CallAbortController | null;
  private readonly _onProgress: TransportProgressCallback | undefined;

  constructor(config: ConnectConfig) {
    this._httpTransport = config.httpTransport;
    this._socketTransport = config.socketTransport;
    this._connectTimeoutMs = config.connectTimeoutMs;
    this._readTimeoutMs = config.readTimeoutMs;
    this._writeTimeoutMs = config.writeTimeoutMs;
    this._callTimeoutMs = config.callTimeoutMs;
    this._followRedirects = config.followRedirects;
    this._dns = config.dns;
    this._proxySelector = config.proxySelector;
    this._pool = config.pool;
    this._sslSocketFactoryInstalled = config.sslSocketFactoryInstalled;
    this._retryOnConnectionFailure = config.retryOnConnectionFailure;
    this._abort = config.abort;
    this._onProgress = config.onProgress;
  }

  async intercept(chain: Chain): Promise<Response> {
    if (chain.isCancelled()) {
      throw new Error('Canceled');
    }
    const request: Request = chain.request();
    const url: HttpUrl = request.url();
    const host: string = url.host();

    let proxies: Proxy[] = this._proxySelector.select(url);
    if (proxies.length === 0) {
      proxies = [Proxy.system()];
    }
    const maxProxyTries: number = this._retryOnConnectionFailure ? proxies.length : 1;

    this._pool.acquire(host);
    try {
      let lastError: Error | null = null;
      for (let pIdx = 0; pIdx < maxProxyTries; pIdx++) {
        if (chain.isCancelled()) {
          throw new Error('Canceled');
        }
        const proxy: Proxy = proxies[pIdx];
        const useCustomDns: boolean = proxy.type() === ProxyType.DIRECT && this._dns !== SYSTEM_DNS;
        let resolvedList: InetAddress[] = [];
        let hasDnsOverride: boolean = false;

        if (useCustomDns) {
          resolvedList = await this._dns.lookup(host);
          if (resolvedList.length === 0) {
            throw new Error(`UnknownHostException: ${host}`);
          }
          const reportsOverride: boolean =
            (this._dns as OverrideAwareDns).reportsOverrideFlag === true;
          hasDnsOverride = reportsOverride
            ? resolvedList.some((a: InetAddress): boolean => a.isHostOverride())
            : true;
        }

        // HTTP/HTTPS 代理优先走 SystemHttpTransport（@ohos.net.http + usingProxy），
        // 避免普通 API/页面/图片请求经由 Http1SocketTransport 触发 currentFd: -1 与响应体截断。
        // 仅在禁用重定向（需拦截 302）、PATCH、SOCKS 代理或自定义 DNS 解析时回退到 socket 传输。
        const useSocket: boolean =
          !this._followRedirects ||
          request.method() === 'PATCH' ||
          proxy.type() === ProxyType.SOCKS ||
          hasDnsOverride;

        const transport: Transport = useSocket ? this._socketTransport : this._httpTransport;
        hilog.info(0x0000, 'ConnectInterceptor',
          'route host=%{public}s proxy=%{public}s dnsCount=%{public}d override=%{public}s transport=%{public}s df=%{public}s',
          host, proxy.toString(), resolvedList.length, String(hasDnsOverride), transport.name,
          String(this._sslSocketFactoryInstalled));
        const candidates: Array<InetAddress | null> = (useSocket && hasDnsOverride && resolvedList.length > 0)
          ? resolvedList : [null];
        const maxAddrTries: number = this._retryOnConnectionFailure ? candidates.length : 1;

        for (let aIdx = 0; aIdx < maxAddrTries; aIdx++) {
          if (chain.isCancelled()) {
            throw new Error('Canceled');
          }
          const addr: InetAddress | null = candidates[aIdx];
          const skipValidation: boolean = this._sslSocketFactoryInstalled ||
            (hasDnsOverride && addr !== null && (addr.isHostOverride() || addr.hostAddress() !== host));
          const execOpts: TransportExecuteOptions = {
            writeTimeoutMs: this._writeTimeoutMs,
            callTimeoutMs: this._callTimeoutMs,
            abort: this._abort,
            proxy: proxy,
            resolvedAddress: addr,
            skipRemoteValidation: skipValidation,
            onProgress: this._onProgress
          };

          const attemptsForSingleAddr: number =
            (this._retryOnConnectionFailure && maxAddrTries === 1 && useSocket) ? 2 : 1;
          for (let retry = 0; retry < attemptsForSingleAddr; retry++) {
            try {
              return await transport.execute(request, this._connectTimeoutMs, this._readTimeoutMs, execOpts);
            } catch (e) {
              const err: Error = toNetworkError(e as Object);
              if (chain.isCancelled() || err.message === 'Canceled' || err.message === 'timeout') {
                throw err;
              }
              hilog.warn(0x0000, 'ConnectInterceptor',
                'attempt failed host=%{public}s transport=%{public}s addr=%{public}s err=%{public}s',
                host, transport.name, addr !== null ? addr.hostAddress() : 'system', err.message);
              lastError = err;
            }
          }
        }
      }
      throw lastError !== null ? lastError : new Error('Connection failed');
    } finally {
      this._pool.release(host);
    }
  }
}



