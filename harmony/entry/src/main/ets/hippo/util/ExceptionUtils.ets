/*
 * Copyright 2016 Hippo Seven
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
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0486   上游: com/hippo/util/ExceptionUtils.kt（79 行，Kotlin object）
 * 目标   : harmony/entry/src/main/ets/hippo/util/ExceptionUtils.ets
 *
 * 平台差异（**这个类是两个不同用法的集合，必须分开看**）：
 *
 * 【1】throwIfFatal(Throwable) —— 已 1:1 落地
 *   上游：只把 JVM 致命错误重抛，其余交给调用方吞掉。依据
 *   https://github.com/ReactiveX/RxJava/issues/748#issuecomment-32471495
 *       VirtualMachineError / ThreadDeath / LinkageError → throw t
 *   ArkTS：**这三个类都不存在**（无 JVM 错误层次）。等价做法是把"引擎级不可恢复错误"识别出来：
 *       - `RangeError`（V8/ArkCompiler 用它表示栈溢出、内存不足等引擎级失败）
 *       - `Error` 且 name 为 'OutOfMemoryError' / 'InternalError'（内置或自建）
 *   其余（含普通 Error）由调用方吞掉 —— 与上游"只放行致命错误"的意图一致。
 *   ⚠️ 这是**近似而非严格等价**：Java 的 LinkageError（类加载失败）在 ArkTS 无对应现象。
 *
 * 【2】getReadableString(Throwable) —— **未移植，见下方说明**
 *   它依赖 4 个跨模块类型 + 资源串：
 *       GetText + R.string.error_*（GetText 是 S0161，本模块待移植）
 *       EhException（net-parse 的 ehviewer/client/exception）
 *       StatusCodeException（net-parse 的 hippo/network）
 *       org.apache.http.conn.ConnectTimeoutException（Apache HttpClient，鸿蒙无此库）
 *   在依赖未就绪前落它会产生 4 个编译不过的 import，会拖红全项目构建闸门。
 *   等 GetText 与 net-parse 的 exception 层就绪后补齐（已在 MR 标注）。
 */

export class ExceptionUtils {

  /**
   * 对应上游 throwIfFatal(Throwable)。
   * 只在收到引擎级不可恢复错误时重抛，其余静默返回（由调用方决定是否吞掉）。
   */
  static throwIfFatal(e: Object | null | undefined): void {
    if (ExceptionUtils.isFatal(e)) {
      throw e as Error;
    }
  }

  /**
   * 是否属于"致命、不可恢复"错误。
   * 新增方法（上游没有 public 版本，只有 throwIfFatal 内联的 when 分支）：
   * storage-db / download-sync 需要在 catch 里判定"要不要继续跑"，故导出判定。
   */
  static isFatal(e: Object | null | undefined): boolean {
    if (e === null || e === undefined) {
      return false;
    }
    if (!(e instanceof Error)) {
      // 非 Error 的 throw 值（如字符串）在 ArkTS 里不是引擎级错误
      return false;
    }
    // RangeError：ArkCompiler 用它表示栈溢出 / 内存分配失败等引擎级失败
    if (e instanceof RangeError) {
      return true;
    }
    const name: string = e.name;
    return name === 'OutOfMemoryError' || name === 'InternalError'
      || name === 'VirtualMachineError' || name === 'LinkageError' || name === 'ThreadDeath';
  }
}
