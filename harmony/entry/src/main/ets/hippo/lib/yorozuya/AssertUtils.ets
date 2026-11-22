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
 * 条目   : S0395
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/AssertUtils.java（100 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/AssertUtils.ets
 *
 * 平台差异（方案 §5-7 重载改造 + §5-1 无反射）：
 *  1. ArkTS 不支持方法重载，Java 的 14 个重载收成 7 个「可选尾参 message」签名：
 *       Java assertTrue(boolean)                 → assertTrue(cond)
 *       Java assertTrue(String, boolean)         → assertTrue(cond, message)
 *     参数顺序由上滑的 message-first 改为 message-last，与 ArkTS 惯例一致；
 *     迁移上游调用点时只需把 message 参数挪到末尾，语义不变。
 *  2. assertInstanceOf(Object, Class) 依赖 java.lang.Class 反射（clazz.isInstance、
 *     clazz.getName），ArkTS 无反射、无 Class 类型值。改为显式断言谓词 + 类型名：
 *       assertInstanceOf(obj, (o: Object): boolean => o instanceof Foo, 'Foo')
 *     默认消息拼接仍为 "The object should be instance of " + typeName，
 *     与上游 clazz.getName() 结果同形。
 *  3. 全部默认消息串逐字保留上游文本（含句末句号），便于金样本比对。
 *  4. AssertException 见 AssertException.ets（extends Error，方案 §5-8）。
 */

import { AssertError } from './AssertError';
import { AssertException } from './AssertException';

/**
 * 类型断言谓词，替代 java.lang.Class 的 isInstance()。
 * 调用方写法：(o: Object): boolean => o instanceof SomeClass
 */
export type TypeGuard = (obj: Object) => boolean;

// 只含静态方法，禁止实例化（上游为 private 构造的 final class）
export class AssertUtils {

  // ── assertTrue ────────────────────────────────────────────────────────────

  static assertTrue(cond: boolean, message?: string): void {
    if (!cond) {
      throw new AssertError(message !== undefined ? message : 'Condition has to be true.');
    }
  }

  static assertTrueEx(cond: boolean, message?: string): void {
    if (!cond) {
      throw new AssertException(message !== undefined ? message : 'Condition has to be true.');
    }
  }

  // ── assertNull ────────────────────────────────────────────────────────────

  static assertNull(object: Object | null | undefined, message?: string): void {
    if (object !== null && object !== undefined) {
      throw new AssertError(message !== undefined ? message : 'Should be null');
    }
  }

  static assertNullEx(object: Object | null | undefined, message?: string): void {
    if (object !== null && object !== undefined) {
      throw new AssertException(message !== undefined ? message : 'Should be null');
    }
  }

  // ── assertNotNull ─────────────────────────────────────────────────────────

  static assertNotNull(object: Object | null | undefined, message?: string): void {
    if (object === null || object === undefined) {
      throw new AssertError(message !== undefined ? message : 'Should not be null');
    }
  }

  static assertNotNullEx(object: Object | null | undefined, message?: string): void {
    if (object === null || object === undefined) {
      throw new AssertException(message !== undefined ? message : 'Should not be null');
    }
  }

  // ── assertEquals ──────────────────────────────────────────────────────────

  static assertEquals(expected: number, actual: number, message?: string): void {
    if (expected !== actual) {
      throw new AssertError(message !== undefined
        ? message : `Should be ${expected}, but it is ${actual}`);
    }
  }

  static assertEqualsEx(expected: number, actual: number, message?: string): void {
    if (expected !== actual) {
      throw new AssertException(message !== undefined
        ? message : `Should be ${expected}, but it is ${actual}`);
    }
  }

  // ── assertInstanceOf ──────────────────────────────────────────────────────

  static assertInstanceOf(object: Object | null | undefined, guard: TypeGuard, typeName: string,
    message?: string): void {
    if (object === null || object === undefined || !guard(object)) {
      throw new AssertError(message !== undefined
        ? message : `The object should be instance of ${typeName}`);
    }
  }

  static assertInstanceOfEx(object: Object | null | undefined, guard: TypeGuard, typeName: string,
    message?: string): void {
    if (object === null || object === undefined || !guard(object)) {
      throw new AssertException(message !== undefined
        ? message : `The object should be instance of ${typeName}`);
    }
  }
}
