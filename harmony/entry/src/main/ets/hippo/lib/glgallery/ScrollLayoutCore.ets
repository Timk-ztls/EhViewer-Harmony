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
 * `ScrollLayoutManager` 的**纯几何内核**（上游没有同名文件，是把 1095 行里的可测数学抽出来）。
 *
 * ## 为什么抽出来
 * `ScrollLayoutManager` 里真正容易错的是这几个数：横向可拖距离、纵向"还能往上/往下滚多少"、
 * 到底部的判定。它们混在 `scrollInternal` 里，与视图池/动画/画布耦合，只能靠跑真机验证。
 * 抽成纯函数后：**不依赖 GalleryView、不依赖画布、可以在 node 里逐条断言**。
 *
 * ## 逐条对上游（`ScrollLayoutManager.java:619` 起的 `scrollInternal`）
 * ```
 * // 横向：只在页面放大后（margin > 0）才可拖，且夹在 [-margin, 0]
 * int margin = pageWidth - width;
 * if (margin > 0 && 0 != dxInt) {
 *     mOffsetX = MathUtils.clamp(oldOffsetX - dxInt, -margin, 0);
 * }
 *
 * // 纵向向上（remainY < 0，想把更上面露出来）
 * limit = (mIndex > 0) ? (int) (-height * RESERVATION) + mInterval : 0;
 *
 * // 纵向向下（remainY > 0，想看下一张）
 * getBottomState();
 * limit = hasNext ? (int) (height * (1 + RESERVATION)) - mInterval : height;
 * limit = Math.min(bottom, limit);      // 「页没填满屏幕」时要修正
 * ```
 * `RESERVATION = 1f`（上游常量，允许露出上一张/下一张的 1 屏）。
 */

/** 上游 `ScrollLayoutManager.RESERVATION = 1f`（**基值**，实际用的是 `reservation(scale)`）。 */
export const RESERVATION: number = 1;

/**
 * 对齐上游 `ScrollLayoutManager.getReservation()`（V-01 修复点）：
 *
 * ```java
 * private float getReservation() {
 *     return Math.max(RESERVATION, (((1 + 2 * RESERVATION) * mScale) - 1) / 2);
 * }
 * ```
 * `mScale = 1` → `1.0`；`1.5` → `1.75`；`2.0` → `2.5`。
 *
 * **我第一版把这里硬化成常量 1** —— 只抄了 `RESERVATION` 这半句、漏了外面那层 `max(...)`。
 * 后果：放大到 2 倍时上游允许露出 2.5 屏、我们只允许 1 屏，**差 1.5 屏**，
 * 症状是「放大后往上滑会突然弹回」。
 */
export function reservation(scale: number): number {
  return Math.max(RESERVATION, ((1 + 2 * RESERVATION) * scale - 1) / 2);
}

/** 横向滚动的结果。 */
export class HorizontalScroll {
  /** 新的 offsetX（负值 = 内容向左移）。 */
  readonly offsetX: number;
  /** 是否真的动了（用于决定要不要 requestFill）。 */
  readonly changed: boolean;
  /** 页面宽度超出视口多少（`<= 0` 表示不可横拖）。 */
  readonly margin: number;

  constructor(offsetX: number, changed: boolean, margin: number) {
    this.offsetX = offsetX;
    this.changed = changed;
    this.margin = margin;
  }
}

/**
 * 横向滚动：对应上游 `scrollInternal` 的第一段。
 *
 * 语义要点：
 *   - **只有 `pageWidth > viewWidth`（放大后）才可拖**；否则 `offsetX` 恒为 0
 *   - `offsetX` 恒 `<= 0`：`-margin` 时露出右边缘，`0` 时左对齐
 *   - `dx` 为正 = 手指右移 = 内容左移（`oldOffsetX - dx`）
 */
export function scrollHorizontal(oldOffsetX: number, dx: number,
  pageWidth: number, viewWidth: number): HorizontalScroll {
  const margin: number = pageWidth - viewWidth;
  if (margin <= 0 || dx === 0) {
    // 上游：margin <= 0 时 offsetX 原样（实际永远是 0）；dx = 0 时不改
    return new HorizontalScroll(Math.min(0, Math.max(-Math.max(0, margin), oldOffsetX)), false, margin);
  }
  const exceptOffsetX: number = oldOffsetX - dx;
  const next: number = Math.min(0, Math.max(-margin, exceptOffsetX));
  return new HorizontalScroll(next, next !== oldOffsetX, margin);
}

/**
 * 向上滚动时的**上限**（对应上游 `remainY < 0` 分支里的 `limit`）。
 *
 * - `index > 0`（不是第一张）：允许露出上一张的 `RESERVATION` 屏，但要扣掉 `interval`
 * - `index == 0`：到 0 为止（不能露出"第一张上面"的空白）
 *
 * 返回的是 `offsetY` 的**最小值**（`offsetY` 越负内容越靠上）。
 */
export function topLimit(index: number, viewHeight: number, interval: number,
  reservationValue: number = RESERVATION): number {
  if (index > 0) {
  return Math.trunc(-viewHeight * reservationValue) + interval;
  }
  return 0;
}

/**
 * 向下滚动时的**上限**（对应上游 `remainY > 0` 分支里的 `limit`）。
 *
 * - `hasNext`：允许露出下一张的 `RESERVATION` 屏，扣掉 `interval`
 * - `!hasNext`：到 `viewHeight` 为止
 * - **最后与 `bottom` 取 min** —— 上游注释 "Fix limit for page not fill screen"：
 *   页没填满屏幕时 `bottom` 比 limit 小，直接用 limit 会滚过头露出空白
 */
