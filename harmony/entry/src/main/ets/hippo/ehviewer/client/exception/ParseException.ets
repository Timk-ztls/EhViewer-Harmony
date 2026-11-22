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

import { EhException } from './EhException';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/exception/ParseException.java
 * （inventory S0089，30 行）
 *
 * 解析失败时携带原始 body（上游 `mBody`），用于把出错页面落盘供排查
 * （`EhEngine.throwException` 在 `Settings.getSaveParseErrorBody()` 时写文件）。
 *
 * 重载处理（ArkTS 无重载）：上游两个构造器
 *   ParseException(String detailMessage, String body)
 *   ParseException(String detailMessage, String body, Throwable cause)
 * → 本层第二构造器合并为三参默认值（cause 默认 null），调用点语义不变。
 */
export class ParseException extends EhException {
  private readonly _body: string | null;

  constructor(detailMessage: string, body: string | null, cause: Error | null = null) {
    super(detailMessage, cause);
    this.name = 'ParseException';
    this._body = body;
  }

  /** 对齐 getBody()。 */
  getBody(): string | null {
    return this._body;
  }
}
