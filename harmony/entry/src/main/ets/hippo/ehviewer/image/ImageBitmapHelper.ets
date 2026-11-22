/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0163   上游: com/hippo/ehviewer/ImageBitmapHelper.java（85 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/image/ImageBitmapHelper.ets
 *
 * `ValueHelper<Image>` 的实现：解码 + 内存缓存三件套（sizeOf / onAdd / onRemove / useMemoryCache）。
 *
 * ## 可移植的两条纯逻辑（断言钉住）
 * 1. **`sizeOf` = width × height × 4**（上游注释 `value.getByteCount() TODO Update Image`：
 *    字节数尚未实现，用 4 字节/像素估算）
 * 2. **`useMemoryCache`**：
 *    ```
 *    value != null → width * height <= MAX_CACHE_SIZE(512*512)
 *    value == null → true          ← **注意：null 时返回 true**
 *    ```
 *    "面积为 null 的缓存项也放行"看着反直觉，但它对应的是"key 已在缓存里、值还没解出来"的中间态。
 *
 * ## 平台差异
 *  · `Image.decode(FileInputStream, hardware)` → 注入 `decodeImage(bytes, hardware)`；
 *    鸿蒙侧用 `@ohos.multimedia.image` 的 `createImageSource(...).createPixelMapSync()`。
 *  · `InputStreamPipe`（obtain/open/close/release 四步）→ 注入 `ImageStreamPipe` 接口，
 *    本类只负责**四步的调用顺序与 finally**（这正是上游最容易泄漏的地方）。
 *  · `OutOfMemoryError` / `ClassCastException` / `IOException` **三种异常分开处理**且都返回 null，
 *    `OutOfMemoryError` 走 `Analytics.recordException`，另两种只打日志 —— 照搬分类。
 */

import { Analytics } from '../Analytics';
import hilog from '@ohos.hilog';

/** 解码出来的图像（只需宽高；具体类型由注入的解码器决定） */
export interface DecodedImage {
  getWidth(): number;

  getHeight(): number;

  /** 对应上游 `Image.obtain()` */
  obtain(): void;

  /** 对应上游 `Image.release()` */
  release(): void;
}

/** 对应上游 `InputStreamPipe` 的四步协议 */
export interface ImageStreamPipe {
  obtain(): void;

  /** 可能抛 `ClassCastException` / `IOException`（上游分别 catch） */
  open(): Object;

  close(): void;

  release(): void;
}

export class ImageBitmapHelper {

  static readonly TAG: string = 'ImageBitmapHelper';
  /** 上游 `MAX_CACHE_SIZE = 512 * 512`（按**像素面积**算，不是字节） */
  static readonly MAX_CACHE_SIZE: number = 512 * 512;
  /** 上游 `value.getWidth() * value.getHeight() * 4` 里的 4（每像素字节估算） */
  static readonly BYTES_PER_PIXEL: number = 4;

  /**
   * 对应上游 `decode(isPipe)`（hardware=true 的重载）
   */
  static decode(pipe: ImageStreamPipe,
    decodeImage: (opened: Object, hardware: boolean) => DecodedImage | null): DecodedImage | null {
    return ImageBitmapHelper.decodeWithHardware(pipe, true, decodeImage);
  }

  /**
   * 对应上游 `decode(isPipe, hardware)`：
   * **`obtain()` → `open()` → decode → 无论成败 `finally { close(); release(); }`**
   * （四步顺序是上游最易泄漏的地方：`obtain` 在 try 之前，`close+release` 在 finally）
   */
  static decodeWithHardware(pipe: ImageStreamPipe, hardware: boolean,
    decodeImage: (opened: Object, hardware: boolean) => DecodedImage | null): DecodedImage | null {
    try {
      pipe.obtain();
      const opened: Object = pipe.open();
      const image: DecodedImage | null = decodeImage(opened, hardware);
      if (image === null) {
        hilog.warn(0x0001, ImageBitmapHelper.TAG,
          'Image decode failed, result is null. hardware=%{public}s', `${hardware}`);
      }
      return image;
    } catch (e) {
      // 上游三种异常分开处理，但三种都返回 null
      if (e instanceof RangeError) {
        // 对应 OutOfMemoryError（JS 侧内存耗尽表现为 RangeError）
        Analytics.recordException(e as Error);
        return null;
      }
      if (e instanceof TypeError) {
        // 对应 ClassCastException
        Analytics.recordException(e as Error);
        hilog.warn(0x0001, ImageBitmapHelper.TAG,
          'InputStream is not FileInputStream. hardware=%{public}s', `${hardware}`);
        return null;
      }
      hilog.warn(0x0001, ImageBitmapHelper.TAG,
        'Open image stream failed. hardware=%{public}s', `${hardware}`);
      return null;
    } finally {
      pipe.close();
      pipe.release();
    }
  }

  /** 对应上游 `sizeOf(key, value)` = width × height × 4 */
  static sizeOf(value: DecodedImage): number {
    return value.getWidth() * value.getHeight() * ImageBitmapHelper.BYTES_PER_PIXEL;
  }

  /** 对应上游 `onAddToMemoryCache(oldValue)`：`obtain()`（引用计数 +1） */
  static onAddToMemoryCache(oldValue: DecodedImage): void {
    oldValue.obtain();
  }

  /** 对应上游 `onRemoveFromMemoryCache(key, oldValue)`：`release()`（引用计数 -1） */
  static onRemoveFromMemoryCache(oldValue: DecodedImage): void {
    oldValue.release();
  }

  /**
   * 对应上游 `useMemoryCache(key, value)`：
   * value 非 null → **像素面积** ≤ 512×512；value 为 null → **true**。
   */
  static useMemoryCache(value: DecodedImage | null): boolean {
    if (value !== null) {
      return value.getWidth() * value.getHeight() <= ImageBitmapHelper.MAX_CACHE_SIZE;
    }
    return true;
  }
}
