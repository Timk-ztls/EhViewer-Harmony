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

import { CancelledException } from './exception/MarkerExceptions';
import { EhException } from './exception/EhException';
import { ParseException } from './exception/ParseException';
import { EhSignInResult } from './EhSignInResult';
import { StatusCodeException } from '../../network/StatusCodeException';
import { EhConfig } from './EhConfig';
import { EhCallbackLike, EhRequest, TaskLike } from './EhRequest';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhClient.java
 * （inventory S0070，254 行）
 *
 * 请求调度器：把 `EhRequest` 变成一次后台执行 + 回调。上游用 `AsyncTask` + `ThreadPoolExecutor`
 * （`IoThreadPoolExecutor`），本层用 Promise + 可注入 `Scheduler`。
 *
 * 三条**必须照搬**的生命周期语义（这是本类的真正内容，而不是 dispatch 表）：
 *   1. `execute()` 时若已 cancel → **直接 onCancel**，不建 Task
 *   2. `Task.stop()` 幂等：只第一次生效，置 stop → 回调 onCancel → 清 callback/config/call
 *      并且 `setCall()` 在 stop 之后调用会抛 `CancelledException`（防止「已取消还挂新请求」）
 *   3. `onPostExecute`：结果是 `CancelledException` → **什么都不做**（onCancel 已在 stop 里发过）；
 *      是其它 Throwable → onFailure；否则 onSuccess
 *
 * METHOD_* 常量与上游逐字一致（注意有 27/28 两个「后补」的编号，不是连续的）。
 */
/** 日志域（与项目其他模块保持 0x0000 默认域一致）。 */
const DOMAIN: number = 0x0000;
/** 日志 TAG（文件级；类里的 `EhClient.TAG` 是给调用方用的标签名，两者取值相同但用途不同）。 */
const TAG: string = 'EhClient';

export class EhClient {
  static readonly TAG: string = 'EhClient';

  static readonly METHOD_SIGN_IN: number = 0;
  static readonly METHOD_GET_GALLERY_LIST: number = 1;
  static readonly METHOD_GET_GALLERY_DETAIL: number = 3;
  static readonly METHOD_GET_PREVIEW_SET: number = 4;
  static readonly METHOD_GET_RATE_GALLERY: number = 5;
  static readonly METHOD_GET_COMMENT_GALLERY: number = 6;
  static readonly METHOD_GET_GALLERY_TOKEN: number = 7;
  static readonly METHOD_GET_FAVORITES: number = 8;
  static readonly METHOD_ADD_FAVORITES: number = 9;
  static readonly METHOD_ADD_FAVORITES_RANGE: number = 10;
  static readonly METHOD_MODIFY_FAVORITES: number = 11;
  static readonly METHOD_GET_TORRENT_LIST: number = 12;
  static readonly METHOD_GET_TOP_LIST: number = 13;
  static readonly METHOD_GET_PROFILE: number = 14;
  static readonly METHOD_VOTE_COMMENT: number = 15;
  static readonly METHOD_IMAGE_SEARCH: number = 16;
  static readonly METHOD_ARCHIVE_LIST: number = 17;
  static readonly METHOD_ARCHIVER: number = 27;
  static readonly METHOD_DOWNLOAD_ARCHIVE: number = 18;
  static readonly METHOD_DOWNLOAD_ARCHIVER: number = 28;
  static readonly METHOD_ADD_TAG: number = 20;
  static readonly METHOD_EDIT_WATCHED: number = 21;
  static readonly METHOD_DELETE_WATCHED: number = 22;
  static readonly METHOD_GET_WATCHED: number = 23;
  static readonly METHOD_GET_NEWS: number = 24;
  static readonly METHOD_GET_HOME: number = 25;
  static readonly METHOD_RESET_LIMIT: number = 26;
  static readonly METHOD_GET_EDIT_COMMENT: number = 29;

  private _dispatcher: MethodDispatcher;
  private _scheduler: Scheduler;

  constructor(dispatcher: MethodDispatcher, scheduler?: Scheduler) {
    this._dispatcher = dispatcher;
    this._scheduler = scheduler === undefined ? new MicrotaskScheduler() : scheduler;
  }

