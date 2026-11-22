/*
 * Copyright 2017 Hippo Seven
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import fileIo from '@ohos.file.fs';
import { DiskLruCache, DiskLruCacheEditor, DiskLruCacheSnapshot, FaultHidingWriter } from './DiskLruCache';
import { Util } from './Util';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';
import { OutputStreamPipe, ByteSink } from '../streampipe/OutputStreamPipe';
import { decodeBytes, utf8Encode } from '../okhttp/RequestBody';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/beerbelly/SimpleDiskCache.java
 * （inventory S0008，447 行 / 实测 522 行含注释）
 *
 * 在 DiskLruCache 之上加：MD5 键哈希 + 按 key 的读写锁 + Input/OutputStreamPipe。
 * 上游使用点：EhApplication.getSpiderInfoCache（spiderInfo 缓存）、EhTagDatabase 等。
 *
 * ArkTS 映射：
 *   java.util.concurrent.locks.ReentrantReadWriteLock → 无锁。ArkTS 无线程共享内存，
 *     SimpleDiskCache 的调用方（页面/服务）都在各自 TaskPool 任务内串行访问；
 *     obtainLock/releaseLock 的「状态机 + wait/notifyAll」在单线程下不可达，
 *     故保留 CounterLock 的计数语义（isFree/obtain/release）但不做真正的阻塞等待。
 *   InputStream / OutputStream → fileIo.File / ByteSink（见 streampipe 两文件）
 *   MessageDigest("MD5") → 本文件的纯 TS MD5（保持与上游一致的 32 位小写十六进制键，
 *     使旧缓存目录可被直接复用）
 *   synchronized + wait/notifyAll → 同步方法（无阻塞）
 */
export class SimpleDiskCache {
  private static readonly LOCK_POOL_MAX_SIZE: number = 10;

  private readonly _cacheDir: string;
  private readonly _size: number;
  private readonly _lockMap: Map<string, CounterLock> = new Map<string, CounterLock>();
  private readonly _lockPool: CounterLock[] = [];
  private _diskLruCache: DiskLruCache | null = null;

  constructor(cacheDir: string, size: number) {
    this._cacheDir = cacheDir;
    this._size = size;
    try {
      this.init();
    } catch (e) {
      // 与上游一致：初始化失败只记录（isValid() 会返回 false）
      this._diskLruCache = null;
    }
  }

  /** 对齐 hashKeyForDisk(String)：MD5(key) → 32 位小写十六进制。 */
  static hashKeyForDisk(key: string): string {
    return md5Hex(utf8Encode(key));
  }

  private init(): void {
    if (!this.isValid()) {
      this._diskLruCache = DiskLruCache.open(this._cacheDir, 1, 1, this._size);
    }
  }

  isValid(): boolean {
    return this._diskLruCache !== null;
  }

  size(): number {
    const c: DiskLruCache | null = this._diskLruCache;
    return c === null ? -1 : c.size();
  }

  flush(): void {
    const c: DiskLruCache | null = this._diskLruCache;
    if (c !== null) {
      try {
        (c as DiskLruCache).flush();
      } catch (e) {
        // 与上游一致：flush 失败只记录
      }
    }
  }

  /** 对齐 clear()：删除并重建 DiskLruCache。 */
  clear(): boolean {
    const c: DiskLruCache | null = this._diskLruCache;
    if (c === null) {
      return false;
    }
    let result: boolean = true;
    try {
      (c as DiskLruCache).delete();
    } catch (e) {
      // 上游 clearCache 只记日志而不置 result = false，最终结果由后续 init() 决定（F-5）
    }
    this._diskLruCache = null;
    try {
      this.init();
    } catch (e) {
      result = false;
    }
    return result;
  }

  contain(key: string): boolean {
    const diskKey: string = SimpleDiskCache.hashKeyForDisk(key);
    const c: DiskLruCache | null = this._diskLruCache;
    if (c === null) {
      return false;
    }
    try {
      return (c as DiskLruCache).contain(diskKey);
    } catch (e) {
      return false;
    }
  }

