/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0411   上游: com/hippo/lib/yorozuya/IOUtils.java（123 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/IOUtils.ets
 *
 * 平台差异（java.io → ArkTS）：
 *  1. **java.io.InputStream / OutputStream / Closeable 在 ArkTS 不存在**，且鸿蒙的文件 IO 是
 *     `@ohos.file.fs`（同步 fs.File 句柄 + ArrayBuffer），没有流对象。
 *     本文件按 CONTRACTS C-3 提供三个最小契约接口，供 yorozuya 内部与 net-parse/okhttp 实现：
 *       Closable          { close(): void }
 *       InputStreamLike   { read(buffer: ArrayBuffer): number }   ← 返回读到的字节数，-1 表示 EOF
 *       OutputStreamLike  { write(buffer: ArrayBuffer, offset: number, length: number): void }
 *     语义逐条对齐 Java：`read` 先填满 buffer 再返回（若流已尽返回 -1），`write` 写到 buffer 的
 *     [offset, offset+length)。**这是新增层**，已在 MR"新增项"表登记（不新增文件，随 IOUtils 一起）。
 *  2. `copy(InputStream, OutputStream)` 的 4KB 缓冲区保留（DEFAULT_BUFFER_SIZE = 1024*4）。
 *  3. `readAsciiLine` 逐字节读到 '\n'，去掉行尾 '\r'；EOF 抛 **EOFException** → ArkTS 用
 *     `class EOFException extends Error`（类名与语义保留，message 为空，与 Java 的 new EOFException() 一致）。
 *     超长行抛 IOException("Line too long") → `class IOException extends Error`，消息串逐字。
 *  4. `readString(is, encoding)`：上游所有调用点都传 "utf-8"，故**内置手写 UTF-8 解码**
 *     （不依赖 `@ohos.util.TextDecoder`，便于单测且零平台依赖）；传其它编码抛
 *     Error("IOUtils.readString: only utf-8 is supported, got <enc>")。若将来需要 GBK 等，
 *     改为注入 TextDecoder（属新增能力，需登记）。
 *  5. `getAllByte` 的 ByteArrayOutputStream → 累积 number[] 后转 Uint8Array(再取 buffer)。
 *  6. `closeQuietly(Closeable)` 吞掉 close 异常（与上游一致，注释 "Don't worry about anything"）。
 */

/** 对应 java.io.Closeable */
export interface Closable {
  close(): void;
}

/** 对应 java.io.InputStream 的最小面（read 返回 -1 表示 EOF） */
export interface InputStreamLike {
  read(buffer: ArrayBuffer): number;
}

/** 对应 java.io.OutputStream 的最小面 */
export interface OutputStreamLike {
  write(buffer: ArrayBuffer, offset: number, length: number): void;
}

/** 对应 java.io.EOFException（message 为空，与上游 new EOFException() 一致） */
export class EOFException extends Error {
  constructor() {
    super('');
    this.name = 'EOFException';
  }
}

/** 对应 java.io.IOException */
export class IOException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'IOException';
  }
}

/**
 * 手写 UTF-8 解码（见文件头差异 4）。
 * 非法字节序列输出 U+FFFD（Java 的 CharsetDecoder 默认 REPLACE 行为）。
 */
export function utf8Decode(bytes: Uint8Array, length: number): string {
  const out: string[] = [];
  let i: number = 0;
  const n: number = length < 0 ? bytes.length : length;
  while (i < n) {
    const b0: number = bytes[i];
    if (b0 < 0x80) {
      out.push(String.fromCharCode(b0));
      i += 1;
    } else if ((b0 & 0xE0) === 0xC0) {
      if (i + 1 >= n) {
        out.push('\uFFFD');
        break;
      }
      const b1: number = bytes[i + 1];
      out.push(String.fromCharCode(((b0 & 0x1F) << 6) | (b1 & 0x3F)));
      i += 2;
    } else if ((b0 & 0xF0) === 0xE0) {
      if (i + 2 >= n) {
        out.push('\uFFFD');
        break;
      }
      const b1: number = bytes[i + 1];
      const b2: number = bytes[i + 2];
      out.push(String.fromCharCode(((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)));
      i += 3;
    } else if ((b0 & 0xF8) === 0xF0) {
      if (i + 3 >= n) {
        out.push('\uFFFD');
        break;
      }
      const b1: number = bytes[i + 1];
      const b2: number = bytes[i + 2];
      const b3: number = bytes[i + 3];
      let cp: number = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
      cp -= 0x10000;
      out.push(String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)));
      i += 4;
    } else {
      out.push('\uFFFD');
      i += 1;
    }
  }
  return out.join('');
}

