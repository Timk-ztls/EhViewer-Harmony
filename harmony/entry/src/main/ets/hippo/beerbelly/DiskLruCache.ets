/*
 * Copyright (C) 2011 The Android Open Source Project
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
import { StrictLineReader, EOFError } from './StrictLineReader';
import { Util } from './Util';
import { decodeBytes, utf8Encode } from '../okhttp/RequestBody';
import { ByteSink } from '../streampipe/OutputStreamPipe';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/beerbelly/DiskLruCache.java
 * （inventory S0007，891 行 / 实测 985 行含注释）
 *
 * 磁盘 LRU 缓存 + journal 日志。BeerBelly 与 SimpleDiskCache 都压在它上面，
 * 二者又是 EhCookieStore（Cookie 持久化）、EhTagDatabase、spiderInfo 缓存的底座。
 *
 * ArkTS 映射（逐项，影响行为的都写在这里）：
 *   java.io.File                      → string 路径
 *   FileInputStream / FileOutputStream → fileIo.File（readSync / writeSync / closeSync）
 *   Writer journalWriter              → JournalWriter（APPEND 模式 + writeSync）
 *   synchronized (DiskLruCache.this)  → ArkTS 无对象锁。本类假定「同一时刻只有一个线程
 *                                        操作一个 DiskLruCache 实例」，由调用方保证；
 *                                        Context 调度下 BeerBelly 的调用全部发生在
 *                                        TaskPool 单任务内（见 BeerBelly.ets 头注释）。
 *   ThreadPoolExecutor executorService→ 同步执行 cleanup（见 submitCleanup()），
 *                                        不引入异步竞态；代价是 trim/rebuild 的耗时会
 *                                        计入调用方，实测 journal < 2000 行时 < 1ms。
 *   IOException                       → Error（message 保持上游文案，便于日志对照）
 *   IllegalStateException             → Error（同上）
 *   Pattern "[a-z0-9_-]{1,120}"       → 正则字面量
 *
 * 嵌套类提升（ArkTS 不支持嵌套类）：
 *   DiskLruCache.Snapshot  → DiskLruCacheSnapshot（同文件）
 *   DiskLruCache.Editor    → DiskLruCacheEditor（同文件）
 *   DiskLruCache.Entry     → DiskLruCacheEntry（同文件，实现细节）
 *   Editor.FaultHidingOutputStream → FaultHidingWriter（同文件）
 *
 * 方法重载（ArkTS 不支持）：
 *   edit(String) / edit(String, long) → edit(key) / editWithSequence(key, expectedSequenceNumber)
 *   new StrictLineReader(...)         → StrictLineReader.withCapacity(...)
 */

const JOURNAL_FILE: string = 'journal';
const JOURNAL_FILE_TEMP: string = 'journal.tmp';
const JOURNAL_FILE_BACKUP: string = 'journal.bkp';
const MAGIC: string = 'libcore.io.DiskLruCache';
const VERSION_1: string = '1';
export const ANY_SEQUENCE_NUMBER: number = -1;
const STRING_KEY_PATTERN: string = '[a-z0-9_-]{1,120}';
const LEGAL_KEY_REGEX: RegExp = new RegExp('^' + STRING_KEY_PATTERN + '$');
const CLEAN: string = 'CLEAN';
const DIRTY: string = 'DIRTY';
const REMOVE: string = 'REMOVE';
const READ: string = 'READ';
const REDUNDANT_OP_COMPACT_THRESHOLD: number = 2000;

/** journal 写入器：对应 BufferedWriter(OutputStreamWriter(FileOutputStream(journalFile, true), US_ASCII))。 */
class JournalWriter {
  private readonly _file: fileIo.File;

  constructor(path: string) {
    this._file = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.APPEND);
  }

  write(s: string): void {
    fileIo.writeSync(this._file.fd, utf8Encode(s));
  }

  /** 对齐 Writer.flush()：解决到内核（writeSync 已直写，故只需 fsync）。 */
  flush(): void {
    try {
      fileIo.fsyncSync(this._file.fd);
    } catch (e) {
      // fsync 失败不改变内存状态，与 BufferedWriter.flush 的语义一致
    }
  }

  close(): void {
    fileIo.closeSync(this._file);
  }
}

