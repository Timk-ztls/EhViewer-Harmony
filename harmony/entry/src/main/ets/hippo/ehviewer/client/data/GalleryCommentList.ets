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

import { GalleryComment } from './GalleryComment';

/**
 * 1:1 对位 upstream: .../client/data/GalleryCommentList.java（inventory S0048，66 行）
 *
 * comments + hasMore（是否还有下一页评论）。
 * 方法 DeleteComment(int) 的拼写与语义都照搬（删除第 num 项，返回新数组，不改原数组引用以外的状态）。
 */
export class GalleryCommentList {
  comments: GalleryComment[];
  hasMore: boolean;

  constructor(comments: GalleryComment[], hasMore: boolean) {
    this.comments = comments;
    this.hasMore = hasMore;
  }

  /** 对齐 DeleteComment(int num)。 */
  deleteComment(num: number): void {
    const result: GalleryComment[] = [];
    for (let i = 0; i < this.comments.length; i++) {
      if (i !== num) {
        result.push(this.comments[i]);
      }
    }
    this.comments = result;
  }

  /** 深拷贝：评论数组逐项复制（上游 Parcel 会递归写每个 GalleryComment）。 */
  copy(): GalleryCommentList {
    const list: GalleryComment[] = [];
    for (let i = 0; i < this.comments.length; i++) {
      list.push(this.comments[i].copy());
    }
    return new GalleryCommentList(list, this.hasMore);
  }}
