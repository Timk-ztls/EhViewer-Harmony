/*
 * Copyright (C) 2006 The Android Open Source Project
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

import { Rect } from './Rect';

/**
 * `android.graphics.RectF` 的 ArkTS 等价实现（浮点矩形）。
 *
 * 用途：`GLES20Canvas.drawTexture(BasicTexture, RectF source, RectF target)` 的
 * 纹理坐标换算全部走这个类型（见上游 GLES20Canvas.convertCoordinate），浮点误差
 * 会直接体现为贴图边缘 1 像素的裁切差异，因此这里不做任何取整，逐运算符照搬 AOSP。
 */
export class RectF {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;

  /**
   * 覆盖上游 `new RectF()` / `new RectF(l,t,r,b)` / `new RectF(RectF)` / `new RectF(Rect)`。
   */
  constructor(a?: number | RectF | Rect, b?: number, c?: number, d?: number) {
    if (a === undefined) {
      return;
    }
    if (typeof a === 'number') {
      this.left = a;
      this.top = b as number;
      this.right = c as number;
      this.bottom = d as number;
    } else {
      this.left = a.left;
      this.top = a.top;
      this.right = a.right;
      this.bottom = a.bottom;
    }
  }

  /**
   * 一个入口覆盖上游三个重载：`set(l,t,r,b)` / `set(RectF)` / `set(Rect)`。
   * 保持调用点写法不变（`mTempSourceRect.set(source)`），符合"符号级 1:1"。
   */
  set(a: number | RectF | Rect, b?: number, c?: number, d?: number): void {
    if (typeof a === 'number') {
      this.left = a;
      this.top = b as number;
      this.right = c as number;
      this.bottom = d as number;
    } else {
      this.left = a.left;
      this.top = a.top;
      this.right = a.right;
      this.bottom = a.bottom;
    }
  }

  setFromRectF(r: RectF): void {
    this.left = r.left;
    this.top = r.top;
    this.right = r.right;
    this.bottom = r.bottom;
  }

  setFromRect(r: Rect): void {
    this.left = r.left;
    this.top = r.top;
    this.right = r.right;
    this.bottom = r.bottom;
  }

  setEmpty(): void {
    this.left = 0;
    this.top = 0;
    this.right = 0;
    this.bottom = 0;
  }

  width(): number {
    return this.right - this.left;
  }

  height(): number {
    return this.bottom - this.top;
  }

  centerX(): number {
    return (this.left + this.right) * 0.5;
  }

  centerY(): number {
    return (this.top + this.bottom) * 0.5;
  }

  /** AOSP 的 isEmpty 判据是 `left >= right || top >= bottom`，不是 `>`。 */
  isEmpty(): boolean {
    return this.left >= this.right || this.top >= this.bottom;
  }

  offset(dx: number, dy: number): void {
    this.left += dx;
    this.top += dy;
    this.right += dx;
    this.bottom += dy;
  }

  offsetTo(newLeft: number, newTop: number): void {
    this.right += newLeft - this.left;
    this.bottom += newTop - this.top;
    this.left = newLeft;
    this.top = newTop;
  }

  inset(dx: number, dy: number): void {
    this.left += dx;
    this.top += dy;
    this.right -= dx;
    this.bottom -= dy;
  }

  contains(x: number, y: number): boolean {
    return this.left < this.right && this.top < this.bottom
      && x >= this.left && x < this.right
      && y >= this.top && y < this.bottom;
  }

  intersect(r: RectF): boolean {
    if (this.left < r.right && r.left < this.right
      && this.top < r.bottom && r.top < this.bottom) {
      if (this.left < r.left) {
        this.left = r.left;
      }
      if (this.top < r.top) {
        this.top = r.top;
      }
      if (this.right > r.right) {
        this.right = r.right;
      }
      if (this.bottom > r.bottom) {
        this.bottom = r.bottom;
      }
      return true;
    }
    return false;
  }

  /** 并集。分支顺序同 `Rect.union`（四条边各自独立扩展，不是 else-if 链）。 */
  union(r: RectF): void {
    if (this.left >= this.right || this.top >= this.bottom) {
      this.set(r);
    } else if (r.left >= r.right || r.top >= r.bottom) {
      return;
    } else {
      if (this.left > r.left) {
        this.left = r.left;
      }
      if (this.top > r.top) {
        this.top = r.top;
      }
      if (this.right < r.right) {
        this.right = r.right;
      }
      if (this.bottom < r.bottom) {
        this.bottom = r.bottom;
      }
    }
  }

  sort(): void {
    if (this.left > this.right) {
      const tmp = this.left;
      this.left = this.right;
      this.right = tmp;
    }
    if (this.top > this.bottom) {
      const tmp = this.top;
      this.top = this.bottom;
      this.bottom = tmp;
    }
  }

  /**
   * 四舍五入到整型矩形。AOSP 用 `Math.round`（半数向正无穷），
   * 这里用 `Math.floor(v + 0.5)` 精确复现，避免 ArkTS 侧双重语义差异。
   */
  round(out: Rect): void {
    out.left = Math.floor(this.left + 0.5);
    out.top = Math.floor(this.top + 0.5);
    out.right = Math.floor(this.right + 0.5);
    out.bottom = Math.floor(this.bottom + 0.5);
  }

  roundOut(out: Rect): void {
    out.left = Math.floor(this.left);
    out.top = Math.floor(this.top);
    out.right = Math.ceil(this.right);
    out.bottom = Math.ceil(this.bottom);
  }

  equalsRectF(r: RectF): boolean {
    return this.left === r.left && this.top === r.top
      && this.right === r.right && this.bottom === r.bottom;
  }

  toString(): string {
    return `RectF(${this.left}, ${this.top}, ${this.right}, ${this.bottom})`;
  }
}
