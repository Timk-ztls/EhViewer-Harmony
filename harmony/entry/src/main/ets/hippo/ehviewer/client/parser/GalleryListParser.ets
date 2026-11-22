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
import { GalleryTagGroup } from '../data/GalleryTagGroup';
import { EhUtils } from '../EhUtils';
import { ParseException } from '../exception/ParseException';
import { GalleryDetailParser } from './GalleryDetailParser';
import { GalleryDetailUrlParser, DetailUrlResult } from './GalleryDetailUrlParser';
import { ParserUtils } from './ParserUtils';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryListParser.java
 * （inventory S0091，437 行 / 实测 475 行含注释）
 *
 * 列表页解析：分页信息（pages/nextPage/翻页链接/结果总数）+ 每个 `.itg` 子项 → GalleryInfo。
 *
 * 跨模块依赖的处理（Lead 已裁决 D-025）：
 *   1) `com.hippo.util.JsoupUtils`（core-runtime，纯函数）→ **本文件内联 3 个 5 行等价方法**
 *      （getElementByClass / getElementByTag / getElementsByClass）。纯函数内联比定义接口更轻。
 *   2) `GalleryListTagsSyncTask(...).execute()`（download-sync，有副作用）→ `TagSyncHook` 接口注入，
 *      默认实现**打 console.warn 后返回**（D-025：可接受延后；warn 必须可被测试断言到）。
 *   3) `EhDB.containLocalFavorites(gid)`（storage-db）→ `LocalFavoriteHook` 接口注入，
 *      默认返回 false（等价「本地收藏库为空」），并同样打一次 warn。
 *   4) `GalleryDetailParser.parseTagGroups(tbody.children())`（本模块）→
 *      委托 `GalleryDetailParser.parseTagGroupsFromElements` 解析标签组。
 *
 * 上游的容错策略（本身就是行为，测试逐条断言）：
 *   - `parse(body, mode)`：任何 Throwable → **返回空 Result**（吞掉，不抛）
 *   - `parse(doc, body, mode)`：列表区任何 Throwable → **抛 ParseException("Can't parse gallery list", body)**
 *   - 无 `ptt` 且无 `searchnav` → 走 catch 分支：No hits found → pages=0 + 空列表；
 *     无 `ptt` → pages=1；否则 pages=Integer.MAX_VALUE（**上游就是这么写的**）
 *   - `parseGalleryInfo`：`title == null` → 返回 null（该项被跳过，不报错）
 *   - 被删除的画廊：`glname` 里没有 `<a>` → gid/token 保持 0，title 仍取文本（**不跳过**）
 *   - `parse` 的 `mode` 参数上游**未使用**（死参数），保留以对齐签名
 */
/**
 * 跨模块契约 C-13 候选：标签同步钩子（download-sync 实现）。
 * 上游：`new GalleryListTagsSyncTask(result.galleryInfoList).execute()` —— parser 里的副作用。
 * 默认实现按 D-025「可接受延后」：打 warn 后返回；**warn 必须能被测试断言到**。
 */
export interface TagSyncHook {
  syncTags(list: GalleryInfo[]): void;
}

export class NoopTagSyncHook implements TagSyncHook {
  syncTags(list: GalleryInfo[]): void {
    console.warn('[net-parse] TagSyncHook 未注入（D-025）：列表页标签未入库，等 download-sync 接线。' +
      ` 本次跳过 ${list.length} 项。`);
  }
}

/**
 * storage-db 的 `EhDB.containLocalFavorites(gid)` 钩子。
 * 默认 false = 本地收藏库为空（未注入时的真实语义），同样打 warn（只打一次，避免刷屏）。
 */
export interface LocalFavoriteHook {
  containLocalFavorites(gid: number): boolean;
}

export class NoopLocalFavoriteHook implements LocalFavoriteHook {
  private static _warned: boolean = false;

