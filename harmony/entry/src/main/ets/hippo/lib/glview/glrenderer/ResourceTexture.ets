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

/**
 * `com.hippo.lib.glview.glrenderer.ResourceTexture` 的 ArkTS 等价实现（inventory S0356）。
 *
 * 语义：位图从**资源**解码（Android 是 `BitmapFactory.decodeResource`）。
 *
 * 平台映射：
 *   | Android | 鸿蒙 |
 *   |---|---|
 *   | `Context` | 宿主传入的 `ResourceContextLike`（只要求能按 resId 解码） |
 *   | `BitmapFactory.decodeResource(res, resId, options)` | `ResourceDecoder.decode(context, resId)` |
 *
 * 三处照搬：
 *   1. 构造时 **context == null 直接抛 `IllegalArgumentException("context == null")`**
 *      （上游把那句 `Assert.assertNotNull` 注释掉了，改成显式抛）
 *   2. `setOpaque(false)` —— 默认非不透明
 *   3. `onFreeBitmap` 里 `bitmap.recycle()`；ArkTS 侧对应 `pixelMap.release()`，
 *      但**只在非 finalizer 线程**执行（上游 `inFinalizer()` 判定）—— 我们保留同一个开关位
 */
export class ResourceTexture extends UploadedTexture {
  protected readonly mContext: ResourceContextLike;
  protected readonly mResId: number;
  private readonly mInFinalizer: boolean;

  constructor(context: ResourceContextLike | null, resId: number, inFinalizer: boolean = false) {
    super(false);
    if (context === null) {
      throw new Error('IllegalArgumentException: context == null');
    }
    this.mContext = context;
    this.mResId = resId;
    this.mInFinalizer = inFinalizer;
    this.setOpaque(false);
  }

  protected onGetBitmap(): image.PixelMap {
    // 上游：Options.inPreferredConfig = ARGB_8888（鸿蒙 PixelMap 默认即 RGBA_8888）
    return this.mContext.decode(this.mResId);
  }

  protected onFreeBitmap(bitmap: image.PixelMap): void {
    if (!this.mInFinalizer) {
      bitmap.release();
    }
  }
}

/**
 * 资源解码接缝：生产实现封装 `@ohos.multimedia.image` +
 * `resourceManager.getMediaContent(resId)` → `createImageSource` → `createPixelMap`。
 */
export interface ResourceContextLike {
  decode(resId: number): image.PixelMap;
}
