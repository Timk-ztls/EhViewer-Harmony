/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0119   上游: com/hippo/ehviewer/Crash.java（147 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/Crash.ets
 *
 * 崩馈日志落盘。上游 `saveCrashLog(context, t)` 的产物是**一个文本文件**，结构固定：
 * ```
 * TIME=<yyyy-MM-dd-HH-mm-ss-SSS>
 * (空行)
 * ======== PackageInfo ========
 * PackageName=… / VersionName=… / VersionCode=… / Signature=…
 * (空行)
 * ======== Runtime ========
 * TopActivity=… / TopScene=…
 * (空行)
 * ======== DeviceInfo ========
 * BOARD=… … MEMORY_TOTAL=…      （19 个 Build 字段 + 4 行内存）
 * (空行)
 * ======== CrashInfo ========
 * <stack trace> + <逐个 cause 的 stack trace>
 * (空行)
 * ```
 * **本文件的重点是可断言的"文本格式化"**：`formatCrashLog(...)` 是纯函数，逐字节可对照；
 * 采集（包信息/设备信息/内存）与落盘都是注入。
 *
 * 平台差异：
 *  1. `Build.*` 19 个字段 → 注入 `DeviceInfoSnapshot`（鸿蒙用 `@ohos.deviceInfo` 映射，
 *     没有的字段填空串 —— **不编造**）。
 *  2. `OSUtils.getAppAllocatedMemory/getAppMaxMemory/getTotalMemory` 与
 *     `Debug.getNativeHeapAllocatedSize` → 注入 `MemorySnapshot`（字节数），
 *     格式化仍走已交付的 `yorozuya/FileUtils.humanReadableByteCount(bytes, false)`。
 *  3. `Throwable.printStackTrace(PrintWriter)` → `formatThrowable(t)`：**注入了**
 *     `stackOf(t)` 取单层栈文本，本文件负责"主异常 + 逐个 cause"的拼接顺序。
 *  4. `FileWriter` 的换行**上游硬编码 `"\r\n"`**（不是 `System.lineSeparator()`）——
 *     **逐字照搬**：换行符变了，与旧版本日志对照会整篇不匹配。
 *  5. `catch { file.delete(); }` —— **写失败要删掉半截文件**（避免留下损坏日志误导读日志的人）。
 *  6. `PackageUtils.getSignature` 已交付（S0496），这里注入取签名的函数。
 *
 * ⚠️ 关于"是否总是记录"（对应 Lead 问的 A/B/C）：
 *   上游是 `if (!initialized || Settings.getSaveCrashLog())` —— **启动初期无条件记录**，
 *   因为那是最容易崩的时段，且此时设置还没读出来。
 *   本实现把它表达成 `shouldSave(wiringCompleted, saveEnabled)`（见下），语义与上游一致：
 *     · `wiringCompleted === false` → **总是记录**（等价上游 `!initialized`）
 *     · 否则 → 跟随 `Settings.getSaveCrashLog()`
 *   `install()` 每次崩溃时**重新求值** `shouldSave`（而不是安装时求值一次），
 *   这样"开机期崩 → 记；稳定期崩且用户关了开关 → 不记"两种情形都正确。
 */

import { AppConfig } from './AppConfig';
import { ReadableTime } from '../util/ReadableTime';
import { FileUtils } from '../lib/yorozuya/FileUtils';
import { PacketInfo, CrashDeviceInfo, CrashMemoryInfo, CrashRuntimeInfo } from './CrashTypes';

export class Crash {

  /** 上游硬编码的行分隔（**不是** `System.lineSeparator()`） */
  static readonly EOL: string = '\r\n';
  /** 上游文件名前缀 `crash-`，后缀 `.log` */
  static readonly FILE_PREFIX: string = 'crash-';
  static readonly FILE_SUFFIX: string = '.log';

  /** 对应上游 `avoidNull(str)` */
  static avoidNull(str: string | null): string {
    return (str !== null) ? str : 'null';
  }

  /**
   * **是否要记录本次崩溃**（对应上游 `if (!initialized || Settings.getSaveCrashLog())`）。
   * @param wiringCompleted 对应上游 `initialized`（`AppWiring` 是否已跑完）
   * @param saveEnabled 对应 `Settings.getSaveCrashLog()`
   */
  static shouldSave(wiringCompleted: boolean, saveEnabled: boolean): boolean {
    return !wiringCompleted || saveEnabled;
  }

  /**
   * 对应上游 `saveCrashLog(context, t)` 的**编排**：
   * 取崩溃目录 → null 直接返回 → 组文件名 → 写 → **写失败删半截文件**。
   * @returns 写入的文件路径；未写（无目录 / 未开启 / 写失败）→ null
   */
  static async saveCrashLog(t: Object,
    pkg: PacketInfo | null,
    device: CrashDeviceInfo,
    memory: CrashMemoryInfo,
    fetchSignature: (packageName: string) => string | null,
    runtime: CrashRuntimeInfo,
    stackOf: (t: Object) => string,
    writeText: (path: string, text: string) => Promise<void>,
    deleteFile: (path: string) => void,
    now: () => number = () => Date.now()): Promise<string | null> {
    const dir: string | null = AppConfig.getExternalCrashDir();
    if (dir === null) {
      return null;
    }
    const nowString: string = ReadableTime.getFilenamableTime(now());
    const path: string = Crash.joinPath(dir, Crash.FILE_PREFIX + nowString + Crash.FILE_SUFFIX);
    const text: string = Crash.formatCrashLog(nowString, pkg, device, memory, fetchSignature,
      runtime, t, stackOf);
    try {
      await writeText(path, text);
      return path;
    } catch (e) {
      // 上游：写失败就把文件删掉（避免留下半截日志误导读日志的人）
      deleteFile(path);
      return null;
    }
  }

