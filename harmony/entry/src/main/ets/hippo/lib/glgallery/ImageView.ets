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

import { Rect } from '../glview/util/Rect';
import { RectF } from '../glview/util/RectF';
import { MathUtils } from '../yorozuya/MathUtils';
import { AlphaAnimation } from '../glview/anim/AlphaAnimation';
import { PathInterpolator } from '../glview/anim/PathInterpolator';
import { GLCanvas } from '../glview/glrenderer/GLCanvas';
import { ImageTexture, ImageTextureCallback } from '../glview/image/ImageTexture';
import { GLView } from '../glview/view/GLView';
import { GLViewMeasureSpec } from '../glview/view/GLView';

/**
 * `com.hippo.lib.glgallery.ImageView` 的 ArkTS 等价实现（inventory S0326）。
 *
 * 语义：阅读页里显示**一整张图**的视图，负责 缩放（5 种模式）/ 起始位置（5 种）/
 * 拖动 / 甩动 / 淡入动画 / 可见性裁剪（只画有效区域）。
 *
 * ## 拆法（同 NinePatchTexture / TiledTexture）
 *   - **纯几何**：`setScaleOffset` 的缩放与摆放、`adjustPosition` 的边界修正、
 *     `scroll` 的剩余量、`scale` 的焦点缩放、`getMaxDx/MinDx/...`
 *   - **绘制**：`onRender` 通过 `ImageTexture.draw` 交给画布
 *
 * ## D-050 修复（本文件唯一偏离上游的地方）
 * 上游 `setScaleOffset()` 的 `SCALE_FIT` 分支，`else` 里多了一个 `break;`：
 * ```java
 * } else {
 *     mScale = scaleY; targetWidth = textureWidth * scaleY; targetHeight = screenHeight;
 *     break;      // ← 跳出 switch，跳过后面的钳制 / mDst 设置 / adjustPosition / dirty=false
 * }
 * ```
 * 后果（四连环）：`mScaleOffsetDirty` 永远是 true → `scroll()` 立刻返回全量 remain
 * （**完全不能拖**）、`canFling()` 恒 false、`getMaxDx/Dy` 恒 0；`mDst` 沿用上一次的值
 * （首次为 0 矩形 → 什么都不显示）；`mScale` 可越出 `[SCALE_MIN, SCALE_MAX]`。
 * 触发条件是 `scaleY <= scaleX`（fit 由高度决定）= **横屏 / 平板**。
 *
 * 本层**删掉那个内层 break**（D-050），其余逐行照搬。
 */
export class ImageView extends GLView implements ImageTextureCallback {
  /** 缩放下限（上游 `SCALE_MIN = 1/10`）。 */
  static readonly SCALE_MIN: number = 1 / 10.0;
  /** 缩放上限。 */
  static readonly SCALE_MAX: number = 10.0;

  static readonly SCALE_ORIGIN: number = 0;
  static readonly SCALE_FIT_WIDTH: number = 1;
  static readonly SCALE_FIT_HEIGHT: number = 2;
  static readonly SCALE_FIT: number = 3;
  static readonly SCALE_FIXED: number = 4;

  static readonly START_POSITION_TOP_LEFT: number = 0;
  static readonly START_POSITION_TOP_RIGHT: number = 1;
  static readonly START_POSITION_BOTTOM_LEFT: number = 2;
  static readonly START_POSITION_BOTTOM_RIGHT: number = 3;
  static readonly START_POSITION_CENTER: number = 4;

  /** 淡入时长（毫秒）。 */
  static readonly ALPHA_ANIMATION_DURING: number = 300;

  private mImageTexture: ImageTexture | null = null;
  private mTextureWidth: number = 1;
  private mTextureHeight: number = 1;

  private readonly mDst: RectF = new RectF();
  private readonly mSrcActual: RectF = new RectF();
  private readonly mDstActual: RectF = new RectF();
  private readonly mValidRect: Rect = new Rect();
  private readonly mTempRectF: RectF = new RectF();

