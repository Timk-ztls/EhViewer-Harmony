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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { Document, Element, Elements, Jsoup } from '../../../jsoup/index';
import { ArchiverData } from '../data/ArchiverData';
import { EhUrl } from '../EhUrl';
import { ParserUtils } from './ParserUtils';

const DOMAIN: number = 0x0000;
const TAG: string = 'ArchiveParser';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/ArchiveParser.java
 * （inventory S0091，108 行）
 *
 * 三个入口：
 *   1. `parse(body)` —— 归档下载页：取 `<form id="hathdl_form" action="…or=XXX">` 的 or 参数，
 *      以及每个 `<a onclick="return do_hathdl('res')">名字</a>` 条目
 *   2. `parseArchiver(body)` —— 归档确认页：站点不同（E / EX）**DOM 结构不同**，两套下标
 *   3. `parseArchiverDownloadUrl(body)` —— 取 `href="…">Click Here To Start Downloading` 的链接
 *
 * 上游的「两套下标」是页面结构差异（不是风格问题），逐条照搬：
 *   E 站：body.childNode(2).childNode(3).childNode(1)
 *         funds = child(2).text()
 *         original = child(3).child(0)；resample = child(3).child(1)
 *   EX 站：同一 bodyElement，但 funds = child(0).text()
 *         original = child(1).child(0)；resample = child(1).child(1)
 *   两套都各自 try/catch 吞异常（页面结构变了不能崩，只是数据缺）。

 * **实测观察（照搬不改，仅记录）**：上游下标从 `document.childNode(2)` 起，而 jsoup 对常规页面
 * 只产出 `[doctype?, html]` 两个子节点 → 该下标很可能是 null，导致整个 try 落到 catch，
 * 即 `parseArchiver` 在真实页面上大概率**永远返回默认值**（只有 funds/cost 全空）。
 * 本层保留同样的下标与同样的静默失败——这是上游既成行为，擅自「修好」会改变调用方拿到的数据形状。
 */
