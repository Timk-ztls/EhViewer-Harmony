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
import { EhTopListDetail, TopListInfo, TopListItem, TopListItemArray, TopListType } from '../data/TopList';
import { EhException } from '../exception/EhException';
import { OffensiveException, PiningException } from '../exception/MarkerExceptions';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/TopListParser.java
 * （inventory S0111，96 行）
 *
 * 排行榜页：`.ido` 的 14 个直接子元素按固定下标取（0=标题，1/3/5/7/9/11/13=七个榜单），
 * 每个榜单里再取 4 个时间段（allTime/pastYear/pastMonth/yesterday），每段 10 条。
 *
 * 上游的**硬编码下标**（照搬，不改成按 class 找）：页面结构一变就抛异常，
 * 这是「宁可炸也不要错位」的选择。
 *
 * 三条前置异常与 GalleryDetailParser 同款顺序：offensive → pining → `#d>p` 错误信息。
 */
export class TopListParser {
  private static readonly OFFENSIVE_STRING: string =
    '<p>(And if you choose to ignore this warning, you lose all rights to complain about it in the future.)</p>';
  private static readonly PINING_STRING: string = '<p>This gallery is pining for the fjords.</p>';
  private static readonly PATTERN_ERROR: RegExp = /<div class="d">\n<p>([^<]+)<\/p>/;

  static parse(body: string): EhTopListDetail {
    if (body.indexOf(TopListParser.OFFENSIVE_STRING) >= 0) {
      throw new OffensiveException();
    }
    if (body.indexOf(TopListParser.PINING_STRING) >= 0) {
      throw new PiningException();
    }
    const m: RegExpMatchArray | null = body.match(TopListParser.PATTERN_ERROR);
    if (m !== null) {
      throw new EhException(m[1]);
    }

    const ehTopListDetail: EhTopListDetail = new EhTopListDetail();
    const document: Document = Jsoup.parse(body);
    const ido: Elements = document.getElementsByClass('ido');
    if (ido.size() === 0) {
      throw new EhException('Can\'t parse top list');
    }
    const elements: Elements = ido.get(0).children();
    ehTopListDetail.title = elements.get(0).text();
    ehTopListDetail.galleryTopListInfo = TopListParser.parseInfo(elements.get(1), TopListType.GALLERY);
    ehTopListDetail.uploaderTopListInfo = TopListParser.parseInfo(elements.get(3), TopListType.UPLOADER);
    ehTopListDetail.taggingTopListInfo = TopListParser.parseInfo(elements.get(5), TopListType.TAGGING);
    ehTopListDetail.hentaiHomeTopListInfo = TopListParser.parseInfo(elements.get(7), TopListType.HENTAI_HOME);
    ehTopListDetail.ehTrackerTopListInfo = TopListParser.parseInfo(elements.get(9), TopListType.EH_TRACKER);
    ehTopListDetail.cleanUpTopListInfo = TopListParser.parseInfo(elements.get(11), TopListType.CLEANUP);
    ehTopListDetail.ratingAndReviewingTopListInfo =
      TopListParser.parseInfo(elements.get(13), TopListType.RATING_AND_REVIEWING);
    return ehTopListDetail;
  }

  private static parseInfo(element: Element, type: number): TopListInfo {
    const topListInfo: TopListInfo = new TopListInfo();
    topListInfo.type = type;
    const elements: Elements = element.children();
    // 下标 1/2/3/4 = allTime / pastYear / pastMonth / yesterday（上游顺序，逐字照搬）
    topListInfo.allTimeTopList = TopListParser.parseArray(
      TopListParser.nthChild(elements.get(1), 1, 0));
    topListInfo.pastYearTopList = TopListParser.parseArray(
      TopListParser.nthChild(elements.get(2), 1, 0));
    topListInfo.pastMonthTopList = TopListParser.parseArray(
      TopListParser.nthChild(elements.get(3), 1, 0));
    topListInfo.yesterdayTopList = TopListParser.parseArray(
      TopListParser.nthChild(elements.get(4), 1, 0));
    return topListInfo;
  }

  /** `element.child(1).child(0)` 的等价（上游链式取子）。 */
  private static nthChild(element: Element, first: number, second: number): Element {
    const c0: Element | null = element.child(first);
    if (c0 === null) {
      throw new Error('top list structure unexpected');
    }
    const c1: Element | null = c0.child(second);
    if (c1 === null) {
      throw new Error('top list structure unexpected');
    }
    return c1;
  }

  private static parseArray(ele: Element): TopListItemArray {
    const topListItemArray: TopListItemArray = new TopListItemArray();
    const minItems: Elements = ele.getElementsByClass('tun');
    const items: TopListItem[] = new Array<TopListItem>(minItems.size());
    for (let i = 0; i < minItems.size(); i++) {
      const inner: Element | null = minItems.get(i).child(0);
      const topListItem: TopListItem = new TopListItem();
      if (inner !== null) {
        topListItem.value = inner.text();
        topListItem.href = inner.attr('href');
      }
      items[i] = topListItem;
    }
    topListItemArray.itemArray = items;
    return topListItemArray;
  }
}
