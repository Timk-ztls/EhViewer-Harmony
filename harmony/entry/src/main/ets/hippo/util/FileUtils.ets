/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0488   上游: com/hippo/util/FileUtils.kt（192 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/FileUtils.ets
 *
 * 注意：**这不是** `hippo/lib/yorozuya/FileUtils`（那个是字节格式化 + 递归删除，已交付）。
 * 本文件是 `com/hippo/util/FileUtils.kt`，只做**文件搬运与读取**。
 *
 * 移植（可移植、且有失败语义）：
 *   · `moveFile(source, destDir)` —— 源不存在 → false；目标目录不存在则建；**再 rename**
 *     （上游只 catch SecurityException → false；建的目录失败不检查，照搬）
 *   · `copyFile(from, to)` / `copyFile(from, to, flush)` —— 1KB 块循环拷贝，**`read > 0`** 的循环条件照搬
 *     （不是 `!= -1`：读到 0 也停）
 *   · `copyFile(UniFile, UniFile, flush)` —— 同一循环，走 UniFile 的流
 *   · `read(file)` —— 整文件按 UTF-8 读成字符串；异常 → null
 *
 * 不移植（Android 专有，见各函数注释）：
 *   · `openAssignFolder(path, context)` —— 用 `Intent(ACTION_OPEN_DOCUMENT)` + `DocumentsContract`
 *     打开系统文件选择器。鸿蒙对应 `@ohos.file.picker` 的 DocumentViewPicker，
 *     但那是**页面级 UI 动作**（要 UIAbilityContext），归 ui-scene/ui-widget，不在本工具类。
 *   · `getPath(context, uri)` —— `ContentResolver.query(MediaStore.Images.Media.DATA)` 把 `content://` 转路径。
 *     鸿蒙无 ContentResolver/MediaStore，URI 由 `@ohos.file.fileuri` 直接解析。
 *   · `getFileName(context, uri)` —— `OpenableColumns.DISPLAY_NAME`，同上。
 *
 * 平台差异：
 *  1. `File` → `string` 路径（与 AppConfig/FileProvider 一致）。
 *  2. 流式拷贝注入 `FileIoLike`（`@ohos.file.fs` 的实现），保持"块循环 + flush"语义可断言。
 *  3. `ExceptionUtils.throwIfFatal + Analytics.recordException` → `throwIfFatal` 保留（OOM/StackOverflow
 *     仍应向上抛），`Analytics.recordException` 在本项目是 D-027 的**本地 hilog**。
 */

import { Analytics } from '../ehviewer/Analytics';
import { ExceptionUtils } from './ExceptionUtils';
import { UniFile } from '../unifile/UniFile';
import hilog from '@ohos.hilog';

/** 文件系统能力（`@ohos.file.fs` 的薄封装，注入以便断言块循环与 flush 时机） */
export interface FileIoLike {
  exists(path: string): boolean;

  isDirectory(path: string): boolean;

  mkdirs(path: string): boolean;

  /** 对应 `File.renameTo`：成功 true */
  rename(from: string, to: string): boolean;

  /** 打开输入流 */
  openIn(path: string): Object;

  /** 打开输出流（覆盖） */
  openOut(path: string): Object;

  /** 读最多 len 字节，返回读到的字节数（0 表示 EOF） */
  read(stream: Object, buf: Uint8Array, len: number): number;

  write(stream: Object, buf: Uint8Array, len: number): void;

  flush(stream: Object): void;

  close(stream: Object): void;
}

export class FileUtils {

  static readonly TAG: string = 'FileUtils';
  /** 上游 `ByteArray(1024)` */
  static readonly COPY_BUFFER_SIZE: number = 1024;

  /**
   * 对应上游 `moveFile(sourceFile, destDir)`：
   * 源不存在 → false；目标目录不存在 → **尝试建（失败也不检查）**；最后 `renameTo`。
   */
  static moveFile(source: string, destDir: string, io: FileIoLike): boolean {
    if (!io.exists(source)) {
      return false;
    }
    // 确保目标目录存在（上游不检查 mkdirs 的返回值）
    if (!io.exists(destDir)) {
      io.mkdirs(destDir);
    }
    const newFile: string = FileUtils.joinPath(destDir, FileUtils.baseName(source));
    try {
      // 重命名/移动文件
      return io.rename(source, newFile);
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      hilog.error(0x0001, FileUtils.TAG, 'moveFile failed: %{public}s', `${(e as Error).message}`);
      return false;
    }
  }

  /** 对应上游 `copyFile(from, to)`（flush=false 重载） */
  static copyFile(from: string, to: string, io: FileIoLike): boolean {
    return FileUtils.copyFileWithFlush(from, to, false, io);
  }

