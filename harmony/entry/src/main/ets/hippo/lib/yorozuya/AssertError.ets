/*
 * Copyright (C) 2015 Hippo Seven
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0393
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/AssertError.java（21 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/AssertError.ets
 *
 * 平台差异：无。ArkTS 的 Error 即 Java Error 的等价物（都是不可 recover 的运行期
 * 错误基类），断言失败语义完全一致。保留 getMessage() 以便上游
 * `e.getMessage()` 调用点零改写。
 */

export class AssertError extends Error {

  constructor(detailMessage: string) {
    super(detailMessage);
    this.name = 'AssertError';
  }

  /** 对应 Java Throwable.getMessage() */
  getMessage(): string {
    return this.message;
  }
}
