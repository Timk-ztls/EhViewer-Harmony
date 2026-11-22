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

import { PreviewSet, PreviewTarget } from './PreviewSet';
import { GalleryPreview } from './GalleryPreview';
import { EhCacheKeyFactory } from '../EhCacheKeyFactory';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/LargePreviewSet.java
 * （inventory S0054，88 行）
 *
 * 整图预览：不做裁剪（load 前 resetClip），缓存键走
 * `EhCacheKeyFactory.getLargePreviewKey(gid, position)`。
 */
export class LargePreviewSet extends PreviewSet {
  private readonly _positionList: number[] = [];
  private readonly _imageUrlList: string[] = [];
  private readonly _pageUrlList: string[] = [];

  addItem(index: number, imageUrl: string, pageUrl: string): void {
    this._positionList.push(index);
    this._imageUrlList.push(imageUrl);
    this._pageUrlList.push(pageUrl);
  }

  size(): number {
    return this._imageUrlList.length;
  }

  getPosition(index: number): number {
    return this._positionList[index];
  }

  getPageUrlAt(index: number): string {
    return this._pageUrlList[index];
  }

  getGalleryPreview(gid: number, index: number): GalleryPreview {
    const preview: GalleryPreview = new GalleryPreview();
    preview.position = this._positionList[index];
    preview.imageKey = EhCacheKeyFactory.getLargePreviewKey(gid, preview.position);
    preview.imageUrl = this._imageUrlList[index];
    preview.pageUrl = this._pageUrlList[index];
    return preview;
  }

  load(view: PreviewTarget, gid: number, index: number): void {
    view.resetClip();
    view.load(EhCacheKeyFactory.getLargePreviewKey(gid, this._positionList[index]),
      this._imageUrlList[index]);
  }

  /** 深拷贝：三个数组各自复制。 */
  copy(): PreviewSet {
    const n: LargePreviewSet = new LargePreviewSet();
    for (let i = 0; i < this._positionList.length; i++) {
      n.addItem(this._positionList[i], this._imageUrlList[i], this._pageUrlList[i]);
    }
    return n;
  }}
