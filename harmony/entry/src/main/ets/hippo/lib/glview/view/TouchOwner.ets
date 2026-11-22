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
 * `com.hippo.lib.glview.view.TouchOwner` 的 ArkTS 等价实现。
 *
 * `TouchHelper` 通过这个接口与"被点击的视图"解耦：helper 只关心
 * 按下/抬起/长按的时序，不关心视图是什么。`GLView` 是唯一实现。
 */
export interface TouchOwner {
  /** 记录热点（按压水波纹/高亮的中心）。 */
  setHotspot(x: number, y: number): void;

  isEnabled(): boolean;

  isPressed(): boolean;

  setPressed(pressed: boolean): void;

  isClickable(): boolean;

  isLongClickable(): boolean;

  performClick(): boolean;

  performLongClick(): boolean;

  /** 视图局部坐标系下的宽（用于判断手指是否移出范围）。 */
  getWidth(): number;

  getHeight(): number;
}
