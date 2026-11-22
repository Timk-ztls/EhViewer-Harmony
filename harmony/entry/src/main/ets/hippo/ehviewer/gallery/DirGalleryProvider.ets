/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/gallery/DirGalleryProvider.java（225 行）
 *
 * 作用：把**本地目录**（含 SAF 目录、SD 卡目录）当成画廊数据源。上游流程三段：
 *   1. `run()`（后台线程）：列举目录里所有支持的图片 → 自然序排序 → 置 `mSize` → `notifyDataChanged()`
 *   2. 请求队列：`onRequest` 入栈 + `notifyPageWait`；后台线程 `pop` 出来解码
 *   3. 解码：`Image.decode(fd, false)` → 成功 `notifyPageSucceed` / 失败 `notifyPageFailed`
 *
 * ── 与上游的**唯一必要差异：并发模型** ────────────────────────────────────────
 * 上游 `extends Thread` 起一个后台线程，用 `wait()/notify()` 做阻塞队列。
 * 鸿蒙侧 core-runtime 的 `PriorityThread.start()` 是**同步执行** `run()`（无真实线程），
 * 直接照搬会在调用线程上跑整个解码循环 → 卡 UI，属静默行为降级。
 *
 * 本实现改为**单线程异步泵**：
 *   - 不阻塞：`onRequest` 只入队并触发 `pump()`，`pump()` 是 async 的，`await` 之间会让出事件循环
 *   - 语义等价：仍然是「一个消费者、按请求先后（后进先出，与上游 Stack 一致）逐页解码」
 *   - 升级路径：若要真正并行解码，需要用 `taskpool` + 可序列化状态（SharedArrayBuffer），
 *     但 `Image`/`PixelMap` 不可跨线程传递，收益有限 —— 上游也只有一个解码线程，故不做。
 * 这条差异已按 lead 要求记录，后续在 MR 里同步。
 *
 * ── 其余平台改写 ─────────────────────────────────────────────────────────────
 *   - `Image.decode(FileInputStream, false)` → `Image.decodeStream(fs.File, false)`：
 *     目录源一定是本地路径，用 `Contracts.toPath()` 拿路径再 `fs.openSync` 取 fd
 *   - `GetText.getString(R.string.error_xxx)` → `GetText.getString('error_xxx')`
 *   - `save(int, UniFile)` / `save(int, UniFile, String)` → `saveToFile` / `saveToDir`（ArkTS 无重载）
 *   - 文件名过滤：上游 `StringUtils.endsWith(name.toLowerCase(), SUPPORT_IMAGE_EXTENSIONS)`
 *     → `GalleryProvider2.isSupportedImageName(name)`（白名单单点在 GalleryProvider2）
 */

import fs from '@ohos.file.fs';
import { GalleryProvider } from '../../lib/glgallery/GalleryProvider';
import { GalleryPageView } from '../../lib/glgallery/GalleryPageView';
import { GalleryProvider2 } from './GalleryProvider2';
import { RequestPump, NO_REQUEST } from './RequestPump';
import { Image } from '../../lib/image/Image';
import { UniFile } from '../../unifile/UniFile';
import { FilenameFilter } from '../../unifile/FilenameFilter';
import { Contracts, InputStream, OutputStream } from '../../unifile/Contracts';
import { IOUtils } from '../../lib/yorozuya/IOUtils';
import { FileUtils } from '../../lib/yorozuya/FileUtils';
import { Utils } from '../../unifile/Utils';
import { GetText } from '../GetText';
import { NaturalComparator } from '../../util/NaturalComparator';

const TAG: string = 'DirGalleryProvider';

/** 只接受支持的图片扩展名（大小写不敏感）。 */
class ImageFilenameFilter implements FilenameFilter {
  accept(dir: UniFile, filename: string): boolean {
    return GalleryProvider2.isSupportedImageName(filename);
  }
}

export class DirGalleryProvider extends GalleryProvider2 {
  private readonly mDir: UniFile;
  /**
   * 请求栈 + 单消费者泵（D-024）。
   * 上游是 `Stack<Integer> mRequests` + `AtomicInteger mDecodingIndex` + 一个 `run()` 线程；
   * 这里把那段抽成 `RequestPump`（可单测，ArchiveGalleryProvider 同构复用）。
   */
  private mPump: RequestPump = new RequestPump();
  private mFileList: UniFile[] | null = null;
  private mSize: number = GalleryProvider.STATE_WAIT;
  private mError: string = '';

  /** 已扫描过目录（避免 start 重复扫描）。 */
  private mScanned: boolean = false; // 不能用 mStarted：GalleryProvider 基类已有同名 private 字段（会造成 incorrectly extends）

  constructor(dir: UniFile) {
    super();
    this.mDir = dir;
    // 运行时自检：RequestPump 的哨兵必须与 glgallery 的 INVALID_INDEX 一致（-1），
    // 否则"当前无请求"的判断会错位。放这里而不是 RequestPump 里，是为了让 RequestPump 保持零依赖可测。
    if (NO_REQUEST !== GalleryPageView.INVALID_INDEX) {
      throw new Error(`[${TAG}] RequestPump.NO_REQUEST(${NO_REQUEST}) != GalleryPageView.INVALID_INDEX(${GalleryPageView.INVALID_INDEX})`);
    }
  }

  // ---------------------------------------------------------------- 生命周期

  start(): void {
    super.start();
    this.mPump.reset();
    if (!this.mScanned) {
      this.mScanned = true;
      // 不 await：扫描是大目录 IO，交给事件循环（上游是后台线程）
      this.scanAndPump();
    }
  }

  stop(): void {
    super.stop();
    this.mPump.stop();
    this.mFileList = null;
  }

  size(): number {
    return this.mSize;
  }

