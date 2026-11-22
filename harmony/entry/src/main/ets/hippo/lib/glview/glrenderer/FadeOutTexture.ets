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
 * `com.hippo.lib.glview.glrenderer.FadeOutTexture` 的 ArkTS 等价实现（inventory S0341）。
 *
 * 语义：从给定纹理**淡出到完全透明**。
 *
 * 一个反直觉但必须照搬的行为：**不在动画中时什么都不画**（不是画原纹理）。
 * 上游 `draw` 里整个绘制都在 `if (isAnimating())` 里，动画结束后调用 equals 于透明。
 */
export class FadeOutTexture extends FadeTexture {
  private readonly mTexture: BasicDrawTexture;

  constructor(texture: BasicDrawTexture) {
    super(texture.getWidth(), texture.getHeight(), texture.isOpaque());
    this.mTexture = texture;
  }

  protected drawImpl(canvas: GLCanvas, a: number | RectF, b: number | RectF | number,
    w: number, h: number): void {
    if (this.isAnimating()) {
      canvas.save(GLCanvas.SAVE_FLAG_ALPHA);
      canvas.setAlpha(this.getRatio());
      if (typeof a === 'number') {
        this.mTexture.draw(canvas, a, b as number, w, h);
      } else {
        this.mTexture.draw(canvas, a, b as RectF);
      }
      canvas.restore();
    }
  }
}

/** FadeOutTexture 需要的子纹理形状（上游是 `BasicTexture`；用接口避免把继承树钉死）。 */
export interface BasicDrawTexture {
  getWidth(): number;

  getHeight(): number;

  isOpaque(): boolean;

  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, c?: number, d?: number): void;
}
