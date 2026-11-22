/*
 * 对位上游：app/src/main/java/com/hippo/unifile/UriOutputStream.java
 *
 * 上游为什么存在这个类（原注释保留）：
 *   Context.getContentResolver().openOutputStream() 与 FileProvider 的 uri 在写入时可能抛
 *   java.io.IOException: write failed: EBADF (Bad file descriptor)，而先拿 ParcelFileDescriptor
 *   再包一层 FileOutputStream 可以规避。
 *
 * 鸿蒙对位：
 *   - 鸿蒙没有 ParcelFileDescriptor/FileProvider 这一层，"URI → fd" 由 fs.openSync(target, mode)
 *     直接完成（API 明确支持传 URI），底层是 VFS fd，不存在上游那个 EBADF 场景。
 *   - 因此本类保留「按 mode 显式打开」的语义（"w" 覆盖 / "wa" 追加），
 *     实现体委托给 Contracts.FsOutputStream，close() 幂等。
 *   - mode 串与上游保持一致，方便调用点（MediaFile/SingleDocumentFile/TreeDocumentFile）零改动。
 */

import { OutputStream, Contracts } from './Contracts';
import { Utils } from './Utils';

const TAG: string = 'UriOutputStream';

export class UriOutputStream implements OutputStream {
  private readonly out: OutputStream;
  private closed: boolean = false;

  private constructor(out: OutputStream) {
    this.out = out;
  }

  /**
   * 对位上游 UriOutputStream.create(context, uri, mode)。
   * mode: "w" 覆盖写 / "wa" 追加写（与 Android ContentResolver 的 openOutputStream mode 一致）。
   */
  static create(target: string, mode: string): UriOutputStream {
    const append: boolean = mode === 'wa';
    try {
      return new UriOutputStream(Contracts.openOutputStreamAppend(target, append));
    } catch (e) {
      Utils.throwIfFatal(e);
      throw new Error(`Can't get OutputStream: ${target}`);
    }
  }

  write(buffer: ArrayBuffer): void {
    this.ensureOpen();
    this.out.write(buffer);
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    this.ensureOpen();
    this.out.writeBytes(buffer, off, len);
  }

  flush(): void {
    this.ensureOpen();
    this.out.flush();
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      this.out.close();
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logW(TAG, 'Failed to close underlying stream');
    }
  }

  private ensureOpen(): void {
    if (this.closed) {
      throw new Error('Stream closed');
    }
  }
}
