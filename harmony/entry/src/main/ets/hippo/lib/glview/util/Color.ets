/*
 * Copyright (C) 2008 The Android Open Source Project
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
 * `android.graphics.Color` 的 ArkTS 等价实现。
 *
 * 颜色在整条渲染链路上都是 **ARGB int32**（不是对象），所以这里全部是静态函数 +
 * 静态常量，与上游调用点逐字对应：`Color.alpha(c)`、`Color.argb(a,r,g,b)`、
 * `Color.WHITE`。
 *
 * 关键语义：ArkTS 的 number 是 IEEE754 double，`(color >>> 24) & 0xFF` 这类位运算
 * 会先 ToInt32 再算，结果与 Java int 完全一致（含负数颜色值）。因此这里不做任何
 * 额外的掩码归一化，保持与 AOSP 逐位一致。
 */
export class Color {
  static readonly BLACK: number = 0xFF000000;
  static readonly DKGRAY: number = 0xFF444444;
  static readonly GRAY: number = 0xFF888888;
  static readonly LTGRAY: number = 0xFFCCCCCC;
  static readonly WHITE: number = 0xFFFFFFFF;
  static readonly RED: number = 0xFFFF0000;
  static readonly GREEN: number = 0xFF00FF00;
  static readonly BLUE: number = 0xFF0000FF;
  static readonly YELLOW: number = 0xFFFFFF00;
  static readonly CYAN: number = 0xFF00FFFF;
  static readonly MAGENTA: number = 0xFFFF00FF;
  static readonly TRANSPARENT: number = 0;

  /** alpha 通道（0..255）。 */
  static alpha(color: number): number {
    return (color >>> 24) & 0xFF;
  }

  /** red 通道。 */
  static red(color: number): number {
    return (color >> 16) & 0xFF;
  }

  /** green 通道。 */
  static green(color: number): number {
    return (color >> 8) & 0xFF;
  }

  /** blue 通道。 */
  static blue(color: number): number {
    return color & 0xFF;
  }

  /** 由 RGB 三通道合成不透明颜色。 */
  static rgb(red: number, green: number, blue: number): number {
    return (0xFF << 24) | ((red & 0xFF) << 16) | ((green & 0xFF) << 8) | (blue & 0xFF);
  }

  /**
   * 由 ARGB 四通道合成颜色。
   * 用 `| 0` 保证结果落在 int32（ArkTS 位运算本身已是 int32，此处显式化意图）。
   */
  static argb(alpha: number, red: number, green: number, blue: number): number {
    return (((alpha & 0xFF) << 24) | ((red & 0xFF) << 16)
      | ((green & 0xFF) << 8) | (blue & 0xFF)) | 0;
  }

  /** 替换 alpha，保留 RGB。 */
  static setAlpha(color: number, alpha: number): number {
    return ((color & 0x00FFFFFF) | ((alpha & 0xFF) << 24)) | 0;
  }

  /** 线性插值：`start * (1 - fraction) + end * fraction`，逐通道四舍五入（AOSP 语义）。 */
  static lerp(startColor: number, endColor: number, fraction: number): number {
    const inverse = 1.0 - fraction;
    const a = Color.alpha(startColor) * inverse + Color.alpha(endColor) * fraction;
    const r = Color.red(startColor) * inverse + Color.red(endColor) * fraction;
    const g = Color.green(startColor) * inverse + Color.green(endColor) * fraction;
    const b = Color.blue(startColor) * inverse + Color.blue(endColor) * fraction;
    return Color.argb(Math.round(a), Math.round(r), Math.round(g), Math.round(b));
  }

  /** 解析 `#RRGGBB` / `#AARRGGBB`，失败返回 0（等价 AOSP 的抛异常场景由调用方兜底）。 */
  static parseColor(colorString: string): number {
    if (colorString.length === 0 || colorString.charAt(0) !== '#') {
      return 0;
    }
    const body = colorString.substring(1);
    if (body.length === 6) {
      return (0xFF000000 | parseInt(body, 16)) | 0;
    }
    if (body.length === 8) {
      return parseInt(body, 16) | 0;
    }
    return 0;
  }

  /** 反解为 `#AARRGGBB`，用于日志与单测断言。 */
  static toString(color: number): string {
    return `#${(color >>> 0).toString(16).padStart(8, '0')}`;
  }
}
