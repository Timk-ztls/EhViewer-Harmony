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
import { RectF } from '../util/RectF';
import { GLCanvas } from './GLCanvas';
import { TiledTexture } from './TiledTexture';

/**
 * `com.hippo.lib.glview.glrenderer.SpriteTexture` 的 ArkTS 等价实现（inventory S0357）。
 *
 * 语义：一张图集（sprite sheet），`rects` 里每 4 个 int 描述一个子图
 * `[sourceX, sourceY, width, height]`。
 *
 * 四处照搬：
 *   1. 构造断言 `rects.length === count * 4`，失败消息
 *      `rects.length must be count * 4`（上游 `AssertUtils.assertEquals`）
 *   2. `drawSprite(canvas, index, x, y)`：**目标尺寸取自 rect 的 w/h**（不缩放）
 *   3. `drawSprite(..., width, height)`：目标尺寸用参数（缩放）
 *   4. `mTempSource` / `mTempTarget` 两个成员**复用**（不是每次 new）——与上游一致，
 *      避免每帧分配
 */
export class SpriteTexture extends TiledTexture {
  private readonly mCount: number;
  private readonly mRects: number[];
  private readonly mTempSource: RectF = new RectF();
  private readonly mTempTarget: RectF = new RectF();

  constructor(bitmap: image.PixelMap, isOpaque: boolean, count: number, rects: number[]) {
    super(bitmap, isOpaque);
    if (rects.length !== count * 4) {
      throw new Error('Assertion failed: rects.length must be count * 4 (actual ' +
        rects.length + ', count ' + count + ')');
    }
    this.mCount = count;
    this.mRects = rects;
  }

  getCount(): number {
    return this.mCount;
  }

  /** 对齐 `drawSprite(canvas, index, x, y)`：按子图自身尺寸画。 */
  drawSprite(canvas: GLCanvas, index: number, x: number, y: number): void {
    const rects: number[] = this.mRects;
    const offset: number = index * 4;
    const sourceX: number = rects[offset];
    const sourceY: number = rects[offset + 1];
    const sourceWidth: number = rects[offset + 2];
    const sourceHeight: number = rects[offset + 3];
    this.mTempSource.set(sourceX, sourceY, sourceX + sourceWidth, sourceY + sourceHeight);
    this.mTempTarget.set(x, y, x + sourceWidth, y + sourceHeight);
    this.drawRect(canvas, this.mTempSource, this.mTempTarget);
  }

  /** 对齐 `drawSprite(canvas, index, x, y, width, height)`：缩放到给定尺寸。 */
  drawSpriteScaled(canvas: GLCanvas, index: number, x: number, y: number,
    width: number, height: number): void {
    const rects: number[] = this.mRects;
    const offset: number = index * 4;
    const sourceX: number = rects[offset];
    const sourceY: number = rects[offset + 1];
    this.mTempSource.set(sourceX, sourceY,
      sourceX + rects[offset + 2], sourceY + rects[offset + 3]);
    this.mTempTarget.set(x, y, x + width, y + height);
    this.drawRect(canvas, this.mTempSource, this.mTempTarget);
  }

  /** 对齐 `drawSpriteMixed(canvas, index, color, ratio, x, y)`。 */
  drawSpriteMixed(canvas: GLCanvas, index: number, color: number, ratio: number,
    x: number, y: number): void {
    const rects: number[] = this.mRects;
    const offset: number = index * 4;
    const sourceX: number = rects[offset];
    const sourceY: number = rects[offset + 1];
    const sourceWidth: number = rects[offset + 2];
    const sourceHeight: number = rects[offset + 3];
    this.mTempSource.set(sourceX, sourceY, sourceX + sourceWidth, sourceY + sourceHeight);
    this.mTempTarget.set(x, y, x + sourceWidth, y + sourceHeight);
    this.drawMixedRegion(canvas, color, ratio, this.mTempSource, this.mTempTarget);
  }

  /** 对齐 `drawSpriteMixed(canvas, index, color, ratio, x, y, width, height)`。 */
  drawSpriteMixedScaled(canvas: GLCanvas, index: number, color: number, ratio: number,
    x: number, y: number, width: number, height: number): void {
    const rects: number[] = this.mRects;
    const offset: number = index * 4;
    const sourceX: number = rects[offset];
    const sourceY: number = rects[offset + 1];
    this.mTempSource.set(sourceX, sourceY,
      sourceX + rects[offset + 2], sourceY + rects[offset + 3]);
    this.mTempTarget.set(x, y, x + width, y + height);
    this.drawMixedRegion(canvas, color, ratio, this.mTempSource, this.mTempTarget);
  }
}
