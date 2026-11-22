/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0493   上游: com/hippo/util/LogCat.kt（37 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/LogCat.ets
 *
 * 上游全文就两步：
 *   1. `FileUtils.ensureFile(file)` —— 确保文件（含父目录）存在，失败 → false
 *   2. `Runtime.getRuntime().exec("logcat -d")` 并 `IOUtils.copy(p.inputStream, FileOutputStream(file))`
 *
 * 平台差异：
 *  1. **`logcat -d` 是 Android 专有命令**，鸿蒙没有等价 CLI。日志采集改为注入：
 *     `dumpLogs: () => Promise<Uint8Array>`。可选实现：
 *       · `@ohos.hilog` 只能写不能读；
 *       · 读历史日志要走 hilog 的落盘文件（需系统权限）或 `hdc hilog`（仅调试）；
 *       · 生产环境通常用 `@ohos.hiviewdfx.hiAppEvent` 捞崩溃事件，而不是全量日志。
 *     → 因此本方法**保留编排与失败语义**（ensureFile 失败 → false；采集中抛错 → false），
 *       采集动作本身由调用方给。
 *  2. `FileOutputStream(file)` → `fileIo.openSync(path, CREATE|TRUNC|WRITE)` + `writeSync`，
 *     同样注入（`writeBytes`），这样本类不直接依赖文件系统 API，便于单测。
 *  3. 上游 `catch (IOException)` **先 printStackTrace 再返回 false** —— 我们用 `hilog.error` 记一条再返回 false
 *     （陷阱 82：低频失败路径，日志只在 catch 里）。
 */

import hilog from '@ohos.hilog';

/** 本类注入的三个能力（对应上游直接调用的 FileUtils / Runtime / FileOutputStream） */
export interface LogCatIo {
  /** 对应 `FileUtils.ensureFile(file)`：确保文件与父目录存在 */
  ensureFile(path: string): Promise<boolean>;

  /** 对应 `Runtime.exec("logcat -d")` 的 stdout 全量内容 */
  dumpLogs(): Promise<Uint8Array>;

  /** 对应 `new FileOutputStream(file)` + `IOUtils.copy(...)`：把字节写进目标文件（覆盖） */
  writeBytes(path: string, bytes: Uint8Array): Promise<void>;
}

export class LogCat {

  /**
   * 对应上游 `save(file: File?)`。
   * @param path 目标文件路径；**null → false**（上游对 `File?` 的处理由 `ensureFile` 兜底，
   *             这里显式短路，避免把 "无路径" 当 "建文件失败" 混在一起——两者都返回 false 但原因不同）
   * @returns true = 已落盘；false = 建文件失败 / 采集失败 / 写入失败
   */
  static async save(path: string | null, io: LogCatIo): Promise<boolean> {
    if (path === null) {
      hilog.error(0x0001, 'LogCat', 'save: null path');
      return false;
    }
    if (!(await io.ensureFile(path))) {
      return false;
    }
    try {
      const logs: Uint8Array = await io.dumpLogs();
      await io.writeBytes(path, logs);
      return true;
    } catch (e) {
      // 上游 printStackTrace 后 return false；这里记一条 error 再返回 false
      hilog.error(0x0001, 'LogCat', 'save failed: %{public}s', `${(e as Error).message}`);
      return false;
    }
  }
}