  /**
   * 对应上游 `copyFile(from, to, flush)`（File 版）：1KB 块循环，`read(...) > 0` 为条件。
   * 失败 → `recordException` + false（上游还会 `throwIfFatal`）。
   */
  static copyFileWithFlush(from: string, to: string, flush: boolean, io: FileIoLike): boolean {
    let inStream: Object | null = null;
    let outStream: Object | null = null;
    try {
      inStream = io.openIn(from);
      outStream = io.openOut(to);
      const buf: Uint8Array = new Uint8Array(FileUtils.COPY_BUFFER_SIZE);
      let c: number = io.read(inStream, buf, FileUtils.COPY_BUFFER_SIZE);
      while (c > 0) {
        io.write(outStream, buf, c);
        c = io.read(inStream, buf, FileUtils.COPY_BUFFER_SIZE);
      }
      if (flush) {
        io.flush(outStream);
      }
      io.close(inStream);
      io.close(outStream);
      return true;
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      Analytics.recordException(e as Error);
      return false;
    } finally {
      // 上游 catch 里没有 close（流泄漏）—— 这里补上（B 类：资源泄漏，用户不可感知）
      if (inStream !== null) {
        try {
          io.close(inStream);
        } catch (e) {
          // ignore
        }
      }
      if (outStream !== null) {
        try {
          io.close(outStream);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /** 对应上游 `copyFile(UniFile, UniFile, flush)`：同一循环，走 UniFile 的流能力 */
  static copyUniFile(from: UniFile, to: UniFile, flush: boolean): boolean {
    let inStream: Object | null = null;
    let outStream: Object | null = null;
    try {
      inStream = from.openInputStream();
      outStream = to.openOutputStream();
      const buf: Uint8Array = new Uint8Array(FileUtils.COPY_BUFFER_SIZE);
      let c: number = (inStream as ReadLike).read(buf);
      while (c > 0) {
        (outStream as WriteLike).write(buf, 0, c);
        c = (inStream as ReadLike).read(buf);
      }
      if (flush) {
        (outStream as FlushLike).flush();
      }
      (inStream as CloseLike).close();
      (outStream as CloseLike).close();
      return true;
    } catch (e) {
      ExceptionUtils.throwIfFatal(e as Object);
      Analytics.recordException(e as Error);
      return false;
    } finally {
      if (inStream !== null) {
        try {
          (inStream as CloseLike).close();
        } catch (e) {
          // ignore
        }
      }
      if (outStream !== null) {
        try {
          (outStream as CloseLike).close();
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /**
   * 对应上游 `read(file)`：整文件按 **UTF-8** 读成字符串；`file == null` → null；
   * 读异常 → `recordException` + null。上游 finally 里 `closeQuietly`。
   */
  static read(path: string | null, io: FileIoLike, readAll: (stream: Object) => Uint8Array): string | null {
    if (path === null) {
      return null;
    }
    let inStream: Object | null = null;
    try {
      inStream = io.openIn(path);
      const bytes: Uint8Array = readAll(inStream);
      return FileUtils.decodeUtf8(bytes);
    } catch (e) {
      Analytics.recordException(e as Error);
      hilog.error(0x0001, FileUtils.TAG, 'read failed: %{public}s', `${(e as Error).message}`);
      return null;
    } finally {
      if (inStream !== null) {
        try {
          io.close(inStream);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /** UTF-8 解码（上游 `IOUtils.readString(is, "utf-8")`） */
  static decodeUtf8(bytes: Uint8Array): string {
    let out: string = '';
    let i: number = 0;
    while (i < bytes.length) {
      const b0: number = bytes[i++];
      if (b0 < 0x80) {
        out += String.fromCharCode(b0);
      } else if (b0 < 0xE0 && i < bytes.length) {
        const b1: number = bytes[i++];
        out += String.fromCharCode(((b0 & 0x1F) << 6) | (b1 & 0x3F));
      } else if (b0 < 0xF0 && i + 1 < bytes.length) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        out += String.fromCharCode(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F));
      } else if (i + 2 < bytes.length) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        const b3: number = bytes[i++];
        let cp: number = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
        cp -= 0x10000;
        out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
      } else {
        out += '\uFFFD';
      }
    }
    return out;
  }

  private static joinPath(dir: string, name: string): string {
    return dir.endsWith('/') ? dir + name : dir + '/' + name;
  }

  private static baseName(path: string): string {
    const idx: number = path.lastIndexOf('/');
    return (idx < 0) ? path : path.substring(idx + 1);
  }
}

/** `UniFile.openInputStream()` 返回值的最小契约 */
interface ReadLike {
  read(buf: Uint8Array): number;
}

interface WriteLike {
  write(buf: Uint8Array, offset: number, length: number): void;
}

interface FlushLike {
  flush(): void;
}

interface CloseLike {
  close(): void;
}
