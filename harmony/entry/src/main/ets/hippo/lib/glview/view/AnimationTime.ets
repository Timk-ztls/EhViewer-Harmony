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

import { Animation } from '../anim/Animation';

/**
 * `com.hippo.lib.glview.view.AnimationTime` 的 ArkTS 等价实现。
 *
 * 动画时间应当是"这一帧会被显示的 vsync 时刻"，但那是未来时间、无法得知；
 * 因此上游取 `eglSwapBuffers` 之后的系统时间（即 `onDrawFrame` 被回调时）作为近似。
 *
 * 鸿蒙侧同样由 `GLRootView` 在每帧渲染入口调 `update()`：时间基准必须**每帧统一**，
 * 否则同一个 `Animation.calculate()` 在不同子视图里拿到不同 now，会出现
 * "同一动画的两个子元素进度不一致"的抖动。
 *
 * 时钟用 `Animation.uptimeMillis()`（单调），不是 `Date.now()`（墙钟会跳）。
 */
export class AnimationTime {
  private static sTime: number = 0;

  /** 把当前单调时钟设为本帧动画时间（`GLRootView` 每帧调用一次）。 */
  static update(): void {
    AnimationTime.sTime = Animation.uptimeMillis();
  }

  /** 本帧动画时间（毫秒）。 */
  static get(): number {
    return AnimationTime.sTime;
  }

  /** 重置并返回当前时间（启动时用）。 */
  static startTime(): number {
    AnimationTime.sTime = Animation.uptimeMillis();
    return AnimationTime.sTime;
  }
}
