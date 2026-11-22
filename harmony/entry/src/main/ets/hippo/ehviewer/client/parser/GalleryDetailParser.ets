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
import { GalleryComment } from '../data/GalleryComment';
import { GalleryCommentList } from '../data/GalleryCommentList';
import { GalleryDetail } from '../data/GalleryDetail';
import { GalleryTagGroup } from '../data/GalleryTagGroup';
import { LargePreviewSet } from '../data/LargePreviewSet';
import { NewVersion } from '../data/NewVersion';
import { NormalPreviewSet } from '../data/NormalPreviewSet';
import { PreviewSet } from '../data/PreviewSet';
import { EhUrl } from '../EhUrl';
import { EhUtils } from '../EhUtils';
import { EhException } from '../exception/EhException';
import { ParseException } from '../exception/ParseException';
import {
  GalleryUnavailableException,
  OffensiveException,
  PiningException
} from '../exception/MarkerExceptions';
import { ParserUtils } from './ParserUtils';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryDetailParser.java
 * （inventory S0100，720 行 / 实测 798 行含注释）
 *
 * 详情页解析：gid/token/apiUid/apiKey、种子/归档链接、封面、标题、分类、上传者、
 * 一组 `#gdd` 的 key-value 信息（posted/parent/visible/language/size/pages/favoriteCount）、
 * 评分与评分人数、收藏状态、新版本列表、标签组、评论、预览图（normal/large 两套正则）。
 *
 * **同时提供正则版与 DOM 版两套解析**（上游就是这样，正则版用于 SpiderInfo 的快速路径）：
 *   parseTagGroups(Document) / parseTagGroups(Elements) / parseTagGroups(String)
 *   parseComments(Document) / parseComments(String)
 *   parsePreviewPages(Document, body) / parsePreviewPages(body)
 *   parsePreviewSet(Document, body) / parsePreviewSet(body)
 *
 * C-7 补充条款（判空）在本文件的处理：
 *   - `gd.title/gd.thumb/...` 本层是 `string` 默认 ''，故「是否取到」一律用**局部可空变量**承载，
 *     禁止用 C-7 字段判空（Lead 的 C-7 补充第 1/2 条）。
 *   - `gd.posted` 解析完成后调用 `refreshPostedAt()`（第 3 条）。
 *
 * 跨模块依赖：
 *   - `EhDB.inBlackList(user)`（storage-db）→ `BlackListHook` 注入，默认 false（打一次 warn）
 *   - `Settings.getFixThumbUrl()`（core-runtime）→ `GalleryDetailParserConfig` 注入，默认值与上游一致
 *   - `JsoupUtils`（core-runtime，纯函数）→ 内联等价私有方法
 *
 * 上游怪异行为逐条保留：
 *   - `parsePreviewSet` 的内层失败被**吞成** `new NormalPreviewSet()`（空集合），不向上抛
 *   - `parseComment` 里 `c8` 分支的 `lastEdited` 用的是 `temp`（评论发布时间）而不是 c8 自己的文本 —— 上游 bug，照搬
 *   - `parseTagGroups(String)` 的正则只认 `<tr><td>name:</td><td><div><a>tag</a></div>...</td></tr>`
 *   - 评论时间用 `dd MMMMM yyyy, HH:mm` + **UTC** 时区
 */
/** core-runtime 的 `Settings.getFixThumbUrl()` 注入点（默认 false，与上游 `Settings.DEFAULT_FIX_THUMB_URL = false` 一致）。 */
export class GalleryDetailParserConfig {
  getFixThumbUrl(): boolean {
    return false;
  }
}

/**
 * storage-db 的 `EhDB.inBlackList(user)` 钩子（C-14 候选）。
 * 默认 false + 打一次 warn：未注入时表现为「黑名单为空」，不会误删评论。
 */
export interface BlackListHook {
  inBlackList(user: string): boolean;
}

export class NoopBlackListHook implements BlackListHook {
  private static _warned: boolean = false;

  inBlackList(user: string): boolean {
    if (!NoopBlackListHook._warned) {
      NoopBlackListHook._warned = true;
      console.warn('[net-parse] BlackListHook 未注入（C-14）：本地评论黑名单恒为空，被拉黑用户的评论仍会显示。');
    }
    return false;
  }
}

