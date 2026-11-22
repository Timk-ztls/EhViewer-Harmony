/**
 * native_image：EhViewer 图片解码/纹理像素 NAPI 层类型声明。
 *
 * 对应上游（Android）两个 JNI 产物的合并：
 *   libimage.so    → com.hippo.lib.image.Image / Image1（decode/render/recycle/...）
 *   libehviewer.so → GifHandler / gifutils.rewriteGifSource / Native.getFd
 *
 * 鸿蒙侧统一为单产物 libnative-lib.so，模块名 native_image。
 * 用法：import nativeImage from 'libnative-lib.so';
 */

/** 解码格式常量，取值与上游 com.hippo.lib.image.Image 的 FORMAT_* 完全一致 */
export declare const FORMAT_UNKNOWN: number; // -1
export declare const FORMAT_PLAIN: number;   //  0
export declare const FORMAT_JPEG: number;    //  1
export declare const FORMAT_PNG: number;     //  2
export declare const FORMAT_GIF: number;     //  3
export declare const FORMAT_WEBP: number;    //  4

/**
 * 解码结果句柄（上游 com.hippo.lib.image.Image1 的等价物）。
 * 生命周期由 native finalizer 管理；主动释放调用 recycle()。
 */
export declare class NativeImage {
  /** 解码器格式（FORMAT_*） */
  readonly format: number;
  /** 当前帧/图像宽度（px） */
  readonly width: number;
  /** 当前帧/图像高度（px） */
  readonly height: number;
  /** 像素字节数（RGBA_8888 = width*height*4；未 complete 时为 0） */
  readonly byteCount: number;
  /** 当前帧播放延迟（ms，仅 GIF/WebP 动图有意义） */
  readonly delay: number;
  /** 帧数（静态图为 1） */
  readonly frameCount: number;

  /**
   * 拷出当前帧 RGBA 像素（新建缓冲，调用方持有）。
   * 需要零拷贝时改用 render() 直接写自己的 ArrayBuffer。
   */
  getPixels(): ArrayBuffer;

  /** 增量解码：返回是否已完成（对应上游 nativeComplete） */
  complete(): boolean;

  /** 是否已完成解码（对应上游 nativeIsCompleted） */
  isCompleted(): boolean;

  /**
   * 把图像区域渲染进目标 RGBA 缓冲（对应上游 nativeRender）。
   * @param dst 目标缓冲，长度须 >= dstW*dstH*4
   * @param dstW/dstH 目标缓冲尺寸
   * @param srcX/srcY 源区域左上角
   * @param dstX/dstY 目标区域左上角
   * @param width/height 拷贝区域尺寸
   * @param fillBlank 区域外是否填充 defaultColor
   * @param defaultColor 填充色（0xAARRGGBB）
   */
  render(dst: ArrayBuffer | Uint8Array, dstW: number, dstH: number,
         srcX: number, srcY: number, dstX: number, dstY: number,
         width: number, height: number, fillBlank: boolean, defaultColor: number): void;

  /** 推进到下一帧（动图） */
  advance(): void;

  /** 图像是否完全不透明（对应上游 nativeIsOpaque） */
  isOpaque(): boolean;

  /** 是否近似灰度图，error 为容差（对应上游 nativeIsGray） */
  isGray(error: number): boolean;

  /** CLAHE 对比度增强（对应上游 nativeClahe） */
  clahe(toGray: boolean): void;

  /** 立即释放 native 内存；之后除 width/height/format 外的调用返回 0/false */
  recycle(): void;
}

/**
 * GIF 逐帧解码器（上游 com.hippo.util.GifHandler 的等价物）。
 * 与上游一致：updateFrame() 绘制当前帧后自增帧号（到末尾回绕），返回新帧延迟。
 */
export declare class GifDecoder {
  readonly width: number;
  readonly height: number;
  readonly frameCount: number;
  readonly currentFrame: number;
  /** 最近一次 updateFrame()/seek() 得到的帧延迟（ms） */
  readonly delay: number;
  /** 内部 RGBA_8888 帧缓冲（零拷贝视图，随 updateFrame 原地更新） */
  readonly pixels: ArrayBuffer;

  /** 从内存缓冲加载 GIF（对应上游 loadPath 的等价入口） */
  load(buffer: ArrayBuffer | Uint8Array): boolean;
  /** 从文件描述符加载（内部 dup，解码器负责关闭副本） */
  loadFd(fd: number): boolean;
  /** 绘制当前帧并前进到下一帧，返回下一帧延迟（ms） */
  updateFrame(): number;
  /** 定位到指定帧并立即绘制，返回该帧延迟（ms） */
  seek(index: number): number;
  recycle(): void;
}

export interface NativeImageModule {
  /** 自动识别格式解码（对应上游 Image1.nativeDecode） */
  decode(buffer: ArrayBuffer | Uint8Array, partially?: boolean): NativeImage;
  /** 指定格式解码，格式不符抛异常（对应上游 Image.nativeDecode3 的格式约束） */
  decodeAs(buffer: ArrayBuffer | Uint8Array, format: number, partially?: boolean): NativeImage;
  /** 用已有 RGBA 像素构造图像（对应上游 Image1.nativeCreate） */
  createPlain(width: number, height: number, pixels: ArrayBuffer | Uint8Array): NativeImage;
  /** 当前构建支持的格式列表（对应上游 nativeGetSupportedFormats） */
  getSupportedFormats(): number[];
  /** 解码器描述（对应上游 nativeGetDecoderDescription） */
  getDecoderDescription(format: number): string;

