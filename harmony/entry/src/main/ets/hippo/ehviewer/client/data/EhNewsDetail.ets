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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/EhNewsDetail.java
 * （inventory S0043）
 *
 * 新闻页容器。三个字段都是**惰性求值**的缓存：
 *   - `getEventPane()`：从 webData 里取 `#eventpane`，**要求它恰好有 3 个子元素**（不是 3 就不算事件条）
 *   - `getHtmlData()`：取文档的第一个子节点（通常是 `<html>`）的 outerHtml —— 用于内嵌展示整页
 *
 * 缓存语义照搬：算出 null 时**不缓存**（下次还会重算），算出非 null 才写回字段。
 */
export class EhNewsDetail {
  webData: string | null = null;
  eventPane: string | null = null;
  htmlData: string | null = null;

  constructor(webData?: string) {
    if (webData !== undefined && webData !== null) {
      this.webData = webData;
    }
  }

  getEventPane(): string | null {
    if (this.eventPane !== null) {
      return this.eventPane;
    }
    const webData: string = this.webData === null ? '' : (this.webData as string);
    const document: Document = Jsoup.parse(webData);
    const eventPaneElement: Element | null = document.getElementById('eventpane');
    if (eventPaneElement !== null && eventPaneElement.children().size() === 3) {
      this.eventPane = eventPaneElement.html();
    }
    return this.eventPane;
  }

  getHtmlData(): string | null {
    if (this.htmlData !== null) {
      return this.htmlData;
    }
    const webData: string = this.webData === null ? '' : (this.webData as string);
    const document: Document = Jsoup.parse(webData);
    const element: Element | null = document.child(0);
    this.htmlData = element === null ? null : element.outerHtml();
    return this.htmlData;
  }
}