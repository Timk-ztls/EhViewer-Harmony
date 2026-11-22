/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0280   上游: com/hippo/ehviewer/util/GZIPUtils.java（249 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/util/GZIPUtils.ets
 *
 * 上游六个方法分两类：
 *  A. **gzip + Base64 字符串压缩**：`compress(String)` / `uncompress(String)`
 *  B. **ZIP 目录打包/解包**：`UnZipFolder` / `ZipFolder` / `ZipFiles`（private）/ `UpZip` / `GetFileList`
 *
 * 平台差异：
 *  1. ArkTS **没有内存态 gzip**（`@ohos.zlib` 只有 `compressFile/decompressFile`，走文件路径）
 *     → 编解码注入 `gzip: (bytes) => Promise<Uint8Array>` / `gunzip`，语义与 `GZIPOutputStream` 等价。
 *  2. `android.util.Base64.DEFAULT` 的两个行为必须复刻（否则存下来的字符串形态不同）：
 *       · 编码：**每 76 字符换行**（`\n`），末尾也带一个 `\n`
 *       · 解码：**忽略所有空白**（换行、空格）
 *     用 `util.Base64Helper` 的 `NO_WRAP` 会得到不同形态 → 自己实现（断言钉死）。
 *  3. `new String(bytes)` / `str.getBytes()` → `UTF-8` 编解码（`TextEncoder`/`TextDecoder`）。
 *     ⚠️ 上游 `out.toString()` 用的是**平台默认字符集**（Android 上是 UTF-8）；这里固定 UTF-8。
 *  4. `ZipFile/ZipInputStream/ZipOutputStream/File*` → 注入 `ZipIoLike`（鸿蒙用
 *     `@ohos.zlib` 的文件能力 + `@ohos.file.fs` 遍历）。
 *  5. **一处安全修复（B 类，已注明）**：上游 `UnZipFolder` 只对**文件**条目做 `..` 检查：
 *     ```java
 *     if (zipEntry.isDirectory()) { ... folder.mkdirs(); }      // ← 无检查
 *     else { if (szName.contains("..")) continue; ... }        // ← 有检查
 *     ```
 *     即"目录条目可以 `mkdirs()` 到目标目录之外"（zip-slip 的目录变体，只建空目录，影响小但真实）。
 *     本实现**两个分支都检查**（用户不可感知的正确性修复，按陷阱 63 属 B 类 → 修）。
 */

import util from '@ohos.util';

/** ZIP 读写的最小契约（`ZipIoLike` 由 ui-scene / download 侧用 @ohos.zlib 实现） */
export interface ZipIoLike {
  /** 列出 zip 内所有条目名（目录条目以上游同样形态带尾部 '/'） */
  listEntries(zipPath: string): Promise<string[]>;

  /** 把单个条目解到目标路径（父目录已由调用方确保） */
  extractEntry(zipPath: string, entryName: string, targetPath: string): Promise<void>;

  /** 目标是否已存在（文件或目录） */
  exists(path: string): Promise<boolean>;

  /** 建目录（含父目录），失败返回 false */
  mkdirs(path: string): Promise<boolean>;

  /** 建空文件，失败返回 false */
  createFile(path: string): Promise<boolean>;

  /** 打开条目为可读流（上游 `UpZip` 返回 InputStream） */
  openEntryStream(zipPath: string, entryName: string): Promise<Object | null>;
}

export class GZIPUtils {

  /** `android.util.Base64.DEFAULT` 的换行宽度 */
  static readonly BASE64_WRAP_WIDTH: number = 76;

  /**
   * 对应上游 `compress(primStr)`：**null 或空串原样返回**（上游第一行就 return），
   * 否则 `Base64.DEFAULT.encode(gzip(utf8Bytes))`。
   */
  static async compress(primStr: string | null,
    gzip: (bytes: Uint8Array) => Promise<Uint8Array>): Promise<string | null> {
    if (primStr === null || primStr.length === 0) {
      return primStr;
    }
    const raw: Uint8Array = new util.TextEncoder().encodeInto(primStr);
    const gz: Uint8Array = await gzip(raw);
    return GZIPUtils.encodeBase64Default(gz);
  }

