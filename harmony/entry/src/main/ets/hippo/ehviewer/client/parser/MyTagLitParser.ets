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

import { Document, Element, Elements, Jsoup } from '../../../jsoup/index';
import { UserTag, UserTagList } from '../data/UserTag';
import { EhException } from '../exception/EhException';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/MyTagLitParser.java
 * （inventory S0106，93 行；上游类名就是 `MyTagLitParser`，少一个 s，**照搬不改**）
 *
 * 我的标签页：`#usertags_outer` 的 children 里**跳过第 0 个**，其余每个解析成一条 UserTag。
 *
 * 上游实现里有两处会抛的地方但被 catch 吞掉（`try{…}catch(Exception ignored){}`），照搬：
 *   - `#usertags_outer` 缺失 → 返回空列表（不是异常）
 *   - 解析某条出错 → 整段 catch，返回已累积的部分
 *
 * `parserUserTag` 里几个**上游会 NPE 的点**（`tag.getElementById(nameId).attr(...)` 没判空）
 * 在本层保持同样的失败模式：拿不到元素 → 抛错 → 被外层 catch 吞掉 → 返回部分结果。
 */
export class MyTagLitParser {
  private static readonly PATTERN_ERROR: RegExp = /<div class="d">\n<p>([^<]+)<\/p>/;

  static parse(body: string): UserTagList {
    const list: UserTagList = new UserTagList();
    list.userTags = [];
    const m: RegExpMatchArray | null = body.match(MyTagLitParser.PATTERN_ERROR);
    if (m !== null) {
      throw new EhException(m[1]);
    }
    try {
      const document: Document = Jsoup.parse(body);
      const element: Element | null = document.getElementById('usertags_outer');
      if (element === null) {
        return list;
      }
      const tags: Elements = element.children();
      for (let i = 0; i < tags.size(); i++) {
        if (i !== 0) {
          list.userTags.push(MyTagLitParser.parseUserTag(tags.get(i)));
        }
      }
    } catch (e) {
      // 上游 catch (Exception ignored)
    }
    return list;
  }

  private static parseUserTag(tag: Element): UserTag {
    const userTag: UserTag = new UserTag();
    userTag.userTagId = tag.id();
    // userTagId 形如 "usertag_12345"，取掉 7 位前缀 "usertag" 得到 id 片段
    const id: string = userTag.userTagId.substring(7);

    const nameEl: Element | null = tag.getElementById('tagpreview' + id);
    if (nameEl !== null && nameEl.attr('title') !== null) {
      userTag.tagName = nameEl.attr('title');
    }

    const watchInput: Element | null = tag.getElementById('tagwatch' + id);
    userTag.watched = watchInput !== null && watchInput.attr('checked') === 'checked';

    const hideInput: Element | null = tag.getElementById('taghide' + id);
    userTag.hidden = hideInput !== null && hideInput.attr('checked') === 'checked';

    const colorEl: Element | null = tag.getElementById('tagcolor' + id);
    userTag.color = colorEl === null ? '' : colorEl.attr('placeholder');

    const weightEl: Element | null = tag.getElementById('tagweight' + id);
    const weightString: string = weightEl === null ? '' : weightEl.attr('value');
    // 上游：空串先置 0，随后**无条件** Integer.parseInt(weightString) ——
    // 空串会抛 NumberFormatException，被外层 catch 吞掉。本层保持同样语义。
    if (weightString.length === 0) {
      userTag.tagWeight = 0;
    }
    const w: number = Number.parseInt(weightString, 10);
    if (Number.isNaN(w)) {
      throw new Error('weight is not a number');
    }
    userTag.tagWeight = w;
    return userTag;
  }
}
