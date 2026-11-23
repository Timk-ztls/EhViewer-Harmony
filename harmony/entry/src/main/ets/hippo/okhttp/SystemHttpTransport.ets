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

import http from '@ohos.net.http';
import util from '@ohos.util';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { InetAddress, describeNetworkError, toNetworkError } from './Dns';
import { Headers } from './Headers';
import { CallAbortController } from './Interceptor';
import { MediaType } from './MediaType';
import { Proxy, ProxyType } from './ProxySelector';
import { Protocol, Response } from './Response';
import { ResponseBody } from './ResponseBody';
import { Request } from './Request';
import { MultipartBody } from './MultipartBody';

/** 传输层接收字节进度回调（contentLength 未知时为 -1）。 */
export type TransportProgressCallback =
  (contentLength: number, receivedSize: number, bytesRead: number) => void;

/** 传输执行附加参数（保持 execute 现有三参向后兼容）。 */
export interface TransportExecuteOptions {
  writeTimeoutMs?: number;
  callTimeoutMs?: number;
  abort?: CallAbortController | null;
  proxy?: Proxy | null;
  resolvedAddress?: InetAddress | null;
  skipRemoteValidation?: boolean;
  onProgress?: TransportProgressCallback;
}

/**
 * 传输层接口：拦截器链的「最后一跳」。
 * OkHttp 的 CallServerInterceptor 直接读写 socket；本层把这一跳抽象成 Transport，
 * 由 OkHttpClient 按 followRedirects / 代理 / DNS 覆写选择实现。
 */
export interface Transport {
  readonly name: string;

  execute(request: Request, connectTimeoutMs: number, readTimeoutMs: number,
    options?: TransportExecuteOptions): Promise<Response>;
}

const MAX_RESPONSE_LIMIT: number = 100 * 1024 * 1024;

/**
 * 基于 @ohos.net.http 的传输实现（系统网络栈）。
 *
 * 能力：HTTP/1.1 + HTTP/2（由系统栈协商）、TLS、gzip/br 自动解压、系统连接池。
 * 限制（决定了不能只用它）：
 *   1) 系统栈会自动跟随重定向，且 HttpRequestOptions 无开关 → followRedirects=false 的
 *      语义（EhEngine.imageSearch 依赖 302 + Location）无法实现；
 *   2) 不支持 SOCKS5、HTTP CONNECT 隧道与自定义 DNS IP 直连；
 *   3) 无法读取流式响应（result 一次性返回），大文件下载要靠 Range 分片。
 */
export class RedirectDetection {
  readonly wasRedirected: boolean;
  readonly location: string | null;

  constructor(wasRedirected: boolean, location: string | null) {
    this.wasRedirected = wasRedirected;
    this.location = location;
  }
}

export class SystemHttpTransport implements Transport {
  readonly name: string = 'ohos.net.http';

