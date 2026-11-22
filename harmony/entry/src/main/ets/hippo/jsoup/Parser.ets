/*
 * Copyright 2009-2020 Jonathan Hedley (jsoup / TagSoup)
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

import { Document, Element, Node, TextNode, VOID_TAGS } from './Nodes';

/**
 * HTML 解析器（jsoup 的 Parser + TagSoup 宽容模式的等价子集）。
 *
 * 上游调用面（15 处 `Jsoup.parse`）：1 处两参 `Jsoup.parse(body, baseUri)`（ForumsParser），
 * 其余单参。因此本层必须支持 baseUri（影响 absUrl 的结果）。
 *
 * 与 jsoup/TagSoup 对齐的行为（决定解析结果一致）：
 *   1) 宽容解析：未闭合标签、多余闭合标签不报错，多余的 `</x>` 直接忽略
 *   2) 自动补全结构：创建 `html` / `head` / `body`，与 jsoup 的 HtmlTreeBuilder 一致；
 *      `<table>` 内直接出现 `<tr>`/`<td>`/`<th>` 时隐式插入 `<tbody>`（必要时再补 `<tr>`），
 *      直接出现 `<col>` 时隐式插入 `<colgroup>`
 *   3) 隐式闭合：`p` 遇块级元素、`li` 遇 `li`、`td`/`th` 遇 `td`/`th`/`tr`、
 *      `tr` 遇 `tr`、`option` 遇 `option`、`dt`/`dd` 互斥 —— jsoup 的 Tag.isKnownTag + 规则表
 *   4) 空元素（VOID_TAGS）不入栈
 *   5) raw text：`script` / `style` 内容不解析标签
 *   6) 实体解码：`&amp; &lt; &gt; &quot; &apos; &#39; &#x27; &nbsp;` 及 `&#NNN;` / `&#xHH;`
 *   7) 属性：双引号/单引号/无引号/布尔属性（无值 → 值为空串，与 jsoup 一致）
 *
 * 未实现（e-hentai 页面不需要）：注释保留（丢弃，与 jsoup 不同但上游不读注释）、
 * 表格 foster parenting、`<template>` 内容独立文档、字符编码嗅探（body 已是 String）。
 */
export class Jsoup {
  /** 对齐 Jsoup.parse(String html)：baseUri 为空串。 */
  static parse(html: string): Document {
    return new HtmlParser(html, '').parseDocument();
  }

  /** 对齐 Jsoup.parse(String html, String baseUri)。 */
  static parseWithBaseUri(html: string, baseUri: string): Document {
    return new HtmlParser(html, baseUri).parseDocument();
  }

  /**
   * 对齐 Jsoup.parseBodyFragment(String html)：把片段包进 body 再解析。
   * 与 jsoup 的差别：jsoup 会用一个空壳 Document + body 容器；本层复用 parseDocument 后
   * 取出 `<body>`（片段场景下两者等价，因为调用方只 select 子元素）。
   */
  static parseBodyFragment(html: string): Document {
    const wrapped: string = '<html><head></head><body>' + html + '</body></html>';
    return new HtmlParser(wrapped, '').parseDocument();
  }
}

