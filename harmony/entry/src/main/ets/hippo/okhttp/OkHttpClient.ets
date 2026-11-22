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

import { Call, RealCall } from './Call';
import { Cache, CacheInterceptor } from './Cache';
import { ConnectionPool, PoolLike } from './ConnectionPool';
import { CookieJar, NoCookies } from './CookieJar';
import { Dns, SYSTEM_DNS } from './Dns';
import { Http1SocketTransport } from './Http1SocketTransport';
import { ConnectConfig, ConnectInterceptor, CookieInterceptor, RedirectInterceptor } from './InternalInterceptors';
import { CallAbortController, Interceptor, InterceptorEntry } from './Interceptor';
import { ProxySelector } from './ProxySelector';
import { Request } from './Request';
import { SystemHttpTransport, TransportProgressCallback } from './SystemHttpTransport';

/** java.util.concurrent.TimeUnit 的最小等价（EhViewer 只用到 SECONDS/MINUTES）。 */
export enum TimeUnit {
  MILLISECONDS = 1,
  SECONDS = 1000,
  MINUTES = 60000
}

/**
 * okhttp3.OkHttpClient 等价层。
 *
 * 上游构造点（EhApplication.getOkHttpClient / getImageOkHttpClient）用到的 Builder 方法
 * 全部覆盖，签名保持一致（除 TimeUnit 换成本层的枚举）：
 *   followRedirects / followSslRedirects / connectTimeout / readTimeout / writeTimeout /
 *   callTimeout / connectionPool / retryOnConnectionFailure / cookieJar / cache / dns /
 *   addInterceptor / addNetworkInterceptor / proxySelector / connectionSpecs / sslSocketFactory
 *
 * 无法等价的两项（已登记 MR，不在本层伪造成功）：
 *   connectionSpecs(List<ConnectionSpec>) —— TLS 套件由系统栈决定，本层只记录
 *   sslSocketFactory(SSLSocketFactory, X509TrustManager) —— 见 DEVIATIONS D-005（Conscrypt 移除）；
 *     本层同样只记录（EhSSLSocketFactory/EhX509TrustManager 在 network/ 里保留类名做空实现，
 *     由 Lead 决定是否需要 socket 引擎的 ca 注入实现真校验）
 */
export class OkHttpClient {
  private readonly _followRedirects: boolean;
  private readonly _followSslRedirects: boolean;
  private readonly _connectTimeoutMs: number;
  private readonly _readTimeoutMs: number;
  private readonly _writeTimeoutMs: number;
  private readonly _callTimeoutMs: number;
  private readonly _retryOnConnectionFailure: boolean;
  private readonly _cookieJar: CookieJar;
  private readonly _cache: Cache | null;
  private readonly _dns: Dns;
  private readonly _interceptors: Interceptor[];
  private readonly _networkInterceptors: Interceptor[];
  private readonly _proxySelector: ProxySelector;
  private readonly _connectionPool: ConnectionPool;
  private readonly _connectionSpecsInstalled: boolean;
  private readonly _sslSocketFactoryInstalled: boolean;
  private _httpTransport: SystemHttpTransport | null = null;
  private _socketTransport: Http1SocketTransport | null = null;

  constructor(builder: OkHttpClientBuilder) {
    this._followRedirects = builder.followRedirectsValue();
    this._followSslRedirects = builder.followSslRedirectsValue();
    this._connectTimeoutMs = builder.connectTimeoutMs();
    this._readTimeoutMs = builder.readTimeoutMs();
    this._writeTimeoutMs = builder.writeTimeoutMs();
    this._callTimeoutMs = builder.callTimeoutMs();
    this._retryOnConnectionFailure = builder.retryOnConnectionFailureValue();
    this._cookieJar = builder.cookieJarValue();
    this._cache = builder.cacheValue();
    this._dns = builder.dnsValue();
    this._interceptors = builder.interceptorsValue().slice();
    this._networkInterceptors = builder.networkInterceptorsValue().slice();
    this._proxySelector = builder.proxySelectorValue();
    this._connectionPool = builder.connectionPoolValue();
    this._connectionSpecsInstalled = builder.connectionSpecsInstalled();
    this._sslSocketFactoryInstalled = builder.sslSocketFactoryInstalled();
  }

  static newBuilder(): OkHttpClientBuilder {
    return new OkHttpClientBuilder();
  }

