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

import { Protocol, Response } from './Response';
import { Request } from './Request';

/**
 * okhttp3.Interceptor / Interceptor.Chain 等价层。
 *
 * 上游用法（EhApplication.getOkHttpClient / getImageOkHttpClient）：
 *   .addNetworkInterceptor(sprocket -> sprocket.proceed(sprocket.request()))
 *   .addNetworkInterceptor(chain -> {
 *       Response response = chain.proceed(chain.request());
 *       for (String header : response.headers("Set-Cookie")) { ...WebView 同步... }
 *       return response;
 *   })
 * 即：网络拦截器能看到「服务端原始响应头」（含 Set-Cookie），应用拦截器看缓存后的结果。
 *
 * 差异：OkHttp 的 intercept(Chain) 返回 Response（同步阻塞）。
 * 本层的 Chain.proceed() 返回 Promise<Response>，拦截器实现必须 async/await ——
 * 这是 ArkTS「网络必须异步」的硬约束（重构方案 §5 第 4 条），
 * 拦截器语义（顺序、短路、改写请求/响应）完全保留。
 */
export interface Interceptor {
  intercept(chain: Chain): Promise<Response>;
}

/** 连接信息，对应 okhttp3.Connection（只保留拦截器会用到的面）。 */
export class Connection {
  private readonly _protocol: Protocol;
  private readonly _routeHost: string;
  private readonly _routePort: number;

  constructor(protocol: Protocol, routeHost: string, routePort: number) {
    this._protocol = protocol;
    this._routeHost = routeHost;
    this._routePort = routePort;
  }

  protocol(): Protocol {
    return this._protocol;
  }

  routeHost(): string {
    return this._routeHost;
  }

  routePort(): number {
    return this._routePort;
  }

  toString(): string {
    return `${this._protocol} ${this._routeHost}:${this._routePort}`;
  }
}

/** okhttp3.Interceptor.Chain 等价。 */
export interface Chain {
  request(): Request;

  proceed(request: Request): Promise<Response>;

  connection(): Connection | null;

  /** 中断当前调用（对应 OkHttp 的 call.cancel()）。 */
  isCancelled(): boolean;
}

/** 责任链节点：一个拦截器 + 下一跳。 */
export class InterceptorEntry {
  readonly interceptor: Interceptor;
  readonly index: number;

  constructor(interceptor: Interceptor, index: number) {
    this.interceptor = interceptor;
    this.index = index;
  }
}

/** 取消信号控制器，用于将 Call.cancel() / callTimeout 实时传递给正在飞行的传输层。 */
export class CallAbortController {
  private _aborted: boolean = false;
  private _listeners: Array<() => void> = [];

  isAborted(): boolean {
    return this._aborted;
  }

  onAbort(listener: () => void): () => void {
    if (this._aborted) {
      listener();
      return (): void => {};
    }
    this._listeners.push(listener);
    return (): void => {
      const idx: number = this._listeners.indexOf(listener);
      if (idx >= 0) {
        this._listeners.splice(idx, 1);
      }
    };
  }

  abort(): void {
    if (this._aborted) {
      return;
    }
    this._aborted = true;
    const snapshot: Array<() => void> = this._listeners.slice();
    this._listeners = [];
    for (let i = 0; i < snapshot.length; i++) {
      try {
        snapshot[i]();
      } catch (e) {
        // 清理监听异常不阻断其它取消回调
      }
    }
  }
}

/**
 * 真实拦截器链。
 * OkHttp 的链式顺序：应用拦截器(正序) → 重试/桥接/缓存 → 网络拦截器(正序) → 传输层(最后一跳)。
 * 这里把「传输层」抽象成 TerminalInterceptor，由 OkHttpClient 注入。
 */
export class RealInterceptorChain implements Chain {
  private readonly _interceptors: InterceptorEntry[];
  private readonly _index: number;
  private readonly _request: Request;
  private readonly _connection: Connection | null;
  private readonly _abort: CallAbortController | null;
  private _cancelled: boolean = false;

  constructor(interceptors: InterceptorEntry[], index: number, request: Request,
    connection: Connection | null = null, abort: CallAbortController | null = null) {
    this._interceptors = interceptors;
    this._index = index;
    this._request = request;
    this._connection = connection;
    this._abort = abort;
  }

  request(): Request {
    return this._request;
  }

  connection(): Connection | null {
    return this._connection;
  }

  abortController(): CallAbortController | null {
    return this._abort;
  }

  isCancelled(): boolean {
    return this._cancelled || (this._abort !== null && this._abort.isAborted());
  }

  markCancelled(): void {
    this._cancelled = true;
    if (this._abort !== null) {
      this._abort.abort();
    }
  }

  async proceed(request: Request): Promise<Response> {
    if (this.isCancelled()) {
      throw new Error('Canceled');
    }
    if (this._index >= this._interceptors.length) {
      throw new Error('No more interceptors (missing terminal transport interceptor)');
    }
    const next: RealInterceptorChain = new RealInterceptorChain(
      this._interceptors, this._index + 1, request, this._connection, this._abort);
    next._cancelled = this._cancelled;
    return next._interceptors[this._index].interceptor.intercept(next);
  }
}

/** 便于 lambda 风格写法的适配器（ArkTS 支持 lambda 实现接口方法，这里显式给个包装）。 */
export class LambdaInterceptor implements Interceptor {
  private readonly fn: (chain: Chain) => Promise<Response>;

  constructor(fn: (chain: Chain) => Promise<Response>) {
    this.fn = fn;
  }

  intercept(chain: Chain): Promise<Response> {
    return this.fn(chain);
  }
}
