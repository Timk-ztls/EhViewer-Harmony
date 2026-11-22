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

import {
  GLView,
  GLViewLayoutParams,
  GLViewGravityLayoutParams,
  GLViewMeasureSpec
} from '../view/GLView';
import { Gravity } from '../view/Gravity';

/**
 * `com.hippo.lib.glview.widget.GLFrameLayout` 的 ArkTS 等价实现。
 *
 * 语义：所有子视图叠在同一区域，按各自 `GravityLayoutParams.gravity` 对齐；
 * 测量时取所有子视图的最大宽高（并至少满足自身 suggested minimum）。
 *
 * ## 保留的上游 bug（**不要"修"**）
 * `onMeasure` 末尾判断是否需要二次测量时，上游写的是：
 * ```java
 * if (MeasureSpec.getSize(widthSpec) != MeasureSpec.EXACTLY || ...)
 * ```
 * 这里拿 **size** 去和 **mode 常量** 比较 —— 几乎恒为 true（size 是像素数，
 * EXACTLY 是 0x40000000），所以**二次测量几乎总会发生**。
 * 后果只是多测一遍（性能），但改对会改变"子视图在 AT_MOST 下的最终尺寸"，
 * 属于行为变化。按 1:1 口径保留，并在此标注。
 */
export class GLFrameLayout extends GLView {
  protected onMeasure(widthSpec: number, heightSpec: number): void {
    let maxWidth = 0;
    let maxHeight = 0;
    for (let i = 0, n = this.getComponentCount(); i < n; i++) {
      const component = this.getComponent(i);
      if (component.getVisibility() === GLView.GONE) {
        continue;
      }
      GLView.measureComponent(component, widthSpec, heightSpec);
      maxWidth = Math.max(maxWidth, component.getMeasuredWidth());
      maxHeight = Math.max(maxHeight, component.getMeasuredHeight());
    }

    // 考虑最小尺寸
    maxWidth = Math.max(maxWidth, this.getSuggestedMinimumWidth());
    maxHeight = Math.max(maxHeight, this.getSuggestedMinimumHeight());

    // 最终尺寸
    maxWidth = GLView.getDefaultSize(maxWidth, widthSpec);
    maxHeight = GLView.getDefaultSize(maxHeight, heightSpec);

    this.setMeasuredSize(maxWidth, maxHeight);

    // 上游用 size 与 mode 常量比较（见类注释：保留该 bug）
    if (GLViewMeasureSpec.getSize(widthSpec) !== GLViewMeasureSpec.EXACTLY
      || GLViewMeasureSpec.getSize(heightSpec) !== GLViewMeasureSpec.EXACTLY) {
      // 二次测量：按确定尺寸再排一遍
      GLView.measureAllComponents(this,
        GLViewMeasureSpec.makeMeasureSpec(maxWidth, GLViewMeasureSpec.EXACTLY),
        GLViewMeasureSpec.makeMeasureSpec(maxHeight, GLViewMeasureSpec.EXACTLY));
    }
  }

  protected onLayout(changeSize: boolean, left: number, top: number, right: number,
    bottom: number): void {
    const width = this.getWidth();
    const height = this.getHeight();

    for (let i = 0, n = this.getComponentCount(); i < n; i++) {
      const component = this.getComponent(i);
      if (component.getVisibility() === GLView.GONE) {
        continue;
      }
      const measureWidth = component.getMeasuredWidth();
      const measureHeight = component.getMeasuredHeight();
      let componentLeft: number;
      let componentTop: number;

      const lp = component.getLayoutParams() as GLViewGravityLayoutParams | null;
      const gravity = lp === null ? Gravity.NO_GRAVITY : lp.gravity;
      if (Gravity.centerHorizontal(gravity)) {
        componentLeft = Math.trunc(width / 2) - Math.trunc(measureWidth / 2);
      } else if (Gravity.right(gravity)) {
        componentLeft = width - measureWidth;
      } else {
        componentLeft = 0;
      }
      if (Gravity.centerVertical(gravity)) {
        componentTop = Math.trunc(height / 2) - Math.trunc(measureHeight / 2);
      } else if (Gravity.bottom(gravity)) {
        componentTop = height - measureHeight;
      } else {
        componentTop = 0;
      }

      component.layout(componentLeft, componentTop,
        componentLeft + measureWidth, componentTop + measureHeight);
    }
  }

  protected checkLayoutParams(p: GLViewLayoutParams | null): boolean {
    return p instanceof GLViewGravityLayoutParams;
  }

  protected generateDefaultLayoutParams(): GLViewLayoutParams {
    return new GLViewGravityLayoutParams(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
  }

  protected generateLayoutParams(p: GLViewLayoutParams): GLViewLayoutParams {
    return p === null ? this.generateDefaultLayoutParams() : new GLViewGravityLayoutParams(p);
  }
}