  containLocalFavorites(gid: number): boolean {
    if (!NoopLocalFavoriteHook._warned) {
      NoopLocalFavoriteHook._warned = true;
      console.warn('[net-parse] LocalFavoriteHook 未注入：本地收藏判定恒为 false（收藏分类 slot 可能显示为 -2 而不是 -1）。');
    }
    return false;
  }
}

export class GalleryListParser {
  private static readonly PATTERN_RATING: RegExp = /\d+px/g;
  private static readonly PATTERN_THUMB_SIZE: RegExp = /height:(\d+)px;width:(\d+)px/;
  private static readonly PATTERN_FAVORITE_SLOT: RegExp = /background-color:rgba\((\d+),(\d+),(\d+),/;
  private static readonly PATTERN_PAGES: RegExp = /(\d+) page/;
  private static readonly PATTERN_NEXT_PAGE: RegExp = /page=(\d+)/;
  private static readonly PATTERN_NEXT_EX_PAGE: RegExp = /next=(\d+)/;
  private static readonly PATTERN_RESULT_COUNT_PAGE: RegExp = /Found .* results/;

  /** 收藏分类色表（索引即 slot；上游 FAVORITE_SLOT_RGB 逐项照搬）。 */
  private static readonly FAVORITE_SLOT_RGB: string[][] = [
    ['0', '0', '0'],
    ['240', '0', '0'],
    ['240', '160', '0'],
    ['208', '208', '0'],
    ['0', '128', '0'],
    ['144', '240', '64'],
    ['64', '176', '240'],
    ['0', '0', '240'],
    ['80', '0', '128'],
    ['224', '128', '224']
  ];

  private static _tagSyncHook: TagSyncHook = new NoopTagSyncHook();
  private static _localFavoriteHook: LocalFavoriteHook = new NoopLocalFavoriteHook();

  static setTagSyncHook(hook: TagSyncHook): void {
    GalleryListParser._tagSyncHook = hook;
  }

  static setLocalFavoriteHook(hook: LocalFavoriteHook): void {
    GalleryListParser._localFavoriteHook = hook;
  }

  /** 对齐 parse(String body, int mode)：异常吞掉返回空 Result。 */
  static parse(body: string, mode: number): ListResult {
    try {
      const d: Document = Jsoup.parse(body);
      return GalleryListParser.parseDocument(d, body, mode);
    } catch (e) {
      return new ListResult();
    }
  }

  /** 对齐 parse(Document d, String body, int mode)。 */
  static parseDocument(d: Document, body: string, mode: number): ListResult {
    const result: ListResult = new ListResult();
    try {
      const ptt: Element | null = GalleryListParser.firstByClass(d, 'ptt');
      if (ptt === null) {
        const searchNav: Element | null = GalleryListParser.firstByClass(d, 'searchnav');
        result.pages = -1;
        result.nextPage = -1;
        if (searchNav !== null) {
          let el: Element | null = searchNav.getElementById('uFirst');
          result.firstHref = el !== null ? el.attr('href') : '';
          el = searchNav.getElementById('uprev');
          result.prevHref = el !== null ? el.attr('href') : '';
          el = searchNav.getElementById('unext');
          result.nextHref = el !== null ? el.attr('href') : '';
          el = searchNav.getElementById('ulast');
          result.lastHref = el !== null ? el.attr('href') : '';
        } else {
          // 上游 assert searchNav != null：assert 在 release 下不生效，随后 NPE 会落进 catch
          throw new Error('searchnav is null');
        }

        const searchText: Element | null = GalleryListParser.firstByClass(d, 'searchtext');
        if (searchText !== null) {
          const text: string = searchText.text();
          const m: RegExpMatchArray | null = text.match(GalleryListParser.PATTERN_RESULT_COUNT_PAGE);
          if (m !== null) {
            const findString: string = m[0];
            const resultArr: string[] = findString.split(' ');
            if (resultArr.length > 3) {
              switch (resultArr[1]) {
                case 'thousands':
                  result.resultCount = '1,000+';
                  break;
                case 'about':
                  result.resultCount = resultArr[2] + '+';
                  break;
                default: {
                  let buffer: string = '';
                  for (let i = 1; i < resultArr.length - 1; i++) {
                    buffer += resultArr[i];
                  }
                  result.resultCount = buffer;
                  break;
                }
              }
            } else if (resultArr.length === 3) {
              result.resultCount = resultArr[1];
            } else {
              result.resultCount = '';
            }
          }
        } else {
          result.resultCount = '';
        }
      } else {
        const row: Element | null = ptt.child(0);
        const cell: Element | null = row === null ? null : row.child(0);
        if (cell === null) {
          throw new Error('ptt structure unexpected');
        }
        const es: Elements = cell.children();
        result.pages = Number.parseInt(es.get(es.size() - 2).text().trim(), 10);
        if (Number.isNaN(result.pages)) {
          throw new Error('pages not a number');
        }
        let e: Element | null = es.get(es.size() - 1);
        if (e !== null) {
          e = e.children().first();
          if (e !== null) {
            const href: string = e.attr('href');
            const matcher: RegExpMatchArray | null = href.match(GalleryListParser.PATTERN_NEXT_PAGE);
            if (matcher !== null) {
              result.nextPage = GalleryListParser.parseIntSafely(matcher[1], 0);
            }
          }
        }
      }
    } catch (e) {
      // 上游 catch (Throwable)：先判断未关注标签 / 空结果，再按 ptt 是否存在给 pages
      result.noWatchedTags = body.indexOf('<p>You do not have any watched tags') >= 0;
      if (body.indexOf('No hits found</p>') >= 0) {
        result.pages = 0;
        result.galleryInfoList = [];
        return result;
      } else if (GalleryListParser.firstByClass(d, 'ptt') === null) {
        result.pages = 1;
      } else {
        result.pages = Number.MAX_SAFE_INTEGER; // Integer.MAX_VALUE 的 JS 等价
      }
    }

    try {
      const itg: Element | null = GalleryListParser.firstByClass(d, 'itg');
      if (itg === null) {
        throw new Error('itg is null'); // 上游 assert itg != null，release 下继续会 NPE
      }
      let es: Elements;
      if (itg.tagName().toLowerCase() === 'table') {
        const first: Element | null = itg.child(0);
        es = first === null ? new Elements([]) : first.children();
      } else {
        es = itg.children();
      }
      const list: GalleryInfo[] = [];
      for (let i = 0; i < es.size(); i++) {
        const gi: GalleryInfo | null = GalleryListParser.parseGalleryInfo(es.get(i));
        if (gi !== null) {
          list.push(gi);
        }
      }
      if (list.length === 0) {
        // 上游：取 `itg gltc` 第一个元素的 child(0).child(1).child(0).text()，空串 → ParseException
        const gltc: Elements = GalleryListParser.allByClass(d, 'itg gltc');
        if (gltc.size() === 0) {
          throw new ParseException('No gallery', body);
        }
        const c0: Element | null = gltc.get(0).child(0);
        const c1: Element | null = c0 === null ? null : c0.child(1);
        const c2: Element | null = c1 === null ? null : c1.child(0);
        const pageMessage: string = c2 === null ? '' : c2.text();
        if (pageMessage.length === 0) {
          throw new ParseException('No gallery', body);
        }
      }
      result.galleryInfoList = list;
    } catch (e) {
      // 上游此处是 catch (Throwable)：内层抛出的 ParseException("No gallery") 也会被
      // 包装成 ParseException("Can't parse gallery list") —— 最终消息由外层决定，照搬。
      throw new ParseException(`Can't parse gallery list`, body, e as Error);
    }

    // 副作用：标签同步（download-sync 注入；默认 warn 后返回，见 D-025）
    GalleryListParser._tagSyncHook.syncTags(result.galleryInfoList);

    return result;
  }

  /** 对齐 parseRating(String ratingStyle)：`width:80px;...` → "4" / "4.5" / null。 */
  static parseRating(ratingStyle: string): string | null {
    // 上游用两个连续 find()，故这里用全局正则逐个取
    const nums: number[] = [];
    const re: RegExp = new RegExp(GalleryListParser.PATTERN_RATING.source, 'g');
    let m: RegExpExecArray | null = re.exec(ratingStyle);
    while (m !== null) {
      nums.push(ParserUtils.parseInt(m[0].replace('px', ''), Number.MIN_SAFE_INTEGER));
      m = re.exec(ratingStyle);
    }
    if (nums.length < 2) {
      return null;
    }
    const num1: number = nums[0];
    const num2: number = nums[1];
    if (num1 === Number.MIN_SAFE_INTEGER || num2 === Number.MIN_SAFE_INTEGER) {
      return null;
    }
    let rate: number = 5 - Math.floor(num1 / 16);
    let re2: string;
    if (num2 === 21) {
      rate--;
      re2 = '' + rate + '.5';
    } else {
      re2 = '' + rate;
    }
    return re2;
  }

  /** 对齐 parseFavoriteSlot(String style)：按收藏分类色表反查 slot，未命中 -2。 */
  static parseFavoriteSlot(style: string): number {
    const m: RegExpMatchArray | null = style.match(GalleryListParser.PATTERN_FAVORITE_SLOT);
    if (m !== null) {
      const r: string = m[1];
      const g: string = m[2];
      const b: string = m[3];
      for (let slot = 0; slot < GalleryListParser.FAVORITE_SLOT_RGB.length; slot++) {
        const rgb: string[] = GalleryListParser.FAVORITE_SLOT_RGB[slot];
        if (r === rgb[0] && g === rgb[1] && b === rgb[2]) {
          return slot;
        }
      }
    }
    return -2;
  }

  /** 对齐 parseGalleryInfo(Element e)：单个 `.itg` 子项 → GalleryInfo（title 缺失返回 null）。 */
  static parseGalleryInfo(e: Element): GalleryInfo | null {
    const gi: GalleryInfo = new GalleryInfo();

    // Title, gid, token (required), tags
    const glname: Element | null = GalleryListParser.firstByClass(e, 'glname');
    if (glname !== null) {
      let a: Element | null = GalleryListParser.firstByTag(glname, 'a');
      if (a === null) {
        const parent: Element | null = glname.parent();
        if (parent !== null && parent.tagName().toLowerCase() === 'a') {
          a = parent;
        }
      }
      if (a !== null) {
        const result: DetailUrlResult | null = GalleryDetailUrlParser.parse(a.attr('href'));
        if (result !== null) {
          gi.gid = result.gid;
          gi.token = result.token;
        }
      }

      let child: Element = glname;
      let children: Elements = glname.children();
      while (children.size() !== 0) {
        child = children.get(0);
        children = child.children();
      }
      gi.title = child.text().trim();

      const tbody: Element | null = GalleryListParser.firstByTag(glname, 'tbody');
      if (tbody !== null) {
        const tags: string[] = [];
        const groups: GalleryTagGroup[] = GalleryDetailParser.parseTagGroupsFromElements(tbody.children());
        for (let k = 0; k < groups.length; k++) {
          const group: GalleryTagGroup = groups[k];
          for (let j = 0; j < group.size(); j++) {
            tags.push(group.groupName + ':' + group.getTagAt(j));
          }
        }
        gi.simpleTags = tags;
      }
    }
    if (glname === null) {
      // 上游：gi.title 为 null（默认值）时才 return null —— 只有 glname 缺失会导致它仍为 null。
      // 本层 GalleryInfo.title 默认 ''，故必须显式用 glname 判断，行为等价。
      return null;
    }

    // Category
    gi.category = EhUtils.UNKNOWN;
    let ce: Element | null = GalleryListParser.firstByClass(e, 'cn');
    if (ce === null) {
      ce = GalleryListParser.firstByClass(e, 'cs');
    }
    if (ce !== null) {
      gi.category = EhUtils.getCategoryByType(ce.text());
    }

    // Thumb
    // 注意：上游 `public String thumb` 默认 null；本层 C-7 要求 thumb: string（默认 ''）。
    // 因此「是否已取到缩略图」用局部变量承载，否则 `gi.thumb === null` 恒为 false，
    // gl1e / gl3t 兜底分支永远不会走（这是金样本测出来的真实差异）。
    let thumbValue: string | null = null;
    const glThumb: Element | null = GalleryListParser.firstByClass(e, 'glthumb');
    if (glThumb !== null) {
      const img: Element | null = glThumb.select('div:nth-child(1)>img').first();
      if (img !== null) {
        const m: RegExpMatchArray | null = img.attr('style').match(GalleryListParser.PATTERN_THUMB_SIZE);
        if (m !== null) {
          gi.thumbWidth = GalleryListParser.parseIntSafely(m[2], 0);
          gi.thumbHeight = GalleryListParser.parseIntSafely(m[1], 0);
        } else {
          GalleryListParser.warn("Can't parse gallery info thumb size");
          gi.thumbWidth = 0;
          gi.thumbHeight = 0;
        }
        let url: string | null = img.attr('data-src');
        if (url.length === 0) {
          url = img.attr('src');
        }
        if (url.length === 0) {
          url = null;
        }
        thumbValue = EhUtils.handleThumbUrlResolution(url);
      }

      const div: Element | null = glThumb.select('div:nth-child(2)>div:nth-child(2)>div:nth-child(2)').first();
      if (div !== null) {
        const matcher: RegExpMatchArray | null = div.text().match(GalleryListParser.PATTERN_PAGES);
        if (matcher !== null) {
          gi.pages = GalleryListParser.parseIntSafely(matcher[1], 0);
        }
      }
    }
    // 扩展版 / 缩略图版兜底
    if (thumbValue === null) {
      let gl: Element | null = GalleryListParser.firstByClass(e, 'gl1e');
      if (gl === null) {
        gl = GalleryListParser.firstByClass(e, 'gl3t');
      }
      if (gl !== null) {
        const img: Element | null = GalleryListParser.firstByTag(gl, 'img');
        if (img !== null) {
          const m: RegExpMatchArray | null = img.attr('style').match(GalleryListParser.PATTERN_THUMB_SIZE);
          if (m !== null) {
            gi.thumbWidth = GalleryListParser.parseIntSafely(m[2], 0);
            gi.thumbHeight = GalleryListParser.parseIntSafely(m[1], 0);
          } else {
            GalleryListParser.warn("Can't parse gallery info thumb size");
            gi.thumbWidth = 0;
            gi.thumbHeight = 0;
          }
          thumbValue = EhUtils.handleThumbUrlResolution(img.attr('src'));
        }
      }
    }

    // Posted
    gi.favoriteSlot = -2;
    const posted: Element | null = e.getElementById('posted_' + gi.gid);
    if (posted !== null) {
      gi.posted = posted.text().trim();
      gi.favoriteSlot = GalleryListParser.parseFavoriteSlot(posted.attr('style'));
    }
    if (gi.favoriteSlot === -2) {
      gi.favoriteSlot = GalleryListParser._localFavoriteHook.containLocalFavorites(gi.gid) ? -1 : -2;
    }

    GalleryListParser.parserTag(gi, e);

    // Rating
    const ir: Element | null = GalleryListParser.firstByClass(e, 'ir');
    if (ir !== null) {
      const ratingText: string | null = GalleryListParser.parseRating(ir.attr('style'));
      gi.rating = ParserUtils.parseFloat(ratingText, -1.0);
      gi.rated = ir.hasClass('irr') || ir.hasClass('irg') || ir.hasClass('irb');
    }

    // Uploader and pages
    let gl: Element | null = GalleryListParser.firstByClass(e, 'glhide');
    let uploaderIndex: number = 0;
    let pagesIndex: number = 1;
    if (gl === null) {
      gl = GalleryListParser.firstByClass(e, 'gl3e');
      uploaderIndex = 3;
      pagesIndex = 4;
    }
    if (gl !== null) {
      const children: Elements = gl.children();
      if (children.size() > uploaderIndex) {
        const a: Element | null = children.get(uploaderIndex).children().first();
        if (a !== null) {
          gi.uploader = a.text().trim();
        }
      }
      if (children.size() > pagesIndex) {
        const matcher: RegExpMatchArray | null =
          children.get(pagesIndex).text().match(GalleryListParser.PATTERN_PAGES);
        if (matcher !== null) {
          gi.pages = GalleryListParser.parseIntSafely(matcher[1], 0);
        }
      }
    }
    // 缩略图版
    const gl5t: Element | null = GalleryListParser.firstByClass(e, 'gl5t');
    if (gl5t !== null) {
      const div: Element | null = gl5t.select('div:nth-child(2)>div:nth-child(2)').first();
      if (div !== null) {
        const matcher: RegExpMatchArray | null = div.text().match(GalleryListParser.PATTERN_PAGES);
        if (matcher !== null) {
          gi.pages = GalleryListParser.parseIntSafely(matcher[1], 0);
        }
      }
    }

    gi.thumb = thumbValue === null ? '' : thumbValue;

    gi.generateSLang();
    // C-7 派生字段：parser 产出后必须刷新 postedAt（上游无此字段，是本层为排序新增的）
    gi.refreshPostedAt();

    return gi;
  }

  /** 对齐 parserTag(GalleryInfo, Element)：`gt` 与 `gtl` 的 title 属性合并进 tgList。 */
  private static parserTag(gi: GalleryInfo, e: Element): void {
    const gts: Elements = GalleryListParser.allByClass(e, 'gt');
    if (gts.size() > 0) {
      gi.tgList = gts.eachAttr('title');
    }
    const gtl: Elements = GalleryListParser.allByClass(e, 'gtl');
    if (gtl.size() > 0) {
      if (gi.tgList === null) {
        gi.tgList = [];
      }
      const more: string[] = gtl.eachAttr('title');
      for (let i = 0; i < more.length; i++) {
        gi.tgList.push(more[i]);
      }
    }
  }

  // ---- JsoupUtils 的 3 个纯函数等价（core-runtime 落地后可换引用）----

  private static firstByClass(root: Element, className: string): Element | null {
    const es: Elements = root.getElementsByClass(className);
    return es.size() === 0 ? null : es.get(0);
  }

  private static allByClass(root: Element, className: string): Elements {
    return root.getElementsByClass(className);
  }

  private static firstByTag(root: Element, tagName: string): Element | null {
    const es: Elements = root.getElementsByTag(tagName);
    // 注意：上游 JsoupUtils.getElementByTag 只找**后代**，且 jsoup 的 getElementsByTag 包含自身；
    // 这里对齐 jsoup 语义（包含自身），因为 glname 自身通常不是 tbody/img/a
    return es.size() === 0 ? null : es.get(0);
  }

  private static parseIntSafely(s: string, def: number): number {
    const v: number = Number.parseInt(s, 10);
    return Number.isNaN(v) ? def : v;
  }

  private static warn(msg: string): void {
    console.warn('[GalleryListParser] ' + msg);
  }
}

/** 对齐 GalleryListParser.Result（静态嵌套类 → 文件级）。 */
export class ListResult {
  pages: number = 0;
  nextPage: number = 0;
  resultCount: string = '';
  firstHref: string = '';
  prevHref: string = '';
  nextHref: string = '';
  lastHref: string = '';
  customErrorString: string = '';
  noWatchedTags: boolean = false;
  galleryInfoList: GalleryInfo[] = [];
}

