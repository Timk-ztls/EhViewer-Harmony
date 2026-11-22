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

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/EhEventParse.java
 * （inventory S0092，51 行）
 *
 * 从首页 HTML 里取 `#eventpane` 的 innerHTML（每日签到提示条）。
 * 找不到 → 返回 null（**不抛**，上游如此）。
 *
 * 上游该文件里有大段被注释掉的样例 HTML，只在注释里保留，不搬。
 */
export class EhEventParse {
  static parse(body: string): string | null {
    const document: Document = Jsoup.parse(body);
    const eventPane: Element | null = document.getElementById('eventpane');
    if (eventPane !== null) {
      return eventPane.html();
    }
    return null;
  }
}
