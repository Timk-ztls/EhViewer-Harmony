/*
 * Copyright 2016 Hippo Seven
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
import { Util } from '../beerbelly/Util';
import { Chain, Interceptor } from './Interceptor';
import { MediaType } from './MediaType';
import { Protocol, Response } from './Response';
import { ResponseBody } from './ResponseBody';
import { Request } from './Request';
import { Headers } from './Headers';
import { HttpUrl } from './HttpUrl';
import { decodeBytes, utf8Encode } from './RequestBody';

/**
 * okhttp3.Cache 等价层（磁盘 HTTP 缓存）+ CacheInterceptor。
 *
 * 上游配置（EhApplication.getOkHttpCache）：
 *   new Cache(new File(getCacheDir(), "http_cache"), 50L * 1024L * 1024L)
 * 两个 client（普通 / 图片）共用同一个 Cache 实例。
 *
 * OkHttp 的 Cache 用 DiskLruCache + journal；本层用「一 URL 一 header 文件 + 一 body 文件」，
 * 存储格式不同，但对外契约保持：
 *   - 可缓存性判定（method / 状态码 / Cache-Control / Pragma / Expires）
 *   - 新鲜度判定（max-age / Expires / Age 修正）
 *   - 条件请求（If-None-Match / If-Modified-Since）与 304 合并
 *   - 命中时给 Response 标记 cacheResponse
 * 与 OkHttp 的差异（已登记 MR）：
 *   1) 不支持 Vary（EhViewer 的 e-hentai 响应无 Vary 变化维度实用价值）
 *   2) 不做 journal 崩溃恢复，孤儿文件在 evictAll / 容量淘汰时清理
 *   3) 容量统计按文件字节数增量维护，启动时扫描一次
 */

const HEADER_SUFFIX: string = '.hdr.json';
const BODY_SUFFIX: string = '.body';
const VERSION: number = 1;

/** 缓存条目的头信息（序列化为 JSON）。 */
export interface CacheEntryMeta {
  url: string;
  method: string;
  code: number;
  message: string;
  protocol: string;
  headers: string[][]; // [[name, value], ...] 保序
  requestTime: number;
  responseTime: number;
  bodyLength: number;
  version: number;
}

export class Cache {
  private readonly _directory: string;
  private readonly _maxSize: number;
  private _size: number = 0;
  private _hitCount: number = 0;
  private _requestCount: number = 0;
  private _initialized: boolean = false;
  private _initPromise: Promise<void> | null = null;
  private readonly _knownKeys: Set<string> = new Set<string>();

  /** 对齐 new Cache(File directory, long maxSize)。 */
  constructor(directory: string, maxSize: number) {
    this._directory = directory;
    this._maxSize = maxSize;
  }

  directory(): string {
    return this._directory;
  }

  maxSize(): number {
    return this._maxSize;
  }

  size(): number {
    this.ensureInit();
    return this._size;
  }

  hitCount(): number {
    return this._hitCount;
  }

  requestCount(): number {
    return this._requestCount;
  }

  /** 对齐 Cache.delete()：清空缓存目录。 */
  evictAll(): void {
    this.ensureInit();
    const names: string[] = fileIo.listFileSync(this._directory);
    for (let i = 0; i < names.length; i++) {
      try {
        fileIo.unlinkSync(`${this._directory}/${names[i]}`);
      } catch (e) {
        // 单文件删除失败不影响整体清理
      }
    }
    this._size = 0;
    this._hitCount = 0;
    this._requestCount = 0;
    this._knownKeys.clear();
  }

  /** 对齐 Cache.close()：本层无 journal，清空内存计数即可。 */
  close(): void {
    this._size = 0;
    this._knownKeys.clear();
  }