/** 手写 UTF-8 编码（代理对正确处理） */
export function utf8Encode(str: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < str.length; i++) {
    let cp: number = str.charCodeAt(i);
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < str.length) {
      const low: number = str.charCodeAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        cp = ((cp - 0xD800) << 10) + (low - 0xDC00) + 0x10000;
        i++;
      }
    }
    if (cp < 0x80) {
      bytes.push(cp);
    } else if (cp < 0x800) {
      bytes.push(0xC0 | (cp >> 6));
      bytes.push(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      bytes.push(0xE0 | (cp >> 12));
      bytes.push(0x80 | ((cp >> 6) & 0x3F));
      bytes.push(0x80 | (cp & 0x3F));
    } else {
      bytes.push(0xF0 | (cp >> 18));
      bytes.push(0x80 | ((cp >> 12) & 0x3F));
      bytes.push(0x80 | ((cp >> 6) & 0x3F));
      bytes.push(0x80 | (cp & 0x3F));
    }
  }
  const u: Uint8Array = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    u[i] = bytes[i];
  }
  return u;
}

export class IOUtils {

  static readonly EOF: number = -1;
  static readonly DEFAULT_BUFFER_SIZE: number = 1024 * 4;
  static readonly MAX_LINE_LENGTH: number = 131072; // 128KB

  /**
   * Close the closeable stuff. Don't worry about anything.
   */
  static closeQuietly(is: Closable | null | undefined): void {
    try {
      if (is !== null && is !== undefined) {
        is.close();
      }
    } catch (e) {
      // Ignore
    }
  }

  /**
   * Copy bytes from an InputStream to an OutputStream.
   *
   * @return the number of bytes copied
   */
  static copy(input: InputStreamLike, output: OutputStreamLike): number {
    const buffer: ArrayBuffer = new ArrayBuffer(IOUtils.DEFAULT_BUFFER_SIZE);
    let count: number = 0;
    let n: number;
    while (IOUtils.EOF !== (n = input.read(buffer))) {
      output.write(buffer, 0, n);
      count += n;
    }
    return count;
  }

  /**
   * Returns the ASCII characters up to but not including the next "\r\n", or "\n".
   *
   * @throws EOFException if the stream is exhausted before the next newline character
   * @throws IOException  if the line exceeds maxLength (prevents OOM on corrupted files)
   */
  static readAsciiLine(inStream: InputStreamLike, maxLength?: number): string {
    const limit: number = (maxLength === undefined) ? IOUtils.MAX_LINE_LENGTH : maxLength;
    const one: ArrayBuffer = new ArrayBuffer(1);
    const view: Uint8Array = new Uint8Array(one);
    const result: string[] = [];
    while (true) {
      const n: number = inStream.read(one);
      if (n === IOUtils.EOF || n === 0) {
        throw new EOFException();
      }
      const c: number = view[0];
      if (c === 0x0A /* '\n' */) {
        break;
      }
      if (result.length >= limit) {
        throw new IOException('Line too long');
      }
      result.push(String.fromCharCode(c));
    }
    if (result.length > 0 && result[result.length - 1] === '\r') {
      result.pop();
    }
    return result.join('');
  }

  /**
   * 对应上游 readString(InputStream, String encoding)。
   * 仅支持 utf-8（上游全部调用点都是 utf-8，见文件头差异 4）。
   */
  static readString(is: InputStreamLike, encoding: string): string {
    const enc: string = (encoding === null || encoding === undefined) ? '' : encoding.toLowerCase();
    if (enc !== 'utf-8' && enc !== 'utf8') {
      throw new Error(`IOUtils.readString: only utf-8 is supported, got ${encoding}`);
    }
    const buffer: ArrayBuffer = new ArrayBuffer(IOUtils.DEFAULT_BUFFER_SIZE);
    const view: Uint8Array = new Uint8Array(buffer);
    const out: string[] = [];
    let n: number;
    while (IOUtils.EOF !== (n = is.read(buffer))) {
      if (n > 0) {
        out.push(utf8Decode(view, n));
      }
    }
    return out.join('');
  }

  /** 对应上游 getAllByte(InputStream) */
  static getAllByte(is: InputStreamLike): Uint8Array {
    const buffer: ArrayBuffer = new ArrayBuffer(IOUtils.DEFAULT_BUFFER_SIZE);
    const view: Uint8Array = new Uint8Array(buffer);
    const all: number[] = [];
    let n: number;
    while (IOUtils.EOF !== (n = is.read(buffer))) {
      for (let i = 0; i < n; i++) {
        all.push(view[i]);
      }
    }
    const result: Uint8Array = new Uint8Array(all.length);
    for (let i = 0; i < all.length; i++) {
      result[i] = all[i];
    }
    return result;
  }
}