  /**
   * 对应上游 `uncompress(compressedStr)`：**null 返回 null**；解码/解压失败返回 null
   * （上游 catch IOException 后 `decompressed` 保持 null）。
   */
  static async uncompress(compressedStr: string | null,
    gunzip: (bytes: Uint8Array) => Promise<Uint8Array>): Promise<string | null> {
    if (compressedStr === null) {
      return null;
    }
    try {
      const compressed: Uint8Array = GZIPUtils.decodeBase64Default(compressedStr);
      const raw: Uint8Array = await gunzip(compressed);
      return new util.TextDecoder().decodeToString(raw);
    } catch (e) {
      return null;
    }
  }

  /**
   * 对应上游 `GetFileList(zipFileString, bContainFolder, bContainFile)`：
   * 遍历条目名，按两个开关筛选。**目录条目以尾部 '/' 判定**（与上游 `zipEntry.isDirectory()` 同义，
   * 因为 ZIP 规范里目录条目名必以 '/' 结尾）。
   */
  static async getFileList(zipPath: string, containFolder: boolean, containFile: boolean,
    io: ZipIoLike): Promise<string[]> {
    const entries: string[] = await io.listEntries(zipPath);
    const result: string[] = [];
    for (let i = 0; i < entries.length; i++) {
      const name: string = entries[i];
      const isFolder: boolean = name.endsWith('/');
      if (isFolder) {
        if (containFolder) {
          result.push(name);
        }
      } else {
        if (containFile) {
          result.push(name);
        }
      }
    }
    return result;
  }

