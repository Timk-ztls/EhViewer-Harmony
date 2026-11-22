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

import { RectF } from '../util/RectF';
import { GLCanvas } from './GLCanvas';
import { FadeTexture } from './FadeTexture';

/**
 * `com.hippo.lib.glview.glrenderer.FadeInTexture` 的 ArkTS 等价实现（inventory S0340）。
 *
 * 语义：从**纯色**开始，逐渐过渡到给定纹理。
 *
 * 与 FadeOutTexture 的对称差异（照搬）：
 *   - 动画中走 `drawMixed(canvas, color, ratio, …)`（在纹理与颜色间插值）
 *   - 动画**结束**后画**原纹理**（不是什么都不画）
 */
export class FadeInTexture extends FadeTexture {
  private readonly mColor: number;
  private readonly mTexture: MixedDrawTexture;

  constructor(color: number, texture: MixedDrawTexture) {
    super(texture.getWidth(), texture.getHeight(), texture.isOpaque());
    this.mColor = color;
    this.mTexture = texture;
  }

  protected drawImpl(canvas: GLCanvas, a: number | RectF, b: number | RectF | number,
    w: number, h: number): void {
    if (this.isAnimating()) {
      if (typeof a === 'number') {
        this.mTexture.drawMixed(canvas, this.mColor, this.getRatio(), a, b as number, w, h);
      } else {
        this.mTexture.drawMixed(canvas, this.mColor, this.getRatio(), a, b as RectF);
      }
    } else {
      if (typeof a === 'number') {
        this.mTexture.draw(canvas, a, b as number, w, h);
      } else {
        this.mTexture.draw(canvas, a, b as RectF);
      }
    }
  }
}

/**
 * FadeInTexture 需要的子纹理形状（上游是 `TiledTexture`）。
 * ArkTS 不支持重载，`draw` / `drawMixed` 各自用「可选参数 + 联合类型」表达两组重载。
 */
export interface MixedDrawTexture {
  getWidth(): number;

  getHeight(): number;

  isOpaque(): boolean;

  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, c?: number, d?: number): void;

  drawMixed(canvas: GLCanvas, color: number, ratio: number,
    a: number | RectF, b: number | RectF, c?: number, d?: number): void;
}
