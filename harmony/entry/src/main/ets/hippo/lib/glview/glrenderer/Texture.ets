/*
 * Copyright (C) 2010 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { RectF } from '../util/RectF';
import { GLCanvas } from './GLCanvas';

/**
 * `com.hippo.lib.glview.glrenderer.Texture` 的 ArkTS 等价实现。
 *
 * 上游是 interface，且 `draw` 有三组重载。ArkTS 的 interface 同样不支持重载，
 * 统一为"可选参数 + 联合类型"，调用点 `texture.draw(canvas, x, y)`、
 * `texture.draw(canvas, x, y, w, h)`、`texture.draw(canvas, source, target)` 写法不变。
 *
 * 纹理继承树（上游注释原样保留，用于对照）：
 * ```
 * Texture
 * -- ColorTexture
 * -- FadeInTexture
 * -- BasicTexture
 *    -- UploadedTexture
 *       -- BitmapTexture
 *       -- Tile
 *       -- ResourceTexture
 *          -- NinePatchTexture
 *       -- CanvasTexture
 *          -- StringTexture
 * ```
 */
export interface Texture {
  getWidth(): number;

  getHeight(): number;

  /**
   * 三合一绘制入口：
   * 1. `draw(canvas, x, y)` —— 按纹理自身尺寸画到 (x,y)
   * 2. `draw(canvas, x, y, w, h)` —— 缩放到 (w,h)
   * 3. `draw(canvas, source: RectF, target: RectF)` —— 指定源/目标矩形
   */
  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, c?: number, d?: number): void;

  isOpaque(): boolean;
}
