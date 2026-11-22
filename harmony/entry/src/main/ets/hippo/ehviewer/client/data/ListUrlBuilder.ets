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
import { AdvanceSearchFlags, CategoryFlags } from './Flags';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/ListUrlBuilder.java
 * （inventory S0055，659 行 / 实测 726 行含注释）
 *
 * 列表页 URL 拼装核心：7 种 mode × 分类位 × 关键词 × 高级搜索位 × 翻页。
 * 上游 `GalleryListParser` 的输入就是本类的 `build()` 结果，故必须先于 parser 落地。
 *
 * ArkTS 映射：
 *   @IntDef @interface Mode           → 普通 int 常量（MODE_*），不做编译期校验（ArkTS 无注解处理器）
 *   java.net.URLEncoder.encode(s,"UTF-8") → FormBodyBuilder.canonicalize(s, false)
 *       （Java URLEncoder 的语义：空格→'+'，保留 A-Za-z0-9-._*，其余 %XX 大写；
 *         okhttp 的 FormBody 编码规则与之逐字节一致，直接复用，避免两套实现漂移）
 *   URLDecoder.decode(v,"utf-8")       → decodeComponent（'+'→' '，再 decodeURIComponent，失败原样）
 *   TextUtils.isEmpty                 → 长度判断
 *   Objects.requireNonNull            → 直接使用（group(0) 必存在）
 *   clone()                           → cloneBuilder()（ArkTS 无 Object.clone 协议）
 *   set(ListUrlBuilder)               → copyFrom(lub)
 *   set(QuickSearch) / toQuickSearch() / equalsQuickSearch(QuickSearch)
 *                                     → 用 QuickSearchLike 接口接住（storage-db 的 QuickSearch 实现它，见 C-11）
 *   build(int pageAction, GalleryInfoContentHelper helper)
 *                                     → buildForPageAction(pageAction, helper)（helper 用 ContentHelperLike 接口）
 *   DEFAULT_ADVANCE / DEFAULT_MIN_RATING → AdvanceSearchFlags.DEFAULT_ADVANCE / DEFAULT_MIN_RATING
 *   AdvanceSearchTable.S*             → AdvanceSearchFlags.S*（位值与 ui-widget 对齐，check-flags.ps1 校验）
 *   EhUtils.NONE                      → CategoryFlags.NONE
 *
 * 上游的怪异之处（逐字保留）：
 *   - MODE_FILTER 的 URL 是 `<host>?f_search=<kw>`（先写 '?' 再拼 page/ f_search）
 *   - MODE_TOP_LIST 在 pageIndex ∉ [1,200) 时**返回 "127.0.0.1:8888"**（上游的兜底哨兵值）
 *   - MODE_UPLOADER/MODE_TAG 的页码是**路径段**而不是 query
 *   - `f_cats` 存的是**取反后的掩码**：`(~category) & ALL_CATEGORY`
 */
export class ListUrlBuilder {
  static readonly MODE_NORMAL: number = 0x0;
  static readonly MODE_UPLOADER: number = 0x1;
  static readonly MODE_TAG: number = 0x2;
  static readonly MODE_WHATS_HOT: number = 0x3;
  static readonly MODE_IMAGE_SEARCH: number = 0x4;
  static readonly MODE_SUBSCRIPTION: number = 0x5;
  static readonly MODE_FILTER: number = 0x6;
  static readonly MODE_TOP_LIST: number = 0x7;

  /** 对齐 ContentLayout.ContentHelper 的翻页动作常量（ui-widget）。 */
  static readonly GOTO_FIRST_PAGE: number = 0;
  static readonly GOTO_PREV_PAGE: number = 1;
  static readonly GOTO_NEXT_PAGE: number = 2;
  static readonly GOTO_LAST_PAGE: number = 3;
  static readonly TYPE_SOMEWHERE: number = 5;

  private static readonly PATTERN_SEEK_DATE: RegExp = /seek=(\d+)-(\d+)-(\d+)/;
  private static readonly PATTERN_JUMP_NODE: RegExp = /jump=(\d)[ymwd]/;

