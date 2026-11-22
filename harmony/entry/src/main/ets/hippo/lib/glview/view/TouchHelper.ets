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

import { MotionEvent } from '../util/MotionEvent';
import { LayoutUtils } from '../../yorozuya/LayoutUtils';
import { SimpleHandler } from '../../yorozuya/SimpleHandler';
import { TouchOwner } from './TouchOwner';

/**
 * `com.hippo.lib.glview.view.TouchHelper` 的 ArkTS 等价实现。
 *
 * 把"按下→（可能长按）→抬起→点击"的时序从视图里拆出来，只依赖 `TouchOwner` 接口。
 * 这是 `GLView` 里点击/长按行为的唯一实现处。
 *
 * ## 时序常量（与 AOSP ViewConfiguration 一致，不许自己调）
 * | 常量 | 值 | 含义 |
 * |---|---:|---|
 * | `TAP_TIMEOUT` | 100ms | 按下后多久认定为"已按下"（此前抬起算 pre-pressed） |
 * | `LONG_PRESS_TIMEOUT` | 500ms | 长按判定 |
 * | `PRESSED_STATE_DURATION` | 64ms | pre-pressed 抬起后保持按下态的时间 |
 * | touch slop | 8dp | 手指移出视图边缘的容差 |
 *
 * ## ArkTS 差异
 * - `ViewConfiguration.getTapTimeout()` 等 → 本类常量（值同 AOSP，见上表）
 * - `LayoutUtils.dp2pix(context, 8)` → `LayoutUtils.dp2pix(8)`（鸿蒙版本不带 Context）
 * - 上游 `SimpleHandler.post()` 返回 boolean（post 失败则立即执行），
 *   本项目 `SimpleHandler.post()` 返回 void（内部已兜底），因此去掉 `if (!post(...))` 分支，
 *   并在注释里标明
 */
export class TouchHelper {
  /** AOSP `ViewConfiguration.getTapTimeout()`。 */
  private static readonly TAP_TIMEOUT: number = 100;

  /** AOSP `ViewConfiguration.getLongPressTimeout()`。 */
  private static readonly LONG_PRESS_TIMEOUT: number = 500;

  /** AOSP `ViewConfiguration.getPressedStateDuration()`。 */
  private static readonly PRESSED_STATE_DURATION: number = 64;

  /** 触摸容差（8dp），首次使用时按屏幕密度换算。 */
  private static sTouchSlop: number = -1;

  private readonly mOwner: TouchOwner;

  private mPrePressed: boolean = false;
  private mHasPerformedLongPress: boolean = false;

  private mPendingCheckForLongPress: (() => void) | null = null;
  private mPendingCheckForTap: (() => void) | null = null;
  private mPerformClick: (() => void) | null = null;
  private mUnsetPressedState: (() => void) | null = null;

  /** 一次性初始化（`GLRootView` 在 Surface 就绪后调用；不调也能用，按 8dp=8px 兜底）。 */
  static initialize(): void {
    TouchHelper.sTouchSlop = LayoutUtils.dp2pix(8);
  }

  constructor(owner: TouchOwner) {
    this.mOwner = owner;
  }

