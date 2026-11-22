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
 * 条目   : S0394
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/AssertException.java（21 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/AssertException.ets
 *
 * 平台差异（方案 §5-8：ArkTS 只有 Error，无 checked exception）：
 * Java 侧 AssertException extends Exception（受检），ArkTS 无受检异常概念，
 * 因此改为 extends Error，类名、构造签名、消息语义保持不变。
 * catch 处按 `e instanceof AssertException` 分派，与 Java 侧 `catch (AssertException e)` 等价。
 */

export class AssertException extends Error {

  constructor(detailMessage: string) {
    super(detailMessage);
    this.name = 'AssertException';
  }

  /** 对应 Java Throwable.getMessage() */
  getMessage(): string {
    return this.message;
  }
}