  async execute(request: Request, connectTimeoutMs: number, readTimeoutMs: number,
    options?: TransportExecuteOptions): Promise<Response> {
    const abort: CallAbortController | null =
      options !== undefined && options.abort !== undefined ? options.abort : null;
    if (abort !== null && abort.isAborted()) {
      throw new Error('Canceled');
    }

    const url: string = request.url().toString();
    const req: http.HttpRequest = http.createHttp();
    const header: Record<string, string> = SystemHttpTransport.buildRequestHeaders(request.headers());
    const callTimeoutMs: number =
      options !== undefined && options.callTimeoutMs !== undefined ? options.callTimeoutMs : 0;

    const httpOptions: http.HttpRequestOptions = {
      method: SystemHttpTransport.methodOf(request.method()),
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false,
      connectTimeout: connectTimeoutMs,
      readTimeout: readTimeoutMs,
      maxLimit: MAX_RESPONSE_LIMIT,
      extraData: SystemHttpTransport.bytesOf(request)
    };

    const proxy: Proxy | null = options !== undefined && options.proxy !== undefined ? options.proxy : null;
    if (proxy !== null) {
      if (proxy.type() === ProxyType.DIRECT) {
        httpOptions.usingProxy = !proxy.isNoProxy();
      } else if (proxy.type() === ProxyType.HTTP) {
        const hp: http.HttpProxy = {
          host: proxy.address(),
          port: proxy.port(),
          exclusionList: []
        };
        httpOptions.usingProxy = hp;
      }
    } else {
      httpOptions.usingProxy = true;
    }

    if (options !== undefined && options.skipRemoteValidation === true) {
      httpOptions.remoteValidation = 'skip';
    }

    let settled: boolean = false;
    let pendingRedirectLoc: string | null = null;
    let capturedRedirected: boolean = false;
    let capturedLocation: string | null = null;
    let headersHandler: ((raw: Object) => void) | null = (raw: Object): void => {
      if (settled) {
        return;
      }
      if (pendingRedirectLoc !== null) {
        capturedRedirected = true;
        if (capturedLocation === null) {
          capturedLocation = pendingRedirectLoc;
        }
      }
      pendingRedirectLoc = SystemHttpTransport.extractLocationHeader(raw);
    };
    try {
      req.on('headersReceive', headersHandler);
    } catch (e) {
      hilog.debug(0x0000, 'SystemHttpTransport', 'on headersReceive unavailable: %{public}s',
        describeNetworkError(e as Object));
      headersHandler = null;
    }

    let timer: number = -1;
    let unsub: () => void = (): void => {};
    const onProgress: TransportProgressCallback | undefined =
      options !== undefined ? options.onProgress : undefined;
    let lastReportedSize: number = 0;
    let progressHandler: ((info: http.DataReceiveProgressInfo) => void) | null = null;
    if (onProgress !== undefined) {
      progressHandler = (info: http.DataReceiveProgressInfo): void => {
        if (settled) {
          return;
        }
        const total: number =
          (typeof info.totalSize === 'number' && Number.isFinite(info.totalSize) && info.totalSize > 0)
            ? info.totalSize
            : -1;
        const received: number =
          (typeof info.receiveSize === 'number' && Number.isFinite(info.receiveSize) && info.receiveSize >= 0)
            ? info.receiveSize
            : 0;
        const delta: number = Math.max(0, received - lastReportedSize);
        if (received > lastReportedSize) {
          lastReportedSize = received;
        }
        onProgress(total, received, delta);
      };
      try {
        req.on('dataReceiveProgress', progressHandler);
      } catch (e) {
        hilog.debug(0x0000, 'SystemHttpTransport', 'on dataReceiveProgress unavailable: %{public}s',
          describeNetworkError(e as Object));
        progressHandler = null;
      }
    }

    try {
      const resp: http.HttpResponse = await new Promise<http.HttpResponse>((resolve, reject) => {
        const failWith = (err: Error): void => {
          if (settled) {
            return;
          }
          settled = true;
          try {
            req.destroy();
          } catch (ignored) {
            // 销毁失败忽略
          }
          reject(err);
        };

        if (abort !== null) {
          unsub = abort.onAbort((): void => {
            failWith(new Error('Canceled'));
          });
        }
        if (callTimeoutMs > 0) {
          timer = setTimeout((): void => {
            failWith(new Error('timeout'));
          }, callTimeoutMs) as number;
        }

        req.request(url, httpOptions).then((r: http.HttpResponse): void => {
          if (settled) {
            return;
          }
          settled = true;
          resolve(r);
        }).catch((e: Object): void => {
          if (settled) {
            hilog.debug(0x0000, 'SystemHttpTransport', 'late request error after settle: %{public}s',
              describeNetworkError(e));
            return;
          }
          settled = true;
          reject(toNetworkError(e, 'http'));
        });
      });

      const rawHeaders: Headers = SystemHttpTransport.headersOf(resp.header);
      const outHeaders: Headers = SystemHttpTransport.stripInflatedHeaders(rawHeaders);
      const body: ArrayBuffer = SystemHttpTransport.resultOf(resp.result);
      const ctValue: string | null = outHeaders.get('Content-Type');
      const ct: MediaType | null = ctValue === null ? null : MediaType.parse(ctValue);
      const code: number = resp.responseCode as number;
      const timingRedirected: boolean = resp.performanceTiming !== undefined &&
        resp.performanceTiming !== null &&
        typeof resp.performanceTiming.redirectTiming === 'number' &&
        resp.performanceTiming.redirectTiming > 0;
      const redir: RedirectDetection = SystemHttpTransport.detectRedirect(
        code, outHeaders, capturedRedirected, capturedLocation, timingRedirected
      );
      return new Response(request, Protocol.HTTP_1_1, code,
        SystemHttpTransport.reasonOf(code), outHeaders,
        new ResponseBody(ct, body), null, Date.now(), redir.wasRedirected, redir.location);
    } finally {
      if (timer !== -1) {
        clearTimeout(timer);
      }
      unsub();
      if (headersHandler !== null) {
        try {
          req.off('headersReceive', headersHandler);
        } catch (e) {
          hilog.debug(0x0000, 'SystemHttpTransport', 'off headersReceive failed: %{public}s',
            describeNetworkError(e as Object));
        }
        headersHandler = null;
      }
      if (progressHandler !== null) {
        try {
          req.off('dataReceiveProgress', progressHandler);
        } catch (e) {
          hilog.debug(0x0000, 'SystemHttpTransport', 'off dataReceiveProgress failed: %{public}s',
            describeNetworkError(e as Object));
        }
        progressHandler = null;
      }
      try {
        req.destroy();
      } catch (ignored) {
        // 销毁失败忽略
      }
    }
  }

