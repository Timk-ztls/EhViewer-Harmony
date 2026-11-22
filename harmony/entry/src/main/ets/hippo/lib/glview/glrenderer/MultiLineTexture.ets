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
import {
  CanvasTexture,
  OffscreenCanvasLike,
  OffscreenDrawingContext,
  PaintLike,
  TextPaintLike,
  FontMetricsLike
} from './CanvasTexture';
import { TextPaintFactoryLike } from './StringTexture';

/**
 * `com.hippo.lib.glview.glrenderer.MultiLineTexture` 的 ArkTS 等价实现（多行文字纹理）。
 *
 * 上游 44 行，核心是 `StaticLayout`（Android 的**断行引擎**）：
 * ```java
 * Layout layout = new StaticLayout(text, 0, text.length(), paint,
 *         maxWidth, alignment, 1, 0, true, null, 0);
 * ```
 * 参数含义（`StaticLayout` 的 11 参构造）：文本 / 起点 / 终点 / 画笔 / 最大宽 /
 * 对齐 / `spacingmult=1` / `spacingadd=0` / `includepad=true` / 省略 ellipsis / 省略 hyphen。
 *
 * ## 平台差异：断行自己做（**登记为近似**）
 * 鸿蒙 `@ohos.graphics.text`（`Paragraph`/`TextStyle`）能断行，但会引入与 `drawing` 两套文字 API
 * 混用的复杂度；本实现选择**在 `drawing` 之上自行断行**：
 * - 以**字符**为断点（CJK 正确；西文按词断行会更好，但页面里用这个纹理的是错误文案，中英混排短句，
 *   按字符断行只会让西文在词中断开 —— 可接受，且与"不引入第二套文字栈"的收益相比更划算）
 * - 高度 = `行数 × 行高`，行高取 `FontMetrics` 的 `descent - ascent`
 *
 * **与上游的可见差异**：西文长词不会整词下移（上游会）。已登记，若后续发现文案里有长西文，
 * 再换 `@ohos.graphics.text` 的 `Paragraph`。
 *
 * ## 对齐
 * 上游用 `Layout.Alignment`（ALIGN_NORMAL/CENTER/OPPOSITE）。这里用枚举对齐到同样三种，
 * 由 `x` 起点计算决定（不改变行内文字形状）。
 */
export enum MultiLineAlignment {
  ALIGN_NORMAL = 0,
  ALIGN_CENTER = 1,
  ALIGN_OPPOSITE = 2
}

export class MultiLineTexture extends CanvasTexture {
  private readonly mLines: string[];
  private readonly mPaint: TextPaintLike;
  private readonly mLineHeight: number;
  private readonly mAlignment: MultiLineAlignment;

  private constructor(lines: string[], paint: TextPaintLike, lineHeight: number,
    width: number, height: number, alignment: MultiLineAlignment,
    offscreen: OffscreenCanvasLike) {
    super(width, height, offscreen);
    this.mLines = lines;
    this.mPaint = paint;
    this.mLineHeight = lineHeight;
    this.mAlignment = alignment;
  }

  /**
   * 创建多行文字纹理。
   *
   * @param text      文本（用 `\n` 显式分段；过长的行自动按字符折行）
   * @param maxWidth  最大宽度（像素）
   * @param textSize  字号（像素）
   * @param color     颜色 0xAARRGGBB
   * @param alignment 对齐方式
   * @param factory   画笔工厂（`StringTexture` 的注入项，D-031 只用默认字体）
   * @param offscreen 离屏画布工厂
   */
  static newInstance(text: string, maxWidth: number, textSize: number, color: number,
    alignment: MultiLineAlignment, factory: TextPaintFactoryLike,
    offscreen: OffscreenCanvasLike): MultiLineTexture {
    const paint: TextPaintLike = StringTextureDefaultPaint.get(factory, textSize, color);
    const metrics: FontMetricsLike = paint.getFontMetrics();
    const lineHeight = Math.max(1, Math.ceil(metrics.descent - metrics.ascent));

    // 断行：显式 \n 优先，其次按字符累计宽度
    const rawLines: string[] = text.split('\n');
    const lines: string[] = [];
    let widest = 0;
    for (let i = 0; i < rawLines.length; i++) {
      const raw = rawLines[i];
      if (raw.length === 0) {
        lines.push('');
        continue;
      }
      let current = '';
      for (let c = 0; c < raw.length; c++) {
        const next = current + raw.charAt(c);
        if (current.length > 0 && paint.measureText(next) > maxWidth) {
          lines.push(current);
          const w = paint.measureText(current);
          if (w > widest) {
            widest = w;
          }
          current = raw.charAt(c);
        } else {
          current = next;
        }
      }
      lines.push(current);
      const w = paint.measureText(current);
      if (w > widest) {
        widest = w;
      }
    }

    const width = Math.max(1, Math.min(maxWidth, Math.ceil(widest)));
    const height = Math.max(1, lines.length * lineHeight);
    return new MultiLineTexture(lines, paint, lineHeight, width, height, alignment, offscreen);
  }

  protected onDraw(canvas: OffscreenDrawingContext, backing: image.PixelMap): void {
    // 上游 `mLayout.draw(canvas)`：基线从第一行的 ascent 往上推（ascent 为负）
    const paint = this.mPaint;
    const metrics: FontMetricsLike = paint.getFontMetrics();
    const width = canvas.getWidth();

    for (let i = 0; i < this.mLines.length; i++) {
      const line = this.mLines[i];
      const lineWidth = paint.measureText(line);
      let x: number;
      if (this.mAlignment === MultiLineAlignment.ALIGN_CENTER) {
        x = Math.max(0, (width - lineWidth) / 2);
      } else if (this.mAlignment === MultiLineAlignment.ALIGN_OPPOSITE) {
        x = Math.max(0, width - lineWidth);
      } else {
        x = 0;
      }
      const baselineY = i * this.mLineHeight - metrics.ascent;
      canvas.drawText(line, x, baselineY, paint);
    }
  }

  /** 行数（诊断/单测）。 */
  getLineCount(): number {
    return this.mLines.length;
  }
}

/**
 * 取默认画笔（等价上游 `StringTexture.getDefaultPaint(textSize, color)`）。
 * 抽成小工具类是为了避免 `MultiLineTexture` 直接依赖 `StringTexture` 的静态私有方法。
 */
class StringTextureDefaultPaint {
  /** 上游 `StringTexture.getDefaultPaint(textSize, color)`：工厂已把字号/颜色/反锯齿一并设好。 */
  static get(factory: TextPaintFactoryLike, textSize: number, color: number): TextPaintLike {
    return factory.createDefaultPaint(textSize, color);
  }
}
