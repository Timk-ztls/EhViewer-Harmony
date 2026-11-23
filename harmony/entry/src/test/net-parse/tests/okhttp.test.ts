/*
 * OkHttp / Transport / Cache / DNS / Redirect / Cookie RFC / PageImageDownloader 单测
 */

import { Cookie, CookieBuilder } from '../../../okhttp/Cookie';
import { HttpUrl } from '../../../okhttp/HttpUrl';
import { Headers, HeadersBuilder } from '../../../okhttp/Headers';
import { FormBody, FormBodyBuilder } from '../../../okhttp/FormBody';
import { MultipartBody, MultipartBodyBuilder } from '../../../okhttp/MultipartBody';
import { MediaType } from '../../../okhttp/MediaType';
import { Request, RequestBuilder } from '../../../okhttp/Request';
import { RequestBody } from '../../../okhttp/RequestBody';
import { Protocol, Response, ResponseBuilder } from '../../../okhttp/Response';
import { ResponseBody } from '../../../okhttp/ResponseBody';
import { Cache, CacheInterceptor } from '../../../okhttp/Cache';
import { ConnectInterceptor, RedirectInterceptor } from '../../../okhttp/InternalInterceptors';
import {
  CallAbortController, Chain, Interceptor, InterceptorEntry, LambdaInterceptor, RealInterceptorChain
} from '../../../okhttp/Interceptor';
import { Http1SocketTransport } from '../../../okhttp/Http1SocketTransport';
import { SystemHttpTransport, TransportExecuteOptions } from '../../../okhttp/SystemHttpTransport';
import { CloseableSocket, ConnectionPool } from '../../../okhttp/ConnectionPool';
import { Proxy, ProxySelector, ProxyType, SystemProxyHelper } from '../../../okhttp/ProxySelector';
import { Dns, InetAddress, OverrideAwareDns, describeNetworkError, toNetworkError } from '../../../okhttp/Dns';
import { OkHttpClient, OkHttpClientBuilder, TimeUnit } from '../../../okhttp/OkHttpClient';
import { PageImageDownloaderImpl } from '../../../okhttp/PageImageDownloaderImpl';
import { CookieRepository } from '../../../network/CookieRepository';
import { InMemoryCookieStore } from '../../../network/CookieDatabase';
import { ByteSink } from '../../../streampipe/OutputStreamPipe';
import { AsyncHostsProvider, EhHostsConfig, HttpDohResolver, OkHttpEhHosts } from '../EhHosts';

declare function require(name: string): any;
declare const process: { exitCode: number };

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

function throws(name: string, fn: () => void): void {
  let caught = false;
  try {
    fn();
  } catch (e) {
    caught = true;
  }
  ok(name, caught);
}

function strToBytes(s: string): ArrayBuffer {
  const arr = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    arr[i] = s.charCodeAt(i) & 0xff;
  }
  return arr.buffer as ArrayBuffer;
}

function bytesToStr(buf: ArrayBuffer): string {
  const u8 = new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < u8.byteLength; i++) {
    s += String.fromCharCode(u8[i]);
  }
  return s;
}

class MemorySink implements ByteSink {
  readonly chunks: Uint8Array[] = [];
  closed: boolean = false;

  write(data: ArrayBuffer): void {
    this.chunks.push(new Uint8Array(data));
  }

  close(): void {
    this.closed = true;
  }

  asText(): string {
    let total = 0;
    for (let i = 0; i < this.chunks.length; i++) {
      total += this.chunks[i].byteLength;
    }
    const merged = new Uint8Array(total);
    let off = 0;
    for (let i = 0; i < this.chunks.length; i++) {
      merged.set(this.chunks[i], off);
      off += this.chunks[i].byteLength;
    }
    return bytesToStr(merged.buffer as ArrayBuffer);
  }
}

// ============================================================================
// 1. Cookie.parse (RFC 6265)
// ============================================================================
function testCookieParsing(): void {
  const url = HttpUrl.parse('https://e-hentai.org/g/12345/abcdef') as HttpUrl;

  // Max-Age 优先于 Expires（无论属性顺序如何）
  const c1 = Cookie.parse(url, 'a=1; Max-Age=60; Expires=Thu, 01 Jan 1970 00:00:00 GMT') as Cookie;
  const c2 = Cookie.parse(url, 'a=1; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=60') as Cookie;
  ok('Max-Age 在 Expires 前：优先 Max-Age 不被覆盖', c1 !== null && c1.expiresAt() > Date.now() + 30000);
  ok('Expires 在 Max-Age 前：同样采用 Max-Age', c2 !== null && c2.expiresAt() > Date.now() + 30000);

  // Max-Age 严格整数校验
  const badMaxAge = Cookie.parse(url, 'a=1; Max-Age=12abc') as Cookie;
  ok('非法 Max-Age 12abc 被忽略，回落为 session cookie', badMaxAge !== null && !badMaxAge.persistent());

  // Max-Age <= 0 与 Expires=1970：MIN_SAFE_INTEGER + persistent=true，可在 CookieRepository 中删除已有持久化 cookie
  const del1 = Cookie.parse(url, 'sid=gone; Max-Age=0') as Cookie;
  const del2 = Cookie.parse(url, 'sid=gone; Max-Age=-5') as Cookie;
  const del3 = Cookie.parse(url, 'sid=gone; Expires=Thu, 01 Jan 1970 00:00:00 GMT') as Cookie;
  eq('Max-Age=0 expiresAt=MIN_SAFE_INTEGER', del1.expiresAt(), Number.MIN_SAFE_INTEGER);
  ok('Max-Age=0 persistent=true', del1.persistent());
  eq('Max-Age=-5 expiresAt=MIN_SAFE_INTEGER', del2.expiresAt(), Number.MIN_SAFE_INTEGER);
  eq('Expires=1970 expiresAt=MIN_SAFE_INTEGER', del3.expiresAt(), Number.MIN_SAFE_INTEGER);
  ok('Expires=1970 persistent=true', del3.persistent());

  const store = new InMemoryCookieStore();
  const repo = new CookieRepository(store);
  const existing = new CookieBuilder()
    .name('sid').value('alive').domain('e-hentai.org').path('/g').expiresAt(Date.now() + 600000).build();
  repo.addCookie(existing);
  eq('删前库中有 1 条', store.rowCount(), 1);
  const delAtPath = Cookie.parse(url, 'sid=; Max-Age=0; Path=/g') as Cookie;
  repo.addCookie(delAtPath);
  eq('Max-Age=0 删除 cookie 后库清空', store.rowCount(), 0);
  eq('删后 getCookies 返回 0', repo.getCookies(url).length, 0);

  // Domain 小写化 & 拒绝空 Domain=
  const upperDom = Cookie.parse(url, 'd=v; Domain=.E-HENTAI.ORG') as Cookie;
  eq('Domain 小写化并剥离前导点', upperDom.domain(), 'e-hentai.org');
  eq('hostOnly=false', upperDom.hostOnly(), false);
  const emptyDom = Cookie.parse(url, 'd=v; Domain=');
  eq('Domain= 空值应拒绝 Set-Cookie', emptyDom, null);
  const mismatchDom = Cookie.parse(url, 'd=v; Domain=other.com');
  eq('不匹配请求域名拒绝', mismatchDom, null);

  // RFC 6265 §5.1.4 默认 path 推导与 matches 校验
  const cSub = Cookie.parse(HttpUrl.parse('https://e-hentai.org/g/12345/abcdef') as HttpUrl, 'p=1') as Cookie;
  eq('默认 path 推导自 encodedPath (/g/12345)', cSub.path(), '/g/12345');
  const cRoot = Cookie.parse(HttpUrl.parse('https://e-hentai.org/login') as HttpUrl, 'p=1') as Cookie;
  eq('顶层文件默认 path 为 /', cRoot.path(), '/');
  ok('matches 使用 encodedPath (/g/12345/xyz 命中)',
    cSub.matches(HttpUrl.parse('https://e-hentai.org/g/12345/xyz') as HttpUrl));
  ok('matches 前缀边界检查 (/g/123450 不命中)',
    !cSub.matches(HttpUrl.parse('https://e-hentai.org/g/123450') as HttpUrl));
}

