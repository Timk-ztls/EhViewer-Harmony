/*
 * Copyright 2024 Hippo Seven
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
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  OffscreenCanvasLike,
  OffscreenDrawingContext,
  PaintLike,
  TextPaintLike,
  FontMetricsLike,
  RectLike
} from './CanvasTexture';
import { TextPaintFactoryLike } from './StringTexture';

const TAG = 'DrawingText';
const DOMAIN = 0x0000;

/**
 * `TextPaintLike` 的 `@ohos.graphics.drawing` 实现（等价 Android `TextPaint`）。
 *
 * ## 为什么需要这一层
 * `StringTexture` / `MultiLineTexture` / `CanvasTexture` 三处都依赖
 * 「把文字画进一张离屏位图」的能力，而鸿蒙侧这件事要 `drawing.Font` + `drawing.Canvas`。
 * 上游这些是 Android 框架自带（`TextPaint` + `Canvas` + `Bitmap`），本项目把它们抽成两个接缝
 * （`TextPaintFactoryLike` / `OffscreenCanvasLike`）由本文件实现。
 *
 * ## 度量字段的对位（D-031/D-056 相关）
 * `FontMetricsLike` 要 4 个字段（`top`/`ascent`/`descent`/`bottom`），而鸿蒙
 * `drawing.FontMetrics` 只给 `ascent`/`descent`（+ 可选 `leading`）。对位方式：
 * | 字段 | 取值 | 说明 |
 * |---|---|---|
 * | `ascent` | `FontMetrics.ascent`（负值） | 直接对应 |
 * | `descent` | `FontMetrics.descent`（正值） | 直接对应 |
 * | `top` | 取 `ascent` | 鸿蒙无"字形最大包围盒"独立字段；用 `ascent` 保守近似 |
 * | `bottom` | 取 `descent` | 同上 |
 *
 * **差异已登记**：`top/bottom` 在 Android 是"极端字形包围盒"，可能比 `ascent/descent` 更外扩。
 * 我们的取值让**行高偏小**（不会切字，只是上下留白略少）—— 这是"少留白"而不是"切掉字形"，
 * 属 D-031 的同类（字体度量口径不同）。
 *
 * ## 文字绘制
 * `drawText(text, x, y, paint)` 里 `y` 是**基线**（与 Android 一致）。
 * 用 `TextBlob.makeFromString(text, font, TEXT_ENCODING_UTF8)` + `canvas.drawTextBlob`。
 */
export class DrawingTextPaint implements TextPaintLike {
  private mFont: drawing.Font;
  private mColor: number;
  private mTextSize: number;
  private mAntiAlias: boolean = true;
  private mBold: boolean = false;
  /** 测量缓存：`measureText` 在同一次布局里会被调很多次（逐字符断行）。 */
  private readonly mMeasureCache: Map<string, number> = new Map<string, number>();

  constructor(textSize: number, color: number) {
    this.mTextSize = textSize;
    this.mColor = color;
    const font = new drawing.Font();
    font.setSize(textSize);
    font.setEdging(drawing.FontEdging.ANTI_ALIAS);
    this.mFont = font;
  }

  getFont(): drawing.Font {
    return this.mFont;
  }