export function bottomLimit(hasNext: boolean, viewHeight: number, interval: number,
  bottom: number, reservationValue: number = RESERVATION): number {
  let limit: number = hasNext
    ? Math.floor(viewHeight * (1 + reservationValue)) - interval
    : viewHeight;
  limit = Math.min(bottom, limit);
  return limit;
}

/**
 * 向上滚动能否**完全**容纳（对应上游 `mOffsetY - remainY <= limit` 的判定）。
 *
 * `remainY < 0`（往上滚），`offsetY - remainY` 是目标位置；`<= limit` 表示还能容纳。
 * 不能容纳时上游会把 `offsetY` 顶到 `limit`，并**多偏 1 像素**避免死循环。
 */
export function canScrollUp(offsetY: number, remainY: number, limit: number): boolean {
  return offsetY - remainY <= limit;
}

/** 向上滚动被边界挡住时的处理结果。 */
export class VerticalClamp {
  /** 新的 offsetY。 */
  readonly offsetY: number;
  /** 没被消费掉的位移（交父容器做越界效果）。 */
  readonly remainY: number;
  /** 是否需要 `forceFill()`（上游在 index > 0 的分支里调它）。 */
  readonly forceFill: boolean;
  /** 是否发生了越界（`overScrollEdge`）。 */
  readonly overScroll: boolean;

  constructor(offsetY: number, remainY: number, forceFill: boolean, overScroll: boolean) {
    this.offsetY = offsetY;
    this.remainY = remainY;
    this.forceFill = forceFill;
    this.overScroll = overScroll;
  }
}

/**
 * 向上滚动被边界挡住（对应上游 `else` 分支）：
 * ```
 * if (mIndex > 0) {
 *     mOffsetY = limit;
 *     remainY = remainY + limit - mOffsetY;   // ← 注意这里用的是**已赋值后**的 mOffsetY，恒为 limit
 *     ++mOffsetY; ++remainY;                  // 偏 1 像素避免死循环
 *     forceFill();
 * } else {
 *     if (mOffsetY != limit) { mOffsetY = limit; }
 *     if (!fling) overScrollEdge(0, remainY + limit - mOffsetY, x, y);
 *     remainY = 0;
 * }
 * ```
 * 上游那两行 `remainY = remainY + limit - mOffsetY` 在赋值后就等于 `remainY + 0`（恒无变化），
 * 属于**冗余写法但无害**（与 D-050 同类：看着像 bug，实则等价）。本层按等价语义实现并注明。
 */
export function clampUp(index: number, offsetY: number, remainY: number, limit: number,
  fling: boolean): VerticalClamp {
  if (index > 0) {
    const newOffsetY: number = limit + 1;
    // 上游：remainY 先 += (limit - limit) 再加 1 → 等价于 +1
    const newRemainY: number = remainY + 1;
    return new VerticalClamp(newOffsetY, newRemainY, true, false);
  }
  const newOffsetY: number = limit;
  return new VerticalClamp(newOffsetY, 0, false, !fling);
}

/**
 * 判断"能否把整段位移都吃掉"的纵向滚动（对应上游 `remainY` 循环的一次迭代）。
 *
 * 返回 `consumed = true` 时表示位移吃完、`offsetY` 已更新；`false` 表示被边界挡住，
 * 调用方应按 `VerticalClamp` 处理。
 */
export class VerticalStep {
  /** 位移是否被完整吃掉。 */
  readonly done: boolean;
  /** 位移被吃掉时的 offsetY（`done = false` 时是**原值**，与上游一致）。 */
  readonly offsetY: number;
  /**
   * 被挡住时应采用的 offsetY（V-02 修复点）。
   *
   * 上游在 `else` 分支里会**回吸**：
   * ```
   * 向上 index>0 → mOffsetY = limit + 1（偏 1 像素防死循环）
   * 向上 index==0 → mOffsetY = limit
   * 向下 hasNext → mOffsetY -= (bottom - limit) 再 --mOffsetY
   * 向下 !hasNext → mOffsetY -= (bottom - limit)
   * ```
   * 我第一版只返回原值，调用方拿到后若照搬就会「卡在越界位置不回吸」——
   * 症状是「滑到底后停在一半，下一帧才弹回」。
   */
  readonly clampedOffsetY: number;

  constructor(done: boolean, offsetY: number, clampedOffsetY: number) {
    this.done = done;
    this.offsetY = offsetY;
    this.clampedOffsetY = clampedOffsetY;
  }
}

export function tryScrollY(offsetY: number, remainY: number, index: number,
  viewHeight: number, interval: number, hasNext: boolean, bottom: number,
  reservationValue: number = RESERVATION): VerticalStep {
  if (remainY < 0) {
    const limit: number = topLimit(index, viewHeight, interval, reservationValue);
    if (canScrollUp(offsetY, remainY, limit)) {
      return new VerticalStep(true, offsetY - remainY, offsetY - remainY);
    }
    // 被挡住：按上游回吸（V-02）
    const clamped: number = index > 0 ? limit + 1 : limit;
    return new VerticalStep(false, offsetY, clamped);
  }
  const limit: number = bottomLimit(hasNext, viewHeight, interval, bottom, reservationValue);
  if (bottom - remainY >= limit) {
    return new VerticalStep(true, offsetY - remainY, offsetY - remainY);
  }
  // 被挡住：按上游回吸（V-02）。`hasNext` 分支还要再偏 1 像素。
  let clamped: number = offsetY - (bottom - limit);
  if (hasNext) {
    clamped = clamped - 1;
  }
  return new VerticalStep(false, offsetY, clamped);
}
