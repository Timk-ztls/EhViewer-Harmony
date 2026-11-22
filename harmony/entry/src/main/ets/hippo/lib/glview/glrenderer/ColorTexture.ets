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

import { RectF } from '../util/RectF';
import { GLCanvas } from './GLCanvas';
import { Texture } from './Texture';

/**
 * `com.hippo.lib.glview.glrenderer.ColorTexture` 的 ArkTS 等价实现。
 *
 * 纯色纹理：不占 GL 纹理，直接 `canvas.fillRect`。用在"图还没解码出来时先铺一层底色"
 * 的占位路径（`GalleryPageView` 的 loading 态）。
 *
 * `isOpaque()` 依赖 `ColorUtils.isOpaque(color)`（yorozuya，core-runtime 归属），
 * 这里内联等价实现 `(color >>> 24) == 0xFF`，避免跨模块未合入时阻塞；
 * 等 yorozuya/ColorUtils 落到 main 后改成调用它（行为完全一致）。
 */
export class ColorTexture implements Texture {
  private readonly mColor: number;
  private mWidth: number = 0;
  private mHeight: number = 0;

  constructor(color: number) {
    this.mColor = color;
  }

  private isValidSize(): boolean {
    return this.mWidth > 0 && this.mHeight > 0;
  }

  /** 三种 draw 重载合一（见 `Texture.ets`）。 */
  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, w?: number, h?: number): void {
    if (typeof a === 'number') {
      if (w === undefined || h === undefined) {
        if (this.isValidSize()) {
          canvas.fillRect(a, b as number, this.mWidth, this.mHeight, this.mColor);
        }
        return;
      }
      canvas.fillRect(a, b as number, w, h, this.mColor);
      return;
    }
    const target = b as RectF;
    canvas.fillRect(target.left, target.top, target.width(), target.height(), this.mColor);
  }

  isOpaque(): boolean {
    return ((this.mColor >>> 24) & 0xFF) === 0xFF;
  }

  setSize(width: number, height: number): void {
    this.mWidth = width;
    this.mHeight = height;
  }

  getWidth(): number {
    return this.mWidth;
  }

  getHeight(): number {
    return this.mHeight;
  }

  getColor(): number {
    return this.mColor;
  }
}
