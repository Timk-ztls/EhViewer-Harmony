/*
 * 对位上游：app/src/main/java/com/hippo/lib/image/RecycledException.kt
 *
 * 平台对位：Kotlin `class RecycledException : Exception()` → ArkTS 只有 Error 一种异常类型
 * （方案 §5-⑧：异常模型不同，保留类名、改为 Error 子类，catch 处按 instanceof 分派）。
 */

/** 对位 com.hippo.lib.image.RecycledException：Image 已被回收后继续使用。 */
export class RecycledException extends Error {
  constructor(message?: string) {
    super(message !== undefined ? message : 'Image is recycled');
    this.name = 'RecycledException';
  }
}
