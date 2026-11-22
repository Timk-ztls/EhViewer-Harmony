/*
 * Copyright 2016 Hippo Seven
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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DataContainer } from '../../../../../conaco/DataContainer';
import { ProgressNotifier } from '../../../../../conaco/ProgressNotifier';
import { DownloadInfo } from '../../../../dao/DownloadInfo';
import { SpiderDen } from '../../../../spider/SpiderDen';
import { UniFileInputStreamPipe } from '../../../../../io/UniFileInputStreamPipe';
import { InputStreamPipe } from '../../../../../streampipe/InputStreamPipe';
import { IOUtils, InputStreamLike, Closable } from '../../../../../lib/yorozuya/IOUtils';
import { UniFile } from '../../../../../unifile/UniFile';
import { OutputStream } from '../../../../../unifile/Contracts';

const TAG = 'ThumbDataContainer';
const DOMAIN = 0x0000;

/**
 * `com.hippo.ehviewer.ui.scene.download.part.ThumbDataContainer` 的 ArkTS 等价实现。
 *
 * 下载缩略图的数据容器：把缩略图字节存进**画廊下载目录**下的 `.thumb` 文件，
 * 供 `Conaco` 的缓存链当持久层用。
 *
 * ## ⚠️ 平台差异：目录解析变成**异步**，必须先解析再构造（登记 D-055）
 * 上游 `SpiderDen.getGalleryDownloadDir(mInfo)` 是**同步**的（`UniFile` 在 Android 上是同步文件 API），
 * 所以 `ensureFile()` 可以惰性调用。鸿蒙侧
 * `SpiderDen.getGalleryDownloadDir(info)` 返回 `Promise<UniFile | null>`（要走数据库 + 文件系统异步 API），
 * 而 `DataContainer.isEnabled(): boolean` 是**同步接口** —— 没法在 `isEnabled()` 里 `await`。
 *
 * 因此改成：
 * ```ts
 * const container = await ThumbDataContainer.create(info);   // 先异步解析目录
 * // 之后 isEnabled()/save()/get()/remove() 全部同步，语义与上游一致
 * ```
 * `create()` 内部一次 `await`；若目录不可用，`mDir` 保持 null，后续三条路径各自安全返回
 * （**不抛异常**），与上游惰性解析的失败行为等价。
 *
 * 直接 `new ThumbDataContainer(info, dir)` 也可以（单测 / 目录已知的场景）；
 * 传 `null` 时 `isEnabled()` 返回 false 并打一条 warn —— **不会**假装成功。
 *
 * ## 文件名 `.thumb` 与惰性建文件
 * 上游在 `ensureFile()` 里 `findFile('.thumb') ?: createFile('.thumb')`；这里保留，
 * 但查找/创建都在**已解析的目录**上同步进行。
 */
export class ThumbDataContainer implements DataContainer {
  private readonly mInfo: DownloadInfo;
  private readonly mDir: UniFile | null;
  private mFile: UniFile | null = null;

  /**
   * @param dir 画廊下载目录（已解析）。null 表示目录不可用，所有操作安全失败。
   *            生产代码请用 `await ThumbDataContainer.create(info)`。
   */
  constructor(info: DownloadInfo, dir: UniFile | null) {
    this.mInfo = info;
    this.mDir = dir;
  }

  /**
   * 异步解析下载目录后再构造（**生产路径**）。
   * @returns 目录不可用时仍返回实例（`isEnabled()` 为 false），与上游"惰性失败"等价
   */
  static async create(info: DownloadInfo): Promise<ThumbDataContainer> {
    let dir: UniFile | null = null;
    try {
      dir = await SpiderDen.getGalleryDownloadDir(info);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getGalleryDownloadDir failed: %{public}s', JSON.stringify(err));
      dir = null;
    }
    return new ThumbDataContainer(info, dir);
  }

  /** 惰性定位 `.thumb`（目录不可用时返回 null，不抛错）。 */
  private ensureFile(): UniFile | null {
    if (this.mFile !== null) {
      return this.mFile;
    }
    const dir = this.mDir;
    if (dir === null || !dir.isDirectory()) {
      return null;
    }
    let file = dir.findFile('.thumb');
    if (file === null) {
      file = dir.createFile('.thumb');
    }
    this.mFile = file;
    return file;
  }

  isEnabled(): boolean {
    const file = this.ensureFile();
    if (file === null && this.mDir === null) {
      hilog.warn(DOMAIN, TAG, 'isEnabled: download dir not resolved '
        + '(use await ThumbDataContainer.create(info))');
    }
    return file !== null;
  }

  /** 上游是空实现（缩略图容器不关心重定向）。 */
  onUrlMoved(requestUrl: string, responseUrl: string): void {
  }

  /**
   * 把 `is` 的字节写入 `.thumb`。
   * @return 成功 true；文件不可用 / IO 失败 false（**从不抛错**，与上游一致）
   */
  save(is: InputStreamLike, length: number, mediaType: string | null,
    notify: ProgressNotifier | null): boolean {
    const file = this.ensureFile();
    if (file === null) {
      return false;
    }

    let os: OutputStream | null = null;
    try {
      os = file.openOutputStream();
      // 不复用 `IOUtils.copy`：它面向 `OutputStreamLike`（write(buffer, offset, length)），
      // 而 unifile 的 `OutputStream` 只有 write(buffer)，ArkTS 禁止结构类型互转。
      // 循环语义与 IOUtils.copy 一致（读到 EOF 为止），缓冲区大小取 IOUtils 的默认值。
      const buffer: ArrayBuffer = new ArrayBuffer(IOUtils.DEFAULT_BUFFER_SIZE);
      let n: number;
      while ((n = is.read(buffer)) > 0) {
        os.write(buffer.slice(0, n));
      }
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'save failed: %{public}s', JSON.stringify(err));
      return false;
    } finally {
      IOUtils.closeQuietly(os as Closable | null);
    }
  }

  get(): InputStreamPipe | null {
    const file = this.ensureFile();
    if (file !== null) {
      return new UniFileInputStreamPipe(file);
    }
    return null;
  }

  /** 删除缩略图。上游**不**清文件字段：再 `save()` 会经 `createFile` 重建。 */
  remove(): void {
    const file = this.ensureFile();
    if (file !== null) {
      file.delete();
    }
  }

  /** 诊断/单测：当前解析到的文件（null 表示目录或文件不可用）。 */
  getFile(): UniFile | null {
    return this.ensureFile();
  }

  /** 诊断/单测：构造时注入的目录。 */
  getDir(): UniFile | null {
    return this.mDir;
  }

  /** 诊断/单测：关联的下载信息。 */
  getInfo(): DownloadInfo {
    return this.mInfo;
  }
}
