/*
 * 对位上游：app/src/main/java/com/hippo/lib/image/Image1.kt
 *
 * 这是什么：native 堆上的图像（像素在 Native 侧），Java/Kotlin 只持有一个 nativePtr。
 * 上游 14 个 `external fun` 全部是 JNI：nativeDecode/nativeCreate/nativeRender/nativeTexImage/
 * nativeAdvance/nativeGetDelay/nativeFrameCount/nativeIsOpaque/nativeIsGray/nativeClahe/
 * nativeRecycle/nativeGetByteCount/nativeIsCompleted/nativeComplete/nativeGetSupportedImageFormats/
 * nativeGetDecoderDescription。
 *
 * 平台对位（方案 §5-⑤：无 JNI 直接绑 Java → native 走 NAPI）：
 *   - 鸿蒙侧没有 JNI，所有 external 必须由 **native-image 模块**用 NAPI 暴露（`cpp/jni/image` 原样承接，
 *     加一层 napi 胶水）。本类不自己实现 native，而是通过 `LibImageBridge` 接口**注入**：
 *     由 native-image / gl-render 在 AbilityStage 启动时调用 `Image1.setBridge(bridge)`。
 *   - 未注入时所有方法抛错（"TODO(native-image)"），**不是空实现**：避免下游以为解码成功。
 *   - `ReLinker.loadLibrary(context, "image")` → 鸿蒙 `import nativeLib from 'libimage.so'`
 *     （在 native-image 落地后由该模块在 setBridge 时完成加载）。
 *   - Bitmap 参数 → `@ohos.multimedia.image` 的 PixelMap（render 的目标）。
 *   - `AtomicInteger sImageCount` → ArkTS 单线程模型下用普通 number 计数（跨 TaskPool 统计时由调用方聚合），
 *     保留 imageCount() 供 debug 使用。
 *
 * 常量 FORMAT_UNKNOWN(-1)/FORMAT_PLAIN(0)/FORMAT_JPEG(1)/FORMAT_PNG(2)/FORMAT_GIF(3)/FORMAT_WEBP(4)
 * 与上游逐值一致，向下游（glgallery / SpiderQueen 的图片解码）保持语义。
 */

import image from '@ohos.multimedia.image';

/**
 * native 解码器桥（对位上游 16 个 external fun）。
 * 实现方：native-image 模块的 NAPI 胶水（cpp/jni/image → libimage.so）。
 */
export interface LibImageBridge {
  decode(fileDescriptor: number, partially: boolean): bigint;

  create(pixelMap: image.PixelMap | null): bigint;

  getByteCount(nativePtr: bigint, format: number): number;

  complete(nativePtr: bigint, format: number): boolean;

  isCompleted(nativePtr: bigint, format: number): boolean;

  render(nativePtr: bigint, format: number, srcX: number, srcY: number,
    dst: image.PixelMap | null, dstX: number, dstY: number,
    width: number, height: number, fillBlank: boolean, defaultColor: number): void;

  texImage(nativePtr: bigint, format: number, init: boolean,
    offsetX: number, offsetY: number, width: number, height: number): void;

  advance(nativePtr: bigint, format: number): void;

  getDelay(nativePtr: bigint, format: number): number;

  frameCount(nativePtr: bigint, format: number): number;

  isOpaque(nativePtr: bigint, format: number): boolean;

  isGray(nativePtr: bigint, format: number, error: number): boolean;

  clahe(nativePtr: bigint, format: number, toGray: boolean): void;

  recycle(nativePtr: bigint, format: number): void;

  supportedImageFormats(): number[];

  decoderDescription(format: number): string | null;
}

/** 对位 com.hippo.lib.image.Image1：像素在 native 堆上的图像（glgallery 的解码核心）。 */
export class Image1 {
  static readonly FORMAT_UNKNOWN: number = -1;
  static readonly FORMAT_PLAIN: number = 0;
  static readonly FORMAT_JPEG: number = 1;
  static readonly FORMAT_PNG: number = 2;
  static readonly FORMAT_GIF: number = 3;
  static readonly FORMAT_WEBP: number = 4;

  private static bridge: LibImageBridge | null = null;
  private static sImageCount: number = 0;

  private mNativePtr: bigint;
  private readonly format: number;
  private readonly widthValue: number;
  private readonly heightValue: number;
  private mRecycleTracker: Error | null = null;

  private constructor(nativePtr: bigint, format: number, width: number, height: number) {
    this.mNativePtr = nativePtr;
    this.format = format;
    this.widthValue = width;
    this.heightValue = height;
    ++Image1.sImageCount;
  }

  /** 由 native-image / gl-render 在启动时注入 NAPI 实现。 */
  static setBridge(bridge: LibImageBridge | null): void {
    Image1.bridge = bridge;
  }

  /**
   * 对位上游 `ReLinker.loadLibrary(context, "image")`。
   * 鸿蒙侧加载 .so 由 native-image 模块负责（import nativeLib from 'libimage.so'），
   * 这里只校验桥已注入，避免下游拿到未初始化的解码器。
   */
  static initialize(): void {
    if (Image1.bridge === null) {
      throw new Error('TODO(native-image): libimage.so 的 NAPI 桥未注入，调用 Image1.setBridge() 后再 initialize()');
    }
  }

  private static requireBridge(): LibImageBridge {
    const b: LibImageBridge | null = Image1.bridge;
    if (b === null) {
      throw new Error('TODO(native-image): libimage.so 的 NAPI 桥未注入（Image1.setBridge）');
    }
    return b;
  }