  private _mode: number = ListUrlBuilder.MODE_NORMAL;
  private _pageIndex: number = 0;
  private _category: number = CategoryFlags.NONE;
  private _keyword: string | null = null;
  private _follow: string | null = null;
  private _advanceSearch: number = -1;
  private _minRating: number = -1;
  private _pageFrom: number = -1;
  private _pageTo: number = -1;
  private _imagePath: string | null = null;
  private _useSimilarityScan: boolean = false;
  private _onlySearchCovers: boolean = false;
  private _showExpunged: boolean = false;

  constructor() {
  }

  /** 对齐 reset()：回到首页状态。 */
  reset(): void {
    this._mode = ListUrlBuilder.MODE_NORMAL;
    this._pageIndex = 0;
    this._category = CategoryFlags.NONE;
    this._keyword = null;
    this._advanceSearch = -1;
    this._minRating = -1;
    this._pageFrom = -1;
    this._pageTo = -1;
    this._imagePath = null;
    this._useSimilarityScan = false;
    this._onlySearchCovers = false;
    this._showExpunged = false;
  }

  /** 对齐 clone()：ArkTS 无 Object.clone 协议，命名 cloneBuilder。 */
  cloneBuilder(): ListUrlBuilder {
    const b: ListUrlBuilder = new ListUrlBuilder();
    b.copyFrom(this);
    return b;
  }

  getMode(): number {
    return this._mode;
  }

  setMode(mode: number): void {
    this._mode = mode;
  }

  getPageIndex(): number {
    return this._pageIndex;
  }

  setPageIndex(pageIndex: number): void {
    this._pageIndex = pageIndex;
  }

  getCategory(): number {
    return this._category;
  }

  setCategory(category: number): void {
    this._category = category;
  }

  getKeyword(): string | null {
    return this._keyword;
  }

  setKeyword(keyword: string | null): void {
    this._keyword = keyword;
  }

  setFollow(follow: string | null): void {
    this._follow = follow;
  }

  getAdvanceSearch(): number {
    return this._advanceSearch;
  }

  setAdvanceSearch(advanceSearch: number): void {
    this._advanceSearch = advanceSearch;
  }

  getMinRating(): number {
    return this._minRating;
  }

  setMinRating(minRating: number): void {
    this._minRating = minRating;
  }

  getPageFrom(): number {
    return this._pageFrom;
  }

  setPageFrom(pageFrom: number): void {
    this._pageFrom = pageFrom;
  }

  getPageTo(): number {
    return this._pageTo;
  }

  setPageTo(pageTo: number): void {
    this._pageTo = pageTo;
  }

  getImagePath(): string | null {
    return this._imagePath;
  }

  setImagePath(imagePath: string | null): void {
    this._imagePath = imagePath;
  }

  isUseSimilarityScan(): boolean {
    return this._useSimilarityScan;
  }

  setUseSimilarityScan(useSimilarityScan: boolean): void {
    this._useSimilarityScan = useSimilarityScan;
  }

  isOnlySearchCovers(): boolean {
    return this._onlySearchCovers;
  }

  setOnlySearchCovers(onlySearchCovers: boolean): void {
    this._onlySearchCovers = onlySearchCovers;
  }

  isShowExpunged(): boolean {
    return this._showExpunged;
  }

  setShowExpunged(showExpunged: boolean): void {
    this._showExpunged = showExpunged;
  }

  /** 对齐 set(ListUrlBuilder)：字段逐个复制（上游「Make them the same」）。 */
  copyFrom(lub: ListUrlBuilder): void {
    this._mode = lub._mode;
    this._pageIndex = lub._pageIndex;
    this._category = lub._category;
    this._keyword = lub._keyword;
    this._follow = lub._follow;
    this._advanceSearch = lub._advanceSearch;
    this._minRating = lub._minRating;
    this._pageFrom = lub._pageFrom;
    this._pageTo = lub._pageTo;
    this._imagePath = lub._imagePath;
    this._useSimilarityScan = lub._useSimilarityScan;
    this._onlySearchCovers = lub._onlySearchCovers;
    this._showExpunged = lub._showExpunged;
  }

