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

/**
 * `android.graphics.Rect` 的 ArkTS 等价实现（纯值对象，无平台语义）。
 *
 * 为什么自写：鸿蒙 ArkTS 没有 `android.graphics`，也没有 `@ohos.graphics.Rect`
 * 的整型矩形（`@ohos.graphics.common2D` 只提供浮点 Rect）。上游 glview/glgallery
 * 有 183 处 `rect` 引用，逐处改写会让 1:1 对照失效，因此保留同名同义的类。
 *
 * 语义差异（必须在 MR 里登记）：
 * - Java 的 `int` 在 ArkTS 中是 double，本类在写入时统一 `| 0` 截断为 int32，
 *   以保持 `width()/height()/centerX()` 的移位与溢出行为一致（上游依赖 `>> 1` 的截断）。
 * - Java 的方法重载在 ArkTS 不存在（DEVIATIONS §5 第 7 条），这里用联合类型参数在
 *   签名层做分派，保证调用点写法不变：`new Rect(r)` 与 `new Rect(0, 0, 1, 1)` 都可用。
 */
export class Rect {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;

  /**
   * 覆盖上游 `new Rect()` / `new Rect(l,t,r,b)` / `new Rect(Rect)` 三种用法。
   * ArkTS 的构造重载支持不稳定，这里用可选+联合参数在签名层分派，保证调用点不变。
   */
  constructor(a?: number | Rect, b?: number, c?: number, d?: number) {
    if (a === undefined) {
      return;
    }
    if (typeof a === 'number') {
      this.left = a | 0;
      this.top = (b as number) | 0;
      this.right = (c as number) | 0;
      this.bottom = (d as number) | 0;
    } else {
      this.left = a.left;
      this.top = a.top;
      this.right = a.right;
      this.bottom = a.bottom;
    }
  }

  /** 返回该矩形的宽；若为空（right <= left）返回负数或 0，与上游一致。 */
  width(): number {
    return this.right - this.left;
  }

  /** 返回该矩形的高。 */
  height(): number {
    return this.bottom - this.top;
  }

  /** 矩形中心 X；用 `>> 1` 保持上游的向负无穷截断语义。 */
  centerX(): number {
    return (this.left + this.right) >> 1;
  }

  /** 矩形中心 Y。 */
  centerY(): number {
    return (this.top + this.bottom) >> 1;
  }

  /** 空矩形定义：left >= right 或 top >= bottom（与 android.graphics.Rect 一致）。 */
  isEmpty(): boolean {
    return this.left >= this.right || this.top >= this.bottom;
  }

  setEmpty(): void {
    this.left = 0;
    this.top = 0;
    this.right = 0;
    this.bottom = 0;
  }

  /** 一个入口覆盖上游 `set(l,t,r,b)` 与 `set(Rect)` 两个重载。 */
  set(a: number | Rect, b?: number, c?: number, d?: number): void {
    if (typeof a === 'number') {
      this.left = a | 0;
      this.top = (b as number) | 0;
      this.right = (c as number) | 0;
      this.bottom = (d as number) | 0;
    } else {
      this.left = a.left;
      this.top = a.top;
      this.right = a.right;
      this.bottom = a.bottom;
    }
  }

  setFromRect(r: Rect): void {
    this.left = r.left;
    this.top = r.top;
    this.right = r.right;
    this.bottom = r.bottom;
  }

  /** 按 (dx, dy) 平移。 */
  offset(dx: number, dy: number): void {
    this.left = (this.left + dx) | 0;
    this.top = (this.top + dy) | 0;
    this.right = (this.right + dx) | 0;
    this.bottom = (this.bottom + dy) | 0;
  }

  /** 四边各向内收缩 dx / dy（dx、dy 可为负，即外扩）。 */
  inset(dx: number, dy: number): void {
    this.left = (this.left + dx) | 0;
    this.top = (this.top + dy) | 0;
    this.right = (this.right - dx) | 0;
    this.bottom = (this.bottom - dy) | 0;
  }

  contains(x: number, y: number): boolean {
    return this.left < this.right && this.top < this.bottom
      && x >= this.left && x < this.right
      && y >= this.top && y < this.bottom;
  }

  containsRect(l: number, t: number, r: number, b: number): boolean {
    return this.left < this.right && this.top < this.bottom
      && this.left <= l && this.top <= t
      && this.right >= r && this.bottom >= b;
  }

  containsRectObj(r: Rect): boolean {
    return this.containsRect(r.left, r.top, r.right, r.bottom);
  }

  /**
   * 与另一矩形求交；无交集时返回 false 并将自身置空。
   * 分支顺序严格按 AOSP 实现，保证边界值行为一致。
   */
  intersect(r: Rect): boolean {
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

  intersectRect(left: number, top: number, right: number, bottom: number): boolean {
    if (this.left < right && left < this.right
      && this.top < bottom && top < this.bottom) {
      if (this.left < left) {
        this.left = left | 0;
      }
      if (this.top < top) {
        this.top = top | 0;
      }
      if (this.right > right) {
        this.right = right | 0;
      }
      if (this.bottom > bottom) {
        this.bottom = bottom | 0;
      }
      return true;
    }
    return false;
  }

  /**
   * 自身置为两矩形并集。分支严格按 AOSP：
   * 自身为空 → 复制对方；对方为空 → 不变；否则**四条边各自独立**扩展。
   * （早期写成 else-if 链只会扩展一条边，实测 0,0,10,10 ∪ 20,20,30,30 会得到 0,0,30,10，
   *  已由单测 Rect.union 固定为正确值 0,0,30,30。）
   */
  union(r: Rect): void {
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

  unionRect(left: number, top: number, right: number, bottom: number): void {
    if (this.left >= this.right || this.top >= this.bottom) {
      this.set(left, top, right, bottom);
    } else {
      if (left < this.left) {
        this.left = left | 0;
      }
      if (top < this.top) {
        this.top = top | 0;
      }
      if (right > this.right) {
        this.right = right | 0;
      }
      if (bottom > this.bottom) {
        this.bottom = bottom | 0;
      }
    }
  }

  /** 规范化为 left<=right、top<=bottom。 */
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

  equalsRect(r: Rect): boolean {
    return this.left === r.left && this.top === r.top
      && this.right === r.right && this.bottom === r.bottom;
  }

  toString(): string {
    return `Rect(${this.left}, ${this.top} - ${this.right}, ${this.bottom})`;
  }
}