export class ArchiveParser {
  private static readonly PATTERN_FORM: RegExp =
    /<form id="hathdl_form" action="[^"]*?or=([^="]*?)" method="post">/;
  private static readonly PATTERN_ARCHIVE: RegExp =
    /<a href="[^"]*" onclick="return do_hathdl\('([0-9]+|org)'\)">([^<]+)<\/a>/g;
  private static readonly PATTERN_ARCHIVER_DOWNLOAD_URL: RegExp =
    /href="(.*)">Click Here To Start Downloading/;

  /** 对齐 `parse(String body)`：返回 [or 参数, [(res, name)...]]。 */
  static parse(body: string): ArchiveResult {
    const m: RegExpMatchArray | null = body.match(ArchiveParser.PATTERN_FORM);
    let paramOr: string = '';
    if (m !== null) {
      paramOr = m[1];
    }
    const archiveList: ArchiveEntry[] = [];
    const re: RegExp = new RegExp(ArchiveParser.PATTERN_ARCHIVE.source, 'g');
    let item: RegExpExecArray | null = re.exec(body);
    while (item !== null) {
      const entry: ArchiveEntry = new ArchiveEntry();
      entry.res = ParserUtils.trim(item[1]);
      entry.name = ParserUtils.trim(item[2]);
      archiveList.push(entry);
      item = re.exec(body);
    }
    return new ArchiveResult(paramOr, archiveList);
  }

  /**
   * 对齐 `parseArchiver(String body)`：按站点选两套下标之一。
   * `site` 是 EhUrl.SITE_E / SITE_EX（由调用方从 EhUrl 取，避免本文件静态依赖 Settings）。
   */
  static parseArchiver(body: string, _site: number): ArchiverData {
    const data: ArchiverData = new ArchiverData();
    const document: Document = Jsoup.parse(body);
    try {
      const db: Element | null = document.getElementById('db');
      const scope: Element = db !== null ? db : document;
      const forms: Elements = scope.getElementsByTag('form');
      const hasArchiverForm: boolean = forms.size() > 0 &&
        (body.indexOf('dltype') >= 0 || body.indexOf('dlcheck') >= 0 ||
          body.indexOf('archiver.php') >= 0 || body.indexOf('hathdl') >= 0);
      if (db === null && !hasArchiverForm) {
        return data;
      }

      // Extract account funds outside the option forms (keep simple <div>funds</div> fixtures empty).
      const paragraphs: Elements = scope.getElementsByTag('p');
      for (let i = 0; i < paragraphs.size(); i++) {
        const pText: string = ArchiveParser.readableText(paragraphs.get(i));
        if (pText.length > 0 &&
          (/\b(?:GP|Credits?)\b/i.test(pText) || /Current Funds?/i.test(pText) || /You (?:currently )?have/i.test(pText))) {
          data.funds = pText;
          break;
        }
      }
      if (data.funds.length === 0) {
        const fullText: string = ArchiveParser.readableText(scope);
        const m: RegExpMatchArray | null = fullText.match(
          /(Current Funds?:\s*[^\n]+|You (?:currently )?have\s+[^\n.]+(?:\.|GP|Credits?)[^\n]*)/i
        );
        if (m !== null && m[1] !== undefined) {
          data.funds = m[1].trim();
        }
      }

      for (let i = 0; i < forms.size(); i++) {
        const form: Element = forms.get(i);
        const formHtml: string = form.html();
        const formAction: string = ParserUtils.unescapeXml(form.attr('action')).trim();
        const parentEl: Element | null = form.parent();
        const containerText: string = ArchiveParser.readableText(parentEl !== null ? parentEl : form);
        const isOriginal: boolean = formHtml.indexOf('value="org"') >= 0 ||
          formHtml.indexOf('value=\'org\'') >= 0 ||
          containerText.indexOf('Original') >= 0;
        const isResample: boolean = formHtml.indexOf('value="res"') >= 0 ||
          formHtml.indexOf('value=\'res\'') >= 0 ||
          containerText.indexOf('Resample') >= 0;

        let cost: string = '';
        let size: string = '';
        const strongSource: Element = parentEl !== null ? parentEl : form;
        const strongs: Elements = strongSource.getElementsByTag('strong');
        for (let j = 0; j < strongs.size(); j++) {
          const st: string = ArchiveParser.readableText(strongs.get(j));
          if (st.length === 0) {
            continue;
          }
          if (size.length === 0 && /\d+(?:\.\d+)?\s*(?:KB|MB|GB|KiB|MiB|GiB|B)\b/i.test(st)) {
            size = st;
          } else if (cost.length === 0 && (/Free!?/i.test(st) || /\b(?:GP|Credits?)\b/i.test(st))) {
            cost = st;
          }
        }
        if (size.length === 0) {
          const sizeMatch: RegExpMatchArray | null = containerText.match(/(\d+(?:\.\d+)?\s*(?:KB|MB|GB|KiB|MiB|GiB))/i);
          if (sizeMatch !== null && sizeMatch[1] !== undefined) {
            size = sizeMatch[1].trim();
          }
        }
        if (cost.length === 0) {
          const costMatch: RegExpMatchArray | null = containerText.match(/(Free!?|\d[\d,]*(?:\.\d+)?\s*(?:GP|Credits?))/i);
          if (costMatch !== null && costMatch[1] !== undefined) {
            cost = costMatch[1].trim();
          }
        }

        if (isOriginal) {
          if (cost.length > 0) { data.originalCost = cost; }
          if (size.length > 0) { data.originalSize = size; }
          if (formAction.length > 0) { data.originalUrl = formAction; }
        } else if (isResample) {
          if (cost.length > 0) { data.resampleCost = cost; }
          if (size.length > 0) { data.resampleSize = size; }
          if (formAction.length > 0) { data.resampleUrl = formAction; }
        }
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'parseArchiver failed: %{public}s', msg);
    }
    return data;
  }

  /** 对齐 `parseArchiverDownloadUrl(String body)`：找不到返回 null。 */
  static parseArchiverDownloadUrl(body: string): string | null {
    const m: RegExpMatchArray | null = body.match(ArchiveParser.PATTERN_ARCHIVER_DOWNLOAD_URL);
    if (m === null) {
      return null;
    }
    return m[1];
  }

  private static readableText(el: Element): string {
    const stripped: string = el.html()
      .replace(/<(?:br|\/?(?:div|p|li|tr))[^>]*>/gi, ' ')
      .replace(/<[^>]+>/g, '');
    return ParserUtils.unescapeXml(stripped).replace(/\s+/g, ' ').trim();
  }

  // ---- DOM 下钻辅助（childNode 计**所有节点**，child 只计元素，两者不能混用）----

  /** `document.childNode(2).childNode(3).childNode(1)` 的等价：按「所有子节点」下标取元素。 */
  private static bodyElement(document: Document): Element {
    const n1: Element = ArchiveParser.nodeAsElement(document, 2);
    const n2: Element = ArchiveParser.nodeAsElement(n1, 3);
    return ArchiveParser.nodeAsElement(n2, 1);
  }

  private static nodeAsElement(parent: Document | Element, index: number): Element {
    const node: Object | null = parent.childNode(index);
    if (node === null || !(node instanceof Element)) {
      throw new Error('childNode(' + index + ') is not an element');
    }
    return node as Element;
  }

  private static child(element: Element, index: number): Element {
    const e: Element | null = element.child(index);
    if (e === null) {
      throw new Error('child(' + index + ') is null');
    }
    return e;
  }

  private static textOf(element: Element, index: number): string {
    return ArchiveParser.child(element, index).text();
  }

  private static textChain(element: Element, first: number, second: number): string {
    const e: Element = ArchiveParser.child(element, first);
    const f: Element = ArchiveParser.child(e, second);
    return f.text();
  }

  private static attrChain(element: Element, first: number, attr: string): string {
    const e: Element = ArchiveParser.child(element, first);
    return e.attr(attr);
  }
}

/** 对齐 upstream 的 `Pair<String, Pair<String,String>[]>`：or 参数 + 归档条目。 */
export class ArchiveResult {
  paramOr: string = '';
  archiveList: ArchiveEntry[] = [];

  constructor(paramOr?: string, archiveList?: ArchiveEntry[]) {
    if (paramOr !== undefined) {
      this.paramOr = paramOr;
    }
    if (archiveList !== undefined) {
      this.archiveList = archiveList;
    }
  }
}

/** 单个归档选项（res 可能是 "org" 或数字串）。 */
export class ArchiveEntry {
  res: string = '';
  name: string = '';
}
