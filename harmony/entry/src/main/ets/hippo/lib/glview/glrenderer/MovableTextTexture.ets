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
import { GLCanvas } from './GLCanvas';
import { SpriteTexture } from './SpriteTexture';
import { OffscreenCanvasLike, OffscreenDrawingContext, TextPaintLike } from './CanvasTexture';

/**
 * `com.hippo.lib.glview.glrenderer.MovableTextTexture` 的 ArkTS 等价实现（inventory S0350）。
 *
 * 语义：把所有用到的字符预先**排版成一张图集**（每字符一个 sprite），
 * 之后按字符索引直接画格子 —— 这样逐帧渲染文字只需若干 `drawSprite`，不必重新排版。
 *
 * ## 拆分（同 SpriteTexture / NinePatchTexture）
 *   - **纯计算**：图集网格（`hCount`/`vCount`）、每字符 rect、宽度累加、`binarySearch` 索引
 *   - **离屏绘制**：把字符画进图集（`OffscreenCanvasLike` 接缝）
 *
 * ## 五处必须照搬
 *   1. `mHeight = fmi.bottom - fmi.top`；`fixed = fmi.bottom`
 *   2. 画布先 `translate(0, height - fixed)`（把基线挪到格子内）
 *   3. 网格数量：`hCount = ceil(sqrt(height/maxWidth*length))`、
 *      `vCount = ceil(sqrt(maxWidth/height*length))`，随后**两次缩减**：
 *      `if (hCount*(vCount-1) > length) vCount--;`
 *      `if ((hCount-1)*vCount > length) hCount--;`
 *   4. `getTextIndexes` / `getTextWidth` 用**二分查找**（`binarySearch`，找不到返回负数）
 *   5. 绘制时 `index >= 0` 才画并前进 `widths[index]`；否则**只前进 `mMaxWidth` 不画**
 */
export class MovableTextTexture extends SpriteTexture {
  // 注意：字段名不能叫 mHeight —— 基类 TiledTexture 有 private mHeight，同名会让 tsc 报 TS2415
  private readonly mChars: string[];
  private readonly mCharWidths: number[];
  private readonly mTextHeight: number;
  private readonly mTextMaxWidth: number;

  private constructor(bitmap: image.PixelMap, count: number, rects: number[],
    characters: string[], widths: number[], height: number, maxWidth: number) {
    super(bitmap, false, count, rects);
    this.mChars = characters;
    this.mCharWidths = widths;
    this.mTextHeight = height;
    this.mTextMaxWidth = maxWidth;
  }

  /** 对齐 `getTextIndexes(text)`：逐字符二分查找（找不到给负值，绘制时跳过）。 */
  getTextIndexes(text: string): number[] {
    const characters: string[] = this.mChars;
    const length: number = text.length;
    const indexes: number[] = new Array<number>(length);
    for (let i = 0; i < length; i++) {
      indexes[i] = MovableTextTexture.binarySearch(characters, text.charAt(i));
    }
    return indexes;
  }

  /** 对齐 `getTextWidth(text)`。 */
  getTextWidth(text: string): number {
    const characters: string[] = this.mChars;
    const widths: number[] = this.mCharWidths;
    let width: number = 0;
    for (let i = 0; i < text.length; i++) {
      const index: number = MovableTextTexture.binarySearch(characters, text.charAt(i));
      if (index >= 0) {
        width += widths[index];
      } else {
        width += this.mTextMaxWidth;
      }
    }
    return width;
  }

  /** 对齐 `getTextWidth(int[] indexes)`（预计算索引版，绘制路径用它）。 */
  getTextWidthOfIndexes(indexes: number[]): number {
    const widths: number[] = this.mCharWidths;
    let width: number = 0;
    for (let i = 0; i < indexes.length; i++) {
      const index: number = indexes[i];
      if (index >= 0) {
        width += widths[index];
      } else {
        width += this.mTextMaxWidth;
      }
    }
    return width;
  }

  getMaxWidth(): number {
    return this.mTextMaxWidth;
  }

  getTextHeight(): number {
    return this.mTextHeight;
  }