  getError(): string {
    return this.mError;
  }

  // ---------------------------------------------------------------- 请求

  protected onRequest(index: number): void {
    // 去重 / 与正在解码的页相同时忽略 —— 语义在 RequestPump.push 里（与上游入栈条件逐条对应）
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

  // ---------------------------------------------------------------- 扫描 + 解码泵

  /**
   * 对位上游 `run()` 的前半段：列举 → 自然序排序 → 置 size → notifyDataChanged。
   * 失败（不是目录 / 读不了）时 `mSize = STATE_ERROR`，错误文案走 GetText（与上游一致）。
   */
  private async scanAndPump(): Promise<void> {
    const filter: ImageFilenameFilter = new ImageFilenameFilter();
    let files: UniFile[] | null = null;
    try {
      files = this.mDir.listFilesFiltered(filter);
    } catch (e) {
      Utils.throwIfFatal(e);
      files = null;
    }

    if (files === null) {
      this.mSize = GalleryProvider.STATE_ERROR;
      this.mError = GetText.getString('error_not_folder_path');
      this.notifyDataChanged();
      return;
    }

    // 自然序排序（a1, a2, a10 而不是 a1, a10, a2）
    const comparator: NaturalComparator = new NaturalComparator();
    files.sort((a: UniFile, b: UniFile): number => comparator.compare(a.getName(), b.getName()));

    this.mFileList = files;
    this.mSize = files.length;
    this.notifyDataChanged();

    await this.pump();
  }

  /** 触发泵（不 await：`onRequest` 是同步接口，泵在的事件循环里推进）。 */
  private pump(): void {
    this.mPump.drain((index: number): Promise<void> => this.decodeAt(index));
  }

  private async decodeAt(index: number): Promise<void> {
    const files: UniFile[] | null = this.mFileList;
    if (files === null) {
      return;
    }
    if (index < 0 || index >= files.length) {
      this.notifyPageFailed(index, GetText.getString('error_out_of_range'));
      return;
    }

    this.mPump.setCurrent(index);
    let fd: fs.File | null = null;
    try {
      // 优先兼容 URI 直开及本地路径
      fd = Contracts.openReadFile(files[index].getUri());
      const image: Image | null = Image.decodeStream(fd, false);
      this.mPump.setCurrent(NO_REQUEST);
      if (image !== null) {
        this.notifyPageSucceed(index, image);
      } else {
        this.notifyPageFailed(index, GetText.getString('error_decoding_failed'));
      }
    } catch (e) {
      this.mPump.setCurrent(NO_REQUEST);
      Utils.throwIfFatal(e);
      this.notifyPageFailed(index, GetText.getString('error_reading_failed'));
    } finally {
      if (fd !== null) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          Utils.throwIfFatal(e);
        }
      }
      this.mPump.setCurrent(NO_REQUEST);
    }
  }

  // ---------------------------------------------------------------- GalleryProvider2

  /** 上游此处也是 TODO（`return Integer.toString(index)`），保持原样。 */
  getImageFilename(index: number): string {
    return `${index}`;
  }

  /** 供 Swiper 回退模式读取自然序排序后的页 URI/路径列表。 */
  getPageUri(index: number): string | null {
    const files: UniFile[] | null = this.mFileList;
    if (files === null || index < 0 || index >= files.length) {
      return null;
    }
    return files[index].getUri();
  }

  /** 对位 `save(int, UniFile)`：把第 index 页整段拷到已打开的文件。 */
  saveToFile(index: number, file: UniFile): boolean {
    const files: UniFile[] | null = this.mFileList;
    if (files === null || index < 0 || index >= files.length) {
      return false;
    }
    let input: InputStream | null = null;
    let output: OutputStream | null = null;
    try {
      input = files[index].openInputStream();
      output = file.openOutputStream();
      if (input === null || output === null) {
        return false;
      }
      // 逐块拷贝（两端都是 unifile 名义类型，直接手写循环，不跨 streampipe 契约）
      const buf: ArrayBuffer = new ArrayBuffer(IOUtils.DEFAULT_BUFFER_SIZE);
      while (true) {
        const n: number = input.readBuffer(buf);
        if (n <= 0) {
          break;
        }
        output.writeBytes(buf, 0, n);
      }
      output.flush();
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    } finally {
      Utils.closeQuietly(input);
      Utils.closeQuietly(output);
    }
  }

  /** 对位 `save(int, UniFile dir, String filename)`：保留原扩展名。 */
  saveToDir(index: number, dir: UniFile, filename: string): UniFile | null {
    const files: UniFile[] | null = this.mFileList;
    if (files === null || index < 0 || index >= files.length) {
      return null;
    }
    const src: UniFile = files[index];
    // 上游：FileUtils.getExtensionFromFilename(src.getName()) —— 返回**不含点**的扩展名
    const extension: string | null = FileUtils.getExtensionFromFilename(src.getName());
    const dst: UniFile | null = dir.subFile(extension !== null ? `${filename}.${extension}` : filename);
    if (dst === null) {
      return null;
    }
    let input: InputStream | null = null;
    let output: OutputStream | null = null;
    try {
      input = src.openInputStream();
      output = dst.openOutputStream();
      if (input === null || output === null) {
        return null;
      }
      const buf: ArrayBuffer = new ArrayBuffer(IOUtils.DEFAULT_BUFFER_SIZE);
      while (true) {
        const n: number = input.readBuffer(buf);
        if (n <= 0) {
          break;
        }
        output.writeBytes(buf, 0, n);
      }
      output.flush();
      return dst;
    } catch (e) {
      Utils.throwIfFatal(e);
      return null;
    } finally {
      Utils.closeQuietly(input);
      Utils.closeQuietly(output);
    }
  }
}