  onTouch(event: MotionEvent): boolean {
    const owner = this.mOwner;
    const x = event.getX();
    const y = event.getY();
    const action = event.getAction();

    if (action === MotionEvent.ACTION_DOWN || action === MotionEvent.ACTION_MOVE) {
      owner.setHotspot(x, y);
    }

    if (!owner.isEnabled()) {
      if (action === MotionEvent.ACTION_UP && owner.isPressed()) {
        owner.setPressed(false);
      }
      // 不可用但可点击的视图仍然消费触摸事件，只是不响应
      return owner.isClickable() || owner.isLongClickable();
    }

    if (owner.isClickable() || owner.isLongClickable()) {
      switch (action) {
        case MotionEvent.ACTION_UP:
          if (owner.isPressed() || this.mPrePressed) {
            if (this.mPrePressed) {
              // 抬起发生在"被认定为按下"之前：先补一个按下态，让用户看到反馈
              this.setPressedAndHotspot(true, x, y);
            }

            if (!this.mHasPerformedLongPress) {
              this.removeLongPressCallback();
              // 用 post 延后点击，让按下态的视觉更新先发生（上游注释原意）
              if (this.mPerformClick === null) {
                this.mPerformClick = () => {
                  owner.performClick();
                };
              }
              SimpleHandler.getInstance().post(this.mPerformClick);
            }

            if (this.mUnsetPressedState === null) {
              this.mUnsetPressedState = () => {
                owner.setPressed(false);
              };
            }

            if (this.mPrePressed) {
              SimpleHandler.getInstance().postDelayed(this.mUnsetPressedState,
                TouchHelper.PRESSED_STATE_DURATION);
            } else {
              SimpleHandler.getInstance().post(this.mUnsetPressedState);
            }

            this.removeTapCallback();
          }
          break;

        case MotionEvent.ACTION_DOWN:
          this.mHasPerformedLongPress = false;
          this.mPrePressed = true;
          if (this.mPendingCheckForTap === null) {
            this.mPendingCheckForTap = () => {
              this.mPrePressed = false;
              this.setPressedAndHotspot(true, this.mTapX, this.mTapY);
              this.checkForLongClick(TouchHelper.TAP_TIMEOUT);
            };
          }
          this.mTapX = event.getX();
          this.mTapY = event.getY();
          SimpleHandler.getInstance().postDelayed(this.mPendingCheckForTap, TouchHelper.TAP_TIMEOUT);
          break;

        case MotionEvent.ACTION_CANCEL:
          owner.setPressed(false);
          this.removeTapCallback();
          this.removeLongPressCallback();
          break;

        case MotionEvent.ACTION_MOVE:
          owner.setHotspot(x, y);
          // 手指移出视图（含容差）就取消按下态与后续长按
          if (!this.pointInView(x, y, TouchHelper.touchSlop())) {
            this.removeTapCallback();
            if (owner.isPressed()) {
              this.removeLongPressCallback();
              owner.setPressed(false);
            }
          }
          break;

        default:
          break;
      }

      return true;
    }

    return false;
  }

  /**
   * `CheckForTap` 需要保存按下坐标。上游用内部类字段 `CheckForTap.x/.y`；
   * ArkTS 禁止无类型对象字面量（arkts-no-untyped-obj-literals），故提到外层两个 number 字段。
   */
  private mTapX: number = 0;
  private mTapY: number = 0;

  private static touchSlop(): number {
    if (TouchHelper.sTouchSlop < 0) {
      TouchHelper.sTouchSlop = LayoutUtils.dp2pix(8);
    }
    return TouchHelper.sTouchSlop;
  }

  private setPressedAndHotspot(pressed: boolean, x: number, y: number): void {
    this.mOwner.setPressed(pressed);
    if (pressed) {
      this.mOwner.setHotspot(x, y);
    }
  }

  /**
   * 局部坐标 (localX, localY) 是否在视图范围内（边界外扩 slop）。
   * 处理 MOVE 事件时用它判断手指是否还在视图上。
   */
  pointInView(localX: number, localY: number, slop: number): boolean {
    return localX >= -slop && localY >= -slop
      && localX < this.mOwner.getWidth() + slop
      && localY < this.mOwner.getHeight() + slop;
  }

  private removeLongPressCallback(): void {
    const cb = this.mPendingCheckForLongPress;
    if (cb !== null) {
      SimpleHandler.getInstance().removeCallbacks(cb);
    }
  }

  private removeTapCallback(): void {
    const cb = this.mPendingCheckForTap;
    if (cb !== null) {
      this.mPrePressed = false;
      SimpleHandler.getInstance().removeCallbacks(cb);
    }
  }

  private checkForLongClick(delayOffset: number): void {
    if (this.mOwner.isLongClickable()) {
      this.mHasPerformedLongPress = false;
      if (this.mPendingCheckForLongPress === null) {
        this.mPendingCheckForLongPress = () => {
          if (this.mOwner.isPressed()) {
            if (this.mOwner.performLongClick()) {
              this.mHasPerformedLongPress = true;
            }
          }
        };
      }
      SimpleHandler.getInstance().postDelayed(this.mPendingCheckForLongPress,
        TouchHelper.LONG_PRESS_TIMEOUT - delayOffset);
    }
  }
}
