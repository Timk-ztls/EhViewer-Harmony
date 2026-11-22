/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0485   上游: com/hippo/util/DrawableManager.kt（38 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/DrawableManager.ets
 *
 * 上游全部逻辑就一句：`ResourcesCompat.getDrawable(context.getResources(), resId, context.getTheme())`
 * （上面还有一大段被注释掉的旧版本，用 `Build.VERSION.SDK_INT >= LOLLIPOP` 分支——
 *  现在 minSdk 已高于它，所以上游自己也删掉了分支）。**返回可空**（`Drawable?`）。
 *
 * 平台差异：
 *  1. `ResourcesCompat.getDrawable` → `resourceManager.getMediaContentSync(resId)` 取字节，
 *     再 `image.createImageSource(arrayBuffer)` + `createPixelMap()`。
 *     ArkTS 无"直接取 Drawable"的 API（`getDrawableSync` 只存在于部分 SDK 版本且不返回 PixelMap）。
 *  2. `Drawable` → `image.PixelMap`（ArkUI `Image(pixelMap)` 直接可用）。
 *  3. **`Context/Theme` 参数消失**：鸿蒙的资源解析走 `resourceManager`，没有 theme 继承链
 *     （主题通过 `$r()`/资源限定词表达）。调用方传 `ctx.resourceManager`。
 *  4. **失败返回 null**（上游 `Drawable?`）：资源不存在 / 解码失败 → null，
 *     调用方按"占位图"处理。按陷阱 82 只在 catch 里打日志（这是低频失败路径）。
 */

import resourceManager from '@ohos.resourceManager';
import image from '@ohos.multimedia.image';
import hilog from '@ohos.hilog';

export class DrawableManager {

  /** 对应上游 `getVectorDrawable(context, resId)`；失败 → null（上游返回类型为 `Drawable?`） */
  static async getVectorDrawable(resMgr: resourceManager.ResourceManager | null,
    resId: number): Promise<image.PixelMap | null> {
    if (resMgr === null) {
      return null;
    }
    try {
      const content: Uint8Array = resMgr.getMediaContentSync(resId);
      // Uint8Array → ArrayBuffer（createImageSource 只接受 ArrayBuffer）
      const buf: ArrayBuffer = content.buffer.slice(content.byteOffset,
        content.byteOffset + content.byteLength);
      const source: image.ImageSource = image.createImageSource(buf);
      try {
        return await source.createPixelMap();
      } finally {
        source.release();
      }
    } catch (e) {
      hilog.error(0x0001, 'DrawableManager',
        'getVectorDrawable(%{public}d) failed: %{public}s', resId, `${(e as Error).message}`);
      return null;
    }
  }
}