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
import { GalleryInfo } from '../data/GalleryInfo';
import { ListUrlBuilder } from '../data/ListUrlBuilder';
import { EhException } from '../exception/EhException';
import { ParseException } from '../exception/ParseException';
import { GalleryListParser, ListResult } from './GalleryListParser';
import { ParserUtils } from './ParserUtils';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/FavoritesParser.java
 * （inventory S0094，107 行）
 *
 * 收藏页 = 「10 个分类的计数/名称」+「排序方式」+ 复用 `GalleryListParser` 的列表解析。
 *
 * 逐条照搬的细节：
 *   - 未登录判定：body 含 `"This page requires you to log on.</p>"` → `EhException(need_sign_in 文案)`
 *     （文案来自 `R.string.need_sign_in`，属 core-runtime i18n → 用 FavoritesParserConfig 注入）
 *   - `.ido` 里的 `.fp` 必须正好 11 个（上游 `AssertUtils.assertEquals(11, fps.size())`，
 *     断言失败会抛 AssertionError → 被 catch 包成 ParseException）；只用前 10 个：
 *     `countArray[i] = fp.child(0).text()`，`catArray[i] = trim(fp.child(2).text())`
 *   - 排序：`searchnav` 里第一个 `<select>` 里带 `selected` 的属性 `value` → favOrder
 *   - 之后把 `GalleryListParser.parse(d, body, MODE_NORMAL)` 的结果整体搬进来
 */
/** core-runtime 的 `R.string.need_sign_in` 注入点。 */
export class FavoritesParserConfig {
  getNeedSignInMessage(): string {
    return '需要登录';
  }
}

export class FavoritesParser {
  private static _config: FavoritesParserConfig = new FavoritesParserConfig();

  static setConfig(config: FavoritesParserConfig): void {
    FavoritesParser._config = config;
  }

  static parse(body: string): FavoritesResult {
    if (body.indexOf('This page requires you to log on.</p>') >= 0) {
      throw new EhException(FavoritesParser._config.getNeedSignInMessage());
    }

    const re: FavoritesResult = new FavoritesResult();
    const catArray: string[] = new Array<string>(10).fill('');
    const countArray: number[] = new Array<number>(10).fill(0);
    let d: Document;
    try {
      d = Jsoup.parse(body);
      const ido: Element | null = FavoritesParser.firstByClass(d, 'ido');
      if (ido === null) {
        throw new Error('ido is null');
      }
      const fps: Elements = ido.getElementsByClass('fp');
      // 上游 AssertUtils.assertEquals(11, fps.size())：不等即失败
      if (fps.size() !== 11) {
        throw new Error(`expected 11 .fp but got ${fps.size()}`);
      }
      for (let i = 0; i < 10; i++) {
        const fp: Element = fps.get(i);
        const c0: Element | null = fp.child(0);
        const c2: Element | null = fp.child(2);
        countArray[i] = ParserUtils.parseInt(c0 === null ? '' : c0.text(), 0);
        catArray[i] = ParserUtils.trim(c2 === null ? '' : c2.text());
      }
      // 排序
      const orders: Elements = FavoritesParser.allByClass(d, 'searchnav');
      if (orders.size() > 0) {
        const order: Element = orders.first() as Element;
        const selects: Elements = order.getElementsByTag('select');
        if (selects.size() > 0) {
          const sel: Element = selects.get(0);
          const result: Elements = sel.getElementsByAttribute('selected');
          re.favOrder = result.attr('value');
        }
      }
    } catch (e) {
      throw new ParseException('Parse favorites error', body, e as Error);
    }

    const result: ListResult = GalleryListParser.parseDocument(d, body, ListUrlBuilder.MODE_NORMAL);
    re.catArray = catArray;
    re.countArray = countArray;
    re.pages = result.pages;
    re.nextPage = result.nextPage;
    re.resultCount = result.resultCount;
    re.firstHref = result.firstHref;
    re.nextHref = result.nextHref;
    re.prevHref = result.prevHref;
    re.lastHref = result.lastHref;
    re.galleryInfoList = result.galleryInfoList;
    return re;
  }

  private static firstByClass(root: Element, className: string): Element | null {
    const es: Elements = root.getElementsByClass(className);
    return es.size() === 0 ? null : es.get(0);
  }

  private static allByClass(root: Element, className: string): Elements {
    return root.getElementsByClass(className);
  }
}

/** 对齐 FavoritesParser.Result。 */
export class FavoritesResult {
  /** Size 10 */
  catArray: string[] = [];
  /** Size 10 */
  countArray: number[] = [];
  pages: number = 0;
  nextPage: number = 0;
  resultCount: string = '';
  firstHref: string = '';
  prevHref: string = '';
  nextHref: string = '';
  lastHref: string = '';
  favOrder: string = '';
  galleryInfoList: GalleryInfo[] = [];
}

