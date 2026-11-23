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

import socket from '@ohos.net.socket';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { InetValidator } from '../network/InetValidator';
import { InetAddress, describeNetworkError, toNetworkError } from './Dns';
import { Headers } from './Headers';
import { CallAbortController } from './Interceptor';
import { MediaType } from './MediaType';
import { Proxy, ProxyType, SystemProxyHelper } from './ProxySelector';
import { Protocol, Response } from './Response';
import { ResponseBody } from './ResponseBody';
import { Request } from './Request';
import { CloseableSocket, ConnectionPool } from './ConnectionPool';
import { Transport, TransportExecuteOptions, TransportProgressCallback } from './SystemHttpTransport';
import { utf8Encode } from './RequestBody';

/**
 * 基于 @ohos.net.socket 的 HTTP/1.1 传输实现。
 *
 * 存在的理由（@ohos.net.http 做不到的能力）：
 *   1) followRedirects=false：EhEngine.imageSearch 与图片反劫持必须拿到原始 302 + Location；
 *   2) PATCH 方法、SOCKS5 代理（ProxyOptions）、HTTP 代理（绝对 URI / CONNECT 隧道）；
 *   3) 自定义 DNS IP 直连（Domain Fronting：连接解析 IP + 发送原始 Host 头 + skipRemoteValidation）；
 *   4) 真正的连接复用：socket 交由 ConnectionPool 按 maxIdleConnections/keepAlive 管理并及时关 FD。
 *
 * ALPN：TLSConnectOptions.ALPNProtocols 固定 ['http/1.1']，保证不会协商到 h2。
 * 压缩：发送 `Accept-Encoding: identity`，不做 gzip/br 解压。
 */

/** socket 句柄包装：TCP 与 TLS 两套签名分开处理。 */
class Conn implements CloseableSocket {
  readonly kind: string;
  private readonly _tcp: socket.TCPSocket | null;
  private readonly _tls: socket.TLSSocket | null;
  private _closed: boolean = false;
  allowPool: boolean = true;
  private _remoteClosed: boolean = false;

  constructor(kind: string, tcp: socket.TCPSocket | null, tls: socket.TLSSocket | null) {
    this.kind = kind;
    this._tcp = tcp;
    this._tls = tls;
  }

  static ofTcp(tcp: socket.TCPSocket): Conn {
    return new Conn('tcp', tcp, null);
  }

  static ofTls(tls: socket.TLSSocket, allowPool: boolean = true): Conn {
    const conn: Conn = new Conn('tls', null, tls);
    conn.allowPool = allowPool;
    return conn;
  }

  markRemoteClosed(): void {
    this._remoteClosed = true;
  }

  isRemoteClosed(): boolean {
    return this._remoteClosed;
  }

  isClosed(): boolean {
    return this._closed;
  }

  async send(data: ArrayBuffer): Promise<void> {
    if (this.kind === 'tcp') {
      const opts: socket.TCPSendOptions = { data: data };
      await (this._tcp as socket.TCPSocket).send(opts);
    } else {
      await (this._tls as socket.TLSSocket).send(data);
    }
  }

  onMessage(cb: (value: socket.SocketMessageInfo) => void): void {
    if (this.kind === 'tcp') {
      (this._tcp as socket.TCPSocket).on('message', cb);
    } else {
      (this._tls as socket.TLSSocket).on('message', cb);
    }
  }

  onError(cb: (err: Object) => void): void {
    if (this.kind === 'tcp') {
      (this._tcp as socket.TCPSocket).on('error', cb);
    } else {
      (this._tls as socket.TLSSocket).on('error', cb);
    }
  }

  onClose(cb: () => void): void {
    if (this.kind === 'tcp') {
      (this._tcp as socket.TCPSocket).on('close', cb);
    } else {
      (this._tls as socket.TLSSocket).on('close', cb);
    }
  }

  offAll(): void {
    try {
      if (this.kind === 'tcp') {
        (this._tcp as socket.TCPSocket).off('message');
        (this._tcp as socket.TCPSocket).off('error');
        (this._tcp as socket.TCPSocket).off('close');
      } else {
        (this._tls as socket.TLSSocket).off('message');
        (this._tls as socket.TLSSocket).off('error');
        (this._tls as socket.TLSSocket).off('close');
      }
    } catch (e) {
      // 未注册监听时 off 可能抛错，忽略
    }
  }

