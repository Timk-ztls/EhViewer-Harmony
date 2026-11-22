/*
 * 对位上游：app/src/main/java/com/hippo/unifile/Utils.java
 *
 * 平台差异（见 MR「UniFile 抽象层平台对位」）：
 *   - 上游 closeQuietly(Cursor) 依赖 ContentResolver 游标，鸿蒙无 Cursor 抽象，
 *     @@ohos.data.relationalStore 的 ResultSet 关闭由 S0124/S0131 等 DAO 自行负责（见 dao/ 目录）。
 *     本文件保留 Closeable 版本，并新增 closeQuietlyRs 供 RDB 游标复用。
 *   - 上游 throwIfFatal 判定 VirtualMachineError / ThreadDeath / LinkageError 三类致命错误。
 *     ArkTS 只有 Error 一种异常，等价判定改为「不可恢复错误」白名单：
 *     OutOfMemory / StackOverflow / 引擎级 SystemError（hilog 无法恢复），其余异常一律吞掉。
 *   - 日志：android.util.Log → @ohos.hilog，Domain 使用 0x0000（保留位），
 *     所有格式串带 %{public}s，避免 hilog 默认把参数打成 <private>。
 */

import hilog from '@ohos.hilog';

const LOG_DOMAIN: number = 0x0000;

/** 上游 java.io.Closeable 的最小等价面。 */
export interface Closeable {
  close(): void;
}

/** 上游 android.database.Cursor 的关闭语义等价物（RDB ResultSet 只保证 close()）。 */
export interface ResultSetLike {
  close(): void;
}

export class Utils {
  private constructor() {
  }

  /**
   * 关闭任意 Closeable，吞掉关闭期异常（上游 closeQuietly(Closeable)）。
   * 注意：ArkTS 无 try-with-resources，调用方必须显式调用。
   */
  static closeQuietly(c: Closeable | null | undefined): void {
    if (c === null || c === undefined) {
      return;
    }
    try {
      c.close();
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }

  /** 关闭 RDB ResultSet，吞掉关闭期异常（对位上游 Cursor 版本）。 */
  static closeQuietlyRs(rs: ResultSetLike | null | undefined): void {
    if (rs === null || rs === undefined) {
      return;
    }
    try {
      rs.close();
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }

  /**
   * 上游 throwIfFatal：致命错误必须继续向上抛，不能被 closeQuietly 吃掉。
   * ArkTS 下按 message 白名单判定（无 typing 可用）：
   *   - 内存/栈溢出：进程已不可信
   *   - 引擎级 SystemError：ArkCompiler 运行时错误
   */
  static throwIfFatal(t: Object | null | undefined): void {
    if (t === null || t === undefined) {
      return;
    }
    const msg: string = (t instanceof Error) ? t.message : String(t);
    if (msg.indexOf('OutOfMemory') >= 0 ||
      msg.indexOf('out of memory') >= 0 ||
      msg.indexOf('StackOverflow') >= 0 ||
      msg.indexOf('stack overflow') >= 0 ||
      msg.indexOf('SystemError') >= 0) {
      throw t as Error;
    }
  }

  /** 判断是否为致命错误（供上层 catch 分支决定是否 rethrow）。 */
  static isFatal(t: Object | null | undefined): boolean {
    if (t === null || t === undefined) {
      return false;
    }
    const msg: string = (t instanceof Error) ? t.message : String(t);
    return msg.indexOf('OutOfMemory') >= 0 ||
      msg.indexOf('out of memory') >= 0 ||
      msg.indexOf('StackOverflow') >= 0 ||
      msg.indexOf('stack overflow') >= 0 ||
      msg.indexOf('SystemError') >= 0;
  }

  /** 对位 android.util.Log.w(String, String) */
  static logW(tag: string, msg: string): void {
    hilog.warn(LOG_DOMAIN, tag, '%{public}s', msg);
  }

  /** 对位 android.util.Log.e(String, String) */
  static logE(tag: string, msg: string): void {
    hilog.error(LOG_DOMAIN, tag, '%{public}s', msg);
  }

  /** 对位 android.util.Log.i(String, String) */
  static logI(tag: string, msg: string): void {
    hilog.info(LOG_DOMAIN, tag, '%{public}s', msg);
  }
}
