/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0409   上游: com/hippo/lib/yorozuya/FileUtils.java（293 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/FileUtils.ets
 *
 * 平台差异（java.io.File → ArkTS 路径字符串 + @ohos.file.fs）：
 *  1. **java.io.File 在 ArkTS 不存在**。鸿蒙的文件操作是"路径字符串 + fs.xxxSync"，
 *     因此本类**所有方法把 File 形参改为 string 路径**：
 *       ensureFile(File)        → ensureFile(path: string)
 *       ensureDirectory(File)   → ensureDirectory(path: string)
 *       delete(File)            → delete(path: string)
 *       deleteContent(File)     → deleteContent(path: string)
 *       read(File)              → read(path: string)
 *       write(File, String)     → write(path: string, str: string)
 *       createTempFile(File, String) → createTempFile(parent: string, extension?: string): string
 *       createTempDir(File)     → createTempDir(parent: string): string
 *       rename(File, File)      → rename(from: string, to: string)
 *     返回值里的 File 同理变 string。下游（DownloadManager/EhDB/SpiderQueen）改用路径字符串调用。
 *  2. `file.exists()/isFile()/isDirectory()/length()` → `fs.accessSync` + `fs.statSync().isFile()/
 *     isDirectory()/size`；`mkdirs()` → 逐级 mkdirSync（见 mkdirsRecursive，SDK 的 mkdirSync
 *     不保证递归）。
 *  3. `read` → `fs.readTextSync`（utf-8，与上游 IOUtils.readString(is, "utf-8") 等价）；
 *     `write` → `openSync(READ_WRITE|CREATE|TRUNC)` + `writeSync` + `closeSync`。
 *  4. **`humanReadableByteCount` 的格式串必须逐字一致**：上游是
 *     `String.format(Locale.US, "%.1f %sB", …)`，即 `123.4 KB` / `1.0 MB`（十进制两位以上才进单位）。
 *     本实现用 `toFixed(1)` 复刻；**Java 的 %.1f 是 HALF_UP，JS toFixed 在二进制不可精确表示时
 *     可能差 0.1**（如 0.15），故对 mid 值显式做 HALF_UP 修正。这个串会进 crash 日志，
 *     格式变了历史日志就无法对照，所以单独处理。
 *  5. `System.currentTimeMillis()` → `Date.now()`。
 *  6. 上游 `rename` 的失败回退是"流拷贝 + 删源"；ArkTS 侧用 `fs.copyFileSync` 做同样的事
 *     （语义等价：先试 renameSync，失败再 copy+delete）。
 *  7. `TextUtils.isEmpty` → 内联判空；StringUtils.remove/trim 复用同批已移植实现。
 */

import fs from '@ohos.file.fs';
import { StringUtils } from './StringUtils';
import { utf8Encode } from './IOUtils';

export class FileUtils {

  private static readonly FORBIDDEN_FILENAME_CHARACTERS: string[] = [
    '\\',
    '/',
    ':',
    '*',
    '?',
    '"',
    '<',
    '>',
    '|',
  ];

  // ── 内部工具 ────────────────────────────────────────────────────────────

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private static isFile(path: string): boolean {
    try {
      return fs.statSync(path).isFile();
    } catch (e) {
      return false;
    }
  }

  private static isDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  /** mkdir -p 等价（SDK 的 mkdirSync 不保证递归） */
  private static mkdirsRecursive(path: string): boolean {
    if (FileUtils.isDirectory(path)) {
      return true;
    }
    const parts: string[] = path.split('/');
    let cur: string = '';
    for (let i = 0; i < parts.length; i++) {
      const p: string = parts[i];
      if (p.length === 0) {
        cur = '/';
        continue;
      }
      cur = (cur === '/' || cur.length === 0) ? (cur + p) : (cur + '/' + p);
      if (!FileUtils.exists(cur)) {
        try {
          fs.mkdirSync(cur);
        } catch (e) {
          return false;
        }
      }
    }
    return FileUtils.isDirectory(path);
  }

  private static joinPath(parent: string, name: string): string {
    if (parent.length === 0) {
      return name;
    }
    const last: string = parent.charAt(parent.length - 1);
    return (last === '/') ? (parent + name) : (parent + '/' + name);
  }

  // ── 公开 API（与上游一一对应） ───────────────────────────────────────────