  close(): void {
    if (this._closed) {
      return;
    }
    this._closed = true;
    try {
      this.offAll();
      if (this._tls !== null) {
        this._tls.close().catch((closeErr: Object): void => {
          hilog.debug(0x0000, 'Http1SocketTransport', 'tls.close ignored: %{public}s',
            closeErr instanceof Error ? closeErr.message : String(closeErr));
        });
      }
      if (this._tcp !== null) {
        this._tcp.close().catch((closeErr: Object): void => {
          hilog.debug(0x0000, 'Http1SocketTransport', 'tcp.close ignored: %{public}s',
            closeErr instanceof Error ? closeErr.message : String(closeErr));
        });
      }
    } catch (e) {
      // 关闭失败无需处理
    }
  }
}

export class Http1SocketTransport implements Transport {
  readonly name: string = 'ohos.net.socket/http1.1';

  private readonly _pool: ConnectionPool;
  private readonly _activeConns: Set<Conn> = new Set<Conn>();

  constructor(pool: ConnectionPool) {
    this._pool = pool;
  }

  async execute(request: Request, connectTimeoutMs: number, readTimeoutMs: number,
    options?: TransportExecuteOptions): Promise<Response> {
    const abort: CallAbortController | null =
      options !== undefined && options.abort !== undefined ? options.abort : null;
    if (abort !== null && abort.isAborted()) {
      throw new Error('Canceled');
    }

    const writeTimeoutMs: number =
      options !== undefined && options.writeTimeoutMs !== undefined ? options.writeTimeoutMs : 10000;
    const callTimeoutMs: number =
      options !== undefined && options.callTimeoutMs !== undefined ? options.callTimeoutMs : 0;
    let proxy: Proxy | null =
      options !== undefined && options.proxy !== undefined ? options.proxy : null;
    const urlHost: string = request.url().host();
    if (proxy !== null && proxy.type() === ProxyType.DIRECT && !proxy.isNoProxy()) {
      const sysProxy: Proxy | null = await SystemProxyHelper.resolveHttpProxy(urlHost);
      if (sysProxy !== null) {
        proxy = sysProxy;
      }
    }
    const resolvedAddress: InetAddress | null =
      options !== undefined && options.resolvedAddress !== undefined ? options.resolvedAddress : null;
    const skipValidation: boolean =
      options !== undefined && options.skipRemoteValidation === true;
    const onProgress: TransportProgressCallback | undefined =
      options !== undefined ? options.onProgress : undefined;

    const port: number = request.url().port();
    const isTls: boolean = request.url().isHttps();
    const isHttpProxyPlain: boolean =
      proxy !== null && proxy.type() === ProxyType.HTTP && !isTls;
    const connectHost: string = resolvedAddress !== null
      ? Http1SocketTransport.stripIpv6Brackets(resolvedAddress.hostAddress())
      : Http1SocketTransport.stripIpv6Brackets(urlHost);
    const proxyTag: string = proxy === null ? 'DIRECT' : proxy.toString();
    const key: string = `${proxyTag}|${urlHost}:${port}|${connectHost}|${isTls}|${skipValidation}`;

    const wire: ArrayBuffer = Http1SocketTransport.serialize(request, isHttpProxyPlain);

    let callTimedOut: boolean = false;
    let callTimer: number = -1;
    const localAbort: CallAbortController = new CallAbortController();
    let unsubParentAbort: () => void = (): void => {};
    if (abort !== null) {
      unsubParentAbort = abort.onAbort((): void => {
        localAbort.abort();
      });
    }
    if (callTimeoutMs > 0) {
      callTimer = setTimeout((): void => {
        callTimedOut = true;
        localAbort.abort();
      }, callTimeoutMs) as number;
    }

    let conn: Conn | null = null;
    try {
      conn = this.takeSocket(key);
      if (conn === null) {
        conn = await this.connect(urlHost, connectHost, port, isTls, proxy,
          connectTimeoutMs, readTimeoutMs, skipValidation, localAbort);
      }
      const c: Conn = conn;
      this._activeConns.add(c);
      const unsubConnAbort: () => void = localAbort.onAbort((): void => {
        c.close();
      });

      try {
        // 先注册接收/错误/关闭监听再发送，防止短响应在 send() resolve 前到达而丢失
        const reader: ResponseReadHandle = Http1SocketTransport.beginReadResponse(
          c, readTimeoutMs, request.method() === 'HEAD', false, localAbort, onProgress);
        reader.promise.catch((): void => {});

        await Http1SocketTransport.sendWithGuard(c, wire, writeTimeoutMs, localAbort);
        reader.startTimer();
        const raw: RawResponse = await reader.promise;

        this._activeConns.delete(c);
        unsubConnAbort();

        const keepAlive: boolean = Http1SocketTransport.shouldKeepAlive(raw);
        if (keepAlive && c.allowPool && !c.isClosed() && !c.isRemoteClosed() && !localAbort.isAborted()) {
          this.returnSocket(key, c);
        } else {
          c.close();
        }
        const ctValue: string | null = raw.headers.get('Content-Type');
        const ct: MediaType | null = ctValue === null ? null : MediaType.parse(ctValue);
        return new Response(request, Protocol.HTTP_1_1, raw.code, raw.message, raw.headers,
          new ResponseBody(ct, raw.body));
      } catch (e) {
        this._activeConns.delete(c);
        unsubConnAbort();
        c.close();
        throw toNetworkError(e as Object);
      }
    } catch (e) {
      if (callTimedOut) {
        throw new Error('timeout');
      }
      throw toNetworkError(e as Object);
    } finally {
      if (callTimer !== -1) {
        clearTimeout(callTimer);
      }
      unsubParentAbort();
    }
  }

