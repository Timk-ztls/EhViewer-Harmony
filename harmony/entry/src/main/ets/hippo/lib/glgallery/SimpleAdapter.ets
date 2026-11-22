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

import { GLRootView } from '../glview/view/GLRootView';
import { ImageWrapper } from '../glview/image/ImageWrapper';
import { ImageTexture, ImageTextureUploader } from '../glview/image/ImageTexture';
import { GalleryProvider, GalleryListener } from './GalleryProvider';
import { GalleryPageView } from './GalleryPageView';
import { GalleryAdapter, GalleryView } from './GalleryView';

/**
 * `SimpleAdapter` 需要的"画廊视图"能力（**窄接口，只 4 个方法**）。
 *
 * 上游 `SimpleAdapter extends GalleryView.Adapter`，而 `GalleryView`(1042) 归 net-parse。
 * `GalleryView.Adapter` 本身我在契约骨架里已落（`GalleryAdapter`），但 `findPageByIndex` /
 * `onDataChanged` 是 `GalleryView` 上的方法 —— 用这个窄接口把它们隔离，
 * `GalleryView` 落地后 `implements GalleryAdapterHost` 即接入（`GalleryView` 已有同名方法）。
 */
export interface GalleryAdapterHost {
  /** 等价 `GalleryView.findPageByIndex(int)`。 */
  findPageByIndex(index: number): GalleryPageView | null;

  /** 等价 `GalleryView.onDataChanged()`。 */
  onDataChanged(): void;
}

/**
 * `com.hippo.lib.glgallery.SimpleAdapter` 的 ArkTS 等价实现。
 *
 * `GalleryProvider`（数据）与 `GalleryPageView`（视图）之间的桥：
 * 绑定页时向 provider 发起请求，provider 回调里把"等待/进度/成功/失败"翻译成页面状态。
 *
 * ## 生命周期要点（容易漏的两处）
 * 1. `onBind` 里**先 `request(index)` 再 `showInfo()`**：顺序反了会在请求已经同步回调的
 *    极端情况下被 `showInfo` 覆盖掉"已成功"状态（上游顺序如此，照搬）
 * 2. `onUnbind` 必须 `cancelRequest(index)`：否则翻过去的页会继续下载，占带宽与内存
 *
 * ## `onPageSucceed` 的 `image.obtain()` 失败分支
 * ```java
 * if (image.obtain()) { ... } else { mProvider.request(index); }   // 图已被回收 → 重新请求
 * ```
 * 这是**有意为之的重试**：图片在请求完成到绑定之间可能被别的页回收掉。
 * 上游留了 `// TODO request loop ?`（担心无限重试），本实现保留同样行为与注释 ——
 * 改成"不重试"会让这一页永久空白；改成"带次数上限"是**行为变更**，不在 1:1 范围内。
 *
 * ## 平台差异
 * | 上游 | 本实现 |
 * |---|---|
 * | `new ImageTexture.Uploader(glRootView)` | `new ImageTextureUploader(glRootView)`（`GLRootView implements GLRoot`） |
 * | `mGalleryView.findPageByIndex(index)` | `GalleryAdapterHost` 窄接口（`GalleryView` 落地后 `implements`） |
 * | `mGalleryView.onDataChanged()` | 同上（`Adapter.onDataChanged()` 的实现转给它） |
 */
export class SimpleAdapter extends GalleryAdapter implements GalleryListener {
  private readonly mProvider: GalleryProvider;
  private readonly mUploader: ImageTextureUploader;
  private mShowIndex: boolean = true;

  constructor(glRootView: GLRootView, provider: GalleryProvider) {
    super();
    this.mProvider = provider;
    this.mUploader = new ImageTextureUploader(glRootView);
  }

  /** 清空待上传队列（视图销毁时调用）。 */
  clearUploader(): void {
    this.mUploader.clear();
  }

  setShowIndex(show: boolean): void {
    this.mShowIndex = show;
  }

  getShowIndex(): boolean {
    return this.mShowIndex;
  }

  // ==========================================================================
  // GalleryAdapter
  // ==========================================================================