  private ensureInit(): void {
    if (this._initialized) {
      return;
    }
    try {
      if (!fileIo.accessSync(this._directory)) {
        fileIo.mkdirSync(this._directory, true);
      }
      const names: string[] = fileIo.listFileSync(this._directory);
      let total: number = 0;
      for (let i = 0; i < names.length; i++) {
        const name: string = names[i];
        if (name.endsWith(HEADER_SUFFIX)) {
          this._knownKeys.add(name.substring(0, name.length - HEADER_SUFFIX.length));
        }
        try {
          total += fileIo.statSync(`${this._directory}/${name}`).size;
        } catch (e) {
          // 忽略统计失败的文件
        }
      }
      this._size = total;
    } catch (e) {
      this._size = 0;
    }
    this._initialized = true;
  }

  private async ensureInitAsync(): Promise<void> {
    if (this._initialized) {
      return;
    }
    if (this._initPromise !== null) {
      await this._initPromise;
      return;
    }
    const job: Promise<void> = this.runInitAsync().finally((): void => {
      this._initPromise = null;
    });
    this._initPromise = job;
    await job;
  }

  private async runInitAsync(): Promise<void> {
    try {
      const exists: boolean = await fileIo.access(this._directory);
      if (!exists) {
        await fileIo.mkdir(this._directory, true);
      }
      const names: string[] = await fileIo.listFile(this._directory);
      let total: number = 0;
      for (let i = 0; i < names.length; i++) {
        const name: string = names[i];
        if (name.endsWith(HEADER_SUFFIX)) {
          this._knownKeys.add(name.substring(0, name.length - HEADER_SUFFIX.length));
        }
        try {
          const st: fileIo.Stat = await fileIo.stat(`${this._directory}/${name}`);
          total += st.size;
        } catch (e) {
          // 忽略统计失败的文件
        }
      }
      this._size = total;
    } catch (e) {
      this._size = 0;
    }
    this._initialized = true;
  }

  /** URL → 文件名。用两段 32 位 FNV-1a 拼成 16 位十六进制，避免超长文件名。 */
  static keyOf(url: string): string {
    let h1: number = 0x811c9dc5;
    let h2: number = 0x01000193;
    for (let i = 0; i < url.length; i++) {
      const c: number = url.charCodeAt(i);
      h1 = (h1 ^ c) >>> 0;
      h1 = Math.imul(h1, 0x01000193) >>> 0;
      h2 = (h2 + c * (i + 1)) >>> 0;
      h2 = Math.imul(h2, 0x85ebca6b) >>> 0;
    }
    return Cache.hex8(h1) + Cache.hex8(h2);
  }

  private static hex8(n: number): string {
    const s: string = (n >>> 0).toString(16);
    return '00000000'.substring(0, 8 - s.length) + s;
  }

  private headerPath(key: string): string {
    return `${this._directory}/${key}${HEADER_SUFFIX}`;
  }

  private bodyPath(key: string): string {
    return `${this._directory}/${key}${BODY_SUFFIX}`;
  }

  /** 读条目；不存在返回 null。 */
  readEntry(request: Request): CacheRecord | null {
    this.ensureInit();
    const key: string = Cache.keyOf(request.url().toString());
    const hp: string = this.headerPath(key);
    if (!fileIo.accessSync(hp)) {
      return null;
    }
    try {
      const metaText: string = fileIo.readTextSync(hp);
      const meta: CacheEntryMeta = JSON.parse(metaText) as CacheEntryMeta;
      if (meta.version !== VERSION || meta.url !== request.url().toString()) {
        return null;
      }
      const bp: string = this.bodyPath(key);
      let body: ArrayBuffer = new ArrayBuffer(0);
      if (fileIo.accessSync(bp)) {
        const size: number = fileIo.statSync(bp).size;
        const file: fileIo.File = fileIo.openSync(bp, fileIo.OpenMode.READ_ONLY);
        try {
          // F-3：ReadOptions.offset 是**文件内**起点，不是缓冲区下标；
          // 用 filePointer 顺序读满（否则 off>0 时读到文件中间且变短）
          body = Util.readFullyTo(file.fd, size);
        } finally {
          fileIo.closeSync(file);
        }
      }
      return new CacheRecord(meta, body);
    } catch (e) {
      return null;
    }
  }