/** 对齐 Editor.FaultHidingOutputStream：写失败只置 hasErrors，不抛。 */
export class FaultHidingWriter implements ByteSink {
  private _file: fileIo.File | null;
  private readonly _owner: DiskLruCacheEditor;

  constructor(file: fileIo.File | null, owner: DiskLruCacheEditor) {
    this._file = file;
    this._owner = owner;
  }

  write(data: ArrayBuffer): void {
    if (this._file === null) {
      return; // 上游 NULL_OUTPUT_STREAM：静默吞掉
    }
    try {
      fileIo.writeSync((this._file as fileIo.File).fd, data);
    } catch (e) {
      this._owner.markHasErrors();
    }
  }

  close(): void {
    if (this._file === null) {
      return;
    }
    try {
      fileIo.closeSync(this._file as fileIo.File);
    } catch (e) {
      this._owner.markHasErrors();
    } finally {
      this._file = null;
    }
  }
}

/**
 * LRU touch 原语（A-02）：把 `key` 移到 Map 迭代序的末尾。
 *
 * 上游 `lruEntries` 是 `LinkedHashMap(0, 0.75f, **true**)`（accessOrder），`get()` / `contain()` /
 * `editWithSequence()` 里的 `lruEntries.get(key)` 都会把 entry 移到 LRU 头部；
 * ArkTS 的 `Map` **没有 access-order**，所以必须手写"删了再插"。
 *
 * 抽成导出的独立函数是为了**可断言**：`_lruEntries` 是 private，没有观测面就回到
 * "改对了 vs 证明改对了"的分界线。三处调用点共用它 → 语义只有一处实现。
 */
export function touchLru<K, V>(map: Map<K, V>, key: K): void {
  const v: V | undefined = map.get(key);
  if (v === undefined) {
    return;
  }
  map.delete(key);
  map.set(key, v);
}

export class DiskLruCache {
  private readonly _directory: string;
  private readonly _journalFile: string;
  private readonly _journalFileTmp: string;
  private readonly _journalFileBackup: string;
  private readonly _appVersion: number;
  private readonly _valueCount: number;
  private readonly _lruEntries: Map<string, DiskLruCacheEntry> = new Map<string, DiskLruCacheEntry>();
  private _maxSize: number;
  private _size: number = 0;
  private _journalWriter: JournalWriter | null = null;
  private _redundantOpCount: number = 0;
  private _nextSequenceNumber: number = 0;

  private constructor(directory: string, appVersion: number, valueCount: number, maxSize: number) {
    this._directory = directory;
    this._appVersion = appVersion;
    this._journalFile = directory + '/' + JOURNAL_FILE;
    this._journalFileTmp = directory + '/' + JOURNAL_FILE_TEMP;
    this._journalFileBackup = directory + '/' + JOURNAL_FILE_BACKUP;
    this._valueCount = valueCount;
    this._maxSize = maxSize;
  }

