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
import { SimpleDiskCache } from './SimpleDiskCache';
import { Util } from './Util';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';
import { OutputStreamPipe, ByteSink } from '../streampipe/OutputStreamPipe';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/beerbelly/BeerBelly.java
 * （inventory S0006，433 行 / 实测 505 行含注释）
 *
 * 两级缓存（内存 LRU + 磁盘 LRU），抽象出 read/write 由子类决定序列化方式。
 * 上游使用点：EhApplication.getSpiderInfoCache 的基类、图库详情缓存等。
 *
 * ArkTS 映射：
 *   android.util.LruCache<K,V>            → 本文件的 LruCache<V>（Map 实现 + accessOrder）
 *   android.util.Log                       → 无日志依赖（异常路径只吞掉，与上游一致）
 *   java.io.InputStream / OutputStream     → fileIo.File / ByteSink（streampipe 层）
 *   BeerBelly.BeerBellyParams（静态嵌套类）→ 文件级 BeerBellyParams
 *   BeerBelly.DiskCache<E>（私有嵌套类）   → 文件级 BeerBellyDiskCache<V>
 *   BeerBelly.MemoryCache<E>               → LruCache<V> 直接持有 parent 回调
 *   abstract V read(InputStreamPipe, boolean hardware)
 *   abstract boolean write(OutputStream os, V value) → write(os: ByteSink, value: V)
 *
 * 泛型：ArkTS 支持类级泛型；抽象方法由子类实现（如 spiderInfo 的 JSON 编解码）。
 */
export abstract class BeerBelly<V> {
  private readonly _hasMemoryCache: boolean;
  private readonly _hasDiskCache: boolean;
  private readonly _memoryCache: LruCache<V> | null;
  private readonly _diskCache: BeerBellyDiskCache<V> | null;

  constructor(params: BeerBellyParams) {
    params.validate();
    this._hasMemoryCache = params.hasMemoryCache;
    this._hasDiskCache = params.hasDiskCache;
    if (params.hasMemoryCache) {
      this._memoryCache = new LruCache<V>(params.memoryCacheMaxSize, this);
    } else {
      this._memoryCache = null;
    }
    if (params.hasDiskCache) {
      const dir: string = params.diskCacheDir === null ? '' : (params.diskCacheDir as string);
      this._diskCache = new BeerBellyDiskCache<V>(dir, params.diskCacheMaxSize, this);
    } else {
      this._diskCache = null;
    }
  }

  // ---- 子类实现的抽象点（与上游逐一对应） ----

  /** 对齐 sizeOf(String, V)。 */
  abstract sizeOf(key: string, value: V): number;

  /** 对齐 memoryEntryAdded(V)。 */
  abstract memoryEntryAdded(value: V): void;

  /** 对齐 memoryEntryRemoved(boolean evicted, String key, V oldValue, V newValue)。 */
  abstract memoryEntryRemoved(evicted: boolean, key: string, oldValue: V | null, newValue: V | null): void;

  /** 对齐 read(InputStreamPipe, boolean hardware)。 */
  abstract read(isPipe: InputStreamPipe, hardware: boolean): V | null;

  /** 对齐 write(OutputStream, V)。 */
  abstract write(os: ByteSink, value: V): boolean;

  // ---- 查询 ----

  getMemoryCache(): LruCache<V> | null {
    return this._memoryCache;
  }

  getDiskCache(): SimpleDiskCache | null {
    return this._diskCache === null ? null : (this._diskCache as BeerBellyDiskCache<V>).diskCache();
  }

  hasMemoryCache(): boolean {
    return this._hasMemoryCache;
  }

  hasDiskCache(): boolean {
    return this._hasDiskCache;
  }

  memorySize(): number {
    const c: LruCache<V> | null = this._memoryCache;
    return c === null ? -1 : (c as LruCache<V>).size();
  }