  /** 写条目（先 body 后 header，避免读到半截条目；超过 maxSize 跳过；不匹配的旧条目删除）。 */
  writeEntry(request: Request, response: Response, responseTime: number, requestTime: number): void {
    this.ensureInit();
    const rb: ResponseBody | null = response.body();
    const body: ArrayBuffer = rb === null ? new ArrayBuffer(0) : rb.bytes();
    if (this._maxSize <= 0 || body.byteLength > this._maxSize) {
      return;
    }
    const key: string = Cache.keyOf(request.url().toString());
    const names: string[] = [];
    const values: string[] = [];
    const h: Headers = response.headers();
    for (let i = 0; i < h.size(); i++) {
      names.push(h.name(i));
      values.push(h.value(i));
    }
    const pairs: string[][] = [];
    for (let i = 0; i < names.length; i++) {
      pairs.push([names[i], values[i]]);
    }
    const meta: CacheEntryMeta = {
      url: request.url().toString(),
      method: request.method(),
      code: response.code(),
      message: response.message(),
      protocol: response.protocol() as string,
      headers: pairs,
      requestTime: requestTime,
      responseTime: responseTime,
      bodyLength: body.byteLength,
      version: VERSION
    };
    const bp: string = this.bodyPath(key);
    const hp: string = this.headerPath(key);
    let oldBodySize: number = 0;
    let oldHeaderSize: number = 0;
    try {
      if (fileIo.accessSync(bp)) {
        oldBodySize = fileIo.statSync(bp).size;
      }
      if (fileIo.accessSync(hp)) {
        oldHeaderSize = fileIo.statSync(hp).size;
      }
    } catch (e) {
      // 忽略旧文件统计失败
    }
    const bodyFile: fileIo.File = fileIo.openSync(bp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC);
    try {
      if (body.byteLength > 0) {
        fileIo.writeSync(bodyFile.fd, body);
      }
    } finally {
      fileIo.closeSync(bodyFile);
    }
    const headerText: string = JSON.stringify(meta);
    const headerBytes: ArrayBuffer = utf8Encode(headerText);
    const headerFile: fileIo.File = fileIo.openSync(hp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(headerFile.fd, headerBytes);
    } finally {
      fileIo.closeSync(headerFile);
    }
    this._size = Math.max(0, this._size - oldBodySize - oldHeaderSize) +
      body.byteLength + headerBytes.byteLength;
    this._knownKeys.add(key);
    this._requestCount++;
    this.trimToSize();
  }

  removeEntry(url: string): void {
    this.ensureInit();
    const key: string = Cache.keyOf(url);
    this._knownKeys.delete(key);
    const bp: string = this.bodyPath(key);
    const hp: string = this.headerPath(key);
    this.unlinkAndSubtract(bp);
    this.unlinkAndSubtract(hp);
  }

