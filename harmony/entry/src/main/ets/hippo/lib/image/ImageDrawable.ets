/*
 * 对位上游：app/src/main/java/com/hippo/lib/image/ImageDrawable.kt
 *
 * ⚠️ 与 ImageBitmap.kt 同样：本文件在上游**整体被注释掉**（实测 88 行 / 88 行注释，0 行有效代码）。
 *    上游没有任何地方能 `new ImageDrawable(...)`，它在编译产物里不存在。
 *
 * 原设计（上游注释代码结构摘要）：
 *   class ImageDrawable(imageBitmap: ImageBitmap) : Drawable(), Animatable, ImageBitmap.Callback
 *     - 构造时 imageBitmap.obtain()，失败抛 RecycledException
 *     - Paint(Paint.FILTER_BITMAP_FLAG) 作为绘制画笔；addCallback(this)
 *     - draw(canvas) → imageBitmap.draw(canvas, null, bounds, paint)
 *     - setAlpha/setColorFilter → 转发给 Paint
 *     - getOpacity → isOpaque ? OPAQUE : UNKNOWN
 *     - getIntrinsicWidth/Height → imageBitmap 的宽高
 *     - start/stop/isRunning → 转发；invalidateImage → invalidateSelf()
 *
 * 鸿蒙对位要点（将来实现时）：
 *   - android.graphics.drawable.Drawable 体系在 ArkTS 不存在（方案 §5-⑥：无 Drawable 体系）。
 *     本项目由 ui-widget 模块自建 `hippo/drawable`（已落地 DrawablePalette/DrawableSpec/PathData），
 *     若将来要恢复 ImageDrawable，应实现该体系的最小宿主接口，而不是另起一套。
 *   - PixelMap 已在 lib/image/Image.ets 里承担「像素源」角色；绘制走 ArkUI Canvas 或 native GL。
 */

const TAG: string = 'ImageDrawable';

/**
 * 上游 ImageDrawable 在 2.0.2.6 里是死代码，本 port 不提供实现。
 * 与 ImageBitmap.ets 同策略：误引用立即暴露，不给空壳。
 */
export function imageDrawableNotAvailable(): never {
  throw new Error(
    `[${TAG}] 上游 ImageDrawable.kt 整体被注释（dead code，0 行有效代码），本 port 不提供实现；` +
    '绘制请走 ArkUI Canvas / native GL，像素源用 lib/image/Image.ets 的 PixelMap');
}