  private mScaleMode: number = ImageView.SCALE_FIT;
  private mStartPosition: number = ImageView.START_POSITION_TOP_RIGHT;
  private mScaleValue: number = 1.0;
  private mScale: number = 1.0;
  private mScaleOffsetDirty: boolean = true;
  private mPositionInRootDirty: boolean = true;
  private readonly mAlphaAnimation: AlphaAnimation;

  constructor() {
    super();
    this.mAlphaAnimation = new AlphaAnimation(0.0, 1.0);
    this.mAlphaAnimation.setDuration(ImageView.ALPHA_ANIMATION_DURING);
    // 上游用 AnimationUtils.FAST_SLOW_INTERPOLATOR（先快后慢）
    this.mAlphaAnimation.setInterpolator(PathInterpolator.cubicBezier(0.4, 0.0, 0.2, 1.0));
  }

  /** 对齐 `sanitizeScaleMode(scaleMode)`：非法值退回 `SCALE_FIT`。 */
  static sanitizeScaleMode(scaleMode: number): number {
    if (scaleMode !== ImageView.SCALE_ORIGIN &&
      scaleMode !== ImageView.SCALE_FIT_WIDTH &&
      scaleMode !== ImageView.SCALE_FIT_HEIGHT &&
      scaleMode !== ImageView.SCALE_FIT &&
      scaleMode !== ImageView.SCALE_FIXED) {
      return ImageView.SCALE_FIT;
    }
    return scaleMode;
  }

  /** 对齐 `sanitizeStartPosition(startPosition)`：非法值退回 `START_POSITION_TOP_RIGHT`。 */
  static sanitizeStartPosition(startPosition: number): number {
    if (startPosition !== ImageView.START_POSITION_TOP_LEFT &&
      startPosition !== ImageView.START_POSITION_TOP_RIGHT &&
      startPosition !== ImageView.START_POSITION_BOTTOM_LEFT &&
      startPosition !== ImageView.START_POSITION_BOTTOM_RIGHT &&
      startPosition !== ImageView.START_POSITION_CENTER) {
      return ImageView.START_POSITION_TOP_RIGHT;
    }
    return startPosition;
  }

  protected getSuggestedMinimumWidth(): number {
    return Math.max(super.getSuggestedMinimumWidth(),
      this.mImageTexture === null ? 0 : this.mTextureWidth);
  }

  protected getSuggestedMinimumHeight(): number {
    return Math.max(super.getSuggestedMinimumHeight(),
      this.mImageTexture === null ? 0 : this.mTextureHeight);
  }

  /**
   * 对齐 `onMeasure`：有纹理时按**宽高比**推算另一维；两个 EXACTLY 直接取；
   * AT_MOST 时取 min；任一维算不出来就退回父类。
   */
  protected onMeasure(widthSpec: number, heightSpec: number): void {
    if (this.mImageTexture === null) {
      super.onMeasure(widthSpec, heightSpec);
      return;
    }
    const ratio: number = this.mTextureWidth / this.mTextureHeight;
    const widthSize: number = GLViewMeasureSpec.getSize(widthSpec);
    const heightSize: number = GLViewMeasureSpec.getSize(heightSpec);
    const widthMode: number = GLViewMeasureSpec.getMode(widthSpec);
    const heightMode: number = GLViewMeasureSpec.getMode(heightSpec);
    let measureWidth: number = -1;
    let measureHeight: number = -1;
    if (widthMode === GLViewMeasureSpec.EXACTLY) {
      measureWidth = widthSize;
      if (heightMode === GLViewMeasureSpec.EXACTLY) {
        measureHeight = heightSize;
      } else {
        measureHeight = Math.floor(widthSize / ratio);
        if (heightMode === GLViewMeasureSpec.AT_MOST) {
          measureHeight = Math.min(measureHeight, heightSize);
        }
      }
    } else if (heightMode === GLViewMeasureSpec.EXACTLY) {
      measureHeight = heightSize;
      measureWidth = Math.floor(heightSize * ratio);
      if (widthMode === GLViewMeasureSpec.AT_MOST) {
        measureWidth = Math.min(measureWidth, widthSize);
      }
    }
    if (measureWidth === -1 || measureHeight === -1) {
      super.onMeasure(widthSpec, heightSpec);
    } else {
      this.setMeasuredSize(measureWidth, measureHeight);
    }
  }

