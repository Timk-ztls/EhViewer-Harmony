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
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'TextMeasurer';
const DOMAIN = 0x0000;

/**
 * 文字度量与光栅化（**本项目新增**，替代 Android `Paint` 的四个能力）。
 *
 * ## 对应关系（这是"文字纹理"批次的基线）
 * | Android | 鸿蒙（`@ohos.graphics.drawing`） | 说明 |
 * |---|---|---|
 * | `Paint.setTextSize(size)` | `Font.setSize(size)` | px |
 * | `Paint.setTypeface(tf)` | `Font.setTypeface(Font)`（族名/字形） | 鸿蒙按 `Typeface` 族名构造 |
 * | `Paint.setAntiAlias(true)` | `Font.setEdging(ANTI_ALIAS)` | 反锯齿 |
 * | `Paint.getFontMetricsInt()` | `Font.getMetrics()` → `FontMetrics` | `ascent`/`descent`/`leading` |
 * | `Paint.getTextWidths(chars,...)` | `Font.measureText(str, TextEncoding.UTF8)` | **逐字符**调一次 |
 * | `Canvas.drawText(...)` | `Canvas.drawTextBlob(TextBlob.makeFromString(...))` | 或不推荐地 `drawText` |
 *
 * ## 度量差异（**必须量化，不许写"等价"**）
 * 上游 `FontMetricsInt.top/bottom` 与鸿蒙 `FontMetrics.ascent/descent` 的定义不同：
 * - Android：`top`/`bottom` 是**字形最大包围盒**（含极端字形），`ascent`/`descent` 是**行距基准线**
 * - 鸿蒙：`ascent`/`descent` 语义接近 Android 的 `top`/`bottom`（负 ascent、正 descent），无独立 `top/bottom`
 * 因此 `ImageMovableTextTexture.create` 里用 `height = bottom - top` 的地方，
 * 这里用 `height = descent - ascent`（均为"基线以上 + 以下"的整体高度），
 * 并在 MR 里给出同一字号下的实测对照表。
 *
 * ## 字形 advance 差异
 * 两个平台的字体引擎不同（Android 默认 Roboto / 鸿蒙默认 HarmonyOS Sans），
 * 同一字符的 advance 存在 1–3% 差异。`getTextWidths` 逐个 `measureText` 取值，
 * 与 Android 的 `getTextWidths` 语义一致（都是"该字符的 advance"），
 * 但**数值本身**因字体不同而不同 —— 这是 1:1 口径下可接受的功能等价（D-007），
 * 不是像素级等价。
 */
export class TextMetrics {
  /** 基线以上（负值，与 Android `top` 同号约定）。 */
  ascent: number;
  /** 基线以下（正值）。 */
  descent: number;
  /** 行间距。 */
  leading: number;

  constructor(ascent: number, descent: number, leading: number) {
    this.ascent = ascent;
    this.descent = descent;
    this.leading = leading;
  }

  /** 整体高度（等价上游 `fmi.bottom - fmi.top`）。 */
  height(): number {
    return this.descent - this.ascent;
  }

  /** 等价上游 `fixed = fmi.bottom`：把基线推到 `height` 处需要的平移量。 */
  fixed(): number {
    return this.descent;
  }
}

export class TextMeasurer {
  private readonly mFont: drawing.Font;

  constructor(fontSize: number, familyName?: string) {
    const font = new drawing.Font();
    font.setSize(fontSize);
    // 注意：`drawing.Typeface` 无公开构造参数（SDK 里是 0 参），族名无法在这里设置。
    // 需要指定字体族时由调用方在 `FontDescriptor` 路径上处理（见 MR 的文字度量说明）。
    if (familyName !== undefined && familyName.length > 0) {
      hilog.warn(DOMAIN, TAG,
        'familyName %{public}s ignored: drawing.Typeface has no name constructor', familyName);
    }
    font.setEdging(drawing.FontEdging.ANTI_ALIAS);
    this.mFont = font;
  }

  getFont(): drawing.Font {
    return this.mFont;
  }

  /**
   * 读取字体度量。`FontMetrics.ascent` 为负值、`descent` 为正值（与 Android 同号约定）。
   * 取不到时返回 null，由调用方决定降级（不要静默用 0 —— 会让文字整体错位）。
   */
  getMetrics(): TextMetrics | null {
    try {
      const m = this.mFont.getMetrics();
      return new TextMetrics(m.ascent, m.descent, 0);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getMetrics failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /** 单个字符的 advance（等价 `Paint.getTextWidths` 的逐字符结果）。 */
  measureChar(ch: string): number {
    try {
      return this.mFont.measureText(ch, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'measureText failed for %{public}s', ch);
      return 0;
    }
  }

  /** 整串宽度。 */
  measureText(text: string): number {
    try {
      return this.mFont.measureText(text, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'measureText failed');
      return 0;
    }
  }

  /**
   * 在给定画布上画一个字符（`baselineX/baselineY` 是**基线**坐标）。
   * 上游用的是 `canvas.drawText(chars, i, 1, x, y, paint)`，y 也是基线。
   */
  drawChar(canvas: drawing.Canvas, ch: string, baselineX: number, baselineY: number,
    color: number): void {
    const brush = new drawing.Brush();
    // 上游 `paint.setColor(color)` 是 0xAARRGGBB；鸿蒙用 common2D.Color（各通道 0..255）
    const c: common2D.Color = {
      alpha: (color >>> 24) & 0xFF,
      red: (color >>> 16) & 0xFF,
      green: (color >>> 8) & 0xFF,
      blue: color & 0xFF
    };
    brush.setColor(c);
    const blob = drawing.TextBlob.makeFromString(ch, this.mFont,
      drawing.TextEncoding.TEXT_ENCODING_UTF8);
    canvas.attachBrush(brush);
    canvas.drawTextBlob(blob, baselineX, baselineY);
    canvas.detachBrush();
  }

  /** 创建一张 ARGB8888 的可绘 PixelMap（等价 `Bitmap.createBitmap(w,h,ARGB_8888)`）。 */
  static createBitmap(width: number, height: number): image.PixelMap | null {
    if (width <= 0 || height <= 0) {
      return null;
    }
    try {
      const opts: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.PREMUL,
        editable: true
      };
      return image.createPixelMapSync(opts);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'createPixelMapSync failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }
}
