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

import { PreviewTarget, INT_MIN } from './PreviewSet';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/GalleryPreview.java
 * （inventory S0051，59 行）
 *
 * 单个预览项。裁剪区默认 Integer.MIN_VALUE = 「未设置」，由 LoadImageView.setClip 解释。
 * 上游字段为 package-private（同包可直写），迁移后保持可写字段；跨包访问只通过
 * getPosition() / load()，与上游调用面一致。
 */
export class GalleryPreview {
  /** 图片缓存键（NormalPreviewSet 用 URL 路径，LargePreviewSet 用 EhCacheKeyFactory）。 */
  imageKey: string = '';
  imageUrl: string = '';
  pageUrl: string = '';
  position: number = 0;
  offsetX: number = INT_MIN;
  offsetY: number = INT_MIN;
  clipWidth: number = INT_MIN;
  clipHeight: number = INT_MIN;

  /** 对齐 GalleryPreview.getPosition()。 */
  getPosition(): number {
    return this.position;
  }

  /** 对齐 GalleryPreview.load(LoadImageView)：先设裁剪区，再按缓存键加载。 */
  load(view: PreviewTarget): void {
    view.setClip(this.offsetX, this.offsetY, this.clipWidth, this.clipHeight);
    view.load(this.imageKey, this.imageUrl);
  }
}