  private unlinkAndSubtract(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        const sz: number = fileIo.statSync(path).size;
        fileIo.unlinkSync(path);
        this._size = Math.max(0, this._size - sz);
      }
    } catch (e) {
      // 单文件清理失败不中断
    }
  }

  /** 异步读条目；未命中索引直接 O(1) 返回 null，避免主线程同步文件 I/O。 */
  async readEntryAsync(request: Request): Promise<CacheRecord | null> {
    await this.ensureInitAsync();
    const key: string = Cache.keyOf(request.url().toString());
    if (!this._knownKeys.has(key)) {
      return null;
    }
    const hp: string = this.headerPath(key);
    try {
      if (!(await fileIo.access(hp))) {
        this._knownKeys.delete(key);
        return null;
      }
      const headerSize: number = (await fileIo.stat(hp)).size;
      const headerBytes: ArrayBuffer = await Cache.readFileBytesAsync(hp, headerSize);
      const metaText: string = decodeBytes(headerBytes, 'utf-8');
      const meta: CacheEntryMeta = JSON.parse(metaText) as CacheEntryMeta;
      if (meta.version !== VERSION || meta.url !== request.url().toString()) {
        return null;
      }
      const bp: string = this.bodyPath(key);
      let body: ArrayBuffer = new ArrayBuffer(0);
      if (await fileIo.access(bp)) {
        const bodySize: number = (await fileIo.stat(bp)).size;
        body = await Cache.readFileBytesAsync(bp, bodySize);
      }
      return new CacheRecord(meta, body);
    } catch (e) {
      return null;
    }
  }

  /** 异步写条目（先 body 后 header，避免阻塞 UI 主线程）。 */
  async writeEntryAsync(request: Request, response: Response, responseTime: number, requestTime: number): Promise<void> {
    await this.ensureInitAsync();
    const rb: ResponseBody | null = response.body();
    const body: ArrayBuffer = rb === null ? new ArrayBuffer(0) : rb.bytes();
    if (this._maxSize <= 0 || body.byteLength > this._maxSize) {
      return;
    }
    const key: string = Cache.keyOf(request.url().toString());
    const h: Headers = response.headers();
    const pairs: string[][] = [];
    for (let i = 0; i < h.size(); i++) {
      pairs.push([h.name(i), h.value(i)]);
    }
    const meta: CacheEntryMeta = {
      url: request.url().toString(),
      method: request.method(),
      code: response.code(),
      message: response.message(),
      protocol: response.protocol() as string,
      headers: pairs,
      requestTime: requestTime,
      responseTime: responseTime,
      bodyLength: body.byteLength,
      version: VERSION
    };
    const bp: string = this.bodyPath(key);
    const hp: string = this.headerPath(key);
    let oldBodySize: number = 0;
    let oldHeaderSize: number = 0;
    try {
      if (await fileIo.access(bp)) {
        oldBodySize = (await fileIo.stat(bp)).size;
      }
      if (await fileIo.access(hp)) {
        oldHeaderSize = (await fileIo.stat(hp)).size;
      }
    } catch (e) {
      // 忽略旧文件统计失败
    }
    const mode: number = fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC;
    const bodyFile: fileIo.File = await fileIo.open(bp, mode);
    try {
      if (body.byteLength > 0) {
        await fileIo.write(bodyFile.fd, body);
      }
    } finally {
      await fileIo.close(bodyFile);
    }
    const headerBytes: ArrayBuffer = utf8Encode(JSON.stringify(meta));
    const headerFile: fileIo.File = await fileIo.open(hp, mode);
    try {
      await fileIo.write(headerFile.fd, headerBytes);
    } finally {
      await fileIo.close(headerFile);
    }
    this._size = Math.max(0, this._size - oldBodySize - oldHeaderSize) +
      body.byteLength + headerBytes.byteLength;
    this._knownKeys.add(key);
    this._requestCount++;
    await this.trimToSizeAsync();
  }

  async removeEntryAsync(url: string): Promise<void> {
    await this.ensureInitAsync();
    const key: string = Cache.keyOf(url);
    if (!this._knownKeys.has(key)) {
      return;
    }
    this._knownKeys.delete(key);
    await this.unlinkAndSubtractAsync(this.bodyPath(key));
    await this.unlinkAndSubtractAsync(this.headerPath(key));
  }

  private async unlinkAndSubtractAsync(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        const sz: number = (await fileIo.stat(path)).size;
        await fileIo.unlink(path);
        this._size = Math.max(0, this._size - sz);
      }
    } catch (e) {
      // 单文件清理失败不中断
    }
  }

  private async trimToSizeAsync(): Promise<void> {
    if (this._size <= this._maxSize) {
      return;
    }
    let files: string[];
    try {
      files = await fileIo.listFile(this._directory);
    } catch (e) {
      return;
    }
    const hdrs: string[] = files.filter((n: string) => n.endsWith(HEADER_SUFFIX));
    const stats: FileStat[] = [];
    for (let i = 0; i < hdrs.length; i++) {
      const p: string = `${this._directory}/${hdrs[i]}`;
      try {
        const st: fileIo.Stat = await fileIo.stat(p);
        stats.push(new FileStat(p, st.mtime * 1000));
      } catch (e) {
        // 忽略
      }
    }
    stats.sort((a: FileStat, b: FileStat) => a.mtime - b.mtime);
    for (let i = 0; i < stats.length && this._size > this._maxSize; i++) {
      const key: string = stats[i].path.substring(this._directory.length + 1,
        stats[i].path.length - HEADER_SUFFIX.length);
      this._knownKeys.delete(key);
      await this.unlinkAndSubtractAsync(this.bodyPath(key));
      await this.unlinkAndSubtractAsync(stats[i].path);
    }
  }

  private static async readFileBytesAsync(path: string, size: number): Promise<ArrayBuffer> {
    if (size <= 0) {
      return new ArrayBuffer(0);
    }
    const file: fileIo.File = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const out: Uint8Array = new Uint8Array(size);
      let totalRead: number = 0;
      while (totalRead < size) {
        const remaining: number = size - totalRead;
        const chunk: ArrayBuffer = new ArrayBuffer(remaining);
        const n: number = await fileIo.read(file.fd, chunk, { length: remaining });
        if (n <= 0) {
          break;
        }
        if (totalRead === 0 && n === size) {
          return chunk;
        }
        out.set(new Uint8Array(chunk, 0, n), totalRead);
        totalRead += n;
      }
      if (totalRead === size) {
        return out.buffer;
      }
      return out.slice(0, totalRead).buffer;
    } finally {
      await fileIo.close(file);
    }
  }

  /** 容量淘汰：按 mtime 最旧优先（近似 OkHttp 的 LRU）。 */
  private trimToSize(): void {
    if (this._size <= this._maxSize) {
      return;
    }
    let files: string[];
    try {
      files = fileIo.listFileSync(this._directory);
    } catch (e) {
      return;
    }
    const hdrs: string[] = files.filter((n: string) => n.endsWith(HEADER_SUFFIX));
    const stats: FileStat[] = [];
    for (let i = 0; i < hdrs.length; i++) {
      const p: string = `${this._directory}/${hdrs[i]}`;
      try {
        stats.push(new FileStat(p, fileIo.statSync(p).mtime * 1000));
      } catch (e) {
        // 忽略
      }
    }
    stats.sort((a: FileStat, b: FileStat) => a.mtime - b.mtime);
    for (let i = 0; i < stats.length && this._size > this._maxSize; i++) {
      const key: string = stats[i].path.substring(this._directory.length + 1,
        stats[i].path.length - HEADER_SUFFIX.length);
      this.unlinkAndSubtract(this.bodyPath(key));
      this.unlinkAndSubtract(stats[i].path);
    }
  }

  /** 命中计数（CacheInterceptor 调用）。 */
  countHit(): void {
    this._hitCount++;
  }
}

