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

import { hilog } from '@kit.PerformanceAnalysisKit';

import { CallAbortController, Chain, InterceptorEntry, RealInterceptorChain } from './Interceptor';
import { Request } from './Request';
import { Response } from './Response';

/**
 * okhttp3.Call / Callback 等价层。
 *
 * 上游用法：
 *   Call call = okHttpClient.newCall(request);
 *   Response response = call.execute();          ← 60+ 处，全部同步
 *   task.setCall(call); ... task.cancel 时 call.cancel()   ← EhClient.Task / EhEngine
 * 以及 download 模块的 enqueue(Callback)（本层的 Callback 与 OkHttp 同名同签名）。
 *
 * 关键语义差异（ArkTS 无同步网络 IO，重构方案 §5 第 4 条）：
 *   execute(): Response   → execute(): Promise<Response>
 *   调用点写 `Response response = await call.execute();`
 *   取消语义保持：cancel() 置标志，链上每个 proceed 前检查；已在飞的传输由
 *   destroy()/close() 打断（引擎负责）。
 */
export interface Callback {
  onFailure(call: Call, e: Error): void;

  onResponse(call: Call, response: Response): void;
}

/** okhttp3.Call 等价抽象。 */
/** 日志域（项目统一 0x0000）与 TAG。 */
const DOMAIN: number = 0x0000;
const TAG: string = 'okhttp.Call';

export abstract class Call {
  abstract request(): Request;

  /** 同步语义保留，执行方式异步（调用点 await）。 */
  abstract execute(): Promise<Response>;

  abstract enqueue(callback: Callback): void;

  abstract cancel(): void;

  abstract isCanceled(): boolean;

  abstract isExecuted(): boolean;

  abstract clone(): Call;
}

/** okhttp3.RealCall 等价。 */
export class RealCall extends Call {
  private readonly _request: Request;
  private readonly _entries: InterceptorEntry[];
  private _executed: boolean = false;
  private _canceled: boolean = false;
  private _timedOut: boolean = false;
  private _chain: RealInterceptorChain | null = null;
  private readonly _onCancel: (() => void) | null;
  private readonly _abortController: CallAbortController | null;
  private readonly _callTimeoutMs: number;
  private readonly _entriesFactory: ((abort: CallAbortController) => InterceptorEntry[]) | null;

  constructor(
    request: Request,
    entries: InterceptorEntry[],
    onCancel: (() => void) | null = null,
    abortController: CallAbortController | null = null,
    callTimeoutMs: number = 0,
    entriesFactory: ((abort: CallAbortController) => InterceptorEntry[]) | null = null
  ) {
    super();
    this._request = request;
    this._entries = entries;
    this._onCancel = onCancel;
    this._abortController = abortController;
    this._callTimeoutMs = callTimeoutMs;
    this._entriesFactory = entriesFactory;
  }

  request(): Request {
    return this._request;
  }

  async execute(): Promise<Response> {
    if (this._executed) {
      throw new Error('Already Executed');
    }
    this._executed = true;
    if (this._canceled) {
      throw new Error('Canceled');
    }
    const abort: CallAbortController = this._abortController !== null
      ? this._abortController : new CallAbortController();
    const chain: RealInterceptorChain = new RealInterceptorChain(
      this._entries, 0, this._request, null, abort);
    this._chain = chain;

    let timer: number = -1;
    if (this._callTimeoutMs > 0) {
      timer = setTimeout((): void => {
        this._timedOut = true;
        this.cancel();
      }, this._callTimeoutMs) as number;
    }

    try {
      const resp: Response = await chain.proceed(this._request);
      if (this._timedOut) {
        resp.close();
        throw new Error('timeout');
      }
      return resp;
    } catch (e) {
      if (this._timedOut) {
        throw new Error('timeout');
      }
      throw e as Error;
    } finally {
      if (timer !== -1) {
        clearTimeout(timer);
      }
    }
  }

  /**
   * 对齐 enqueue(Callback)：结果通过回调返回，失败走 onFailure。
   * ArkTS 里等价于「发起一个不阻塞调用方的 Promise 链」，
   * 回调在微任务里执行，与 OkHttp 的 Dispatcher 线程池语义差异见 MR。
   */
  enqueue(callback: Callback): void {
    if (this._executed) {
      throw new Error('Already Executed');
    }
    this.execute().then((response: Response) => {
      try {
        callback.onResponse(this, response);
      } catch (e) {
        callback.onFailure(this, e as Error);
      }
    }).catch((e: Error) => {
      // 低危：错误**照旧转交** `callback.onFailure`（OkHttp 同语义），上层一定会再报一次。
      // 这里补 debug 级痕迹，只为"日志能对上调用方看到的失败"，不用 error 级避免与上层重复刷屏。
      hilog.debug(DOMAIN, TAG, 'call failed, dispatch to onFailure: url=%{public}s, err=%{public}s',
        this._request.url().toString(), e.message);
      callback.onFailure(this, e);
    });
  }

  cancel(): void {
    this._canceled = true;
    if (this._chain !== null) {
      this._chain.markCancelled();
    }
    if (this._abortController !== null) {
      this._abortController.abort();
    }
    if (this._onCancel !== null) {
      this._onCancel();
    }
  }

  isCanceled(): boolean {
    return this._canceled;
  }

  isExecuted(): boolean {
    return this._executed;
  }

  clone(): Call {
    if (this._entriesFactory !== null) {
      const freshAbort: CallAbortController = new CallAbortController();
      const freshEntries: InterceptorEntry[] = this._entriesFactory(freshAbort);
      return new RealCall(this._request, freshEntries, this._onCancel,
        freshAbort, this._callTimeoutMs, this._entriesFactory);
    }
    const freshAbort: CallAbortController | null = this._abortController !== null
      ? new CallAbortController() : null;
    return new RealCall(this._request, this._entries, this._onCancel,
      freshAbort, this._callTimeoutMs, null);
  }
}
