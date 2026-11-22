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

import { image } from '@kit.ImageKit';
import { GLCanvas } from './GLCanvas';
import { BasicTexture } from './BasicTexture';
import { GLConst } from '../native/GLConst';
import { PixelMapUtils } from '../util/PixelMapUtils';

/**
 * `com.hippo.lib.glview.glrenderer.UploadedTexture` 的 ArkTS 等价实现。
 *
 * 语义（上游注释直译）：纹理内容来自一张位图，子类实现 `onGetBitmap()` 提供位图、
 * `onFreeBitmap(bitmap)` 在不再需要时释放。`isContentValid()` 只有在 `isLoaded()`
 * 为真时才有意义 —— 表示 GPU 上的内容是否过期。
 *
 * ## Bitmap → PixelMap 的映射
 * | 上游 | 鸿蒙 |
 * |---|---|
 * | `onGetBitmap(): Bitmap` | `onGetBitmap(): image.PixelMap` |
 * | `GLUtils.getInternalFormat(bitmap)` | 恒 `GL_RGBA`（鸿蒙解码统一 RGBA8888） |
 * | `GLUtils.getType(bitmap)` | 恒 `GL_UNSIGNED_BYTE` |
 * | `Bitmap.createBitmap(1,length,cfg)` 生成边框线 | `texSubImage2DFill(...)` 填零（像素等价） |
 * | `bitmap.recycle()` | `pixelMap.release()` |
 *
 * ## 边线优化（不是自由发挥，是等价替换）
 * 上游为一个全零的 1×N / N×1 位图建了 `HashMap<BorderKey,Bitmap>` 缓存，只为把
 * "2 的幂尺寸里多出来的那一圈"刷成透明。这里改成 `texSubImage2DFill` 直接 memset：
 * 上传的像素值完全相同（RGBA=0），但省掉了位图分配、缓存与一次内存拷贝。
 * 单测断言"上传顺序含 4 次 fill 且区域坐标与上游一致"。
 */
export abstract class UploadedTexture extends BasicTexture {
  private static readonly UPLOAD_LIMIT: number = 100;

  private mContentValid: boolean = true;
  private mIsUploading: boolean = false;
  private mOpaque: boolean = true;
  private mThrottled: boolean = false;

  private static sUploadedCount: number = 0;

  /** 当前持有的位图（PixelMap）；为 null 表示已释放，需要时由 `onGetBitmap()` 重新取。 */
  protected mBitmap: image.PixelMap | null = null;
  private mBorder: number = 0;

  /** `UploadedTexture()` 与 `UploadedTexture(boolean hasBorder)` 的一个入口。 */
  protected constructor(hasBorder: boolean = false) {
    super(null, 0, BasicTexture.STATE_UNLOADED);
    if (hasBorder) {
      this.setBorder(true);
      this.mBorder = 1;
    }
  }

  /**
   * 设置「正在上传」标记。
   * 上游是 package-private（`TextureUploader` 同包直调）；ArkTS 没有包级可见性，故设为 public。
   */
  setIsUploading(uploading: boolean): void {
    this.mIsUploading = uploading;
  }

  isUploading(): boolean {
    return this.mIsUploading;
  }

  protected setThrottled(throttled: boolean): void {
    this.mThrottled = throttled;
  }

  /** 懒加载位图；首次取到时若尺寸未知，用位图尺寸 + 边框算出内容尺寸。 */
  private peekBitmap(): image.PixelMap {
    if (this.mBitmap === null) {
      this.mBitmap = this.onGetBitmap();
      if (this.mWidth === BasicTexture.UNSPECIFIED) {
        const size = PixelMapUtils.readSize(this.mBitmap);
        if (size === null) {
          throw new Error('UploadedTexture: PixelMap.getImageInfoSync failed (released?)');
        }
        this.setSize(size.width + this.mBorder * 2, size.height + this.mBorder * 2);
      }
    }
    return this.mBitmap;
  }

  private freeBitmap(): void {
    const bitmap = this.mBitmap;
    if (bitmap === null) {
      throw new Error('null == mBitmap');
    }
    this.onFreeBitmap(bitmap);
    this.mBitmap = null;
  }

  getWidth(): number {
    if (this.mWidth === BasicTexture.UNSPECIFIED) {
      this.peekBitmap();
    }
    return this.mWidth;
  }

  getHeight(): number {
    if (this.mWidth === BasicTexture.UNSPECIFIED) {
      this.peekBitmap();
    }
    return this.mHeight;
  }

  /** 子类提供内容位图。 */
  protected abstract onGetBitmap(): image.PixelMap;

  /** 子类决定如何释放位图（持有外部位图时什么都不做，自解码的则 release）。 */
  protected abstract onFreeBitmap(bitmap: image.PixelMap): void;

