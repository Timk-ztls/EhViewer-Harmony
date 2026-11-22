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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/StatusCodeException.java
 * （inventory S0441，若干个 HTTP 状态码异常的封装）
 *
 * 语义要点：
 *   - 24 个已知状态码（400-417、500-505）各有本地化文案；未知码用 DEFAULT_ERROR_MESSAGE
 *   - `isIdentifiedResponseCode()` = 「文案不是默认文案」——注意这是**按文案判断**而不是按码表查，
 *     所以 `new StatusCodeException(400, "自定义")` 也算 identified（上游如此）
 *   - 文案来自 `R.string.error_status_code_XXX`（core-runtime 的 i18n）→ 用 StatusCodeConfig 注入；
 *     默认实现返回英文（与上游英文资源一致），core-runtime 落地后 setConfig 换中文
 */
/** core-runtime 的 `R.string.error_status_code_*` 注入点。 */
export class StatusCodeConfig {
  /**
   * @param code       HTTP 状态码
   * @param known     是否在上游的 24 个已知码之内
   * @param defMessage 默认文案
   */
  getErrorMessage(code: number, known: boolean, defMessage: string): string {
    if (!known) {
      return defMessage;
    }
    return `Error ${code}`;
  }
}

export class StatusCodeException extends Error {
  /** 对齐 ERROR_MESSAGE_ARRAY 的容量提示（SparseArray(24)）。 */
  private static readonly DEFAULT_ERROR_MESSAGE: string = 'Error response code';
  private static readonly KNOWN_CODES: number[] = [
    400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417,
    500, 501, 502, 503, 504, 505
  ];

  private static _config: StatusCodeConfig = new StatusCodeConfig();

  static setConfig(config: StatusCodeConfig): void {
    StatusCodeException._config = config;
  }

  private readonly _responseCode: number;
  private readonly _message: string;

  /** 对齐 `StatusCodeException(int responseCode)`。 */
  constructor(responseCode: number, message?: string) {
    const msg: string = message === undefined
      ? StatusCodeException._config.getErrorMessage(responseCode,
        StatusCodeException.KNOWN_CODES.indexOf(responseCode) >= 0,
        StatusCodeException.DEFAULT_ERROR_MESSAGE)
      : message;
    super(msg);
    this.name = 'StatusCodeException';
    this._responseCode = responseCode;
    this._message = msg;
  }

  getResponseCode(): number {
    return this._responseCode;
  }

  /** 对齐 isIdentifiedResponseCode：按「文案是否等于默认文案」判断。 */
  isIdentifiedResponseCode(): boolean {
    return StatusCodeException.DEFAULT_ERROR_MESSAGE !== this._message;
  }

  getMessage(): string {
    return this._message;
  }

  getLocalizedMessage(): string {
    return this.getMessage();
  }
}

