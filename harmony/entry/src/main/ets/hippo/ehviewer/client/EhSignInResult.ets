/*
 * Copyright 2014 Hippo Seven
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
 * `EhClient.signIn` 的结果（net-parse 自有类）。
 *
 * ## 为什么不在 net-parse 里直接用 ui-scene 的 `SignInResult`
 * `SignInResult` 声明在 `ui-scene` 的 `SignInScene.ets` 里。若 net-parse 去 import 它，
 * 就形成 **net-parse → ui-scene 的反向依赖**（层序错）。所以这里定义等价类，
 * 由 `AppWiring` 做一层 5 行适配（`success/errorCode/displayName/avatar` 四个字段同名同序）。
 *
 * ## `errorCode` 码表（**本项目自定**，上游没有数字码）
 * 上游 `SignInScene` 失败时只弹「异常文案」对话框（`ExceptionUtils.getReadableString(e)`），
 * **没有数字码**。ui-scene 的 `SignInResult.errorCode` 是契约先行的产物，说「原值透传」——
 * 所以我们这里给出稳定分类，适配层原样搬过去即可：
 *
 * ```
 *    0  成功
 *   -1  客户端不可用 / 已取消（与 UnavailableSignInClient 的 -1 同值，便于适配）
 *   -2  其它异常（网络、IO、超时…）
 *   -3  解析失败（返回的不是登录页/论坛页结构）
 *   -4  账号或密码错误（上游 SignInParser 的 ERROR_PATTERN 命中，文案在 errorMessage 里）
 *   >0  HTTP 状态码（StatusCodeException 的 responseCode 原值）
 * ```
 *
 * `errorMessage` 保留上游那句可读文案（登录失败对话框的正文）；适配层可以选择丢弃。
 */
export class EhSignInResult {
  /** 成功码。 */
  static readonly OK: number = 0;
  /** 客户端不可用 / 已取消。 */
  static readonly ERR_UNAVAILABLE: number = -1;
  /** 其它异常（网络/IO/超时）。 */
  static readonly ERR_OTHER: number = -2;
  /** 解析失败。 */
  static readonly ERR_PARSE: number = -3;
  /** 账号或密码错误。 */
  static readonly ERR_CREDENTIAL: number = -4;

  readonly success: boolean;
  readonly errorCode: number;
  readonly displayName: string;
  readonly avatar: string;
  readonly errorMessage: string;

  constructor(success: boolean, errorCode: number, displayName: string, avatar: string,
    errorMessage: string = '') {
    this.success = success;
    this.errorCode = errorCode;
    this.displayName = displayName;
    this.avatar = avatar;
    this.errorMessage = errorMessage;
  }

  static ok(displayName: string, avatar: string): EhSignInResult {
    return new EhSignInResult(true, EhSignInResult.OK, displayName, avatar, '');
  }

  static fail(errorCode: number, errorMessage: string): EhSignInResult {
    return new EhSignInResult(false, errorCode, '', '', errorMessage);
  }
}