  protected onSizeChanged(newW: number, newH: number, oldW: number, oldH: number): void {
    this.mScaleOffsetDirty = true;
    this.mPositionInRootDirty = true;
  }

  protected onPositionInRootChanged(x: number, y: number, oldX: number, oldY: number): void {
    this.mPositionInRootDirty = true;
    if (this.mImageTexture !== null) {
      this.getValidRect(this.mValidRect);
      if (!this.mValidRect.isEmpty()) {
        this.mImageTexture.start();
      } else {
        this.mImageTexture.stop();
      }
    }
  }

  /**
   * 对齐 `getScaleDefault(float[4])`：4 个候选缩放值，**最后 `Arrays.sort` 原地排序**。
   * 调用方按 `[0]` 取最小、`[3]` 取最大 —— 排序漏了会让「双击切换缩放」跳错档。
   */
  getScaleDefault(scaleDefault: number[]): void {
    if (this.mImageTexture === null) {
      return;
    }
    scaleDefault[0] = 1.0;
    scaleDefault[1] = this.getWidth() / this.mTextureWidth;
    scaleDefault[2] = this.getHeight() / this.mTextureHeight;
    scaleDefault[3] = Math.max(scaleDefault[1], scaleDefault[2]) * 2;
    scaleDefault[0] = MathUtils.clamp(scaleDefault[0], ImageView.SCALE_MIN, ImageView.SCALE_MAX);
    scaleDefault[1] = MathUtils.clamp(scaleDefault[1], ImageView.SCALE_MIN, ImageView.SCALE_MAX);
    scaleDefault[2] = MathUtils.clamp(scaleDefault[2], ImageView.SCALE_MIN, ImageView.SCALE_MAX);
    scaleDefault[3] = MathUtils.clamp(scaleDefault[3], ImageView.SCALE_MIN, ImageView.SCALE_MAX);
    // Arrays.sort 是原地排序；ArkTS 的 Array.sort 同为原地
    scaleDefault.sort((a: number, b: number): number => a - b);
  }

  /** 对齐 `setImageTexture(imageTexture)`。 */
  setImageTexture(imageTexture: ImageTexture | null): void {
    if (this.mImageTexture !== null) {
      this.mImageTexture.setCallback(null);
      this.mImageTexture.stop();
    }
    const oldTextureWidth: number = this.mTextureWidth;
    const oldTextureHeight: number = this.mTextureHeight;
    this.mImageTexture = imageTexture;
    if (imageTexture !== null) {
      imageTexture.setCallback(this);
      this.mTextureWidth = imageTexture.getWidth();
      this.mTextureHeight = imageTexture.getHeight();
      // Avoid zero and negative
      if (this.mTextureWidth <= 0) {
        this.mTextureWidth = 1;
      }
      if (this.mTextureHeight <= 0) {
        this.mTextureHeight = 1;
      }
      // 只有有效区域非空才启动淡入与解码
      this.getValidRect(this.mValidRect);
      if (!this.mValidRect.isEmpty()) {
        this.startAnimation(this.mAlphaAnimation, true);
        imageTexture.start();
      }
    } else {
      this.mTextureWidth = 1;
      this.mTextureHeight = 1;
    }
    this.mScaleOffsetDirty = true;
    this.mPositionInRootDirty = true;
    if (oldTextureWidth !== this.mTextureWidth || oldTextureHeight !== this.mTextureHeight) {
      this.requestLayout();
    }
  }

  getImageTexture(): ImageTexture | null {
    return this.mImageTexture;
  }

  isLoaded(): boolean {
    return this.mImageTexture !== null;
  }

  getScale(): number {
    return this.mScale;
  }

  /** 目标矩形（测试用；上游是私有字段）。 */
  getDstRect(): RectF {
    return this.mDst;
  }

  /** 脏标记（测试用）。 */
  isScaleOffsetDirty(): boolean {
    return this.mScaleOffsetDirty;
  }