  remove(key: string): boolean {
    const diskKey: string = SimpleDiskCache.hashKeyForDisk(key);
    const c: DiskLruCache | null = this._diskLruCache;
    if (c === null) {
      return false;
    }
    try {
      return (c as DiskLruCache).remove(diskKey);
    } catch (e) {
      return false;
    }
  }

  /** 对齐 put(String, InputStream)：整段写入（源为文件句柄）。 */
  put(key: string, source: fileIo.File): boolean {
    const diskKey: string = SimpleDiskCache.hashKeyForDisk(key);
    const c: DiskLruCache | null = this._diskLruCache;
    if (c === null) {
      return false;
    }
    return this.putToDisk(c as DiskLruCache, diskKey, source);
  }

  /** 对齐 put(String, byte[])：供 ArkTS 侧直接给内存数据。 */
  putBytes(key: string, data: ArrayBuffer): boolean {
    const diskKey: string = SimpleDiskCache.hashKeyForDisk(key);
    const c: DiskLruCache | null = this._diskLruCache;
    if (c === null) {
      return false;
    }
    const cache: DiskLruCache = c as DiskLruCache;
    let editor: DiskLruCacheEditor | null = null;
    let completeEdit: boolean = false;
    try {
      editor = cache.edit(diskKey);
      if (editor === null) {
        return false;
      }
      const out = (editor as DiskLruCacheEditor).newOutputStream(0);
      out.write(data);
      out.close();
      completeEdit = true;
      (editor as DiskLruCacheEditor).commit();
      return true;
    } catch (e) {
      if (!completeEdit && editor !== null) {
        try {
          (editor as DiskLruCacheEditor).abort();
        } catch (e2) {
          // 忽略
        }
      }
      return false;
    }
  }

  private putToDisk(cache: DiskLruCache, key: string, source: fileIo.File): boolean {
    let editor: DiskLruCacheEditor | null = null;
    let completeEdit: boolean = false;
    try {
      editor = cache.edit(key);
      if (editor === null) {
        // The editor is in progress
        return false;
      }
      const out = (editor as DiskLruCacheEditor).newOutputStream(0);
      // Util.copy(is, os)
      const buffer: ArrayBuffer = new ArrayBuffer(8 * 1024);
      while (true) {
        let n: number = 0;
        try {
          n = fileIo.readSync(source.fd, buffer);
        } catch (e) {
          throw new Error(`IOException: read failed: ${(e as Error).message}`);
        }
        if (n <= 0) {
          break;
        }
        out.write(n === buffer.byteLength ? buffer : buffer.slice(0, n));
      }
      out.close();
      completeEdit = true;
      (editor as DiskLruCacheEditor).commit();
      return true;
    } catch (e) {
      if (!completeEdit && editor !== null) {
        try {
          (editor as DiskLruCacheEditor).abort();
        } catch (e2) {
          // 忽略
        }
      }
      return false;
    }
  }

  /** 查询缓存条目的本地文件路径（仅在 clean 文件存在时返回）。 */
  getCacheFilePath(key: string): string | null {
    const diskKey: string = SimpleDiskCache.hashKeyForDisk(key);
    const c: DiskLruCache | null = this._diskLruCache;
    if (c === null) {
      return null;
    }
    try {
      return (c as DiskLruCache).getCleanFilePath(diskKey, 0);
    } catch (_e) {
      return null;
    }
  }

  /** 对齐 getInputStreamPipe(String)：命中返回 pipe，未命中返回 null。 */
  getInputStreamPipe(key: string): InputStreamPipe | null {
    if (this.contain(key)) {
      return new CacheInputStreamPipe(this, SimpleDiskCache.hashKeyForDisk(key));
    }
    return null;
  }

  /** 对齐 getOutputStreamPipe(String)：总是返回 pipe（是否命中不影响）。 */
  getOutputStreamPipe(key: string): OutputStreamPipe {
    return new CacheOutputStreamPipe(this, SimpleDiskCache.hashKeyForDisk(key));
  }

  /** 供 pipe 访问（对应上游内部类的隐式外部实例访问）。 */
  diskCacheOrNull(): DiskLruCache | null {
    return this._diskLruCache;
  }