  /**
   * 账号密码登录（对齐上游 `EhClient.doChangeCall` 的 `METHOD_SIGN_IN` 分支 →
   * `EhEngine.signIn(task, client, username, password)`，返回**显示名**）。
   *
   * ## 上游对位（已查证 `EhEngine.java:170-205`）
   * ```
   * POST https://forums.e-hentai.org/index.php?act=Login&CODE=01     ← EhUrl.API_SIGN_IN
   * referer: https://forums.e-hentai.org/index.php?act=Login&CODE=00
   * origin : https://forums.e-hentai.org
   * body   : UserName=<u>&PassWord=<p>&submit=Log me in&CookieDate=1&temporary_https=off
   * 成功判据：响应 HTML 里 `<p>You are now logged in as: (.+?)<` → 捕获组 = 显示名
   * 失败判据：`<h4>The error returned was:</h4> <p>…</p>` 或 `<span class="postcolor">…</span>`
   *          → 抛 EhException（文案即错误原因，例如 "The entered email address or password is incorrect"）
   * 都不是 → ParseException("Can't parse sign in")
   * ```
   * **不是**看 cookie（`ipb_member_id` 是 WebView 登录路径的判据，不是账号密码路径的）。
   *
   * ## 头像
   * 上游登录成功后由 UI 再取一次 profile（`getProfile`）拿显示名与头像；
   * 这里同样试取一次，**取不到不影响登录成功**（头像为空串）。
   */
  async signIn(username: string, password: string): Promise<EhSignInResult> {
    const task: Task = new Task(this._dispatcher, EhClient.METHOD_SIGN_IN, null, null,
      [username, password], this._scheduler);
    let displayName: string;
    try {
      const raw: Object = await this._dispatcher.invoke(task, EhClient.METHOD_SIGN_IN,
        [username, password]);
      displayName = raw as string;
    } catch (e) {
      return EhClient.mapSignInError(e);
    }
    let avatar: string = '';
    try {
      const profile: Object = await this._dispatcher.invoke(task, EhClient.METHOD_GET_PROFILE, []);
      const av: Object | null = (profile as Object as ProfileResultLike).avatar;
      avatar = av === null || av === undefined ? '' : av as string;
    } catch (e) {
      // 头像取不到不影响登录成功（上游同样：进设置页才拉头像）
    }
    return EhSignInResult.ok(displayName, avatar);
  }

  /**
   * 把 signIn 抛出的异常映射成稳定的 errorCode（码表见 `EhSignInResult` 类注释）。
   *
   * 注意 `ParseException` 的可达性：
   * - 若 `MethodDispatcher` 直接抛出 `ParseException`（如直接调 `SignInParser.parse` 或测试桩），
   *   此处会命中 `ERR_PARSE`（-3）。
   * - 若 `MethodDispatcher` 走 `EhEngine.signIn`（经 `runApi` → `doThrowException`），
   *   `doThrowException` 会把 `ParseException` 转成 `EhException`（`body` / `errorEmptyHtml` /
   *   `errorParseError`），此时会落入下方的 `ERR_CREDENTIAL`（-4），除非 dispatcher 保留或区分原始异常。
   */
  static mapSignInError(e: Object): EhSignInResult {
    const err: Error = e as Error;
    const message: string = err.message === undefined ? '' : err.message;
    if (e instanceof StatusCodeException) {
      const code: number = (e as StatusCodeException).getResponseCode();
      return EhSignInResult.fail(code, message);
    }
    if (e instanceof CancelledException) {
      return EhSignInResult.fail(EhSignInResult.ERR_UNAVAILABLE, message);
    }
    if (e instanceof ParseException) {
      return EhSignInResult.fail(EhSignInResult.ERR_PARSE, message);
    }
    if (e instanceof EhException) {
      // 注意顺序：ParseException extends EhException，所以 ParseException 必须在前
      return EhSignInResult.fail(EhSignInResult.ERR_CREDENTIAL, message);
    }
    return EhSignInResult.fail(EhSignInResult.ERR_OTHER, message);
  }

  /** 对齐 `execute(EhRequest)`：已取消就直接 onCancel，否则建 Task 并异步执行。 */
  execute(request: EhRequest): Task {
    const args: Object[] = request.getArgs();
    if (!request.isCancel()) {
      const task: Task = new Task(
        this._dispatcher,
        request.getMethod(),
        request.getCallback(),
        request.getEhConfig(),
        args,
        this._scheduler
      );
      request.bindTask(task);
      this._scheduler.schedule((): void => {
        task.run();
      });
      return task;
    }
    const callback = request.getCallback();
    if (callback !== null) {
      callback.onCancel();
    }
    return new Task(this._dispatcher, request.getMethod(), null, request.getEhConfig(), args, this._scheduler);
  }
}

/** 后台执行器抽象（上游 `IoThreadPoolExecutor`）。 */
export interface Scheduler {
  schedule(runnable: () => void): void;
}

/** 默认调度：微任务（等价「尽快执行」），测试里可换成手动驱动。 */
export class MicrotaskScheduler implements Scheduler {
  schedule(runnable: () => void): void {
    Promise.resolve().then(runnable);
  }
}

/**
 * 各 METHOD_* 的实际执行体（上游是 `EhEngine.xxx(this, client, args...)`）。
 * 抽成接口后 EhClient 不依赖 EhEngine，便于先交付调度语义。
 */
