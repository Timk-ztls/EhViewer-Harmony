/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/gallery/ArchiveGalleryProvider.java（260 行）
 *
 * 作用：把**压缩包**（zip/7z）当成画廊数据源。上游是**两段流水线**：
 *   ArchiveTask（线程 1）：解析归档 → 条目按路径自然序排序 → 收到请求就把该条目**解压进 Pipe**
 *   DecodeTask（线程 2）：从 Pipe 读流 → `Image.decode(BitmapDrawable.createFromStream(...))` → 通知
 * 两个线程之间用 `LinkedHashMap<Integer, InputStream> streams` + `wait()/notify()` 交接。
 *
 * ── 与上游的三处必要差异（登记 D-024 系列）───────────────────────────────────
 * 1) **两线程流水线 → 单线程异步泵**：`PriorityThread.start()` 在鸿蒙是同步执行（无真实线程），
 *    照搬会卡 UI。这里用同一个 `RequestPump`（与 DirGalleryProvider 共用，D-024）串行处理
 *    「解压 → 解码」。代价：解压与解码不再重叠（上游是流水线）。收益：无锁、无 Pipe、
 *    `streams` 那个「解压完等解码」的中间队列整类 bug 消失。
 *    —— 对"一次只翻一页"的阅读场景，重叠收益本就有限；真要恢复重叠需 `taskpool` + 可序列化状态，
 *    而 `PixelMap` 不可跨线程，故不做。
 * 2) **Pipe 中间流 → 内存缓冲**：上游把条目解压进 `Pipe(4*1024)` 再让解码线程读；
 *    本实现把条目解压进 `BufferSink`（内存），再 `image.createImageSource(buffer)` 解码。
 *    因为 `Image.decodeStream` 只吃 fd，而归档条目没有 fd。缓冲上限 64MB（见 MAX_BUFFER_BYTES），
 *    超出即失败并报 `error_decoding_failed` —— 单页图片不会有这么大的。
 * 3) **构造参数**：上游 `(Context, Uri)` → 本 port `(UniFile)`（调用方先 `UniFile.fromUri(uri)`），
 *    与 DirGalleryProvider 一致，避免把 Context 拖进 gallery 层。
 *
 * `getImageFilename` / `saveToFile` / `saveToDir` 上游本身就是 `// TODO`，本 port 保持原样并注明。
 */

import fs from '@ohos.file.fs';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import image from '@ohos.multimedia.image';
import { GalleryProvider } from '../../lib/glgallery/GalleryProvider';
import { GalleryProvider2 } from './GalleryProvider2';
import { RequestPump, NO_REQUEST } from './RequestPump';
import { A7ZipArchive, A7ZipArchiveEntry } from './A7ZipArchive';
import { ArchiveFormat, isRarUnsupportedError, sniffRandomAccessFormat } from './ArchiveFormatSniffer';
import { Image } from '../../lib/image/Image';
import { UniFile } from '../../unifile/UniFile';
import { UniRandomAccessFile } from '../../unifile/UniRandomAccessFile';
import { Contracts, OutputStream } from '../../unifile/Contracts';
import { FileUtils } from '../../lib/yorozuya/FileUtils';
import { Utils } from '../../unifile/Utils';
import { AppConfig } from '../AppConfig';
import { GetText } from '../GetText';
import { NaturalComparator } from '../../util/NaturalComparator';

const LOG_DOMAIN: number = 0x0000;
const TAG: string = 'ArchiveGalleryProvider';

/** 单页解压缓冲上限（64MB）。超过即判定为异常条目，避免 OOM。 */
export const MAX_BUFFER_BYTES: number = 64 * 1024 * 1024;

export type ZipFallbackExtractor = (srcPath: string, outDir: string) => Promise<void>;

async function defaultZipFallbackExtractor(srcPath: string, outDir: string): Promise<void> {
  await zlib.decompressFile(srcPath, outDir, {});
}

interface ZlibSourcePath {
  path: string;
  staged: boolean;
}

/**
 * 收集解压出的字节（对位上游 `Pipe` 的写端，但落在内存里）。
 * 实现 unifile 的 `OutputStream`（名义类型），因为 `A7ZipArchive.openEntry(index, sink)` 要它。
 */