class FileStat {
  readonly path: string;
  readonly mtime: number;

  constructor(path: string, mtime: number) {
    this.path = path;
    this.mtime = mtime;
  }
}

/** 一条缓存记录。 */
export class CacheRecord {
  readonly meta: CacheEntryMeta;
  readonly body: ArrayBuffer;

  constructor(meta: CacheEntryMeta, body: ArrayBuffer) {
    this.meta = meta;
    this.body = body;
  }

  headers(): Headers {
    const names: string[] = [];
    const values: string[] = [];
    for (let i = 0; i < this.meta.headers.length; i++) {
      names.push(this.meta.headers[i][0]);
      values.push(this.meta.headers[i][1]);
    }
    return new Headers(names, values);
  }

  /** 还原成 Response。 */
  toResponse(request: Request): Response {
    const h: Headers = this.headers();
    const ctValue: string | null = h.get('Content-Type');
    const ct: MediaType | null = ctValue === null ? null : MediaType.parse(ctValue);
    const body: ResponseBody = new ResponseBody(ct, this.body);
    let protocol: Protocol = Protocol.HTTP_1_1;
    if (this.meta.protocol === 'h2') {
      protocol = Protocol.HTTP_2;
    } else if (this.meta.protocol === 'http/1.0') {
      protocol = Protocol.HTTP_1_0;
    }
    return new Response(request, protocol, this.meta.code, this.meta.message, h, body);
  }
}