  memoryMaxSize(): number {
    const c: LruCache<V> | null = this._memoryCache;
    return c === null ? -1 : (c as LruCache<V>).maxSize();
  }

  diskSize(): number {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    return c === null ? -1 : (c as BeerBellyDiskCache<V>).size();
  }

  diskMaxSize(): number {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    return c === null ? -1 : (c as BeerBellyDiskCache<V>).getMaxSize();
  }

  // ---- 读取 ----

  getFromMemory(key: string): V | null {
    const c: LruCache<V> | null = this._memoryCache;
    if (this._hasMemoryCache && c !== null) {
      return (c as LruCache<V>).get(key);
    }
    return null;
  }

  /** 对齐 getFromDisk(String)。 */
  getFromDisk(key: string): V | null {
    return this.getFromDiskWithFlag(key, true);
  }

  /** 对齐 getFromDisk(String, boolean hardware)。 */
  getFromDiskWithFlag(key: string, hardware: boolean): V | null {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    if (this._hasDiskCache && c !== null) {
      return (c as BeerBellyDiskCache<V>).getWithFlag(key, hardware);
    }
    return null;
  }

  /** 对齐 get(String, boolean hardware)：内存命中直接返回；磁盘命中回填内存。 */
  get(key: string, hardware: boolean): V | null {
    const fromMemory: V | null = this.getFromMemory(key);
    if (fromMemory !== null) {
      return fromMemory;
    }
    const fromDisk: V | null = this.getFromDiskWithFlag(key, hardware);
    if (fromDisk !== null) {
      this.putToMemory(key, fromDisk as V);
      return fromDisk;
    }
    return null;
  }

  // ---- 写入 ----

  putToMemory(key: string, value: V): boolean {
    const c: LruCache<V> | null = this._memoryCache;
    if (this._hasMemoryCache && c !== null) {
      this.memoryEntryAdded(value);
      (c as LruCache<V>).put(key, value);
      return true;
    }
    return false;
  }

  putToDisk(key: string, value: V): boolean {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    if (this._hasDiskCache && c !== null) {
      return (c as BeerBellyDiskCache<V>).put(key, value);
    }
    return false;
  }

  put(key: string, value: V): void {
    this.putToMemory(key, value);
    this.putToDisk(key, value);
  }

  // ---- 删除 ----

  removeFromMemory(key: string): void {
    const c: LruCache<V> | null = this._memoryCache;
    if (this._hasMemoryCache && c !== null) {
      (c as LruCache<V>).remove(key);
    }
  }

  removeFromDisk(key: string): void {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    if (this._hasDiskCache && c !== null) {
      (c as BeerBellyDiskCache<V>).remove(key);
    }
  }

  remove(key: string): void {
    this.removeFromMemory(key);
    this.removeFromDisk(key);
  }

  /** 对齐 pullFromDiskCache(String, OutputStream)。 */
  pullFromDiskCache(key: string, os: ByteSink): boolean {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    if (this._hasDiskCache && c !== null) {
      return (c as BeerBellyDiskCache<V>).pull(key, os);
    }
    return false;
  }

  /** 对齐 putRawToDisk(String, InputStream)。 */
  putRawToDisk(key: string, source: fileIo.File): boolean {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    if (this._hasDiskCache && c !== null) {
      return (c as BeerBellyDiskCache<V>).putRaw(key, source);
    }
    return false;
  }

  // ---- 清理 ----

  clearMemory(): void {
    const c: LruCache<V> | null = this._memoryCache;
    if (this._hasMemoryCache && c !== null) {
      (c as LruCache<V>).evictAll();
    }
  }

  clearDisk(): void {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    if (this._hasDiskCache && c !== null) {
      (c as BeerBellyDiskCache<V>).clear();
    }
  }

  flush(): void {
    const c: BeerBellyDiskCache<V> | null = this._diskCache;
    if (this._hasDiskCache && c !== null) {
      (c as BeerBellyDiskCache<V>).flush();
    }
  }

