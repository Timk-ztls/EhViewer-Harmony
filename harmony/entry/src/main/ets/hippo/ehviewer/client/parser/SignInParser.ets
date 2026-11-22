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

import { EhException } from '../exception/EhException';
import { ParseException } from '../exception/ParseException';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/SignInParser.java
 * （inventory S0110，45 行）
 *
 * 论坛登录结果页三分支：
 *   1. `<p>You are now logged in as: NAME<`            → 返回 NAME
 *   2. 错误页：`<h4>The error returned was:</h4>\s*<p>MSG</p>`
 *      或 `<span class="postcolor">MSG</span>`        → EhException(MSG)
 *   3. 都不匹配                                        → ParseException("Can't parse sign in")
 *
 * 正则里 NAME 用了非贪婪 `(.+?)` 且**以 `<` 结尾**（页面上是 `<br>` 或 `<a>`），照搬。
 */
export class SignInParser {
  private static readonly NAME_PATTERN: RegExp = /<p>You are now logged in as: (.+?)</;
  private static readonly ERROR_PATTERN: RegExp =
    /(?:<h4>The error returned was:<\/h4>\s*<p>(.+?)<\/p>)|(?:<span class="postcolor">(.+?)<\/span>)/;

  static parse(body: string): string {
    const m: RegExpMatchArray | null = body.match(SignInParser.NAME_PATTERN);
    if (m !== null) {
      return m[1];
    }
    const em: RegExpMatchArray | null = body.match(SignInParser.ERROR_PATTERN);
    if (em !== null) {
      const first: string | undefined = em[1];
      throw new EhException(first === undefined || first === null ? em[2] : first);
    }
    throw new ParseException("Can't parse sign in", body);
  }
}
