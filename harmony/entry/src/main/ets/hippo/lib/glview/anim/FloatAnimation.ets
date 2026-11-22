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

import { Animation } from './Animation';
import { MathUtils } from '../../yorozuya/MathUtils';

/**
 * `com.hippo.lib.glview.anim.FloatAnimation` 的 ArkTS 等价实现。
 *
 * 在 `[from, to]` 区间上按 progress 线性插值，`get()` 取当前值。
 * `GLProgressView` 的四个不确定进度动画（trimStart/trimEnd/trimOffset/trimRotation）
 * 都用它 —— 子类只覆写 `onCalculate` 把 `get()` 抄进自己的字段。
 */
export class FloatAnimation extends Animation {
  private mFrom: number = 0;
  private mTo: number = 0;
  private mCurrent: number = 0;

  setRange(from: number, to: number): void {
    this.mFrom = from;
    this.mTo = to;
  }

  protected onCalculate(progress: number): void {
    this.mCurrent = MathUtils.lerp(this.mFrom, this.mTo, progress);
  }

  get(): number {
    return this.mCurrent;
  }
}
