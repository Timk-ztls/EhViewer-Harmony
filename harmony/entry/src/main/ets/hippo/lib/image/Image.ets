/*
 * 对位上游：app/src/main/java/com/hippo/lib/image/Image.kt
 *
 * 平台对位（Bitmap/Drawable → PixelMap）：
 *   - `android.graphics.Bitmap` / `BitmapDrawable` / `AnimatedImageDrawable` → `@ohos.multimedia.image`
 *     的 `PixelMap`（方案 §4「Android Bitmap/Drawable/Canvas → PixelMap」）。
 *   - 解码：上游 `ImageDecoder.decodeDrawable(FileChannel.map(...))` /
 *     `BitmapFactory.decodeStream(stream, null, options)` → 鸿蒙 `image.createImageSource(fd)`
 *     + `createPixelMap(DecodingOptions)`。降采样策略保留上游算式：
 *       simpleSize = available > 10MB ? available / 10MB + 1 : 1
 *       screenSize = max(1, min(srcW / screenW, srcH / screenH))
 *       sampleSize = max(screenSize, simpleSize)
 *   - `fun release()` 与构造参数 `val release: () -> Unit?` 在 ArkTS 不能同名（无属性/方法重载），
 *     构造参数改名为 `releaseCallback`，方法仍叫 `release()`（调用点一致）。
 *   - **动画（GIF/WebP-animated）**：上游靠 AnimatedImageDrawable；PixelMap 是静态帧。
 *     鸿蒙等价物是 `ImageSource.createPixelMapList()`（API 12+）逐帧播放。本 port 暂按静态图处理，
 *     动图解码走 `Image1.ets`（native 像素 + native 逐帧），与上游 EhViewer 实际路径一致
 *     （glgallery 用的就是 Image1）。TODO(动画)：若要在 Image 上支持动图，补 createPixelMapList 帧循环。
 *   - `nativeTexImage`：上游是 JNI 直传 Bitmap 给 GL 上传纹理。鸿蒙必须走 NAPI（方案 §5-⑤），
 *     由 native-image / gl-render 模块提供；本类通过 `setTexImageBridge()` 注入，
 *     未注入时 texImage() **抛错**而不是静默成功（避免"看起来能渲染"的假绿）。
 */

import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import display from '@ohos.display';
import { Utils } from '../../unifile/Utils';

const TAG: string = 'Image';

/** 纹理上传桥（对位上游 `nativeTexImage(Bitmap, init, offsetX, offsetY, w, h)`）。 */
export interface TexImageBridge {
  texImage(pixelMap: image.PixelMap, init: boolean, offsetX: number, offsetY: number,
    width: number, height: number): void;
}

export class Image {
  /** 屏幕尺寸，用于解码降采样（上游 Image.screenWidth/screenHeight）。 */
  static screenWidth: number = 0;
  static screenHeight: number = 0;

  private static texBridge: TexImageBridge | null = null;