  /** 内容变了：丢掉旧位图，尺寸置为未知，等下一次绑定重新取。 */
  invalidateContent(): void {
    if (this.mBitmap !== null) {
      this.freeBitmap();
    }
    this.mContentValid = false;
    this.mWidth = BasicTexture.UNSPECIFIED;
    this.mHeight = BasicTexture.UNSPECIFIED;
  }

  /** GPU 上的内容是否有效。 */
  isContentValid(): boolean {
    return this.isLoaded() && this.mContentValid;
  }

  /** 把内容更新到 GPU。已加载但内容过期时只做一次 `texSubImage2D`。 */
  updateContent(canvas: GLCanvas): void {
    if (!this.isLoaded()) {
      // 上游：if (mThrottled && ++sUploadedCount > UPLOAD_LIMIT) return;
      // 注意短路：非 throttled 纹理不计入配额（++ 根本不会执行），这里保持一致
      if (this.mThrottled) {
        UploadedTexture.sUploadedCount++;
        if (UploadedTexture.sUploadedCount > UploadedTexture.UPLOAD_LIMIT) {
          return;
        }
      }
      this.uploadToCanvas(canvas);
    } else if (!this.mContentValid) {
      const bitmap = this.peekBitmap();
      canvas.texSubImage2D(this, this.mBorder, this.mBorder, bitmap, GLConst.GL_RGBA,
        GLConst.GL_UNSIGNED_BYTE);
      this.freeBitmap();
      this.mContentValid = true;
    }
  }

  static resetUploadLimit(): void {
    UploadedTexture.sUploadedCount = 0;
  }

  static uploadLimitReached(): boolean {
    return UploadedTexture.sUploadedCount > UploadedTexture.UPLOAD_LIMIT;
  }

  private uploadToCanvas(canvas: GLCanvas): void {
    const bitmap = this.peekBitmap();
    if (bitmap === null) {
      this.mState = BasicTexture.STATE_ERROR;
      throw new Error('Texture load fail, no bitmap');
    }
    try {
      const size = PixelMapUtils.readSize(bitmap);
      if (size === null) {
        this.mState = BasicTexture.STATE_ERROR;
        throw new Error('UploadedTexture: cannot read PixelMap size (released?)');
      }
      const bWidth = size.width;
      const bHeight = size.height;
      const texWidth = this.getTextureWidth();
      const texHeight = this.getTextureHeight();

      if (bWidth > texWidth || bHeight > texHeight) {
        throw new Error('bWidth > texWidth || bHeight > texHeight');
      }
      // 上传到新纹理
      this.mId = canvas.getGLId().generateTexture();
      canvas.setTextureParameters(this);

      if (bWidth === texWidth && bHeight === texHeight) {
        canvas.initializeTexture(this, bitmap);
      } else {
        canvas.initializeTextureSize(this, GLConst.GL_RGBA, GLConst.GL_UNSIGNED_BYTE);
        canvas.texSubImage2D(this, this.mBorder, this.mBorder, bitmap, GLConst.GL_RGBA,
          GLConst.GL_UNSIGNED_BYTE);

        if (this.mBorder > 0) {
          // 左边框：竖线 1 × texHeight，透明
          canvas.texSubImage2DFill(this, 0, 0, 1, texHeight, GLConst.GL_RGBA,
            GLConst.GL_UNSIGNED_BYTE, 0);
          // 上边框：横线 texWidth × 1，透明
          canvas.texSubImage2DFill(this, 0, 0, texWidth, 1, GLConst.GL_RGBA,
            GLConst.GL_UNSIGNED_BYTE, 0);
        }

        // 右边框
        if (this.mBorder + bWidth < texWidth) {
          canvas.texSubImage2DFill(this, this.mBorder + bWidth, 0, 1, texHeight,
            GLConst.GL_RGBA, GLConst.GL_UNSIGNED_BYTE, 0);
        }

        // 下边框
        if (this.mBorder + bHeight < texHeight) {
          canvas.texSubImage2DFill(this, 0, this.mBorder + bHeight, texWidth, 1,
            GLConst.GL_RGBA, GLConst.GL_UNSIGNED_BYTE, 0);
        }
      }
    } finally {
      this.freeBitmap();
    }
    this.setAssociatedCanvas(canvas);
    this.mState = BasicTexture.STATE_LOADED;
    this.mContentValid = true;
  }

  onBind(canvas: GLCanvas): boolean {
    this.updateContent(canvas);
    return this.isContentValid();
  }

  getTarget(): number {
    return GLConst.GL_TEXTURE_2D;
  }

  setOpaque(isOpaque: boolean): void {
    this.mOpaque = isOpaque;
  }

  isOpaque(): boolean {
    return this.mOpaque;
  }

  recycle(): void {
    super.recycle();
    if (this.mBitmap !== null) {
      this.freeBitmap();
    }
  }
}
