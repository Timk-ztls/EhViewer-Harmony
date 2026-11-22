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

/**
 * `com.hippo.lib.glview.view.Gravity` 的 ArkTS 等价实现。
 *
 * 位标志 + 两个"位置模式"枚举。上游用 `@IntDef` 注解限定取值域，ArkTS 无注解，
 * 改为注释 + 常量（取值与上游逐位一致）。
 *
 * `POSITION_BEGIN/CENTER/FINISH` 供 `GLView.getDefaultBegin()` 把一个子视图
 * 在父容器里按左/中/右（或上/中/下）摆放。
 */
export class Gravity {
  // ---- 方向位 ----
  static readonly LEFT: number = 0x0001;
  static readonly TOP: number = 0x0002;
  static readonly RIGHT: number = 0x0004;
  static readonly BOTTOM: number = 0x0008;

  static readonly CENTER_HORIZONTAL: number = Gravity.LEFT | Gravity.RIGHT;
  static readonly CENTER_VERTICAL: number = Gravity.TOP | Gravity.BOTTOM;
  static readonly CENTER: number = Gravity.CENTER_VERTICAL | Gravity.CENTER_HORIZONTAL;

  static readonly HORIZONTAL_MASK: number = Gravity.CENTER_HORIZONTAL;
  static readonly VERTICAL_MASK: number = Gravity.CENTER_VERTICAL;

  static readonly NO_GRAVITY: number = 0;

  // ---- 位置模式 ----
  static readonly POSITION_BEGIN: number = 0;
  static readonly POSITION_CENTER: number = 1;
  static readonly POSITION_FINISH: number = 2;

  // ---- 方向 ----
  static readonly HORIZONTAL: number = 0;
  static readonly VERTICAL: number = 1;

  static centerHorizontal(gravity: number): boolean {
    return (gravity & Gravity.HORIZONTAL_MASK) === Gravity.CENTER_HORIZONTAL;
  }

  static right(gravity: number): boolean {
    return (gravity & Gravity.HORIZONTAL_MASK) === Gravity.RIGHT;
  }

  static left(gravity: number): boolean {
    return (gravity & Gravity.HORIZONTAL_MASK) === Gravity.LEFT;
  }

  static centerVertical(gravity: number): boolean {
    return (gravity & Gravity.VERTICAL_MASK) === Gravity.CENTER_VERTICAL;
  }

  static top(gravity: number): boolean {
    return (gravity & Gravity.VERTICAL_MASK) === Gravity.TOP;
  }

  static bottom(gravity: number): boolean {
    return (gravity & Gravity.VERTICAL_MASK) === Gravity.BOTTOM;
  }

  /** 把某方向上的 gravity 归一成 BEGIN / CENTER / FINISH 三态。 */
  static getPosition(gravity: number, direction: number): number {
    if (direction === Gravity.HORIZONTAL) {
      if (Gravity.right(gravity)) {
        return Gravity.POSITION_FINISH;
      } else if (Gravity.centerHorizontal(gravity)) {
        return Gravity.POSITION_CENTER;
      } else {
        return Gravity.POSITION_BEGIN;
      }
    } else {
      if (Gravity.bottom(gravity)) {
        return Gravity.POSITION_FINISH;
      } else if (Gravity.centerVertical(gravity)) {
        return Gravity.POSITION_CENTER;
      } else {
        return Gravity.POSITION_BEGIN;
      }
    }
  }
}