  clear(): void {
    this.clearMemory();
    this.clearDisk();
  }
}

/**
 * 对齐 BeerBelly.BeerBellyParams（静态嵌套类 → 文件级）。
 * ArkTS 无重载/无默认参数歧义，字段默认值与上游一致。
 */
export class BeerBellyParams {
  hasMemoryCache: boolean = false;
  memoryCacheMaxSize: number = 0;
  hasDiskCache: boolean = false;
  diskCacheDir: string | null = null;
  diskCacheMaxSize: number = 0;

  /** 对齐 isValid()：非法组合抛 IllegalStateException（这里抛 Error，文案保持）。 */
  validate(): void {
    if (!this.hasMemoryCache && !this.hasDiskCache) {
      throw new Error('IllegalStateException: No memory cache and no disk cache. What can I do for you?');
    }
    if (this.hasMemoryCache && this.memoryCacheMaxSize <= 0) {
      throw new Error('IllegalStateException: Memory cache max size must be bigger than 0.');
    }
    if (this.hasDiskCache) {
      if (this.diskCacheDir === null) {
        throw new Error('IllegalStateException: Disk cache dir can\'t be null.');
      }
      if (this.diskCacheMaxSize <= 0) {
        throw new Error('IllegalStateException: Disk cache max size must be bigger than 0.');
      }
    }
  }
}

/**
 * 对齐 BeerBelly.DiskCache<E>（私有嵌套类 → 文件级）。
 * 8KB 缓冲写：上游用 BufferedOutputStream(8192)，这里直接用 ByteSink（写入即落盘），
 * 差异仅影响 syscall 次数，不影响字节内容。
 */
export class BeerBellyDiskCache<V> {
  private static readonly IO_BUFFER_SIZE: number = 8 * 1024;

  private readonly _diskCache: SimpleDiskCache;
  private readonly _parent: BeerBelly<V>;
  private readonly _cacheDir: string;
  private readonly _maxSize: number;

  constructor(cacheDir: string, size: number, parent: BeerBelly<V>) {
    this._diskCache = new SimpleDiskCache(cacheDir, size);
    this._parent = parent;
    this._cacheDir = cacheDir;
    this._maxSize = size;
  }

  diskCache(): SimpleDiskCache {
    return this._diskCache;
  }

  getCacheDir(): string {
    return this._cacheDir;
  }

  getMaxSize(): number {
    return this._maxSize;
  }

  size(): number {
    return this._diskCache.size();
  }

  flush(): void {
    this._diskCache.flush();
  }

  clear(): void {
    this._diskCache.clear();
  }

  /** 对齐 get(String) / get(String, boolean hardware)（ArkTS 无重载，统一为 getWithFlag）。 */
  getWithFlag(key: string, hardware: boolean): V | null {
    const isPipe: InputStreamPipe | null = this._diskCache.getInputStreamPipe(key);
    if (isPipe === null) {
      return null;
    }
    return this._parent.read(isPipe as InputStreamPipe, hardware);
  }


  put(key: string, value: V): boolean {
    const osPipe: OutputStreamPipe = this._diskCache.getOutputStreamPipe(key);
    try {
      osPipe.obtain();
      const os: ByteSink = osPipe.open();
      const ok: boolean = this._parent.write(os, value);
      os.close();
      return ok;
    } catch (e) {
      return false;
    } finally {
      osPipe.close();
      osPipe.release();
    }
  }

  putRaw(key: string, source: fileIo.File): boolean {
    return this._diskCache.put(key, source as fileIo.File);
  }

  remove(key: string): void {
    this._diskCache.remove(key);
  }