// ============================================================================
// 2. HttpUrl IPv6 + 端口 + Headers.set + Request.newBuilder + Body caching
// ============================================================================
function testHttpBasics(): void {
  // HttpUrl IPv6 & port
  const v6 = HttpUrl.parse('http://[2001:db8::1]:8080/test') as HttpUrl;
  eq('HttpUrl.host() 剥离 IPv6 方括号', v6.host(), '2001:db8::1');
  eq('HttpUrl.port()', v6.port(), 8080);
  eq('HttpUrl.toString() 重新包方括号', v6.toString(), 'http://[2001:db8::1]:8080/test');
  const v6Built = HttpUrl.get('http://example.com').newBuilder().host('::1').port(9090).build();
  eq('HttpUrlBuilder IPv6 自动加方括号', v6Built.toString(), 'http://[::1]:9090/');

  eq('端口 0 非法', HttpUrl.parse('http://example.com:0/a'), null);
  eq('端口 65536 非法', HttpUrl.parse('http://example.com:65536/a'), null);
  eq('非纯数字端口非法', HttpUrl.parse('http://example.com:80abc/a'), null);

  // Headers.set 校验与全量去重
  const hb = new HeadersBuilder();
  hb.add('X-Test', 'one').add('x-test', 'two');
  hb.set('X-Test', 'final');
  eq('HeadersBuilder.set 覆盖全部旧同名值', hb.build().values('X-Test'), ['final']);
  throws('HeadersBuilder.set 拒绝 CR/LF 注入', () => {
    new HeadersBuilder().set('X-Test', 'a\r\nb');
  });
  throws('Headers.ofMap 拒绝空头名', () => {
    const m = new Map<string, string>();
    m.set('', 'v');
    Headers.ofMap(m);
  });

  // FormBody & MultipartBody 单次序列化缓存 + Request.newBuilder 保留 tag
  const fb = new FormBodyBuilder().add('k', 'v w').build();
  const b1 = fb.bytes();
  const b2 = fb.bytes();
  ok('FormBody.bytes() 返回缓存实例', b1 === b2);
  eq('FormBody contentLength 与字节一致', fb.contentLength(), b1.byteLength);

  const mb = new MultipartBodyBuilder().setBoundary('bnd').addFormDataPart('a', 'b').build();
  const m1 = mb.bytes();
  const m2 = mb.bytes();
  ok('MultipartBody.bytes() 返回缓存实例', m1 === m2);

  const req = new RequestBuilder().url('https://e-hentai.org/').tag('my-tag').build();
  const req2 = req.newBuilder().addHeader('X-A', '1').build();
  eq('Request.newBuilder() 保留 _tag', req2.tag(), 'my-tag');
}

// ============================================================================
// 3. RedirectInterceptor
// ============================================================================
async function testRedirectInterceptor(): Promise<void> {
  const mkChain = (req: Request, responder: (r: Request) => Response): Chain => {
    const entry = new InterceptorEntry(new LambdaInterceptor(async (c: Chain): Promise<Response> => {
      return responder(c.request());
    }), 0);
    return new RealInterceptorChain([entry], 0, req);
  };

  // followRedirects=false 不跟随 302
  const rNoFollow = new RedirectInterceptor(false, false);
  const req0 = new RequestBuilder().url('https://e-hentai.org/start').build();
  const resp0 = await rNoFollow.intercept(mkChain(req0, (r: Request): Response => {
    return new Response(r, Protocol.HTTP_1_1, 302, 'Found',
      Headers.of('Location', '/next'), ResponseBody.empty());
  }));
  eq('followRedirects=false 直接返回 302', resp0.code(), 302);

  // followSslRedirects=false 拒绝 https -> http 降级重定向
  const rNoSsl = new RedirectInterceptor(true, false);
  const reqHttps = new RequestBuilder().url('https://e-hentai.org/start').build();
  const respSsl = await rNoSsl.intercept(mkChain(reqHttps, (r: Request): Response => {
    return new Response(r, Protocol.HTTP_1_1, 302, 'Found',
      Headers.of('Location', 'http://e-hentai.org/downgraded'), ResponseBody.empty());
  }));
  eq('followSslRedirects=false 阻止跨 scheme 跳转', respSsl.code(), 302);

  // GET 307 应跟随，POST 307 不跟随
  const rFollow = new RedirectInterceptor(true, true);
  let hops = 0;
  const resp307Get = await rFollow.intercept(mkChain(reqHttps, (r: Request): Response => {
    hops++;
    if (r.url().toString() === 'https://e-hentai.org/start') {
      return new Response(r, Protocol.HTTP_1_1, 307, 'Temporary Redirect',
        Headers.of('Location', 'https://e-hentai.org/final'), ResponseBody.empty());
    }
    return new Response(r, Protocol.HTTP_1_1, 200, 'OK', new Headers([], []), ResponseBody.empty());
  }));
  eq('GET 307 正常跟随到 200', resp307Get.code(), 200);
  eq('GET 307 共请求 2 次', hops, 2);

  const reqPost = new RequestBuilder().url('https://e-hentai.org/submit')
    .post(RequestBody.create(null, 'payload')).build();
  const resp307Post = await rFollow.intercept(mkChain(reqPost, (r: Request): Response => {
    return new Response(r, Protocol.HTTP_1_1, 307, 'Temporary Redirect',
      Headers.of('Location', 'https://e-hentai.org/other'), ResponseBody.empty());
  }));
  eq('POST 307 不自动重定向', resp307Post.code(), 307);

  // 302 POST->GET 且跨 host 时剥离 Host/Content-*/Cookie/Authorization
  const reqPostAuth = new RequestBuilder()
    .url('https://a.example.com/post')
    .addHeader('Host', 'a.example.com')
    .addHeader('Cookie', 'secret=1')
    .addHeader('Authorization', 'Bearer xyz')
    .addHeader('Content-Length', '7')
    .addHeader('Content-Type', 'text/plain')
    .addHeader('Transfer-Encoding', 'chunked')
    .post(RequestBody.create(null, 'payload'))
    .build();
  let seenSecond: Request | null = null;
  const respCross = await rFollow.intercept(mkChain(reqPostAuth, (r: Request): Response => {
    if (r.url().host() === 'a.example.com') {
      return new Response(r, Protocol.HTTP_1_1, 302, 'Found',
        Headers.of('Location', 'https://b.example.com/dest'), ResponseBody.empty());
    }
    seenSecond = r;
    return new Response(r, Protocol.HTTP_1_1, 200, 'OK', new Headers([], []), ResponseBody.empty());
  }));
  eq('302 跨站跟随到 200', respCross.code(), 200);
  ok('下一跳存在', seenSecond !== null);
  const nextReq = seenSecond as unknown as Request;
  eq('POST 302 变 GET', nextReq.method(), 'GET');
  eq('POST 302 丢弃 body', nextReq.body(), null);
  eq('跨 host 剥离 Host', nextReq.header('Host'), null);
  eq('跨 host 剥离 Cookie', nextReq.header('Cookie'), null);
  eq('跨 host 剥离 Authorization', nextReq.header('Authorization'), null);
  eq('丢 body 剥离 Content-Length', nextReq.header('Content-Length'), null);
  eq('丢 body 剥离 Content-Type', nextReq.header('Content-Type'), null);
  eq('丢 body 剥离 Transfer-Encoding', nextReq.header('Transfer-Encoding'), null);
}