  /** 对位上游 `Image.initialize(ehApplication)`：只需屏幕尺寸。 */
  static initialize(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      Image.screenWidth = d.width;
      Image.screenHeight = d.height;
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logW(TAG, 'initialize: 取屏幕尺寸失败，降采样按 1 处理');
      Image.screenWidth = 0;
      Image.screenHeight = 0;
    }
  }

  /** 由 native-image / gl-render 模块注入纹理上传实现（NAPI）。 */
  static setTexImageBridge(bridge: TexImageBridge | null): void {
    Image.texBridge = bridge;
  }

  private mPixelMap: image.PixelMap | null = null;
  private mReferences: number = 0;
  private readonly hardware: boolean;
  private readonly releaseCallback: () => void;
  private readonly animatedFlag: boolean;

  private constructor(pixelMap: image.PixelMap | null, hardware: boolean,
    releaseCallback: () => void, animated: boolean) {
    this.mPixelMap = pixelMap;
    this.hardware = hardware;
    this.releaseCallback = releaseCallback;
    this.animatedFlag = animated;
    if (pixelMap === null) {
      throw new Error('数据解码出错');
    }
  }

  /** 对位上游 `Image.decode(FileInputStream, hardware)`。入参改为已打开的 fs 句柄。 */
  static decodeStream(file: fs.File, hardware: boolean): Image | null {
    try {
      const imageSource: image.ImageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = imageSource.getImageInfoSync();
      const srcW: number = info.size.width;
      const srcH: number = info.size.height;
      const size: number = fs.statSync(file.fd).size;
      let simpleSize: number = 1;
      if (size > 10485760) {
        simpleSize = Math.floor(size / 10485760) + 1;
      }
      const screenFactor: number = Image.screenWidth > 0 && Image.screenHeight > 0
        ? Math.max(1, Math.min(Math.floor(srcW / Image.screenWidth), Math.floor(srcH / Image.screenHeight)))
        : 1;
      const sampleSize: number = Math.max(screenFactor, simpleSize);

      const options: image.DecodingOptions = {
        sampleSize: sampleSize,
        editable: false
      };
      // 上游 hardware=true 对应 ALLOCATOR_DEFAULT（GPU/硬件缓冲）；ArkTS 用 desiredPixelFormat 控制，
      // 但 GL 纹理路径必须软件内存（上游注释：必须 copy 到 tile buffer），故这里按 hardware 反选后
      // 由调用方决定：hardware=false → RGBA_8888 软件内存。
      if (!hardware) {
        options.desiredPixelFormat = image.PixelMapFormat.RGBA_8888;
      }
      const pixelMap: image.PixelMap = imageSource.createPixelMapSync(options);
      imageSource.release();
      return new Image(pixelMap, hardware, () => {
      }, false);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logE(TAG, `decodeStream failed: ${e}`);
      return null;
    }
  }

  /** 对位上游 `Image.decode(Drawable, hardware)`：鸿蒙入参直接是 PixelMap。 */
  static decodePixelMap(pixelMap: image.PixelMap | null, hardware: boolean): Image | null {
    try {
      return new Image(pixelMap, hardware, () => {
      }, false);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logE(TAG, `decodePixelMap failed: ${e}`);
      return null;
    }
  }

  /** 对位上游 `Image.create(Bitmap)`：持有一个已有 PixelMap（不拷贝）。 */
  static create(pixelMap: image.PixelMap): Image | null {
    return Image.decodePixelMap(pixelMap, false);
  }

  /** 对位上游 `val animated`：PixelMap 是静态帧，动图由 Image1 承担（见文件头）。 */
  getAnimated(): boolean {
    return this.animatedFlag;
  }

  getWidth(): number {
    const pm: image.PixelMap | null = this.mPixelMap;
    if (pm === null) {
      return 0;
    }
    return pm.getImageInfoSync().size.width;
  }

  getHeight(): number {
    const pm: image.PixelMap | null = this.mPixelMap;
    if (pm === null) {
      return 0;
    }
    return pm.getImageInfoSync().size.height;
  }

  isRecycled(): boolean {
    return this.mPixelMap === null;
  }

  /** 对位上游 `@Synchronized fun recycle()`。 */
  recycle(): void {
    const pm: image.PixelMap | null = this.mPixelMap;
    if (pm === null) {
      return;
    }
    this.mPixelMap = null;
    try {
      pm.release();
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logW(TAG, `pixelMap.release failed: ${e}`);
    }
    this.releaseCallback();
  }

  /** 对位上游 `@Synchronized fun obtain(): Boolean`。 */
  obtain(): boolean {
    if (this.isRecycled()) {
      return false;
    }
    ++this.mReferences;
    return true;
  }

  /**
   * 对位上游 `@Synchronized fun release()`（引用计数）。
   * 注意：上游同名的构造参数 `val release: () -> Unit?` 已改名 releaseCallback（ArkTS 无属性/方法重载）。
   */
  release(): void {
    --this.mReferences;
    if (this.mReferences <= 0 && !this.isRecycled()) {
      this.recycle();
    }
  }

  /** 对位上游 `getDrawable()`（上游返回 Drawable，鸿蒙返回 PixelMap）。 */
  getPixelMap(): image.PixelMap {
    if (!this.obtain()) {
      throw new Error('Recycled!');
    }
    const pm: image.PixelMap | null = this.mPixelMap;
    if (pm === null) {
      throw new Error('Recycled!');
    }
    return pm;
  }

  /**
   * 对位上游 `texImage(init, offsetX, offsetY, width, height)`。
   * 硬件缓冲不能用于 glgallery（上游 check），这里同样拒。
   */
  texImage(init: boolean, offsetX: number, offsetY: number, width: number, height: number): void {
    if (this.hardware) {
      throw new Error('Hardware buffer cannot be used in glgallery');
    }
    const pm: image.PixelMap | null = this.mPixelMap;
    if (pm === null) {
      throw new Error('Recycled!');
    }
    const bridge: TexImageBridge | null = Image.texBridge;
    if (bridge === null) {
      // 上游是 nativeTexImage(...) 直调 JNI；鸿蒙必须经 NAPI，由 native-image/gl-render 注入
      throw new Error('TODO(native-image/gl-render): TexImageBridge 未注入，无法上传 GL 纹理');
    }
    bridge.texImage(pm, init, offsetX, offsetY, width, height);
  }

  /** 对位上游 `start()`：静态帧无需启动；动图路径见 Image1。 */
  start(): void {
    // 静态 PixelMap 无动画可启动（上游只在 AnimatedImageDrawable 上 start）
  }

  /** 对位上游 `val delay`：动图 10ms，否则 0。 */
  getDelay(): number {
    return this.animatedFlag ? 10 : 0;
  }

  /** 对位上游 `val isOpaque`（PixelFormat.OPAQUE 判定 → PixelMap alphaType）。 */
  isOpaque(): boolean {
    const pm: image.PixelMap | null = this.mPixelMap;
    if (pm === null) {
      return false;
    }
    return pm.getImageInfoSync().alphaType === image.AlphaType.OPAQUE;
  }
}