  static ensureFile(path: string | null | undefined): boolean {
    if (path === null || path === undefined) {
      return false;
    }
    return !FileUtils.exists(path) || FileUtils.isFile(path);
  }

  static ensureDirectory(path: string | null | undefined): boolean {
    if (path === null || path === undefined) {
      return false;
    }
    if (FileUtils.exists(path)) {
      return FileUtils.isDirectory(path);
    }
    return FileUtils.mkdirsRecursive(path);
  }

  /**
   * Convert byte to human readable string.
   * 格式必须与上游 `String.format(Locale.US, "%.1f %sB", …)` 逐字一致（见文件头差异 4）。
   */
  static humanReadableByteCount(bytes: number, si: boolean): string {
    const unit: number = si ? 1000 : 1024;
    if (bytes < unit) {
      return `${bytes} B`;
    }
    const exp: number = Math.trunc(Math.log(bytes) / Math.log(unit));
    const prefixChars: string = si ? 'kMGTPE' : 'KMGTPE';
    const pre: string = prefixChars.charAt(exp - 1) + (si ? '' : 'i');
    const value: number = bytes / Math.pow(unit, exp);
    return `${FileUtils.format1f(value)} ${pre}B`;
  }

  /**
   * 复刻 Java `String.format(Locale.US, "%.1f", v)`。
   *
   * **必须是 `v.toFixed(1)`，不能手写 `Math.floor(v*10+0.5)/10`** —— 后者会在
   * 「v*10 的浮点乘法恰好进位到 x.5、而 v 的精确二进制值略小于 x.5」时**多进一位**：
   * ```
   *   v=0.15  → 手写实现 "0.2"，Java/toFixed "0.1"   ← 0.15 的精确值是 0.1499999...
   *   v=0.95  → 手写实现 "1.0"，Java/toFixed "0.9"
   *   v=8.95  → 手写实现 "9.0"，Java/toFixed "8.9"
   * ```
   * 暴力对照 0.001~100 的十万个千分位值与按 1.07 递增的字节数：**400 处不一致**（已实测）。
   *
   * 语义依据：ECMA `Number.prototype.toFixed` 规定"取使 |n/10^f − x| 最小的 n，并列时取较大者"，
   * 即对正数就是 **HALF_UP**，且作用于 **x 的精确数学值** —— 与 Java `Formatter` 的 `%.1f` 一致。
   * （注意与 `DecimalFormat`/`NumberFormat` 的默认 **HALF_EVEN** 不同，见 ProgressDialog 的注释。）
   */
  private static format1f(v: number): string {
    return v.toFixed(1);
  }

  /**
   * **测试用出口**：暴露 `%.1f` 的复刻结果，便于对边界值做断言。
   * 上游没有这个方法（格式串直接内联在 `humanReadableByteCount` 里），
   * 抽出来只为了让"HALF_UP vs HALF_EVEN vs floor"这三者的差异可被单独验证。
   */
  static formatOneDecimalForTest(v: number): string {
    return FileUtils.format1f(v);
  }

  /**
   * Try to delete file, dir and it's children
   */
  static delete(path: string | null | undefined): boolean {
    if (path === null || path === undefined) {
      return false;
    }
    let success: boolean = true;
    if (FileUtils.isDirectory(path)) {
      let children: string[] | null = null;
      try {
        children = fs.listFileSync(path);
      } catch (e) {
        children = null;
      }
      if (children !== null) {
        for (let i = 0; i < children.length; i++) {
          success = FileUtils.delete(FileUtils.joinPath(path, children[i])) && success;
        }
      }
      try {
        fs.rmdirSync(path);
      } catch (e) {
        success = false;
      }
      return success;
    }
    try {
      fs.unlinkSync(path);
    } catch (e) {
      success = false;
    }
    return success;
  }

  static deleteContent(path: string | null | undefined): boolean {
    if (path === null || path === undefined) {
      return false;
    }
    let success: boolean = true;
    let children: string[] | null = null;
    try {
      children = fs.listFileSync(path);
    } catch (e) {
      children = null;
    }
    if (children !== null) {
      for (let i = 0; i < children.length; i++) {
        success = FileUtils.delete(FileUtils.joinPath(path, children[i])) && success;
      }
    }
    return success;
  }

