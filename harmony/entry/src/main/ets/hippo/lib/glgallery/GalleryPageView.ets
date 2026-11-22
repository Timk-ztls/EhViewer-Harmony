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

import { Texture } from '../glview/glrenderer/Texture';
import { BasicTexture } from '../glview/glrenderer/BasicTexture';
import { ImageTexture } from '../glview/image/ImageTexture';
import { ImageMovableTextTexture } from '../glview/image/ImageMovableTextTexture';
import { GLImageMovableTextView } from '../glview/image/GLImageMovableTextView';
import { GLView, GLViewLayoutParams, GLViewGravityLayoutParams } from '../glview/view/GLView';
import { Gravity } from '../glview/view/Gravity';
import { GLFrameLayout } from '../glview/widget/GLFrameLayout';
import { GLLinearLayout, GLLinearLayoutParams } from '../glview/widget/GLLinearLayout';
import { GLProgressView } from '../glview/widget/GLProgressView';
import { GLTextureView } from '../glview/widget/GLTextureView';
import { ImageView } from './ImageView';

/**
 * 错误文案绑定能力（**只声明 `GalleryPageView` 实际用到的三个方法**）。
 *
 * 上游签名 `setError(String error, GalleryView galleryView)` 直接依赖 `GalleryView`，
 * 而 `GalleryView` 又依赖 `GalleryPageView`（池化 + `findPageUnder`），形成环。
 * 用这个窄接口打断环：`GalleryView` 实现它，`GalleryPageView` 只依赖接口。
 *
 * 与 `GalleryDetailSceneHost`（native-image）/ `PageImageDownloader`（storage-db）同一手法。
 */
export interface GalleryPageErrorHost {
  /** 把错误文案绑定到视图（内部创建 `StringTexture`）。 */
  bindErrorView(errorView: GLTextureView, error: string): void;
}

/**
 * `com.hippo.lib.glgallery.GalleryPageView` 的 ArkTS 等价实现（**类体落地**）。
 *
 * 一页的内容容器：`ImageView`（图片）+ 竖向 `GLLinearLayout`（页码 / 错误图标 / 进度圈）。
 * `GalleryView` 用 `Pool<GalleryPageView>`（容量 5）复用实例。
 *
 * ## 可见性三态（这套布局的核心，改一个值就翻页抖动）
 * | 状态 | mImage | mInfo |
 * |---|---|---|
 * | 图片就绪 | `VISIBLE` | `GONE` |
 * | 显示信息（加载中 / 错误） | **`INVISIBLE`** | `VISIBLE` |
 *
 * `showInfo()` 用 `INVISIBLE` 而非 `GONE` 是**故意的**：`GONE` 让 `ImageView` 不参与布局，
 * `GalleryPageView` 的测量尺寸会跳变（翻页时页面高度忽大忽小）；`INVISIBLE` 保留占位，
 * "图片有效区域"仍按图片尺寸算。
 *
 * ## `getSuggestedMinimumHeight()` 的反直觉判断
 * ```java
 * if (mImage.getVisibility() == VISIBLE) return 0;
 * else return mMinHeight;
 * ```
 * 理由（上游注释）：**实际图片可能比 `mMinHeight` 小**，此时不该被最小高度撑开；
 * 只有"没图"（信息页）时才用 `mMinHeight` 保证信息面板有地方显示。
 */
export abstract class GalleryPageView extends GLFrameLayout {
  /** 无效页索引（上游 `GalleryPageView.INVALID_INDEX`）。 */
  static readonly INVALID_INDEX: number = -1;

  /** 进度条隐藏（上游 `PROGRESS_GONE`）。 */
  static readonly PROGRESS_GONE: number = -1.0;

  /** 进度不可确定，显示转圈（上游 `PROGRESS_INDETERMINATE`）。 */
  static readonly PROGRESS_INDETERMINATE: number = -2.0;

  private readonly mImage: ImageView;
  private readonly mInfo: GLLinearLayout;
  private readonly mPage: GLImageMovableTextView;
  private readonly mError: GLTextureView;
  private readonly mProgress: GLProgressView;

  /** 与 `GLView` 的私有 `mMinHeight` 重名，改名避让（ArkTS 不允许同名私有成员）。 */
  private readonly mPageMinHeight: number;

  private mIndex: number = GalleryPageView.INVALID_INDEX;