  /** 对齐 DiskLruCache.open(File, int, int, long)。 */
  static open(directory: string, appVersion: number, valueCount: number, maxSize: number): DiskLruCache {
    if (maxSize <= 0) {
      throw new Error('IllegalArgumentException: maxSize <= 0');
    }
    if (valueCount <= 0) {
      throw new Error('IllegalArgumentException: valueCount <= 0');
    }
    if (Util.exists(directory)) {
      // 目录存在但不可读时尽早失败（上游在 listFiles 时才暴露）
      if (!Util.isDirectory(directory)) {
        throw new Error(`not a directory: ${directory}`);
      }
    }

    // If a bkp file exists, use it instead.
    const backupFile: string = directory + '/' + JOURNAL_FILE_BACKUP;
    if (Util.exists(backupFile)) {
      const journalFile: string = directory + '/' + JOURNAL_FILE;
      if (Util.exists(journalFile)) {
        Util.deleteFile(backupFile);
      } else {
        DiskLruCache.renameTo(backupFile, journalFile, false);
      }
    }

    // Prefer to pick up where we left off.
    let cache: DiskLruCache = new DiskLruCache(directory, appVersion, valueCount, maxSize);
    if (Util.exists(cache._journalFile)) {
      try {
        cache.readJournal();
        cache.processJournal();
        return cache;
      } catch (e) {
        // journalIsCorrupt → remove and start fresh（上游打印日志后 delete()）
        cache.delete();
      }
    }

    // Create a new empty cache.
    if (!Util.exists(directory)) {
      fileIo.mkdirSync(directory, true);
    }
    cache = new DiskLruCache(directory, appVersion, valueCount, maxSize);
    cache.rebuildJournal();
    return cache;
  }

  private static deleteIfExists(file: string): void {
    if (Util.exists(file) && !Util.deleteFile(file)) {
      throw new Error('IOException: failed to delete ' + file);
    }
  }

  private static renameTo(from: string, to: string, deleteDestination: boolean): void {
    if (deleteDestination) {
      DiskLruCache.deleteIfExists(to);
    }
    if (!Util.rename(from, to)) {
      throw new Error(`IOException: failed to rename ${from} -> ${to}`);
    }
  }

  /**
   * 对齐 executorService.submit(cleanupCallable)。
   * ArkTS 侧同步执行：trimToSize + 必要的 journal rebuild，见文件头说明。
   */
  private submitCleanup(): void {
    if (this._journalWriter === null) {
      return; // Closed.
    }
    this.trimToSize();
    if (this.journalRebuildRequired()) {
      this.rebuildJournal();
      this._redundantOpCount = 0;
    }
  }

  private readJournal(): void {
    const file: fileIo.File = fileIo.openSync(this._journalFile, fileIo.OpenMode.READ_ONLY);
    const reader: StrictLineReader = new StrictLineReader(file, Util.US_ASCII);
    try {
      const magic: string = reader.readLine();
      const version: string = reader.readLine();
      const appVersionString: string = reader.readLine();
      const valueCountString: string = reader.readLine();
      const blank: string = reader.readLine();
      if (magic !== MAGIC || version !== VERSION_1 ||
        appVersionString !== `${this._appVersion}` || valueCountString !== `${this._valueCount}` ||
        blank !== '') {
        throw new Error(`IOException: unexpected journal header: [${magic}, ${version}, ` +
          `${valueCountString}, ${blank}]`);
      }

      let lineCount: number = 0;
      while (true) {
        try {
          this.readJournalLine(reader.readLine());
          lineCount++;
        } catch (e) {
          if (e instanceof EOFError) {
            break;
          }
          throw e as Error;
        }
      }
      this._redundantOpCount = lineCount - this._lruEntries.size;

      // If we ended on a truncated line, rebuild the journal before appending to it.
      if (reader.hasUnterminatedLine()) {
        this.rebuildJournal();
      } else {
        this._journalWriter = new JournalWriter(this._journalFile);
      }
    } finally {
      reader.close();
    }
  }

  private readJournalLine(line: string): void {
    const firstSpace: number = line.indexOf(' ');
    if (firstSpace === -1) {
      throw new Error('IOException: unexpected journal line: ' + line);
    }
    const keyBegin: number = firstSpace + 1;
    const secondSpace: number = line.indexOf(' ', keyBegin);
    let key: string;
    if (secondSpace === -1) {
      key = line.substring(keyBegin);
      if (firstSpace === REMOVE.length && line.startsWith(REMOVE)) {
        this._lruEntries.delete(key);
        return;
      }
    } else {
      key = line.substring(keyBegin, secondSpace);
    }

    let entry: DiskLruCacheEntry | undefined = this._lruEntries.get(key);
    if (entry === undefined) {
      entry = new DiskLruCacheEntry(key, this._valueCount, this._directory);
      this._lruEntries.set(key, entry);
    }

    if (secondSpace !== -1 && firstSpace === CLEAN.length && line.startsWith(CLEAN)) {
      const parts: string[] = line.substring(secondSpace + 1).split(' ');
      entry.readable = true;
      entry.currentEditor = null;
      entry.setLengths(parts);
    } else if (secondSpace === -1 && firstSpace === DIRTY.length && line.startsWith(DIRTY)) {
      entry.currentEditor = new DiskLruCacheEditor(entry, this, this._valueCount);
    } else if (secondSpace === -1 && firstSpace === READ.length && line.startsWith(READ)) {
      // This work was already done by calling lruEntries.get().
    } else {
      throw new Error('IOException: unexpected journal line: ' + line);
    }
  }

