/*
 * 对位上游：app/src/main/java/com/hippo/unifile/FileDescriptorRandomAccessFile.java
 *
 * 平台对位：
 *   - 上游用 android.system.Os 的 lseek/fstat/ftruncate/read/write/close 直接操作 FileDescriptor。
 *     鸿蒙 SDK 20 的 fs.lseek 已可用：seek() 直接调用 fs.lseek(fd, pos, WhenceType.SEEK_SET)
 *     移动内核文件指针，并同步维护用户态逻辑指针 pointer（getFilePointer() 使用）；
 *     readSync/writeSync 不传 offset，让内核顺序推进，避免与 FilePointer 双重推进（见 F-3 裁决）。
 *   - 模式串沿用 java.io.RandomAccessFile 的 "r"/"rw"/"rws"/"rwd"。
 *     "rws"（每写 fsync）鸿蒙有 fs.fsyncSync；"rwd"（fdatasync）鸿蒙没有对应 API，
 *     退化为 fsyncSync —— 语义更严格（元数据也刷），不会丢数据。TODO(平台)：API 出现 fdatasync 后替换。
 *   - 上游用 ParcelFileDescriptor 保证 URI 授权；鸿蒙把授权落在路径/URI 本身，
 *     打开走 fs.openSync(target)（target 可以是 URI），故不再需要 pfd 包装层。
 */

import fs from '@ohos.file.fs';
import { UniRandomAccessFile, RandomAccessMode } from './UniRandomAccessFile';
import { Utils } from './Utils';
import { Contracts } from './Contracts';

const TAG: string = 'FileDescriptorRandomAccessFile';

const FLUSH_NONE: number = 0;
const FLUSH_FSYNC: number = 1;
const FLUSH_FDATASYNC: number = 2;

export class FileDescriptorRandomAccessFile implements UniRandomAccessFile {
  private readonly file: fs.File;
  private readonly fd: number;
  private readonly mode: string;
  private readonly flushAfterWrite: number;
  private pointer: number = 0;
  private closed: boolean = false;
  private readonly closeLock: Object = new Object();

  private constructor(file: fs.File, mode: string) {
    this.file = file;
    this.fd = file.fd;
    this.mode = mode;
    if (mode === RandomAccessMode.RWS) {
      this.flushAfterWrite = FLUSH_FSYNC;
    } else if (mode === RandomAccessMode.RWD) {
      this.flushAfterWrite = FLUSH_FDATASYNC;
    } else {
      this.flushAfterWrite = FLUSH_NONE;
    }
  }

  /**
   * 对位上游 FileDescriptorRandomAccessFile.create(context, uri, mode)。
   * target 接受绝对路径或 file:// URI。
   */
  static create(target: string, mode: string): FileDescriptorRandomAccessFile {
    if (mode !== RandomAccessMode.R && mode !== RandomAccessMode.RW
      && mode !== RandomAccessMode.RWS && mode !== RandomAccessMode.RWD) {
      throw new Error(`IllegalArgumentException: Illegal mode "${mode}" must be one of "r", "rw", "rws", or "rwd"`);
    }
    if (mode === RandomAccessMode.R) {
      try {
        const readFile: fs.File = Contracts.openReadFile(target);
        return new FileDescriptorRandomAccessFile(readFile, mode);
      } catch (e) {
        Utils.throwIfFatal(e);
        throw new Error(`Can't get FileDescriptor: ${target}`);
      }
    }
    const openMode: number = fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE;
    if (Contracts.isUri(target)) {
      try {
        const uriFile: fs.File = fs.openSync(target, openMode);
        return new FileDescriptorRandomAccessFile(uriFile, mode);
      } catch (e) {
        Utils.throwIfFatal(e);
        Utils.logW(TAG, `create direct URI rw fallback to path: ${target}`);
      }
    }
    const path: string = Contracts.toPath(target);
    let file: fs.File;
    try {
      file = fs.openSync(path, openMode);
    } catch (e) {
      Utils.throwIfFatal(e);
      throw new Error(`Can't get FileDescriptor: ${target}`);
    }
    return new FileDescriptorRandomAccessFile(file, mode);
  }

  /** 已关闭则抛（上游对已关闭句柄的操作会抛 IOException）。 */
  private ensureOpen(): void {
    if (this.closed) {
      throw new Error('File is closed');
    }
  }

