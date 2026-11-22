/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0489   上游: com/hippo/util/GifHandler.java（24 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/GifHandler.ets
 *
 * 【算法等价 · 容器不同】（与 FastBlur 同口径）
 *   上游是 **JNI 包装**：`System.loadLibrary("ehviewer")` + `native long loadPath(String)`，
 *   返回一个 native gif 对象地址；`getWidth/getHeight/updateFrame(long, Bitmap)` 都带着它。
 *   鸿蒙没有 NDK gif 解码器，等价能力是 `@ohos.multimedia.image`：
 *     `image.createImageSource(fd)` → `createPixelMap({index})` 逐帧解码。
 *
 *   因此本文件移植的是**生命周期契约**而不是解码实现：
 *     · `loadPath(path)` → 打开解码器，失败返回 null（上游 native 失败返回 0）
 *     · `getWidth()/getHeight()` → 首帧尺寸
 *     · `updateFrame(target)` → 解码到指定帧并把像素写入 target（**语义保持"下一帧"**）
 *   具体解码由注入的 `GifDecoder` 完成（ui-scene 用 image API 实现），
 *   这样 core-runtime 不依赖 ImageSource 的句柄语义，也能单测"帧推进/边界/释放"。
 *
 * 平台差异：
 *  1. `long gifAddr`（native 指针）→ `Object | null` 解码器句柄（ArkTS 无裸指针）。
 *  2. `Bitmap` 参数 → `PixelMapLike`（只声明"接收像素"的能力）。
 *  3. 上游**没有 release()** —— JNI 对象靠 GC finalize。ArkTS 侧对象不会自动释放 native 资源，
 *     故补 `release()`（**这是 B 类修复**：用户不可感知的资源泄漏，按陷阱 63 三分法应"修"）。
 */

/** 上游 `Bitmap` 在本文件里的用途：接收一帧像素 */
export interface PixelMapLike {
  /** 写入 RGBA8888 像素；由 ui-scene 的 PixelMap 适配 */
  writePixels(rgba: Uint8ClampedArray, width: number, height: number): void;
}

/** 解码器契约：ui-scene 用 @ohos.multimedia.image 实现 */
export interface GifDecoder {
  /** 总帧数（上游无此方法，但 updateFrame 返回的 int 就是"本次解码是否成功/下一帧索引"的语义） */
  getFrameCount(): number;

  getWidth(): number;

  getHeight(): number;

  /** 解码第 index 帧为 RGBA8888 */
  decodeFrame(index: number): Uint8ClampedArray;

  release(): void;
}

export class GifHandler {

  private decoder: GifDecoder | null = null;
  private frameIndex: number = 0;

  /**
   * 对应上游 `new GifHandler(path)` + `loadPath(path)`。
   * @param decoder `loadDecoder(path)` 返回 null 表示打开失败（上游 native 返回 0 同义）
   */
  constructor(decoder: GifDecoder | null) {
    this.decoder = decoder;
  }

  /** 上游 `getWidth()`；打开失败 → 0（上游 native 返回 0） */
  getWidth(): number {
    return (this.decoder !== null) ? this.decoder.getWidth() : 0;
  }

  /** 上游 `getHeight()`；打开失败 → 0 */
  getHeight(): number {
    return (this.decoder !== null) ? this.decoder.getHeight() : 0;
  }

  /**
   * 对应上游 `updateFrame(bitmap)`：解码**下一帧**到 bitmap，返回该帧索引。
   * 上游返回的 int 是 native 层的"是否还有下一帧"等状态；这里返回**实际写入的帧索引**，
   * 到底后**回绕到 0**（GIF 循环播放语义，上游 native 亦为循环）。
   * @returns 写入的帧索引；解码器不可用 → -1
   */
  updateFrame(target: PixelMapLike): number {
    if (this.decoder === null) {
      return -1;
    }
    const total: number = this.decoder.getFrameCount();
    if (total <= 0) {
      return -1;
    }
    const index: number = this.frameIndex % total;
    const rgba: Uint8ClampedArray = this.decoder.decodeFrame(index);
    target.writePixels(rgba, this.decoder.getWidth(), this.decoder.getHeight());
    this.frameIndex = (index + 1) % total;
    return index;
  }

  /** 释放解码器（**上游没有此方法，见文件头差异 3**） */
  release(): void {
    if (this.decoder !== null) {
      this.decoder.release();
      this.decoder = null;
    }
    this.frameIndex = 0;
  }
}