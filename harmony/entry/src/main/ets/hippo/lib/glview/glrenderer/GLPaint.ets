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

/**
 * `com.hippo.lib.glview.glrenderer.GLPaint` 的 ArkTS 等价实现（1:1，无平台语义）。
 *
 * 只承载三条画笔属性：颜色、背景色（`drawOval`/`drawArc` 画"环"时用它填内圈）、线宽。
 * 上游 `setLineWidth` 对负值抛 `IllegalArgumentException`，这里抛 `Error`（DEVIATIONS §5 第 8 条）。
 */
export class GLPaint {
  private mLineWidth: number = 1.0;
  private mColor: number = 0;
  private mBackgroundColor: number = 0;

  setColor(color: number): void {
    this.mColor = color;
  }

  getColor(): number {
    return this.mColor;
  }

  setBackgroundColor(backgroundColor: number): void {
    this.mBackgroundColor = backgroundColor;
  }

  getBackgroundColor(): number {
    return this.mBackgroundColor;
  }

  setLineWidth(width: number): void {
    if (width < 0) {
      throw new Error('width < 0');
    }
    this.mLineWidth = width;
  }

  getLineWidth(): number {
    return this.mLineWidth;
  }
}