// ============================================================================
// 4. Cache & CacheInterceptor
// ============================================================================
async function testCacheInterceptor(): Promise<void> {
  const os = require('os');
  const path = require('path');
  const fs = require('fs');
  const dir: string = path.join(os.tmpdir(), 'okhttp-cache-test-' + Date.now() + '-' + Math.floor(Math.random() * 10000));

  try {
    const cache = new Cache(dir, 1024);
    const url = 'https://e-hentai.org/cache-item';
    let networkCalls = 0;

    let nextServerResp: ((req: Request) => Response) | null = null;
    const runWithCache = async (req: Request): Promise<Response> => {
      const entries: InterceptorEntry[] = [
        new InterceptorEntry(new CacheInterceptor(cache), 0),
        new InterceptorEntry(new LambdaInterceptor(async (c: Chain): Promise<Response> => {
          networkCalls++;
          return (nextServerResp as (r: Request) => Response)(c.request());
        }), 1)
      ];
      return new RealInterceptorChain(entries, 0, req).proceed(req);
    };

    // 1) 首跳回源并写缓存（带引号的 max-age="60" + ETag）
    nextServerResp = (r: Request): Response => {
      return new Response(r, Protocol.HTTP_1_1, 200, 'OK',
        Headers.of('Cache-Control', 'public, max-age="60"', 'ETag', '"v1"', 'X-Old', 'a'),
        new ResponseBody(null, strToBytes('cached-body')));
    };
    const r1 = await runWithCache(new RequestBuilder().url(url).build());
    eq('首跳 status=200', r1.code(), 200);
    eq('首跳 cacheResponse=null', r1.cacheResponse(), null);

    // 2) 二跳命中缓存，不打网络，cacheResponse 非空
    const r2 = await runWithCache(new RequestBuilder().url(url).build());
    eq('二跳仍为 1 次网络请求', networkCalls, 1);
    ok('二跳设置 cacheResponse()', r2.cacheResponse() !== null);
    eq('二跳命中缓存体', r2.body()?.string(), 'cached-body');

    // 3) 强制 revalidation (no-cache) → 304 合并，network 被关闭且头覆盖不重复
    let closedNetwork304 = false;
    nextServerResp = (r: Request): Response => {
      const rb = new ResponseBody(null, new ArrayBuffer(0));
      const origClose = rb.close.bind(rb);
      rb.close = (): void => { closedNetwork304 = true; origClose(); };
      return new Response(r, Protocol.HTTP_1_1, 304, 'Not Modified',
        Headers.of('Cache-Control', 'max-age=120', 'X-Old', 'b', 'Set-Cookie', 'a=1'), rb);
    };
    const r3 = await runWithCache(new RequestBuilder().url(url).addHeader('Cache-Control', 'no-cache').build());
    eq('304 发起第 2 次网络请求', networkCalls, 2);
    eq('304 返回 200 合并响应', r3.code(), 200);
    ok('304 调用 network.close()', closedNetwork304);
    eq('304 合并后 X-Old 覆盖为单个 b', r3.headersOf('X-Old'), ['b']);
    eq('304 保留缓存体', r3.body()?.string(), 'cached-body');

    // 4) POST 触发缓存失效
    nextServerResp = (r: Request): Response => {
      return new Response(r, Protocol.HTTP_1_1, 200, 'OK', new Headers([], []), new ResponseBody(null, strToBytes('posted')));
    };
    await runWithCache(new RequestBuilder().url(url).post(RequestBody.create(null, 'x')).build());
    eq('POST 清除条目后缓存失效', cache.readEntry(new RequestBuilder().url(url).build()), null);

    // 5) no-store 不落盘，超大体 (> maxSize) 不落盘
    const urlNoStore = 'https://e-hentai.org/no-store';
    nextServerResp = (r: Request): Response => {
      return new Response(r, Protocol.HTTP_1_1, 200, 'OK',
        Headers.of('Cache-Control', 'no-store, max-age=60'), new ResponseBody(null, strToBytes('secret')));
    };
    await runWithCache(new RequestBuilder().url(urlNoStore).build());
    eq('no-store 不缓存', cache.readEntry(new RequestBuilder().url(urlNoStore).build()), null);

    const urlBig = 'https://e-hentai.org/too-big';
    nextServerResp = (r: Request): Response => {
      return new Response(r, Protocol.HTTP_1_1, 200, 'OK',
        Headers.of('Cache-Control', 'max-age=60'),
        new ResponseBody(null, new ArrayBuffer(2048)));
    };
    await runWithCache(new RequestBuilder().url(urlBig).build());
    eq('超过 maxSize 的响应体不缓存', cache.readEntry(new RequestBuilder().url(urlBig).build()), null);

    // 6) computeAgeMs 解析 Age 头
    const urlAge = 'https://e-hentai.org/aged';
    nextServerResp = (r: Request): Response => {
      return new Response(r, Protocol.HTTP_1_1, 200, 'OK',
        Headers.of('Cache-Control', 'max-age=60', 'Age', '70'),
        new ResponseBody(null, strToBytes('stale')));
    };
    await runWithCache(new RequestBuilder().url(urlAge).build());
    const rec = cache.readEntry(new RequestBuilder().url(urlAge).build());
    ok('Age=70 的响应落盘', rec !== null);
    if (rec !== null) {
      ok('computeAgeMs >= 70000', CacheInterceptor.computeAgeMs(rec, Date.now()) >= 70000);
    }
  } finally {
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch (e) {
      // ignore cleanup error
    }
  }
}

