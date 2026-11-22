/*
 * Copyright (C) 2010 The Android Open Source Project
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

import { Image } from '../../image/Image';
import { Rect } from '../util/Rect';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ImageWrapper';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.image.ImageWrapper` 的 ArkTS 等价实现。
 *
 * 用途：给一张 `Image` 套一层"裁剪区 + 引用计数"的外壳，支持同一张图被多处使用
 * （画廊同页多列、缩略图与全图共用缓存），引用归零时自动回收底层图。
 *
 * ## 关键行为（逐条对齐，别"优化"）
 * - `mCut` 初始为整图；`setCutRect` 会把越界区域 clamp 到图内，
 *   **若 clamp 后为空则回退成整图**（上游用 `Log.e` 记录后重置，因为空裁剪区行为未定义）
 * - `obtain()` / `release()` 是引用计数：`release()` 减到 <= 0 才真正 `image.recycle()`
 * - `getWidth()/getHeight()` 返回的是**裁剪后的尺寸**，不是原图尺寸
 * - `texImage()` 的偏移量会**加上裁剪区左上角**再传给 `Image.texImage()`
 *   —— 这是分块上传的关键，漏加就会把整图左上角的内容贴到目标块上
 *
 * ## ArkTS 差异
 * - `synchronized` 不可用：ArkTS 单线程模型（UI 线程 + TaskPool 各自独立 VM），
 *   渲染与通知都在同一 VM 内，因此去掉同步块；状态机语义不变
 * - `Image` 的引用计数方法在 storage-db 的 port 里保留了 `obtain()/release()`，
 *   本类仍然自己做一份计数（上游如此），不依赖底层是否计数
 */
export class ImageWrapper {
  private readonly mImage: Image;
  private readonly mCut: Rect;
  private mReferences: number = 0;

  /**
   * @param image 传入前不应处于 obtained/recycled 状态（上游契约）
   */
  constructor(image: Image) {
    this.mImage = image;
    this.mCut = new Rect(0, 0, image.getWidth(), image.getHeight());
  }

  /** 裁剪到指定区域；越界 clamp，clamp 后为空则回退整图。 */
  setCutRect(left: number, top: number, right: number, bottom: number): void {
    this.mCut.left = Math.max(0, left);
    this.mCut.top = Math.max(0, top);
    this.mCut.right = Math.min(this.mImage.getWidth(), right);
    this.mCut.bottom = Math.min(this.mImage.getHeight(), bottom);

    if (this.mCut.isEmpty()) {
      hilog.error(DOMAIN, TAG, 'Cut rect is empty');
      this.mCut.set(0, 0, this.mImage.getWidth(), this.mImage.getHeight());
    }
  }

  /**
   * 按百分比裁剪，区间 `[0.0, 1.0]`。
   * 注意上游用 `getWidth()/getHeight()`（**裁剪后**尺寸）乘百分比，不是原图尺寸；
   * 连续调用会相对当前裁剪区累乘，这是上游既有行为，保持一致。
   */
  setCutPercent(left: number, top: number, right: number, bottom: number): void {
    this.setCutRect(
      Math.trunc(this.getWidth() * left),
      Math.trunc(this.getHeight() * top),
      Math.trunc(this.getWidth() * right),
      Math.trunc(this.getHeight() * bottom)
    );
  }

  /** 引用 +1；底层图已回收则返回 false（上游用于缓存 put 前的存活检查）。 */
  obtain(): boolean {
    if (this.mImage.isRecycled()) {
      return false;
    }
    this.mReferences++;
    return true;
  }

  /** 引用 -1；归零且底层图未回收时真正 recycle。 */
  release(): void {
    this.mReferences--;
    if (this.mReferences <= 0 && !this.mImage.isRecycled()) {
      this.mImage.recycle();
    }
  }

  isImageRecycled(): boolean {
    return this.mImage.isRecycled();
  }

  getAnimated(): boolean {
    return this.mImage.getAnimated();
  }

  /** 裁剪后宽度。 */
  getWidth(): number {
    return this.mCut.width();
  }

  /** 裁剪后高度。 */
  getHeight(): number {
    return this.mCut.height();
  }

  /**
   * 把（裁剪区内的）图像上传到当前绑定的 GL 纹理。
   * 偏移量加上裁剪区左上角 —— 与上游一致，分块上传依赖这一步。
   */
  texImage(init: boolean, offsetX: number, offsetY: number, width: number, height: number): void {
    this.mImage.texImage(init, offsetX + this.mCut.left, offsetY + this.mCut.top, width, height);
  }

  start(): void {
    this.mImage.start();
  }

  getDelay(): number {
    return this.mImage.getDelay();
  }

  isOpaque(): boolean {
    return this.mImage.isOpaque();
  }

  isRecycled(): boolean {
    return this.mImage.isRecycled();
  }

  /** 直接取底层 Image（上游无此方法；供 `ImageTexture` 需要访问原图时使用，避免再包一层）。 */
  getImage(): Image {
    return this.mImage;
  }

  /** 当前引用计数（调试/泄漏排查用）。 */
  getReferenceCount(): number {
    return this.mReferences;
  }
}
