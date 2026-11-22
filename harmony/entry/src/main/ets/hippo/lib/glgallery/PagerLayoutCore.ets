/*
 * Copyright 2014 Hippo Seven
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

/**
 * `PagerLayoutManager` 的**纯几何内核**（上游无同名文件）。
 *
 * ## 与 `ScrollLayoutCore` 的关系（为什么只复用一小部分）
 * 翻页模式与连续滚动的**形状不同**：
 * ```
 * 连续滚动：逐像素推进 + 边界处 forceFill() 让上面/下面补内容
 * 翻页：    整页位移 + 边界吸附（offset 只在中缝附近有意义）
 * ```
 * 所以 `ScrollLayoutCore.clampUp` 的「±1 像素防死循环」在翻页里**用不上**
 * （翻页的 offset 范围只有 `[-width-interval+1, width+interval-1]`，不会无限推进）。
 * 能对上的只有**夹紧公式的形态**，这里按翻页自己的边界重写，**不为复用而变形上游**。
 *
 * ## 逐条对上游（`PagerLayoutManager.onFill()` 的布局段）
 * ```
 * GalleryPageView leftPage = getLeftPage();
 * GalleryPageView rightPage = getRightPage();
 *
 * final int min = rightPage == null ? 0 : -width - mInterval + 1;
 * final int max = leftPage == null ? 0 :  width + mInterval - 1;
 * mOffset = MathUtils.clamp(mOffset, min, max);
 *
 * // current：(offset, 0, width + offset, height)
 * // left   ：(-interval - width + offset, 0, -interval + offset, height)
 * // right  ：(width + interval + offset, 0, width + interval + width + offset, height)
 * ```
 *
 * 方向由 `mMode` 决定（`getLeftPage`/`getRightPage`）：
 * ```
 * MODE_LEFT_TO_RIGHT : left = previous, right = next
 * MODE_RIGHT_TO_LEFT : left = next,     right = previous   ← 默认
 * ```
 */

/** `PagerLayoutManager.MODE_LEFT_TO_RIGHT`。 */
export const MODE_LEFT_TO_RIGHT: number = 0;
/** `PagerLayoutManager.MODE_RIGHT_TO_LEFT`（上游默认）。 */
export const MODE_RIGHT_TO_LEFT: number = 1;

/** 布局矩形（左、上、右、下）。 */
export class PagerRect {
  readonly left: number;
  readonly top: number;
  readonly right: number;
  readonly bottom: number;

  constructor(left: number, top: number, right: number, bottom: number) {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
  }
}

/**
 * 夹紧 `offset`（对应 `onFill` 里的 `MathUtils.clamp(mOffset, min, max)`）。
 *
 * 边界取决于**两侧有没有页**：
 *   - 右侧没有页（`hasRightPage = false`）→ `min = 0`（不能往右露出空白）
 *   - 左侧没有页（`hasLeftPage = false`）→ `max = 0`（不能往左露出空白）
 *
 * 注意 `+1 / -1` 补偿：上游用 `-width - interval + 1` 与 `width + interval - 1`，
 * 是为了**留住 1 像素**，让「翻页中」这个状态可判定（`offset != 0` 才算在翻页）。
 * 这是业务值，不是笔误 —— 删掉会让边界永远等于 0、翻页判定失效。
 */
export function clampPagerOffset(offset: number, hasLeftPage: boolean, hasRightPage: boolean,
  width: number, interval: number): number {
  const min: number = hasRightPage ? -width - interval + 1 : 0;
  const max: number = hasLeftPage ? width + interval - 1 : 0;
  return Math.min(max, Math.max(min, offset));
}

/** 当前页的位置：(offset, 0, width+offset, height)。 */
export function placeCurrentPage(offset: number, width: number, height: number): PagerRect {
  return new PagerRect(offset, 0, width + offset, height);
}

/**
 * 左侧页的位置：`(-interval - width + offset, 0, -interval + offset, height)`。
 *
 * 注意宽度仍是 `width`：`(-interval+offset) - (-interval-width+offset) = width`。
 */
export function placeLeftPage(offset: number, width: number, height: number,
  interval: number): PagerRect {
  return new PagerRect(-interval - width + offset, 0, -interval + offset, height);
}

/** 右侧页的位置：`(width + interval + offset, 0, width + interval + width + offset, height)`。 */
export function placeRightPage(offset: number, width: number, height: number,
  interval: number): PagerRect {
  return new PagerRect(width + interval + offset, 0,
    width + interval + width + offset, height);
}

/** 对齐上游 `getLeftPage()`：`LEFT_TO_RIGHT` 时左侧是「上一页」，默认模式下是「下一页」。 */
export function isLeftPagePrevious(mode: number): boolean {
  return mode === MODE_LEFT_TO_RIGHT;
}

