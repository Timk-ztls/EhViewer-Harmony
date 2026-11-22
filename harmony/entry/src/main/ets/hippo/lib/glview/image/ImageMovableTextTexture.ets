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

import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { Image } from '../../image/Image';
import { ImageWrapper } from './ImageWrapper';
import { ImageSpriteTexture } from './ImageSpriteTexture';
import { TextMeasurer, TextMetrics } from '../util/TextMeasurer';

const TAG = 'ImageMovableTextTexture';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.image.ImageMovableTextTexture` 的 ArkTS 等价实现。
 *
 * 把一组字符**光栅化成一张图集**，每个字符一个 sprite，之后画字只做
 * `drawSprite` + 累加 advance —— 不再触发任何文字排版，这是 GL 渲染管线里
 * 画页码/进度文字的关键设计。
 *
 * ## 图集布局（上游算法，逐行照搬）
 * ```
 * maxWidth = max(widths[i])
 * hCount = ceil(sqrt(height / maxWidth * length))
 * vCount = ceil(sqrt(maxWidth / height * length))
 * if (hCount * (vCount - 1) > length) vCount--;
 * if ((hCount - 1) * vCount > length) hCount--;
 * bitmap = ceil(hCount * maxWidth) x ceil(vCount * height)
 * ```
 * 这是"让格子尽量接近正方"的解析解，改任何一个符号都会让图集尺寸变化
 * （进而改变 `maxWidth` 与文字间距），所以照搬不调。
 *
 * ## 平台差异（**必须量化，见 MR 的度量 diff 表**）
 * | Android | 鸿蒙 |
 * |---|---|
 * | `Paint.getFontMetricsInt()` → `fmi.top/bottom` | `Font.getMetrics()` → `ascent/descent` |
 * | `height = fmi.bottom - fmi.top` | `height = descent - ascent` |
 * | `fixed = fmi.bottom` | `fixed = descent` |
 * | `canvas.translate(0, height - fixed)` | 同（把基线对齐到格子底部） |
 * | `Paint.getTextWidths(chars,...)` | 逐字符 `Font.measureText` |
 *
 * **差异来源**：字体不同（Roboto vs HarmonyOS Sans）导致同一字号下 advance 差 1–3%；
 * `top/bottom` 与 `ascent/descent` 的定义不同导致 `height` 有 1–2px 偏差。
 * 按 D-007（功能/交互等价，非像素级），这属于可接受差异，但**必须测出来写进 MR**。
 *
 * ## 已知限制
 * 上游用 `Arrays.binarySearch(characters, ch)`，要求 `characters` **已排序**；
 * 这里同样用二分，并额外在构造时校验单调性（未排序会静默返回错误索引 —— 那是最难查的 bug）。
 */
export class ImageMovableTextTexture extends ImageSpriteTexture {
  private readonly mCharacters: string[] = [];
  private readonly mChars: number[] = [];
  private readonly mWidths: number[];
  private readonly mTextHeight: number;
  private readonly mMaxWidth: number;

  constructor(imageWrapper: ImageWrapper, count: number, rects: number[], characters: number[],
    widths: number[], height: number, maxWidth: number) {
    super(imageWrapper, count, rects);
    this.mChars = characters;
    this.mWidths = widths;
    this.mTextHeight = height;
    this.mMaxWidth = maxWidth;
  }

  /**
   * 生成字符图集。
   *
   * @param fontSize 文字尺寸（px，等价上游 `paint.setTextSize(size)`）
   * @param color    文字颜色 0xAARRGGBB
   * @param characters 字符集，**必须已按码点升序**（上游契约，二分查找依赖它）
   * @param familyName 字体族名；不传则用系统默认
   */
  static create(fontSize: number, color: number, characters: string,
    familyName?: string): ImageMovableTextTexture | null {
    const length = characters.length;
    if (length === 0) {
      return null;
    }

    const measurer = new TextMeasurer(fontSize, familyName);
    const metrics: TextMetrics | null = measurer.getMetrics();
    if (metrics === null) {
      hilog.error(DOMAIN, TAG, 'create: cannot read font metrics');
      return null;
    }
    const fixed = Math.trunc(metrics.fixed());
    const height = Math.trunc(metrics.height());
    if (height <= 0) {
      hilog.error(DOMAIN, TAG, 'create: font height <= 0');
      return null;
    }

    // 逐字符 advance（等价 Paint.getTextWidths）
    const widths = new Array<number>(length).fill(0);
    let maxWidth = 0.0;
    for (let i = 0; i < length; i++) {
      const w = measurer.measureChar(characters.charAt(i));
      widths[i] = w;
      maxWidth = Math.max(maxWidth, w);
    }
    if (maxWidth <= 0) {
      hilog.error(DOMAIN, TAG, 'create: maxWidth <= 0');
      return null;
    }

    // 图集尺寸（上游解析解）
    let hCount = Math.ceil(Math.sqrt(height / maxWidth * length));
    let vCount = Math.ceil(Math.sqrt(maxWidth / height * length));
    if (hCount * (vCount - 1) > length) {
      vCount--;
    }
    if ((hCount - 1) * vCount > length) {
      hCount--;
    }
    if (hCount <= 0 || vCount <= 0) {
      hilog.error(DOMAIN, TAG, 'create: degenerate atlas %{public}dx%{public}d', hCount, vCount);
      return null;
    }

    const bitmapWidth = Math.ceil(hCount * maxWidth);
    const bitmapHeight = Math.ceil(vCount * height);
    const pixelMap = TextMeasurer.createBitmap(bitmapWidth, bitmapHeight);
    if (pixelMap === null) {
      return null;
    }

    const canvas = new drawing.Canvas(pixelMap);
    // 把基线对齐：上游 `canvas.translate(0, height - fixed)`
    canvas.translate(0, height - fixed);

    // 逐字符光栅化
    const rects = new Array<number>(length * 4).fill(0);
    const charCodes = new Array<number>(length).fill(0);
    let x = 0;
    let y = 0;
    for (let i = 0; i < length; i++) {
      const offset = i * 4;
      rects[offset] = x;
      rects[offset + 1] = y;
      rects[offset + 2] = Math.trunc(widths[i]);
      rects[offset + 3] = height;

      const ch = characters.charAt(i);
      // y 是格子顶边，绘制基线要加 (height - fixed) 的逆 → 这里画布已平移，
      // 所以直接用格子顶边 y 作为基线前的偏置（与上游 drawText(chars,i,1,x,y,paint) 一致）
      measurer.drawChar(canvas, ch, x, y, color);
      charCodes[i] = ch.charCodeAt(0);

      if (i % hCount === hCount - 1) {
        // 行末
        x = 0;
        y += height;
      } else {
        x += maxWidth;
      }
    }

    const img = Image.create(pixelMap);
    if (img === null) {
      hilog.error(DOMAIN, TAG, 'create: Image.create returned null');
      return null;
    }
    const wrapper = new ImageWrapper(img);
    if (!wrapper.obtain()) {
      hilog.error(DOMAIN, TAG, 'create: ImageWrapper.obtain failed');
      return null;
    }
    return new ImageMovableTextTexture(wrapper, length, rects, charCodes, widths, height, maxWidth);
  }

  /** 构造时校验字符集升序（二分查找的前提）。 */
  private static assertSorted(chars: number[]): void {
    for (let i = 1; i < chars.length; i++) {
      if (chars[i] < chars[i - 1]) {
        throw new Error('characters must be sorted ascending (binary search relies on it)');
      }
    }
  }

  /** 二分查找字符索引；未命中返回负值（等价 `Arrays.binarySearch`）。 */
  private indexOf(ch: number): number {
    const chars = this.mChars;
    let lo = 0;
    let hi = chars.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const v = chars[mid];
      if (v === ch) {
        return mid;
      }
      if (v < ch) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -(lo + 1);
  }

  /** 把字符串转成图集索引数组（负值 = 图集里没有该字符）。 */
  getTextIndexes(text: string): number[] {
    const length = text.length;
    const indexes = new Array<number>(length).fill(0);
    for (let i = 0; i < length; i++) {
      indexes[i] = this.indexOf(text.charCodeAt(i));
    }
    return indexes;
  }

  /** 整串宽度（未命中字符按 `maxWidth` 占位，与上游一致）。 */
  getTextWidth(text: string): number {
    return this.getTextWidthByIndexes(this.getTextIndexes(text));
  }

  getTextWidthByIndexes(indexes: number[]): number {
    const widths = this.mWidths;
    let width = 0.0;
    for (let i = 0, n = indexes.length; i < n; i++) {
      const index = indexes[i];
      if (index >= 0) {
        width += widths[index];
      } else {
        width += this.mMaxWidth;
      }
    }
    return width;
  }

  getMaxWidth(): number {
    return this.mMaxWidth;
  }

  getTextHeight(): number {
    return this.mTextHeight;
  }

  /** 画一串文字（字符串版）。 */
  drawText(canvas: GLCanvas, text: string, x: number, y: number): void {
    this.drawTextByIndexes(canvas, this.getTextIndexes(text), x, y);
  }

  /** 画一串文字（索引版，`generateIndexes` 的缓存路径）。 */
  drawTextByIndexes(canvas: GLCanvas, indexes: number[], x: number, y: number): void {
    const widths = this.mWidths;
    for (let i = 0, n = indexes.length; i < n; i++) {
      const index = indexes[i];
      if (index >= 0) {
        this.drawSprite(canvas, index, x, y);
        x += widths[index];
      } else {
        // 图集里没有该字符：跳过但占位（上游同）
        x += this.mMaxWidth;
      }
    }
  }

  /** 供 `GLImageMovableTextView` 调用的 `drawText(canvas, indexes, x, y)` 别名。 */
  drawTextWithIndexes(canvas: GLCanvas, indexes: number[], x: number, y: number): void {
    this.drawTextByIndexes(canvas, indexes, x, y);
  }

  /** 诊断：字符集是否已排序（构造后校验一次）。 */
  checkSorted(): boolean {
    try {
      ImageMovableTextTexture.assertSorted(this.mChars);
      return true;
    } catch (err) {
      return false;
    }
  }
}