// ============================================================================
// 5. ConnectionPool & Http1SocketTransport 静态解码 / Mock Socket 行为
// ============================================================================
async function testSocketTransportAndPool(): Promise<void> {
  // ConnectionPool FD 关闭与容量/过期淘汰
  let closedIds: number[] = [];
  const mkSock = (id: number): CloseableSocket => ({
    close: (): void => { closedIds.push(id); }
  });
  const pool = new ConnectionPool(2, 5);
  pool.putIdle('k1', mkSock(1));
  pool.putIdle('k2', mkSock(2));
  pool.putIdle('k3', mkSock(3)); // 超出 maxIdle=2，淘汰最旧 1
  eq('ConnectionPool 超出 maxIdle 关闭最旧 socket', closedIds, [1]);
  eq('idleConnectionCount=2', pool.idleConnectionCount(), 2);
  const taken = pool.takeIdleConn('k3');
  ok('takeIdleConn 命中 k3', taken !== null);
  pool.evictAll();
  eq('evictAll 关闭剩余池化连接', closedIds, [1, 2]);

  // serialize 绝对 URI（HTTP 代理）& IPv6 Host
  const reqHttp = new RequestBuilder().url('http://[2001:db8::1]:8080/p?q=1').build();
  const absRaw = bytesToStr(Http1SocketTransport.serialize(reqHttp, true));
  ok('serialize(absoluteUri=true) 请求行含完整 URL',
    absRaw.startsWith('GET http://[2001:db8::1]:8080/p?q=1 HTTP/1.1\r\n'));
  ok('serialize IPv6 Host 带方括号与非默认端口',
    absRaw.indexOf('Host: [2001:db8::1]:8080\r\n') >= 0);

  // netAddressOf 剥离 IPv6 方括号并设 family
  const addrV6 = Http1SocketTransport.netAddressOf('[::1]', 443);
  eq('netAddressOf 剥离 IPv6 方括号', addrV6.address, '::1');
  eq('netAddressOf IPv6 family=2', addrV6.family, 2);
  const addrV4 = Http1SocketTransport.netAddressOf('1.2.3.4', 80);
  eq('netAddressOf IPv4 family=1', addrV4.family, 1);

  // decodeChunked：扩展/trailer/CRLF 严格校验
  const goodChunked = new TextEncoder().encode('5;ext=1\r\nhello\r\n6\r\n world\r\n0\r\nX-Trail: 1\r\n\r\n');
  const decGood = Http1SocketTransport.decodeChunked(goodChunked, 0);
  ok('decodeChunked 合法 chunk + trailer 完成', decGood.complete && decGood.body !== null);
  if (decGood.body !== null) {
    eq('decodeChunked 拼装结果', bytesToStr(decGood.body), 'hello world');
  }

  const incomplete = new TextEncoder().encode('5\r\nhello\r\n0\r\n');
  eq('decodeChunked 缺少最终空白 CRLF 返回未完成', Http1SocketTransport.decodeChunked(incomplete, 0).complete, false);

  throws('decodeChunked 拒绝非法十六进制长度 5xyz', () => {
    Http1SocketTransport.decodeChunked(new TextEncoder().encode('5xyz\r\nhello\r\n0\r\n\r\n'), 0);
  });
  throws('decodeChunked 拒绝块尾缺少 CRLF', () => {
    Http1SocketTransport.decodeChunked(new TextEncoder().encode('5\r\nhelloXX0\r\n\r\n'), 0);
  });

  // Mock @ohos.net.socket 验证：
  //   a) on('message') 必须先于 send() 注册
  //   b) 1xx 临时响应跳过，读到真实 200
  //   c) HTTP Proxy CONNECT 隧道 + constructTLSSocketInstance(tcp) + skipRemoteValidation
  //   d) SOCKS5 ProxyOptions
  const socketMod = require('@ohos.net.socket').default;
  const origConstructTcp = socketMod.constructTCPSocketInstance;
  const origConstructTls = socketMod.constructTLSSocketInstance;
  try {
    // a + b: 1xx + chunked + listener-before-send
    const events: string[] = [];
    let msgHandler: ((v: { message: ArrayBuffer }) => void) | null = null;
    socketMod.constructTCPSocketInstance = () => ({
      async connect(_opts: any) { events.push('connect'); },
      async send(_opts: any) {
        events.push('send');
        ok('onMessage 必须在 send 之前注册', msgHandler !== null);
        if (msgHandler !== null) {
          msgHandler({ message: strToBytes('HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 ') });
          msgHandler({ message: strToBytes('OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n2\r\nok\r\n0\r\n\r\n') });
        }
      },
      async close() { events.push('close'); },
      on(ev: string, cb: any) {
        events.push('on:' + ev);
        if (ev === 'message') {
          msgHandler = cb;
        }
      },
      off(_ev: string) {}
    });

    const t1 = new Http1SocketTransport(new ConnectionPool(1, 5));
    const resp1 = await t1.execute(new RequestBuilder().url('http://example.com/a').build(), 2000, 2000);
    eq('跳过 100 Continue 后返回 200', resp1.code(), 200);
    eq('分片 chunked 响应体', resp1.body()?.string(), 'ok');

    // c: HTTP proxy CONNECT + HTTPS -> constructTLSSocketInstance(tcp) + skipRemoteValidation
    let connectReqText = '';
    let innerHttpReqText = '';
    let tcpMsgCb: ((v: { message: ArrayBuffer }) => void) | null = null;
    let tlsMsgCb: ((v: { message: ArrayBuffer }) => void) | null = null;
    let tlsConnectOpts: any = null;
    let passedTcpToTls: any = null;

    const fakeTcp = {
      async connect(opts: any) {
        eq('HTTP 代理连接到代理主机', opts.address.address, '127.0.0.1');
        eq('HTTP 代理连接到代理端口', opts.address.port, 8888);
      },
      async send(opts: any) {
        connectReqText = bytesToStr(opts.data);
        if (tcpMsgCb !== null) {
          tcpMsgCb({ message: strToBytes('HTTP/1.1 200 Connection Established\r\n\r\n') });
        }
      },
      async close() {},
      on(ev: string, cb: any) { if (ev === 'message') { tcpMsgCb = cb; } },
      off(_ev: string) {}
    };

    socketMod.constructTCPSocketInstance = () => fakeTcp;
    socketMod.constructTLSSocketInstance = (tcp?: any) => {
      passedTcpToTls = tcp;
      return {
        async connect(opts: any) { tlsConnectOpts = opts; },
        async send(data: ArrayBuffer) {
          innerHttpReqText = bytesToStr(data);
          if (tlsMsgCb !== null) {
            tlsMsgCb({ message: strToBytes('HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nyes') });
          }
        },
        async close() {},
        on(ev: string, cb: any) { if (ev === 'message') { tlsMsgCb = cb; } },
        off(_ev: string) {}
      };
    };

    const t2 = new Http1SocketTransport(new ConnectionPool(1, 5));
    const respConnect = await t2.execute(
      new RequestBuilder().url('https://e-hentai.org/index.php').build(),
      2000, 2000,
      { proxy: new Proxy(ProxyType.HTTP, '127.0.0.1', 8888), skipRemoteValidation: true }
    );
    ok('CONNECT 请求行指向目标站', connectReqText.startsWith('CONNECT e-hentai.org:443 HTTP/1.1\r\n'));
    ok('constructTLSSocketInstance 接管已 CONNECT 的 tcpSocket', passedTcpToTls === fakeTcp);
    eq('TLS skipRemoteValidation 透传', tlsConnectOpts?.skipRemoteValidation, true);
    ok('隧道内层写相对路径 HTTP 请求', innerHttpReqText.startsWith('GET /index.php HTTP/1.1\r\n'));
    eq('HTTPS via HTTP CONNECT 读到响应', respConnect.body()?.string(), 'yes');

    // d: SOCKS5 ProxyOptions
    let socksOpts: any = null;
    let socksMsgCb: ((v: { message: ArrayBuffer }) => void) | null = null;
    socketMod.constructTCPSocketInstance = () => ({
      async connect(opts: any) { socksOpts = opts; },
      async send(_opts: any) {
        if (socksMsgCb !== null) {
          socksMsgCb({ message: strToBytes('HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nsocks') });
        }
      },
      async close() {},
      on(ev: string, cb: any) { if (ev === 'message') { socksMsgCb = cb; } },
      off(_ev: string) {}
    });

    const t3 = new Http1SocketTransport(new ConnectionPool(1, 5));
    const respSocks = await t3.execute(
      new RequestBuilder().url('http://exhentai.org/').build(),
      2000, 2000,
      { proxy: new Proxy(ProxyType.SOCKS, '127.0.0.1', 1080) }
    );
    eq('SOCKS5 ProxyTypes=1', socksOpts?.proxy?.type, 1);
    eq('SOCKS5 代理地址', socksOpts?.proxy?.address?.address, '127.0.0.1');
    eq('SOCKS5 代理端口', socksOpts?.proxy?.address?.port, 1080);
    eq('SOCKS5 目标地址', socksOpts?.address?.address, 'exhentai.org');
    eq('SOCKS5 响应体', respSocks.body()?.string(), 'socks');
  } finally {
    socketMod.constructTCPSocketInstance = origConstructTcp;
    socketMod.constructTLSSocketInstance = origConstructTls;
  }
}

