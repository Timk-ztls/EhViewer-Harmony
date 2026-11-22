/*
 * 对位上游：app/src/main/java/com/hippo/unifile/RawRandomAccessFile.java
 *
 * 平台对位：
 *   - 上游是 java.io.RandomAccessFile 的薄包装（RawFile 用 new RandomAccessFile(file, mode) 构造）。
 *     鸿蒙没有按路径的 RandomAccessFile，等价底座是 FileDescriptorRandomAccessFile（fd + 用户态指针），
 *     因此本类退化为「对 FileDescriptorRandomAccessFile 的委托」，方法集合与上游一字不差，
 *     调用点（UniFile.createRandomAccessFile / Spider / 老式编辑器）零改动。
 *   - 语义一致性：上游所有方法直接透传，故本类同样不做任何检查，异常由底座抛出。
 */

import { UniRandomAccessFile } from './UniRandomAccessFile';
import { FileDescriptorRandomAccessFile } from './FileDescriptorRandomAccessFile';

export class RawRandomAccessFile implements UniRandomAccessFile {
  private readonly mFile: FileDescriptorRandomAccessFile;

  constructor(file: FileDescriptorRandomAccessFile) {
    this.mFile = file;
  }

  /** 便利构造：对位上游 new RawRandomAccessFile(new RandomAccessFile(file, mode))。 */
  static open(target: string, mode: string): RawRandomAccessFile {
    return new RawRandomAccessFile(FileDescriptorRandomAccessFile.create(target, mode));
  }

  close(): void {
    this.mFile.close();
  }

  getFilePointer(): number {
    return this.mFile.getFilePointer();
  }

  seek(pos: number): void {
    this.mFile.seek(pos);
  }

  skipBytes(n: number): number {
    return this.mFile.skipBytes(n);
  }

  length(): number {
    return this.mFile.length();
  }

  setLength(newLength: number): void {
    this.mFile.setLength(newLength);
  }

  read(buffer: ArrayBuffer): number {
    return this.mFile.read(buffer);
  }

  readBytes(buffer: ArrayBuffer, off: number, len: number): number {
    return this.mFile.readBytes(buffer, off, len);
  }

  write(buffer: ArrayBuffer): void {
    this.mFile.write(buffer);
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    this.mFile.writeBytes(buffer, off, len);
  }
}