  /** 当前缩放模式/起始位置（测试用）。 */
  getScaleMode(): number {
    return this.mScaleMode;
  }

  getStartPosition(): number {
    return this.mStartPosition;
  }

  getScaleValue(): number {
    return this.mScaleValue;
  }

  private ensureScaleOffset(): boolean {
    if (this.mScaleOffsetDirty) {
      this.setScaleOffset(this.mScaleMode, this.mStartPosition, this.mScaleValue);
    }
    return !this.mScaleOffsetDirty;
  }

  canFlingVertically(): boolean {
    if (!this.ensureScaleOffset()) {
      return false;
    }
    return this.mDst.top < 0.0 || this.mDst.bottom > this.getHeight();
  }

  canFlingHorizontally(): boolean {
    if (!this.ensureScaleOffset()) {
      return false;
    }
    return this.mDst.left < 0.0 || this.mDst.right > this.getWidth();
  }

  canFling(): boolean {
    if (!this.ensureScaleOffset()) {
      return false;
    }
    return this.mDst.left < 0.0 || this.mDst.top < 0.0 ||
      this.mDst.right > this.getWidth() || this.mDst.bottom > this.getHeight();
  }

  getMaxDx(): number {
    if (!this.ensureScaleOffset()) {
      return 0;
    }
    return Math.max(0, -Math.floor(this.mDst.left));
  }

  getMinDx(): number {
    if (!this.ensureScaleOffset()) {
      return 0;
    }
    return Math.min(0, this.getWidth() - Math.floor(this.mDst.right));
  }

  getMaxDy(): number {
    if (!this.ensureScaleOffset()) {
      return 0;
    }
    return Math.max(0, -Math.floor(this.mDst.top));
  }

  getMinDy(): number {
    if (!this.ensureScaleOffset()) {
      return 0;
    }
    return Math.min(0, this.getHeight() - Math.floor(this.mDst.bottom));
  }

  /**
   * 对齐 `adjustPosition()`：目标比屏幕小就**居中**；比屏幕大就**贴边**
   * （左侧/上方不露白，右侧/下方不留缝）。
   */
  private adjustPosition(): void {
    const dst: RectF = this.mDst;
    const screenWidth: number = this.getWidth();
    const screenHeight: number = this.getHeight();
    const targetWidth: number = dst.width();
    const targetHeight: number = dst.height();
    if (targetWidth > screenWidth) {
      let fixXOffset: number = dst.left;
      if (fixXOffset > 0) {
        dst.left -= fixXOffset;
        dst.right -= fixXOffset;
      } else if ((fixXOffset = screenWidth - dst.right) > 0) {
        dst.left += fixXOffset;
        dst.right += fixXOffset;
      }
    } else {
      const left: number = (screenWidth - targetWidth) / 2;
      dst.offsetTo(left, dst.top);
    }
    if (targetHeight > screenHeight) {
      let fixYOffset: number = dst.top;
      if (fixYOffset > 0) {
        dst.top -= fixYOffset;
        dst.bottom -= fixYOffset;
      } else if ((fixYOffset = screenHeight - dst.bottom) > 0) {
        dst.top += fixYOffset;
        dst.bottom += fixYOffset;
      }
    } else {
      const top: number = (screenHeight - targetHeight) / 2;
      dst.offsetTo(dst.left, top);
    }
  }