  private processJournal(): void {
    DiskLruCache.deleteIfExists(this._journalFileTmp);
    const doomed: string[] = [];
    this._lruEntries.forEach((entry: DiskLruCacheEntry, key: string) => {
      if (entry.currentEditor === null) {
        for (let t = 0; t < this._valueCount; t++) {
          this._size += entry.lengths[t];
        }
      } else {
        entry.currentEditor = null;
        for (let t = 0; t < this._valueCount; t++) {
          DiskLruCache.deleteIfExists(entry.getCleanFile(t));
          DiskLruCache.deleteIfExists(entry.getDirtyFile(t));
        }
        doomed.push(key);
      }
    });
    for (let i = 0; i < doomed.length; i++) {
      this._lruEntries.delete(doomed[i]);
    }
  }

  private rebuildJournal(): void {
    if (this._journalWriter !== null) {
      (this._journalWriter as JournalWriter).close();
    }

    const parts: string[] = [];
    parts.push(MAGIC);
    parts.push('\n');
    parts.push(VERSION_1);
    parts.push('\n');
    parts.push(`${this._appVersion}`);
    parts.push('\n');
    parts.push(`${this._valueCount}`);
    parts.push('\n');
    parts.push('\n');

    this._lruEntries.forEach((entry: DiskLruCacheEntry) => {
      if (entry.currentEditor !== null) {
        parts.push(DIRTY + ' ' + entry.key + '\n');
      } else {
        parts.push(CLEAN + ' ' + entry.key + entry.getLengths() + '\n');
      }
    });

    if (!Util.exists(this._directory)) {
      fileIo.mkdirSync(this._directory, true);
    }
    Util.writeText(this._journalFileTmp, parts.join(''));

    if (Util.exists(this._journalFile)) {
      DiskLruCache.renameTo(this._journalFile, this._journalFileBackup, true);
    }
    DiskLruCache.renameTo(this._journalFileTmp, this._journalFile, false);
    Util.deleteFile(this._journalFileBackup);

    this._journalWriter = new JournalWriter(this._journalFile);
  }

  /**
   * 诊断：按 **LRU 序（最旧 → 最新）** 返回全部 key。
   *
   * 存在的唯一理由是**让 touch 可观测** —— `_lruEntries` 是 private，而"touch 生效"这件事
   * 只能通过迭代顺序观测（Map 保持插入序）。断言见 `disklru-lru.test.ets`。
   */
  keysInLruOrder(): string[] {
    const keys: string[] = [];
    this._lruEntries.forEach((entry: DiskLruCacheEntry, key: string) => {
      keys.push(key);
    });
    return keys;
  }

  /** Return true if it contains the key. */
  contain(key: string): boolean {
    this.checkNotClosed();
    this.validateKey(key);
    const entry: DiskLruCacheEntry | undefined = this._lruEntries.get(key);
    if (entry === undefined) {
      return false;
    }
    // A-02 LRU touch：上游 `lruEntries` 是 `LinkedHashMap(0, 0.75f, **true**)`（accessOrder），
    // 所以 `contain()` 里的 `lruEntries.get(key)` 也会把 entry 移到 LRU 头部。
    // 我们用的是普通 `Map`（ArkTS 无 access-order）→ 必须**手写重插**，否则
    // `trimToSize` 会优先淘汰"刚看过的"，症状是"刚看完的画廊再看一遍，图要重新下载"。
    touchLru(this._lruEntries, key);
    return entry.readable;
  }