/**
 * HTTP 缓存拦截器（对应 OkHttp 的 CacheInterceptor + CacheStrategy）。
 *
 * 位置：应用拦截器之后、网络拦截器之前（与 OkHttp 一致）。
 * 决策：
 *   1) 请求方法非 GET → 直通网络
 *   2) 无缓存 → 直通网络，可缓存则落盘
 *   3) 有缓存且新鲜（max-age 未过 / Expires 未过）→ 直接返回缓存，不联网
 *   4) 有缓存但不新鲜，且有 ETag/Last-Modified → 加条件头联网；304 → 合并头返回缓存体
 *   5) 其余 → 直通网络并（若可缓存）落盘
 */
export class CacheInterceptor implements Interceptor {
  private readonly _cache: Cache;

  constructor(cache: Cache) {
    this._cache = cache;
  }

  async intercept(chain: Chain): Promise<Response> {
    const request: Request = chain.request();
    const requestTime: number = Date.now();
    const method: string = request.method();

    if (CacheInterceptor.invalidatesCache(method)) {
      await this._cache.removeEntryAsync(request.url().toString());
      return chain.proceed(request);
    }
    if (method !== 'GET') {
      return chain.proceed(request);
    }

    const reqCc: Map<string, string | null> = CacheInterceptor.parseDirectives(
      request.headers().values('Cache-Control'));
    const cacheOnly: boolean = reqCc.has('only-if-cached');
    const reqNoCache: boolean = reqCc.has('no-cache');
    const reqNoStore: boolean = reqCc.has('no-store');
    const reqMaxAge: number = CacheInterceptor.directiveIntFromMap(reqCc, 'max-age');
    const reqMinFresh: number = CacheInterceptor.directiveIntFromMap(reqCc, 'min-fresh');
    const record: CacheRecord | null = reqNoStore ? null : await this._cache.readEntryAsync(request);

    if (record !== null) {
      let freshness: number = CacheInterceptor.freshnessLifetimeMs(record);
      if (reqMaxAge >= 0) {
        freshness = Math.min(freshness, reqMaxAge * 1000);
      }
      const minFreshMs: number = reqMinFresh > 0 ? reqMinFresh * 1000 : 0;
      const age: number = CacheInterceptor.computeAgeMs(record, requestTime);
      if (!reqNoCache && age + minFreshMs < freshness) {
        this._cache.countHit();
        const cached: Response = record.toResponse(request);
        return cached.newBuilder().cacheResponse(cached).build();
      }
      // 需要再验证
      const validator: Request | null = CacheInterceptor.conditionalize(request, record);
      if (validator !== null && !cacheOnly) {
        const network: Response = await chain.proceed(validator);
        if (network.code() === 304) {
          this._cache.countHit();
          const cached: Response = record.toResponse(request);
          const merged: Response = CacheInterceptor.combine(network, record, request);
          network.close();
          if (!reqNoStore) {
            await this._cache.writeEntryAsync(request, merged, Date.now(), requestTime);
          }
          return merged.newBuilder().cacheResponse(cached).build();
        }
        if (!reqNoStore && CacheInterceptor.isCacheable(network)) {
          await this._cache.writeEntryAsync(request, network, Date.now(), requestTime);
        }
        return network;
      }
      if (cacheOnly) {
        this._cache.countHit();
        const cached: Response = record.toResponse(request);
        return cached.newBuilder().cacheResponse(cached).build();
      }
    } else if (cacheOnly) {
      return new Response(request, Protocol.HTTP_1_1, 504, 'Unsatisfiable Request (only-if-cached)',
        CacheInterceptor.emptyHeaders(), ResponseBody.empty());
    }

    const response: Response = await chain.proceed(request);
    if (!reqNoStore && CacheInterceptor.isCacheable(response)) {
      await this._cache.writeEntryAsync(request, response, Date.now(), requestTime);
    }
    return response;
  }

  private static invalidatesCache(method: string): boolean {
    return method === 'POST' || method === 'PATCH' || method === 'PUT' ||
      method === 'DELETE' || method === 'MOVE';
  }

  private static emptyHeaders(): Headers {
    return new Headers([], []);
  }