/** 隐式闭合规则：遇到 tag 时，栈顶若是这些元素就先弹出。 */
const IMPLIED_CLOSE: Map<string, string[]> = new Map<string, string[]>();
IMPLIED_CLOSE.set('li', ['li']);
IMPLIED_CLOSE.set('td', ['td', 'th', 'colgroup', 'caption']);
IMPLIED_CLOSE.set('th', ['td', 'th', 'colgroup', 'caption']);
IMPLIED_CLOSE.set('tr', ['tr', 'td', 'th', 'colgroup', 'caption']);
IMPLIED_CLOSE.set('option', ['option']);
IMPLIED_CLOSE.set('dt', ['dt', 'dd']);
IMPLIED_CLOSE.set('dd', ['dt', 'dd']);
IMPLIED_CLOSE.set('thead', ['thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'colgroup', 'caption']);
IMPLIED_CLOSE.set('tbody', ['thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'colgroup', 'caption']);
IMPLIED_CLOSE.set('tfoot', ['thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'colgroup', 'caption']);
IMPLIED_CLOSE.set('colgroup', ['colgroup', 'caption']);
IMPLIED_CLOSE.set('caption', ['caption']);
IMPLIED_CLOSE.set('col', ['caption']);

/** 会「关掉未闭合 p」的块级起始标签（jsoup 的 p 处理规则）。 */
const CLOSES_P: string[] = [
  'address', 'article', 'aside', 'blockquote', 'details', 'div', 'dl', 'fieldset', 'figcaption',
  'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'main',
  'menu', 'nav', 'ol', 'p', 'pre', 'section', 'table', 'ul'
];

/** raw text 元素：内容不解析标签。 */
const RAW_TEXT_TAGS: string[] = ['script', 'style'];

export class HtmlParser {
  private readonly _html: string;
  private readonly _baseUri: string;
  private _pos: number = 0;

  constructor(html: string, baseUri: string) {
    this._html = html;
    this._baseUri = baseUri;
  }

  /** 解析整篇文档，返回带 html/head/body 骨架的 Document。 */
  parseDocument(): Document {
    const doc: Document = new Document(this._baseUri);
    doc.setLocation(this._baseUri);
    const html: Element = new Element('html', this._baseUri);
    const head: Element = new Element('head', this._baseUri);
    const body: Element = new Element('body', this._baseUri);
    doc.appendChild(html);
    html.appendChild(head);
    html.appendChild(body);

    const stack: Element[] = [body];
    const n: number = this._html.length;

    while (this._pos < n) {
      const lt: number = this._html.indexOf('<', this._pos);
      if (lt < 0) {
        this.appendText(stack[stack.length - 1], this._html.substring(this._pos));
        break;
      }
      if (lt > this._pos) {
        this.appendText(stack[stack.length - 1], this._html.substring(this._pos, lt));
      }
      this._pos = lt;

      if (this._html.startsWith('<!--', this._pos)) {
        // 注释直接丢弃（上游不读注释）
        const end: number = this._html.indexOf('-->', this._pos + 4);
        this._pos = end < 0 ? n : end + 3;
        continue;
      }
      if (this._html.startsWith('<!', this._pos)) {
        // doctype / CDATA 声明：跳到 '>'
        const end: number = this._html.indexOf('>', this._pos);
        this._pos = end < 0 ? n : end + 1;
        continue;
      }
      if (this._html.startsWith('</', this._pos)) {
        this.handleEndTag(stack);
        continue;
      }
      this.handleStartTag(stack, head, body);
    }
    return doc;
  }

  private appendText(parent: Element, raw: string): void {
    if (raw.length === 0) {
      return;
    }
    parent.appendChild(new TextNode(HtmlParser.decodeEntities(raw)));
  }

  private handleStartTag(stack: Element[], head: Element, body: Element): void {
    const n: number = this._html.length;
    // 标签名
    let i: number = this._pos + 1;
    let nameEnd: number = i;
    while (nameEnd < n && /[A-Za-z0-9:_\-]/.test(this._html.charAt(nameEnd))) {
      nameEnd++;
    }
    if (nameEnd === i) {
      // 不是标签（例如文本里的 "<"），当作文本
      this.appendText(stack[stack.length - 1], '<');
      this._pos++;
      return;
    }
    const tagName: string = this._html.substring(i, nameEnd).toLowerCase();
    i = nameEnd;

    // 属性
    const attrs: AttrPair[] = [];
    let selfClosing: boolean = false;
    while (i < n) {
      while (i < n && /\s/.test(this._html.charAt(i))) {
        i++;
      }
      if (i >= n) {
        break;
      }
      const ch: string = this._html.charAt(i);
      if (ch === '>') {
        i++;
        break;
      }
      if (ch === '/' && i + 1 < n && this._html.charAt(i + 1) === '>') {
        selfClosing = true;
        i += 2;
        break;
      }
      if (ch === '/') {
        i++;
        continue;
      }
      // 属性名
      let an: number = i;
      while (an < n && !/[\s=>\/]/.test(this._html.charAt(an))) {
        an++;
      }
      const attrName: string = this._html.substring(i, an);
      i = an;
      while (i < n && /\s/.test(this._html.charAt(i))) {
        i++;
      }
      if (i < n && this._html.charAt(i) === '=') {
        i++;
        while (i < n && /\s/.test(this._html.charAt(i))) {
          i++;
        }
        if (i < n && (this._html.charAt(i) === '"' || this._html.charAt(i) === '\'')) {
          const quote: string = this._html.charAt(i);
          const close: number = this._html.indexOf(quote, i + 1);
          const end: number = close < 0 ? n : close;
          attrs.push(new AttrPair(attrName, HtmlParser.decodeEntities(this._html.substring(i + 1, end))));
          i = close < 0 ? n : close + 1;
        } else {
          let av: number = i;
          while (av < n && !/[\s>]/.test(this._html.charAt(av))) {
            av++;
          }
          attrs.push(new AttrPair(attrName, HtmlParser.decodeEntities(this._html.substring(i, av))));
          i = av;
        }
      } else {
        attrs.push(new AttrPair(attrName, ''));
      }
    }
    this._pos = i;

    // 隐式闭合与隐式表格容器补全
    this.applyImpliedClose(stack, tagName);
    this.applyImpliedTableOpen(stack, tagName);
    const parent: Element = stack[stack.length - 1];

    // head 内的元素归 head：title/meta/link/style/script 出现在 body 前
    let target: Element = parent;
    if (parent === body && stack.length === 1 &&
      (tagName === 'title' || tagName === 'meta' || tagName === 'link' || tagName === 'style' ||
        tagName === 'base') && body.childCount() === 0) {
      target = head;
    }

    const el: Element = new Element(tagName, this._baseUri);
    for (let a = 0; a < attrs.length; a++) {
      el.setAttr(attrs[a].name, attrs[a].value);
    }
    target.appendChild(el);

    if (VOID_TAGS.indexOf(tagName) >= 0 || selfClosing) {
      return; // 空元素不入栈
    }

    if (RAW_TEXT_TAGS.indexOf(tagName) >= 0) {
      // raw text：直接吃到对应结束标签
      const closeTag: string = '</' + tagName;
      const closeIdx: number = this._html.toLowerCase().indexOf(closeTag, this._pos);
      const end: number = closeIdx < 0 ? this._html.length : closeIdx;
      const content: string = this._html.substring(this._pos, end);
      if (content.length > 0) {
        el.appendChild(new TextNode(content)); // raw text 不解码实体（与 HTML 规范一致）
      }
      this._pos = closeIdx < 0 ? this._html.length : this._html.indexOf('>', closeIdx) + 1;
      return;
    }
    stack.push(el);
  }

  private handleEndTag(stack: Element[]): void {
    const n: number = this._html.length;
    let i: number = this._pos + 2;
    let nameEnd: number = i;
    while (nameEnd < n && /[A-Za-z0-9:_\-]/.test(this._html.charAt(nameEnd))) {
      nameEnd++;
    }
    const tagName: string = this._html.substring(i, nameEnd).toLowerCase();
    const gt: number = this._html.indexOf('>', nameEnd);
    this._pos = gt < 0 ? n : gt + 1;
    if (tagName.length === 0) {
      return;
    }
    // 从栈顶向下找到同名元素；找不到则忽略（宽容）
    for (let s = stack.length - 1; s >= 1; s--) {
      if (stack[s].normalName() === tagName) {
        stack.length = s; // 弹出该元素及其上所有未闭合元素
        return;
      }
    }
  }

  private applyImpliedClose(stack: Element[], tagName: string): void {
    // p：遇块级元素先闭合
    if (CLOSES_P.indexOf(tagName) >= 0 && stack.length > 1 && stack[stack.length - 1].normalName() === 'p') {
      stack.length = stack.length - 1;
    }
    const rules: string[] | undefined = IMPLIED_CLOSE.get(tagName);
    if (rules === undefined) {
      return;
    }
    while (stack.length > 1) {
      const top: string = stack[stack.length - 1].normalName();
      if (rules.indexOf(top) >= 0) {
        stack.length = stack.length - 1;
      } else {
        break;
      }
    }
  }

  /** 对齐 HTML5 / Jsoup InTable：table 内直接出现 tr/td/th 时补 tbody，td/th 缺 tr 时补 tr，col 缺 colgroup 时补 colgroup。 */
  private applyImpliedTableOpen(stack: Element[], tagName: string): void {
    const top: string = stack[stack.length - 1].normalName();
    if (top === 'table') {
      if (tagName === 'col') {
        const colgroup: Element = new Element('colgroup', this._baseUri);
        stack[stack.length - 1].appendChild(colgroup);
        stack.push(colgroup);
        return;
      }
      if (tagName === 'tr' || tagName === 'td' || tagName === 'th') {
        const tbody: Element = new Element('tbody', this._baseUri);
        stack[stack.length - 1].appendChild(tbody);
        stack.push(tbody);
      }
    }
    const afterTop: string = stack[stack.length - 1].normalName();
    if ((tagName === 'td' || tagName === 'th') &&
      (afterTop === 'tbody' || afterTop === 'thead' || afterTop === 'tfoot')) {
      const tr: Element = new Element('tr', this._baseUri);
      stack[stack.length - 1].appendChild(tr);
      stack.push(tr);
    }
  }

  /** 实体解码（数值 + 常用命名实体）。 */
  static decodeEntities(s: string): string {
    if (s.indexOf('&') < 0) {
      return s;
    }
    return s.replace(/&(#x?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);/g,
      (match: string, body: string): string => {
        if (body.charAt(0) === '#') {
          const isHex: boolean = body.charAt(1) === 'x' || body.charAt(1) === 'X';
          const code: number = Number.parseInt(isHex ? body.substring(2) : body.substring(1),
            isHex ? 16 : 10);
          if (Number.isNaN(code) || code < 0 || code > 0x10ffff) {
            return match;
          }
          return String.fromCharCode(code);
        }
        const named: string | undefined = NAMED_ENTITIES.get(body);
        return named === undefined ? match : named;
      });
  }
}

class AttrPair {
  readonly name: string;
  readonly value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

/** 常用命名实体（HTML4 子集 + nbsp；上游页面主要出现这几个）。 */
const NAMED_ENTITIES: Map<string, string> = new Map<string, string>();
NAMED_ENTITIES.set('amp', '&');
NAMED_ENTITIES.set('lt', '<');
NAMED_ENTITIES.set('gt', '>');
NAMED_ENTITIES.set('quot', '"');
NAMED_ENTITIES.set('apos', '\'');
NAMED_ENTITIES.set('nbsp', '\u00a0');
NAMED_ENTITIES.set('copy', '\u00a9');
NAMED_ENTITIES.set('reg', '\u00ae');
NAMED_ENTITIES.set('hellip', '\u2026');
NAMED_ENTITIES.set('mdash', '\u2014');
NAMED_ENTITIES.set('ndash', '\u2013');
NAMED_ENTITIES.set('lsquo', '\u2018');
NAMED_ENTITIES.set('rsquo', '\u2019');
NAMED_ENTITIES.set('ldquo', '\u201c');
NAMED_ENTITIES.set('rdquo', '\u201d');
NAMED_ENTITIES.set('middot', '\u00b7');
NAMED_ENTITIES.set('times', '\u00d7');
NAMED_ENTITIES.set('deg', '\u00b0');
NAMED_ENTITIES.set('laquo', '\u00ab');
NAMED_ENTITIES.set('raquo', '\u00bb');
