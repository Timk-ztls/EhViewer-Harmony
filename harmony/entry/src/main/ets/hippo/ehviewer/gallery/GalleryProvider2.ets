/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/gallery/GalleryProvider2.java（45 行）
 *
 * 作用：EhViewer 三种画廊来源（本地目录 / 在线图库 / 压缩包）的共同基类，在 glgallery 的
 * `GalleryProvider` 之上补两件事：
 *   1) **图片扩展名白名单**（`SUPPORT_IMAGE_EXTENSIONS`，带点、5 个、顺序与上游一致）
 *   2) **起始页**（`getStartPage()` / `putStartPage(page)` —— 上游方法名就是 put，不是 set，保持原样）
 *      以及两个「另存为」抽象方法（保存到已打开文件 / 保存到目录+文件名）
 *
 * 平台对位：
 *   - 基类 `GalleryProvider` 已由 gl-render 落地（`hippo/lib/glgallery/GalleryProvider.ets`），
 *     契约是「请求-通知」模型：子类只实现 `size()/getError()/onRequest/onForceRequest/onCancelRequest`，
 *     通知由基类投递到 GL 线程。本类**不实现**这些，保持 abstract（上游同样不实现）。
 *   - 扩展名白名单在这里**单点定义**（上游home）。下游 `SpiderDen.ets` 与 `A7ZipArchive.ets`
 *     都从这里引用，不再各自留一份字面量（此前为防止阻塞各自留了副本，现已收回）。
 *   - `UniFile` 为 storage-db 自己的统一文件抽象。
 */

import { GalleryProvider } from '../../lib/glgallery/GalleryProvider';
import { UniFile } from '../../unifile/UniFile';

export abstract class GalleryProvider2 extends GalleryProvider {
  /**
   * 支持的图片扩展名（带点，顺序与上游一致）。
   * 注意：判断处一律**先 toLowerCase()** 再比（上游 `StringUtils.endsWith(name.toLowerCase(), ...)`），
   * 大小写混排的文件名（如 `.JPG`）同样能读到。
   */
  static readonly SUPPORT_IMAGE_EXTENSIONS: string[] = [
    '.jpg', // Joint Photographic Experts Group
    '.jpeg',
    '.png', // Portable Network Graphics
    '.gif', // Graphics Interchange Format
    '.webp'
  ];

  /** 起始页（单页/双页模式的阅读起点）；默认 0。 */
  getStartPage(): number {
    return 0;
  }

  /** 对位上游 `putStartPage(int page)`：默认空实现，由子类覆盖。 */
  putStartPage(page: number): void {
  }

  /**
   * 第 index 页的**文件名（不含扩展名）**。
   * 上游注释：`@return without extension`。
   */
  abstract getImageFilename(index: number): string;

  /** 把第 index 页保存到已打开的文件；成功 true。 */
  abstract saveToFile(index: number, file: UniFile): boolean;

  /**
   * 把第 index 页保存成 `dir/filename(.ext)`；成功返回目标 UniFile，失败 null。
   * 上游是 `save(int, UniFile, String)` 与 `save(int, UniFile)` 的重载 ——
   * ArkTS 无方法重载（方案 §5-⑦），故重命名为 `saveToDir` / `saveToFile`。
   */
  abstract saveToDir(index: number, dir: UniFile, filename: string): UniFile | null;

  /** 扩展名是否在白名单内（含大小写归一）。三个子类的文件列举过滤都用它。 */
  static isSupportedImageName(name: string): boolean {
    const lower: string = name.toLowerCase();
    for (const extension of GalleryProvider2.SUPPORT_IMAGE_EXTENSIONS) {
      if (lower.endsWith(extension)) {
        return true;
      }
    }
    return false;
  }
}
