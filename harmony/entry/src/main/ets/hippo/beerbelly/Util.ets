/*
 * Copyright (C) 2012 The Android Open Source Project
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
 */

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/beerbelly/Util.java（inventory S0010，94 行）
 *
 * Junk drawer of utility methods.
 *
 * ArkTS 映射：
 *   java.io.Reader / InputStream / OutputStream → 无对应；改为按 ArkTS 原语提供等价能力：
 *     readFully(Reader)        → readFullyText(path)（读整个文本文件）
 *     copy(InputStream, OutputStream) → copyFile(src, dst)（返回字节数）
 *   java.io.Closeable           → 无该接口；closeQuietly → closeQuietlyFile(fileIo.File)
 *   Charset 常量                → 字符串常量 US_ASCII / UTF_8（ArkTS 无 Charset 对象）
 * 方法名保持（除参数类型带来的必然改名），语义逐行照搬。
 */
import fileIo from '@ohos.file.fs';
import { decodeBytes, utf8Encode } from '../okhttp/RequestBody';

/**
 * `@ohos.file.fs` 的 `File` 结构由平台提供（`fileIo.File`），本层只当类型注解用。
 */
const EOF: number = -1;
const DEFAULT_BUFFER_SIZE: number = 1024 * 4;

export class Util {
  static readonly US_ASCII: string = 'ascii';
  static readonly UTF_8: string = 'utf-8';

  /**
   * 把已打开的 fd 从**当前文件指针**读满 `size` 字节，返回实际读到的内容。
   *
   * ## 为什么不用 `{ offset: pos }`（审计 C 的 F-3）
   * `@ohos.file.fs` 的 `ReadOptions.offset` 是「**文件内**起点（filePointer + offset）」，
   * **不是** Java `read(byte[] b, int off, int len)` 里的「缓冲区下标」。
   * 若把缓冲区进度写进 `offset`，`off = 0` 时恰好对、`off > 0` 时**读的是文件中间**，
   * 且只读到 `size - off` 字节 —— 最坏形态是「首个调用正确、后面全错」。
   *
   * 正确做法：**不传 offset**，让内核 filePointer 自己前进；每次读进临时块再拷进目标缓冲。
   */
  static readFullyTo(fd: number, size: number): ArrayBuffer {
    const dst: ArrayBuffer = new ArrayBuffer(size);
    const dstView: Uint8Array = new Uint8Array(dst);
    let pos: number = 0;
    while (pos < size) {
      const want: number = Math.min(Util.READ_CHUNK, size - pos);
      const chunk: ArrayBuffer = new ArrayBuffer(want);
      const n: number = fileIo.readSync(fd, chunk, { length: want });
      if (n <= 0) {
        break;
      }
      dstView.set(new Uint8Array(chunk, 0, n), pos);
      pos += n;
    }
    return dst.slice(0, pos);
  }

  /** 单次读块大小（只影响系统调用次数，不影响结果）。 */
  static readonly READ_CHUNK: number = 64 * 1024;

  /** 对齐 Util.readFully(Reader)：一次性读完文本。 */
  static readFullyText(path: string): string {
    const size: number = fileIo.statSync(path).size;
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      return decodeBytes(Util.readFullyTo(file.fd, size), Util.UTF_8);
    } finally {
      fileIo.closeSync(file);
    }
  }

  /**
   * 对齐 Util.deleteContents(File)：递归删除 dir 下所有内容，dir 本身保留。
   * 任一文件删不掉即抛错（与上游一致），否则 DiskLruCache 的 readonly 清理会静默失败。
   */
  static deleteContents(dir: string): void {
    let names: string[];
    try {
      names = fileIo.listFileSync(dir);
    } catch (e) {
      throw new Error(`not a readable directory: ${dir}`);
    }
    if (names === null || names === undefined) {
      throw new Error(`not a readable directory: ${dir}`);
    }
    for (let i = 0; i < names.length; i++) {
      const path: string = dir + '/' + names[i];
      const isDir: boolean = Util.isDirectory(path);
      if (isDir) {
        Util.deleteContents(path);
      }
      try {
        if (isDir) {
          fileIo.rmdirSync(path);
        } else {
          fileIo.unlinkSync(path);
        }
      } catch (e) {
        throw new Error(`failed to delete file: ${path}`);
      }
    }
  }

  /** 对齐 Util.closeQuietly(Closeable)。 */
  static closeQuietlyFile(file: fileIo.File | null): void {
    if (file === null) {
      return;
    }
    try {
      fileIo.closeSync(file);
    } catch (e) {
      // 与上游一致：静默
    }
  }

  /** 对齐 Util.copy(InputStream, OutputStream)：返回拷贝字节数。 */
  static copyFile(srcPath: string, dstPath: string): number {
    const src: fileIo.File = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
    const dst: fileIo.File = fileIo.openSync(dstPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC);
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(DEFAULT_BUFFER_SIZE);
      let count: number = 0;
      while (true) {
        const n: number = fileIo.readSync(src.fd, buffer);
        if (n === EOF || n === 0) {
          break;
        }
        const slice: ArrayBuffer = n === buffer.byteLength ? buffer : buffer.slice(0, n);
        fileIo.writeSync(dst.fd, slice);
        count += n;
      }
      return count;
    } finally {
      Util.closeQuietlyFile(src);
      Util.closeQuietlyFile(dst);
    }
  }

  /** 目录判定（对应 File.isDirectory()）。 */
  static isDirectory(path: string): boolean {
    try {
      return fileIo.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  /** 文件存在（对应 File.exists()）。 */
  static exists(path: string): boolean {
    return fileIo.accessSync(path);
  }

  /** 文件长度（对应 File.length()，不存在返回 0）。 */
  static fileLength(path: string): number {
    try {
      return fileIo.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  /** 删除文件（对应 File.delete()，返回是否成功）。 */
  static deleteFile(path: string): boolean {
    try {
      fileIo.unlinkSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 改名（对应 File.renameTo()）。 */
  static rename(src: string, dst: string): boolean {
    try {
      fileIo.renameSync(src, dst);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 写文本（对应 FileWriter 的整段写）。 */
  static writeText(path: string, text: string): void {
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, utf8Encode(text));
    } finally {
      fileIo.closeSync(file);
    }
  }
}
