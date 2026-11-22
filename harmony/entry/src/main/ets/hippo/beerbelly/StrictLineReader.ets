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

import fileIo from '@ohos.file.fs';
import { decodeBytes } from '../okhttp/RequestBody';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/beerbelly/StrictLineReader.java
 * （inventory S0009，177 行）
 *
 * Buffers input from an InputStream for reading lines；行尾 "\n" 或 "\r\n"，输入结束抛 EOF。
 *
 * ArkTS 映射：
 *   java.io.InputStream          → fileIo.File（构造时打开，close() 关闭）
 *   java.io.EOFException         → 本文件的 EOFError（DiskLruCache 靠 instanceof 捕获）
 *   Charset（US-ASCII/UTF-8/ISO-8859-1）→ 仅接受 'ascii' / 'utf-8' / 'iso-8859-1'，
 *     与上游构造函数同一校验（只允许 US_ASCII —— 上游 DiskLruCache 传的就是 US_ASCII）
 *   synchronized (in)            → ArkTS 无对象锁；本类是纯单线程磁盘 journal 读取器，
 *     由 DiskLruCache 的调用点串行化（见 DiskLruCache.ets 的 lock 说明）
 *   ByteArrayOutputStream 匿名子类 → 用 Uint8Array 累积 + 最后一次解码，逻辑等价
 *
 * 状态机（buf/pos/end，end == -1 表示有未终止行）逐行照搬，不做"改进"。
 */

const CR: number = 13; // '\r'
const LF: number = 10; // '\n'
const DEFAULT_CAPACITY: number = 8192;

/** 对齐 java.io.EOFException。 */
export class EOFError extends Error {
  constructor() {
    super('end of stream');
    this.name = 'EOFError';
  }
}

export class StrictLineReader {
  private _file: fileIo.File;
  private _charset: string;
  private _buf: Uint8Array | null;
  private _pos: number = 0;
  private _end: number = 0;

  /** 对齐 StrictLineReader(InputStream, Charset)——容量默认 8192。 */
  constructor(file: fileIo.File, charset: string) {
    if (file === null || charset === null) {
      throw new Error('NullPointerException: in or charset is null');
    }
    if (charset !== 'ascii') {
      throw new Error('IllegalArgumentException: Unsupported encoding');
    }
    this._file = file;
    this._charset = charset;
    this._buf = new Uint8Array(DEFAULT_CAPACITY);
  }

  /** 对齐 StrictLineReader(InputStream, int capacity, Charset)。ArkTS 无重载，用具名工厂。 */
  static withCapacity(file: fileIo.File, capacity: number, charset: string): StrictLineReader {
    const r: StrictLineReader = new StrictLineReader(file, charset);
    // 用指定容量重新分配（保持上游的 capacity 校验顺序）
    r.realloc(capacity);
    return r;
  }

  private realloc(capacity: number): void {
    if (capacity < 0) {
      throw new Error('IllegalArgumentException: capacity <= 0');
    }
    this._buf = new Uint8Array(capacity);
  }

  /** 对齐 close()：关闭底层文件并标记已关闭。 */
  close(): void {
    if (this._buf !== null) {
      this._buf = null;
      fileIo.closeSync(this._file);
    }
  }

  /**
   * 对齐 readLine()：返回不含行尾的一行；输入耗尽抛 EOFError。
   * 若末尾是未终止行，同样抛 EOFError，调用方用 hasUnterminatedLine() 判断。
   */
  readLine(): string {
    if (this._buf === null) {
      throw new Error('IOException: LineReader is closed');
    }
    if (this._pos >= this._end) {
      this.fillBuf();
    }
    const buf: Uint8Array = this._buf as Uint8Array;
    for (let i = this._pos; i !== this._end; ++i) {
      if (buf[i] === LF) {
        const lineEnd: number = (i !== this._pos && buf[i - 1] === CR) ? i - 1 : i;
        const res: string = this.decode(this._pos, lineEnd);
        this._pos = i + 1;
        return res;
      }
    }

    // 缓冲区内没有 LF：把剩余内容搬到 pending，然后继续读缓冲（上游用 ByteArrayOutputStream）
    const pending: number[] = [];
    while (true) {
      for (let i = this._pos; i < this._end; i++) {
        pending.push(buf[i]);
      }
      // 标记未终止行：fillBuf 抛 EOF 时调用方能识别
      this._end = -1;
      this.fillBuf();
      const buf2: Uint8Array = this._buf as Uint8Array;
      for (let i = this._pos; i !== this._end; ++i) {
        if (buf2[i] === LF) {
          if (i !== this._pos) {
            for (let k = this._pos; k < i; k++) {
              pending.push(buf2[k]);
            }
          }
          this._pos = i + 1;
          return this.decodeBytesFromPending(pending);
        }
      }
    }
  }

  /** 对齐 hasUnterminatedLine()。 */
  hasUnterminatedLine(): boolean {
    return this._end === -1;
  }

  /** 对齐 fillBuf()：只应在 pos == end 或 end == -1 时调用。 */
  private fillBuf(): void {
    const buf: Uint8Array = this._buf as Uint8Array;
    const buffer: ArrayBuffer = new ArrayBuffer(buf.byteLength);
    let result: number = 0;
    try {
      result = fileIo.readSync(this._file.fd, buffer);
    } catch (e) {
      throw new Error(`IOException: ${(e as Error).message}`);
    }
    if (result === -1 || result === 0) {
      // 上游：read 返回 -1 → EOFException
      throw new EOFError();
    }
    const read: Uint8Array = new Uint8Array(buffer, 0, result);
    buf.set(read, 0);
    this._pos = 0;
    this._end = result;
  }

  private decode(start: number, end: number): string {
    const buf: Uint8Array = this._buf as Uint8Array;
    const slice: Uint8Array = buf.slice(start, end);
    return decodeBytes(slice.buffer as ArrayBuffer, this._charset);
  }

  private decodeBytesFromPending(pending: number[]): string {
    // 上游 ByteArrayOutputStream.toString() 会去掉末尾的 CR
    let length: number = pending.length;
    if (length > 0 && pending[length - 1] === CR) {
      length = length - 1;
    }
    const arr: Uint8Array = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      arr[i] = pending[i];
    }
    return decodeBytes(arr.buffer as ArrayBuffer, this._charset);
  }
}
