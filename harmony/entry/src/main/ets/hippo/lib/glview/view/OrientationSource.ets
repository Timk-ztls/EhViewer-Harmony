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
 * `com.hippo.lib.glview.view.OrientationSource` 的 ArkTS 等价实现。
 *
 * 给 `GLRootView` 提供"屏幕旋转 + 补偿角"信息。`GLView.convertInput()` 用这两个值
 * 把触摸坐标从屏幕坐标系转换到内容坐标系 —— 转错就是"横屏时拖动方向偏 90°"。
 *
 * 两个值的含义（Android 惯例）：
 * - `getDisplayRotation()`：显示旋转角度，0/90/180/270（**度**，顺时针）
 * - `getCompensation()`：为对齐"自然方向"需要的补偿角，同样是 0/90/180/270
 *
 * 鸿蒙侧由 `GLRootView` 从 `window.getLastWindow()` 的 `window.getWindowProperties()`
 * 与 `display.getDefaultDisplaySync().rotation` 换算后实现本接口。
 */
export interface OrientationSource {
  /** 显示旋转角度（0/90/180/270，度）。 */
  getDisplayRotation(): number;

  /** 补偿角（0/90/180/270，度）。 */
  getCompensation(): number;
}