  /** 内部：把 `0xAARRGGBB` 转成 `common2D.Color`（各通道 0..255）。 */
  static toCommonColor(color: number): common2D.Color {
    const c: common2D.Color = {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
    return c;
  }

  getColor(): number {
    return this.mColor;
  }

  setColor(color: number): void {
    this.mColor = color;
  }

  getStrokeWidth(): number {
    // TextPaint 的 stroke 语义不用于文字填充，保留 0（等价上游未设置时的默认）
    return 0;
  }

  setStrokeWidth(width: number): void {
    // 文字填充不受影响（上游 `TextPaint.setStrokeWidth` 在 `Style.FILL` 下也无效）
  }

  getTextSize(): number {
    return this.mTextSize;
  }

  setTextSize(size: number): void {
    this.mTextSize = size;
    this.mFont.setSize(size);
    this.mMeasureCache.clear();
  }

  isAntiAlias(): boolean {
    return this.mAntiAlias;
  }

  setAntiAlias(antiAlias: boolean): void {
    this.mAntiAlias = antiAlias;
    this.mFont.setEdging(antiAlias ? drawing.FontEdging.ANTI_ALIAS : drawing.FontEdging.ALIAS);
  }

  measureText(text: string): number {
    const cached = this.mMeasureCache.get(text);
    if (cached !== undefined) {
      return cached;
    }
    let width = 0;
    try {
      width = this.mFont.measureText(text, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'measureText failed: %{public}s', JSON.stringify(err));
      width = 0;
    }
    this.mMeasureCache.set(text, width);
    return width;
  }

  getFontMetrics(): FontMetricsLike {
    try {
      const m = this.mFont.getMetrics();
      const metrics: FontMetricsLike = {
        // top/bottom 无独立字段 → 用 ascent/descent 近似（差异见类注释）
        top: m.ascent,
        ascent: m.ascent,
        descent: m.descent,
        bottom: m.descent
      };
      return metrics;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getMetrics failed: %{public}s', JSON.stringify(err));
      const fallback: FontMetricsLike = {
        top: -this.mTextSize,
        ascent: -this.mTextSize,
        descent: 0,
        bottom: this.mTextSize
      };
      return fallback;
    }
  }

  /**
   * 等价 `TextUtils.ellipsize(text, paint, maxWidth, TruncateAt.END)`：超宽时末尾加 `…`。
   * 按**字符**回退（与 D-056 同一取舍：不引入第二套排版栈）。
   */
  ellipsize(text: string, maxWidth: number): string {
    if (this.measureText(text) <= maxWidth) {
      return text;
    }
    const ELLIPSIS = '\u2026';
    const ellipsisWidth = this.measureText(ELLIPSIS);
    let lo = 0;
    let hi = text.length;
    let best = '';
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const candidate = text.substring(0, mid) + ELLIPSIS;
      if (this.measureText(candidate) <= maxWidth) {
        best = candidate;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (best.length === 0 && ellipsisWidth > maxWidth) {
      return '';
    }
    return best;
  }

  /**
   * 记录粗体状态。**当前不改变渲染**（D-068：`drawing.Font` 无 weight 能力）。
   * 保留该状态是为了：① 上游调用点零改动 ② 将来若 SDK 提供 weight，改这里一处即可。
   */
  setBold(bold: boolean): void {
    if (this.mBold === bold) {
      return;
    }
    this.mBold = bold;
    this.mMeasureCache.clear();
  }

  isBold(): boolean {
    return this.mBold;
  }

  /**
   * 按当前状态建一个用于绘制的 `Font`。
   *
   * **粗体（`mBold`）不改变渲染**：SDK 20 的 `drawing.Font` 只有
   * `setSize/setScaleX/setSkewX/setEdging/measureText/getScaleX`，**没有 `setBold`/`setWeight`/`setTypeface`**
   * （`FontDescriptor` 与 `drawing.FontWeight` 均不存在）。见 **D-068**。
   *
   * 为什么不"用 `setScaleX` 拉伸近似"：`measureText` 会跟着变，
   * 而 `MultiLineTexture` 的断行（D-056）依赖 `measureText` → 断行位置会错。
   * 宁可"粗体不生效"（错误文案里几乎不可见），也不要"断行错位"。
   */
  buildDrawFont(): drawing.Font {
    const font = new drawing.Font();
    font.setSize(this.mTextSize);
    font.setEdging(this.mAntiAlias ? drawing.FontEdging.ANTI_ALIAS : drawing.FontEdging.ALIAS);
    return font;
  }
}

/** `TextPaintFactoryLike` 的实现（等价上游 `new TextPaint()` 的默认配置）。 */
export class DrawingTextPaintFactory implements TextPaintFactoryLike {
  private static sInstance: DrawingTextPaintFactory | null = null;

  static getInstance(): DrawingTextPaintFactory {
    let instance = DrawingTextPaintFactory.sInstance;
    if (instance === null) {
      instance = new DrawingTextPaintFactory();
      DrawingTextPaintFactory.sInstance = instance;
    }
    return instance;
  }

  /** 上游 `StringTexture.getDefaultPaint(textSize, color)`：抗锯齿 + 指定字号颜色。 */
  createDefaultPaint(textSize: number, color: number): TextPaintLike {
    const paint = new DrawingTextPaint(textSize, color);
    paint.setAntiAlias(true);
    return paint;
  }
}

/**
 * `OffscreenCanvasLike` 的实现：把 `drawing.Canvas` 盖在 `image.PixelMap` 上。
 *
 * 对应关系：
 * | Android | 鸿蒙 |
 * |---|---|
 * | `Bitmap.createBitmap(w, h, ARGB_8888)` | `image.createPixelMapSync({ RGBA_8888, PREMUL })` |
 * | `new Canvas(bitmap)` | `new drawing.Canvas(pixelMap)` |
 */
export class DrawingOffscreenCanvas implements OffscreenCanvasLike {
  private static sInstance: DrawingOffscreenCanvas | null = null;

  static getInstance(): DrawingOffscreenCanvas {
    let instance = DrawingOffscreenCanvas.sInstance;
    if (instance === null) {
      instance = new DrawingOffscreenCanvas();
      DrawingOffscreenCanvas.sInstance = instance;
    }
    return instance;
  }

  createBitmap(width: number, height: number): image.PixelMap {
    const opts: image.InitializationOptions = {
      size: { width: Math.max(1, width), height: Math.max(1, height) },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.PREMUL,
      editable: true
    };
    return image.createPixelMapSync(opts);
  }

  createCanvas(bitmap: image.PixelMap): OffscreenDrawingContext {
    return new DrawingContext(new drawing.Canvas(bitmap), bitmap);
  }

  /** 便捷：一次拿到两个接缝（`GalleryView.setTextRendering` 直接可用）。 */
  static installGlobally(): void {
    // 由调用方（ui 层）注入到 GalleryView；这里只提供两个单例
    hilog.info(DOMAIN, TAG, 'DrawingText seams available');
  }
}

/**
 * `OffscreenDrawingContext` 的实现（`drawing.Canvas` 的薄包装）。
 *
 * `paint`（`TextPaintLike` / `PaintLike`）在本层被翻译成 `drawing.Brush`（填充）或
 * `drawing.Pen`（描边），每次绘制临时构造 —— 上游复用 `Paint` 对象，但 `drawing` 的
 * `attachBrush/detachBrush` 是配对的，临时构造更不容易漏 detach。
 */
export class DrawingContext implements OffscreenDrawingContext {
  private readonly mCanvas: drawing.Canvas;
  private readonly mBitmap: image.PixelMap;

  constructor(canvas: drawing.Canvas, bitmap: image.PixelMap) {
    this.mCanvas = canvas;
    this.mBitmap = bitmap;
  }

  getWidth(): number {
    return this.mBitmap.getImageInfoSync().size.width;
  }

  getHeight(): number {
    return this.mBitmap.getImageInfoSync().size.height;
  }

  /** 等价 `canvas.drawColor(int)`：整张填充（`0x00000000` = 透明清除）。 */
  drawColor(color: number): void {
    const brush = new drawing.Brush();
    brush.setColor(DrawingTextPaint.toCommonColor(color));
    this.mCanvas.attachBrush(brush);
    const w = this.getWidth();
    const h = this.getHeight();
    this.mCanvas.drawRect({ left: 0, top: 0, right: w, bottom: h });
    this.mCanvas.detachBrush();
  }

  /** 等价 `canvas.drawText(text, x, y, paint)`；`y` 是**基线**。 */
  drawText(text: string, x: number, y: number, paint: TextPaintLike): void {
    if (text.length === 0) {
      return;
    }
    const textPaint = paint instanceof DrawingTextPaint ? paint as DrawingTextPaint : null;
    const font = textPaint !== null ? textPaint.buildDrawFont() : new drawing.Font();
    const brush = new drawing.Brush();
    brush.setColor(DrawingTextPaint.toCommonColor(paint.getColor()));

    const blob = drawing.TextBlob.makeFromString(text, font,
      drawing.TextEncoding.TEXT_ENCODING_UTF8);
    this.mCanvas.attachBrush(brush);
    this.mCanvas.drawTextBlob(blob, x, y);
    this.mCanvas.detachBrush();
  }

  /** 等价 `canvas.drawBitmap(bitmap, src, dst)`；`src` 为 null 表示整图。 */
  drawBitmap(bitmap: image.PixelMap, src: RectLike | null, dst: RectLike): void {
    const srcRect: common2D.Rect = src === null
      ? {
        left: 0, top: 0,
        right: bitmap.getImageInfoSync().size.width,
        bottom: bitmap.getImageInfoSync().size.height
      }
      : { left: src.left, top: src.top, right: src.right, bottom: src.bottom };
    const dstRect: common2D.Rect = {
      left: dst.left, top: dst.top, right: dst.right, bottom: dst.bottom
    };
    this.mCanvas.drawImageRect(bitmap, srcRect, dstRect);
  }

  drawLine(x1: number, y1: number, x2: number, y2: number, paint: PaintLike): void {
    const pen = new drawing.Pen();
    pen.setColor(DrawingTextPaint.toCommonColor(paint.getColor()));
    pen.setStrokeWidth(paint.getStrokeWidth());
    this.mCanvas.attachPen(pen);
    this.mCanvas.drawLine(x1, y1, x2, y2);
    this.mCanvas.detachPen();
  }

  drawRect(left: number, top: number, right: number, bottom: number, paint: PaintLike): void {
    const brush = new drawing.Brush();
    brush.setColor(DrawingTextPaint.toCommonColor(paint.getColor()));
    this.mCanvas.attachBrush(brush);
    this.mCanvas.drawRect({ left: left, top: top, right: right, bottom: bottom });
    this.mCanvas.detachBrush();
  }

  translate(dx: number, dy: number): void {
    this.mCanvas.translate(dx, dy);
  }
}