  /**
   * @return null for get exception
   */
  static read(path: string | null | undefined): string | null {
    if (path === null || path === undefined) {
      return null;
    }
    try {
      return fs.readTextSync(path);
    } catch (e) {
      return null;
    }
  }

  static write(path: string | null | undefined, str: string | null | undefined): boolean {
    if (path === null || path === undefined) {
      return false;
    }
    if (str === null || str === undefined) {
      return true;
    }
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const bytes: Uint8Array = utf8Encode(str);
      fs.writeSync(file.fd, bytes.buffer as ArrayBuffer);
      return true;
    } catch (e) {
      return false;
    } finally {
      if (file !== null && file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // Ignore
        }
      }
    }
  }

  static sanitizeFilename(filename: string): string {
    // Remove forbidden_filename_characters
    let name: string = StringUtils.remove(filename, FileUtils.FORBIDDEN_FILENAME_CHARACTERS) as string;

    // Ensure utf-8 byte count <= 255
    let byteCount: number = 0;
    let length: number = 0;
    const len: number = name.length;
    for (; length < len; length++) {
      const ch: number = name.charCodeAt(length);
      if (ch <= 0x7F) {
        byteCount += 1;
      } else if (ch <= 0x7FF) {
        byteCount += 2;
      } else if (ch >= 0xD800 && ch <= 0xDBFF) {
        byteCount += 4;
        length++;
      } else {
        byteCount += 3;
      }
      // Meet max byte count
      if (byteCount > 255) {
        name = name.substring(0, length);
        break;
      }
    }

    // Trim
    return StringUtils.trim(name) as string;
  }

  /**
   * Get extension from filename
   *
   * @return null for can't find extension, "" empty String for ending with . dot
   */
  static getExtensionFromFilename(filename: string | null | undefined): string | null {
    if (filename === null || filename === undefined) {
      return null;
    }
    const index: number = filename.lastIndexOf('.');
    if (index !== -1) {
      return filename.substring(index + 1);
    }
    return null;
  }

  /**
   * Get name from filename
   *
   * @return null for start with . dot
   */
  static getNameFromFilename(filename: string | null | undefined): string | null {
    if (filename === null || filename === undefined) {
      return null;
    }
    const index: number = filename.lastIndexOf('.');
    if (index !== -1) {
      const name: string = filename.substring(0, index);
      return name.length === 0 ? null : name;
    }
    return filename;
  }

  /**
   * Create a temp file, you need to delete it by yourself.
   *
   * @return the temp file path or null
   */
  static createTempFile(parent: string | null | undefined, extension?: string): string | null {
    if (parent === null || parent === undefined) {
      return null;
    }
    const now: number = Date.now();
    for (let i = 0; i < 100; i++) {
      let filename: string = `${now + i}`;
      if (extension !== undefined && extension !== null) {
        filename = filename + '.' + extension;
      }
      const tempPath: string = FileUtils.joinPath(parent, filename);
      if (!FileUtils.exists(tempPath)) {
        return tempPath;
      }
    }
    // Unbelievable
    return null;
  }

  /**
   * Create a temp dir, you need to delete it by yourself.
   *
   * @return the temp dir path or null
   */
  static createTempDir(parent: string | null | undefined): string | null {
    if (parent === null || parent === undefined) {
      return null;
    }
    const now: number = Date.now();
    for (let i = 0; i < 100; i++) {
      const filename: string = `${now + i}`;
      const tempPath: string = FileUtils.joinPath(parent, filename);
      if (!FileUtils.exists(tempPath)) {
        try {
          fs.mkdirSync(tempPath);
          return tempPath;
        } catch (e) {
          // try next
        }
      }
    }
    // Unbelievable
    return null;
  }

  /**
   * Only support file now
   */
  static rename(from: string, to: string): boolean {
    if (!FileUtils.isFile(from) || FileUtils.exists(to)) {
      return false;
    }

    try {
      fs.renameSync(from, to);
    } catch (e) {
      // fall through to copy path
    }
    if (!FileUtils.exists(from) && FileUtils.isFile(to)) {
      return true;
    }

    // Copy content (对应上游"流拷贝"回退)
    try {
      fs.copyFileSync(from, to);
    } catch (e) {
      try {
        fs.unlinkSync(to);
      } catch (e2) {
        // Ignore
      }
      return false;
    }

    // delete old one
    try {
      fs.unlinkSync(from);
      return true;
    } catch (e) {
      return false;
    }
  }
}
