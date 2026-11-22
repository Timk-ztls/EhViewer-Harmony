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

import { MotionEvent } from '../glview/util/MotionEvent';

/**
 * `com.hippo.lib.glgallery.DownUpDetector` 的 ArkTS 等价实现。
 *
 * 把"多指事件"归约成"整体是否处于按下态"，只在状态**翻转**时回调：
 * - `ACTION_DOWN` → 进入按下态，`onDown`
 * - `ACTION_POINTER_DOWN` → 透传 `onPointerDown`（不改变按下态）
 * - `ACTION_UP` → 先 `onPointerUp` 再退出按下态（`onUp`）
 * - `ACTION_CANCEL` → 退出按下态（`onUp`）
 *
 * 注意 `ACTION_POINTER_UP`（不是 `ACTION_UP`）**不在这里处理**：上游也没处理 ——
 * 多指场景下抬起一根手指不算"整体抬起"，仍由后续 `ACTION_UP` 收尾。
 * 这是 `GalleryView` 双击缩放过程中不会误触发"抬手"的原因。
 */
export interface DownUpListener {
  onDown(e: MotionEvent): void;

  onUp(e: MotionEvent): void;

  onPointerDown(e: MotionEvent): void;

  onPointerUp(e: MotionEvent): void;
}

export class DownUpDetector {
  private mStillDown: boolean = false;
  private readonly mListener: DownUpListener;

  constructor(listener: DownUpListener) {
    this.mListener = listener;
  }

  private setState(down: boolean, e: MotionEvent): void {
    if (down === this.mStillDown) {
      return;
    }
    this.mStillDown = down;
    if (down) {
      this.mListener.onDown(e);
    } else {
      this.mListener.onUp(e);
    }
  }

  onTouchEvent(ev: MotionEvent): void {
    switch (ev.getActionMasked()) {
      case MotionEvent.ACTION_DOWN:
        this.setState(true, ev);
        break;
      case MotionEvent.ACTION_POINTER_DOWN:
        this.mListener.onPointerDown(ev);
        break;
      case MotionEvent.ACTION_UP:
        this.mListener.onPointerUp(ev);
        this.setState(false, ev);
        break;
      case MotionEvent.ACTION_CANCEL:
        this.setState(false, ev);
        break;
      default:
        break;
    }
  }

  isDown(): boolean {
    return this.mStillDown;
  }
}