  /** RFC 7234 §4.2.3：考虑 Age 头与 Date/responseTime 偏差后的当前缓存年龄（毫秒）。 */
  static computeAgeMs(record: CacheRecord, now: number): number {
    const h: Headers = record.headers();
    const dateStr: string | null = h.get('Date');
    const dateMs: number = dateStr === null ? -1 : CacheInterceptor.parseHttpDate(dateStr);
    const apparentReceivedAge: number = dateMs >= 0
      ? Math.max(0, record.meta.responseTime - dateMs)
      : 0;
    const responseDelay: number = Math.max(0, record.meta.responseTime - record.meta.requestTime);
    const ageStr: string | null = h.get('Age');
    let ageValueMs: number = 0;
    if (ageStr !== null) {
      const trimmed: string = ageStr.trim();
      if (/^\d+$/.test(trimmed)) {
        ageValueMs = Number.parseInt(trimmed, 10) * 1000;
      }
    }
    const correctedAgeValue: number = ageValueMs + responseDelay;
    const initialAge: number = Math.max(apparentReceivedAge, correctedAgeValue);
    const residentDuration: number = Math.max(0, now - record.meta.responseTime);
    return initialAge + residentDuration;
  }

  /** RFC 7234 §4.2：max-age → Expires - Date → 0（未给缓存信息）。 */
  static freshnessLifetimeMs(record: CacheRecord): number {
    const h: Headers = record.headers();
    const ccValues: string[] = h.values('Cache-Control');
    if (ccValues.length > 0) {
      const directives: Map<string, string | null> = CacheInterceptor.parseDirectives(ccValues);
      if (directives.has('no-store') || directives.has('no-cache')) {
        return 0;
      }
      const maxAge: number = CacheInterceptor.directiveIntFromMap(directives, 'max-age');
      if (maxAge >= 0) {
        return maxAge * 1000;
      }
    }
    const expires: string | null = h.get('Expires');
    if (expires !== null) {
      const exp: number = CacheInterceptor.parseHttpDate(expires);
      const date: string | null = h.get('Date');
      const base: number = date === null ? record.meta.responseTime : CacheInterceptor.parseHttpDate(date);
      if (exp > 0 && base > 0) {
        return exp - base;
      }
    }
    return 0;
  }

  /** 解析 Cache-Control / Pragma token 列表（支持带引号值与值内逗号）。 */
  static parseDirectives(values: string[]): Map<string, string | null> {
    const map: Map<string, string | null> = new Map<string, string | null>();
    for (let vIdx = 0; vIdx < values.length; vIdx++) {
      const header: string = values[vIdx];
      let pos: number = 0;
      const len: number = header.length;
      while (pos < len) {
        while (pos < len && (header.charAt(pos) === ' ' || header.charAt(pos) === '\t' || header.charAt(pos) === ',')) {
          pos++;
        }
        if (pos >= len) {
          break;
        }
        const tokenStart: number = pos;
        while (pos < len && header.charAt(pos) !== '=' && header.charAt(pos) !== ',') {
          pos++;
        }
        const name: string = header.substring(tokenStart, pos).trim().toLowerCase();
        let val: string | null = null;
        if (pos < len && header.charAt(pos) === '=') {
          pos++;
          while (pos < len && (header.charAt(pos) === ' ' || header.charAt(pos) === '\t')) {
            pos++;
          }
          if (pos < len && header.charAt(pos) === '"') {
            pos++;
            const valStart: number = pos;
            while (pos < len && header.charAt(pos) !== '"') {
              pos++;
            }
            val = header.substring(valStart, pos);
            if (pos < len && header.charAt(pos) === '"') {
              pos++;
            }
            while (pos < len && header.charAt(pos) !== ',') {
              pos++;
            }
          } else {
            const valStart: number = pos;
            while (pos < len && header.charAt(pos) !== ',') {
              pos++;
            }
            val = header.substring(valStart, pos).trim();
          }
        }
        if (name.length > 0) {
          map.set(name, val);
        }
        if (pos < len && header.charAt(pos) === ',') {
          pos++;
        }
      }
    }
    return map;
  }