// ============================================================================
// 6. SystemHttpTransport & OkHttpClient 路由 + PageImageDownloaderImpl
// ============================================================================
async function testClientRoutingAndDownloader(): Promise<void> {
  // buildRequestHeaders & stripInflatedHeaders
  const reqH = new HeadersBuilder()
    .add('Accept-Encoding', 'br')
    .add('X-Multi', '1')
    .add('x-multi', '2')
    .add('Cookie', 'a=1')
    .add('cookie', 'b=2')
    .build();
  const built = SystemHttpTransport.buildRequestHeaders(reqH);
  eq('Accept-Encoding 已指定时不重复追加 gzip', built['Accept-Encoding'], 'br');
  eq('多值普通头逗号聚合', built['X-Multi'], '1, 2');
  eq('多值 Cookie 分号聚合', built['Cookie'], 'a=1; b=2');

  const inflated = SystemHttpTransport.stripInflatedHeaders(
    Headers.of('Content-Encoding', 'gzip', 'Content-Length', '123', 'X-Keep', 'ok'));
  eq('解压后剥离 Content-Encoding', inflated.get('Content-Encoding'), null);
  eq('解压后剥离压缩前 Content-Length', inflated.get('Content-Length'), null);
  eq('保留其它头', inflated.get('X-Keep'), 'ok');

  const httpMod = require('@ohos.net.http').default;
  const socketMod = require('@ohos.net.socket').default;
  const origCreateHttp = httpMod.createHttp;
  const origConstructTls = socketMod.constructTLSSocketInstance;
  try {
    let lastHttpOpts: any = null;
    let destroyed = false;
    httpMod.createHttp = () => ({
      async request(_url: string, opts: any) {
        lastHttpOpts = opts;
        return {
          responseCode: 200,
          header: { 'Content-Encoding': 'gzip', 'Content-Length': '9', 'Content-Type': 'text/plain' },
          result: strToBytes('inflated-body')
        };
      },
      destroy() { destroyed = true; }
    });

    // NO_PROXY → usingProxy: false; maxLimit = 100 MiB
    const clientNoProxy = new OkHttpClientBuilder()
      .proxySelector({ select: (): Proxy[] => [Proxy.NO_PROXY] })
      .build();
    const res1 = await clientNoProxy.newCall(new RequestBuilder().url('https://e-hentai.org/test').build()).execute();
    eq('SystemHttpTransport maxLimit=100MiB', lastHttpOpts?.maxLimit, 100 * 1024 * 1024);
    eq('Proxy.NO_PROXY -> usingProxy=false', lastHttpOpts?.usingProxy, false);
    eq('自动剥离 gzip Content-Length', res1.headers().get('Content-Length'), null);
    ok('finally 调用 req.destroy()', destroyed);

    // HTTP 代理优先走 SystemHttpTransport（配置 usingProxy），不强走 Http1SocketTransport
    lastHttpOpts = null;
    const clientHttpProxy = new OkHttpClientBuilder()
      .proxySelector({ select: (): Proxy[] => [new Proxy(ProxyType.HTTP, '127.0.0.1', 7890)] })
      .build();
    const resHttpProxy = await clientHttpProxy.newCall(new RequestBuilder().url('https://e-hentai.org/proxy-test').build()).execute();
    eq('HTTP 代理走 SystemHttpTransport 返回 200', resHttpProxy.code(), 200);
    eq('HTTP 代理传入 usingProxy host/port', lastHttpOpts?.usingProxy,
      { host: '127.0.0.1', port: 7890, exclusionList: [] });

    // DNS override (Domain Fronting) → 路由到 SocketTransport 并直连覆写 IP + skipRemoteValidation=true
    let frontedConnectOpts: any = null;
    let frontedReqText = '';
    let frontedMsgCb: ((v: { message: ArrayBuffer }) => void) | null = null;
    socketMod.constructTLSSocketInstance = () => ({
      async connect(opts: any) { frontedConnectOpts = opts; },
      async send(data: ArrayBuffer) {
        frontedReqText = bytesToStr(data);
        if (frontedMsgCb !== null) {
          frontedMsgCb({ message: strToBytes('HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok') });
        }
      },
      async close() {},
      on(ev: string, cb: any) { if (ev === 'message') { frontedMsgCb = cb; } },
      off(_ev: string) {}
    });

    const overrideDns: OverrideAwareDns = {
      reportsOverrideFlag: true,
      async lookup(_h: string): Promise<InetAddress[]> {
        return [new InetAddress('e-hentai.org', '104.20.18.168', true)];
      }
    };
    const dfClient = new OkHttpClientBuilder().dns(overrideDns).build();
    const dfRes = await dfClient.newCall(new RequestBuilder().url('https://e-hentai.org/g/1/a').build()).execute();
    eq('Domain Fronting Socket 连接覆写 IP', frontedConnectOpts?.address?.address, '104.20.18.168');
    eq('Domain Fronting 设 skipRemoteValidation=true', frontedConnectOpts?.skipRemoteValidation, true);
    ok('Domain Fronting 保留原 Host 头', frontedReqText.indexOf('Host: e-hentai.org\r\n') >= 0);
    eq('Domain Fronting 返回 200', dfRes.body()?.string(), 'ok');

    // OkHttpClient.newBuilder() 不互相污染
    const baseClient = new OkHttpClientBuilder().followRedirects(true).followSslRedirects(false).build();
    const subClient = baseClient.newBuilder().followRedirects(false).build();
    eq('原 client followRedirects 仍为 true', baseClient.followRedirects(), true);
    eq('新 client followRedirects 为 false', subClient.followRedirects(), false);
    eq('新 client 保留 followSslRedirects=false', subClient.followSslRedirects(), false);

    // call.cancel() 在执行前拦截
    const canceledCall = dfClient.newCall(new RequestBuilder().url('https://e-hentai.org/').build());
    canceledCall.cancel();
    let cancelCaught = false;
    try {
      await canceledCall.execute();
    } catch (e) {
      cancelCaught = (e as Error).message === 'Canceled';
    }
    ok('call.cancel() 触发 Canceled', cancelCaught);

    // PageImageDownloaderImpl：传 followRedirects=true 客户端也能拦截 302 劫持 + 保留 EhRequestBuilder 头 & C-18 Referer
    let seenDownloadReq = '';
    let dlMsgCb: ((v: { message: ArrayBuffer }) => void) | null = null;
    let returnHijack = false;
    socketMod.constructTLSSocketInstance = () => ({
      async connect(_opts: any) {},
      async send(data: ArrayBuffer) {
        seenDownloadReq = bytesToStr(data);
        if (dlMsgCb !== null) {
          if (returnHijack) {
            dlMsgCb({ message: strToBytes('HTTP/1.1 302 Found\r\nLocation: https://evil.example/a.jpg\r\nContent-Length: 0\r\nConnection: close\r\n\r\n') });
          } else {
            dlMsgCb({ message: strToBytes('HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\nIMG!') });
          }
        }
      },
      async close() {},
      on(ev: string, cb: any) { if (ev === 'message') { dlMsgCb = cb; } },
      off(_ev: string) {}
    });

    // followRedirects(true) 客户端 + overrideDns 强制走 socket，验证 PageImageDownloaderImpl 内部关闭自动重定向并识别 302 劫持
    const downloader = new PageImageDownloaderImpl(dfClient);
    const sink1 = new MemorySink();
    const rOk = await downloader.downloadWithStatus('https://img.example/1.jpg', sink1, 'https://e-hentai.org/s/1');
    eq('PageImageDownloader 下载成功', rOk.ok, true);
    eq('PageImageDownloader 写出字节', sink1.asText(), 'IMG!');
    ok('PageImageDownloader 使用 EhRequestBuilder (含 User-Agent)',
      seenDownloadReq.indexOf('User-Agent: Mozilla/') >= 0);
    ok('PageImageDownloader 非空 Referer 写入请求头',
      seenDownloadReq.indexOf('Referer: https://e-hentai.org/s/1\r\n') >= 0);

    const sink2 = new MemorySink();
    await downloader.downloadWithStatus('https://img.example/2.jpg', sink2, '');
    ok('C-18 空串 referer 不发送 Referer 头', seenDownloadReq.indexOf('Referer:') < 0);

    returnHijack = true;
    const sink3 = new MemorySink();
    const rHijack = await downloader.downloadWithStatus('https://img.example/3.jpg', sink3);
    eq('PageImageDownloader 拦截 302 反劫持', rHijack.ok, false);
    eq('反劫持标记 hijacked=true', rHijack.hijacked, true);

    // BusinessError 格式化与归一化：不出现 [object Object] 且保留 Canceled 哨兵
    eq('describeNetworkError 格式化 code+message',
      describeNetworkError({ code: 2300035, message: 'SSL connect error' }),
      '[2300035] SSL connect error');
    eq('toNetworkError 保留 Canceled 哨兵',
      toNetworkError(new Error('Canceled'), 'http').message,
      'Canceled');
    httpMod.createHttp = () => ({
      async request(_url: string, _opts: any) {
        throw { code: 2300007, message: "Couldn't connect to server" };
      },
      destroy() {}
    });
    let httpErrMsg = '';
    try {
      await clientNoProxy.newCall(new RequestBuilder().url('https://e-hentai.org/err').build()).execute();
    } catch (e) {
      httpErrMsg = e instanceof Error ? e.message : String(e);
    }
    eq('SystemHttpTransport BusinessError 归一化',
      httpErrMsg,
      "http: [2300007] Couldn't connect to server");

    // 2A: Http1SocketTransport 分块接收进度回调（先头+半包，再尾包，按 Content-Length 上报）
    let sockProgCb: any = null;
    socketMod.constructTLSSocketInstance = () => ({
      async connect(_opts: any) {},
      async send(_data: ArrayBuffer) {
        if (sockProgCb !== null) {
          sockProgCb({ message: strToBytes('HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\nABCDE') });
          setTimeout(() => {
            sockProgCb({ message: strToBytes('FGHIJ') });
          }, 5);
        }
      },
      async close() {},
      on(ev: string, cb: any) { if (ev === 'message') { sockProgCb = cb; } },
      off(_ev: string) {}
    });
    const sockEvents: number[][] = [];
    const sinkSockProg = new MemorySink();
    const resSockProg = await downloader.downloadWithStatus(
      'https://img.example/prog.jpg',
      sinkSockProg,
      'https://e-hentai.org/s/1',
      (cl: number, rec: number, delta: number) => {
        sockEvents.push([cl, rec, delta]);
      }
    );
    eq('Socket 分块进度下载成功', resSockProg.ok, true);
    eq('Socket 分块进度写出完整字节', sinkSockProg.asText(), 'ABCDEFGHIJ');
    ok('Socket 分块进度至少触发首包(5/10)与尾包(10/10)',
      sockEvents.some((e) => e[0] === 10 && e[1] === 5 && e[2] === 5) &&
      sockEvents.some((e) => e[0] === 10 && e[1] === 10));

    // 2A: SystemHttpTransport dataReceiveProgress 监听注册并在 finally 中 off 清理
    let attachedProgressCb: ((info: { receiveSize: number; totalSize: number }) => void) | null = null;
    let offCount = 0;
    httpMod.createHttp = () => ({
      on(ev: string, cb: any) {
        if (ev === 'dataReceiveProgress') {
          attachedProgressCb = cb;
        }
      },
      off(ev: string, cb?: any) {
        if (ev === 'dataReceiveProgress' && cb === attachedProgressCb) {
          offCount++;
        }
      },
      async request(_url: string, _opts: any) {
        if (attachedProgressCb !== null) {
          attachedProgressCb({ receiveSize: 4, totalSize: 10 });
          attachedProgressCb({ receiveSize: 10, totalSize: 10 });
        }
        return {
          result: strToBytes('0123456789'),
          responseCode: 200,
          header: { 'Content-Length': '10' },
          resultType: 2
        };
      },
      destroy() {}
    });
    const sysEvents: number[][] = [];
    const transportSys = new SystemHttpTransport();
    await transportSys.execute(
      new RequestBuilder().url('https://ehgt.org/p.jpg').build(),
      3000,
      3000,
      {
        onProgress: (cl: number, rec: number, delta: number) => {
          sysEvents.push([cl, rec, delta]);
        }
      }
    );
    eq('SystemHttpTransport dataReceiveProgress 上报进度', sysEvents, [[10, 4, 4], [10, 10, 6]]);
    eq('SystemHttpTransport finally 调用 off 清理 dataReceiveProgress', offCount, 1);

    // 2A: unknown/chunked totalSize=-1 不伪造百分比
    const unknownEvents: number[][] = [];
    httpMod.createHttp = () => ({
      on(ev: string, cb: any) {
        if (ev === 'dataReceiveProgress') {
          attachedProgressCb = cb;
        }
      },
      off(ev: string, _cb?: any) {
        if (ev === 'dataReceiveProgress') {
          offCount++;
        }
      },
      async request(_url: string, _opts: any) {
        if (attachedProgressCb !== null) {
          attachedProgressCb({ receiveSize: 5, totalSize: -1 });
        }
        return {
          result: strToBytes('HELLO'),
          responseCode: 200,
          header: {},
          resultType: 2
        };
      },
      destroy() {}
    });
    await transportSys.execute(
      new RequestBuilder().url('https://ehgt.org/chunked.jpg').build(),
      3000,
      3000,
      {
        onProgress: (cl: number, rec: number, delta: number) => {
          unknownEvents.push([cl, rec, delta]);
        }
      }
    );
    eq('SystemHttpTransport 未知长度保持 total=-1', unknownEvents, [[-1, 5, 5]]);
  } finally {
    httpMod.createHttp = origCreateHttp;
    socketMod.constructTLSSocketInstance = origConstructTls;
  }
}

