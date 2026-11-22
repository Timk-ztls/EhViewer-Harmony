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

import { Rect } from '../util/Rect';
import { CollectionUtils } from '../../yorozuya/collect/CollectionUtils';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { MovableTextTexture } from '../glrenderer/MovableTextTexture';
import { GLView } from '../view/GLView';
import { Gravity } from '../view/Gravity';

/**
 * `com.hippo.lib.glview.widget.GLMovableTextView` 的 ArkTS 等价实现（inventory S0384）。
 *
 * 语义：用 `MovableTextTexture` 显示一段文字（字符图集逐字画），支持 gravity 对齐。
 *
 * ## 六处照搬
 *   1. `generateIndexes()`：纹理为 null 或文字为空 → **索引数组重置为空数组**（不是 null）
 *   2. `setText(null)` **视为空串**；`setText` 内容相同则**直接返回**（不重排）
 *   3. `setTextTexture` 同一个纹理对象则直接返回
 *   4. `setGravity` 只在值变化时 `invalidate()`
 *   5. `getSuggestedMinimumWidth/Height`：**与父类值取 max**（不是替换）
 *   6. `onRender`：`mTextTexture == null || mIndexes == null` 直接返回；
 *      否则用 `getDefaultBegin(...)` 算 x/y 再 `drawText(canvas, mIndexes, x, y)`
 *
 * 注意 `mIndexes` 初值是 `CollectionUtils.EMPTY_INT_ARRAY`（空数组，**不是 null**）——
 * 所以 `onRender` 里的 `mIndexes == null` 分支在当前实现下不可达（守住上游写法）。
 */
export class GLMovableTextView extends GLView {
  private mTextTexture: MovableTextTexture | null = null;
  private mText: string = '';
  private mIndexes: number[] | null = CollectionUtils.EMPTY_INT_ARRAY;
  private mGravity: number = Gravity.NO_GRAVITY;

  /** 对齐 `generateIndexes()`。 */
  private generateIndexes(): void {
    if (this.mTextTexture === null || this.mText.length === 0) {
      this.mIndexes = CollectionUtils.EMPTY_INT_ARRAY;
    } else {
      this.mIndexes = this.mTextTexture.getTextIndexes(this.mText);
    }
  }

  /** 对齐 `setTextTexture(textTexture)`。 */
  setTextTexture(textTexture: MovableTextTexture | null): void {
    if (this.mTextTexture === textTexture) {
      return;
    }
    this.mTextTexture = textTexture;
    this.generateIndexes();
    this.requestLayout();
  }

  /** 对齐 `setText(text)`：**null 视为空串**；相同则跳过。 */
  setText(text: string | null): void {
    let t: string = text === null ? '' : text;
    if (t === this.mText) {
      return;
    }
    this.mText = t;
    this.generateIndexes();
    this.requestLayout();
  }

  /** 对齐 `setGravity(gravity)`：只在变化时 invalidate。 */
  setGravity(gravity: number): void {
    if (this.mGravity !== gravity) {
      this.mGravity = gravity;
      this.invalidate();
    }
  }

  /** 测试用：当前文字。 */
  getText(): string {
    return this.mText;
  }

  /** 测试用：当前索引数组。 */
  getIndexes(): number[] | null {
    return this.mIndexes;
  }

  /** 测试用：当前 gravity。 */
  getGravity(): number {
    return this.mGravity;
  }

  /** 测试用：当前纹理。 */
  getTextTexture(): MovableTextTexture | null {
    return this.mTextTexture;
  }

  /** 对齐 `getSuggestedMinimumWidth()`：与父类值**取 max**。 */
  protected getSuggestedMinimumWidth(): number {
    const base: number = super.getSuggestedMinimumWidth();
    if (this.mTextTexture === null) {
      return base;
    }
    const textWidth: number = this.mTextTexture.getTextWidthOfIndexes(
      this.mIndexes === null ? [] : this.mIndexes);
    return Math.max(Math.floor(textWidth) + this.mPaddings.left + this.mPaddings.right, base);
  }

  /** 对齐 `getSuggestedMinimumHeight()`：与父类值**取 max**。 */
  protected getSuggestedMinimumHeight(): number {
    const base: number = super.getSuggestedMinimumHeight();
    if (this.mTextTexture === null) {
      return base;
    }
    return Math.max(Math.floor(this.mTextTexture.getTextHeight())
      + this.mPaddings.top + this.mPaddings.bottom, base);
  }

  /** 对齐 `onRender(canvas)`。 */
  onRender(canvas: GLCanvas): void {
    const texture: MovableTextTexture | null = this.mTextTexture;
    const indexes: number[] | null = this.mIndexes;
    if (texture === null || indexes === null) {
      return;
    }
    const paddings: Rect = this.getPaddings();
    const x: number = GLView.getDefaultBegin(this.getWidth(),
      Math.floor(texture.getTextWidthOfIndexes(indexes)),
      paddings.left, paddings.right, Gravity.getPosition(this.mGravity, Gravity.HORIZONTAL));
    const y: number = GLView.getDefaultBegin(this.getHeight(),
      Math.floor(texture.getTextHeight()),
      paddings.top, paddings.bottom, Gravity.getPosition(this.mGravity, Gravity.VERTICAL));
    texture.drawTextOfIndexes(canvas, indexes, x, y);
  }
}