  private takeSocket(key: string): Conn | null {
    const taken: CloseableSocket | null = this._pool.takeIdleConn(key);
    if (taken === null) {
      return null;
    }
    const c: Conn = taken as Conn;
    c.offAll();
    if (c.isClosed()) {
      return null;
    }
    return c;
  }

  private returnSocket(key: string, c: Conn): void {
    c.offAll();
    c.onClose((): void => {
      this._pool.removeIdleConn(c);
    });
    c.onError((): void => {
      this._pool.removeIdleConn(c);
    });
    this._pool.putIdle(key, c);
  }

  private async connect(
    urlHost: string,
    connectHost: string,
    port: number,
    isTls: boolean,
    proxy: Proxy | null,
    connectTimeoutMs: number,
    readTimeoutMs: number,
    skipValidation: boolean,
    abort: CallAbortController
  ): Promise<Conn> {
    if (abort.isAborted()) {
      throw new Error('Canceled');
    }

    // 1) HTTP 代理分支：plain HTTP 直连代理发绝对 URI；HTTPS 先 CONNECT 再构造 TLSSocket
    if (proxy !== null && proxy.type() === ProxyType.HTTP) {
      const proxyAddr: socket.NetAddress = Http1SocketTransport.netAddressOf(
        proxy.address(), proxy.port());
      const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
      const tcpOptions: socket.TCPConnectOptions = { address: proxyAddr, timeout: connectTimeoutMs };
      await Http1SocketTransport.guardAsync(
        tcp.connect(tcpOptions), connectTimeoutMs, abort, 'connect', (): void => {
          try {
            tcp.close();
          } catch (ignored) {
            // 忽略关闭错误
          }
        });
      if (!isTls) {
        return Conn.ofTcp(tcp);
      }
      const tcpConn: Conn = Conn.ofTcp(tcp);
      const authorityHost: string = Http1SocketTransport.formatAuthorityHost(urlHost);
      const connectWire: ArrayBuffer = utf8Encode(
        `CONNECT ${authorityHost}:${port} HTTP/1.1\r\nHost: ${authorityHost}:${port}\r\n\r\n`);
      const tunnelReader: ResponseReadHandle = Http1SocketTransport.beginReadResponse(
        tcpConn, readTimeoutMs, true, true, abort);
      tunnelReader.promise.catch((): void => {});
      try {
        await Http1SocketTransport.sendWithGuard(tcpConn, connectWire, connectTimeoutMs, abort);
        tunnelReader.startTimer();
        const tunnelResp: RawResponse = await tunnelReader.promise;
        if (tunnelResp.code < 200 || tunnelResp.code >= 300) {
          throw new Error(`Proxy CONNECT failed: HTTP ${tunnelResp.code} ${tunnelResp.message}`);
        }
        tcpConn.offAll();
      } catch (e) {
        tcpConn.close();
        throw toNetworkError(e as Object);
      }

      const tls: socket.TLSSocket = socket.constructTLSSocketInstance(tcp);
      const targetAddr: socket.NetAddress = Http1SocketTransport.netAddressOf(connectHost, port);
      const secure: socket.TLSSecureOptions = {};
      const tlsOptions: socket.TLSConnectOptions = {
        address: targetAddr,
        secureOptions: secure,
        ALPNProtocols: ['http/1.1'],
        skipRemoteValidation: skipValidation
      };
      await Http1SocketTransport.guardAsync(
        tls.connect(tlsOptions), connectTimeoutMs, abort, 'tls connect', (): void => {
          try {
            tls.close();
          } catch (ignored) {
            // 忽略关闭错误
          }
          try {
            tcp.close();
          } catch (ignored) {
            // 忽略关闭错误
          }
        });
      return Conn.ofTls(tls, false);
    }

    // 2) 直连 / SOCKS5 代理分支
    const targetAddr: socket.NetAddress = Http1SocketTransport.netAddressOf(connectHost, port);
    let proxyOptions: socket.ProxyOptions | undefined = undefined;
    if (proxy !== null && proxy.type() === ProxyType.SOCKS) {
      proxyOptions = {
        type: socket.ProxyTypes.SOCKS5,
        address: Http1SocketTransport.netAddressOf(proxy.address(), proxy.port())
      };
    }

    if (isTls) {
      const tls: socket.TLSSocket = socket.constructTLSSocketInstance();
      const secure: socket.TLSSecureOptions = {};
      const tlsOptions: socket.TLSConnectOptions = {
        address: targetAddr,
        secureOptions: secure,
        ALPNProtocols: ['http/1.1'],
        skipRemoteValidation: skipValidation,
        proxy: proxyOptions
      };
      await Http1SocketTransport.guardAsync(
        tls.connect(tlsOptions), connectTimeoutMs, abort, 'tls connect', (): void => {
          try {
            tls.close();
          } catch (ignored) {
            // 忽略关闭错误
          }
        });
      return Conn.ofTls(tls, false);
    }

    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    const tcpOptions: socket.TCPConnectOptions = {
      address: targetAddr,
      timeout: connectTimeoutMs,
      proxy: proxyOptions
    };
    await Http1SocketTransport.guardAsync(
      tcp.connect(tcpOptions), connectTimeoutMs, abort, 'connect', (): void => {
        try {
          tcp.close();
        } catch (ignored) {
          // 忽略关闭错误
        }
      });
    return Conn.ofTcp(tcp);
  }