  /** 默认客户端，等价 `new OkHttpClient()`。 */
  static default(): OkHttpClient {
    return new OkHttpClientBuilder().build();
  }

  /** 对齐 newCall(Request)，支持可选字节下载进度回调。 */
  newCall(request: Request, onProgress?: TransportProgressCallback): Call {
    const abort: CallAbortController = new CallAbortController();
    const factory = (ab: CallAbortController): InterceptorEntry[] => this.buildEntries(ab, onProgress);
    const entries: InterceptorEntry[] = factory(abort);
    return new RealCall(request, entries, null, abort, this._callTimeoutMs, factory);
  }

  private buildEntries(abort: CallAbortController, onProgress?: TransportProgressCallback): InterceptorEntry[] {
    const entries: InterceptorEntry[] = [];
    let index: number = 0;

    // 1) 应用拦截器
    for (let i = 0; i < this._interceptors.length; i++) {
      entries.push(new InterceptorEntry(this._interceptors[i], index++));
    }
    // 2) 重定向
    entries.push(new InterceptorEntry(
      new RedirectInterceptor(this._followRedirects, this._followSslRedirects), index++));
    // 3) Cookie（OkHttp 的 BridgeInterceptor 阶段）
    entries.push(new InterceptorEntry(new CookieInterceptor(this._cookieJar), index++));
    // 4) 缓存
    if (this._cache !== null) {
      entries.push(new InterceptorEntry(new CacheInterceptor(this._cache as Cache), index++));
    }
    // 5) 网络拦截器（在缓存之后、传输之前，与 OkHttp 的顺序一致）
    for (let i = 0; i < this._networkInterceptors.length; i++) {
      entries.push(new InterceptorEntry(this._networkInterceptors[i], index++));
    }
    // 6) 传输（最后一跳：在运行时逐跳判定系统栈 / socket 引擎）
    const pool: PoolLike = this._connectionPool;
    const connectCfg: ConnectConfig = {
      httpTransport: this.getHttpTransport(),
      socketTransport: this.getSocketTransport(),
      connectTimeoutMs: this._connectTimeoutMs,
      readTimeoutMs: this._readTimeoutMs,
      writeTimeoutMs: this._writeTimeoutMs,
      callTimeoutMs: this._callTimeoutMs,
      followRedirects: this._followRedirects,
      dns: this._dns,
      proxySelector: this._proxySelector,
      pool: pool,
      sslSocketFactoryInstalled: this._sslSocketFactoryInstalled,
      retryOnConnectionFailure: this._retryOnConnectionFailure,
      abort: abort,
      onProgress: onProgress
    };
    entries.push(new InterceptorEntry(new ConnectInterceptor(connectCfg), index++));
    return entries;
  }

  private getHttpTransport(): SystemHttpTransport {
    if (this._httpTransport === null) {
      this._httpTransport = new SystemHttpTransport();
    }
    return this._httpTransport as SystemHttpTransport;
  }

  private getSocketTransport(): Http1SocketTransport {
    if (this._socketTransport === null) {
      this._socketTransport = new Http1SocketTransport(this._connectionPool);
    }
    return this._socketTransport as Http1SocketTransport;
  }

  followRedirects(): boolean {
    return this._followRedirects;
  }

  followSslRedirects(): boolean {
    return this._followSslRedirects;
  }

  connectTimeoutMs(): number {
    return this._connectTimeoutMs;
  }

  readTimeoutMs(): number {
    return this._readTimeoutMs;
  }

  writeTimeoutMs(): number {
    return this._writeTimeoutMs;
  }

  callTimeoutMs(): number {
    return this._callTimeoutMs;
  }

  retryOnConnectionFailure(): boolean {
    return this._retryOnConnectionFailure;
  }

  cookieJar(): CookieJar {
    return this._cookieJar;
  }

  cache(): Cache | null {
    return this._cache;
  }

  dns(): Dns {
    return this._dns;
  }

  proxySelector(): ProxySelector {
    return this._proxySelector;
  }

  connectionPool(): ConnectionPool {
    return this._connectionPool;
  }

  connectionSpecsInstalled(): boolean {
    return this._connectionSpecsInstalled;
  }

  sslSocketFactoryInstalled(): boolean {
    return this._sslSocketFactoryInstalled;
  }

