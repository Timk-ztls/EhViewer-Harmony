/*
 * Copyright 2014 Qihoo Inc.
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

import { MathUtils } from '../../yorozuya/MathUtils';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { CanvasAnimation } from './CanvasAnimation';

/**
 * `com.hippo.lib.glview.anim.AlphaAnimation` 的 ArkTS 等价实现（inventory S0330）。
 *
 * 语义：把 `[from, to]` 的 alpha 按进度线性插值，并 `multiplyAlpha` 到画布上。
 *
 * 三个照搬点：
 *   1. 用 **multiplyAlpha**（乘）而不是 setAlpha —— 会与画布已有 alpha 叠加
 *   2. 插值结果额外 clamp 到 [0,1]：`from`/`to` 传入越界值时不会画出非法 alpha
 *   3. `getCanvasSaveFlags()` 只声明 `SAVE_FLAG_ALPHA`（不改矩阵，避免每帧存全量状态）
 */
export class AlphaAnimation extends CanvasAnimation {
  private readonly mStartAlpha: number;
  private readonly mEndAlpha: number;
  private mCurrentAlpha: number;

  constructor(from: number, to: number) {
    super();
    this.mStartAlpha = from;
    this.mEndAlpha = to;
    this.mCurrentAlpha = from;
  }

  apply(canvas: GLCanvas): void {
    canvas.multiplyAlpha(this.mCurrentAlpha);
  }

  getCanvasSaveFlags(): number {
    return GLCanvas.SAVE_FLAG_ALPHA;
  }

  protected onCalculate(progress: number): void {
    this.mCurrentAlpha = MathUtils.clamp(
      this.mStartAlpha + (this.mEndAlpha - this.mStartAlpha) * progress, 0.0, 1.0);
  }

  /** 测试与调试用：当前 alpha（上游是 private 字段，无 getter）。 */
  getCurrentAlpha(): number {
    return this.mCurrentAlpha;
  }
}