  private static directiveIntFromMap(directives: Map<string, string | null>, name: string): number {
    const val: string | null | undefined = directives.get(name.toLowerCase());
    if (val === undefined || val === null) {
      return -1;
    }
    const trimmed: string = val.trim();
    if (!/^\d+$/.test(trimmed)) {
      return -1;
    }
    const v: number = Number.parseInt(trimmed, 10);
    return Number.isNaN(v) ? -1 : v;
  }

  static directiveSeconds(cacheControl: string, name: string): number {
    const directives: Map<string, string | null> = CacheInterceptor.parseDirectives([cacheControl]);
    return CacheInterceptor.directiveIntFromMap(directives, name);
  }

  static parseHttpDate(s: string): number {
    const t: number = Date.parse(s);
    return Number.isNaN(t) ? -1 : t;
  }

  /** 是否允许缓存该响应（对齐 OkHttp CacheStrategy.isCacheable）。 */
  static isCacheable(response: Response): boolean {
    if (response.code() === 302 || response.code() === 307) {
      if (response.headers().get('Location') === null) {
        return false;
      }
    } else if (response.code() !== 200 && response.code() !== 203 && response.code() !== 204 &&
      response.code() !== 300 && response.code() !== 301 && response.code() !== 308 &&
      response.code() !== 404 && response.code() !== 405 && response.code() !== 410 &&
      response.code() !== 414 && response.code() !== 501) {
      return false;
    }
    const h: Headers = response.headers();
    const ccValues: string[] = h.values('Cache-Control');
    if (ccValues.length > 0) {
      const directives: Map<string, string | null> = CacheInterceptor.parseDirectives(ccValues);
      if (directives.has('no-store')) {
        return false;
      }
    }
    const pragmaValues: string[] = h.values('Pragma');
    if (pragmaValues.length > 0 && ccValues.length === 0 && h.get('Expires') === null) {
      const pragmaDirectives: Map<string, string | null> = CacheInterceptor.parseDirectives(pragmaValues);
      if (pragmaDirectives.has('no-cache')) {
        return false;
      }
    }
    if (h.get('Content-Length') !== null && h.get('Expires') === null && ccValues.length === 0) {
      // 没有明确缓存信息时不落盘（OkHttp 对 heuristic 缓存默认为 0）
      return false;
    }
    return h.get('Expires') !== null || ccValues.length > 0;
  }

  /** 加 If-None-Match / If-Modified-Since；都取不到返回 null。 */
  static conditionalize(request: Request, record: CacheRecord): Request | null {
    const h: Headers = record.headers();
    const etag: string | null = h.get('ETag');
    const lastModified: string | null = h.get('Last-Modified');
    if (etag === null && lastModified === null) {
      return null;
    }
    const b = request.newBuilder();
    if (etag !== null) {
      b.header('If-None-Match', etag as string);
    }
    if (lastModified !== null) {
      b.header('If-Modified-Since', lastModified as string);
    }
    return b.build();
  }

  /** 304 合并：缓存头 + 网络头（网络头覆盖同名，不追加重复），body 用缓存体。 */
  static combine(network: Response, record: CacheRecord, request: Request): Response {
    const cached: Response = record.toResponse(request);
    const builder = cached.newBuilder();
    const nh: Headers = network.headers();
    const networkNames: Set<string> = new Set<string>();
    for (let i = 0; i < nh.size(); i++) {
      const lower: string = nh.name(i).toLowerCase();
      if (lower !== 'content-length') {
        networkNames.add(lower);
      }
    }
    networkNames.forEach((lowerName: string): void => {
      builder.removeHeader(lowerName);
    });
    for (let i = 0; i < nh.size(); i++) {
      const name: string = nh.name(i);
      const value: string = nh.value(i);
      if (name.toLowerCase() === 'content-length') {
        continue; // 304 的 Content-Length 是 0，不能覆盖缓存体长度
      }
      builder.addHeader(name, value);
    }
    builder.code(200);
    builder.message('OK (cached, revalidated)');
    return builder.build();
  }
}
