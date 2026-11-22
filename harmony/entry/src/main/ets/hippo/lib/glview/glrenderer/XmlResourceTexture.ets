/*
 * Copyright 2014 Qihoo Inc.
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

import { image } from '@kit.ImageKit';
import { UploadedTexture } from './UploadedTexture';
import { OffscreenCanvasLike, OffscreenDrawingContext } from './CanvasTexture';

/**
 * `com.hippo.lib.glview.glrenderer.XmlResourceTexture` 的 ArkTS 等价实现（inventory S0363）。
 *
 * 语义：位图由 **XML drawable**（矢量/形状/选择器）按给定边界绘制而来。
 *
 * ## 尺寸三条规则（逐条照搬，顺序不能换）
 * ```
 * width  = mWidth;  height = mHeight;              // 构造后 setBound() 设的
 * if (width  <= 0) width  = drawable.getIntrinsicWidth();
 * if (height <= 0) height = drawable.getIntrinsicHeight();
 * if (width  <= 0) width  = 1;                     // 仍然 <=0 → 兜底 1
 * if (height <= 0) height = 1;
 * ```
 * 注意：**只有 width/height 各自为 0 时才用 intrinsic**，不是「两者都 0 才用」。
 *
 * ## 与 ResourceTexture 的区别
 * - `ResourceTexture`：解码一张图（`decodeResource`），尺寸由位图决定
 * - `XmlResourceTexture`：**不是图**，是按边界**画**出来的；因此必须 `setBound()` 或靠 intrinsic
 *
 * `setBound()` 会 `invalidateContent()` —— 改了边界必须重新画，否则还是旧尺寸的纹理。
 */
export class XmlResourceTexture extends UploadedTexture {
  private readonly mContext: XmlDrawableContextLike;
  private readonly mResId: number;
  private mBoundWidth: number = 0;
  private mBoundHeight: number = 0;
  private readonly mOffscreen: OffscreenCanvasLike;

  constructor(context: XmlDrawableContextLike, resId: number, offscreen: OffscreenCanvasLike) {
    super(false);
    this.mContext = context;
    this.mResId = resId;
    this.mOffscreen = offscreen;
    this.setOpaque(false);
  }

  /** 对齐 `setBound(width, height)`：设边界并**作废已有内容**。 */
  setBound(width: number, height: number): void {
    this.mBoundWidth = width;
    this.mBoundHeight = height;
    this.invalidateContent();
  }

  protected onGetBitmap(): image.PixelMap {
    const drawable: DrawableLike = this.mContext.getDrawable(this.mResId);
    let width: number = this.mBoundWidth;
    let height: number = this.mBoundHeight;
    if (width <= 0) {
      width = drawable.getIntrinsicWidth();
    }
    if (height <= 0) {
      height = drawable.getIntrinsicHeight();
    }
    if (width <= 0) {
      width = 1;
    }
    if (height <= 0) {
      height = 1;
    }
    drawable.setBounds(0, 0, width, height);
    const bitmap: image.PixelMap = this.mOffscreen.createBitmap(width, height);
    const canvas: OffscreenDrawingContext = this.mOffscreen.createCanvas(bitmap);
    drawable.draw(canvas);
    return bitmap;
  }

  protected onFreeBitmap(bitmap: image.PixelMap): void {
    // 上游：`if (!inFinalizer()) bitmap.recycle();`
    // 这里由 UploadedTexture 统一管理，子类不额外做（与 ResourceTexture 的写法保持一致）
    bitmap.release();
  }
}

/** 宿主侧「按 resId 取 drawable」的能力（等价 `ContextCompat.getDrawable`）。 */
export interface XmlDrawableContextLike {
  getDrawable(resId: number): DrawableLike;
}

/** 对齐 `android.graphics.drawable.Drawable` 的最小子集。 */
export interface DrawableLike {
  getIntrinsicWidth(): number;

  getIntrinsicHeight(): number;

  setBounds(left: number, top: number, right: number, bottom: number): void;

  draw(canvas: OffscreenDrawingContext): void;
}
