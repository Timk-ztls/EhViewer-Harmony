/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0431   上游: com/hippo/lib/yorozuya/ViewUtils.java（454 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/ViewUtils.ets
 *
 * 【**部分移植**：MeasureSpec 运算 / 几何判定 / View id 生成，其余是 Android View API 封装】
 *
 * 移植的（纯逻辑，可断言）：
 *   · `MeasureSpec.getMode / getSize / makeMeasureSpec` —— 上游直接调 `View.MeasureSpec`，
 *     那是**两个整数打包成一个 int** 的位运算，与平台无关 → 这里自己实现
 *   · `getSuitableSize(size, measureSpec)` —— 三种 spec 模式下的尺寸决策（**唯一有分支的业务逻辑**）
 *   · `isViewUnder(view, x, y, slop)` —— 命中判定（含 translation 与 slop 容差）
 *   · `getX2 / getY2` —— `right + translationX` / `bottom + translationY`
 *   · `getIndexInParent(view, children)` —— 在父容器里的下标（找不到 → -1）
 *   · `generateViewId()` —— 从 1 递增，超过 `0x00FFFFFF` 回绕到 1（**不回绕到 0**）
 *   · `MAX_SIZE = Integer.MAX_VALUE & ~(0x3 << 30)`
 *
 * 不移植的（Android View/Canvas/反射体系，归 ui-widget 或 na）：
 *   `getCenterInWindow(s)` / `getLocationInWindow` / `getCenterInAncestor` / `getAncestor` /
 *   `getChild` / `getBitmapFromView`（Canvas 绘制）/ `removeFromParent` /
 *   `remove/addHardwareAccelerationSupport` / `measureView` / `removeOnGlobalLayoutListener` /
 *   `transformPointToViewLocal`（矩阵）/ `setEnabledRecursively` / `dumpViewHierarchy` /
 *   `translationXBy/YBy`（setter 调用）/ `$$(activity|dialog|view, id)`（findViewById）
 *   —— 这些在 ArkUI 里要么没有对应 API（HardwareAcceleration / findViewByid / getDrawingCache），
 *   要么变成**声明式状态**（translation 是 `@State`，不是 setter）。
 *
 * 平台差异：
 *  1. `View` → 注入几何接口 `ViewGeometryLike`（只声明本文件用到的 6 个读数）。
 *     ArkUI 的 `Component` 不出这些读数，调用方自己维护或从 `onAreaChange` 缓存。
 *  2. `AtomicInteger.compareAndSet` → JS 单线程，直接用普通计数器（**不需要**原子性）。
 *  3. `View.getLeft()/getRight()` 是**相对父容器**的坐标；ArkUI 用 `position`/`offset` +
 *     `onAreaChange`，语义接近但需要在调用方换算，文件头已注明。
 */

/** 上游 `View.MeasureSpec` 的两个模式常量（Android 值） */
export class MeasureSpec {
  /** 父容器不对子 View 施加约束 */
  static readonly UNSPECIFIED: number = 0;
  /** 父容器已决定精确尺寸 */
  static readonly EXACTLY: number = 1;
  /** 子 View 不得超过某尺寸 */
  static readonly AT_MOST: number = 2;

  /** `View.MeasureSpec.getMode(measureSpec)`：取高 2 位 */
  static getMode(measureSpec: number): number {
    return (measureSpec & ViewUtils.MODE_MASK) >>> ViewUtils.MODE_SHIFT;
  }

  /** `View.MeasureSpec.getSize(measureSpec)`：取低 30 位 */
  static getSize(measureSpec: number): number {
    return measureSpec & ViewUtils.SIZE_MASK;
  }

  /** `View.MeasureSpec.makeMeasureSpec(size, mode)`：打包 */
  static makeMeasureSpec(size: number, mode: number): number {
    return (size & ViewUtils.SIZE_MASK) | ((mode << ViewUtils.MODE_SHIFT) & ViewUtils.MODE_MASK_IN_PLACE);
  }
}

