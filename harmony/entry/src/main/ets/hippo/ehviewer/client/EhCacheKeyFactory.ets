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

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhCacheKeyFactory.java
 * （inventory S0069，33 行）
 *
 * 图片/预览的缓存键构造。键格式必须逐字符一致：磁盘缓存目录与 Android 版共用同一套键，
 * 且 `LargePreviewSet.getGalleryPreview` 依赖 `getLargePreviewKey(gid, position)`。
 */
export class EhCacheKeyFactory {
  /** 注意上游的怪异行为：thumb 键其实是 `preview:large:<gid>:0`（注释里保留了旧键）。 */
  static getThumbKey(gid: number): string {
    return 'preview:large:' + gid + ':' + 0;
  }

  static getNormalPreviewKey(gid: number, index: number): string {
    return 'preview:normal:' + gid + ':' + index;
  }

  static getLargePreviewKey(gid: number, index: number): string {
    return 'preview:large:' + gid + ':' + index;
  }

  static getLargePreviewSetKey(gid: number, index: number): string {
    return 'large_preview_set:' + gid + ':' + index;
  }

  static getImageKey(gid: number, index: number): string {
    return 'image:' + gid + ':' + index;
  }
}
