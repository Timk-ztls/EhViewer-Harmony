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
import {
  GLView,
  GLViewLayoutParams,
  GLViewGravityLayoutParams,
  GLViewMeasureSpec
} from '../view/GLView';
import { Gravity } from '../view/Gravity';

/** `GLLinearLayout.LayoutParams`：在 gravity 之上加 `weight`（权重分配剩余空间）。 */
export class GLLinearLayoutParams extends GLViewGravityLayoutParams {
  weight: number = 0.0;

  /** `(LayoutParams source)` 与 `(w,h)` 合一。 */
  constructor(width: number | GLViewLayoutParams, height?: number) {
    super(width, height === undefined ? 0 : height);
    if (typeof width !== 'number' && width instanceof GLLinearLayoutParams) {
      this.weight = width.weight;
    }
  }
}

/**
 * `com.hippo.lib.glview.widget.GLLinearLayout` 的 ArkTS 等价实现。
 *
 * 单方向线性布局（行或列），支持 `weight` 权重分配剩余空间与 `gravity` 对齐。
 * `GalleryPageView` 的中间信息面板就是它（页码 / 错误图标 / 进度圈竖排）。
 *
 * ## 测量策略（两条分支，别合并）
 * 1. **主轴尺寸确定（EXACTLY）**：先测所有"无权重"子视图并扣掉它们的尺寸，
 *    剩下的空间按 `weight` 比例分给有权限的子视图（各自 spec 设为 EXACTLY）
 * 2. 否则：所有子视图按 `layoutWidthSpec/layoutHeightSpec` 统一测量
 *
 * 注意 `layoutWidthSpec = makeMeasureSpec(size - paddings, mode)`：
 * 先在**尺寸**上扣掉 padding，mode 原样透传。
 *
 * ## 保留的上游细节
 * - `onMeasure` 里累加间隔时用 `if (i != 0)` 判断，而 `i` 是**包含 GONE 子视图的索引**：
 *   若第 0 个是 GONE、第 1 个是第一个可见子视图，则它会**多算一次 interval**。
 *   这会让 GONE 在前的布局多出一点间距。按 1:1 口径保留。
 * - `setOrientation` 的 javadoc 写"默认 HORIZONTAL"，实际字段默认 `VERTICAL`（注释错、行为对）。
 */
export class GLLinearLayout extends GLView {
  static readonly HORIZONTAL: number = 0;
  static readonly VERTICAL: number = 1;

  private mInterval: number = 0;
  private mOrientation: number = GLLinearLayout.VERTICAL;

  private readonly mTempList: GLView[] = [];

  setInterval(interval: number): void {
    if (this.mInterval !== interval) {
      this.mInterval = interval;
      this.requestLayout();
    }
  }

  /** 列还是行。默认 `VERTICAL`（上游 javadoc 写 HORIZONTAL 是笔误，字段默认值才是准的）。 */
  setOrientation(orientation: number): void {
    if (this.mOrientation !== orientation) {
      this.mOrientation = orientation;
      this.requestLayout();
    }
  }

  getOrientation(): number {
    return this.mOrientation;
  }

  getInterval(): number {
    return this.mInterval;
  }