  obtainLock(key: string): CounterLock {
    let lock: CounterLock | undefined = this._lockMap.get(key);
    if (lock === undefined) {
      if (this._lockPool.length > 0) {
        lock = this._lockPool.pop() as CounterLock;
      } else {
        lock = new CounterLock();
      }
      this._lockMap.set(key, lock);
    }
    lock.obtain();
    return lock;
  }

  releaseLock(key: string, lock: CounterLock): void {
    lock.release();
    if (lock.isFree()) {
      this._lockMap.delete(key);
      if (this._lockPool.length < SimpleDiskCache.LOCK_POOL_MAX_SIZE) {
        this._lockPool.push(lock);
      }
    }
  }
}

/** 对齐 SimpleDiskCache.CounterLock（计数部分；读写锁语义见文件头说明）。 */
export class CounterLock {
  private _count: number = 0;

  isFree(): boolean {
    return this._count === 0;
  }

  release(): void {
    this._count--;
    if (this._count < 0) {
      throw new Error('IllegalStateException: Release time is more than occupy time');
    }
  }

  obtain(): void {
    this._count++;
  }
}

/** 对齐 SimpleDiskCache.CacheInputStreamPipe。 */
export class CacheInputStreamPipe implements InputStreamPipe {
  private readonly _cache: SimpleDiskCache;
  private readonly _key: string;
  private _lock: CounterLock | null = null;
  private _snapshot: DiskLruCacheSnapshot | null = null;
  private _file: fileIo.File | null = null;

  constructor(cache: SimpleDiskCache, key: string) {
    this._cache = cache;
    this._key = key;
  }

  obtain(): void {
    if (this._lock === null) {
      this._lock = this._cache.obtainLock(this._key);
    }
  }

  release(): void {
    if (this._snapshot !== null) {
      throw new Error('IllegalStateException: Please close it first');
    }
    if (this._lock !== null) {
      this._cache.releaseLock(this._key, this._lock as CounterLock);
      this._lock = null;
    }
  }

  open(): fileIo.File {
    if (this._lock === null) {
      throw new Error('IllegalStateException: Please obtain it first');
    }
    if (this._snapshot !== null) {
      throw new Error('IllegalStateException: Please close it before reopen');
    }
    const cache: DiskLruCache | null = this._cache.diskCacheOrNull();
    if (cache === null) {
      throw new Error("IOException: Can't find disk lru cache");
    }
    const snapshot: DiskLruCacheSnapshot | null = (cache as DiskLruCache).get(this._key);
    if (snapshot === null) {
      throw new Error(`IOException: Miss the key ${this._key}`);
    }
    this._snapshot = snapshot;
    const f: fileIo.File = (snapshot as DiskLruCacheSnapshot).getInputStream(0);
    this._file = f;
    return f;
  }

  close(): void {
    if (this._snapshot !== null) {
      (this._snapshot as DiskLruCacheSnapshot).close();
      this._snapshot = null;
    }
    this._file = null;
  }
}

/** 对齐 SimpleDiskCache.CacheOutputStreamPipe：close() 先关闭写端再 commit（上游行为）。 */
export class CacheOutputStreamPipe implements OutputStreamPipe {
  private readonly _cache: SimpleDiskCache;
  private readonly _key: string;
  private _lock: CounterLock | null = null;
  private _editor: DiskLruCacheEditor | null = null;
  private _writer: FaultHidingWriter | null = null;

  constructor(cache: SimpleDiskCache, key: string) {
    this._cache = cache;
    this._key = key;
  }

  obtain(): void {
    if (this._lock === null) {
      this._lock = this._cache.obtainLock(this._key);
    }
  }

  release(): void {
    if (this._editor !== null) {
      throw new Error('IllegalStateException: Please close it first');
    }
    if (this._lock !== null) {
      this._cache.releaseLock(this._key, this._lock as CounterLock);
      this._lock = null;
    }
  }

  open(): ByteSink {
    if (this._lock === null) {
      throw new Error('IllegalStateException: Please obtain it first');
    }
    if (this._editor !== null) {
      throw new Error('IllegalStateException: Please close it before reopen');
    }
    const cache: DiskLruCache | null = this._cache.diskCacheOrNull();
    if (cache === null) {
      throw new Error("IOException: Can't find disk lru cache");
    }
    const editor: DiskLruCacheEditor | null = (cache as DiskLruCache).edit(this._key);
    if (editor === null) {
      throw new Error(`IOException: Miss the key ${this._key}`);
    }
    const out: FaultHidingWriter = (editor as DiskLruCacheEditor).newOutputStream(0);
    this._editor = editor;
    this._writer = out;
    return out;
  }