async function testWave1NetworkAndReaderCases(): Promise<void> {
  const httpMod = require('@ohos.net.http').default;
  const socketMod = require('@ohos.net.socket').default;
  const origCreateHttp = httpMod.createHttp;
  const origConstructTls = socketMod.constructTLSSocketInstance;
  const origConstructTcp = socketMod.constructTCPSocketInstance;

  class StaticSelector extends ProxySelector {
    private readonly _proxies: Proxy[];
    constructor(proxies: Proxy[]) {
      super();
      this._proxies = proxies;
    }
    select(_url: HttpUrl): Proxy[] {
      return this._proxies;
    }
  }

  class MemorySink implements ByteSink {
    chunks: number[] = [];
    closed: boolean = false;
    write(buf: ArrayBuffer): number {
      const u8 = new Uint8Array(buf);
      for (let i = 0; i < u8.length; i++) {
        this.chunks.push(u8[i]);
      }
      return u8.length;
    }
    close(): void {
      this.closed = true;
    }
  }

  try {
    // 1) SystemHttpTransport: headersReceive Location 捕获 + redirectTiming 检测 + dataReceiveProgress 进度透传
    let capturedOpts: Record<string, Object> | null = null;
    httpMod.createHttp = () => {
      const cbs: Record<string, Function> = {};
      return {
        on(ev: string, cb: Function) { cbs[ev] = cb; },
        off(_ev: string) {},
        destroy() {},
        async request(_url: string, opts: Record<string, Object>) {
          capturedOpts = opts;
          if (cbs['headersReceive']) {
            cbs['headersReceive']({ Location: 'https://hijack.invalid/redir.jpg' });
            cbs['headersReceive']({ 'Content-Length': '100' });
          }
          if (cbs['dataReceiveProgress']) {
            cbs['dataReceiveProgress']({ totalSize: 100, receiveSize: 50 });
            cbs['dataReceiveProgress']({ totalSize: 100, receiveSize: 100 });
          }
          return {
            responseCode: 200,
            header: { 'Content-Type': 'image/jpeg' },
            resultType: 2,
            result: new Uint8Array([0xff, 0xd8, 0xff, 0xe0]).buffer,
            performanceTiming: { redirectTiming: 14 }
          };
        }
      };
    };

    const progressLog: number[][] = [];
    const sysResp = await new SystemHttpTransport().execute(
      new RequestBuilder().url('https://hath.network/h/page.jpg').build(),
      5000,
      5000,
      {
        proxy: Proxy.system(),
        onProgress: (cl: number, recv: number, delta: number) => {
          progressLog.push([cl, recv, delta]);
        }
      }
    );
    ok('SystemHttpTransport 保留 Proxy.system -> usingProxy=true',
      capturedOpts !== null && capturedOpts['usingProxy'] === true);
    eq('SystemHttpTransport 检测 headersReceive + redirectTiming 发生重定向', sysResp.wasRedirected(), true);
    eq('SystemHttpTransport 记录首次跳转 Location', sysResp.redirectLocation(), 'https://hijack.invalid/redir.jpg');
    eq('SystemHttpTransport 连续回调 dataReceiveProgress 增量字节',
      progressLog, [[100, 50, 50], [100, 100, 50]]);

    // 2) PageImageDownloaderImpl 走 followRedirects(true) 客户端：正常走 SystemHttpTransport 且触发劫持拦截
    const followClient = new OkHttpClientBuilder()
      .followRedirects(true)
      .proxySelector(new StaticSelector([Proxy.system()]))
      .build();
    const dlHijack = new PageImageDownloaderImpl(followClient);
    const hijackRes = await dlHijack.downloadWithStatus('https://hath.network/h/img1.jpg', new MemorySink());
    eq('PageImageDownloaderImpl 捕获 SystemHttpTransport 30x 劫持', hijackRes.ok, false);
    eq('PageImageDownloaderImpl 劫持标记 hijacked=true', hijackRes.hijacked, true);

    httpMod.createHttp = () => {
      const cbs: Record<string, Function> = {};
      return {
        on(ev: string, cb: Function) { cbs[ev] = cb; },
        off(_ev: string) {},
        destroy() {},
        async request(_url: string, opts: Record<string, Object>) {
          capturedOpts = opts;
          if (cbs['headersReceive']) {
            cbs['headersReceive']({ 'Content-Length': '4' });
          }
          if (cbs['dataReceiveProgress']) {
            cbs['dataReceiveProgress']({ totalSize: 4, receiveSize: 4 });
          }
          return {
            responseCode: 200,
            header: { 'Content-Type': 'image/png', 'Content-Length': '4' },
            resultType: 2,
            result: new Uint8Array([0x89, 0x50, 0x4e, 0x47]).buffer,
            performanceTiming: { redirectTiming: 0 }
          };
        }
      };
    };
    const okSink = new MemorySink();
    const okProg: number[][] = [];
    capturedOpts = null;
    const okRes = await dlHijack.downloadWithStatus(
      'https://hath.network/h/ok.png',
      okSink,
      'https://e-hentai.org/s/abc/1-1',
      (cl: number, recv: number, delta: number) => okProg.push([cl, recv, delta])
    );
    eq('PageImageDownloaderImpl 正常图片下载成功', okRes.ok, true);
    eq('PageImageDownloaderImpl 正常图片写入 4 字节', okRes.received, 4);
    ok('PageImageDownloaderImpl 通过 followRedirects(true) 走 SystemHttpTransport', capturedOpts !== null);
    ok('PageImageDownloaderImpl 保留 dataReceiveProgress 进度回调', okProg.length >= 1 && okProg[0][0] === 4);

    // 3) resolveRedirectUrl 使用 followRedirects(false) 探测 302 Location vs 200 HTML (GP 不足)
    const enc = new (require('util').TextEncoder)();
    const toBuf = (s: string): ArrayBuffer => {
      const u = enc.encode(s);
      return u.buffer.slice(u.byteOffset, u.byteOffset + u.byteLength);
    };
    let nextSocketReply = 'HTTP/1.1 302 Found\r\nLocation: https://origin-cdn.invalid/raw.png\r\nContent-Length: 0\r\n\r\n';
    socketMod.constructTLSSocketInstance = () => {
      let tlsMsgCb: ((v: { message: ArrayBuffer }) => void) | null = null;
      return {
        async connect(_opts: any) {},
        async send(_data: any) {
          if (tlsMsgCb !== null) {
            tlsMsgCb({ message: toBuf(nextSocketReply) });
          }
        },
        async close() {},
        on(ev: string, cb: any) { if (ev === 'message') { tlsMsgCb = cb; } },
        off(_ev: string) {}
      };
    };
    const resolvedOrigin = await dlHijack.resolveRedirectUrl(
      'https://e-hentai.org/fullimg/1/0/raw.png',
      'https://e-hentai.org/s/abc/1-1'
    );
    eq('resolveRedirectUrl 探测 302 返回绝对原图地址', resolvedOrigin, 'https://origin-cdn.invalid/raw.png');

    nextSocketReply = 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 9\r\n\r\nNo GP!!!!';
    const insufficientGp = await dlHijack.resolveRedirectUrl(
      'https://e-hentai.org/fullimg/1/0/raw.png',
      'https://e-hentai.org/s/abc/1-1'
    );
    eq('resolveRedirectUrl 探测 200 HTML 返回 null 触发 GP 不足', insufficientGp, null);

    // 4) SystemProxyHelper 排除列表匹配与 resolveHttpProxy + ConnectInterceptor 验证
    eq('SystemProxyHelper *.ehgt.org 命中子域', SystemProxyHelper.isHostExcluded('a.ehgt.org', ['*.ehgt.org']), true);
    eq('SystemProxyHelper .ehgt.org 命中裸域', SystemProxyHelper.isHostExcluded('ehgt.org', ['.ehgt.org']), true);
    eq('SystemProxyHelper *.ehgt.org 不误杀 exhentai.org', SystemProxyHelper.isHostExcluded('exhentai.org', ['*.ehgt.org']), false);
    eq('SystemProxyHelper 通配符 * 全排除', SystemProxyHelper.isHostExcluded('e-hentai.org', ['*']), true);

    SystemProxyHelper.setResolver(async (_host: string) => new Proxy(ProxyType.HTTP, '127.0.0.1', 7890));
    const resolvedSysProxy = await SystemProxyHelper.resolveHttpProxy('exhentai.org');
    eq('SystemProxyHelper.resolveHttpProxy 返回 HTTP 127.0.0.1:7890',
      resolvedSysProxy !== null ? `${resolvedSysProxy.type()}:${resolvedSysProxy.address()}:${resolvedSysProxy.port()}` : '',
      'HTTP:127.0.0.1:7890');

    // ConnectInterceptor 在 Socket 模式下将 Proxy.system() 替换为 SystemProxyHelper 解析出的 HTTP 代理
    let connectLineSeen = '';
    let innerSocketTls = false;
    let fakeTcpCb: ((v: { message: ArrayBuffer }) => void) | null = null;
    socketMod.constructTCPSocketInstance = () => ({
      async connect(_opts: any) {},
      async send(opts: any) {
        connectLineSeen = bytesToStr(opts.data);
        if (fakeTcpCb !== null) {
          fakeTcpCb({ message: toBuf('HTTP/1.1 200 Connection Established\r\n\r\n') });
        }
      },
      async close() {},
      on(ev: string, cb: any) { if (ev === 'message') { fakeTcpCb = cb; } },
      off(_ev: string) {}
    });
    socketMod.constructTLSSocketInstance = (tcp: any) => {
      innerSocketTls = tcp !== undefined;
      let cb: ((v: { message: ArrayBuffer }) => void) | null = null;
      return {
        async connect(_opts: any) {},
        async send(_data: any) {
          if (cb !== null) {
            cb({ message: toBuf('HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok') });
          }
        },
        async close() {},
        on(ev: string, fn: any) { if (ev === 'message') { cb = fn; } },
        off(_ev: string) {}
      };
    };
    const noFollowSysClient = new OkHttpClientBuilder()
      .followRedirects(false)
      .proxySelector(new StaticSelector([Proxy.system()]))
      .build();
    const sysSocketResp = await noFollowSysClient.newCall(new RequestBuilder().url('https://exhentai.org/').build()).execute();
    eq('ConnectInterceptor 解析系统 HTTP 代理并建立 CONNECT 隧道', sysSocketResp.code(), 200);
    ok('ConnectInterceptor CONNECT 请求指向 exhentai.org:443',
      innerSocketTls && connectLineSeen.indexOf('CONNECT exhentai.org:443') >= 0);

    // 5) OkHttpEhHosts IPv4 优先 + HttpDohResolver usingProxy=true
    const mixedProvider: AsyncHostsProvider = {
      async getList(_host: string): Promise<string[] | null> {
        return ['2a00:7c80::1', '185.132.132.79', '2a00:7c80::2', '62.112.8.152'];
      }
    };
    const ehHosts = new OkHttpEhHosts(new EhHostsConfig(), null, mixedProvider, null);
    const addrs = await ehHosts.lookup('ehgt.org');
    eq('OkHttpEhHosts 返回 4 条地址', addrs.length, 4);
    ok('OkHttpEhHosts 将 IPv4 排在 IPv6 之前',
      !addrs[0].isIpv6() && !addrs[1].isIpv6() && addrs[2].isIpv6() && addrs[3].isIpv6());

    let dohOpts: Record<string, Object> | null = null;
    httpMod.createHttp = () => ({
      on(_ev: string, _cb: Function) {},
      off(_ev: string) {},
      destroy() {},
      async request(_url: string, opts: Record<string, Object>) {
        dohOpts = opts;
        return { responseCode: 200, header: {}, resultType: 2, result: new ArrayBuffer(0) };
      }
    });
    await new HttpDohResolver().lookupAsync('exhentai.org');
    ok('HttpDohResolver POST 请求开启 usingProxy: true',
      dohOpts !== null && dohOpts['usingProxy'] === true);
  } finally {
    SystemProxyHelper.setResolver(null);
    httpMod.createHttp = origCreateHttp;
    socketMod.constructTLSSocketInstance = origConstructTls;
    socketMod.constructTCPSocketInstance = origConstructTcp;
  }
}

async function main(): Promise<void> {
  testCookieParsing();
  testHttpBasics();
  await testRedirectInterceptor();
  await testCacheInterceptor();
  await testSocketTransportAndPool();
  await testClientRoutingAndDownloader();
  await testWave1NetworkAndReaderCases();

  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (let i = 0; i < failures.length; i++) {
      console.log('  FAIL ' + failures[i]);
    }
    process.exitCode = 1;
  }
}

main().catch((e: Error) => {
  console.error(e);
  process.exitCode = 1;
});
