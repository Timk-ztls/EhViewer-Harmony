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
 * 1:1 对位 upstream: .../client/data/GalleryTagGroup.java（inventory S0052，59 行）
 *
 * 详情页标签分组（"language" / "artist" / "male" … 各一组）。
 * 上游 mTagList 是 private final ArrayList<String>，只暴露 addTag/size/getTagAt。
 * ArkTS 版保持同样封装：数组私有，方法名不变。
 */
export class GalleryTagGroup {
  groupName: string = '';
  private readonly _tagList: string[] = [];

  /** 对齐 addTag(String)。 */
  addTag(tag: string): void {
    this._tagList.push(tag);
  }

  size(): number {
    return this._tagList.length;
  }

  getTagAt(position: number): string {
    return this._tagList[position];
  }

  /** 供 parser / UI 只读遍历（上游无此方法，但 list 本身是 final 可迭代；只增不改）。 */
  toArray(): string[] {
    return this._tagList.slice();
  }

  /** 深拷贝：标签数组经 `addTag` 重建（`_tagList` 是 private，只能走公开 API）。 */
  copy(): GalleryTagGroup {
    const n: GalleryTagGroup = new GalleryTagGroup();
    n.groupName = this.groupName;
    for (let i = 0; i < this.size(); i++) {
      n.addTag(this.getTagAt(i));
    }
    return n;
  }}
