/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/gallery/EhGalleryProvider.java（183 行）
 *
 * 作用：把 `SpiderQueen`（下载/缓存引擎）包装成画廊数据源。它是「阅读器 ↔ 下载器」的桥：
 *   请求 → `SpiderQueen.request(index)` → 返回值决定是"等"、"进度"还是"失败"
 *   反向 ← `OnSpiderListener` 的 8 个回调 → 转成 `GalleryProvider` 的 notify*
 *
 * ── 为什么本文件用 `SpiderQueenLike` 而不是直接吃 `SpiderQueen` ─────────────────
 * `SpiderQueen` 的读取队列/`request`/`save` 属**第 2/3 批**（等 core-runtime 的
 * `Settings.getPreloadImage`/`getMultiThreadDownload`）。按 lead 批准的**契约先行**：
 * 消费方定义最小接口（同 `ConacoTaskLike`/`EhRequestBuilderLike` 的做法），
 * `SpiderQueen` 落地那些方法后 `implements SpiderQueenLike` 即可，**零返工**。
 *
 * 本接口只含本文件真正用到的 9 个方法（上游 EhGalleryProvider 的全部 SpiderQueen 调用）。
 *
 * ── 上游语义要点（逐条对位，别凭印象改）─────────────────────────────────
 * 1) `getImageFilename(index)` = `String.format(Locale.US, "%d-%s-%08d", gid, token, index + 1)`
 *    —— **index + 1**、gid 与 token 都进文件名（与 SpiderDen 的纯序号命名不同，
 *    这是"另存为"时的默认文件名）。
 * 2) `request()` 的返回值是**三态**：`Float` → 进度、`String` → 失败、`null` → 等待中。
 *    ArkTS 无装箱 Object，用 `number | string | null` 表达（`number` 即 Float 语义）。
 * 3) `stop()` 里 `releaseSpiderQueen` 是 **postDelayed 3000ms**（上游注释：Activity recreate 时可能重入），
 *    不是立即释放 —— 立即释放会让旋转屏幕后正在解码的页面被打断。
 * 4) `onPageDownload` 只在 `contentLength > 0` 时算百分比（未知长度不显示假的 0%）。
 */

import { GalleryProvider } from '../../lib/glgallery/GalleryProvider';
import { GalleryProvider2 } from './GalleryProvider2';
import { GalleryInfo } from '../client/data/GalleryInfo';
import { UniFile } from '../../unifile/UniFile';
import { Utils } from '../../unifile/Utils';
import { SimpleHandler } from '../../lib/yorozuya/SimpleHandler';
import { Image } from '../../lib/image/Image';
import { OnSpiderListener, PageRequestResult, SpiderQueenLike } from '../spider/SpiderQueen';

export { SpiderQueenLike };

const TAG: string = 'EhGalleryProvider';

/** 取 queen 的工厂（默认实现等 SpiderQueen 第 2/3 批落地后接 `SpiderQueen.obtainSpiderQueen`）。 */
export type SpiderQueenFactory = (info: GalleryInfo, mode: number) => SpiderQueenLike;

/** 与 `SpiderQueen.MODE_READ` 对齐（这里重复一份常量只为不让 gallery 层反向依赖 spider 的内部常量）。 */
const MODE_READ: number = 0;

export class EhGalleryProvider extends GalleryProvider2 implements OnSpiderListener {
  private static queenFactory: SpiderQueenFactory | null = null;
  private static queenReleaser: ((queen: SpiderQueenLike) => void) | null = null;

  /**
   * 由 SpiderQueen 第 2/3 批/上层注入。
   * 未注入时 `start()` **抛错**（不是静默不加载 —— 那会让阅读器永远转圈）。
   */
  static setSpiderQueenFactory(factory: SpiderQueenFactory | null): void {
    EhGalleryProvider.queenFactory = factory;
  }

  private readonly mGalleryInfo: GalleryInfo;
  private mSpiderQueen: SpiderQueenLike | null = null;

  constructor(galleryInfo: GalleryInfo) {
    super();
    this.mGalleryInfo = galleryInfo;
  }

  // ---------------------------------------------------------------- 生命周期

  start(): void {
    super.start();
    const factory: SpiderQueenFactory | null = EhGalleryProvider.queenFactory;
    if (factory === null) {
      throw new Error(
        `[${TAG}] TODO(spider): SpiderQueenFactory 未注入` +
        '（SpiderQueen 第 2/3 批的 request/save 落地后由上层注入 obtainSpiderQueen）');
    }
    this.mSpiderQueen = factory(this.mGalleryInfo, MODE_READ);
    this.mSpiderQueen.addOnSpiderListener(this);
  }

