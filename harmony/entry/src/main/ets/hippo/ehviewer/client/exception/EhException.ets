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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/exception/EhException.java
 * （inventory S0083，24 行）
 *
 * ArkTS 异常模型的基类。上游是 `class EhException extends Exception`；
 * ArkTS 只有 `Error`，按重构方案 §5 第 8 条「9 个 exception 类保留类名，统一继承 Error」。
 *
 * 关键约束：`instanceof` 分派必须成立（上游 catch 处按具体类型分支），
 * 所以每个异常类都要显式 `extends EhException`，不能只做类型别名。
 * `this.name` 保持类名，便于日志与栈信息对齐上游 `getClass().getSimpleName()`。
 */
export class EhException extends Error {
  constructor(detailMessage: string, cause: Error | null = null) {
    super(detailMessage);
    this.name = 'EhException';
    if (cause !== null) {
      // 对应 Java 的 Throwable(String, Throwable)：ArkTS 的 Error 无 cause 字段，
      // 用显式字段保存，行为（可读取原始异常）保持
      this.causeError = cause;
    }
  }

  /** 对齐 Throwable.getCause()。 */
  causeError: Error | null = null;
}