  private static sendWithGuard(conn: Conn, wire: ArrayBuffer, writeTimeoutMs: number,
    abort: CallAbortController): Promise<void> {
    return Http1SocketTransport.guardAsync(
      conn.send(wire), writeTimeoutMs, abort, 'write', (): void => {
        conn.close();
      });
  }

  private static guardAsync<T>(op: Promise<T>, timeoutMs: number, abort: CallAbortController,
    phase: string, onInterrupt: () => void): Promise<T> {
    if (abort.isAborted()) {
      onInterrupt();
      return Promise.reject(new Error('Canceled'));
    }
    return new Promise<T>((resolve, reject) => {
      let settled: boolean = false;
      let timer: number = -1;
      let unsub: () => void = (): void => {};

      const cleanup = (): void => {
        if (timer !== -1) {
          clearTimeout(timer);
          timer = -1;
        }
        unsub();
      };

      unsub = abort.onAbort((): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        onInterrupt();
        reject(new Error('Canceled'));
      });

      if (timeoutMs > 0) {
        timer = setTimeout((): void => {
          if (settled) {
            return;
          }
          settled = true;
          cleanup();
          onInterrupt();
          reject(new Error(`${phase} timeout after ${timeoutMs}ms`));
        }, timeoutMs) as number;
      }

      op.then((val: T): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        resolve(val);
      }).catch((e: Object): void => {
        if (settled) {
          hilog.debug(0x0000, 'Http1SocketTransport', 'late %{public}s error after settle: %{public}s',
            phase, describeNetworkError(e));
          return;
        }
        settled = true;
        cleanup();
        reject(toNetworkError(e, phase));
      });
    });
  }

  /**
   * 读一条完整响应：先注册监听再由调用方发送请求，支持跳过 1xx 临时响应、
   * Content-Length / 增量 O(N) chunked / 连接关闭定界。
   */
  private static beginReadResponse(
    conn: Conn,
    readTimeoutMs: number,
    headOnly: boolean,
    connectOnly: boolean,
    abort: CallAbortController,
    onProgress?: TransportProgressCallback
  ): ResponseReadHandle {
    const buf: ChunkBuffer = new ChunkBuffer();
    let parsed: RawResponse | null = null;
    let chunked: boolean = false;
    let contentLength: number = -1;
    let chunkedParser: ChunkedStreamParser | null = null;
    let timer: number = -1;
    let closeGraceTimer: number = -1;
    let settled: boolean = false;
    let timerStarted: boolean = false;
    let reportedBodyBytes: number = 0;
    let progressHeaderNotified: boolean = false;
    let unsubAbort: () => void = (): void => {};
    let resolveFn: (r: RawResponse) => void = (): void => {};
    let rejectFn: (e: Error) => void = (): void => {};

    const emitProgress = (total: number, received: number, delta: number): void => {
      if (onProgress !== undefined) {
        onProgress(total, received, delta);
      }
    };

    const cleanup = (): void => {
      if (timer !== -1) {
        clearTimeout(timer);
        timer = -1;
      }
      if (closeGraceTimer !== -1) {
        clearTimeout(closeGraceTimer);
        closeGraceTimer = -1;
      }
      unsubAbort();
      conn.offAll();
    };

    const finish = (r: RawResponse): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      resolveFn(r);
    };

    const fail = (e: Error): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      rejectFn(e);
    };

    const processAvailable = (): void => {
      while (!settled) {
        if (parsed === null) {
          const headerEnd: number = buf.indexOfCrlfCrlf();
          if (headerEnd < 0) {
            return;
          }
          const headerBytes: Uint8Array = buf.sliceHeader(headerEnd);
          let head: RawResponse;
          try {
            head = Http1SocketTransport.parseHead(headerBytes, headerEnd);
          } catch (e) {
            fail(e as Error);
            return;
          }
          buf.consume(headerEnd + 4);

          // 跳过 1xx 临时响应（如 100 Continue / 103 Early Hints），继续读取后续真实响应
          if (head.code >= 100 && head.code < 200) {
            parsed = null;
            continue;
          }

          parsed = head;
          if (connectOnly || headOnly || head.code === 204 || head.code === 304) {
            head.body = new ArrayBuffer(0);
            finish(head);
            return;
          }
          const te: string | null = head.headers.get('Transfer-Encoding');
          chunked = te !== null && te.toLowerCase().indexOf('chunked') >= 0;
          if (chunked) {
            chunkedParser = new ChunkedStreamParser();
          } else {
            const cl: string | null = head.headers.get('Content-Length');
            if (cl !== null && /^\d+$/.test(cl.trim())) {
              contentLength = Number.parseInt(cl.trim(), 10);
            } else {
              contentLength = -1;
            }
          }
        }

        const p: RawResponse = parsed as RawResponse;
        if (chunked) {
          try {
            const body: ArrayBuffer | null = (chunkedParser as ChunkedStreamParser).feed(buf);
            if (body === null) {
              return;
            }
            p.body = body;
            finish(p);
            return;
          } catch (e) {
            fail(e as Error);
            return;
          }
        }
        if (contentLength >= 0) {
          if (p.code >= 200 && p.code < 300 && contentLength > 0) {
            const cur: number = Math.min(buf.byteLength(), contentLength);
            if (!progressHeaderNotified || cur > reportedBodyBytes) {
              progressHeaderNotified = true;
              const delta: number = Math.max(0, cur - reportedBodyBytes);
              reportedBodyBytes = Math.max(reportedBodyBytes, cur);
              emitProgress(contentLength, reportedBodyBytes, delta);
            }
          }
          if (buf.byteLength() < contentLength) {
            return;
          }
          p.body = buf.takeBytes(contentLength);
          finish(p);
          return;
        }
        // 无定界：等连接关闭
        return;
      }
    };

    const promise: Promise<RawResponse> = new Promise<RawResponse>((resolve, reject) => {
      resolveFn = resolve;
      rejectFn = reject;

      if (abort.isAborted()) {
        settled = true;
        conn.offAll();
        reject(new Error('Canceled'));
        return;
      }

      unsubAbort = abort.onAbort((): void => {
        fail(new Error('Canceled'));
      });

      conn.onMessage((value: socket.SocketMessageInfo) => {
        buf.append(new Uint8Array(value.message));
        processAvailable();
      });

      conn.onError((err: Object) => {
        fail(toNetworkError(err, 'socket error'));
      });

      conn.onClose(() => {
        if (conn instanceof Conn) {
          conn.markRemoteClosed();
        }
        const finalizeClose = (): void => {
          const p: RawResponse | null = parsed;
          if (p === null) {
            fail(new Error('connection closed before response headers'));
            return;
          }
          if (chunked) {
            fail(new Error('connection closed before chunked body completed'));
            return;
          }
          if (contentLength >= 0 && buf.byteLength() < contentLength) {
            fail(new Error(`truncated body: expected ${contentLength}, got ${buf.byteLength()}`));
            return;
          }
          p.body = buf.takeBytes(contentLength >= 0 ? contentLength : buf.byteLength());
          finish(p);
        };
        const pNow: RawResponse | null = parsed;
        if (pNow !== null && !chunked && (contentLength < 0 || buf.byteLength() >= contentLength)) {
          finalizeClose();
          return;
        }
        // Harmony @ohos.net.socket 的 close 与尾包 message 存在乱序/微任务时差，给 80ms 排水窗口再判失败
        if (closeGraceTimer !== -1) {
          clearTimeout(closeGraceTimer);
        }
        closeGraceTimer = setTimeout(() => {
          closeGraceTimer = -1;
          finalizeClose();
        }, 80) as number;
      });
    });

    const startTimer = (): void => {
      if (settled || timerStarted || readTimeoutMs <= 0) {
        return;
      }
      timerStarted = true;
      timer = setTimeout((): void => {
        fail(new Error(`read timeout after ${readTimeoutMs}ms`));
      }, readTimeoutMs) as number;
    };

    return new ResponseReadHandle(promise, startTimer);
  }

  static stripIpv6Brackets(host: string): string {
    const t: string = host.trim();
    if (t.startsWith('[') && t.endsWith(']')) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  private static formatAuthorityHost(host: string): string {
    const clean: string = Http1SocketTransport.stripIpv6Brackets(host);
    return clean.indexOf(':') >= 0 ? `[${clean}]` : clean;
  }

  static netAddressOf(host: string, port: number): socket.NetAddress {
    const clean: string = Http1SocketTransport.stripIpv6Brackets(host);
    if (clean.indexOf(':') >= 0) {
      return { address: clean, port: port, family: 2 };
    }
    if (InetValidator.isValidInet4Address(clean)) {
      return { address: clean, port: port, family: 1 };
    }
    return { address: clean, port: port };
  }

  static parseHead(b: Uint8Array, headerEnd: number): RawResponse {
    const text: string = decodeAscii(b, 0, headerEnd);
    const lines: string[] = text.split('\r\n');
    const statusLine: string = lines.length > 0 ? lines[0] : '';
    const m: RegExpMatchArray | null = statusLine.match(/^HTTP\/(\d)\.(\d)\s+(\d{3})(?:\s+(.*))?$/);
    if (m === null) {
      throw new Error(`bad status line: ${statusLine}`);
    }
    const names: string[] = [];
    const values: string[] = [];
    for (let i = 1; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.length === 0) {
        continue;
      }
      const colon: number = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      names.push(line.substring(0, colon).trim());
      values.push(line.substring(colon + 1).trim());
    }
    const r: RawResponse = new RawResponse();
    r.code = Number.parseInt(m[3], 10);
    r.message = m[4] === undefined ? '' : m[4];
    r.protocol = `http/${m[1]}.${m[2]}`;
    r.headers = new Headers(names, values);
    r.body = new ArrayBuffer(0);
    return r;
  }

  /** chunked 解码（严格校验十六进制块长、块尾 CRLF、消费全部 trailer）；未收完返回 complete=false，格式非法抛错。 */
  static decodeChunked(b: Uint8Array, start: number): ChunkedResult {
    const out: Uint8Array[] = [];
    let total: number = 0;
    let pos: number = start;
    while (true) {
      const lineEnd: number = indexOfCrlf(b, pos);
      if (lineEnd < 0) {
        return new ChunkedResult(false, null);
      }
      const sizeLine: string = decodeAscii(b, pos, lineEnd).split(';')[0].trim();
      if (!/^[0-9a-fA-F]+$/.test(sizeLine)) {
        throw new Error(`invalid chunk size: ${sizeLine}`);
      }
      const size: number = Number.parseInt(sizeLine, 16);
      if (Number.isNaN(size) || size < 0) {
        throw new Error(`invalid chunk size: ${sizeLine}`);
      }
      if (size === 0) {
        let trailerPos: number = lineEnd + 2;
        while (true) {
          const trailEnd: number = indexOfCrlf(b, trailerPos);
          if (trailEnd < 0) {
            return new ChunkedResult(false, null);
          }
          if (trailEnd === trailerPos) {
            break;
          }
          trailerPos = trailEnd + 2;
        }
        break;
      }
      const dataStart: number = lineEnd + 2;
      if (dataStart + size + 1 >= b.byteLength) {
        return new ChunkedResult(false, null);
      }
      if (b[dataStart + size] !== 13 || b[dataStart + size + 1] !== 10) {
        throw new Error('missing CRLF after chunk data');
      }
      out.push(b.subarray(dataStart, dataStart + size));
      total += size;
      pos = dataStart + size + 2;
    }
    const merged: Uint8Array = new Uint8Array(total);
    let off: number = 0;
    for (let i = 0; i < out.length; i++) {
      merged.set(out[i], off);
      off += out[i].byteLength;
    }
    return new ChunkedResult(true, merged.buffer as ArrayBuffer);
  }

  private static shouldKeepAlive(raw: RawResponse): boolean {
    const conn: string | null = raw.headers.get('Connection');
    if (conn !== null) {
      const lower: string = conn.toLowerCase();
      if (lower.indexOf('close') >= 0) {
        return false;
      }
      if (lower.indexOf('keep-alive') >= 0) {
        return true;
      }
    }
    return raw.protocol === 'http/1.1';
  }

  /** 序列化为 HTTP/1.1 报文（请求行 + 头 + CRLF + 体）；走明文 HTTP 代理时请求行写绝对 URI。 */
  static serialize(request: Request, absoluteUri: boolean = false): ArrayBuffer {
    const url = request.url();
    const target: string = absoluteUri
      ? url.toString()
      : (url.encodedPath() + (url.query() === null ? '' : `?${url.query()}`));
    const parts: string[] = [];
    parts.push(`${request.method()} ${target} HTTP/1.1\r\n`);
    const h: Headers = request.headers();
    let hasHost: boolean = false;
    let hasAcceptEncoding: boolean = false;
    for (let i = 0; i < h.size(); i++) {
      const name: string = h.name(i);
      if (name.toLowerCase() === 'host') {
        hasHost = true;
      }
      if (name.toLowerCase() === 'accept-encoding') {
        hasAcceptEncoding = true;
      }
      parts.push(`${name}: ${h.value(i)}\r\n`);
    }
    if (!hasHost) {
      const defaultPort: number = url.isHttps() ? 443 : 80;
      const hostLit: string = Http1SocketTransport.formatAuthorityHost(url.host());
      const hostValue: string = url.port() === defaultPort ? hostLit : `${hostLit}:${url.port()}`;
      parts.push(`Host: ${hostValue}\r\n`);
    }
    if (!hasAcceptEncoding) {
      parts.push('Accept-Encoding: identity\r\n');
    }
    parts.push('\r\n');
    const headBytes: ArrayBuffer = utf8Encode(parts.join(''));
    const body = request.body();
    if (body === null) {
      return headBytes;
    }
    const bodyBytes: ArrayBuffer = body.bytes();
    const out: Uint8Array = new Uint8Array(headBytes.byteLength + bodyBytes.byteLength);
    out.set(new Uint8Array(headBytes), 0);
    out.set(new Uint8Array(bodyBytes), headBytes.byteLength);
    return out.buffer as ArrayBuffer;
  }

  /** 关闭所有在飞与池化保活连接（客户端 close() 时调用）。 */
  closeAll(): void {
    this._activeConns.forEach((s: Conn): void => {
      s.close();
    });
    this._activeConns.clear();
    this._pool.evictAll();
  }
}