  /** 对齐 `drawText(canvas, text, x, y)`：逐字符画 sprite。 */
  drawText(canvas: GLCanvas, text: string, x: number, y: number): void {
    const characters: string[] = this.mChars;
    const widths: number[] = this.mCharWidths;
    let cursor: number = x;
    for (let i = 0; i < text.length; i++) {
      const index: number = MovableTextTexture.binarySearch(characters, text.charAt(i));
      if (index >= 0) {
        this.drawSprite(canvas, index, cursor, y);
        cursor += widths[index];
      } else {
        cursor += this.mTextMaxWidth;
      }
    }
  }

  /** 对齐 `drawText(canvas, indexes, x, y)`。 */
  drawTextOfIndexes(canvas: GLCanvas, indexes: number[], x: number, y: number): void {
    const widths: number[] = this.mCharWidths;
    let cursor: number = x;
    for (let i = 0; i < indexes.length; i++) {
      const index: number = indexes[i];
      if (index >= 0) {
        this.drawSprite(canvas, index, cursor, y);
        cursor += widths[index];
      } else {
        cursor += this.mTextMaxWidth;
      }
    }
  }

  /**
   * 对齐 `create(typeface, size, color, characters)`：排版并画出一张字符图集。
   *
   * 图集网格的计算**必须逐行照搬**（两次缩减的顺序不能换），否则图集尺寸会多一格，
   * 表现为「右下角一块空白」或「图集过大导致显存浪费」——都不报错。
   */
  static create(paint: TextPaintLike, characters: string[],
    offscreen: OffscreenCanvasLike): MovableTextTexture {
    const fmi = paint.getFontMetrics();
    const fixed: number = fmi.bottom;
    const height: number = fmi.bottom - fmi.top;
    const length: number = characters.length;
    const widths: number[] = new Array<number>(length);
    for (let i = 0; i < length; i++) {
      widths[i] = paint.measureText(characters[i]);
    }
    // 图集尺寸
    let maxWidth: number = 0;
    for (let i = 0; i < widths.length; i++) {
      maxWidth = Math.max(maxWidth, widths[i]);
    }
    let hCount: number = Math.ceil(Math.sqrt(height / maxWidth * length));
    let vCount: number = Math.ceil(Math.sqrt(maxWidth / height * length));
    if (hCount * (vCount - 1) > length) {
      vCount--;
    }
    if ((hCount - 1) * vCount > length) {
      hCount--;
    }

    const bitmapWidth: number = Math.ceil(hCount * maxWidth);
    const bitmapHeight: number = Math.ceil(vCount * height);
    const bitmap: image.PixelMap = offscreen.createBitmap(bitmapWidth, bitmapHeight);
    const canvas: OffscreenDrawingContext = offscreen.createCanvas(bitmap);
    canvas.translate(0, height - fixed);

    // 逐字符画进图集，同时记录每个字符的 rect
    const rects: number[] = new Array<number>(length * 4);
    let x: number = 0;
    let y: number = 0;
    for (let i = 0; i < length; i++) {
      const offset: number = i * 4;
      rects[offset + 0] = x;
      rects[offset + 1] = y;
      rects[offset + 2] = Math.floor(widths[i]);
      rects[offset + 3] = height;
      canvas.drawText(characters[i], x, y, paint);
      if (i % hCount === hCount - 1) {
        // The end of row
        x = 0;
        y += height;
      } else {
        x += maxWidth;
      }
    }
    return new MovableTextTexture(bitmap, length, rects, characters, widths, height, maxWidth);
  }

  /** 对齐 `Arrays.binarySearch(char[], key)`：找不到返回 `-(插入点) - 1`（负数）。 */
  private static binarySearch(characters: string[], target: string): number {
    let low: number = 0;
    let high: number = characters.length - 1;
    while (low <= high) {
      const mid: number = (low + high) >>> 1;
      const midChar: string = characters[mid];
      if (midChar < target) {
        low = mid + 1;
      } else if (midChar > target) {
        high = mid - 1;
      } else {
        return mid;
      }
    }
    return -(low + 1);
  }
}