  stop(): void {
    super.stop();
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    if (queen !== null) {
      queen.removeOnSpiderListener(this);
      // 上游注释：「Activity recreate may called, so wait 3000s」
      // 立即释放会让转屏后正在解码的页面被打断，故延迟 3s。
      SimpleHandler.getInstance().postDelayed((): void => {
        EhGalleryProvider.releaseQueen(queen);
      }, 3000);
      this.mSpiderQueen = null;
    }
  }

  /** 供 postDelayed 的闭包调用（上游是 `ReleaseTask` 内部类，ArkTS 用静态方法等价）。 */
  private static releaseQueen(queen: SpiderQueenLike): void {
    const releaser: ((q: SpiderQueenLike) => void) | null = EhGalleryProvider.queenReleaser;
    if (releaser !== null) {
      releaser(queen);
    }
  }


  /** 与工厂配套：延迟释放时的实际释放动作（默认 `SpiderQueen.releaseSpiderQueen(q, MODE_READ)`）。 */
  static setSpiderQueenReleaser(releaser: ((queen: SpiderQueenLike) => void) | null): void {
    EhGalleryProvider.queenReleaser = releaser;
  }

  // ---------------------------------------------------------------- GalleryProvider2

  getStartPage(): number {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    return queen !== null ? queen.getStartPage() : super.getStartPage();
  }

  putStartPage(page: number): void {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    if (queen !== null) {
      queen.putStartPage(page);
    }
  }

  /** 对位上游 `"%d-%s-%08d"`（gid-token-序号），**index + 1**。 */
  getImageFilename(index: number): string {
    let seq: string = `${index + 1}`;
    while (seq.length < 8) {
      seq = `0${seq}`;
    }
    return `${this.mGalleryInfo.gid}-${this.mGalleryInfo.token}-${seq}`;
  }

  saveToFile(index: number, file: UniFile): boolean {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    return queen !== null ? queen.saveToFile(index, file) : false;
  }

  saveToDir(index: number, dir: UniFile, filename: string): UniFile | null {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    return queen !== null ? queen.saveToDir(index, dir, filename) : null;
  }

  size(): number {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    return queen !== null ? queen.size() : GalleryProvider.STATE_ERROR;
  }

  getError(): string {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    // 上游此处是 `return "Error"; // TODO` —— 保持原样，不发明文案
    return queen !== null ? queen.getError() : 'Error';
  }

  // ---------------------------------------------------------------- 请求

  protected onRequest(index: number): void {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    if (queen === null) {
      return;
    }
    this.dispatchResult(index, queen.request(index));
  }

  protected onForceRequest(index: number): void {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    if (queen === null) {
      return;
    }
    this.dispatchResult(index, queen.forceRequest(index));
  }

  /** 三态分派（对位上游的 `instanceof Float / String / null` 判断）。 */
  private dispatchResult(index: number, result: PageRequestResult): void {
    if (typeof result === 'number') {
      this.notifyPagePercent(index, result);
    } else if (typeof result === 'string') {
      this.notifyPageFailed(index, result);
    } else {
      this.notifyPageWait(index);
    }
  }

  protected onCancelRequest(index: number): void {
    const queen: SpiderQueenLike | null = this.mSpiderQueen;
    if (queen !== null) {
      queen.cancelRequest(index);
    }
  }

  // ---------------------------------------------------------------- OnSpiderListener（8 个，逐个转成 notify*）

  onGetPages(pages: number): void {
    this.notifyDataChanged();
  }

  onGet509(index: number): void {
    // 上游此处就是空实现（`// TODO`），保持原样
  }

  onPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void {
    // 上游：只在长度已知（> 0）时算百分比，避免显示假的 0%
    if (contentLength > 0) {
      this.notifyPagePercent(index, receivedSize / contentLength);
    }
  }

  onPageSuccess(index: number, finished: number, downloaded: number, total: number): void {
    this.notifyDataChangedAt(index);
  }

  onPageFailure(index: number, error: string, finished: number, downloaded: number, total: number): void {
    this.notifyPageFailed(index, error);
  }

  onFinish(finished: number, downloaded: number, total: number): void {
    // 上游空实现，保持原样
  }

  onGetImageSuccess(index: number, image: Image): void {
    this.notifyPageSucceed(index, image);
  }

  onGetImageFailure(index: number, error: string): void {
    this.notifyPageFailed(index, error);
  }

  /** 供测试/排查：当前是否已持有 queen。 */
  hasSpiderQueen(): boolean {
    return this.mSpiderQueen !== null;
  }
}