export class BufferSink implements OutputStream {
  private chunks: Uint8Array[] = [];
  private total: number = 0;
  private closed: boolean = false;
  /** 上限可注入：生产用 MAX_BUFFER_BYTES，测试用小值验证超限分支（行为不变）。 */
  private readonly mLimit: number;

  constructor(limit: number = MAX_BUFFER_BYTES) {
    this.mLimit = limit;
  }

  write(buffer: ArrayBuffer): void {
    this.writeBytes(buffer, 0, buffer.byteLength);
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    if (this.total + len > this.mLimit) {
      throw new Error(`[${TAG}] entry exceeds buffer limit(${this.mLimit})`);
    }
    const src: Uint8Array = new Uint8Array(buffer);
    const copy: Uint8Array = new Uint8Array(len);
    copy.set(src.subarray(off, off + len));
    this.chunks.push(copy);
    this.total += len;
  }

  flush(): void {
    // 内存 sink 无需 flush
  }

  close(): void {
    this.closed = true;
  }

  /** 合并成一个连续 ArrayBuffer（解码 API 要求连续内存）。 */
  toArrayBuffer(): ArrayBuffer {
    const out: ArrayBuffer = new ArrayBuffer(this.total);
    const view: Uint8Array = new Uint8Array(out);
    let at: number = 0;
    for (const chunk of this.chunks) {
      view.set(chunk, at);
      at += chunk.length;
    }
    return out;
  }

  byteLength(): number {
    return this.total;
  }
}

export class ArchiveGalleryProvider extends GalleryProvider2 {
  private static sZipFallbackExtractor: ZipFallbackExtractor = defaultZipFallbackExtractor;
  private static sSeqCounter: number = 0;

  /** 允许单测注入假 ZIP 解压器（生产默认走 `@kit.BasicServicesKit` `zlib.decompressFile`）。 */
  static setZipFallbackExtractor(extractor: ZipFallbackExtractor | null): void {
    ArchiveGalleryProvider.sZipFallbackExtractor = extractor === null ? defaultZipFallbackExtractor : extractor;
  }

  private readonly mFile: UniFile;

  /** 请求栈 + 单消费者泵（与 DirGalleryProvider 同一个类，D-024）。 */
  private mPump: RequestPump = new RequestPump();
  private mArchive: A7ZipArchive | null = null;
  private mEntries: A7ZipArchiveEntry[] = [];
  private mFallbackFilePaths: string[] = [];
  private mFallbackExtractDir: string | null = null;
  private mSize: number = GalleryProvider.STATE_WAIT;
  private mError: string = '';
  private mStartedTask: boolean = false;
  private mStopped: boolean = false;
  private mOpenPromise: Promise<number> | null = null;
  private mOpenResolve: ((size: number) => void) | null = null;

  constructor(file: UniFile) {
    super();
    this.mFile = file;
  }

  // ---------------------------------------------------------------- 生命周期

  private ensureOpenPromise(): void {
    if (this.mOpenPromise === null) {
      this.mOpenPromise = new Promise<number>((resolve: (size: number) => void): void => {
        this.mOpenResolve = resolve;
      });
    }
  }

  private resolveOpenPromise(size: number): void {
    const res: ((size: number) => void) | null = this.mOpenResolve;
    if (res !== null) {
      this.mOpenResolve = null;
      res(size);
    }
  }

  /** 等待归档头解析完毕（给 ArkUI Swiper 兜底模式读取总页数与页面文件）。 */
  waitUntilReady(): Promise<number> {
    if (this.mSize >= 0 || this.mSize === GalleryProvider.STATE_ERROR) {
      return Promise.resolve(this.mSize);
    }
    if (this.mOpenPromise !== null) {
      return this.mOpenPromise;
    }
    return Promise.resolve(this.mSize);
  }

  start(): void {
    super.start();
    this.mStopped = false;
    this.mPump.reset();
    if (!this.mStartedTask) {
      this.mStartedTask = true;
      this.ensureOpenPromise();
      // 不 await：解析归档是 IO，交给事件循环（上游是独立线程）
      this.archiveTask();
    }
  }

