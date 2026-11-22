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

import { RectF } from '../util/RectF';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { Texture } from '../glrenderer/Texture';
import { GLView } from '../view/GLView';

/**
 * `com.hippo.lib.glview.widget.GLTextureView` 的 ArkTS 等价实现。
 *
 * 只做一件事：把一张 `Texture` 按 padding 内缩后铺满自身区域。
 * `GalleryPageView` 的"错误图标"就用它（`GLTextureView` + `ResourceTexture`）。
 *
 * ## 保留的上游 bug（**不要"修"**）
 * `getSuggestedMinimumHeight()` 里返回的是 `super.getSuggestedMinimumWidth()` ——
 * 复制粘贴错误。影响：有纹理时"建议最小高度"用了宽度值，会让某些布局里
 * 该视图的测量高度偏大。改对会改变布局尺寸，按 1:1 口径保留并标注。
 */
export class GLTextureView extends GLView {
  private readonly mSrc: RectF = new RectF();
  private readonly mDst: RectF = new RectF();

  private mTexture: Texture | null = null;

  setTexture(texture: Texture | null): void {
    this.mTexture = texture;
    if (texture !== null) {
      this.mSrc.set(0.0, 0.0, texture.getWidth(), texture.getHeight());
    } else {
      this.mSrc.setEmpty();
    }
    this.invalidate();
  }

  getTexture(): Texture | null {
    return this.mTexture;
  }

  protected getSuggestedMinimumWidth(): number {
    const texture = this.mTexture;
    return texture === null
      ? super.getSuggestedMinimumWidth()
      : texture.getWidth() + this.mPaddings.width();
  }

  protected getSuggestedMinimumHeight(): number {
    const texture = this.mTexture;
    // 上游此处误用 getSuggestedMinimumWidth()，保留（见类注释）
    return texture === null
      ? super.getSuggestedMinimumWidth()
      : texture.getHeight() + this.mPaddings.height();
  }

  onRender(canvas: GLCanvas): void {
    const texture = this.mTexture;
    if (texture === null || this.mSrc.isEmpty()) {
      return;
    }

    this.mDst.set(this.mPaddings.left, this.mPaddings.top,
      this.getWidth() - this.mPaddings.right, this.getHeight() - this.mPaddings.bottom);
    if (this.mDst.isEmpty()) {
      return;
    }

    texture.draw(canvas, this.mSrc, this.mDst);
  }
}