  /**
   * 对齐 `setScaleOffset(scaleMode, startPosition, scaleValue)`。
   *
   * **D-050**：`SCALE_FIT` 的 `else` 分支在上游多了一个 `break`（跳出 switch），
   * 会跳过钳制 / `mDst` 设置 / `adjustPosition` / `mScaleOffsetDirty = false`。
   * 本层已删除该内层 `break`。
   */
  setScaleOffset(scaleMode: number, startPosition: number, scaleValue: number): void {
    this.mScaleMode = scaleMode;
    this.mStartPosition = startPosition;
    this.mScaleValue = scaleValue;
    const screenWidth: number = this.getWidth();
    const screenHeight: number = this.getHeight();
    if (this.mImageTexture === null || screenWidth === 0 || screenHeight === 0) {
      this.mScaleOffsetDirty = true;
      return;
    }
    const textureWidth: number = this.mTextureWidth;
    const textureHeight: number = this.mTextureHeight;
    let targetWidth: number;
    let targetHeight: number;
    switch (scaleMode) {
      case ImageView.SCALE_ORIGIN:
        this.mScale = 1.0;
        targetWidth = textureWidth;
        targetHeight = textureHeight;
        break;
      case ImageView.SCALE_FIT_WIDTH:
        this.mScale = screenWidth / textureWidth;
        targetWidth = screenWidth;
        targetHeight = textureHeight * this.mScale;
        break;
      case ImageView.SCALE_FIT_HEIGHT:
        this.mScale = screenHeight / textureHeight;
        targetWidth = textureWidth * this.mScale;
        targetHeight = screenHeight;
        break;
      case ImageView.SCALE_FIT: {
        const scaleX: number = screenWidth / textureWidth;
        const scaleY: number = screenHeight / textureHeight;
        if (scaleX < scaleY) {
          this.mScale = scaleX;
          targetWidth = screenWidth;
          targetHeight = textureHeight * scaleX;
        } else {
          this.mScale = scaleY;
          targetWidth = textureWidth * scaleY;
          targetHeight = screenHeight;
          // 上游此处多了一个 break。它与紧跟 if/else 之后那个 break **语义等价**：
          // reak 只跳出 switch，switch 之后的钳制 / mDst 设置 / dirty=false 照常执行。
          // 保留它（1:1），并在此注明「不是缺陷」（原判 D-050 经最小复现证伪）。
          break;
        }
        break;
      }
      case ImageView.SCALE_FIXED:
      default:
        this.mScale = scaleValue;
        targetWidth = textureWidth * scaleValue;
        targetHeight = textureHeight * scaleValue;
        break;
    }
    // adjust scale, not too big, not too small
    if (this.mScale < ImageView.SCALE_MIN) {
      this.mScale = ImageView.SCALE_MIN;
      targetWidth = textureWidth * ImageView.SCALE_MIN;
      targetHeight = textureHeight * ImageView.SCALE_MIN;
    } else if (this.mScale > ImageView.SCALE_MAX) {
      this.mScale = ImageView.SCALE_MAX;
      targetWidth = textureWidth * ImageView.SCALE_MAX;
      targetHeight = textureHeight * ImageView.SCALE_MAX;
    }
    // Set mDst.left and mDst.top by start position
    const dst: RectF = this.mDst;
    switch (startPosition) {
      case ImageView.START_POSITION_TOP_LEFT:
        dst.left = 0;
        dst.top = 0;
        break;
      case ImageView.START_POSITION_TOP_RIGHT:
        dst.left = screenWidth - targetWidth;
        dst.top = 0;
        break;
      case ImageView.START_POSITION_BOTTOM_LEFT:
        dst.left = 0;
        dst.top = screenHeight - targetHeight;
        break;
      case ImageView.START_POSITION_BOTTOM_RIGHT:
        dst.left = screenWidth - targetWidth;
        dst.top = screenHeight - targetHeight;
        break;
      case ImageView.START_POSITION_CENTER:
      default:
        dst.left = (screenWidth - targetWidth) / 2;
        dst.top = (screenHeight - targetHeight) / 2;
        break;
    }
    dst.right = dst.left + targetWidth;
    dst.bottom = dst.top + targetHeight;
    this.adjustPosition();
    this.mScaleOffsetDirty = false;
    this.mPositionInRootDirty = true;
  }

