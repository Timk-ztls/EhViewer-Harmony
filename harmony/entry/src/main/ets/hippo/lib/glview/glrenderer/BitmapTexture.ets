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
import { UploadedTexture } from './UploadedTexture';

/**
 * `com.hippo.lib.glview.glrenderer.BitmapTexture` 的 ArkTS 等价实现。
 *
 * 语义：内容由外部固定位图提供；**纹理不拥有位图**，调用方必须保证位图在纹理生命周期内有效；
 * 纹理回收时不释放位图（`onFreeBitmap` 空实现）。
 *
 * Bitmap → `image.PixelMap`。上游断言 `bitmap != null && !bitmap.isRecycled()`，
 * 鸿蒙侧 PixelMap 没有 `isRecycled()`（`release()` 后再用会抛 BusinessError），
 * 因此只保留非空断言，并登记为差异。
 */
export class BitmapTexture extends UploadedTexture {
  protected mContentBitmap: image.PixelMap;

  /** `BitmapTexture(bitmap)` 与 `BitmapTexture(bitmap, hasBorder)` 合一。 */
  constructor(bitmap: image.PixelMap, hasBorder: boolean = false) {
    super(hasBorder);
    if (bitmap === null || bitmap === undefined) {
      throw new Error('bitmap == null');
    }
    this.mContentBitmap = bitmap;
  }

  protected onFreeBitmap(_bitmap: image.PixelMap): void {
    // 不拥有位图，什么都不做
  }

  protected onGetBitmap(): image.PixelMap {
    return this.mContentBitmap;
  }

  getBitmap(): image.PixelMap {
    return this.mContentBitmap;
  }
}