  stop(): void {
    this.mStopped = true;
    super.stop();
    this.mPump.stop();
    const archive: A7ZipArchive | null = this.mArchive;
    if (archive !== null) {
      archive.close();
      this.mArchive = null;
    }
    this.mEntries = [];
    this.mFallbackFilePaths = [];
    const fallbackDir: string | null = this.mFallbackExtractDir;
    this.mFallbackExtractDir = null;
    if (fallbackDir !== null) {
      try {
        FileUtils.delete(fallbackDir);
      } catch (e) {
        hilog.warn(LOG_DOMAIN, TAG, 'cleanup fallback dir failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
    }
    this.resolveOpenPromise(this.mSize);
  }

  size(): number {
    return this.mSize;
  }

  getError(): string {
    return this.mError;
  }

  // ---------------------------------------------------------------- 请求

  protected onRequest(index: number): void {
    this.mPump.push(index);
    this.notifyPageWait(index);
    this.pump();
  }

  protected onForceRequest(index: number): void {
    this.onRequest(index);
  }

  protected onCancelRequest(index: number): void {
    this.mPump.cancel(index);
  }

  // ---------------------------------------------------------------- 归档解析 + 解码泵

  private rarUnsupportedMessage(): string {
    const text: string = GetText.getString('error_rar_unsupported');
    return text.length > 0 ? text : 'RAR archive format is not supported';
  }

  private looksLikeZipUri(uri: string): boolean {
    const lower: string = uri.toLowerCase();
    return lower.endsWith('.zip') || lower.endsWith('.cbz');
  }

  private safeCloseUraf(uraf: UniRandomAccessFile | null): void {
    if (uraf === null) {
      return;
    }
    try {
      uraf.close();
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }

  private canReadRegularPath(path: string): boolean {
    if (path.length === 0) {
      return false;
    }
    try {
      return fs.accessSync(path);
    } catch (e) {
      hilog.debug(LOG_DOMAIN, TAG, 'accessSync skipped for %{public}s: %{public}s',
        path, e instanceof Error ? e.message : String(e));
      return false;
    }
  }

  private resolveZlibSourcePath(baseRoot: string, seq: number): ZlibSourcePath | null {
    const uri: string = this.mFile.getUri();
    const isExternalSandboxUri: boolean = uri.startsWith('file://docs/') || uri.startsWith('datashare://');
    const directPath: string = Contracts.toPath(uri);
    if (!isExternalSandboxUri && this.canReadRegularPath(directPath)) {
      return { path: directPath, staged: false };
    }

    const stagedPath: string = `${baseRoot}/eh_zip_src_${seq}.zip`;
    let srcFile: fs.File | null = null;
    let dstFile: fs.File | null = null;
    try {
      srcFile = Contracts.openReadFile(uri);
      dstFile = fs.openSync(stagedPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const buf: ArrayBuffer = new ArrayBuffer(65536);
      let readLen: number = fs.readSync(srcFile.fd, buf);
      while (readLen > 0) {
        fs.writeSync(dstFile.fd, buf, { length: readLen });
        readLen = fs.readSync(srcFile.fd, buf);
      }
      return { path: stagedPath, staged: true };
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'stage archive for zlib failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      try {
        if (fs.accessSync(stagedPath)) {
          fs.unlinkSync(stagedPath);
        }
      } catch (cleanupErr) {
        hilog.warn(LOG_DOMAIN, TAG, 'unlink staged archive failed: %{public}s',
          cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr));
      }
      return null;
    } finally {
      if (srcFile !== null) {
        try {
          fs.closeSync(srcFile);
        } catch (closeErr) {
          hilog.warn(LOG_DOMAIN, TAG, 'close staged src failed: %{public}s',
            closeErr instanceof Error ? closeErr.message : String(closeErr));
        }
      }
      if (dstFile !== null) {
        try {
          fs.closeSync(dstFile);
        } catch (closeErr) {
          hilog.warn(LOG_DOMAIN, TAG, 'close staged dst failed: %{public}s',
            closeErr instanceof Error ? closeErr.message : String(closeErr));
        }
      }
    }
  }

  private collectExtractedImages(rootDir: string): string[] {
    const collected: string[] = [];
    const stack: string[] = [rootDir];
    while (stack.length > 0) {
      const currentDir: string = stack.pop() as string;
      let children: string[] = [];
      try {
        children = fs.listFileSync(currentDir);
      } catch (e) {
        hilog.warn(LOG_DOMAIN, TAG, 'listFileSync failed in %{public}s: %{public}s',
          currentDir, e instanceof Error ? e.message : String(e));
        continue;
      }
      for (let i = 0; i < children.length; i++) {
        const childPath: string = `${currentDir}/${children[i]}`;
        try {
          const st: fs.Stat = fs.statSync(childPath);
          if (st.isDirectory()) {
            stack.push(childPath);
          } else if (GalleryProvider2.isSupportedImageName(children[i])) {
            collected.push(childPath);
          }
        } catch (statErr) {
          hilog.debug(LOG_DOMAIN, TAG, 'statSync skipped for %{public}s: %{public}s',
            childPath, statErr instanceof Error ? statErr.message : String(statErr));
        }
      }
    }
    const comparator: NaturalComparator = new NaturalComparator();
    const prefixLen: number = rootDir.length + 1;
    collected.sort((a: string, b: string): number => {
      const relA: string = a.length > prefixLen ? a.substring(prefixLen) : a;
      const relB: string = b.length > prefixLen ? b.substring(prefixLen) : b;
      return comparator.compare(relA, relB);
    });
    return collected;
  }

  private async tryZlibFallback(): Promise<string[] | null> {
    const tempDir: string | null = AppConfig.getTempDir();
    const baseRoot: string = (tempDir !== null && tempDir.length > 0) ? tempDir : '/tmp';
    const seq: number = ++ArchiveGalleryProvider.sSeqCounter;
    const extractDir: string = `${baseRoot}/eh_zip_fb_${seq}`;

    const sourceInfo: ZlibSourcePath | null = this.resolveZlibSourcePath(baseRoot, seq);
    if (sourceInfo === null) {
      return null;
    }

    let extractedOk: boolean = false;
    try {
      if (!FileUtils.ensureDirectory(extractDir)) {
        try {
          fs.mkdirSync(extractDir, true);
        } catch (mkdirErr) {
          hilog.warn(LOG_DOMAIN, TAG, 'mkdirSync fallback dir failed: %{public}s',
            mkdirErr instanceof Error ? mkdirErr.message : String(mkdirErr));
        }
      }
      await ArchiveGalleryProvider.sZipFallbackExtractor(sourceInfo.path, extractDir);
      extractedOk = true;
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'zlib fallback decompress failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      extractedOk = false;
    } finally {
      if (sourceInfo.staged) {
        try {
          if (fs.accessSync(sourceInfo.path)) {
            fs.unlinkSync(sourceInfo.path);
          }
        } catch (unlinkErr) {
          hilog.warn(LOG_DOMAIN, TAG, 'unlink staged archive failed: %{public}s',
            unlinkErr instanceof Error ? unlinkErr.message : String(unlinkErr));
        }
      }
    }

    if (!extractedOk || this.mStopped) {
      try {
        FileUtils.delete(extractDir);
      } catch (delErr) {
        hilog.warn(LOG_DOMAIN, TAG, 'cleanup failed fallback dir: %{public}s',
          delErr instanceof Error ? delErr.message : String(delErr));
      }
      return null;
    }

    const images: string[] = this.collectExtractedImages(extractDir);
    if (images.length === 0 || this.mStopped) {
      try {
        FileUtils.delete(extractDir);
      } catch (delErr) {
        hilog.warn(LOG_DOMAIN, TAG, 'cleanup empty fallback dir: %{public}s',
          delErr instanceof Error ? delErr.message : String(delErr));
      }
      return null;
    }

    this.mFallbackExtractDir = extractDir;
    return images;
  }

  /** 对位上游 `ArchiveTask.run()` 的前半段：打开归档 → 条目排序 → 置 size → notifyDataChanged。 */
  private async archiveTask(): Promise<void> {
    let uraf: UniRandomAccessFile | null = null;
    try {
      uraf = this.mFile.createRandomAccessFile('r');
    } catch (e) {
      Utils.throwIfFatal(e);
      uraf = null;
    }
    if (uraf === null) {
      this.mSize = GalleryProvider.STATE_ERROR;
      this.mError = GetText.getString('error_reading_failed');
      this.notifyDataChanged();
      this.resolveOpenPromise(this.mSize);
      return;
    }

    const sniffedFormat: ArchiveFormat = sniffRandomAccessFormat(uraf);
    if (sniffedFormat === ArchiveFormat.RAR) {
      this.safeCloseUraf(uraf);
      this.mSize = GalleryProvider.STATE_ERROR;
      this.mError = this.rarUnsupportedMessage();
      this.notifyDataChanged();
      this.resolveOpenPromise(this.mSize);
      return;
    }

    let archive: A7ZipArchive | null = null;
    let rarError: boolean = false;
    try {
      archive = A7ZipArchive.create(uraf);
    } catch (e) {
      Utils.throwIfFatal(e);
      rarError = isRarUnsupportedError(e);
      archive = null;
    }
    if (rarError) {
      this.safeCloseUraf(uraf);
      this.mSize = GalleryProvider.STATE_ERROR;
      this.mError = this.rarUnsupportedMessage();
      this.notifyDataChanged();
      this.resolveOpenPromise(this.mSize);
      return;
    }

    if (archive === null) {
      this.safeCloseUraf(uraf);
      if (this.mStopped) {
        this.resolveOpenPromise(this.mSize);
        return;
      }
      if (sniffedFormat === ArchiveFormat.ZIP || this.looksLikeZipUri(this.mFile.getUri())) {
        const fallbackPaths: string[] | null = await this.tryZlibFallback();
        if (this.mStopped) {
          this.resolveOpenPromise(this.mSize);
          return;
        }
        if (fallbackPaths !== null && fallbackPaths.length > 0) {
          this.mFallbackFilePaths = fallbackPaths;
          this.mSize = fallbackPaths.length;
          this.notifyDataChanged();
          this.resolveOpenPromise(this.mSize);
          await this.pumpAsync();
          return;
        }
      }
      this.mSize = GalleryProvider.STATE_ERROR;
      this.mError = GetText.getString('error_invalid_archive');
      this.notifyDataChanged();
      this.resolveOpenPromise(this.mSize);
      return;
    }

    if (this.mStopped) {
      archive.close();
      this.resolveOpenPromise(this.mSize);
      return;
    }

    this.mArchive = archive;
    const entries: A7ZipArchiveEntry[] = [];
    const count: number = archive.entryCount();
    for (let i = 0; i < count; i++) {
      entries.push(new A7ZipArchiveEntry(archive, i, archive.entryName(i)));
    }

    // 按路径自然序排序（a1, a2, a10 —— 与上游 naturalComparator 一致）
    const comparator: NaturalComparator = new NaturalComparator();
    entries.sort((a: A7ZipArchiveEntry, b: A7ZipArchiveEntry): number =>
      comparator.compare(a.getPath(), b.getPath()));

    this.mEntries = entries;
    this.mSize = entries.length;
    this.notifyDataChanged();
    this.resolveOpenPromise(this.mSize);

    await this.pumpAsync();
  }

  /** 触发泵（同步接口，泵在事件循环里推进）。 */
  private pump(): void {
    this.mPump.drain((index: number): Promise<void> => this.decodeAt(index));
  }

  /** archiveTask 内部要等泵跑完（保持与上游 run() 同构的"常驻消费者"语义）。 */
  private async pumpAsync(): Promise<void> {
    await this.mPump.drain((index: number): Promise<void> => this.decodeAt(index));
  }

  /** 解压 + 解码一页（上游把这两步拆在 ArchiveTask / DecodeTask）。 */
  private async decodeAt(index: number): Promise<void> {
    if (this.mFallbackFilePaths.length > 0) {
      if (index < 0 || index >= this.mFallbackFilePaths.length) {
        this.notifyPageFailed(index, GetText.getString('error_out_of_range'));
        return;
      }
      this.mPump.setCurrent(index);
      let file: fs.File | null = null;
      try {
        file = Contracts.openReadFile(this.mFallbackFilePaths[index]);
        const decoded: Image | null = Image.decodeStream(file, false);
        if (decoded !== null) {
          this.notifyPageSucceed(index, decoded);
        } else {
          this.notifyPageFailed(index, GetText.getString('error_decoding_failed'));
        }
      } catch (e) {
        Utils.throwIfFatal(e);
        this.notifyPageFailed(index, GetText.getString('error_decoding_failed'));
      } finally {
        if (file !== null) {
          try {
            fs.closeSync(file);
          } catch (closeErr) {
            hilog.warn(LOG_DOMAIN, TAG, 'close fallback image failed: %{public}s',
              closeErr instanceof Error ? closeErr.message : String(closeErr));
          }
        }
        this.mPump.setCurrent(NO_REQUEST);
      }
      return;
    }

    const entries: A7ZipArchiveEntry[] = this.mEntries;
    if (index < 0 || index >= entries.length) {
      this.notifyPageFailed(index, GetText.getString('error_out_of_range'));
      return;
    }

    this.mPump.setCurrent(index);
    try {
      const sink: BufferSink = new BufferSink();
      entries[index].extract(sink);
      const bytes: ArrayBuffer = sink.toArrayBuffer();
      if (bytes.byteLength === 0) {
        this.notifyPageFailed(index, GetText.getString('error_decoding_failed'));
        return;
      }
      const source: image.ImageSource = image.createImageSource(bytes);
      try {
        const pixelMap: image.PixelMap = source.createPixelMapSync();
        const decoded: Image | null = Image.decodePixelMap(pixelMap, false);
        if (decoded !== null) {
          this.notifyPageSucceed(index, decoded);
        } else {
          this.notifyPageFailed(index, GetText.getString('error_decoding_failed'));
        }
      } finally {
        source.release();
      }
    } catch (e) {
      Utils.throwIfFatal(e);
      this.notifyPageFailed(index, GetText.getString('error_decoding_failed'));
    } finally {
      this.mPump.setCurrent(NO_REQUEST);
    }
  }

  /** 为 ArkUI Swiper 兜底模式准备单页本地图片文件。 */
  async preparePageFileForSwiper(index: number, dstPath: string): Promise<boolean> {
    await this.waitUntilReady();
    if (this.mStopped) {
      return false;
    }
    if (this.mFallbackFilePaths.length > 0) {
      if (index < 0 || index >= this.mFallbackFilePaths.length) {
        return false;
      }
      let srcFile: fs.File | null = null;
      let dstFile: fs.File | null = null;
      try {
        srcFile = Contracts.openReadFile(this.mFallbackFilePaths[index]);
        dstFile = fs.openSync(dstPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        const buf: ArrayBuffer = new ArrayBuffer(65536);
        let readLen: number = fs.readSync(srcFile.fd, buf);
        while (readLen > 0) {
          fs.writeSync(dstFile.fd, buf, { length: readLen });
          readLen = fs.readSync(srcFile.fd, buf);
        }
        return true;
      } catch (e) {
        hilog.warn(LOG_DOMAIN, TAG, 'copy fallback page %{public}d failed: %{public}s',
          index, e instanceof Error ? e.message : String(e));
        return false;
      } finally {
        if (srcFile !== null) {
          try {
            fs.closeSync(srcFile);
          } catch (closeErr) {
            hilog.warn(LOG_DOMAIN, TAG, 'close swiper src failed: %{public}s',
              closeErr instanceof Error ? closeErr.message : String(closeErr));
          }
        }
        if (dstFile !== null) {
          try {
            fs.closeSync(dstFile);
          } catch (closeErr) {
            hilog.warn(LOG_DOMAIN, TAG, 'close swiper dst failed: %{public}s',
              closeErr instanceof Error ? closeErr.message : String(closeErr));
          }
        }
      }
    }

    if (index < 0 || index >= this.mEntries.length) {
      return false;
    }
    let outFile: fs.File | null = null;
    try {
      const sink: BufferSink = new BufferSink();
      this.mEntries[index].extract(sink);
      const bytes: ArrayBuffer = sink.toArrayBuffer();
      if (bytes.byteLength === 0) {
        return false;
      }
      outFile = fs.openSync(dstPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(outFile.fd, bytes, { length: bytes.byteLength });
      return true;
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'extract swiper page %{public}d failed: %{public}s',
        index, e instanceof Error ? e.message : String(e));
      return false;
    } finally {
      if (outFile !== null) {
        try {
          fs.closeSync(outFile);
        } catch (closeErr) {
          hilog.warn(LOG_DOMAIN, TAG, 'close swiper out failed: %{public}s',
            closeErr instanceof Error ? closeErr.message : String(closeErr));
        }
      }
    }
  }

  // ---------------------------------------------------------------- GalleryProvider2

  /** 上游此处是 `// TODO return Integer.toString(index)`，保持原样。 */
  getImageFilename(index: number): string {
    return `${index}`;
  }

  /** 上游此处是 `// TODO return false`，保持原样（压缩包"另存为"上游未实现）。 */
  saveToFile(index: number, file: UniFile): boolean {
    return false;
  }

  /** 上游此处是 `// TODO return null`，保持原样。 */
  saveToDir(index: number, dir: UniFile, filename: string): UniFile | null {
    return null;
  }
}