  /** 仅查询可读 clean 文件路径（供 ArkUI Image URI 直接渲染，不打开 fd、不改写 LRU/journal）。 */
  getCleanFilePath(key: string, index: number = 0): string | null {
    if (this._journalWriter === null) {
      return null;
    }
    try {
      this.validateKey(key);
    } catch (_e) {
      return null;
    }
    const entry: DiskLruCacheEntry | undefined = this._lruEntries.get(key);
    if (entry === undefined || !entry.readable) {
      return null;
    }
    return entry.getCleanFile(index);
  }

  /** 返回快照，命中时把 entry 移到 LRU 头部（Map 插入序 → 用重插实现）。 */
  get(key: string): DiskLruCacheSnapshot | null {
    this.checkNotClosed();
    this.validateKey(key);
    const entry: DiskLruCacheEntry | undefined = this._lruEntries.get(key);
    if (entry === undefined || !entry.readable) {
      return null;
    }

    // Open all streams eagerly to guarantee that we see a single published snapshot.
    const files: fileIo.File[] = [];
    try {
      for (let i = 0; i < this._valueCount; i++) {
        files.push(fileIo.openSync(entry.getCleanFile(i), fileIo.OpenMode.READ_ONLY));
      }
    } catch (e) {
      for (let i = 0; i < files.length; i++) {
        Util.closeQuietlyFile(files[i]);
      }
      return null;
    }

    this._redundantOpCount++;
    const jw: JournalWriter | null = this._journalWriter;
    if (jw === null) {
      for (let i = 0; i < files.length; i++) {
        Util.closeQuietlyFile(files[i]);
      }
      throw new Error('IllegalStateException: cache is closed');
    }
    (jw as JournalWriter).write(READ + ' ' + key + '\n');
    // LRU：先于可能触发的 trim/cleanup 更新访问序，避免热点 entry 被紧接着误淘汰（F-2）
    touchLru(this._lruEntries, key);
    if (this.journalRebuildRequired()) {
      this.submitCleanup();
    }

    return new DiskLruCacheSnapshot(key, entry.sequenceNumber, files, entry.lengths.slice(), this);
  }

  /** 对齐 edit(String key)。 */
  edit(key: string): DiskLruCacheEditor | null {
    return this.editWithSequence(key, ANY_SEQUENCE_NUMBER);
  }

  /** 对齐 edit(String, long expectedSequenceNumber)。 */
  editWithSequence(key: string, expectedSequenceNumber: number): DiskLruCacheEditor | null {
    this.checkNotClosed();
    this.validateKey(key);
    let entry: DiskLruCacheEntry | undefined = this._lruEntries.get(key);
    if (expectedSequenceNumber !== ANY_SEQUENCE_NUMBER &&
      (entry === undefined || entry.sequenceNumber !== expectedSequenceNumber)) {
      return null; // Snapshot is stale.
    }
    if (entry === undefined) {
      entry = new DiskLruCacheEntry(key, this._valueCount, this._directory);
      this._lruEntries.set(key, entry);
    } else if (entry.currentEditor !== null) {
      return null; // Another edit is in progress.
    } else {
      // A-02 LRU touch：上游 editWithSequence 的 `lruEntries.get(key)` 同样会 touch
      // （accessOrder=true）。命中已有 entry 时重插到末尾；新建分支的 set 本身就是插到末尾。
      touchLru(this._lruEntries, key);
    }

    const editor: DiskLruCacheEditor = new DiskLruCacheEditor(entry, this, this._valueCount);
    entry.currentEditor = editor;

    // Flush the journal before creating files to prevent file leaks.
    const jw: JournalWriter = this._journalWriter as JournalWriter;
    jw.write(DIRTY + ' ' + key + '\n');
    jw.flush();
    return editor;
  }