  private closeWriterQuietly(): void {
    if (this._writer !== null) {
      try {
        this._writer.close();
      } catch (e) {
        // Empty（与上游一致）
      }
      this._writer = null;
    }
  }

  close(): void {
    this.closeWriterQuietly();
    if (this._editor !== null) {
      try {
        (this._editor as DiskLruCacheEditor).commit();
      } catch (e) {
        // Empty（与上游一致）
      }
      this._editor = null;
    }
  }

  /**
   * 写失败或任务取消时中止编辑：先关闭写端再 abort，防止 0 字节或半截文件被 commit 进缓存。
   */
  abort(): void {
    this.closeWriterQuietly();
    if (this._editor !== null) {
      try {
        (this._editor as DiskLruCacheEditor).abort();
      } catch (e) {
        // Empty（与上游一致）
      }
      this._editor = null;
    }
  }
}

/**
 * 纯 TS MD5（RFC 1321）。
 * 为什么要自己写：`@ohos.security.cryptoFramework` 的摘要 API 只有异步版本，
 * 而 hashKeyForDisk 必须同步返回（DiskLruCache 的键）。实现与上游
 * MessageDigest.getInstance("MD5") 逐字节一致 → 旧缓存目录可直接复用。
 */
export function md5Hex(input: ArrayBuffer): string {
  const bytes: Uint8Array = new Uint8Array(input);
  const bitLen: number = bytes.length * 8;

  // padding：0x80 + 若干 0 + 8 字节长度（小端）
  const withPad: number = (((bytes.length + 8) >> 6) + 1) * 64;
  const msg: Uint8Array = new Uint8Array(withPad);
  msg.set(bytes, 0);
  msg[bytes.length] = 0x80;
  const view: DataView = new DataView(msg.buffer);
  view.setUint32(withPad - 8, bitLen >>> 0, true);
  view.setUint32(withPad - 4, Math.floor(bitLen / 0x100000000) >>> 0, true);

  let a0: number = 0x67452301;
  let b0: number = 0xefcdab89;
  let c0: number = 0x98badcfe;
  let d0: number = 0x10325476;

  const S: number[] = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
  ];
  const K: number[] = new Array<number>(64).fill(0);
  for (let i = 0; i < 64; i++) {
    K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000) >>> 0;
  }

  const chunk: Int32Array = new Int32Array(16);
  for (let off = 0; off < withPad; off += 64) {
    for (let i = 0; i < 16; i++) {
      chunk[i] = view.getInt32(off + i * 4, true);
    }
    let A: number = a0;
    let B: number = b0;
    let C: number = c0;
    let D: number = d0;

    for (let i = 0; i < 64; i++) {
      let F: number = 0;
      let g: number = 0;
      if (i < 16) {
        F = (B & C) | ((~B) & D);
        g = i;
      } else if (i < 32) {
        F = (D & B) | ((~D) & C);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        F = B ^ C ^ D;
        g = (3 * i + 5) % 16;
      } else {
        F = C ^ (B | (~D));
        g = (7 * i) % 16;
      }
      const tmp: number = D;
      D = C;
      C = B;
      const x: number = (A + F + K[i] + chunk[g]) | 0;
      B = (B + rotl(x, S[i])) | 0;
      A = tmp;
    }
    a0 = (a0 + A) | 0;
    b0 = (b0 + B) | 0;
    c0 = (c0 + C) | 0;
    d0 = (d0 + D) | 0;
  }

  return hex32(a0) + hex32(b0) + hex32(c0) + hex32(d0);
}

function rotl(x: number, c: number): number {
  return (x << c) | (x >>> (32 - c));
}

function hex32(n: number): string {
  const out: string[] = [];
  for (let i = 0; i < 4; i++) {
    const b: number = (n >>> (i * 8)) & 0xff;
    out.push((b < 16 ? '0' : '') + b.toString(16));
  }
  return out.join('');
}
