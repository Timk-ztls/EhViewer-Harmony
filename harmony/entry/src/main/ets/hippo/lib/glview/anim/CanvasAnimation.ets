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

import { Animation } from './Animation';
import { GLCanvas } from '../glrenderer/GLCanvas';

/**
 * `com.hippo.lib.glview.anim.CanvasAnimation` 的 ArkTS 等价实现。
 *
 * 在普通 `Animation` 之上加两个画布相关能力：
 * - `getCanvasSaveFlags()`：本动画会改哪些画布状态（alpha / matrix），
 *   `GLRootView` 据此决定 `save()` 时保存哪部分，避免每帧无谓地存全量状态
 * - `apply(canvas)`：把当前进度对应的变换写到画布上
 *
 * 生命周期由 `GLRootView.registerLaunchedAnimation()` 接管：每帧对所有活动动画
 * 调一次 `calculate(now)`，返回的保存标志用于 `save/restore` 配对。
 */
export abstract class CanvasAnimation extends Animation {
  /** 本动画会修改的画布状态位（`GLCanvas.SAVE_FLAG_ALPHA` / `SAVE_FLAG_MATRIX`）。 */
  abstract getCanvasSaveFlags(): number;

  /** 把当前进度应用到画布（translate/rotate/alpha 等）。 */
  abstract apply(canvas: GLCanvas): void;
}
