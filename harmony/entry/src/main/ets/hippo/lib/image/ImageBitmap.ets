/*
 * 对位上游：app/src/main/java/com/hippo/lib/image/ImageBitmap.kt
 *
 * ⚠️ 本文件在上游是**整体被注释掉的死代码**（实测：335 行 / 335 行注释，0 行有效代码，
 *    `git show origin/upstream:app/src/main/java/com/hippo/lib/image/ImageBitmap.kt` 每行都以 `//` 开头）。
 *    因此上游编译产物里没有 ImageBitmap 类，也没有任何调用点能引用它
 *    （原设计是 `Image1`（native 像素）+ `Bitmap`（渲染目标）的组合，后来被 `Image.kt` 的
 *     PixelMap 路线取代）。
 *
 * 本 port 的处理（不是"没做"，是"上游本来就没有可移植的实现"）：
 *   - 保留同名文件与目标路径（inventory 一一对应），但不提供可实例化的假类 ——
 *     凭空造一个 ImageBitmap 会给下游一个上游不存在的类型，属于污染 API。
 *   - 原设计在这里以文档形式保留，将来若要在鸿蒙恢复该形态（Image1 + PixelMap 组合），
 *     照下面结构实现即可。
 *
 * 原设计（上游注释代码的结构摘要）：
 *   class ImageBitmap(image1_or_bitmap) : Animatable, Runnable
 *     - 两个构造器：ImageBitmap(Image1)（多帧时保留 Image1，单帧则立即 recycle）
 *                  ImageBitmap(Bitmap)（FORMAT_PLAIN 直用）
 *     - obtain()/release() 引用计数；release 到 0 时 recycle bitmap 与 Image1
 *     - addCallback(WeakReference<Callback>) / removeCallback：多帧时通过 Handler 在主线程
 *       invalidateSelf()，Callback 接口只有 invalidateImage(who: ImageBitmap?)
 *     - draw(canvas, src, dst, paint)：`image1.render(...)` 到 mBitmap 或直接 drawBitmap
 *     - start()/stop()/isRunning()：多帧时按 `image1.delay` 自循环重绘
 *     - format / isOpaque / byteCount / frameCount 转发自 Image1
 *
 * 鸿蒙对位要点（将来实现时）：

 *   - Bitmap → @ohos.multimedia.image 的 PixelMap；Canvas/Paint → ArkUI CanvasRenderingContext2D
 *     或 native GL（纹理路径见 gl-render 模块）
 *   - WeakReference<Callback> → ArkTS 无弱引用，改用显式注册/注销 + 强引用集合（由持有方负责移除）
 *   - Handler(Looper.getMainLooper()) → @ohos.uvloop / setInterval 或 ArkUI 的 animateTo 帧回调
 */

const TAG: string = 'ImageBitmap';

/**
 * 上游 ImageBitmap 在 2.0.2.6 里是死代码，本 port 不提供实现。
 * 该函数存在只为让「误引用」在编译/运行期马上暴露，而不是拿到一个空壳对象。
 */
export function imageBitmapNotAvailable(): never {
  throw new Error(
    `[${TAG}] 上游 ImageBitmap.kt 整体被注释（dead code，0 行有效代码），本 port 不提供实现；` +
    '如需多帧合成请用 Image1（native）+ PixelMap 路线');
}
