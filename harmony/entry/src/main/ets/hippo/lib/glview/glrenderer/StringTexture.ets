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

import { CanvasTexture, FontMetricsLike, OffscreenCanvasLike, OffscreenDrawingContext, TextPaintLike } from './CanvasTexture';

/**
 * `com.hippo.lib.glview.glrenderer.StringTexture` 的 ArkTS 等价实现（inventory S0358）。
 *
 * 语义（上游注释直译）：显示一段文字的纹理。用 `newInstance(...)` 创建，
 * 指定文字、字号、颜色。
 *
 * ## 纹理尺寸的计算（最容易错的地方，逐条照搬）
 * ```
 * width  = ceil(paint.measureText(text))        ← 向上取整
 * height = metrics.bottom - metrics.top          ← 行高，不是字号
 * if (width  <= 0) width  = 1                    ← 至少 1×1（空串会得到 0）
 * if (height <= 0) height = 1
 * ```
 *
 * ## 绘制
 * ```
 * canvas.translate(0, -mMetrics.ascent)   ← 上移 ascent（ascent 是负值，所以是"上移"）
 * canvas.drawText(mText, 0, 0, mPaint)
 * ```
 * 这两行是配套的：`drawText` 的 y 是**基线**，先 translate 到 `-ascent` 才能让文字顶部贴 0。
 *
 * ## 省略号截断
 * `lengthLimit > 0` 时用 `TextUtils.ellipsize(..., TruncateAt.END)` —— 鸿蒙侧交给
 * `TextPaintLike.ellipsize(text, maxWidth)`，由宿主实现（可用 `@ohos.measure` / `Paragraph`）。
 */
export class StringTexture extends CanvasTexture {
  private readonly mText: string;
  private readonly mPaint: TextPaintLike;
  private readonly mMetrics: FontMetricsLike;

  private constructor(text: string, paint: TextPaintLike, metrics: FontMetricsLike,
    width: number, height: number, offscreen: OffscreenCanvasLike) {
    super(width, height, offscreen);
    this.mText = text;
    this.mPaint = paint;
    this.mMetrics = metrics;
  }

  /** 对齐 `getDefaultPaint(textSize, color)`：抗锯齿 + 阴影（阴影鸿蒙侧由宿主 paint 决定）。 */
  static getDefaultPaint(factory: TextPaintFactoryLike, textSize: number,
    color: number): TextPaintLike {
    return factory.createDefaultPaint(textSize, color);
  }

  /** 对齐 `newInstance(text, textSize, color)`。 */
  static newInstance(text: string, textSize: number, color: number,
    factory: TextPaintFactoryLike, offscreen: OffscreenCanvasLike): StringTexture {
    return StringTexture.newInstanceWithPaint(text,
      StringTexture.getDefaultPaint(factory, textSize, color), offscreen);
  }

  /**
   * 对齐 `newInstance(text, textSize, color, lengthLimit, isBold)`。
   * `lengthLimit > 0` → 先按宽度截断（末段省略号），**再**计算纹理尺寸。
   */
  static newInstanceLimited(text: string, textSize: number, color: number,
    lengthLimit: number, isBold: boolean, factory: TextPaintFactoryLike,
    offscreen: OffscreenCanvasLike): StringTexture {
    const paint: TextPaintLike = StringTexture.getDefaultPaint(factory, textSize, color);
    if (isBold) {
      paint.setBold(true);
    }
    let finalText: string = text;
    if (lengthLimit > 0) {
      finalText = paint.ellipsize(text, lengthLimit);
    }
    return StringTexture.newInstanceWithPaint(finalText, paint, offscreen);
  }

  private static newInstanceWithPaint(text: string, paint: TextPaintLike,
    offscreen: OffscreenCanvasLike): StringTexture {
    const metrics: FontMetricsLike = paint.getFontMetrics();
    let width: number = Math.ceil(paint.measureText(text));
    let height: number = metrics.bottom - metrics.top;
    // The texture size needs to be at least 1x1.
    if (width <= 0) {
      width = 1;
    }
    if (height <= 0) {
      height = 1;
    }
    return new StringTexture(text, paint, metrics, width, height, offscreen);
  }

  /** 当前文字（测试用；上游是 private）。 */
  getText(): string {
    return this.mText;
  }

  /** 行高（测试用）。 */
  getMetrics(): FontMetricsLike {
    return this.mMetrics;
  }

  protected onDraw(canvas: OffscreenDrawingContext, backing: Object): void {
    // 上游：canvas.translate(0, -mMetrics.ascent) 然后 drawText(text, 0, 0, paint)
    canvas.translate(0, -this.mMetrics.ascent);
    canvas.drawText(this.mText, 0, 0, this.mPaint);
  }
}

/**
 * 文字 paint 工厂（宿主实现）。上游 `getDefaultPaint` 里做三件事：
 * `setTextSize` / `setAntiAlias(true)` / `setColor` / `setShadowLayer(2,0,0,BLACK)`。
 * 鸿蒙侧 paint 对象类型不同，故用工厂产出一个满足 `TextPaintLike` 的实现。
 */
export interface TextPaintFactoryLike {
  createDefaultPaint(textSize: number, color: number): TextPaintLike;
}
