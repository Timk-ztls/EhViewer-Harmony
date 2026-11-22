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

import { JsonObject } from './Json';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/VoteCommentParser.java
 * （inventory S0113，41 行）
 *
 * `{"comment_id":1253922,"comment_score":-19,"comment_vote":0}` → Result
 *
 * 注意 `expectVote` **不是**服务端返回值，而是把调用方传入的 `vote` 原样回填（上游如此），
 * 用于 UI 做乐观更新对账，不要误以为它是响应字段。
 */
export class VoteCommentParser {
  /** 对齐 `parse(String body, int vote)`。 */
  static parse(body: string, vote: number): VoteCommentResult {
    const result: VoteCommentResult = new VoteCommentResult();
    const jo: JsonObject = JsonObject.parse(body);
    result.id = jo.getLong('comment_id');
    result.score = jo.getInt('comment_score');
    result.vote = jo.getInt('comment_vote');
    result.expectVote = vote;
    return result;
  }
}

/** 对齐 VoteCommentParser.Result（静态嵌套类 → 文件级）。 */
export class VoteCommentResult {
  id: number = 0;
  score: number = 0;
  vote: number = 0;
  expectVote: number = 0;
}