  pull(key: string, os: ByteSink): boolean {
    const isPipe: InputStreamPipe | null = this._diskCache.getInputStreamPipe(key);
    if (isPipe === null) {
      return false;
    }
    const pipe: InputStreamPipe = isPipe as InputStreamPipe;
    try {
      pipe.obtain();
      const input: fileIo.File = pipe.open();
      const buffer: ArrayBuffer = new ArrayBuffer(BeerBellyDiskCache.IO_BUFFER_SIZE);
      while (true) {
        const n: number = fileIo.readSync(input.fd, buffer);
        if (n <= 0) {
          break;
        }
        os.write(n === buffer.byteLength ? buffer : buffer.slice(0, n));
      }
      return true;
    } catch (e) {
      return false;
    } finally {
      pipe.close();
      pipe.release();
    }
  }
}

/**
 * android.util.LruCache<String, E> 的最小等价实现。
 * 语义：accessOrder 淘汰（get 也刷新顺序）、sizeOf 计权、entryRemoved 回调。
 * 说明：core-runtime 模块的 `hippo/util/LruCache` 尚未落地，本类先内联；
 * 待其落地后替换为 `import { LruCache } from '../util/LruCache'`，接口保持兼容。
 */
export class LruCache<V> {
  private readonly _maxSize: number;
  private readonly _parent: BeerBelly<V> | null;
  private readonly _map: Map<string, V> = new Map<string, V>();
  private _size: number = 0;

  constructor(maxSize: number, parent: BeerBelly<V> | null = null) {
    if (maxSize <= 0) {
      throw new Error('IllegalArgumentException: maxSize <= 0');
    }
    this._maxSize = maxSize;
    this._parent = parent;
  }

  maxSize(): number {
    return this._maxSize;
  }

  size(): number {
    return this._size;
  }

  get(key: string): V | null {
    const v: V | undefined = this._map.get(key);
    if (v === undefined) {
      return null;
    }
    // accessOrder：重新插入以刷新顺序
    this._map.delete(key);
    this._map.set(key, v);
    return v;
  }

  put(key: string, value: V): V | null {
    const old: V | undefined = this._map.get(key);
    if (old !== undefined) {
      this._size -= this.sizeOfValue(key, old);
      this._map.delete(key);
    }
    this._map.set(key, value);
    this._size += this.sizeOfValue(key, value);
    if (old !== undefined && this._parent !== null) {
      this._parent.memoryEntryRemoved(false, key, old, value);
    }
    this.trimToSize();
    return old === undefined ? null : old;
  }

  remove(key: string): V | null {
    const old: V | undefined = this._map.get(key);
    if (old === undefined) {
      return null;
    }
    this._size -= this.sizeOfValue(key, old);
    this._map.delete(key);
    if (this._parent !== null) {
      this._parent.memoryEntryRemoved(false, key, old, null);
    }
    return old;
  }

  evictAll(): void {
    const keys: string[] = [];
    this._map.forEach((v: V, k: string) => {
      keys.push(k);
    });
    for (let i = 0; i < keys.length; i++) {
      const old: V | undefined = this._map.get(keys[i]);
      this._map.delete(keys[i]);
      if (old !== undefined && this._parent !== null) {
        this._parent.memoryEntryRemoved(true, keys[i], old, null);
      }
    }
    this._size = 0;
  }

  private sizeOfValue(key: string, value: V): number {
    if (this._parent === null) {
      return 1;
    }
    const s: number = this._parent.sizeOf(key, value);
    return s < 0 ? 0 : s;
  }

  private trimToSize(): void {
    while (this._size > this._maxSize) {
      let eldestKey: string | null = null;
      this._map.forEach((v: V, k: string) => {
        if (eldestKey === null) {
          eldestKey = k;
        }
      });
      if (eldestKey === null) {
        break;
      }
      const key: string = eldestKey as string;
      const old: V | undefined = this._map.get(key);
      this._map.delete(key);
      if (old !== undefined) {
        this._size -= this.sizeOfValue(key, old);
        if (this._parent !== null) {
          this._parent.memoryEntryRemoved(true, key, old, null);
        }
      }
    }
  }
}