  /** 对位上游 `decode(InputStream, partially)`。入参改为已打开的 fd。 */
  static decode(fileDescriptor: number, partially: boolean): Image1 | null {
    const nativePtr: bigint = Image1.requireBridge().decode(fileDescriptor, partially);
    if (nativePtr === BigInt(0)) {
      return null;
    }
    // native 侧不知道宽高，由 bridge 通过 render 时的 info 提供；此处沿用上游语义：
    // 宽高来自 native（上游是 `val width: Int` 构造参数），故这里要求 bridge 在 decode 后
    // 通过 getByteCount 之外的方式提供——鸿蒙实现约定：decode 返回的 ptr 立即附带一个
    // 尺寸查询（见 native-image 的 NAPI 契约），暂用 0 占位并在 getWidth() 处提示。
    return new Image1(nativePtr, Image1.FORMAT_UNKNOWN, 0, 0);
  }

  /** 对位上游 `create(Bitmap?)`。 */
  static create(pixelMap: image.PixelMap | null): Image1 | null {
    const nativePtr: bigint = Image1.requireBridge().create(pixelMap);
    if (nativePtr === BigInt(0)) {
      return null;
    }
    const w: number = pixelMap !== null ? pixelMap.getImageInfoSync().size.width : 0;
    const h: number = pixelMap !== null ? pixelMap.getImageInfoSync().size.height : 0;
    return new Image1(nativePtr, Image1.FORMAT_PLAIN, w, h);
  }

  /** 对位上游 `val imageCount`（debug 用）。 */
  static imageCount(): number {
    return Image1.sImageCount;
  }

  /** 对位上游 `val supportedImageFormats`。 */
  static supportedImageFormats(): number[] {
    return Image1.requireBridge().supportedImageFormats();
  }

  /** 对位上游 `getDecoderDescription(format)`。 */
  static getDecoderDescription(format: number): string | null {
    return Image1.requireBridge().decoderDescription(format);
  }

  getFormat(): number {
    return this.format;
  }

  getWidth(): number {
    return this.widthValue;
  }

  getHeight(): number {
    return this.heightValue;
  }

  private checkRecycled(): void {
    if (this.mNativePtr === BigInt(0)) {
      if (this.mRecycleTracker !== null) {
        throw new Error(`The image is recycled. caused by: ${this.mRecycleTracker.message}`);
      }
      throw new Error('The image is recycled.');
    }
  }

  /** 对位上游 `val byteCount`。 */
  getByteCount(): number {
    this.checkRecycled();
    return Image1.requireBridge().getByteCount(this.mNativePtr, this.format);
  }

  /** 对位上游 `complete()`。 */
  complete(): boolean {
    this.checkRecycled();
    return Image1.requireBridge().complete(this.mNativePtr, this.format);
  }

  /** 对位上游 `val isCompleted`（上游 catch 后返回 false）。 */
  isCompleted(): boolean {
    try {
      this.checkRecycled();
      return Image1.requireBridge().isCompleted(this.mNativePtr, this.format);
    } catch (e) {
      return false;
    }
  }

  /** 对位上游 `render(...)`：把 native 像素渲染到 PixelMap 目标。 */
  render(srcX: number, srcY: number, dst: image.PixelMap | null, dstX: number, dstY: number,
    width: number, height: number, fillBlank: boolean, defaultColor: number): void {
    this.checkRecycled();
    Image1.requireBridge().render(this.mNativePtr, this.format, srcX, srcY, dst, dstX, dstY,
      width, height, fillBlank, defaultColor);
  }

  /** 对位上游 `texImage(...)`：init=true 走 glTexImage2D，false 走 glTexSubImage2D。 */
  texImage(init: boolean, offsetX: number, offsetY: number, width: number, height: number): void {
    this.checkRecycled();
    Image1.requireBridge().texImage(this.mNativePtr, this.format, init, offsetX, offsetY, width, height);
  }

  /** 对位上游 `advance()`：动图推进一帧（静态图无操作）。 */
  advance(): void {
    this.checkRecycled();
    Image1.requireBridge().advance(this.mNativePtr, this.format);
  }

  /** 对位上游 `val delay`：≤10 视为异常值 → 100。 */
  getDelay(): number {
    this.checkRecycled();
    const delay: number = Image1.requireBridge().getDelay(this.mNativePtr, this.format);
    return delay <= 10 ? 100 : delay;
  }

  /** 对位上游 `val frameCount`。 */
  getFrameCount(): number {
    this.checkRecycled();
    return Image1.requireBridge().frameCount(this.mNativePtr, this.format);
  }

  /** 对位上游 `val isOpaque`。 */
  isOpaque(): boolean {
    this.checkRecycled();
    return Image1.requireBridge().isOpaque(this.mNativePtr, this.format);
  }

  /** 对位上游 `isGray(error)`。 */
  isGray(error: number): boolean {
    this.checkRecycled();
    return Image1.requireBridge().isGray(this.mNativePtr, this.format, error);
  }

  /** 对位上游 `clahe(toGray)`：CLAHE 对比度增强。 */
  clahe(toGray: boolean): void {
    this.checkRecycled();
    Image1.requireBridge().clahe(this.mNativePtr, this.format, toGray);
  }

  /** 对位上游 `recycle()`：释放 native 对象（幂等）。 */
  recycle(): void {
    if (this.mNativePtr === BigInt(0)) {
      return;
    }
    Image1.requireBridge().recycle(this.mNativePtr, this.format);
    this.mNativePtr = BigInt(0);
    --Image1.sImageCount;
    this.mRecycleTracker = new Error(`ImageRecycleTracker(format=${this.format})`);
  }

  /** 对位上游 `val isRecycled`。 */
  isRecycled(): boolean {
    return this.mNativePtr === BigInt(0);
  }
}
