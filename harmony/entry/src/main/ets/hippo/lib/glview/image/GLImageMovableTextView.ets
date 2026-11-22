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

import { Rect } from '../util/Rect';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { GLView } from '../view/GLView';
import { Gravity } from '../view/Gravity';
import { ImageMovableTextTexture } from './ImageMovableTextTexture';

/**
 * `com.hippo.lib.glview.image.GLImageMovableTextView` 的 ArkTS 等价实现。
 *
 * 用"图片式字符图集"（`ImageMovableTextTexture`）画文字的轻量视图。
 * 相比系统排版，它能在 GL 渲染管线里**零额外纹理上传**地画文字
 * （整个字符集一张图集，每个字符一个 sprite）。
 *
 * ## 索引缓存
 * `setText` / `setTextTexture` 都会重新 `generateIndexes()`：
 * 把字符串转成"图集索引数组"，渲染时只做 `drawSprite` + 累加 advance。
 * 找不到的字符索引为负（`binarySearch` 未命中），渲染时**跳过但占位**（累加 `mMaxWidth`）。
 */
export class GLImageMovableTextView extends GLView {
  private mTextTexture: ImageMovableTextTexture | null = null;

  private mText: string = '';
  private mIndexes: number[] = [];

  private mGravity: number = Gravity.NO_GRAVITY;

  private generateIndexes(): void {
    const texture = this.mTextTexture;
    if (texture === null || this.mText.length === 0) {
      this.mIndexes = [];
    } else {
      this.mIndexes = texture.getTextIndexes(this.mText);
    }
  }

  setTextTexture(textTexture: ImageMovableTextTexture | null): void {
    if (this.mTextTexture === textTexture) {
      return;
    }
    this.mTextTexture = textTexture;
    this.generateIndexes();
    this.requestLayout();
  }

  getTextTexture(): ImageMovableTextTexture | null {
    return this.mTextTexture;
  }

  setText(text: string | null): void {
    const t = text === null ? '' : text;
    if (t === this.mText) {
      return;
    }
    this.mText = t;
    this.generateIndexes();
    this.requestLayout();
  }

  getText(): string {
    return this.mText;
  }

  setGravity(gravity: number): void {
    if (this.mGravity !== gravity) {
      this.mGravity = gravity;
      this.invalidate();
    }
  }

  protected getSuggestedMinimumWidth(): number {
    const texture = this.mTextTexture;
    if (texture === null) {
      return super.getSuggestedMinimumWidth();
    }
    return Math.max(Math.trunc(texture.getTextWidthByIndexes(this.mIndexes))
      + this.mPaddings.left + this.mPaddings.right, super.getSuggestedMinimumWidth());
  }

  protected getSuggestedMinimumHeight(): number {
    const texture = this.mTextTexture;
    if (texture === null) {
      return super.getSuggestedMinimumHeight();
    }
    return Math.max(Math.trunc(texture.getTextHeight())
      + this.mPaddings.top + this.mPaddings.bottom, super.getSuggestedMinimumHeight());
  }

  onRender(canvas: GLCanvas): void {
    const texture = this.mTextTexture;
    if (texture === null) {
      return;
    }

    const paddings: Rect = this.getPaddings();
    const x = GLView.getDefaultBegin(this.getWidth(),
      Math.trunc(texture.getTextWidthByIndexes(this.mIndexes)),
      paddings.left, paddings.right, Gravity.getPosition(this.mGravity, Gravity.HORIZONTAL));
    const y = GLView.getDefaultBegin(this.getHeight(),
      Math.trunc(texture.getTextHeight()),
      paddings.top, paddings.bottom, Gravity.getPosition(this.mGravity, Gravity.VERTICAL));
    texture.drawTextByIndexes(canvas, this.mIndexes, x, y);
  }
}
