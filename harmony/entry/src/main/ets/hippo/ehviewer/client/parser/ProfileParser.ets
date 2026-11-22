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
import { EhException } from '../exception/EhException';
import { ParseException } from '../exception/ParseException';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/ProfileParser.java
 * （inventory S0108，93 行）
 *
 * 两种入口（上游为两个方法，ArkTS 无重载 → 加后缀）：
 *   parse(body)     —— 论坛用户页：`#profilename` 取显示名，其 next.next 的 child(0).src 取头像
 *   parseNew(body)  —— 反代返回的转义 HTML：先 `\u003C`→`<`、去掉 `\n`/`\"`/`\t`，
 *                      再从 `#userlinks` 下钻取名字；含 `ERR_CONNECTION_REFUSED` 时返回空 Result
 *
 * 头像规则：空 → null；不以 `http` 开头 → 前面拼 `EhUrl.URL_FORUMS`。
 * 取头像的整段在 try 里（拿不到就算「没有头像」，不影响显示名）。
 */
export class ProfileParser {
  /** 对齐 `parse(String body)`。 */
  static parse(body: string): ProfileResult {
    try {
      const result: ProfileResult = new ProfileResult();
      const d: Document = Jsoup.parse(body);
      const profilename: Element | null = d.getElementById('profilename');
      if (profilename === null) {
        throw new Error('profilename is null');
      }
      const nameChild: Element | null = profilename.child(0);
      if (nameChild === null) {
        throw new Error('profilename child(0) is null');
      }
      result.displayName = nameChild.text();
      ProfileParser.parseAvatar(profilename, result);
      return result;
    } catch (e) {
      if (e instanceof ParseException) {
        throw e as ParseException;
      }
      throw new ParseException('Parse forums error', body, e as Error);
    }
  }

  /** 对齐 `parseNew(String body)`：反转义反代返回的 HTML 片段。 */
  static parseNew(body: string): ProfileResult {
    try {
      const htmlString: string = body
        .replace(/\\u003C/g, '<')
        .replace(/\\n/g, '')
        .replace(/\\"/g, '')
        .replace(/\\t/g, '');
      const result: ProfileResult = new ProfileResult();
      if (htmlString.indexOf('ERR_CONNECTION_REFUSED') >= 0) {
        return result;
      }
      const document: Document = Jsoup.parse(htmlString);
      const profilename: Element | null = document.getElementById('userlinks');
      if (profilename === null) {
        throw new Error('userlinks is null');
      }
      const c0: Element | null = profilename.child(0);
      const c1: Element | null = c0 === null ? null : c0.child(0);
      const c2: Element | null = c1 === null ? null : c1.child(0);
      if (c2 === null) {
        throw new Error('userlinks child(0).child(0).child(0) is null');
      }
      result.displayName = c2.text();
      ProfileParser.parseAvatar(profilename, result);
      return result;
    } catch (e) {
      if (e instanceof ParseException) {
        throw e as ParseException;
      }
      throw new ParseException('Parse forums error', body, e as Error);
    }
  }

  /** 头像：nextElementSibling().nextElementSibling().child(0).attr("src")，失败静默。 */
  private static parseAvatar(profilename: Element, result: ProfileResult): void {
    try {
      const sib1: Element | null = profilename.nextElementSibling();
      const sib2: Element | null = sib1 === null ? null : sib1.nextElementSibling();
      const child0: Element | null = sib2 === null ? null : sib2.child(0);
      const src: string = child0 === null ? '' : child0.attr('src');
      if (src.length === 0) {
        result.avatar = null;
      } else if (!src.startsWith('http')) {
        result.avatar = EhUrlForumsPrefix() + src;
      } else {
        result.avatar = src;
      }
    } catch (e) {
      // 上游 Log.i(TAG, "No avatar") —— 拿不到就算了
    }
  }
}

/** 避免在类体内引入额外 import 顺序问题（EhUrl 只在头像拼接时用）。 */
function EhUrlForumsPrefix(): string {
  return 'https://forums.e-hentai.org/';
}

/** 对齐 ProfileParser.Result。 */
export class ProfileResult {
  displayName: string = '';
  avatar: string | null = null;
}
