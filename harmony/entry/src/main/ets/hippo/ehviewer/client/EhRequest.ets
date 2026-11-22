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

import { EhConfig } from './EhConfig';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhRequest.java
 * （inventory S0076，81 行）
 *
 * EhClient 的请求描述符：method（API_METHOD_*）+ args + callback + 可选 EhConfig。
 *
 * 关键语义：
 *   - `getEhConfig()` **惰性回落**：自身没设就用 `Settings.getEhConfig()`（本层用 EhRequestConfig 注入）
 *   - `cancel()` 幂等：只在首次调用时置 mCancel 并驱动 task.cancel()，之后返回 false
 */
/** core-runtime 的 `Settings.getEhConfig()` 注入点。 */
export class EhRequestConfig {
  getEhConfig(): EhConfig {
    return new EhConfig();
  }
}

/** EhClient.Callback 的最小形状（跨文件避免循环依赖）。 */
export interface EhCallbackLike {
  onSuccess(result: Object): void;

  onFailure(e: Error): void;

  onCancel(): void;
}

/** EhClient.Task 的最小形状（上游 cancel() 调的是 task.stop()）。 */
export interface TaskLike {
  stop(): void;
}

export class EhRequest {
  private _method: number = 0;
  private _args: Object[] = [];
  private _callback: EhCallbackLike | null = null;
  private _ehConfig: EhConfig | null = null;
  private _cancel: boolean = false;

  static setConfig(config: EhRequestConfig): void {
    EhRequest._config = config;
  }

  private static _config: EhRequestConfig = new EhRequestConfig();

  setMethod(method: number): EhRequest {
    this._method = method;
    return this;
  }

  setArgs(args: Object[]): EhRequest {
    this._args = args;
    return this;
  }

  setCallback(callback: EhCallbackLike | null): EhRequest {
    this._callback = callback;
    return this;
  }

  setEhConfig(ehConfig: EhConfig | null): EhRequest {
    this._ehConfig = ehConfig;
    return this;
  }

  getMethod(): number {
    return this._method;
  }

  getArgs(): Object[] {
    return this._args;
  }

  getCallback(): EhCallbackLike | null {
    return this._callback;
  }

  /** 对齐 `getEhConfig()`：自身为 null 时回落到全局配置。 */
  getEhConfig(): EhConfig {
    return this._ehConfig !== null ? (this._ehConfig as EhConfig) : EhRequest._config.getEhConfig();
  }

  isCancel(): boolean {
    return this._cancel;
  }

  /** 对齐 `cancel()`：幂等，首次返回 true。 */
  cancel(): boolean {
    if (!this._cancel) {
      this._cancel = true;
      if (this._task !== null) {
        (this._task as TaskLike).stop();
      }
      return true;
    }
    return false;
  }

  private _task: TaskLike | null = null;

  /** EhClient 内部挂任务用（上游是包级字段 `EhClient.Task task`）。 */
  bindTask(task: TaskLike | null): void {
    this._task = task;
  }

  getTask(): TaskLike | null {
    return this._task;
  }
}