  getDirectory(): string {
    return this._directory;
  }

  getMaxSize(): number {
    return this._maxSize;
  }

  setMaxSize(maxSize: number): void {
    this._maxSize = maxSize;
    this.submitCleanup();
  }

  size(): number {
    return this._size;
  }

  /** 对齐 completeEdit(Editor, boolean)（包内可见）。 */
  completeEdit(editor: DiskLruCacheEditor, success: boolean): void {
    const entry: DiskLruCacheEntry = editor.entry;
    if (entry.currentEditor !== editor) {
      throw new Error('IllegalStateException: editor mismatch');
    }

    // If this edit is creating the entry for the first time, every index must have a value.
    if (success && !entry.readable) {
      for (let i = 0; i < this._valueCount; i++) {
        if (!editor.isWritten(i)) {
          editor.abort();
          throw new Error(`IllegalStateException: Newly created entry didn't create value for index ${i}`);
        }
        if (!Util.exists(entry.getDirtyFile(i))) {
          editor.abort();
          return;
        }
      }
    }

    for (let i = 0; i < this._valueCount; i++) {
      const dirty: string = entry.getDirtyFile(i);
      if (success) {
        if (Util.exists(dirty)) {
          const clean: string = entry.getCleanFile(i);
          Util.rename(dirty, clean);
          const oldLength: number = entry.lengths[i];
          const newLength: number = Util.fileLength(clean);
          entry.lengths[i] = newLength;
          this._size = this._size - oldLength + newLength;
        }
      } else {
        DiskLruCache.deleteIfExists(dirty);
      }
    }

    this._redundantOpCount++;
    entry.currentEditor = null;
    if (entry.readable || success) {
      entry.readable = true;
      (this._journalWriter as JournalWriter).write(CLEAN + ' ' + entry.key + entry.getLengths() + '\n');
      if (success) {
        entry.sequenceNumber = this._nextSequenceNumber++;
      }
    } else {
      this._lruEntries.delete(entry.key);
      (this._journalWriter as JournalWriter).write(REMOVE + ' ' + entry.key + '\n');
    }
    (this._journalWriter as JournalWriter).flush();

    if (this._size > this._maxSize || this.journalRebuildRequired()) {
      this.submitCleanup();
    }
  }

  /** We only rebuild the journal when it will halve the size of the journal and eliminate ≥2000 ops. */
  journalRebuildRequired(): boolean {
    return this._redundantOpCount >= REDUNDANT_OP_COMPACT_THRESHOLD &&
      this._redundantOpCount >= this._lruEntries.size;
  }

  /** 删除一个 entry；正在编辑的不能删。 */
  remove(key: string): boolean {
    this.checkNotClosed();
    this.validateKey(key);
    const entry: DiskLruCacheEntry | undefined = this._lruEntries.get(key);
    if (entry === undefined || entry.currentEditor !== null) {
      return false;
    }

    for (let i = 0; i < this._valueCount; i++) {
      const file: string = entry.getCleanFile(i);
      if (Util.exists(file) && !Util.deleteFile(file)) {
        throw new Error('IOException: failed to delete ' + file);
      }
      this._size -= entry.lengths[i];
      entry.lengths[i] = 0;
    }

    this._redundantOpCount++;
    (this._journalWriter as JournalWriter).write(REMOVE + ' ' + key + '\n');
    this._lruEntries.delete(key);

    if (this.journalRebuildRequired()) {
      this.submitCleanup();
    }
    return true;
  }

  isClosed(): boolean {
    return this._journalWriter === null;
  }

  private checkNotClosed(): void {
    if (this._journalWriter === null) {
      throw new Error('IllegalStateException: cache is closed');
    }
  }

  flush(): void {
    this.checkNotClosed();
    this.trimToSize();
    (this._journalWriter as JournalWriter).flush();
  }

