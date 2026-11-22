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
 * 1:1 对位 upstream: .../client/data/GalleryComment.java（inventory S0047，78 行）
 *
 * 详情页评论项。字段语义（上游注释保留）：
 *   id == 0 表示「上传者评论」，不可投票
 *   voteUpAble/voteUpEd 与 voteDownAble/voteDownEd 区分「可投」与「已投」
 *   lastEdited 是最后编辑时间，0 表示未编辑
 */
@Observed
export class GalleryComment {
  /** 0 for uploader comment. can't vote */
  id: number = 0;
  score: number = 0;
  editable: boolean = false;
  voteUpAble: boolean = false;
  voteUpEd: boolean = false;
  voteDownAble: boolean = false;
  voteDownEd: boolean = false;
  voteState: string = '';
  time: number = 0;
  user: string = '';
  comment: string = '';
  lastEdited: number = 0;

  constructor() {
  }

  /** 深拷贝（上游走 Parcel）；全部是基本类型字段。 */
  copy(): GalleryComment {
    const n: GalleryComment = new GalleryComment();
    n.id = this.id;
    n.score = this.score;
    n.editable = this.editable;
    n.voteUpAble = this.voteUpAble;
    n.voteUpEd = this.voteUpEd;
    n.voteDownAble = this.voteDownAble;
    n.voteDownEd = this.voteDownEd;
    n.voteState = this.voteState;
    n.time = this.time;
    n.user = this.user;
    n.comment = this.comment;
    n.lastEdited = this.lastEdited;
    return n;
  }}