  /** 修正 GIF 首帧过短的帧延迟（原地改写，对应上游 rewriteGifSource） */
  rewriteGifSource(buffer: ArrayBuffer | Uint8Array): void;
  /** 同上，作用于文件（mmap 写回，对应上游 rewriteGifSource2） */
  rewriteGifSourceFd(fd: number): void;

  /**
   * 解压 7z（D-004 方案 A）。当前产物未编译 LZMA SDK，
   * 调用会抛 code=7001（未编译）/7002（参数）/7003（解压失败）/7004（口令）。
   * @returns 解压出的文件数
   */
  extract7z(archive: ArrayBuffer | Uint8Array, outDir: string, password?: string): number;

  open7z(length: number, readAt: (pos: number, buf: ArrayBuffer, len: number) => number): number;
  close7z(handle: number): void;
  get7zEntryCount(handle: number): number;
  get7zEntryName(handle: number, index: number): string;
  is7zEntryDir(handle: number, index: number): boolean;
  is7zEncrypted(handle: number): boolean;
  is7zEntryEncrypted(handle: number, index: number): boolean;
  extract7zEntry(handle: number, index: number): ArrayBuffer;

  openZip(length: number, readAt: (pos: number, buf: ArrayBuffer, len: number) => number): number;
  closeZip(handle: number): void;
  getZipEntryCount(handle: number): number;
  getZipEntryName(handle: number, index: number): string;
  isZipEntryDir(handle: number, index: number): boolean;
  isZipEncrypted(handle: number): boolean;
  isZipEntryEncrypted(handle: number, index: number): boolean;
  extractZipEntry(handle: number, index: number): ArrayBuffer;

  NativeImage: typeof NativeImage;
  GifDecoder: typeof GifDecoder;
}

declare const nativeImage: NativeImageModule;
export default nativeImage;

/**
 * C-1｜GL NAPI 边界（gl-render ↔ native-image）
 * 全部函数在 render 线程调用，统一返回 GLErr（0..6），禁止裸 bool。
 * EGL surface 由 native 侧通过 XComponent 回调持有，ArkTS 只需声明
 * XComponent({ type: 'surface', libraryname: 'native-lib' })。
 */
export declare const enum GLErr {
  OK = 0,
  NOT_READY = 1,
  BAD_ID = 2,
  OUT_OF_RESOURCES = 3,
  PROGRAM_FAILED = 4,
  GL_ERROR = 5,
  BAD_ARGUMENT = 6
}

export declare function nativeInit(): number;
export declare function nativeSetSurface(width: number, height: number): number;
export declare function nativeDestroySurface(): number;
/** 只执行不上屏（一帧内可多次调用） */
export declare function nativeReplay(commands: Float32Array): number;
/** 单独 swap，一次帧末尾调一次 */
export declare function nativePresent(): number;
export declare function nativeGenTexture(): number;
export declare function nativeDeleteTexture(id: number): number;
export declare function nativeTexImage2D(id: number, width: number, height: number,
                                        format: number, type: number, pixelMap: object): number;
export declare function nativeTexSubImage2D(id: number, xOffset: number, yOffset: number,
                                            width: number, height: number, format: number,
                                            type: number, pixelMap: object): number;
/**
 * 用单色填充一块纹理区域（UploadedTexture 的非 2 次幂边框填充）。
 * @param argb 颜色，语义 **0xAARRGGBB**（与上游 `Color.argb` 一致）：
 *             0x11223344 → a=0x11, r=0x22, g=0x33, b=0x44；0x00000000 = 全透明。
 *             落盘字节序按 GL_RGBA/GL_UNSIGNED_BYTE 为 r,g,b,a，不做预乘。
 */
export declare function nativeTexSubImage2DFill(id: number, xOffset: number, yOffset: number,
                                               width: number, height: number, format: number,
                                               type: number, argb: number): number;
/**
 * 区域 blit（C-1 补充，gl-render 的 `ImageTexture` 分块上传依赖）：
 * 把 pixelMap 的 `[srcX,srcY,srcW,srcH)` 区域贴到纹理 `id` 的 `(dstX,dstY)`。
 *
 * - `dstX/dstY` **允许为负**：负的部分裁掉，src 同步平移（1:1 不缩放）
 * - `srcX/srcY/srcW/srcH` 允许超出 pixelMap：超出部分跳过
 * - `init=true`：先 `glTexImage2D(GL_RGBA, texW, texH, null)` 分配存储，再 blit
 * - 完全落在纹理外 → 返回 `GLErr.OK`（无写入，不是错误）
 */
export declare function nativeTexImageRegion(id: number, init: boolean, pixelMap: object,
                                            srcX: number, srcY: number, srcW: number, srcH: number,
                                            dstX: number, dstY: number,
                                            texW: number, texH: number): number;

export declare function nativeGenBuffer(target: number): number;
export declare function nativeBufferDataF32(id: number, data: Float32Array): number;
export declare function nativeBufferDataU8(id: number, data: Uint8Array): number;
export declare function nativeDeleteBuffer(id: number): number;
export declare function nativeGenFramebuffer(): number;
export declare function nativeBindFramebuffer(id: number): number;
export declare function nativeAttachTexture(target: number, attachment: number,
                                            texTarget: number, textureId: number): number;
export declare function nativeDeleteFramebuffer(id: number): number;
export declare function nativeUnbindFramebuffer(): number;
export declare function nativeGlGetError(): number;
export declare function nativeGetString(what: number): string;