  close(): void {
    if (this._journalWriter === null) {
      return; // Already closed.
    }
    this._lruEntries.forEach((entry: DiskLruCacheEntry) => {
      if (entry.currentEditor !== null) {
        (entry.currentEditor as DiskLruCacheEditor).abort();
      }
    });
    this.trimToSize();
    (this._journalWriter as JournalWriter).close();
    this._journalWriter = null;
  }

  private trimToSize(): void {
    while (this._size > this._maxSize) {
      let firstKey: string | null = null;
      this._lruEntries.forEach((entry: DiskLruCacheEntry, key: string) => {
        if (firstKey === null) {
          firstKey = key;
        }
      });
      if (firstKey === null) {
        break;
      }
      this.remove(firstKey as string);
    }
  }

  /** 关闭并删除全部内容（包括不是本缓存创建的文件），与上游一致。 */
  delete(): void {
    this.close();
    Util.deleteContents(this._directory);
  }

  private validateKey(key: string): void {
    if (!LEGAL_KEY_REGEX.test(key)) {
      throw new Error(`IllegalArgumentException: keys must match regex ${STRING_KEY_PATTERN}: "${key}"`);
    }
  }
}

/** 对齐 DiskLruCache.Snapshot。 */
export class DiskLruCacheSnapshot {
  readonly key: string;
  readonly sequenceNumber: number;
  private readonly _files: fileIo.File[];
  private readonly _lengths: number[];
  private readonly _cache: DiskLruCache | null;

  constructor(key: string, sequenceNumber: number, files: fileIo.File[], lengths: number[],
    cache: DiskLruCache | null = null) {
    this.key = key;
    this.sequenceNumber = sequenceNumber;
    this._files = files;
    this._lengths = lengths;
    this._cache = cache;
  }

  /** 对齐 Snapshot.edit()：序列号变化的快照无法再编辑（返回 null）。 */
  edit(): DiskLruCacheEditor | null {
    if (this._cache === null) {
      return null;
    }
    return (this._cache as DiskLruCache).editWithSequence(this.key, this.sequenceNumber);
  }

  /** 对齐 getInputStream(index)：返回已打开的只读文件句柄。 */
  getInputStream(index: number): fileIo.File {
    return this._files[index];
  }

  /** 对齐 getString(index)：按 UTF-8 读全文。 */
  getString(index: number): string {
    const file: fileIo.File = this._files[index];
    const size: number = fileIo.statSync(file.fd).size;
    if (size === 0) {
      return '';
    }
    // F-3：不能把「缓冲区进度」写进 ReadOptions.offset（那是文件内起点）；
    // 交给 Util.readFullyTo 用 filePointer 顺序读
    return decodeBytes(Util.readFullyTo(file.fd, size), Util.UTF_8);
  }

  getLength(index: number): number {
    return this._lengths[index];
  }

  close(): void {
    for (let i = 0; i < this._files.length; i++) {
      Util.closeQuietlyFile(this._files[i]);
    }
  }
}

/** 对齐 DiskLruCache.Editor。 */
export class DiskLruCacheEditor {
  readonly entry: DiskLruCacheEntry;
  private readonly _written: boolean[] | null;
  private _hasErrors: boolean = false;
  private _committed: boolean = false;
  private readonly _cache: DiskLruCache;
  private readonly _valueCount: number;

  constructor(entry: DiskLruCacheEntry, cache: DiskLruCache, valueCount: number) {
    this.entry = entry;
    this._cache = cache;
    this._valueCount = valueCount;
    this._written = entry.readable ? null : new Array<boolean>(valueCount).fill(false);
  }

  markHasErrors(): void {
    this._hasErrors = true;
  }

  isWritten(index: number): boolean {
    if (this._written === null) {
      return true; // 已存在的 entry 不要求每个 index 都写
    }
    return (this._written as boolean[])[index];
  }