  /**
   * 对应上游 `UnZipFolder(zipFileString, outPathString)`：
   * 目标目录不存在则创建；遍历条目，目录建目录、文件建文件并写入。
   *
   * **两个分支都做 `..` 检查**（上游只对文件做，见文件头差异 5）。
   * @returns 是否全部成功（上游 `false` 的三种来源：父目录建失败 / 建文件失败 / IO 异常）
   */
  static async unZipFolder(zipPath: string, outPath: string, io: ZipIoLike): Promise<boolean> {
    try {
      if (!(await io.exists(outPath))) {
        if (!(await io.mkdirs(outPath))) {
          // 上游 mkdir() 失败不 return，继续尝试 —— 但后续建文件会失败并返回 false
        }
      }
      const entries: string[] = await io.listEntries(zipPath);
      for (let i = 0; i < entries.length; i++) {
        let name: string = entries[i];
        const isFolder: boolean = name.endsWith('/');
        if (isFolder) {
          // get the folder name
          name = name.substring(0, name.length - 1);
          // ⚠️ 上游此处**没有** `..` 检查（见文件头差异 5）—— 这里补上
          if (GZIPUtils.containsDotDot(name)) {
            continue;
          }
          const folder: string = GZIPUtils.joinPath(outPath, name);
          await io.mkdirs(folder);
        } else {
          if (GZIPUtils.containsDotDot(name)) {
            continue; // 上游原样：文件条目含 '..' 直接跳过
          }
          const file: string = GZIPUtils.joinPath(outPath, name);
          const parent: string | null = GZIPUtils.parentOf(file);
          if (parent !== null && !(await io.exists(parent))) {
            if (!(await io.mkdirs(parent))) {
              return false;
            }
          }
          if (!(await io.exists(file))) {
            if (!(await io.createFile(file))) {
              return false;
            }
          }
          await io.extractEntry(zipPath, entries[i], file);
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 对应上游 `UpZip(zipFileString, fileString)`：返回该条目的可读流（找不到 → null） */
  static async upZip(zipPath: string, fileName: string, io: ZipIoLike): Promise<Object | null> {
    return await io.openEntryStream(zipPath, fileName);
  }

  // ── Base64（复刻 android.util.Base64.DEFAULT）──────────────────────────

  private static readonly B64_CHARS: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  /** `Base64.DEFAULT` 编码：标准字母表 + 每 76 字符插 `\n` + 末尾带 `\n` */
  static encodeBase64Default(data: Uint8Array): string {
    let out: string = '';
    const n: number = data.length;
    let i: number = 0;
    while (i < n) {
      const b0: number = data[i++];
      const b1: number = (i < n) ? data[i++] : -1;
      const b2: number = (i < n) ? data[i++] : -1;
      out += GZIPUtils.B64_CHARS.charAt(b0 >> 2);
      out += GZIPUtils.B64_CHARS.charAt(((b0 & 0x03) << 4) | ((b1 < 0 ? 0 : b1) >> 4));
      out += (b1 < 0) ? '=' : GZIPUtils.B64_CHARS.charAt(((b1 & 0x0F) << 2) | ((b2 < 0 ? 0 : b2) >> 6));
      out += (b2 < 0) ? '=' : GZIPUtils.B64_CHARS.charAt(b2 & 0x3F);
    }
    // 每 76 字符换行，末尾补一个换行（Android DEFAULT 行为）
    let wrapped: string = '';
    let p: number = 0;
    while (p < out.length) {
      const end: number = Math.min(p + GZIPUtils.BASE64_WRAP_WIDTH, out.length);
      wrapped += out.substring(p, end) + '\n';
      p = end;
    }
    return wrapped;
  }

  /** `Base64.DEFAULT` 解码：**忽略所有空白**；非法字符抛错（上游会抛 IllegalArgumentException） */
  static decodeBase64Default(s: string): Uint8Array {
    let clean: string = '';
    for (let i = 0; i < s.length; i++) {
      const c: string = s.charAt(i);
      if (c === '\n' || c === '\r' || c === ' ' || c === '\t') {
        continue;
      }
      clean += c;
    }
    let padding: number = 0;
    while (clean.length > 0 && clean.charAt(clean.length - 1) === '=') {
      padding++;
      clean = clean.substring(0, clean.length - 1);
    }
    // 输出长度必须按**带填充的总长度**算：每 4 个字符 3 字节，再减去填充字节数。
    // 只按去掉 '=' 后的长度算会**多出 1~2 个假字节**（末尾半字节被当成完整字节写出）。
    const totalWithPad: number = clean.length + padding;
    if (totalWithPad % 4 !== 0) {
      throw new Error('Bad base-64');
    }
    const outLen: number = (totalWithPad / 4) * 3 - padding;
    const out: Uint8Array = new Uint8Array(outLen);
    let oi: number = 0;
    let buf: number = 0;
    let bits: number = 0;
    for (let i = 0; i < clean.length; i++) {
      const v: number = GZIPUtils.B64_CHARS.indexOf(clean.charAt(i));
      if (v < 0) {
        throw new Error('Bad base-64');
      }
      buf = (buf << 6) | v;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out[oi++] = (buf >> bits) & 0xFF;
      }
    }
    return out;
  }

  // ── 路径工具 ──────────────────────────────────────────────────────────

  /** 上游用 `File.separator`，鸿蒙侧统一用 '/' */
  private static joinPath(base: string, name: string): string {
    if (base.endsWith('/')) {
      return base + name;
    }
    return base + '/' + name;
  }

  private static parentOf(path: string): string | null {
    const idx: number = path.lastIndexOf('/');
    if (idx <= 0) {
      return null;
    }
    return path.substring(0, idx);
  }

  /** 上游 `szName.contains("..")` —— **子串判定**，不是路径段判定（照搬，见断言） */
  private static containsDotDot(name: string): boolean {
    return name.indexOf('..') >= 0;
  }
}