class ResponseReadHandle {
  readonly promise: Promise<RawResponse>;
  readonly startTimer: () => void;

  constructor(promise: Promise<RawResponse>, startTimer: () => void) {
    this.promise = promise;
    this.startTimer = startTimer;
  }
}

/** O(N) 分片缓冲：按接收顺序持有多块 Uint8Array，仅在需要边界解析/完成时合并。 */
class ChunkBuffer {
  private _chunks: Uint8Array[] = [];
  private _length: number = 0;

  append(chunk: Uint8Array): void {
    if (chunk.byteLength === 0) {
      return;
    }
    this._chunks.push(chunk);
    this._length += chunk.byteLength;
  }

  byteLength(): number {
    return this._length;
  }

  byteAt(index: number): number {
    let offset: number = index;
    for (let i = 0; i < this._chunks.length; i++) {
      const c: Uint8Array = this._chunks[i];
      if (offset < c.byteLength) {
        return c[offset];
      }
      offset -= c.byteLength;
    }
    return -1;
  }

  indexOfCrlf(from: number = 0): number {
    if (this._length - from < 2) {
      return -1;
    }
    let idx: number = 0;
    let prevByte: number = -1;
    for (let cIdx = 0; cIdx < this._chunks.length; cIdx++) {
      const c: Uint8Array = this._chunks[cIdx];
      for (let i = 0; i < c.byteLength; i++) {
        const cur: number = c[i];
        if (idx > from && prevByte === 13 && cur === 10) {
          return idx - 1;
        }
        prevByte = cur;
        idx++;
      }
    }
    return -1;
  }

