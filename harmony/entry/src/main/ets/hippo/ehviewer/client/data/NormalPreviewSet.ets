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

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/NormalPreviewSet.java
 * （inventory S0057，117 行）
 *
 * 缩略图网格预览：每项是一个裁剪块（offset + clip 尺寸）。
 * 上游用 `IntList`（com.hippo.lib.yorozuya.collect.IntList，core-runtime）存位置/偏移，
 * 这里用 `number[]` 等价（IntList 底层就是 int 数组，无额外语义）；字符串表用 string[]。
 */
export class NormalPreviewSet extends PreviewSet {
  private _positionList: number[] = [];
  private _imageKeyList: string[] = [];
  private _imageUrlList: string[] = [];
  private _offsetXList: number[] = [];
  private _offsetYList: number[] = [];
  private _clipWidthList: number[] = [];
  private _clipHeightList: number[] = [];
  private _pageUrlList: string[] = [];

  /** 对齐 private getImageKey(String imageUrl)：取第一个 '/' 之后的部分作为缓存键。 */
  private getImageKey(imageUrl: string): string {
    const index: number = imageUrl.indexOf('/');
    if (index >= 0) {
      return imageUrl.substring(index + 1);
    }
    return imageUrl;
  }

  /** 对齐 addItem(int, String, int, int, int, int, String)。 */
  addItem(position: number, imageUrl: string, xOffset: number, yOffset: number, width: number,
    height: number, pageUrl: string): void {
    this._positionList.push(position);
    this._imageKeyList.push(this.getImageKey(imageUrl));
    this._imageUrlList.push(imageUrl);
    this._offsetXList.push(xOffset);
    this._offsetYList.push(yOffset);
    this._clipWidthList.push(width);
    this._clipHeightList.push(height);
    this._pageUrlList.push(pageUrl);
  }

  size(): number {
    return this._positionList.length;
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
    preview.imageKey = this._imageKeyList[index];
    preview.imageUrl = this._imageUrlList[index];
    preview.pageUrl = this._pageUrlList[index];
    preview.offsetX = this._offsetXList[index];
    preview.offsetY = this._offsetYList[index];
    preview.clipWidth = this._clipWidthList[index];
    preview.clipHeight = this._clipHeightList[index];
    return preview;
  }

  load(view: PreviewTarget, gid: number, index: number): void {
    view.setClip(this._offsetXList[index], this._offsetYList[index],
      this._clipWidthList[index], this._clipHeightList[index]);
    view.load(this._imageKeyList[index], this._imageUrlList[index]);
  }

  /**
   * 深拷贝：逐个数组复制（上游走 Parcel，等价于重建全部列表）。
   * 私有 add 方法不暴露，这里直接用内部列表重新填。
   */
  copy(): PreviewSet {
    const n: NormalPreviewSet = new NormalPreviewSet();
    for (let i = 0; i < this._positionList.length; i++) {
      n._positionList.push(this._positionList[i]);
      n._imageKeyList.push(this._imageKeyList[i]);
      n._imageUrlList.push(this._imageUrlList[i]);
      n._offsetXList.push(this._offsetXList[i]);
      n._offsetYList.push(this._offsetYList[i]);
      n._clipWidthList.push(this._clipWidthList[i]);
      n._clipHeightList.push(this._clipHeightList[i]);
      n._pageUrlList.push(this._pageUrlList[i]);
    }
    return n;
  }}
