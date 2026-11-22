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

import { Document, Element, Jsoup } from '../../../jsoup/index';
import { EhException } from '../exception/EhException';
import { ParseException } from '../exception/ParseException';
import { JsonObject } from './Json';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GetEditCommentParser.java
 * （inventory S0105，56 行）
 *
 * `{"comment_id":123,"editable_comment":"<textarea name=\"commenttext_edit\">…</textarea>"}`
 * → { id, comment }
 *
 * 三个异常出口（顺序与作用域照搬）：
 *   1. JSON 里有 `error` 字段 → EhException(该字段)   ← **不在** JSONException 的 catch 里
 *   2. 解析出的片段里找不到 `textarea[name=commenttext_edit]` → ParseException
 *   3. 其余（JSON 非法等）→ ParseException("Can't parse editable comment")，cause 挂原异常
 *
 * `textarea.wholeText()` 取的是**全部文本节点**（含转义还原），不是 value 属性。
 */
export class GetEditCommentParser {
  static parse(body: string): EditCommentResult {
    try {
      const jsonObject: JsonObject = JsonObject.parse(body);
      if (jsonObject.has('error')) {
        throw new EhException(jsonObject.getString('error'));
      }
      const result: EditCommentResult = new EditCommentResult();
      result.id = jsonObject.getLong('comment_id');
      const fragment: Document = Jsoup.parseBodyFragment(jsonObject.getString('editable_comment'));
      const textarea: Element | null = fragment.selectFirst('textarea[name=commenttext_edit]');
      if (textarea === null) {
        throw new ParseException("Can't find editable comment", body);
      }
      result.comment = textarea.wholeText();
      return result;
    } catch (e) {
      // 上游只把 JSONException 包成 ParseException；EhException/ParseException 直接透出
      if (e instanceof EhException) {
        throw e as EhException;
      }
      if (e instanceof ParseException) {
        throw e as ParseException;
      }
      throw new ParseException("Can't parse editable comment", body, e as Error);
    }
  }
}

/** 对齐 GetEditCommentParser.Result。 */
export class EditCommentResult {
  id: number = 0;
  comment: string = '';
}
