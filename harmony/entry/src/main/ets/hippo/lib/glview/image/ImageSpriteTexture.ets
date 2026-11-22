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

import { RectF } from '../util/RectF';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { ImageWrapper } from './ImageWrapper';
import { ImageTexture } from './ImageTexture';

/**
 * `com.hippo.lib.glview.image.ImageSpriteTexture` 的 ArkTS 等价实现。
 *
 * 在 `ImageTexture` 之上加一层"sprite 表"：`rects` 是 `count * 4` 的扁平数组
 * （每项 `x, y, w, h`），每个索引对应图集里的一个字符/图标。
 * `ImageMovableTextTexture` 用它把整张字符图集当字模表。
 *
 * 四个 `drawSprite*` 重载在 ArkTS 里合并：
 * - `drawSprite(canvas, index, x, y)` / `drawSprite(canvas, index, x, y, w, h)`
 * - `drawSpriteMixed(canvas, index, color, ratio, x, y)` / `... , w, h)`
 */
export class ImageSpriteTexture extends ImageTexture {
  private readonly mCount: number;
  private readonly mRects: number[];

  private readonly mTempSource: RectF = new RectF();
  private readonly mTempTarget: RectF = new RectF();

  constructor(image: ImageWrapper, count: number, rects: number[]) {
    super(image);
    // 上游 AssertUtils.assertEquals("rects.length must be count * 4", count*4, rects.length)
    if (count * 4 !== rects.length) {
      throw new Error(`rects.length must be count * 4 (count=${count}, len=${rects.length})`);
    }
    this.mCount = count;
    this.mRects = rects;
  }

  getCount(): number {
    return this.mCount;
  }

  /** 索引越界直接抛错（上游会数组越界，这里给具名错误）。 */
  private checkIndex(index: number): number {
    if (index < 0 || index >= this.mCount) {
      throw new Error(`sprite index out of range: ${index} (count=${this.mCount})`);
    }
    return index * 4;
  }

  drawSprite(canvas: GLCanvas, index: number, x: number, y: number, width?: number,
    height?: number): void {
    const offset = this.checkIndex(index);
    const rects = this.mRects;
    const sourceX = rects[offset];
    const sourceY = rects[offset + 1];
    const sourceWidth = rects[offset + 2];
    const sourceHeight = rects[offset + 3];

    this.mTempSource.set(sourceX, sourceY, sourceX + sourceWidth, sourceY + sourceHeight);
    if (width === undefined || height === undefined) {
      this.mTempTarget.set(x, y, x + sourceWidth, y + sourceHeight);
    } else {
      this.mTempTarget.set(x, y, x + width, y + height);
    }
    this.draw(canvas, this.mTempSource, this.mTempTarget);
  }

  drawSpriteMixed(canvas: GLCanvas, index: number, color: number, ratio: number, x: number,
    y: number, width?: number, height?: number): void {
    const offset = this.checkIndex(index);
    const rects = this.mRects;
    const sourceX = rects[offset];
    const sourceY = rects[offset + 1];
    const sourceWidth = rects[offset + 2];
    const sourceHeight = rects[offset + 3];

    this.mTempSource.set(sourceX, sourceY, sourceX + sourceWidth, sourceY + sourceHeight);
    if (width === undefined || height === undefined) {
      this.mTempTarget.set(x, y, x + sourceWidth, y + sourceHeight);
    } else {
      this.mTempTarget.set(x, y, x + width, y + height);
    }
    this.drawMixed(canvas, color, ratio, this.mTempSource, this.mTempTarget);
  }
}