/** 本文件用到的 View 几何读数（`getLeft()/getRight()/getTop()/getBottom()/getTranslationX/Y()`） */
export interface ViewGeometryLike {
  left: number;
  right: number;
  top: number;
  bottom: number;
  translationX: number;
  translationY: number;
}

export class ViewUtils {

  /** 上游 `MAX_SIZE = Integer.MAX_VALUE & ~(0x3 << 30)` —— 去掉高 2 位（Mode 位） */
  static readonly MAX_SIZE: number = 0x3FFFFFFF;
  /** `MeasureSpec` 的位布局：高 2 位是 mode，低 30 位是 size */
  static readonly MODE_SHIFT: number = 30;
  static readonly MODE_MASK: number = 0xC0000000 | 0;
  static readonly MODE_MASK_IN_PLACE: number = 0xC0000000 | 0;
  static readonly SIZE_MASK: number = 0x3FFFFFFF;

  /** 上游 `sNextGeneratedId = new AtomicInteger(1)` */
  private static sNextGeneratedId: number = 1;

  /**
   * 对应上游 `getSuitableSize(size, measureSpec)`：
   * `UNSPECIFIED` → size；`EXACTLY` → specSize；`AT_MOST` → size==0 ? specSize : min(size, specSize)
   * （**注意 AT_MOST 分支是 `return`，不落到底部 return**，照搬。）
   */
  static getSuitableSize(size: number, measureSpec: number): number {
    let result: number = size;
    const specMode: number = MeasureSpec.getMode(measureSpec);
    const specSize: number = MeasureSpec.getSize(measureSpec);

    if (specMode === MeasureSpec.UNSPECIFIED) {
      result = size;
    } else if (specMode === MeasureSpec.EXACTLY) {
      result = specSize;
    } else if (specMode === MeasureSpec.AT_MOST) {
      return (size === 0) ? specSize : Math.min(size, specSize);
    }
    return result;
  }

  /**
   * 对应上游 `isViewUnder(view, x, y, slop)`：
   * 命中条件 `left+tX-slop <= x < right+tX+slop` 且 y 同理（**左闭右开 + 容差外扩**）。
   */
  static isViewUnder(view: ViewGeometryLike | null, x: number, y: number, slop: number): boolean {
    if (view === null) {
      return false;
    }
    return x >= view.left + view.translationX - slop
      && x < view.right + view.translationX + slop
      && y >= view.top + view.translationY - slop
      && y < view.bottom + view.translationY + slop;
  }

  /** `right + translationX`（视觉右边界） */
  static getX2(view: ViewGeometryLike): number {
    return view.right + view.translationX;
  }

  /** `bottom + translationY`（视觉下边界） */
  static getY2(view: ViewGeometryLike): number {
    return view.bottom + view.translationY;
  }

  /** 对应上游 `getIndexInParent(view)`：在 `children` 里找引用相等的下标，找不到 → -1 */
  static getIndexInParent(view: Object, children: Object[]): number {
    for (let i = 0; i < children.length; i++) {
      if (children[i] === view) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 对应上游 `generateViewId()`：返回当前值并递增；超过 `0x00FFFFFF` **回绕到 1（不是 0）**。
   * aapt 生成的 id 高字节非零，所以必须限制在该范围以下。
   * 上游用 CAS 循环；**JS 单线程，直接读改写即可**（不需要原子性）。
   */
  static generateViewId(): number {
    const result: number = ViewUtils.sNextGeneratedId;
    let newValue: number = result + 1;
    if (newValue > 0x00FFFFFF) {
      newValue = 1; // Roll over to 1, not 0.
    }
    ViewUtils.sNextGeneratedId = newValue;
    return result;
  }

  /** 测试用：把 id 计数器重置到指定值（上游是 private AtomicInteger，无此方法） */
  static resetNextGeneratedIdForTest(value: number): void {
    ViewUtils.sNextGeneratedId = value;
  }
}