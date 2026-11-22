/*
 * Copyright 2016 Hippo Seven
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { GalleryPreview } from './GalleryPreview';

/**
 * 预览目标（跨模块契约，待 Lead 登记 C-8）：
 *
 * 上游 `PreviewSet.load(LoadImageView view, long gid, int index)` 直接操作
 * `com.hippo.widget.LoadImageView`（ui-widget 模块）。net-parse 不能依赖 ui-widget 的具体实现，
 * 否则两个模块编译期互相锁死，所以这里声明一个**最小接口**，由 ui-widget 的 `LoadImageView` 实现：
 *
 *   setClip(offsetX, offsetY, clipWidth, clipHeight)  ← 上游 view.setClip(...)
 *   resetClip()                                      ← 上游 view.resetClip()
 *   load(cacheKey, url)                              ← 上游 view.load(key, url)
 *
 * 迁移说明：ui-widget 侧只需 `class LoadImageView implements PreviewTarget`，方法签名不变，
 * 本模块所有 PreviewSet 实现都按接口调用，行为等价。
 */
export interface PreviewTarget {
  setClip(offsetX: number, offsetY: number, clipWidth: number, clipHeight: number): void;

  resetClip(): void;

  load(cacheKey: string, url: string): void;
}

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/PreviewSet.java
 * （inventory S0058，25 行）
 *
 * 预览集合抽象：详情页的缩略图网格（NormalPreviewSet）与整图预览（LargePreviewSet）。
 * 上游 abstract class implements Parcelable；ArkTS 无 Parcel，序列化走 JSON / 缓存键。
 */
export abstract class PreviewSet {
  abstract size(): number;

  abstract getPosition(index: number): number;

  abstract getPageUrlAt(index: number): string;

  abstract getGalleryPreview(gid: number, index: number): GalleryPreview;

  abstract load(view: PreviewTarget, gid: number, index: number): void;

  /**
   * 深拷贝（上游走 Parcel：CREATOR 重建具体类型）。
   * 调用方拿到的是**独立实例**，改它不影响原对象。
   */
  abstract copy(): PreviewSet;
}

/** Java 的 Integer.MIN_VALUE（GalleryPreview 的裁剪区默认值）。 */
export const INT_MIN: number = -2147483648;