  indexOfCrlfCrlf(): number {
    if (this._length < 4) {
      return -1;
    }
    let idx: number = 0;
    let b0: number = -1;
    let b1: number = -1;
    let b2: number = -1;
    for (let cIdx = 0; cIdx < this._chunks.length; cIdx++) {
      const c: Uint8Array = this._chunks[cIdx];
      for (let i = 0; i < c.byteLength; i++) {
        const b3: number = c[i];
        if (idx >= 3 && b0 === 13 && b1 === 10 && b2 === 13 && b3 === 10) {
          return idx - 3;
        }
        b0 = b1;
        b1 = b2;
        b2 = b3;
        idx++;
      }
    }
    return -1;
  }

  sliceHeader(length: number): Uint8Array {
    return new Uint8Array(this.takeBytes(length));
  }

  consume(n: number): void {
    if (n <= 0) {
      return;
    }
    if (n >= this._length) {
      this._chunks = [];
      this._length = 0;
      return;
    }
    let rem: number = n;
    while (rem > 0 && this._chunks.length > 0) {
      const first: Uint8Array = this._chunks[0];
      if (rem >= first.byteLength) {
        this._chunks.shift();
        this._length -= first.byteLength;
        rem -= first.byteLength;
      } else {
        this._chunks[0] = first.subarray(rem);
        this._length -= rem;
        rem = 0;
      }
    }
  }

