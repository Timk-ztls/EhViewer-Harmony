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

import { UrlBuilder } from '../../../network/UrlBuilder';
import { FormBodyBuilder } from '../../../okhttp/FormBody';
import { EhUrl } from '../EhUrl';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/FavListUrlBuilder.java
 * （inventory S0045，170 行）
 *
 * 收藏页 URL 拼装（与 ListUrlBuilder 是姊妹类，但规则不同）：
 *   - favcat 取值 0..9；`FAV_CAT_ALL = -1`（不加参数）、`FAV_CAT_LOCAL = -2`（本地收藏，不加参数）
 *   - 有关键词时才补 `sn=on`（Name）、`st=on`（Tags）、`sf=on`（Note）三个检索范围开关
 *   - 翻页 `page` 只在 index > 0 时加
 *
 * 上游的 `// ub.addQuery("favcat", "all")` 被注释掉了（`FAV_CAT_ALL` 不加参数），逐字保留。
 */
export class FavListUrlBuilder {
  static readonly FAV_CAT_ALL: number = -1;
  static readonly FAV_CAT_LOCAL: number = -2;

  /** 对齐 ContentLayout.ContentHelper 的翻页动作常量（与 ListUrlBuilder 同一套数值）。 */
  static readonly GOTO_FIRST_PAGE: number = 0;
  static readonly GOTO_PREV_PAGE: number = 1;
  static readonly GOTO_NEXT_PAGE: number = 2;
  static readonly GOTO_LAST_PAGE: number = 3;
  static readonly TYPE_SOMEWHERE: number = 5;

  private static readonly PATTERN_SEEK_DATE: RegExp = /seek=(\d+)-(\d+)-(\d+)/;
  private static readonly PATTERN_JUMP_NODE: RegExp = /jump=(\d)[ymwd]/;

  private _index: number = 0;
  private _keyword: string | null = null;
  private _favCat: number = FavListUrlBuilder.FAV_CAT_ALL;

  setIndex(index: number): void {
    this._index = index;
  }

  setKeyword(keyword: string | null): void {
    this._keyword = keyword;
  }

  setFavCat(favCat: number): void {
    this._favCat = favCat;
  }

  getKeyword(): string | null {
    return this._keyword;
  }

  getFavCat(): number {
    return this._favCat;
  }

  /** 对齐 isValidFavCat：只接受 0..9。 */
  static isValidFavCat(favCat: number): boolean {
    return favCat >= 0 && favCat <= 9;
  }

  isLocalFavCat(): boolean {
    return this._favCat === FavListUrlBuilder.FAV_CAT_LOCAL;
  }

  /** 对齐 jumpHrefBuild(String, String)：替换已有 seek/jump，否则追加。 */
  jumpHrefBuild(urlOld: string, appendParam: string): string {
    const seekM: RegExpMatchArray | null = urlOld.match(FavListUrlBuilder.PATTERN_SEEK_DATE);
    const jumpM: RegExpMatchArray | null = urlOld.match(FavListUrlBuilder.PATTERN_JUMP_NODE);
    if (seekM !== null) {
      return urlOld.replace(seekM[0], appendParam);
    } else if (jumpM !== null) {
      return urlOld.replace(jumpM[0], appendParam);
    }
    return urlOld + '&' + appendParam;
  }

  /** 对齐 build(int pageAction, GalleryInfoContentHelper helper)。 */
  buildForPageAction(pageAction: number, helper: FavContentHelperLike): string {
    switch (pageAction) {
      case FavListUrlBuilder.GOTO_PREV_PAGE:
        return helper.getPrevHref();
      case FavListUrlBuilder.GOTO_NEXT_PAGE:
      case FavListUrlBuilder.TYPE_SOMEWHERE:
        return helper.getNextHref();
      case FavListUrlBuilder.GOTO_LAST_PAGE:
        return helper.getLastHref();
      case FavListUrlBuilder.GOTO_FIRST_PAGE:
      default:
        return helper.getFirstHref();
    }
  }

  /** 对齐 build()。 */
  build(): string {
    const ub: UrlBuilder = new UrlBuilder(EhUrl.getFavoritesUrl());
    if (FavListUrlBuilder.isValidFavCat(this._favCat)) {
      ub.addQuery('favcat', `${this._favCat}`);
    } else if (this._favCat === FavListUrlBuilder.FAV_CAT_ALL) {
      // 上游此处被注释掉：ub.addQuery("favcat", "all");
    }
    const keyword: string | null = this._keyword;
    if (keyword !== null && keyword.length > 0) {
      ub.addQuery('f_search', FormBodyBuilder.canonicalize(keyword, false));
      ub.addQuery('sn', 'on'); // Name
      ub.addQuery('st', 'on'); // Tags
      ub.addQuery('sf', 'on'); // Note
    }
    if (this._index > 0) {
      ub.addQuery('page', `${this._index}`);
    }
    return ub.build();
  }
}

/** 跨模块契约（同 C-12）：ui-widget 的 `GalleryInfoContentHelper` 实现本接口。 */
export interface FavContentHelperLike {
  getFirstHref(): string;

  getPrevHref(): string;

  getNextHref(): string;

  getLastHref(): string;
}
