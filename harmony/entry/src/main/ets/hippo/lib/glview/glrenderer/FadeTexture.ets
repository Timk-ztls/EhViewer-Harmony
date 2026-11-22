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

import { AnimationTime } from '../view/AnimationTime';
import { MathUtils } from '../../yorozuya/MathUtils';
import { RectF } from '../util/RectF';
import { GLCanvas } from './GLCanvas';
import { Texture } from './Texture';

/**
 * `com.hippo.lib.glview.glrenderer.FadeTexture` 的 ArkTS 等价实现（inventory S0342）。
 *
 * 语义：淡入/淡出的**时间轴基类**。它不持有子纹理，只负责两件事：
 *   - `isAnimating()`：是否还在动画中
 *   - `getRatio()`：**剩余**比例（1 = 刚开始，0 = 结束）
 * 子类（FadeInTexture / FadeOutTexture）决定拿这个比例做什么。
 *
 * 三处容易写错的地方，逐条照搬上游：
 *   1. `DURATION = 180ms` 是**常量**，不跟随时长设置
 *   2. `isAnimating()` 是**惰性状态机**：第一次发现超过 DURATION 才把 `mIsAnimating` 置 false
 *      （所以「动画结束」只在被询问时被观察到，不自行触发回调）
 *   3. `getRatio()` 返回 `1 - elapsed/DURATION` 并 clamp 到 [0,1] —— 名字叫 ratio，语义是「还剩多少」
 */
export abstract class FadeTexture implements Texture {
  /** 淡入淡出时长（毫秒）。上游 `public static final int DURATION = 180;`。 */
  static readonly DURATION: number = 180;

  private readonly mStartTime: number;
  private readonly mWidth: number;
  private readonly mHeight: number;
  private readonly mIsOpaque: boolean;
  private mIsAnimating: boolean;

  protected constructor(width: number, height: number, opaque: boolean) {
    this.mWidth = width;
    this.mHeight = height;
    this.mIsOpaque = opaque;
    this.mStartTime = AnimationTime.get();
    this.mIsAnimating = true;
  }

  /** 三合一入口，与 `BasicTexture.draw` 同一套运行时分派约定。 */
  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, w?: number, h?: number): void {
    if (typeof a === 'number') {
      if (w === undefined || h === undefined) {
        // 上游：draw(canvas, x, y) → draw(canvas, x, y, mWidth, mHeight)
        this.drawImpl(canvas, a, b as number, this.mWidth, this.mHeight);
      } else {
        this.drawImpl(canvas, a, b as number, w, h);
      }
    } else {
      this.drawImpl(canvas, a, b as RectF, 0, 0);
    }
  }

  /** 子类实现绘制。数值形态（x,y,w,h）与矩形形态（source,target）共用一个入口，用 `a` 的类型区分。 */
  protected abstract drawImpl(canvas: GLCanvas, a: number | RectF, b: number | RectF | number,
    w: number, h: number): void;

  isOpaque(): boolean {
    return this.mIsOpaque;
  }

  getWidth(): number {
    return this.mWidth;
  }

  getHeight(): number {
    return this.mHeight;
  }

  /** 惰性判定：超过 DURATION 才把状态置 false（只置一次）。 */
  isAnimating(): boolean {
    if (this.mIsAnimating) {
      if (FadeTexture.now() - this.mStartTime >= FadeTexture.DURATION) {
        this.mIsAnimating = false;
      }
    }
    return this.mIsAnimating;
  }

  /** **剩余**比例（1 = 刚开始，0 = 结束），clamp 到 [0,1]。 */
  protected getRatio(): number {
    const r: number = (FadeTexture.now() - this.mStartTime) / FadeTexture.DURATION;
    return MathUtils.clamp(1.0 - r, 0.0, 1.0);
  }

  /** 动画时间源。抽出成 static 便于测试用 `AnimationTime.update()` 驱动。 */
  protected static now(): number {
    return AnimationTime.get();
  }
}