  onBind(view: GalleryPageView, index: number): void {
    this.mProvider.request(index);
    view.showInfo();
    view.setImage(null);
    if (this.mShowIndex) {
      view.setPage(index + 1);
    } else {
      view.hidePage();
    }
    view.setProgress(GalleryPageView.PROGRESS_INDETERMINATE);
    view.setError(null, null);
  }

  onUnbind(view: GalleryPageView, index: number): void {
    this.mProvider.cancelRequest(index);
    view.setImage(null);
    view.setError(null, null);
  }

  getError(): string | null {
    return this.mProvider.getError();
  }

  size(): number {
    return this.mProvider.size();
  }

  /** 上游 `onDataChanged()` 覆写：转给 `GalleryView`。 */
  onDataChanged(): void {
    const host = this.adapterHost();
    if (host !== null) {
      host.onDataChanged();
    }
  }

  // ==========================================================================
  // GalleryProvider.Listener
  // ==========================================================================

  onPageWait(index: number): void {
    const page = this.findPageByIndex(index);
    if (page !== null) {
      page.showInfo();
      page.setImage(null);
      if (this.mShowIndex) {
        page.setPage(index + 1);
      } else {
        page.hidePage();
      }
      page.setProgress(GalleryPageView.PROGRESS_INDETERMINATE);
      page.setError(null, null);
    }
  }

  onPagePercent(index: number, percent: number): void {
    const page = this.findPageByIndex(index);
    if (page !== null) {
      page.showInfo();
      page.setImage(null);
      if (this.mShowIndex) {
        page.setPage(index + 1);
      } else {
        page.hidePage();
      }
      page.setProgress(percent);
      page.setError(null, null);
    }
  }

  onPageSucceed(index: number, image: ImageWrapper): void {
    const page = this.findPageByIndex(index);
    if (page === null) {
      return;
    }

    if (image.obtain()) {
      const imageTexture = new ImageTexture(image);
      this.mUploader.addTexture(imageTexture);
      page.showImage();
      page.setImage(imageTexture);
      if (this.mShowIndex) {
        page.setPage(index + 1);
      } else {
        page.hidePage();
      }
      page.setProgress(GalleryPageView.PROGRESS_GONE);
      page.setError(null, null);
    } else {
      // 图在"请求完成 → 绑定"之间被回收了：重新请求。
      // 上游留了 `// TODO request loop ?`（担心无限重试），这里保留同样行为与同样的疑虑 ——
      // 不重试会让该页永久空白；加次数上限属行为变更，不在 1:1 范围。
      this.mProvider.request(index);
    }
  }

  onPageFailed(index: number, error: string): void {
    const page = this.findPageByIndex(index);
    if (page !== null) {
      page.showInfo();
      page.setImage(null);
      if (this.mShowIndex) {
        page.setPage(index + 1);
      } else {
        page.hidePage();
      }
      page.setProgress(GalleryPageView.PROGRESS_GONE);
      page.setError(error, this.mGalleryView === null ? null : this.mGalleryView);
    }
  }

  onDataChangedAt(index: number): void {
    const page = this.findPageByIndex(index);
    if (page !== null) {
      // 该页数据变了 → 重新请求
      this.mProvider.request(index);
    }
  }

  // ==========================================================================
  // 宿主查找
  // ==========================================================================

  /**
   * `GalleryView` 同时实现了 `GalleryAdapterHost` 与 `GalleryPageErrorHost`。
   * `GalleryAdapter.mGalleryView` 的类型是 `GalleryView | null`，这里按需要收窄。
   */
  private adapterHost(): GalleryAdapterHost | null {
    const view = this.mGalleryView;
    if (view === null) {
      return null;
    }
    return view as Object as GalleryAdapterHost;
  }

  private findPageByIndex(index: number): GalleryPageView | null {
    const view = this.mGalleryView;
    if (view === null) {
      return null;
    }
    return view.findPageByIndex(index);
  }

  /** 诊断：provider。 */
  getProvider(): GalleryProvider {
    return this.mProvider;
  }

  /** 诊断：上传队列。 */
  getUploader(): ImageTextureUploader {
    return this.mUploader;
  }
}