  takeBytes(count: number): ArrayBuffer {
    const n: number = Math.min(count, this._length);
    const out: Uint8Array = new Uint8Array(n);
    let off: number = 0;
    for (let i = 0; i < this._chunks.length && off < n; i++) {
      const c: Uint8Array = this._chunks[i];
      const take: number = Math.min(c.byteLength, n - off);
      out.set(take === c.byteLength ? c : c.subarray(0, take), off);
      off += take;
    }
    return out.buffer as ArrayBuffer;
  }

  takeAscii(count: number): string {
    const u8: Uint8Array = new Uint8Array(this.takeBytes(count));
    return decodeAscii(u8, 0, u8.byteLength);
  }
}

/** 增量式 O(N) chunked 状态机，避免每包重扫/整包拷贝。 */
class ChunkedStreamParser {
  private _state: number = 0; // 0=NEED_SIZE, 1=NEED_DATA, 2=NEED_TRAILERS
  private _needBytes: number = 0;
  private _parts: Uint8Array[] = [];
  private _total: number = 0;

  feed(buf: ChunkBuffer): ArrayBuffer | null {
    while (true) {
      if (this._state === 0) {
        const lineEnd: number = buf.indexOfCrlf(0);
        if (lineEnd < 0) {
          return null;
        }
        const sizeLine: string = buf.takeAscii(lineEnd).split(';')[0].trim();
        if (!/^[0-9a-fA-F]+$/.test(sizeLine)) {
          throw new Error(`invalid chunk size: ${sizeLine}`);
        }
        const size: number = Number.parseInt(sizeLine, 16);
        if (Number.isNaN(size) || size < 0) {
          throw new Error(`invalid chunk size: ${sizeLine}`);
        }
        buf.consume(lineEnd + 2);
        if (size === 0) {
          this._state = 2;
        } else {
          this._needBytes = size;
          this._state = 1;
        }
      } else if (this._state === 1) {
        if (buf.byteLength() < this._needBytes + 2) {
          return null;
        }
        if (buf.byteAt(this._needBytes) !== 13 || buf.byteAt(this._needBytes + 1) !== 10) {
          throw new Error('missing CRLF after chunk data');
        }
        if (this._needBytes > 0) {
          this._parts.push(new Uint8Array(buf.takeBytes(this._needBytes)));
          this._total += this._needBytes;
        }
        buf.consume(this._needBytes + 2);
        this._needBytes = 0;
        this._state = 0;
      } else {
        const trailEnd: number = buf.indexOfCrlf(0);
        if (trailEnd < 0) {
          return null;
        }
        if (trailEnd === 0) {
          buf.consume(2);
          const merged: Uint8Array = new Uint8Array(this._total);
          let off: number = 0;
          for (let i = 0; i < this._parts.length; i++) {
            merged.set(this._parts[i], off);
            off += this._parts[i].byteLength;
          }
          return merged.buffer as ArrayBuffer;
        }
        buf.consume(trailEnd + 2);
      }
    }
  }
}

/** 原始响应（传输层内部结构）。 */
export class RawResponse {
  code: number = -1;
  message: string = '';
  protocol: string = 'http/1.1';
  headers: Headers = new Headers([], []);
  body: ArrayBuffer = new ArrayBuffer(0);
}

export class ChunkedResult {
  readonly complete: boolean;
  readonly body: ArrayBuffer | null;

  constructor(complete: boolean, body: ArrayBuffer | null) {
    this.complete = complete;
    this.body = body;
  }
}

function indexOfCrlf(b: Uint8Array, from: number): number {
  for (let i = from; i + 1 < b.byteLength; i++) {
    if (b[i] === 13 && b[i + 1] === 10) {
      return i;
    }
  }
  return -1;
}

/** HTTP 头是 ISO-8859-1 兼容的字节序列，逐字节转字符即可（UTF-8 头部在 e-hentai 不会出现）。 */
function decodeAscii(b: Uint8Array, start: number, end: number): string {
  let s: string = '';
  for (let i = start; i < end; i++) {
    s += String.fromCharCode(b[i]);
  }
  return s;
}
