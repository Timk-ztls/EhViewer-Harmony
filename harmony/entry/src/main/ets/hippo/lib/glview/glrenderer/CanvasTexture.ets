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
 * `com.hippo.lib.glview.glrenderer.CanvasTexture` 的 ArkTS 等价实现（inventory S0337）。
 *
 * 语义（上游注释直译）：内容是**在一块画布上画出来**的纹理；子类覆写 `onDraw()`。
 * 默认**不是**不透明的。
 *
 * ## 离屏画布接缝（Lead 批准的 `OffscreenCanvasLike`）
 * Android 有 `Bitmap.createBitmap` + `new Canvas(bitmap)`；鸿蒙侧由宿主提供，我们只定义最小形状。
 * 约束：**只暴露被测代码实际用到的能力**，实现方用 `@ohos.multimedia.image` + `OffscreenCanvas`。
 *
 * ## 三处照搬
 *   1. 构造时 `Config.ARGB_8888`（鸿蒙 PixelMap 默认 RGBA_8888，无需传参）
 *   2. 构造时 `setSize(width, height)` —— **尺寸在构造时就确定**，不等位图
 *   3. `setOpaque(false)`；`onFreeBitmap` 里 recycle（非 finalizer 时）
 */
export abstract class CanvasTexture extends UploadedTexture {
  private readonly mOffscreen: OffscreenCanvasLike;
  private readonly mInFinalizer: boolean;

  constructor(width: number, height: number, offscreen: OffscreenCanvasLike,
    inFinalizer: boolean = false) {
    super(false);
    this.mOffscreen = offscreen;
    this.mInFinalizer = inFinalizer;
    this.setSize(width, height);
    this.setOpaque(false);
  }

  protected onGetBitmap(): image.PixelMap {
    // 上游：createBitmap(mWidth, mHeight, ARGB_8888) → new Canvas(bitmap) → onDraw(canvas, bitmap)
    const width: number = this.getWidth();
    const height: number = this.getHeight();
    const backing: image.PixelMap = this.mOffscreen.createBitmap(width, height);
    const canvas: OffscreenDrawingContext = this.mOffscreen.createCanvas(backing);
    this.onDraw(canvas, backing);
    return backing;
  }

  protected onFreeBitmap(bitmap: image.PixelMap): void {
    if (!this.mInFinalizer) {
      bitmap.release();
    }
  }

  /** 子类在这里把内容画到 `canvas` 上；`backing` 是同一张位图（上游签名如此）。 */
  protected abstract onDraw(canvas: OffscreenDrawingContext, backing: image.PixelMap): void;
}

/**
 * 离屏画布接缝（最小形状，按 Lead 批准的约束）。
 *
 * 只加「被测代码实际用到」的能力：
 *   - `createBitmap(w,h)`：分配一张 ARGB_8888 位图
 *   - `createCanvas(bitmap)`：得到绘制上下文
 * 文字/位图/线条绘制放在 `OffscreenDrawingContext` 上（由具体子类按需使用）。
 */
export interface OffscreenCanvasLike {
  createBitmap(width: number, height: number): image.PixelMap;

  createCanvas(bitmap: image.PixelMap): OffscreenDrawingContext;
}

/** 离屏绘制上下文（对齐 android.graphics.Canvas 的常用子集）。 */
export interface OffscreenDrawingContext {
  getWidth(): number;

  getHeight(): number;

  drawColor(color: number): void;

  drawText(text: string, x: number, y: number, paint: TextPaintLike): void;

  drawBitmap(bitmap: image.PixelMap, src: RectLike | null, dst: RectLike): void;

  drawLine(x1: number, y1: number, x2: number, y2: number, paint: PaintLike): void;

  drawRect(left: number, top: number, right: number, bottom: number, paint: PaintLike): void;

  /** 对齐 `Canvas.translate(dx, dy)`（StringTexture 用它把基线挪到顶部）。 */
  translate(dx: number, dy: number): void;
}

/** 对齐 `android.graphics.Paint` 的子集。 */
export interface PaintLike {
  getColor(): number;

  setColor(color: number): void;

  getStrokeWidth(): number;

  setStrokeWidth(width: number): void;
}

/** 对齐 `android.graphics.Paint`（文字相关子集）+ `Paint`。 */
export interface TextPaintLike extends PaintLike {
  getTextSize(): number;

  setTextSize(size: number): void;

  isAntiAlias(): boolean;

  measureText(text: string): number;

  /** 对齐 `Paint.getFontMetricsInt()`（返回 top/ascent/descent/bottom）。 */
  getFontMetrics(): FontMetricsLike;

  /** 对齐 `TextUtils.ellipsize(text, paint, maxWidth, TruncateAt.END)`。 */
  ellipsize(text: string, maxWidth: number): string;

  /** 对齐 `paint.setTypeface(Typeface.defaultFromStyle(Typeface.BOLD))`。 */
  setBold(bold: boolean): void;
}

/** 对齐 `Paint.FontMetricsInt`（只用 top/bottom/ascent，都是整数像素）。 */
export interface FontMetricsLike {
  top: number;
  ascent: number;
  descent: number;
  bottom: number;
}

/** 对齐 `android.graphics.Rect`（左上右下）。 */
export interface RectLike {
  left: number;
  top: number;
  right: number;
  bottom: number;
}