  /** 聚合同名多值请求头（大小写不敏感），并在未显式指定 Accept-Encoding 时补 gzip。 */
  static buildRequestHeaders(h: Headers): Record<string, string> {
    const firstNames: Map<string, string> = new Map<string, string>();
    const grouped: Map<string, string[]> = new Map<string, string[]>();
    for (let i = 0; i < h.size(); i++) {
      const name: string = h.name(i);
      const lower: string = name.toLowerCase();
      if (!firstNames.has(lower)) {
        firstNames.set(lower, name);
      }
      let list: string[] | undefined = grouped.get(lower);
      if (list === undefined) {
        list = [];
        grouped.set(lower, list);
      }
      list.push(h.value(i));
    }
    const header: Record<string, string> = {};
    grouped.forEach((values: string[], lower: string): void => {
      const key: string = firstNames.get(lower) as string;
      const sep: string = lower === 'cookie' ? '; ' : ', ';
      header[key] = values.join(sep);
    });
    if (!grouped.has('accept-encoding')) {
      header['Accept-Encoding'] = 'gzip';
    }
    return header;
  }

  /** `@ohos.net.http` 已在内部完成解压，剥离残留的 Content-Encoding 与压缩前 Content-Length。 */
  static stripInflatedHeaders(headers: Headers): Headers {
    const ce: string | null = headers.get('Content-Encoding');
    if (ce === null || ce.trim().toLowerCase() === 'identity') {
      return headers;
    }
    return headers.newBuilder()
      .remove('Content-Encoding')
      .remove('Content-Length')
      .build();
  }

  private static methodOf(method: string): http.RequestMethod {
    switch (method) {
      case 'POST':
        return http.RequestMethod.POST;
      case 'PUT':
        return http.RequestMethod.PUT;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      case 'HEAD':
        return http.RequestMethod.HEAD;
      case 'OPTIONS':
        return http.RequestMethod.OPTIONS;
      case 'TRACE':
        return http.RequestMethod.TRACE;
      case 'CONNECT':
        return http.RequestMethod.CONNECT;
      default:
        return http.RequestMethod.GET;
    }
  }

  private static bytesOf(request: Request): string | ArrayBuffer | undefined {
    const body = request.body();
    if (body === null) {
      return undefined;
    }
    if (body instanceof MultipartBody) {
      return body.bytes();
    }
    return body.bytes();
  }

  static extractLocationHeader(raw: Object | null | undefined): string | null {
    if (raw === null || raw === undefined || typeof raw !== 'object') {
      return null;
    }
    const record: Record<string, Object> = raw as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (k.toLowerCase() !== 'location') {
        continue;
      }
      const v: Object = record[k];
      if (v instanceof Array) {
        const arr: string[] = v as string[];
        if (arr.length > 0 && typeof arr[0] === 'string' && arr[0].trim().length > 0) {
          return arr[0].trim();
        }
      } else if (typeof v === 'string' && (v as string).trim().length > 0) {
        return (v as string).trim();
      }
    }
    return null;
  }

  static detectRedirect(code: number, outHeaders: Headers, capturedRedirected: boolean,
    capturedLocation: string | null, timingRedirected: boolean): RedirectDetection {
    const isCodeRedirect: boolean = code >= 300 && code <= 399;
    const wasRedirected: boolean = isCodeRedirect || capturedRedirected || timingRedirected;
    const headerLoc: string | null = isCodeRedirect ? outHeaders.get('Location') : null;
    const loc: string | null = capturedLocation !== null ? capturedLocation : headerLoc;
    return new RedirectDetection(wasRedirected, loc);
  }

  /** `@ohos.net.http` 的响应头是 Object（值为 string | string[]），统一展开成多值 Headers。 */
  private static headersOf(raw: Object): Headers {
    const names: string[] = [];
    const values: string[] = [];
    const record: Record<string, Object> = raw as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const v: Object = record[key];
      if (v instanceof Array) {
        const arr: string[] = v as string[];
        for (let j = 0; j < arr.length; j++) {
          names.push(key);
          values.push(arr[j]);
        }
      } else {
        names.push(key);
        values.push(v === null || v === undefined ? '' : `${v}`);
      }
    }
    return new Headers(names, values);
  }

  private static resultOf(result: string | Object | ArrayBuffer): ArrayBuffer {
    if (result instanceof ArrayBuffer) {
      return result;
    }
    if (typeof result === 'string') {
      const s: string = result as string;
      const enc = new util.TextEncoder('utf-8');
      const u8: Uint8Array = enc.encodeInto(s);
      return u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength) as ArrayBuffer;
    }
    // 空响应
    return new ArrayBuffer(0);
  }

  /**
   * @ohos.net.http 不返回 reason phrase。HTML 解析链路不读 message，
   * 但 Response.message() 要给出与 HTTP 语义一致的值，否则日志与断言会漂。
   */
  static reasonOf(code: number): string {
    switch (code) {
      case 200:
        return 'OK';
      case 201:
        return 'Created';
      case 204:
        return 'No Content';
      case 301:
        return 'Moved Permanently';
      case 302:
        return 'Found';
      case 303:
        return 'See Other';
      case 304:
        return 'Not Modified';
      case 307:
        return 'Temporary Redirect';
      case 308:
        return 'Permanent Redirect';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 405:
        return 'Method Not Allowed';
      case 429:
        return 'Too Many Requests';
      case 500:
        return 'Internal Server Error';
      case 502:
        return 'Bad Gateway';
      case 503:
        return 'Service Unavailable';
      case 504:
        return 'Gateway Timeout';
      default:
        return '';
    }
  }
}