  /** 对齐 OkHttpClient.close()：释放连接与 sockets。 */
  close(): void {
    if (this._socketTransport !== null) {
      (this._socketTransport as Http1SocketTransport).closeAll();
    }
    this._connectionPool.evictAll();
  }

  newBuilder(): OkHttpClientBuilder {
    const b: OkHttpClientBuilder = new OkHttpClientBuilder();
    b.setFollowRedirects(this._followRedirects);
    b.setFollowSslRedirects(this._followSslRedirects);
    b.setConnectTimeoutMs(this._connectTimeoutMs);
    b.setReadTimeoutMs(this._readTimeoutMs);
    b.setWriteTimeoutMs(this._writeTimeoutMs);
    b.setCallTimeoutMs(this._callTimeoutMs);
    b.setRetryOnConnectionFailure(this._retryOnConnectionFailure);
    b.setCookieJar(this._cookieJar);
    b.setCache(this._cache);
    b.setDns(this._dns);
    b.setInterceptors(this._interceptors.slice());
    b.setNetworkInterceptors(this._networkInterceptors.slice());
    b.setProxySelector(this._proxySelector);
    b.setConnectionPool(this._connectionPool);
    b.setConnectionSpecsInstalled(this._connectionSpecsInstalled);
    b.setSslSocketFactoryInstalled(this._sslSocketFactoryInstalled);
    return b;
  }

  /** 只读诊断信息，便于 MR 的金样本与运行期日志判断实际走了哪条引擎。 */
  describe(): string {
    return `OkHttpClient{followRedirects=${this._followRedirects}, ` +
      `followSslRedirects=${this._followSslRedirects}, connectTimeout=${this._connectTimeoutMs}ms, ` +
      `readTimeout=${this._readTimeoutMs}ms, cookieJar=${this._cookieJar.constructor.name}, ` +
      `cache=${this._cache === null ? 'none' : (this._cache as Cache).directory()}, ` +
      `appInterceptors=${this._interceptors.length}, networkInterceptors=${this._networkInterceptors.length}}`;
  }
}

/** okhttp3.OkHttpClient.Builder 等价。 */
export class OkHttpClientBuilder {
  private _followRedirects: boolean = true;
  private _followSslRedirects: boolean = true;
  private _connectTimeoutMs: number = 10000;
  private _readTimeoutMs: number = 10000;
  private _writeTimeoutMs: number = 10000;
  private _callTimeoutMs: number = 0;
  private _retryOnConnectionFailure: boolean = true;
  private _cookieJar: CookieJar = new NoCookies();
  private _cache: Cache | null = null;
  private _dns: Dns = SYSTEM_DNS;
  private _interceptors: Interceptor[] = [];
  private _networkInterceptors: Interceptor[] = [];
  private _proxySelector: ProxySelector = ProxySelector.getDefault();
  private _connectionPool: ConnectionPool = new ConnectionPool(5, 5);
  private _connectionSpecsInstalled: boolean = false;
  private _sslSocketFactoryInstalled: boolean = false;

  followRedirects(followRedirects: boolean): OkHttpClientBuilder {
    this._followRedirects = followRedirects;
    return this;
  }

  followSslRedirects(followSslRedirects: boolean): OkHttpClientBuilder {
    this._followSslRedirects = followSslRedirects;
    return this;
  }

  /** 对齐 connectTimeout(long, TimeUnit)。 */
  connectTimeout(timeout: number, unit: TimeUnit): OkHttpClientBuilder {
    this._connectTimeoutMs = timeout * unit;
    return this;
  }

  readTimeout(timeout: number, unit: TimeUnit): OkHttpClientBuilder {
    this._readTimeoutMs = timeout * unit;
    return this;
  }

  writeTimeout(timeout: number, unit: TimeUnit): OkHttpClientBuilder {
    this._writeTimeoutMs = timeout * unit;
    return this;
  }

  callTimeout(timeout: number, unit: TimeUnit): OkHttpClientBuilder {
    this._callTimeoutMs = timeout * unit;
    return this;
  }

  retryOnConnectionFailure(retry: boolean): OkHttpClientBuilder {
    this._retryOnConnectionFailure = retry;
    return this;
  }

  connectionPool(pool: ConnectionPool): OkHttpClientBuilder {
    this._connectionPool = pool;
    return this;
  }