  /** 对齐 set(QuickSearch q)：注意不复制 pageIndex，且把 4 个图片搜索字段清零。 */
  copyFromQuickSearch(q: QuickSearchLike): void {
    this._mode = q.getMode();
    this._category = q.getCategory();
    this._keyword = q.getKeyword();
    this._advanceSearch = q.getAdvanceSearch();
    this._minRating = q.getMinRating();
    this._pageFrom = q.getPageFrom();
    this._pageTo = q.getPageTo();
    this._imagePath = null;
    this._useSimilarityScan = false;
    this._onlySearchCovers = false;
    this._showExpunged = false;
  }

  /** 对齐 set(String q, int mode)。 */
  setKeywordWithMode(q: string | null, mode: number): void {
    this._mode = mode;
    this._category = -1;
    this._keyword = q;
    this._advanceSearch = -1;
    this._minRating = -1;
    this._pageFrom = -1;
    this._pageTo = -1;
    this._imagePath = null;
    this._useSimilarityScan = false;
    this._onlySearchCovers = false;
    this._showExpunged = false;
  }

  /** 对齐 set(String q)：等价 set(q, MODE_TAG)。 */
  setKeywordAsTag(q: string | null): void {
    this.setKeywordWithMode(q, ListUrlBuilder.MODE_TAG);
  }

  /** 对齐 toQuickSearch()。 */
  toQuickSearch(target: QuickSearchLike): void {
    target.setMode(this._mode);
    target.setCategory(this._category);
    target.setKeyword(this._keyword);
    target.setAdvanceSearch(this._advanceSearch);
    target.setMinRating(this._minRating);
    target.setPageFrom(this._pageFrom);
    target.setPageTo(this._pageTo);
  }

  /** 对齐 equalsQuickSearch(QuickSearch q)。 */
  equalsQuickSearch(q: QuickSearchLike | null): boolean {
    if (q === null) {
      return false;
    }
    if (q.getMode() !== this._mode) {
      return false;
    }
    if (q.getCategory() !== this._category) {
      return false;
    }
    const qk: string | null = q.getKeyword();
    if (qk !== this._keyword && !(qk !== null && this._keyword !== null && qk === this._keyword)) {
      return false;
    }
    if (q.getAdvanceSearch() !== this._advanceSearch) {
      return false;
    }
    if (q.getMinRating() !== this._minRating) {
      return false;
    }
    if (q.getPageFrom() !== this._pageFrom) {
      return false;
    }
    if (q.getPageTo() !== this._pageTo) {
      return false;
    }
    return true;
  }

  /** 对齐 equalKeyWord(String keyword)。 */
  equalKeyWord(keyword: string): boolean {
    if (this._keyword === null) {
      return false;
    }
    return this._keyword === keyword;
  }

