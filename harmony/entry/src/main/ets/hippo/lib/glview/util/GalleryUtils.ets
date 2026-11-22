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

import { Color } from './Color';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'GalleryUtils';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.util.GalleryUtils` 的 ArkTS 等价实现。
 *
 * 两类职责：
 * 1. **颜色 ↔ 浮点数组**：`GLEdgeView`、`Animation` 系列逐帧插值用，纯数学，逐运算符照搬。
 * 2. **渲染线程检测**：上游注释自己写了"only works most of the time, it's for debugging only"。
 *    鸿蒙侧拿不到线程 ID（`@ohos.deviceInfo`/`@ohos.worker` 都不暴露当前线程标识），
 *    因此实现退化为"渲染线程是否已建立"的哨兵：一旦 `setRenderThread()` 被调用过，
 *    同一 VM 内的后续调用都判为渲染线程。
 *
 *    这个退化对行为的影响：只有当代码在 TaskPool worker 里误调渲染 API 时，
 *    断言不会触发（Android 会触发）。该类断言仅用于开发期自检，
 *    不影响渲染结果 —— 登记为平台差异，不阻塞 1:1。
 */
export class GalleryUtils {
  /** ARGB int → [a, r, g, b] 归一化浮点数组（顺序是 ARGB，不是 RGBA）。 */
  static intColorToFloatARGBArray(from: number): number[] {
    return [
      Color.alpha(from) / 255.0,
      Color.red(from) / 255.0,
      Color.green(from) / 255.0,
      Color.blue(from) / 255.0
    ];
  }

  /** [a, r, g, b] → ARGB int；截断取整与上游 `(int)` 强转一致（向零取整）。 */
  static floatARGBArrayTointColor(from: number[]): number {
    return Color.argb(
      Math.trunc(from[0] * 255),
      Math.trunc(from[1] * 255),
      Math.trunc(from[2] * 255),
      Math.trunc(from[3] * 255)
    );
  }

  /** 渲染线程是否已建立（哨兵）。 */
  private static sRenderThreadAlive: boolean = false;

  /** 在渲染线程入口调用一次（`GLRootView.onSurfaceCreated`）。 */
  static setRenderThread(): void {
    GalleryUtils.sRenderThreadAlive = true;
  }

  /**
   * 当前是否处于渲染线程。
   * 见类注释：鸿蒙无线程 ID API，退化为哨兵判断。
   */
  static isRenderThread(): boolean {
    return GalleryUtils.sRenderThreadAlive;
  }

  /** 上游在此抛 AssertError；ArkTS 只有 Error（DEVIATIONS §5 第 8 条）。 */
  static assertInRenderThread(): void {
    if (!GalleryUtils.isRenderThread()) {
      hilog.error(DOMAIN, TAG, 'assertInRenderThread failed: render thread not established');
      throw new Error('Should not do this in render thread');
    }
  }

  /** 重置哨兵，用于 surface 销毁后的重入（鸿蒙 XComponent 会重建 Surface）。 */
  static resetRenderThread(): void {
    GalleryUtils.sRenderThreadAlive = false;
  }
}
