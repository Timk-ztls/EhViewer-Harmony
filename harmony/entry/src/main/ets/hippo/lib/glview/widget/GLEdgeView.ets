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

import { Matrix } from '../util/Matrix';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { GLView } from '../view/GLView';
import { GLEdgeEffect } from './GLEdgeEffect';

/**
 * `com.hippo.lib.glview.widget.GLEdgeView` 的 ArkTS 等价实现。
 *
 * 四条边各挂一个 `GLEdgeEffect`，用一个 4×16 的矩阵数组做边方向变换：
 * - TOP：单位阵（原样）
 * - LEFT：绕 Z 转 90° + Y 轴翻转
 * - BOTTOM：下移 h + Y 轴翻转
 * - RIGHT：右移 w + 绕 Z 转 90°
 *
 * 变换矩阵的起始下标就是方向常量 × 16（`TOP_M = TOP * 16` 等），
 * 这样 `render()` 里 `multiplyMatrix(mMatrix, i * 16)` 与 `onPull(offset, i)` 的下标天然对齐。
 *
 * `onPull` 有两个重载（带/不带 `position`），ArkTS 无重载 → 第三个参数可选。
 */
export class GLEdgeView extends GLView {
  static readonly TOP: number = 0;
  static readonly LEFT: number = 1;
  static readonly BOTTOM: number = 2;
  static readonly RIGHT: number = 3;

  private static readonly TOP_M: number = GLEdgeView.TOP * 16;
  private static readonly LEFT_M: number = GLEdgeView.LEFT * 16;
  private static readonly BOTTOM_M: number = GLEdgeView.BOTTOM * 16;
  private static readonly RIGHT_M: number = GLEdgeView.RIGHT * 16;

  private readonly mEffect: GLEdgeEffect[] = [];
  private readonly mMatrix: number[] = new Array<number>(4 * 16).fill(0);

  constructor(color: number) {
    super();
    for (let i = 0; i < 4; i++) {
      this.mEffect.push(new GLEdgeEffect(color));
    }
  }

  setColor(color: number): void {
    for (let i = 0; i < 4; i++) {
      this.mEffect[i].setColor(color);
    }
  }

  protected onLayout(changeSize: boolean, left: number, top: number, right: number,
    bottom: number): void {
    if (!changeSize) {
      return;
    }

    const w = right - left;
    const h = bottom - top;
    for (let i = 0; i < 4; i++) {
      if ((i & 1) === 0) {
        // top / bottom
        this.mEffect[i].setSize(w, h);
      } else {
        // left / right
        this.mEffect[i].setSize(h, w);
      }
    }

    // 四条边的变换（上游注释：不设变换时 EdgeEffect 只会从 (0,0) 画到 (w, Y*h)）
    Matrix.setIdentityM(this.mMatrix, GLEdgeView.TOP_M);
    Matrix.setIdentityM(this.mMatrix, GLEdgeView.LEFT_M);
    Matrix.setIdentityM(this.mMatrix, GLEdgeView.BOTTOM_M);
    Matrix.setIdentityM(this.mMatrix, GLEdgeView.RIGHT_M);

    Matrix.rotateM(this.mMatrix, GLEdgeView.LEFT_M, 90, 0, 0, 1);
    Matrix.scaleM(this.mMatrix, GLEdgeView.LEFT_M, 1, -1, 1);

    Matrix.translateM(this.mMatrix, GLEdgeView.BOTTOM_M, 0, h, 0);
    Matrix.scaleM(this.mMatrix, GLEdgeView.BOTTOM_M, 1, -1, 1);

    Matrix.translateM(this.mMatrix, GLEdgeView.RIGHT_M, w, 0, 0);
    Matrix.rotateM(this.mMatrix, GLEdgeView.RIGHT_M, 90, 0, 0, 1);
  }

  /** 覆盖 `GLView.render`：**不**渲染子视图（本类不承载子节点），只画四个边缘效果。 */
  render(canvas: GLCanvas): void {
    let more = false;
    for (let i = 0; i < 4; i++) {
      canvas.save(GLCanvas.SAVE_FLAG_MATRIX);
      canvas.multiplyMatrix(this.mMatrix, i * 16);
      more = this.mEffect[i].draw(canvas) || more;
      canvas.restore();
    }
    if (more) {
      this.invalidate();
    }
  }

  /**
   * 内容被拉离边缘时调用。`offset` 单位像素；`position` 可选（手指位置 0..1）。
   * 上游两个重载合一：`onPull(offset, direction)` 与 `onPull(offset, position, direction)`。
   *
   * 注意两个重载的 `fullLength` 取法**相反**：
   * - 无 position：`(direction & 1) == 0 ? width : height`
   * - 有 position：`(direction & 1) == 0 ? height : width`（用于 position 归一化）
   * 这是上游原样，照搬。
   */
  onPull(offset: number, a: number, b?: number): void {
    const hasPosition = b !== undefined;
    const direction = hasPosition ? (b as number) : a;
    const fullLength = hasPosition
      ? ((direction & 1) === 0 ? this.getHeight() : this.getWidth())
      : ((direction & 1) === 0 ? this.getWidth() : this.getHeight());

    if (hasPosition) {
      const position = a;
      const fullPosition = (direction & 1) === 0 ? this.getWidth() : this.getHeight();
      this.mEffect[direction].onPull(offset / fullLength, position / fullPosition);
    } else {
      this.mEffect[direction].onPull(offset / fullLength);
    }

    if (!this.mEffect[direction].isFinished()) {
      this.invalidate();
    }
  }

  /**
   * 松手后调用。上游两个重载合一：`onRelease()`（全部四条边）/ `onRelease(direction)`（单边）。
   */
  onRelease(direction?: number): void {
    if (direction === undefined) {
      let more = false;
      for (let i = 0; i < 4; i++) {
        this.mEffect[i].onRelease();
        more = !this.mEffect[i].isFinished() || more;
      }
      if (more) {
        this.invalidate();
      }
      return;
    }
    const effect = this.mEffect[direction];
    effect.onRelease();
    if (!effect.isFinished()) {
      this.invalidate();
    }
  }

  /** 吸收一次冲击（fling 撞边界）。velocity 单位 px/s。 */
  onAbsorb(velocity: number, direction: number): void {
    this.mEffect[direction].onAbsorb(velocity);
    if (!this.mEffect[direction].isFinished()) {
      this.invalidate();
    }
  }

  isFinished(direction: number): boolean {
    return this.mEffect[direction].isFinished();
  }
}