/** 对齐上游 `getRightPage()`：与 `isLeftPagePrevious` 相反。 */
export function isRightPagePrevious(mode: number): boolean {
  return mode !== MODE_LEFT_TO_RIGHT;
}
/**
 * 抬手后的**回弹/翻页位移**（对应上游 `onUp()` 的 Scroll 段）。
 *
 * ```java
 * if (mOffset >= mInterval && getLeftPage() != null) {
 *     dx = mOffset - width - mInterval;          // 已经越过左侧页 → 翻到左侧页（对齐它的起点）
 * } else if (mOffset <= -mInterval && getRightPage() != null) {
 *     dx = mOffset + width + mInterval;          // 已经越过右侧页 → 翻到右侧页
 * } else {
 *     dx = mOffset;                              // 没越过 → 回弹到 0
 * }
 * ```
 * **不是"半屏阈值"** —— 判据是 `|offset| >= interval` 且对侧**有页**。
 * 我第一版按直觉写成"过半屏才翻页"，是**错的**（上游靠 `mInterval` 这个中缝宽度判定，
 * 与屏幕宽度无关），已改正。
 */
export function snapDx(offset: number, width: number, interval: number,
  hasLeftPage: boolean, hasRightPage: boolean): number {
  if (offset >= interval && hasLeftPage) {
    return offset - width - interval;
  }
  if (offset <= -interval && hasRightPage) {
    return offset + width + interval;
  }
  return offset;
}

/**
 * 回弹动画时长（对应上游 `onUp()`）：
 * ```java
 * final float pageDelta = 7 * (float) Math.abs(mOffset) / (width + mInterval);
 * int duration = (int) ((pageDelta + 1) * 100);
 * ```
 * `Math.abs` 用**原始 offset**（不是 `dx`）；`(pageDelta + 1) * 100` 含 100ms 基础时长。
 */
export function snapDuration(offset: number, width: number, interval: number): number {
  const pageDelta: number = 7 * Math.abs(offset) / (width + interval);
  return Math.floor((pageDelta + 1) * 100);
}
/** `scrollBetweenPages` 的结果。 */
export class ScrollBetweenResult {
  /** 没被吃掉的位移（交回调用方继续处理）。 */
  readonly remain: number;
  /** 新的 offset（翻页成功时为 0）。 */
  readonly offset: number;
  /** 需要触发的翻页动作：`-1` = pageLeft，`+1` = pageRight，`0` = 不翻。 */
  readonly flip: number;

  constructor(remain: number, offset: number, flip: number) {
    this.remain = remain;
    this.offset = offset;
    this.flip = flip;
  }
}

/**
 * 页间滚动（对应上游 `PagerLayoutManager.scrollBetweenPages(dx)`，`:547-594`）。
 *
 * ## 为什么这段可以由纯函数提供（与 `tryScrollY` 的区别）
 * 上游这段的 `limit` / `remain` / `mOffset` **不依赖任何重排**：
 * 没有 `forceFill()`、没有 `mIndex` 变化参与计算。所以把它做成纯函数**不改变帧内行为**。
 * 对比 `ScrollLayoutCore.tryScrollY`：它返回的 `clampedOffsetY` 在上游是**先 `forceFill()`
 * 重排、再按新状态算出来的** → 那个量不能由纯函数提供，所以只在那里提供"判定"、控制流留在外面。
 *
 * ## 逐行对应
 * ```java
 * if (dx < 0) {                                  // 想露出左边
 *     limit = leftPage == null ? 0 : width + mInterval;
 *     if (dx > mOffset - limit) { remain = 0; mOffset -= dx; }
 *     else { if (leftPage != null) pageLeft(); remain = dx + limit - mOffset; mOffset = 0; }
 * } else {                                       // 想露出右边
 *     limit = rightPage == null ? 0 : -width - mInterval;
 *     if (dx < mOffset - limit) { remain = 0; mOffset -= dx; }
 *     else { if (rightPage != null) pageRight(); remain = dx + limit - mOffset; mOffset = 0; }
 * }
 * ```
 * **注意两个分支的比较方向相反**（`dx >` vs `dx <`）：`dx<0` 时 limit 是**正**的（+width+interval），
 * `dx>0` 时 limit 是**负**的（-width-interval）。写反会得到"永远不进翻页分支"或"每帧都翻页"。
 */
export function scrollBetweenPages(dx: number, offset: number, width: number, interval: number,
  hasLeftPage: boolean, hasRightPage: boolean): ScrollBetweenResult {
  if (dx < 0) {
    const limit: number = hasLeftPage ? width + interval : 0;
    if (dx > offset - limit) {
      return new ScrollBetweenResult(0, offset - dx, 0);
    }
    const remain: number = dx + limit - offset;
    return new ScrollBetweenResult(remain, 0, hasLeftPage ? -1 : 0);
  }
  const limit: number = hasRightPage ? -width - interval : 0;
  if (dx < offset - limit) {
    return new ScrollBetweenResult(0, offset - dx, 0);
  }
  const remain: number = dx + limit - offset;
  return new ScrollBetweenResult(remain, 0, hasRightPage ? 1 : 0);
}