  constructor(pageTextTexture: ImageMovableTextTexture | null, progressColor: number,
    progressBgColor: number, progressSize: number, minHeight: number, infoInterval: number) {
    super();

    // Add image
    this.mImage = new ImageView();
    let glp = new GLViewGravityLayoutParams(GLViewLayoutParams.MATCH_PARENT,
      GLViewLayoutParams.MATCH_PARENT);
    this.addComponent(this.mImage, glp);

    // Add other panel
    this.mInfo = new GLLinearLayout();
    this.mInfo.setOrientation(GLLinearLayout.VERTICAL);
    this.mInfo.setInterval(infoInterval);
    glp = new GLViewGravityLayoutParams(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
    glp.gravity = Gravity.CENTER;
    this.addComponent(this.mInfo, glp);

    // Add page
    this.mPage = new GLImageMovableTextView();
    this.mPage.setTextTexture(pageTextTexture);
    let lp = new GLLinearLayoutParams(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
    lp.gravity = Gravity.CENTER_HORIZONTAL;
    this.mInfo.addComponent(this.mPage, lp);

    // Add error
    this.mError = new GLTextureView();
    lp = new GLLinearLayoutParams(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
    lp.gravity = Gravity.CENTER_HORIZONTAL;
    this.mInfo.addComponent(this.mError, lp);

    // Add progress
    this.mProgress = new GLProgressView();
    this.mProgress.setBgColor(progressBgColor);
    this.mProgress.setColor(progressColor);
    this.mProgress.setMinimumWidth(progressSize);
    this.mProgress.setMinimumHeight(progressSize);
    lp = new GLLinearLayoutParams(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
    lp.gravity = Gravity.CENTER_HORIZONTAL;
    this.mInfo.addComponent(this.mProgress, lp);

    this.mPageMinHeight = minHeight;
  }

  protected getSuggestedMinimumHeight(): number {
    // 图片可见时最小高度为 0（实际图片可能比 mMinHeight 小，不该被撑开）
    if (this.mImage.getVisibility() === GLView.VISIBLE) {
      return 0;
    }
    return this.mPageMinHeight;
  }

  getIndex(): number {
    return this.mIndex;
  }

  setIndex(index: number): void {
    this.mIndex = index;
  }

  showImage(): void {
    this.mImage.setVisibility(GLView.VISIBLE);
    this.mInfo.setVisibility(GLView.GONE);
  }

  showInfo(): void {
    // INVISIBLE（不是 GONE）：保留占位，避免测量尺寸跳变导致翻页抖动
    this.mImage.setVisibility(GLView.INVISIBLE);
    this.mInfo.setVisibility(GLView.VISIBLE);
  }

  private unbindImage(): void {
    const texture: ImageTexture | null = this.mImage.getImageTexture();
    if (texture !== null) {
      this.mImage.setImageTexture(null);
      texture.recycle();
    }
  }

  setImage(imageTexture: ImageTexture | null): void {
    this.unbindImage();
    if (imageTexture !== null) {
      this.mImage.setImageTexture(imageTexture);
    }
  }

  setPage(page: number): void {
    this.mPage.setVisibility(GLView.VISIBLE);
    this.mPage.setText(page.toString());
  }

  hidePage(): void {
    this.mPage.setVisibility(GLView.GONE);
  }

  setProgress(progress: number): void {
    if (progress === GalleryPageView.PROGRESS_GONE) {
      this.mProgress.setVisibility(GLView.GONE);
    } else if (progress === GalleryPageView.PROGRESS_INDETERMINATE) {
      this.mProgress.setVisibility(GLView.VISIBLE);
      this.mProgress.setIndeterminate(true);
    } else {
      this.mProgress.setVisibility(GLView.VISIBLE);
      this.mProgress.setIndeterminate(false);
      this.mProgress.setProgress(progress);
    }
  }

  private unbindError(): void {
    const texture: Texture | null = this.mError.getTexture();
    if (texture !== null) {
      this.mError.setTexture(null);
      if (texture instanceof BasicTexture) {
        (texture as BasicTexture).recycle();
      }
    }
  }

  /**
   * @param error     null 表示无错误（隐藏错误区）
   * @param errorHost 错误文案绑定器（`GalleryView` 实现）
   */
  setError(error: string | null, errorHost: GalleryPageErrorHost | null): void {
    this.unbindError();
    if (error === null) {
      this.mError.setVisibility(GLView.GONE);
    } else {
      this.mError.setVisibility(GLView.VISIBLE);
      if (errorHost !== null) {
        errorHost.bindErrorView(this.mError, error);
      }
    }
  }

  getImageView(): ImageView {
    return this.mImage;
  }

  isLoaded(): boolean {
    return this.mImage.getVisibility() === GLView.VISIBLE;
  }

  isError(): boolean {
    return this.mError.getVisibility() === GLView.VISIBLE;
  }

  isUnderInfo(x: number, y: number): boolean {
    return this.mInfo.bounds().contains(Math.trunc(x), Math.trunc(y));
  }

  /** 诊断：信息面板（页码 / 错误 / 进度）。 */
  getInfoLayout(): GLLinearLayout {
    return this.mInfo;
  }

  /** 诊断：错误视图。 */
  getErrorView(): GLTextureView {
    return this.mError;
  }

  /** 诊断：进度视图。 */
  getProgressView(): GLProgressView {
    return this.mProgress;
  }
}