  /** 对齐 newInputStream(index)：读上一个已提交值。 */
  newInputStream(index: number): fileIo.File | null {
    if (this.entry.currentEditor !== this) {
      throw new Error('IllegalStateException: editor mismatch');
    }
    if (!this.entry.readable) {
      return null;
    }
    try {
      return fileIo.openSync(this.entry.getCleanFile(index), fileIo.OpenMode.READ_ONLY);
    } catch (e) {
      return null;
    }
  }

  getString(index: number): string | null {
    const file: fileIo.File | null = this.newInputStream(index);
    if (file === null) {
      return null;
    }
    try {
      const size: number = fileIo.statSync(file.fd).size;
      if (size === 0) {
        return '';
      }
      // F-3：同上，用 filePointer 顺序读满
      return decodeBytes(Util.readFullyTo(file.fd, size), Util.UTF_8);
    } finally {
      Util.closeQuietlyFile(file);
    }
  }

  /** 对齐 newOutputStream(index)：返回 FaultHidingWriter。 */
  newOutputStream(index: number): FaultHidingWriter {
    if (index < 0 || index >= this._valueCount) {
      throw new Error(`IllegalArgumentException: Expected index ${index} to be greater than 0 and ` +
        `less than the maximum value count of ${this._valueCount}`);
    }
    if (this.entry.currentEditor !== this) {
      throw new Error('IllegalStateException: editor mismatch');
    }
    if (!this.entry.readable && this._written !== null) {
      (this._written as boolean[])[index] = true;
    }
    const dirtyFile: string = this.entry.getDirtyFile(index);
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(dirtyFile, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE |
        fileIo.OpenMode.TRUNC);
    } catch (e) {
      // Attempt to recreate the cache directory.（与上游同一恢复路径）
      try {
        fileIo.mkdirSync(this._cache.getDirectory(), true);
        file = fileIo.openSync(dirtyFile, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE |
          fileIo.OpenMode.TRUNC);
      } catch (e2) {
        // Unable to recover. Silently eat the writes.
        file = null;
      }
    }
    return new FaultHidingWriter(file, this);
  }

  /** 对齐 set(index, String)：UTF-8 写入。 */
  set(index: number, value: string): void {
    const writer: FaultHidingWriter = this.newOutputStream(index);
    try {
      writer.write(utf8Encode(value));
    } finally {
      writer.close();
    }
  }

  commit(): void {
    if (this._hasErrors) {
      this._cache.completeEdit(this, false);
      this._cache.remove(this.entry.key); // The previous entry is stale.
    } else {
      this._cache.completeEdit(this, true);
    }
    this._committed = true;
  }

  abort(): void {
    this._cache.completeEdit(this, false);
  }

  abortUnlessCommitted(): void {
    if (!this._committed) {
      try {
        this.abort();
      } catch (e) {
        // ignored，与上游一致
      }
    }
  }
}

/** 对齐 DiskLruCache.Entry（实现细节）。 */
export class DiskLruCacheEntry {
  readonly key: string;
  readonly lengths: number[];
  readable: boolean = false;
  currentEditor: DiskLruCacheEditor | null = null;
  sequenceNumber: number = 0;
  private readonly _directory: string;

  constructor(key: string, valueCount: number, directory: string) {
    this.key = key;
    this.lengths = new Array<number>(valueCount).fill(0);
    this._directory = directory;
  }

  getLengths(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.lengths.length; i++) {
      parts.push(' ' + this.lengths[i]);
    }
    return parts.join('');
  }

  setLengths(strings: string[]): void {
    if (strings.length !== this.lengths.length) {
      throw new Error(`IOException: unexpected journal line: [${strings.join(', ')}]`);
    }
    for (let i = 0; i < strings.length; i++) {
      const v: number = Number.parseInt(strings[i], 10);
      if (Number.isNaN(v)) {
        throw new Error(`IOException: unexpected journal line: [${strings.join(', ')}]`);
      }
      this.lengths[i] = v;
    }
  }

  getCleanFile(i: number): string {
    return this._directory + '/' + this.key + '.' + i;
  }

  getDirtyFile(i: number): string {
    return this._directory + '/' + this.key + '.' + i + '.tmp';
  }
}