  cookieJar(cookieJar: CookieJar): OkHttpClientBuilder {
    this._cookieJar = cookieJar;
    return this;
  }

  cache(cache: Cache | null): OkHttpClientBuilder {
    this._cache = cache;
    return this;
  }

  dns(dns: Dns): OkHttpClientBuilder {
    this._dns = dns;
    return this;
  }

  addInterceptor(interceptor: Interceptor): OkHttpClientBuilder {
    this._interceptors.push(interceptor);
    return this;
  }

  addNetworkInterceptor(interceptor: Interceptor): OkHttpClientBuilder {
    this._networkInterceptors.push(interceptor);
    return this;
  }

  proxySelector(selector: ProxySelector): OkHttpClientBuilder {
    this._proxySelector = selector;
    return this;
  }

  /** 记录型：TLS 套件由系统栈决定，见类头注释。 */
  connectionSpecs(specs: string[]): OkHttpClientBuilder {
    this._connectionSpecsInstalled = specs.length > 0;
    return this;
  }

  /** 记录型：见 DEVIATIONS D-005。 */
  sslSocketFactory(installed: boolean): OkHttpClientBuilder {
    this._sslSocketFactoryInstalled = installed;
    return this;
  }

  build(): OkHttpClient {
    return new OkHttpClient(this);
  }

  // ---- 供 OkHttpClient 读取的内部访问器（ArkTS 无包级可见性，用方法代替） ----
  followRedirectsValue(): boolean {
    return this._followRedirects;
  }

  followSslRedirectsValue(): boolean {
    return this._followSslRedirects;
  }

  connectTimeoutMs(): number {
    return this._connectTimeoutMs;
  }

  readTimeoutMs(): number {
    return this._readTimeoutMs;
  }

  writeTimeoutMs(): number {
    return this._writeTimeoutMs;
  }

  callTimeoutMs(): number {
    return this._callTimeoutMs;
  }

  retryOnConnectionFailureValue(): boolean {
    return this._retryOnConnectionFailure;
  }

  cookieJarValue(): CookieJar {
    return this._cookieJar;
  }

  cacheValue(): Cache | null {
    return this._cache;
  }

  dnsValue(): Dns {
    return this._dns;
  }

  interceptorsValue(): Interceptor[] {
    return this._interceptors;
  }

  networkInterceptorsValue(): Interceptor[] {
    return this._networkInterceptors;
  }

  proxySelectorValue(): ProxySelector {
    return this._proxySelector;
  }

  connectionPoolValue(): ConnectionPool {
    return this._connectionPool;
  }

  connectionSpecsInstalled(): boolean {
    return this._connectionSpecsInstalled;
  }

  sslSocketFactoryInstalled(): boolean {
    return this._sslSocketFactoryInstalled;
  }

  setFollowRedirects(v: boolean): void {
    this._followRedirects = v;
  }

  setFollowSslRedirects(v: boolean): void {
    this._followSslRedirects = v;
  }

  setConnectTimeoutMs(v: number): void {
    this._connectTimeoutMs = v;
  }

  setReadTimeoutMs(v: number): void {
    this._readTimeoutMs = v;
  }

  setWriteTimeoutMs(v: number): void {
    this._writeTimeoutMs = v;
  }

  setCallTimeoutMs(v: number): void {
    this._callTimeoutMs = v;
  }

  setRetryOnConnectionFailure(v: boolean): void {
    this._retryOnConnectionFailure = v;
  }

  setCookieJar(v: CookieJar): void {
    this._cookieJar = v;
  }

  setCache(v: Cache | null): void {
    this._cache = v;
  }

  setDns(v: Dns): void {
    this._dns = v;
  }

  setInterceptors(v: Interceptor[]): void {
    this._interceptors = v;
  }

  setNetworkInterceptors(v: Interceptor[]): void {
    this._networkInterceptors = v;
  }

  setProxySelector(v: ProxySelector): void {
    this._proxySelector = v;
  }

  setConnectionPool(v: ConnectionPool): void {
    this._connectionPool = v;
  }

  setConnectionSpecsInstalled(v: boolean): void {
    this._connectionSpecsInstalled = v;
  }

  setSslSocketFactoryInstalled(v: boolean): void {
    this._sslSocketFactoryInstalled = v;
  }
}