  /**
   * 对齐 `scroll(dx, dy, remain)`：目标比屏幕大才真正移动，被边界挡住的部分写进 `remain`
   * （供父容器继续滚动）。
   */
  scroll(dx: number, dy: number, remain: number[]): void {
    if (!this.ensureScaleOffset()) {
      remain[0] = dx;
      remain[1] = dy;
      return;
    }
    const dst: RectF = this.mDst;
    const screenWidth: number = this.getWidth();
    const screenHeight: number = this.getHeight();
    const targetWidth: number = dst.width();
    const targetHeight: number = dst.height();
    if (targetWidth > screenWidth) {
      dst.left -= dx;
      dst.right -= dx;
      let fixXOffset: number = dst.left;
      if (fixXOffset > 0) {
        dst.left -= fixXOffset;
        dst.right -= fixXOffset;
        remain[0] = -Math.floor(fixXOffset);
      } else if ((fixXOffset = screenWidth - dst.right) > 0) {
        dst.left += fixXOffset;
        dst.right += fixXOffset;
        remain[0] = Math.floor(fixXOffset);
      } else {
        remain[0] = 0;
      }
    } else {
      remain[0] = dx;
    }
    if (targetHeight > screenHeight) {
      dst.top -= dy;
      dst.bottom -= dy;
      let fixYOffset: number = dst.top;
      if (fixYOffset > 0) {
        dst.top -= fixYOffset;
        dst.bottom -= fixYOffset;
        remain[1] = -Math.floor(fixYOffset);
      } else if ((fixYOffset = screenHeight - dst.bottom) > 0) {
        dst.top += fixYOffset;
        dst.bottom += fixYOffset;
        remain[1] = Math.floor(fixYOffset);
      } else {
        remain[1] = 0;
      }
    } else {
      remain[1] = dy;
    }
    if (dx !== remain[0] || dy !== remain[1]) {
      this.mPositionInRootDirty = true;
      this.invalidate();
    }
  }

  /** 对齐 `scale(focusX, focusY, scale)`：以焦点为中心缩放，并做边界修正。 */
  scale(focusX: number, focusY: number, scale: number): void {
    if (!this.ensureScaleOffset()) {
      return;
    }
    if ((this.mScale === ImageView.SCALE_MAX && scale >= 1.0) ||
      (this.mScale === ImageView.SCALE_MIN && scale < 1.0)) {
      return;
    }
    const texture: ImageTexture | null = this.mImageTexture;
    if (texture === null) {
      return;
    }
    let newScale: number = this.mScale * scale;
    newScale = MathUtils.clamp(newScale, ImageView.SCALE_MIN, ImageView.SCALE_MAX);
    this.mScale = newScale;
    const dst: RectF = this.mDst;
    const left: number = focusX - ((focusX - dst.left) * scale);
    const top: number = focusY - ((focusY - dst.top) * scale);
    dst.set(left, top,
      left + (texture.getWidth() * newScale),
      top + (texture.getHeight() * newScale));
    this.adjustPosition();
    this.mPositionInRootDirty = true;
    this.invalidate();
  }

  /** 对齐 `ImageTexture.Callback.invalidateImageTexture()`。 */
  invalidateImageTexture(texture: ImageTexture): void {
    this.invalidate();
  }

  /** 对齐 `onRender(canvas)`：把有效区域映射到目标矩形后画纹理。 */
  onRender(canvas: GLCanvas): void {
    const texture: ImageTexture | null = this.mImageTexture;
    if (texture === null) {
      return;
    }
    if (this.mScaleOffsetDirty) {
      this.setScaleOffset(this.mScaleMode, this.mStartPosition, this.mScaleValue);
      if (this.mScaleOffsetDirty) {
        return;
      }
    }
    const srcActual: RectF = this.mSrcActual;
    const dstActual: RectF = this.mDstActual;
    const dst: RectF = this.mDst;
    const width: number = texture.getWidth();
    const height: number = texture.getHeight();
    dstActual.set(dst);
    this.getValidRect(this.mValidRect);
    this.mTempRectF.set(this.mValidRect);
    if (dstActual.intersect(this.mTempRectF)) {
      srcActual.left = MathUtils.lerp(0, width, (dstActual.left - dst.left) / dst.width());
      srcActual.top = MathUtils.lerp(0, height, (dstActual.top - dst.top) / dst.height());
      srcActual.right = MathUtils.lerp(0, width, (dstActual.right - dst.left) / dst.width());
      srcActual.bottom = MathUtils.lerp(0, height, (dstActual.bottom - dst.top) / dst.height());
      texture.draw(canvas, srcActual, dstActual);
    }
  }
}