  /**
   * 对齐 setQuery(String query)：解析 `k=v&k2=v2` 反填 builder 状态。
   * 逐键处理，语义与上游 switch 一一对应（含 f_cats 取反、advsearch 开关联动）。
   */
  setQuery(query: string | null): void {
    this.reset();
    if (query === null || query === undefined || query.length === 0) {
      return;
    }
    const querys: string[] = query.split('&');
    let category: number = 0;
    let keyword: string | null = null;
    let enableAdvanceSearch: boolean = false;
    let advanceSearch: number = 0;
    let enableMinRating: boolean = false;
    let minRating: number = -1;
    let enablePage: boolean = false;
    let pageFrom: number = -1;
    let pageTo: number = -1;

    for (let i = 0; i < querys.length; i++) {
      const str: string = querys[i];
      const index: number = str.indexOf('=');
      if (index < 0) {
        continue;
      }
      const key: string = str.substring(0, index);
      const value: string = str.substring(index + 1);
      switch (key) {
        case 'f_cats': {
          const cats: number = ListUrlBuilder.parseIntSafely(value, CategoryFlags.ALL_CATEGORY);
          category |= (~cats) & CategoryFlags.ALL_CATEGORY;
          break;
        }
        case 'f_doujinshi':
          if (value === '1') {
            category |= CategoryFlags.DOUJINSHI;
          }
          break;
        case 'f_manga':
          if (value === '1') {
            category |= CategoryFlags.MANGA;
          }
          break;
        case 'f_artistcg':
          if (value === '1') {
            category |= CategoryFlags.ARTIST_CG;
          }
          break;
        case 'f_gamecg':
          if (value === '1') {
            category |= CategoryFlags.GAME_CG;
          }
          break;
        case 'f_western':
          if (value === '1') {
            category |= CategoryFlags.WESTERN;
          }
          break;
        case 'f_non-h':
          if (value === '1') {
            category |= CategoryFlags.NON_H;
          }
          break;
        case 'f_imageset':
          if (value === '1') {
            category |= CategoryFlags.IMAGE_SET;
          }
          break;
        case 'f_cosplay':
          if (value === '1') {
            category |= CategoryFlags.COSPLAY;
          }
          break;
        case 'f_asianporn':
          if (value === '1') {
            category |= CategoryFlags.ASIAN_PORN;
          }
          break;
        case 'f_misc':
          if (value === '1') {
            category |= CategoryFlags.MISC;
          }
          break;
        case 'f_search':
          keyword = ListUrlBuilder.decodeComponent(value);
          break;
        case 'advsearch':
          if (value === '1') {
            enableAdvanceSearch = true;
          }
          break;
        case 'f_sname':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SNAME;
          }
          break;
        case 'f_stags':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.STAGS;
          }
          break;
        case 'f_sdesc':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SDESC;
          }
          break;
        case 'f_storr':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.STORR;
          }
          break;
        case 'f_sto':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.STO;
          }
          break;
        case 'f_sdt1':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SDT1;
          }
          break;
        case 'f_sdt2':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SDT2;
          }
          break;
        case 'f_sh':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SH;
          }
          break;
        case 'f_sfl':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SFL;
          }
          break;
        case 'f_sfu':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SFU;
          }
          break;
        case 'f_sft':
          if (value === 'on') {
            advanceSearch |= AdvanceSearchFlags.SFT;
          }
          break;
        case 'f_sr':
          if (value === 'on') {
            enableMinRating = true;
          }
          break;
        case 'f_srdd':
          minRating = ListUrlBuilder.parseIntSafely(value, -1);
          break;
        case 'f_sp':
          if (value === 'on') {
            enablePage = true;
          }
          break;
        case 'f_spf':
          pageFrom = ListUrlBuilder.parseIntSafely(value, -1);
          break;
        case 'f_spt':
          pageTo = ListUrlBuilder.parseIntSafely(value, -1);
          break;
        default:
          break;
      }
    }

    this._category = category;
    this._keyword = keyword;
    if (enableAdvanceSearch) {
      this._advanceSearch = advanceSearch;
      this._minRating = enableMinRating ? minRating : -1;
      if (enablePage) {
        this._pageFrom = pageFrom;
        this._pageTo = pageTo;
      } else {
        this._pageFrom = -1;
        this._pageTo = -1;
      }
    } else {
      this._advanceSearch = -1;
    }
  }

  /** 对齐 build(int pageAction, GalleryInfoContentHelper helper)：取 helper 里已解析好的翻页链接。 */
  buildForPageAction(pageAction: number, helper: ContentHelperLike): string {
    switch (pageAction) {
      case ListUrlBuilder.GOTO_PREV_PAGE:
        return helper.getPrevHref();
      case ListUrlBuilder.GOTO_NEXT_PAGE:
      case ListUrlBuilder.TYPE_SOMEWHERE:
        return helper.getNextHref();
      case ListUrlBuilder.GOTO_LAST_PAGE:
        return helper.getLastHref();
      case ListUrlBuilder.GOTO_FIRST_PAGE:
      default:
        return helper.getFirstHref();
    }
  }

  /**
   * 对齐 jumpHrefBuild(String urlOld, String appendParam)：
   * 已有 `seek=YYYY-MM-DD` 或 `jump=N[y|m|w|d]` 就原地替换，否则追加 `&param`。
   */
  jumpHrefBuild(urlOld: string, appendParam: string): string {
    const seek: RegExpMatchArray | null = urlOld.match(ListUrlBuilder.PATTERN_SEEK_DATE);
    if (seek !== null) {
      return urlOld.replace(seek[0], appendParam);
    }
    const jump: RegExpMatchArray | null = urlOld.match(ListUrlBuilder.PATTERN_JUMP_NODE);
    if (jump !== null) {
      return urlOld.replace(jump[0], appendParam);
    }
    return urlOld + '&' + appendParam;
  }

  /** 对齐 build()：7 种 mode 的 URL 拼装（逐分支照搬，含上游怪异行为）。 */
  build(): string {
    switch (this._mode) {
      case ListUrlBuilder.MODE_UPLOADER: {
        let sb: string = EhUrl.getHost() + 'uploader/';
        sb += ListUrlBuilder.encodeComponent(this._keyword);
        if (this._pageIndex !== 0) {
          sb += '/' + this._pageIndex;
        }
        return sb;
      }
      case ListUrlBuilder.MODE_TAG: {
        let sb: string = EhUrl.getHost() + 'tag/';
        sb += ListUrlBuilder.encodeComponent(this._keyword);
        if (this._pageIndex !== 0) {
          sb += '/' + this._pageIndex;
        }
        return sb;
      }
      case ListUrlBuilder.MODE_FILTER: {
        let sb: string = EhUrl.getHost() + '?';
        if (this._pageIndex !== 0) {
          sb += 'page=' + this._pageIndex + '&';
        }
        sb += 'f_search=';
        sb += ListUrlBuilder.encodeComponent(this._keyword);
        return sb;
      }
      case ListUrlBuilder.MODE_WHATS_HOT:
        return EhUrl.getPopularUrl();
      case ListUrlBuilder.MODE_IMAGE_SEARCH:
        return EhUrl.getImageSearchUrl();
      case ListUrlBuilder.MODE_TOP_LIST: {
        let sb: string = EhUrl.getTopListUrl() + '?';
        sb += this._follow === null ? '' : (this._follow as string);
        if (this._pageIndex === 0) {
          return sb;
        }
        if (this._pageIndex > 0 && this._pageIndex < 200) {
          sb += '&p=' + this._pageIndex;
        } else {
          // 上游哨兵值（用来触发「非法页」分支，逐字保留）
          return '127.0.0.1:8888';
        }
        return sb;
      }
      case ListUrlBuilder.MODE_SUBSCRIPTION: {
        const url: string = EhUrl.getWatchedUrl();
        const ub: UrlBuilder = new UrlBuilder(url);
        this.applyCommonQueries(ub);
        return ub.build();
      }
      case ListUrlBuilder.MODE_NORMAL:
      default: {
        const ub: UrlBuilder = new UrlBuilder(EhUrl.getHost());
        this.applyCommonQueries(ub);
        return ub.build();
      }
    }
  }

  /** MODE_NORMAL 与 MODE_SUBSCRIPTION 共用的 query 拼装（上游同一段代码）。 */
  private applyCommonQueries(ub: UrlBuilder): void {
    if (this._category !== CategoryFlags.NONE) {
      ub.addQuery('f_cats', (~this._category) & CategoryFlags.ALL_CATEGORY);
    }
    if (this._keyword !== null) {
      const keyword: string = (this._keyword as string).trim();
      if (keyword.length > 0) {
        ub.addQuery('f_search', ListUrlBuilder.encodeComponent(this._keyword));
      }
    }
    if (this._pageIndex !== 0) {
      ub.addQuery('page', this._pageIndex);
    }
    if (this._advanceSearch !== -1) {
      ub.addQuery('advsearch', '1');
      if ((this._advanceSearch & AdvanceSearchFlags.SNAME) !== 0) {
        ub.addQuery('f_sname', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.STAGS) !== 0) {
        ub.addQuery('f_stags', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.SDESC) !== 0) {
        ub.addQuery('f_sdesc', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.STORR) !== 0) {
        ub.addQuery('f_storr', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.STO) !== 0) {
        ub.addQuery('f_sto', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.SDT1) !== 0) {
        ub.addQuery('f_sdt1', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.SDT2) !== 0) {
        ub.addQuery('f_sdt2', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.SH) !== 0) {
        ub.addQuery('f_sh', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.SFL) !== 0) {
        ub.addQuery('f_sfl', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.SFU) !== 0) {
        ub.addQuery('f_sfu', 'on');
      }
      if ((this._advanceSearch & AdvanceSearchFlags.SFT) !== 0) {
        ub.addQuery('f_sft', 'on');
      }
      if (this._minRating !== -1) {
        ub.addQuery('f_sr', 'on');
        ub.addQuery('f_srdd', this._minRating);
      }
      if (this._pageFrom !== -1 || this._pageTo !== -1) {
        ub.addQuery('f_sp', 'on');
        ub.addQuery('f_spf', this._pageFrom !== -1 ? `${this._pageFrom}` : '');
        ub.addQuery('f_spt', this._pageTo !== -1 ? `${this._pageTo}` : '');
      }
    }
  }

  /** Java URLEncoder.encode(s, "UTF-8") 的等价（空格→'+'，其余 %XX 大写）。 */
  private static encodeComponent(s: string | null): string {
    if (s === null || s === undefined) {
      return '';
    }
    return FormBodyBuilder.canonicalize(s, false);
  }

  /** Java URLDecoder.decode(s, "utf-8") 的等价（'+'→' '，非法转义原样保留）。 */
  private static decodeComponent(s: string): string {
    const plus: string = s.split('+').join(' ');
    try {
      return decodeURIComponent(plus);
    } catch (e) {
      return plus;
    }
  }

  private static parseIntSafely(s: string, def: number): number {
    const v: number = Number.parseInt(s, 10);
    return Number.isNaN(v) ? def : v;
  }

  /** 对齐上游 GalleryListScene.wrapTagKeyword：为含空格的 `ns:tag` 自动加引号与精准后缀 `$`。 */
  static wrapTagKeyword(keyword: string): string {
    const trimmed: string = keyword.trim();
    const index1: number = trimmed.indexOf(':');
    if (index1 === -1 || index1 >= trimmed.length - 1) {
      return trimmed;
    }
    if (trimmed.charAt(index1 + 1) === '"') {
      return trimmed;
    }
    const index2: number = trimmed.indexOf(' ');
    if (index2 <= index1) {
      return trimmed;
    }
    return `${trimmed.substring(0, index1 + 1)}"${trimmed.substring(index1 + 1)}$"`;
  }

  /** 从 LIST_URL_BUILDER 产出的 URL 反解显示在 SearchBar 中的搜索关键词。 */
  static extractSearchKeywordFromUrl(url: string): string {
    if (url.length === 0) {
      return '';
    }
    const tagMatch: RegExpMatchArray | null = url.match(/\/tag\/([^/?#]+)(?:\/\d+)?(?:[?#].*)?$/);
    if (tagMatch !== null && tagMatch[1] !== undefined) {
      return ListUrlBuilder.wrapTagKeyword(ListUrlBuilder.decodeComponent(tagMatch[1]));
    }
    const uploaderMatch: RegExpMatchArray | null = url.match(/\/uploader\/([^/?#]+)(?:\/\d+)?(?:[?#].*)?$/);
    if (uploaderMatch !== null && uploaderMatch[1] !== undefined) {
      const up: string = ListUrlBuilder.decodeComponent(uploaderMatch[1]).trim();
      if (up.length === 0) {
        return '';
      }
      return up.indexOf(' ') >= 0 ? `uploader:"${up}"` : `uploader:${up}`;
    }
    const queryMatch: RegExpMatchArray | null = url.match(/[?&]f_search=([^&#]*)/);
    if (queryMatch !== null && queryMatch[1] !== undefined) {
      return ListUrlBuilder.decodeComponent(queryMatch[1]).trim();
    }
    return '';
  }
}

/**
 * 跨模块契约 C-11 候选：`QuickSearch`（storage-db 的 dao 实体）实现本接口即可与本类互转。
 * 上游 7 个字段：mode / category / keyword / advanceSearch / minRating / pageFrom / pageTo。
 */
export interface QuickSearchLike {
  getMode(): number;

  getCategory(): number;

  getKeyword(): string | null;

  getAdvanceSearch(): number;

  getMinRating(): number;

  getPageFrom(): number;

  getPageTo(): number;

  setMode(mode: number): void;

  setCategory(category: number): void;

  setKeyword(keyword: string | null): void;

  setAdvanceSearch(advanceSearch: number): void;

  setMinRating(minRating: number): void;

  setPageFrom(pageFrom: number): void;

  setPageTo(pageTo: number): void;
}

/** 跨模块契约 C-12 候选：ui-widget 的 `GalleryInfoContentHelper` 实现本接口。 */
export interface ContentHelperLike {
  getFirstHref(): string;

  getPrevHref(): string;

  getNextHref(): string;

  getLastHref(): string;
}