  /**
   * **纯函数**：把上游 `saveCrashLog` 里所有 `fw.write(...)` 的产物拼成一个字符串。
   * 逐字节可与上游日志对照（含 `\r\n` 与空行位置）。
   */
  static formatCrashLog(timeString: string, pkg: PacketInfo | null, device: CrashDeviceInfo,
    memory: CrashMemoryInfo, fetchSignature: (packageName: string) => string | null,
    runtime: CrashRuntimeInfo, t: Object, stackOf: (t: Object) => string): string {
    const eol: string = Crash.EOL;
    let s: string = '';
    s += 'TIME=' + timeString + eol;
    s += eol;

    // ── PackageInfo ──
    s += '======== PackageInfo ========' + eol;
    if (pkg !== null) {
      const versionName: string = (pkg.versionName === null) ? 'null' : pkg.versionName;
      const signature: string | null = fetchSignature(pkg.packageName);
      s += 'PackageName=' + pkg.packageName + eol;
      s += 'VersionName=' + versionName + eol;
      s += 'VersionCode=' + pkg.versionCode + eol;
      s += 'Signature=' + ((signature !== null) ? signature : 'null') + eol;
    } else {
      s += "Can't get package information" + eol;
    }
    s += eol;

    // ── Runtime ──
    s += '======== Runtime ========' + eol;
    s += 'TopActivity=' + Crash.avoidNull(runtime.topActivityClassName) + eol;
    s += 'TopScene=' + Crash.avoidNull(runtime.topSceneClassName) + eol;
    s += eol;

    // ── DeviceInfo（19 个字段 + 4 行内存，顺序照搬）──
    s += '======== DeviceInfo ========' + eol;
    s += 'BOARD=' + device.board + eol;
    s += 'BOOTLOADER=' + device.bootloader + eol;
    s += 'CPU_ABI=' + device.cpuAbi + eol;
    s += 'CPU_ABI2=' + device.cpuAbi2 + eol;
    s += 'DEVICE=' + device.device + eol;
    s += 'DISPLAY=' + device.display + eol;
    s += 'FINGERPRINT=' + device.fingerprint + eol;
    s += 'HARDWARE=' + device.hardware + eol;
    s += 'HOST=' + device.host + eol;
    s += 'ID=' + device.id + eol;
    s += 'MANUFACTURER=' + device.manufacturer + eol;
    s += 'MODEL=' + device.model + eol;
    s += 'PRODUCT=' + device.product + eol;
    s += 'RADIO=' + device.radio + eol;
    s += 'SERIAL=' + device.serial + eol;
    s += 'TAGS=' + device.tags + eol;
    s += 'TYPE=' + device.type + eol;
    s += 'USER=' + device.user + eol;
    s += 'CODENAME=' + device.codename + eol;
    s += 'INCREMENTAL=' + device.incremental + eol;
    s += 'RELEASE=' + device.release + eol;
    s += 'SDK=' + device.sdkInt + eol;
    // 四行内存都走 humanReadableByteCount(bytes, false)
    s += 'MEMORY=' + FileUtils.humanReadableByteCount(memory.appAllocated, false) + eol;
    s += 'MEMORY_NATIVE=' + FileUtils.humanReadableByteCount(memory.nativeAllocated, false) + eol;
    s += 'MEMORY_MAX=' + FileUtils.humanReadableByteCount(memory.appMax, false) + eol;
    s += 'MEMORY_TOTAL=' + FileUtils.humanReadableByteCount(memory.total, false) + eol;
    s += eol;

    // ── CrashInfo ──
    s += '======== CrashInfo ========' + eol;
    s += Crash.formatThrowable(t, stackOf);
    s += eol;
    return s;
  }

  /**
   * 对应上游 `getThrowableInfo(t, fw)`：**先主异常，再逐个 cause**（沿 cause 链一路打）。
   * @param stackOf 取单个 Throwable 的栈文本（对应 `t.printStackTrace(pw)`）
   */
  static formatThrowable(t: Object, stackOf: (t: Object) => string,
    causeOf: (t: Object) => Object | null = () => null): string {
    let s: string = stackOf(t);
    let cause: Object | null = causeOf(t);
    while (cause !== null) {
      s += stackOf(cause);
      cause = causeOf(cause);
    }
    return s;
  }

  private static joinPath(dir: string, name: string): string {
    return dir.endsWith('/') ? dir + name : dir + '/' + name;
  }
}