export interface MethodDispatcher {
  invoke(task: TaskInterface, method: number, args: Object[]): Promise<Object>;
}

/** Task 暴露给 dispatcher 的最小接口（上游 dispatcher 需要 `task.getEhConfig()` / `task.setCall()`）。 */
export interface TaskInterface {
  getEhConfig(): EhConfig | null;

  setCall(call: Object | null): void;
}

/** 对齐 `EhClient.Task`（`AsyncTask<Object, Void, Object>`）。 */
export class Task implements TaskInterface, TaskLike {
  private _dispatcher: MethodDispatcher;
  private _method: number;
  private _callback: EhCallbackLike | null;
  private _ehConfig: EhConfig | null;
  private _args: Object[];
  private _scheduler: Scheduler;
  private _call: Object | null = null;
  private _stop: boolean = false;

  constructor(
    dispatcher: MethodDispatcher,
    method: number,
    callback: EhCallbackLike | null,
    ehConfig: EhConfig | null,
    args: Object[] = [],
    scheduler?: Scheduler
  ) {
    this._dispatcher = dispatcher;
    this._method = method;
    this._callback = callback;
    this._ehConfig = ehConfig;
    this._args = args;
    this._scheduler = scheduler === undefined ? new MicrotaskScheduler() : scheduler;
  }

  getMethod(): number {
    return this._method;
  }

  getEhConfig(): EhConfig | null {
    return this._ehConfig;
  }

  isStop(): boolean {
    return this._stop;
  }

  getCall(): Object | null {
    return this._call;
  }

  /** 对齐 `setCall(Call)`：stop 之后再挂请求 → 抛 CancelledException。 */
  setCall(call: Object | null): void {
    if (this._stop) {
      throw new CancelledException();
    }
    this._call = call;
  }

  /** 对齐 `stop()`：幂等；首次异步派发 onCancel（对齐 SimpleHandler）并清理引用。 */
  stop(): void {
    if (!this._stop) {
      this._stop = true;
      const finalCallback: EhCallbackLike | null = this._callback;
      const currentCall: Object | null = this._call;
      this._callback = null;
      this._ehConfig = null;
      this._call = null;
      if (currentCall !== null && typeof (currentCall as Cancelable).cancel === 'function') {
        (currentCall as Cancelable).cancel();
      }
      if (finalCallback !== null) {
        this._scheduler.schedule((): void => {
          finalCallback.onCancel();
        });
      }
    }
  }

  /** 对齐 `doInBackground` + `onPostExecute`：异常转结果，再按类型分派回调。 */
  run(): void {
    if (this._stop) {
      return;
    }
    this._dispatcher.invoke(this, this._method, this._args)
      .then((value: Object): void => {
        this.onPostExecute(value);
      })
      .catch((e: Object): void => {
        // 三段式：操作 + 关键标识 + 后果。
        // 注意：这里**不是"吞掉"** —— 异常照旧转交 `onPostExecute` → `callback.onFailure`（上游同语义）；
        // 缺的只是日志痕迹：没有这一行，UI 显示了失败、日志里却什么也没有，排查时无从下手。
        hilog.error(DOMAIN, TAG, 'client task failed: method=%{public}d, err=%{public}s; ' +
          '后果：已转交 callback.onFailure（UI 会收到失败）', this._method, this.errorToString(e));
        this.onPostExecute(e);
      });
  }

  /** 异常/值的字符串化（统一 `Error.message` 与裸对象的输出形态）。 */
  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    if (e instanceof CancelledException) {
      return 'CancelledException';
    }
    return String(e);
  }

  /** 对齐 `onPostExecute(Object result)`。 */
  onPostExecute(result: Object): void {
    const callback: EhCallbackLike | null = this._callback;
    if (callback !== null) {
      if (!(result instanceof CancelledException)) {
        if (result instanceof Error) {
          callback.onFailure(result as Error);
        } else {
          callback.onSuccess(result);
        }
      }
      // 是 CancelledException → 什么都不做（onCancel 已在 stop 里发过）
    }
    this._callback = null;
    this._ehConfig = null;
    this._call = null;
  }
}

/** 对齐 `EhClient.Callback<E>` —— 与 EhRequest 的回调形状同一份定义（避免 ArkTS 结构类型不兼容）。 */
export interface TaskCallback extends EhCallbackLike {
}

/** 可取消对象（上游 okhttp 的 `Call.cancel()`）。 */
export interface Cancelable {
  cancel(): void;
}
/** `getProfile` 结果的最小形状（避免 import ProfileParser 的类型层级）。 */
interface ProfileResultLike {
  displayName: string;
  avatar: string | null;
}