export class GalleryDetailParser {
  // 注意：JS 没有 Pattern.DOTALL 常量，用 [\s\S] 代替 `.`
  private static readonly PATTERN_ERROR: RegExp = /<div class="d">\n<p>([^<]+)<\/p>/;
  private static readonly PATTERN_DETAIL: RegExp =
    /var gid = (\d+);[\s\S]+?var token = "([a-f0-9]+)";[\s\S]+?var apiuid = ([\-\d]+);[\s\S]+?var apikey = "([a-f0-9]+)";/;
  private static readonly PATTERN_TORRENT: RegExp =
    /<a[^<>]*onclick="return popUp\('([^']+)'[^)]+\)">Torrent Download \((\d+)\)<\/a>/;
  private static readonly PATTERN_ARCHIVE: RegExp =
    /<a[^<>]*onclick="return popUp\('([^']+)'[^)]+\)">Archive Download<\/a>/;
  private static readonly PATTERN_COVER: RegExp = /width:(\d+)px; height:(\d+)px[\s\S]+?url\(([\s\S]+?)\)/;
  private static readonly PATTERN_TAG_GROUP: RegExp =
    /<tr><td[^<>]+>([\w\s]+):<\/td><td>(?:<div[^<>]+><a[^<>]+>[\w\s]+<\/a><\/div>)+<\/td><\/tr>/g;
  private static readonly PATTERN_TAG: RegExp = /<div[^<>]+><a[^<>]+>([\w\s]+)<\/a><\/div>/g;
  private static readonly PATTERN_COMMENT: RegExp =
    /<div class="c3">Posted on ([^<>]+) by: &nbsp; <a[^<>]+>([^<>]+)<\/a>[\s\S]+?<div class="c6"[^>]*>([\s\S]+?)<\/div><div class="c[78]"/g;
  private static readonly PATTERN_PAGES: RegExp =
    /<tr><td[^<>]*>Length:<\/td><td[^<>]*>([\d,]+) pages<\/td><\/tr>/;
  private static readonly PATTERN_PREVIEW_PAGES: RegExp =
    /<td[^>]+><a[^>]+>([\d,]+)<\/a><\/td><td[^>]+>(?:<a[^>]+>)?&gt;(?:<\/a>)?<\/td>/;
  private static readonly PATTERN_NORMAL_PREVIEW: RegExp =
    /<div class="gdtm"[^<>]*><div[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\(([\s\S]+?)\)[^<>]*?-(\d+)px[^<>]*><a[^<>]*href="([\s\S]+?)"[^<>]*><img alt="([\d,]+)"/g;
  private static readonly PATTERN_NORMAL_PREVIEW_NEW: RegExp =
    /<a href="([\s\S]+?)">[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\(([\s\S]+?)\)[^<>]*"><\/div>[^<>]*<\/a>/g;
  private static readonly PATTERN_NORMAL_PREVIEW_NEW_WITH_LABEL: RegExp =
    /<a href="([\s\S]+?)">[^<>]*<div>[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\(([\s\S]+?)\)[^<>]*">/g;
  private static readonly PATTERN_SMALL_PREVIEW: RegExp =
    /<a href="([\s\S]+?)">[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\(([\s\S]+?)\)[^<>]*?-(\d+)px[^<>]*>/g;
  private static readonly PATTERN_SMALL_PREVIEW_WITH_LABEL: RegExp =
    /<a href="([\s\S]+?)">[^<>]*<div>[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\(([\s\S]+?)\)[^<>]*?-(\d+)px[^<>]*>/g;
  private static readonly PATTERN_LARGE_PREVIEW: RegExp =
    /<div class="gdtl"[\s\S]+?<a href="([\s\S]+?)"><img alt="([\d,]+)"[\s\S]+?src="([\s\S]+?)"/g;
  private static readonly PATTERN_LARGE_PREVIEW_NEW: RegExp =
    /<a href="([\s\S]+?)">[^<>]*<div title="Page (\d+):[^<>]*\(([\s\S]+?)\)[^<>]*0 0[^<>]*>/g;
  private static readonly PATTERN_ARCHIVE_DOWNLOAD: RegExp =
    /onclick="return popUp\('(.*)',480,320\)">Archive Download<\/a>/;

  private static readonly EMPTY_GALLERY_TAG_GROUP_ARRAY: GalleryTagGroup[] = [];
  private static readonly EMPTY_GALLERY_COMMENT_ARRAY: GalleryCommentList =
    new GalleryCommentList([], false);

  private static readonly OFFENSIVE_STRING: string =
    '<p>(And if you choose to ignore this warning, you lose all rights to complain about it in the future.)</p>';
  private static readonly PINING_STRING: string = '<p>This gallery is pining for the fjords.</p>';
  private static readonly UNAVAILABLE_STRING: string = 'This gallery is unavailable';

  private static _config: GalleryDetailParserConfig = new GalleryDetailParserConfig();
  private static _blackListHook: BlackListHook = new NoopBlackListHook();

  static setConfig(config: GalleryDetailParserConfig): void {
    GalleryDetailParser._config = config;
  }

  static setBlackListHook(hook: BlackListHook): void {
    GalleryDetailParser._blackListHook = hook;
  }

  /** 对齐 parse(String body)：四种「非正常页」先抛，再逐段解析。 */
  static parse(body: string): GalleryDetail {
    if (body.indexOf(GalleryDetailParser.OFFENSIVE_STRING) >= 0) {
      throw new OffensiveException();
    }
    if (body.indexOf(GalleryDetailParser.PINING_STRING) >= 0) {
      throw new PiningException();
    }
    if (body.indexOf(GalleryDetailParser.UNAVAILABLE_STRING) >= 0) {
      throw new GalleryUnavailableException();
    }
    const m: RegExpMatchArray | null = body.match(GalleryDetailParser.PATTERN_ERROR);
    if (m !== null) {
      throw new EhException(m[1]);
    }

    const galleryDetail: GalleryDetail = new GalleryDetail();
    const document: Document = Jsoup.parse(body);
    GalleryDetailParser.parseDetail(galleryDetail, document, body);
    galleryDetail.tags = GalleryDetailParser.parseTagGroups(document);
    galleryDetail.comments = GalleryDetailParser.parseComments(document);
    galleryDetail.previewPages = GalleryDetailParser.parsePreviewPagesDocument(document, body);
    galleryDetail.previewSet = GalleryDetailParser.parsePreviewSetDocument(document, body);
    galleryDetail.SpiderInfoPages = GalleryDetailParser.parsePages(body);
    galleryDetail.SpiderInfoPreviewPages = GalleryDetailParser.parsePreviewPages(body);
    galleryDetail.SpiderInfoPreviewSet = GalleryDetailParser.parsePreviewSet(body);
    // C-7 补充第 3 条：派生字段必须显式刷新
    galleryDetail.refreshPostedAt();
    return galleryDetail;
  }

  /** 对齐 parseDetail(GalleryDetail, Document, String)。 */
  private static parseDetail(gd: GalleryDetail, d: Document, body: string): void {
    const matcher: RegExpMatchArray | null = body.match(GalleryDetailParser.PATTERN_DETAIL);
    if (matcher === null) {
      throw new ParseException("Can't parse gallery detail", body);
    }
    gd.gid = GalleryDetailParser.parseLongSafely(matcher[1], -1);
    gd.token = matcher[2];
    gd.apiUid = GalleryDetailParser.parseLongSafely(matcher[3], -1);
    gd.apiKey = matcher[4];
    if (gd.gid === -1) {
      throw new ParseException("Can't parse gallery detail", body);
    }

    let m: RegExpMatchArray | null = body.match(GalleryDetailParser.PATTERN_TORRENT);
    if (m !== null) {
      gd.torrentUrl = ParserUtils.unescapeXml(GalleryDetailParser.trimStr(m[1]));
      gd.torrentCount = ParserUtils.parseInt(m[2], 0);
    } else {
      gd.torrentCount = 0;
      gd.torrentUrl = '';
    }

    m = body.match(GalleryDetailParser.PATTERN_ARCHIVE);
    if (m !== null) {
      gd.archiveUrl = ParserUtils.unescapeXml(GalleryDetailParser.trimStr(m[1]));
    } else {
      gd.archiveUrl = '';
    }

    try {
      const gm: Element | null = GalleryDetailParser.firstByClass(d, 'gm');
      if (gm === null) {
        throw new Error('gm is null');
      }
      // 封面
      const gd1: Element | null = gm.getElementById('gd1');
      try {
        const child0: Element | null = gd1 === null ? null : gd1.child(0);
        gd.thumb = GalleryDetailParser.parseCoverStyle(
          GalleryDetailParser.trimStr(child0 === null ? '' : child0.attr('style')));
      } catch (e) {
        gd.thumb = '';
      }
      // 标题
      const gn: Element | null = gm.getElementById('gn') ?? d.getElementById('gn');
      gd.title = gn === null ? '' : GalleryDetailParser.trimStr(gn.text());
      const gj: Element | null = gm.getElementById('gj') ?? d.getElementById('gj');
      gd.titleJpn = gj === null ? '' : GalleryDetailParser.trimStr(gj.text());
      // 分类
      const gdc: Element | null = gm.getElementById('gdc');
      try {
        let ce: Element | null = gdc === null ? null : GalleryDetailParser.firstByClass(gdc, 'cn');
        if (ce === null && gdc !== null) {
          ce = GalleryDetailParser.firstByClass(gdc, 'cs');
        }
        gd.category = EhUtils.getCategoryByType(ce === null ? null : ce.text());
      } catch (e) {
        gd.category = EhUtils.UNKNOWN;
      }
      // 上传者
      const gdn: Element | null = gm.getElementById('gdn');
      gd.uploader = gdn === null ? '' : GalleryDetailParser.trimStr(gdn.text());
      // 一组 key-value
      const gdd: Element | null = gm.getElementById('gdd');
      gd.posted = '';
      gd.parent = '';
      gd.visible = '';
      gd.size = '';
      gd.pages = 0;
      gd.favoriteCount = 0;
      try {
        const c0: Element | null = gdd === null ? null : gdd.child(0);
        const c1: Element | null = c0 === null ? null : c0.child(0);
        if (c1 === null) {
          throw new Error('gdd structure unexpected');
        }
        const es: Elements = c1.children();
        for (let i = 0; i < es.size(); i++) {
          GalleryDetailParser.parseDetailInfo(gd, es.get(i), body);
        }
      } catch (e) {
        // 上游在此吞掉异常（默认值已设好）
      }
      // 评分人数
      const ratingCount: Element | null = gm.getElementById('rating_count');
      gd.ratingCount = ratingCount === null
        ? 0
        : ParserUtils.parseInt(GalleryDetailParser.trimStr(ratingCount.text()), 0);
      // 评分
      const ratingLabel: Element | null = gm.getElementById('rating_label');
      if (ratingLabel !== null) {
        const ratingStr: string = GalleryDetailParser.trimStr(ratingLabel.text());
        if (ratingStr === 'Not Yet Rated') {
          gd.rating = -1.0;
        } else {
          const index: number = ratingStr.indexOf(' ');
          if (index === -1 || index >= ratingStr.length) {
            gd.rating = 0;
          } else {
            gd.rating = ParserUtils.parseFloat(ratingStr.substring(index + 1), 0);
          }
        }
      } else {
        gd.rating = -1.0;
      }
      // 是否已评分（网页端 #rating_image 含 irg / irb / irr 类）
      const ratingImage: Element | null = gm.getElementById('rating_image') ?? d.getElementById('rating_image');
      gd.rated = ratingImage !== null &&
        (ratingImage.hasClass('irg') || ratingImage.hasClass('irb') || ratingImage.hasClass('irr'));
      // 收藏状态
      const gdf: Element | null = gm.getElementById('gdf');
      gd.isFavorited = gdf !== null && GalleryDetailParser.trimStr(gdf.text()) !== 'Add to Favorites';
      if (gdf !== null) {
        const favoriteName: string = GalleryDetailParser.trimStr(gdf.text());
        gd.favoriteName = favoriteName === 'Add to Favorites' ? null : GalleryDetailParser.trimStr(gdf.text());
      }
    } catch (e) {
      throw new ParseException("Can't parse gallery detail", body, e as Error);
    }

    // 新版本列表（#gnd）
    try {
      const updateElement: Element | null = d.getElementById('gnd');
      if (updateElement === null) {
        gd.newVersions = null;
        return;
      }
      const versionList: NewVersion[] = [];
      const textNodes: string[] = updateElement.textNodes().map((t): string => t.text());
      for (let i = 0; i < updateElement.children().size(); i++) {
        const urlE: Element = updateElement.child(i) as Element;
        const url: string = urlE.absUrl('href');
        if (url !== null && url !== undefined && url.length > 0) {
          const version: NewVersion = new NewVersion();
          version.versionUrl = url;
          const nameS: string = urlE.text();
          const textNode: string | null = versionList.length < textNodes.length
            ? textNodes[versionList.length] : null;
          const timeS: string = textNode === null ? '' : textNode;
          version.versionName = timeS.length > 0 ? nameS + timeS : nameS;
          versionList.push(version);
        }
      }
      gd.newVersions = versionList.length === 0 ? null : versionList;
    } catch (e) {
      gd.newVersions = null;
    }
  }

  /** 对齐 parseCoverStyle(String)：从 `background:transparent url(...)` 里取 url。 */
  private static parseCoverStyle(str: string): string {
    const matcher: RegExpMatchArray | null = str.match(GalleryDetailParser.PATTERN_COVER);
    if (matcher !== null) {
      return EhUtils.handleThumbUrlResolution(matcher[3]) as string;
    }
    return '';
  }

  /** 对齐 parseDetailInfo(GalleryDetail, Element, String)：按 key 前缀分派。 */
  private static parseDetailInfo(gd: GalleryDetail, e: Element, body: string): void {
    const es: Elements = e.children();
    if (es.size() < 2) {
      return;
    }
    const key: string = GalleryDetailParser.trimStr(es.get(0).text());
    const value: string = GalleryDetailParser.trimStr(es.get(1).ownText());
    if (key.startsWith('Posted')) {
      gd.posted = value;
    } else if (key.startsWith('Parent')) {
      const a: Element | null = es.get(1).children().first();
      if (a !== null) {
        gd.parent = a.attr('href');
      }
    } else if (key.startsWith('Visible')) {
      gd.visible = value;
    } else if (key.startsWith('Language')) {
      gd.language = value;
    } else if (key.startsWith('File Size')) {
      gd.size = value;
    } else if (key.startsWith('Length')) {
      const index: number = value.indexOf(' ');
      gd.pages = index >= 0 ? ParserUtils.parseInt(value.substring(0, index), 1) : 1;
    } else if (key.startsWith('Favorited')) {
      switch (value) {
        case 'Never':
          gd.favoriteCount = 0;
          break;
        case 'Once':
          gd.favoriteCount = 1;
          break;
        default: {
          const index: number = value.indexOf(' ');
          gd.favoriteCount = index === -1 ? 0 : ParserUtils.parseInt(value.substring(0, index), 0);
          break;
        }
      }
    }
  }

  /** 对齐 parseTagGroup(Element)：`<td>namespace:</td><td><div><a>tag</a></div>…` → 一组标签。 */
  private static parseTagGroup(element: Element): GalleryTagGroup | null {
    try {
      const group: GalleryTagGroup = new GalleryTagGroup();
      const nameEl: Element | null = element.child(0);
      if (nameEl === null) {
        return null;
      }
      let nameSpace: string = nameEl.text();
      if (nameSpace.length === 0) {
        return null;
      }
      nameSpace = nameSpace.substring(0, nameSpace.length - 1); // 去掉末尾 ':'
      group.groupName = nameSpace;

      const tagCell: Element | null = element.child(1);
      if (tagCell === null) {
        return null;
      }
      const tags: Elements = tagCell.children();
      for (let i = 0; i < tags.size(); i++) {
        let tag: string = tags.get(i).text();
        const index: number = tag.indexOf('|');
        if (index >= 0) {
          tag = tag.substring(0, index).trim();
        }
        group.addTag(tag);
      }
      return group.size() > 0 ? group : null;
    } catch (e) {
      return null;
    }
  }

  /** 对齐 parseTagGroups(Document)。 */
  static parseTagGroups(document: Document): GalleryTagGroup[] {
    try {
      const taglist: Element | null = document.getElementById('taglist');
      if (taglist === null) {
        return GalleryDetailParser.EMPTY_GALLERY_TAG_GROUP_ARRAY;
      }
      const c0: Element | null = taglist.child(0);
      const c1: Element | null = c0 === null ? null : c0.child(0);
      if (c1 === null) {
        return GalleryDetailParser.EMPTY_GALLERY_TAG_GROUP_ARRAY;
      }
      return GalleryDetailParser.parseTagGroupsFromElements(c1.children());
    } catch (e) {
      return GalleryDetailParser.EMPTY_GALLERY_TAG_GROUP_ARRAY;
    }
  }

  /** 对齐 parseTagGroups(Elements trs)。 */
  static parseTagGroupsFromElements(trs: Elements): GalleryTagGroup[] {
    try {
      const list: GalleryTagGroup[] = [];
      for (let i = 0; i < trs.size(); i++) {
        const group: GalleryTagGroup | null = GalleryDetailParser.parseTagGroup(trs.get(i));
        if (group !== null) {
          list.push(group);
        }
      }
      return list;
    } catch (e) {
      return GalleryDetailParser.EMPTY_GALLERY_TAG_GROUP_ARRAY;
    }
  }

  /** 对齐 parseTagGroups(String body)：正则版（SpiderInfo 快速路径用）。 */
  static parseTagGroupsFromBody(body: string): GalleryTagGroup[] {
    const list: GalleryTagGroup[] = [];
    const re: RegExp = new RegExp(GalleryDetailParser.PATTERN_TAG_GROUP.source, 'g');
    let m: RegExpExecArray | null = re.exec(body);
    while (m !== null) {
      const tagGroup: GalleryTagGroup = new GalleryTagGroup();
      tagGroup.groupName = ParserUtils.trim(m[1]);
      GalleryDetailParser.parseGroup(tagGroup, m[0]);
      list.push(tagGroup);
      m = re.exec(body);
    }
    return list;
  }

  private static parseGroup(tagGroup: GalleryTagGroup, body: string): void {
    const re: RegExp = new RegExp(GalleryDetailParser.PATTERN_TAG.source, 'g');
    let m: RegExpExecArray | null = re.exec(body);
    while (m !== null) {
      tagGroup.addTag(ParserUtils.trim(m[1]));
      m = re.exec(body);
    }
  }

  /** 对齐 parseComment(Element)：单个 `.c1` 评论块 → GalleryComment。 */
  static parseComment(element: Element): GalleryComment | null {
    try {
      const comment: GalleryComment = new GalleryComment();

      const a: Element | null = element.previousElementSibling();
      const name: string = a === null ? '' : a.attr('name');
      try {
        comment.id = Number.parseInt(GalleryDetailParser.trimStr(name).substring(1), 10);
        if (Number.isNaN(comment.id)) {
          comment.id = 0;
        }
      } catch (e) {
        // 上游 NumberFormatException 时保留 0
      }

      const c4: Element | null = GalleryDetailParser.firstByClass(element, 'c4');
      if (c4 !== null) {
        const children: Elements = c4.children();
        for (let i = 0; i < children.size(); i++) {
          const e: Element = children.get(i);
          switch (e.text()) {
            case 'Vote+':
              comment.voteUpAble = true;
              comment.voteUpEd = GalleryDetailParser.trimStr(e.attr('style')).length > 0;
              break;
            case 'Vote-':
              comment.voteDownAble = true;
              comment.voteDownEd = GalleryDetailParser.trimStr(e.attr('style')).length > 0;
              break;
            case 'Edit':
              comment.editable = true;
              break;
            default:
              break;
          }
        }
      }

      const c7: Element | null = GalleryDetailParser.firstByClass(element, 'c7');
      if (c7 !== null) {
        comment.voteState = GalleryDetailParser.trimStr(c7.text());
      }

      const c5: Element | null = GalleryDetailParser.firstByClass(element, 'c5');
      if (c5 !== null) {
        const es: Elements = c5.children();
        if (es.size() > 0) {
          comment.score = ParserUtils.parseInt(GalleryDetailParser.trimStr(es.get(0).text()), 0);
        }
      }

      const c3: Element | null = GalleryDetailParser.firstByClass(element, 'c3');
      if (c3 === null) {
        return null;
      }
      let temp: string = c3.ownText();
      if (temp.indexOf(' by:') >= 0) {
        temp = temp.substring('Posted on '.length, temp.length - ' by:'.length);
      } else {
        temp = temp.substring('Posted on '.length);
      }
      comment.time = GalleryDetailParser.parseWebCommentDate(temp);

      const c3Child0: Element | null = c3.child(0);
      comment.user = c3.children().size() === 0
        ? (c4 === null ? '' : c4.text())
        : (c3Child0 === null ? '' : c3Child0.text());

      const c6: Element | null = GalleryDetailParser.firstByClass(element, 'c6');
      comment.comment = c6 === null ? '' : c6.html();

      const c8: Element | null = GalleryDetailParser.firstByClass(element, 'c8');
      if (c8 !== null) {
        const e: Element | null = c8.children().first();
        if (e !== null) {
          // 上游 bug：这里用的是 temp（评论发布时间），不是 c8 自己的文本。照搬。
          comment.lastEdited = GalleryDetailParser.parseWebCommentDate(temp);
        }
      }
      return comment;
    } catch (e) {
      return null;
    }
  }

  /** 对齐 parseComments(Document)：DOM 版，含本地黑名单过滤与 "click to show all"。 */
  static parseComments(document: Document): GalleryCommentList {
    try {
      const cdiv: Element | null = document.getElementById('cdiv');
      if (cdiv === null) {
        return GalleryDetailParser.EMPTY_GALLERY_COMMENT_ARRAY;
      }
      const c1s: Elements = cdiv.getElementsByClass('c1');
      const list: GalleryComment[] = [];
      for (let i = 0; i < c1s.size(); i++) {
        const comment: GalleryComment | null = GalleryDetailParser.parseComment(c1s.get(i));
        if (comment !== null && !GalleryDetailParser._blackListHook.inBlackList(comment.user)) {
          list.push(comment);
        }
      }

      let hasMore: boolean = false;
      const chd: Element | null = cdiv.getElementById('chd');
      if (chd !== null) {
        hasMore = GalleryDetailParser.containsText(chd, 'click to show all');
      }
      return new GalleryCommentList(list, hasMore);
    } catch (e) {
      return GalleryDetailParser.EMPTY_GALLERY_COMMENT_ARRAY;
    }
  }

  /** 对齐 NodeTraversor + NodeVisitor 的等价：深度优先找「文本等于 target」的元素。 */
  private static containsText(root: Element, target: string): boolean {
    if (root.text() === target) {
      return true;
    }
    const children: Elements = root.children();
    for (let i = 0; i < children.size(); i++) {
      if (GalleryDetailParser.containsText(children.get(i), target)) {
        return true;
      }
    }
    return false;
  }

  /** 对齐 parseComments(String body)：正则版。 */
  static parseCommentsFromBody(body: string): GalleryComment[] {
    const list: GalleryComment[] = [];
    const re: RegExp = new RegExp(GalleryDetailParser.PATTERN_COMMENT.source, 'g');
    let m: RegExpExecArray | null = re.exec(body);
    while (m !== null) {
      const webDateString: string = ParserUtils.trim(m[1]);
      const comment: GalleryComment = new GalleryComment();
      comment.time = GalleryDetailParser.parseWebCommentDate(webDateString);
      comment.user = ParserUtils.trim(m[2]);
      comment.comment = m[3];
      list.push(comment);
      m = re.exec(body);
    }
    return list;
  }

  /** 对齐 parsePreviewPages(Document, String)（DOM 版，注意方法名后缀以避重载）。 */
  static parsePreviewPagesDocument(document: Document, body: string): number {
    try {
      const ptt: Element | null = GalleryDetailParser.firstByClass(document, 'ptt');
      if (ptt === null) {
        throw new Error('ptt is null');
      }
      const c0: Element | null = ptt.child(0);
      const c1: Element | null = c0 === null ? null : c0.child(0);
      if (c1 === null) {
        throw new Error('ptt structure unexpected');
      }
      const elements: Elements = c1.children();
      const v: number = Number.parseInt(elements.get(elements.size() - 2).text(), 10);
      if (Number.isNaN(v)) {
        throw new Error('not a number');
      }
      return v;
    } catch (e) {
      throw new ParseException("Can't parse preview pages", body, e as Error);
    }
  }

  /** 对齐 parsePreviewPages(String body)：正则版。 */
  static parsePreviewPages(body: string): number {
    const m: RegExpMatchArray | null = body.match(GalleryDetailParser.PATTERN_PREVIEW_PAGES);
    let previewPages: number = -1;
    if (m !== null) {
      previewPages = ParserUtils.parseInt(m[1], -1);
    }
    if (previewPages <= 0) {
      throw new ParseException('Parse preview page count error', body);
    }
    return previewPages;
  }

  /** 对齐 parsePages(String body)：`Length: N pages`。 */
  static parsePages(body: string): number {
    let pages: number = -1;
    const m: RegExpMatchArray | null = body.match(GalleryDetailParser.PATTERN_PAGES);
    if (m !== null) {
      pages = ParserUtils.parseInt(m[1], -1);
    }
    if (pages < 0) {
      throw new ParseException('Parse pages error', body);
    }
    return pages;
  }

  /** 对齐 parsePreviewSet(Document d, String body)。 */
  static parsePreviewSetDocument(d: Document, body: string): PreviewSet {
    const gt200: Elements = d.getElementsByClass('gt200');
    const gt100: Elements = d.getElementsByClass('gt100');
    let previewClass: string = gt200.size() > 0 ? GalleryDetailParser.htmlOf(gt200) : '';
    if (previewClass.length === 0) {
      previewClass = gt100.size() > 0 ? GalleryDetailParser.htmlOf(gt100) : '';
    }
    try {
      const source: string = previewClass.length === 0 ? body : previewClass;
      let previewSet: PreviewSet = GalleryDetailParser.parseNormalPreviewSet(source);
      if (previewSet.size() === 0) {
        previewSet = GalleryDetailParser.parseLargePreviewSet(source);
      }
      if (previewSet.size() === 0) {
        throw new ParseException('加载预览图失败', previewClass);
      }
      return previewSet;
    } catch (e) {
      // 上游吞掉 ParseException 返回空 NormalPreviewSet
      return new NormalPreviewSet();
    }
  }

  /** 对齐 parsePreviewSet(String body)。 */
  static parsePreviewSet(body: string): PreviewSet {
    return GalleryDetailParser.parsePreviewSetDocument(Jsoup.parse(body), body);
  }

  /** 对齐 parseLargePreviewSet(String body)：新格式优先，回落旧格式。 */
  private static parseLargePreviewSet(body: string): LargePreviewSet {
    const largePreviewSet: LargePreviewSet = new LargePreviewSet();
    GalleryDetailParser.findLarge(body, largePreviewSet, true);
    if (largePreviewSet.size() === 0) {
      GalleryDetailParser.findLarge(body, largePreviewSet, false);
    }
    return largePreviewSet;
  }

  private static findLarge(body: string, largePreviewSet: LargePreviewSet, isNew: boolean): void {
    const source: string = isNew
      ? GalleryDetailParser.PATTERN_LARGE_PREVIEW_NEW.source
      : GalleryDetailParser.PATTERN_LARGE_PREVIEW.source;
    const re: RegExp = new RegExp(source, 'g');
    let m: RegExpExecArray | null = re.exec(body);
    while (m !== null) {
      const index: number = ParserUtils.parseInt(m[2], 0) - 1;
      if (index >= 0) {
        let imageUrl: string = ParserUtils.trim(m[3]);
        const pageUrl: string = ParserUtils.trim(m[1]);
        if (GalleryDetailParser._config.getFixThumbUrl()) {
          imageUrl = EhUrl.getFixedPreviewThumbUrl(imageUrl);
        }
        largePreviewSet.addItem(index, imageUrl, pageUrl);
      }
      m = re.exec(body);
    }
  }

  /** 对齐 parseNormalPreviewSet(String body)：五套正则依次尝试。 */
  private static parseNormalPreviewSet(body: string): NormalPreviewSet {
    const normalPreviewSet: NormalPreviewSet = new NormalPreviewSet();
    GalleryDetailParser.parseNewPreview(body, normalPreviewSet, GalleryDetailParser.PATTERN_SMALL_PREVIEW.source);
    if (normalPreviewSet.size() === 0) {
      GalleryDetailParser.parseNewPreview(body, normalPreviewSet, GalleryDetailParser.PATTERN_NORMAL_PREVIEW_NEW.source);
    }
    if (normalPreviewSet.size() === 0) {
      GalleryDetailParser.parseNewPreview(body, normalPreviewSet, GalleryDetailParser.PATTERN_SMALL_PREVIEW_WITH_LABEL.source);
    }
    if (normalPreviewSet.size() === 0) {
      GalleryDetailParser.parseNewPreview(body, normalPreviewSet, GalleryDetailParser.PATTERN_NORMAL_PREVIEW_NEW_WITH_LABEL.source);
    }
    if (normalPreviewSet.size() === 0) {
      // 旧格式：PATTERN_NORMAL_PREVIEW（6 个组，第 6 组是页码）
      const re: RegExp = new RegExp(GalleryDetailParser.PATTERN_NORMAL_PREVIEW.source, 'g');
      let m: RegExpExecArray | null = re.exec(body);
      while (m !== null) {
        const position: number = ParserUtils.parseInt(m[6], 0) - 1;
        if (position >= 0) {
          const imageUrl: string = ParserUtils.trim(m[3]);
          const xOffset: number = ParserUtils.parseInt(m[4], 0);
          const width: number = ParserUtils.parseInt(m[1], 0);
          const height: number = ParserUtils.parseInt(m[2], 0);
          if (width > 0 && height > 0) {
            const pageUrl: string = ParserUtils.trim(m[5]);
            normalPreviewSet.addItem(position, imageUrl, xOffset, 0, width, height, pageUrl);
          }
        }
        m = re.exec(body);
      }
    }
    return normalPreviewSet;
  }

  /** 对齐 parserNewPreview(Matcher, NormalPreviewSet)：组数 5 或 6（带 xOffset）。 */
  private static parseNewPreview(body: string, normalPreviewSet: NormalPreviewSet, source: string): void {
    const re: RegExp = new RegExp(source, 'g');
    const expectOffset: boolean = source === GalleryDetailParser.PATTERN_SMALL_PREVIEW.source ||
      source === GalleryDetailParser.PATTERN_SMALL_PREVIEW_WITH_LABEL.source;
    let m: RegExpExecArray | null = re.exec(body);
    while (m !== null) {
      const position: number = ParserUtils.parseInt(m[2], 0) - 1;
      if (position >= 0) {
        const imageUrl: string = ParserUtils.trim(m[5]);
        const xOffset: number = expectOffset ? ParserUtils.parseInt(m[6], 0) : 0;
        const width: number = ParserUtils.parseInt(m[3], 0);
        const height: number = ParserUtils.parseInt(m[4], 0);
        if (width > 0 && height > 0) {
          const pageUrl: string = ParserUtils.trim(m[1]);
          normalPreviewSet.addItem(position, imageUrl, xOffset, 0, width, height, pageUrl);
        }
      }
      m = re.exec(body);
    }
  }

  // ---- 工具 ----

  /** 对齐 StringUtils.trim：null → ""，其余 trim（**不**反转义）。 */
  private static trimStr(s: string | null): string {
    return s === null || s === undefined ? '' : s.trim();
  }

  private static parseLongSafely(s: string, def: number): number {
    const v: number = Number.parseInt(s, 10);
    return Number.isNaN(v) ? def : v;
  }

  /** 对齐 jsoup Elements.html()：拼接所有匹配元素的 innerHtml。 */
  private static htmlOf(es: Elements): string {
    let out: string = '';
    for (let i = 0; i < es.size(); i++) {
      out += es.get(i).html();
    }
    return out;
  }

  private static firstByClass(root: Element, className: string): Element | null {
    const es: Elements = root.getElementsByClass(className);
    return es.size() === 0 ? null : es.get(0);
  }

  /**
   * 对齐 `SimpleDateFormat("dd MMMMM yyyy, HH:mm", Locale.US)` + **UTC** 时区。
   * 例："02 January 2020, 03:04" → 毫秒时间戳；解析失败返回 0（正则版上游用 new Date(0L)）。
   */
  static parseWebCommentDate(s: string): number {
    const m: RegExpMatchArray | null = s.trim().match(/^(\d{1,2}) ([A-Za-z]+) (\d{4}), (\d{1,2}):(\d{2})$/);
    if (m === null) {
      return 0;
    }
    const months: string[] = [
      'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december'
    ];
    const month: number = months.indexOf(m[2].toLowerCase());
    if (month < 0) {
      return 0;
    }
    // Date.UTC：与上游 UTC 时区口径一致
    return Date.UTC(Number.parseInt(m[3], 10), month, Number.parseInt(m[1], 10),
      Number.parseInt(m[4], 10), Number.parseInt(m[5], 10), 0, 0);
  }
}