  protected onMeasure(widthSpec: number, heightSpec: number): void {
    const layoutWidthSpec = GLViewMeasureSpec.makeMeasureSpec(
      GLViewMeasureSpec.getSize(widthSpec) - this.mPaddings.left - this.mPaddings.right,
      GLViewMeasureSpec.getMode(widthSpec));
    const layoutHeightSpec = GLViewMeasureSpec.makeMeasureSpec(
      GLViewMeasureSpec.getSize(heightSpec) - this.mPaddings.top - this.mPaddings.bottom,
      GLViewMeasureSpec.getMode(heightSpec));

    if (this.mOrientation === GLLinearLayout.HORIZONTAL
      && GLViewMeasureSpec.getMode(widthSpec) === GLViewMeasureSpec.EXACTLY) {
      let width = GLViewMeasureSpec.getSize(layoutWidthSpec);
      let sumWeight = 0.0;

      for (let i = 0, n = this.getComponentCount(); i < n; i++) {
        const component = this.getComponent(i);
        if (component.getVisibility() === GLView.GONE) {
          continue;
        }
        const lp = component.getLayoutParams() as GLLinearLayoutParams | null;
        const weight = lp === null ? 0 : lp.weight;

        if (weight > 0.0) {
          sumWeight += weight;
          this.mTempList.push(component);
        } else {
          GLView.measureComponent(component, layoutWidthSpec, layoutHeightSpec);
          width -= component.getMeasuredWidth();
        }
      }

      for (let i = 0; i < this.mTempList.length; i++) {
        const component = this.mTempList[i];
        const lp = component.getLayoutParams() as GLLinearLayoutParams | null;
        const weight = lp === null ? 0 : lp.weight;
        const height = lp === null ? GLViewLayoutParams.WRAP_CONTENT : lp.height;
        const componentWidthSpec = GLViewMeasureSpec.makeMeasureSpec(
          Math.trunc(width * weight / sumWeight), GLViewMeasureSpec.EXACTLY);
        const componentHeightSpec = GLView.getComponentSpec(layoutHeightSpec, height);
        component.measure(componentWidthSpec, componentHeightSpec);
      }

      this.mTempList.length = 0;
    } else if (this.mOrientation === GLLinearLayout.VERTICAL
      && GLViewMeasureSpec.getMode(heightSpec) === GLViewMeasureSpec.EXACTLY) {
      let height = GLViewMeasureSpec.getSize(layoutHeightSpec);
      let sumWeight = 0.0;

      for (let i = 0, n = this.getComponentCount(); i < n; i++) {
        const component = this.getComponent(i);
        if (component.getVisibility() === GLView.GONE) {
          continue;
        }
        const lp = component.getLayoutParams() as GLLinearLayoutParams | null;
        const weight = lp === null ? 0 : lp.weight;

        if (weight > 0.0) {
          sumWeight += weight;
          this.mTempList.push(component);
        } else {
          GLView.measureComponent(component, layoutWidthSpec, layoutHeightSpec);
          height -= component.getMeasuredHeight();
        }
      }

      for (let i = 0; i < this.mTempList.length; i++) {
        const component = this.mTempList[i];
        const lp = component.getLayoutParams() as GLLinearLayoutParams | null;
        const weight = lp === null ? 0 : lp.weight;
        const width = lp === null ? GLViewLayoutParams.WRAP_CONTENT : lp.width;
        const componentWidthSpec = GLView.getComponentSpec(layoutWidthSpec, width);
        const componentHeightSpec = GLViewMeasureSpec.makeMeasureSpec(
          Math.trunc(height * weight / sumWeight), GLViewMeasureSpec.EXACTLY);
        component.measure(componentWidthSpec, componentHeightSpec);
      }

      this.mTempList.length = 0;
    } else {
      GLView.measureAllComponents(this, layoutWidthSpec, layoutHeightSpec);
    }

    let maxWidth = 0;
    let maxHeight = 0;
    for (let i = 0, n = this.getComponentCount(); i < n; i++) {
      const component = this.getComponent(i);
      if (component.getVisibility() === GLView.GONE) {
        continue;
      }

      if (this.mOrientation === GLLinearLayout.VERTICAL) {
        maxWidth = Math.max(maxWidth, component.getMeasuredWidth());
        // 上游用 `i != 0` 判断间隔（i 含 GONE），保留该行为
        if (i !== 0) {
          maxHeight += this.mInterval;
        }
        maxHeight += component.getMeasuredHeight();
      } else if (this.mOrientation === GLLinearLayout.HORIZONTAL) {
        maxHeight = Math.max(maxHeight, component.getMeasuredHeight());
        if (i !== 0) {
          maxWidth += this.mInterval;
        }
        maxWidth += component.getMeasuredWidth();
      }
    }

    const paddings = this.getPaddings();
    maxWidth = maxWidth + paddings.left + paddings.right;
    maxHeight = maxHeight + paddings.top + paddings.bottom;

    this.setMeasuredSize(GLView.getDefaultSize(maxWidth, widthSpec),
      GLView.getDefaultSize(maxHeight, heightSpec));
  }

  protected onLayout(changeSize: boolean, left: number, top: number, right: number,
    bottom: number): void {
    const width = this.getWidth();
    const height = this.getHeight();
    const paddings: Rect = this.getPaddings();
    let componentLeft: number = 0;
    let componentTop: number = 0;

    if (this.mOrientation === GLLinearLayout.VERTICAL) {
      componentTop = paddings.top;

      for (let i = 0, n = this.getComponentCount(); i < n; i++) {
        const component = this.getComponent(i);
        if (component.getVisibility() === GLView.GONE) {
          continue;
        }
        const measureWidth = component.getMeasuredWidth();
        const measureHeight = component.getMeasuredHeight();

        const lp = component.getLayoutParams() as GLViewGravityLayoutParams | null;
        const gravity = lp === null ? Gravity.NO_GRAVITY : lp.gravity;
        componentLeft = GLView.getDefaultBegin(width, measureWidth, paddings.left,
          paddings.right, Gravity.getPosition(gravity, Gravity.HORIZONTAL));
        component.layout(componentLeft, componentTop,
          componentLeft + measureWidth, componentTop + measureHeight);

        componentTop += measureHeight + this.mInterval;
      }
    } else if (this.mOrientation === GLLinearLayout.HORIZONTAL) {
      componentLeft = paddings.left;

      for (let i = 0, n = this.getComponentCount(); i < n; i++) {
        const component = this.getComponent(i);
        if (component.getVisibility() === GLView.GONE) {
          continue;
        }
        const measureWidth = component.getMeasuredWidth();
        const measureHeight = component.getMeasuredHeight();

        const lp = component.getLayoutParams() as GLViewGravityLayoutParams | null;
        const gravity = lp === null ? Gravity.NO_GRAVITY : lp.gravity;
        componentTop = GLView.getDefaultBegin(height, measureHeight, paddings.top,
          paddings.bottom, Gravity.getPosition(gravity, Gravity.VERTICAL));
        component.layout(componentLeft, componentTop,
          componentLeft + measureWidth, componentTop + measureHeight);

        componentLeft += measureWidth + this.mInterval;
      }
    }
  }

  protected checkLayoutParams(p: GLViewLayoutParams | null): boolean {
    return p instanceof GLLinearLayoutParams;
  }

  protected generateDefaultLayoutParams(): GLViewLayoutParams {
    return new GLLinearLayoutParams(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
  }

  protected generateLayoutParams(p: GLViewLayoutParams): GLViewLayoutParams {
    return p === null ? this.generateDefaultLayoutParams() : new GLLinearLayoutParams(p);
  }
}