  private maybeSync(): void {
    if (this.flushAfterWrite === FLUSH_NONE) {
      return;
    }
    try {
      fs.fsyncSync(this.fd);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logW(TAG, `fsync failed: ${this.fd}`);
    }
  }

  close(): void {
    // 幂等关闭：上游用 synchronized(closeLock) + volatile closed 保证
    let needClose: boolean = false;
    // ArkTS 无线程可抢占的临界区语义差异：本工程句柄不跨线程共享，标记-判断足够
    if (!this.closed) {
      this.closed = true;
      needClose = true;
    }
    if (!needClose) {
      return;
    }
    try {
      fs.closeSync(this.file);
    } catch (e) {
      Utils.throwIfFatal(e);
      throw new Error('An error occurs while closing');
    }
  }

  getFilePointer(): number {
    this.ensureOpen();
    return this.pointer;
  }

  seek(pos: number): void {
    this.ensureOpen();
    if (pos < 0) {
      throw new Error(`offset < 0: ${pos}`);
    }
    // ⚠ F-3 裁决：read/write **不再传 offset**（`ReadOptions.offset` 是 filePointer+offset，
    // 会与内核指针双重推进）。所以 seek 必须**显式移动内核指针**，否则后续读写位置全错。
    fs.lseek(this.fd, pos, fs.WhenceType.SEEK_SET);
    this.pointer = pos;
  }

  skipBytes(n: number): number {
    this.ensureOpen();
    if (n <= 0) {
      return 0;
    }
    const pos: number = this.pointer;
    const len: number = this.length();
    let newPos: number = pos + n;
    if (newPos > len) {
      newPos = len;
    }
    this.seek(newPos);
    return newPos - pos;
  }

  length(): number {
    this.ensureOpen();
    try {
      const st: fs.Stat = fs.statSync(this.fd);
      return st.size;
    } catch (e) {
      Utils.throwIfFatal(e);
      throw new Error('An error occurs while getting file size');
    }
  }

  setLength(newLength: number): void {
    this.ensureOpen();
    if (newLength < 0) {
      throw new Error('newLength < 0');
    }
    try {
      fs.truncateSync(this.fd, newLength);
    } catch (e) {
      Utils.throwIfFatal(e);
      throw new Error('An error occurs while truncating');
    }
    if (this.pointer > newLength) {
      this.seek(newLength);
    }
    this.maybeSync();
  }

  read(buffer: ArrayBuffer): number {
    return this.readBytes(buffer, 0, buffer.byteLength);
  }

  private static validateRange(buffer: ArrayBuffer, off: number, len: number): void {
    if (off < 0 || len < 0 || off + len > buffer.byteLength) {
      throw new RangeError(
        `IndexOutOfBoundsException: off=${off}, len=${len}, byteLength=${buffer.byteLength}`
      );
    }
  }

  readBytes(buffer: ArrayBuffer, off: number, len: number): number {
    this.ensureOpen();
    FileDescriptorRandomAccessFile.validateRange(buffer, off, len);
    if (len === 0) {
      return 0;
    }
    let n: number = 0;
    if (off === 0) {
      n = fs.readSync(this.fd, buffer, { length: len });
    } else {
      const tmp: ArrayBuffer = new ArrayBuffer(len);
      n = fs.readSync(this.fd, tmp, { length: len });
      if (n > 0) {
        new Uint8Array(buffer, off, n).set(new Uint8Array(tmp, 0, n));
      }
    }
    if (n > 0) {
      this.pointer += n;
      return n;
    }
    return -1;
  }

  write(buffer: ArrayBuffer): void {
    this.writeBytes(buffer, 0, buffer.byteLength);
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    this.ensureOpen();
    FileDescriptorRandomAccessFile.validateRange(buffer, off, len);
    if (len === 0) {
      return;
    }
    let n: number = 0;
    if (off === 0) {
      n = fs.writeSync(this.fd, buffer, { length: len });
    } else {
      const slice: ArrayBuffer = buffer.slice(off, off + len);
      n = fs.writeSync(this.fd, slice, { length: len });
    }
    this.pointer += n;
    this.maybeSync();
  }

  /** 对位上游 @IntDef FlushMode，仅供调用点表达意图。 */
  getFlushMode(): number {
    return this.flushAfterWrite;
  }
}
