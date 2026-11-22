/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0482   上游: com/hippo/util/BitmapUtils.java（113 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/BitmapUtils.ets
 *
 * **本文件移植的核心是 `decodeStream` 里的采样率计算**（上游最有价值的一段）：
 *   分别按 宽 / 高 / 总像素 / 可用内存 算出 scaleW / scaleH / scaleP / scaleM，
 *   取四者（与 1）的**最大值**，再 `nextPowerOf2(...)` 得到 `inSampleSize`。
 *   任何一步算出"内存不够"（`availableMemory() - 5MB < 0`）→ `sampleSize[0] = -1` 并返回 null。
 * 这段算法与平台无关，可完全单测 —— 也最容易移植走样（少算一路 scale 就会 OOM 或糊成马赛克）。
 *
 * 平台差异：
 *  1. `BitmapFactory.decodeStream` → 注入 `decodeBounds` / `decode`（ui-widget 用
 *     `@ohos.multimedia.image` 的 `ImageSource.getImageInfo()` + `createPixelMap({desiredSize})`）。
 *     **注意**：ArkTS 的 `image` 用 `desiredSize` 而不是 `inSampleSize`，故下游要按
 *     `Math.floor(w / sample)` 换算 —— 本文件保留 `sampleSize` 这个上游契约量。
 *  2. `Runtime.getRuntime()` + `ActivityManager.getMemoryClass()` 的可用内存 →
 *     注入 `availableMemory()`（鸿蒙侧建议用 `@ohos.hidebug` 或 `process.MemoryUsage`）。
 *  3. `InputStreamPipe` → 注入 `InputStreamPipeLike {obtain/open/close/release}`（已有 UniFile 侧实现）。
 *  4. `OutOfMemoryError` → ArkTS 无 OOM 类型，用普通 catch；语义保持"解码失败 → null + sampleSize=-1"。
 *  5. `sampleSize[0]` 的"出参数组" → 保留为 `SampleSizeHolder { value }`（ArkTS 无 int[] 出参习惯）。
 */

import { MathUtils } from '../lib/yorozuya/MathUtils';

/** 上游 `int[] sampleSize` 的出参（保留可变语义） */
export class SampleSizeHolder {
  value: number;

  constructor(value: number = 0) {
    this.value = value;
  }
}

/** 上游 `InputStreamPipe` 的最小契约 */
export interface InputStreamPipeLike {
  obtain(): void;

  open(): Object;

  close(): void;

  release(): void;
}

/** 上游 `BitmapFactory.Options` 的 bounds 结果 */
export interface BitmapBounds {
  outWidth: number;
  outHeight: number;
}

export class BitmapUtils {

  /**
   * 对应上游 `decodeStream(isp, maxWidth, maxHeight, pixels, checkMemory, justCalc, sampleSize)`。
   *
   * @param decodeBounds  只解码边界（`inJustDecodeBounds = true`）
   * @param decode        按 sampleSize 真正解码
   * @param availableMemory 当前可用字节数（`checkMemory` 时用）
   * @returns 解码结果；**null** 表示失败或 `justCalc`；`sampleSize.value = -1` 表示"内存/尺寸不足"
   */
  static async decodeStream(isp: InputStreamPipeLike, maxWidth: number, maxHeight: number,
    pixels: number, checkMemory: boolean, justCalc: boolean, sampleSize: SampleSizeHolder | null,
    decodeBounds: (stream: Object) => BitmapBounds | null,
    decode: (stream: Object, sampleSize: number) => Promise<Object | null>,
    availableMemory: () => number): Promise<Object | null> {
    try {
      isp.obtain();

      const bounds: BitmapBounds | null = decodeBounds(isp.open());
      isp.close();

      if (bounds === null || bounds.outWidth <= 0 || bounds.outHeight <= 0) {
        BitmapUtils.setSampleSize(sampleSize, -1);
        return null;
      }

      const width: number = bounds.outWidth;
      const height: number = bounds.outHeight;

      let scaleW: number = 1;
      let scaleH: number = 1;
      let scaleP: number = 1;
      let scaleM: number = 1;
      if (maxWidth > 0 && width > maxWidth) {
        scaleW = MathUtils.ceilDivide(width, maxWidth);
      }
      if (maxHeight > 0 && height > maxHeight) {
        scaleH = MathUtils.ceilDivide(height, maxHeight);
      }
      if (pixels > 0 && width * height > pixels) {
        scaleP = Math.ceil(Math.sqrt(width * height / pixels));
      }
      if (checkMemory) {
        const m: number = availableMemory() - 5 * 1024 * 1024; // Leave 5m
        if (m < 0) {
          BitmapUtils.setSampleSize(sampleSize, -1);
          return null;
        }
        if (width * height * 3 > m) {
          scaleM = Math.ceil(Math.sqrt(width * height * 3 / m));
        }
      }

      const inSampleSize: number = MathUtils.nextPowerOf2(
        MathUtils.maxOf([scaleW, scaleH, scaleP, scaleM, 1]));
      BitmapUtils.setSampleSize(sampleSize, inSampleSize);

      if (justCalc) {
        return null;
      }
      try {
        return await decode(isp.open(), inSampleSize);
      } catch (e) {
        BitmapUtils.setSampleSize(sampleSize, -1);
        return null;
      }
    } catch (e) {
      BitmapUtils.setSampleSize(sampleSize, -1);
      return null;
    } finally {
      isp.close();
      isp.release();
    }
  }

  /** 对应上游 `decodeStream(isp, maxWidth, maxHeight)` 便捷重载 */
  static async decodeStreamSimple(isp: InputStreamPipeLike, maxWidth: number, maxHeight: number,
    decodeBounds: (stream: Object) => BitmapBounds | null,
    decode: (stream: Object, sampleSize: number) => Promise<Object | null>,
    availableMemory: () => number): Promise<Object | null> {
    return BitmapUtils.decodeStream(isp, maxWidth, maxHeight, -1, false, false, null,
      decodeBounds, decode, availableMemory);
  }

  private static setSampleSize(holder: SampleSizeHolder | null, value: number): void {
    if (holder !== null) {
      holder.value = value;
    }
  }
}