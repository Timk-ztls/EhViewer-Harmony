/*
 * Copyright 2009-2020 Jonathan Hedley (jsoup)
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

import { HttpUrl } from '../okhttp/HttpUrl';

/**
 * jsoup 节点树等价层：Node / TextNode / Attributes / Element / Elements / Document。
 *
 * 为什么自建：ArkTS 无 jsoup（Java 库），而 23 个 parser 的 296 个调用点全部压在这套 API 上。
 * 实现范围由 `git grep` 统计驱动（见 MR 的频次表）：
 *   child 84 / text 54 / attr 32 / getElementById 29 / children 24 / getElementsByClass 18 /
 *   first 14 / html 6 / childNode 6 / select 4 / nextElementSibling 4 / hasClass 3 /
 *   ownText 2 / tagName 2 / eachAttr 2 / getAllElements 2 / getElementsByTag 1 / id 1 /
 *   textNodes 1 / absUrl 1 / previousElementSibling 1 / parent 1 / outerHtml 1 /
 *   selectFirst 1 / wholeText 1 / getElementsByAttribute 1
 *
 * 与原 jsoup 的语义对齐点（决定了解析结果逐字段一致）：
 *   1) text()：遍历 TextNode，做「空白折叠」（连续空白→单个空格）并在 block 元素/BR 前补空格
 *   2) ownText()：只看直接子 TextNode，规则同上
 *   3) 属性名大小写不敏感（HTML 语义），属性值保留原样（实体已在解析期解码）
 *   4) child(i) 只计元素，childNode(i) 计文本/元素全部节点 —— 上游这两者混用，必须区分
 *   5) Elements 是 Element 的有序集合，first()/get(i)/size()
 *
 * 未实现（上游未用到）：siblingElements 之外的选择器伪类、form 相关 API、OutputSettings 定制。
 */

/** 节点类型（对齐 jsoup 的 Node 继承结构，用常量 + 类层次表达）。 */
export abstract class Node {
  protected _parentNode: Node | null = null;
  protected _baseUri: string = '';

  parentNode(): Node | null {
    return this._parentNode;
  }

  /** 向下转型：父节点是 Element 才返回，否则 null（ArkTS 无泛型擦除后的 instanceof 便捷写法）。 */
  parent(): Element | null {
    const p: Node | null = this._parentNode;
    if (p instanceof Element) {
      return p as Element;
    }
    return null;
  }

  setParentNode(parent: Node | null): void {
    this._parentNode = parent;
  }

  baseUri(): string {
    return this._baseUri;
  }

  setBaseUri(baseUri: string): void {
    this._baseUri = baseUri;
  }

  abstract nodeName(): string;

  abstract cloneNode(): Node;
}

/** 文本节点。 */
export class TextNode extends Node {
  private readonly _text: string;

  constructor(text: string) {
    super();
    this._text = text;
  }

  nodeName(): string {
    return '#text';
  }

  /** 对齐 TextNode.getWholeText()：不折叠空白。 */
  getWholeText(): string {
    return this._text;
  }

  /** 对齐 TextNode.text()：空白折叠后的文本。 */
  text(): string {
    return TextNode.normaliseWhitespace(this._text);
  }

  isBlank(): boolean {
    return TextNode.normaliseWhitespace(this._text).length === 0;
  }

  /** 对齐 jsoup 的 StringUtil.normaliseWhitespace：`\s+` → 单个空格 + trim。 */
  static normaliseWhitespace(s: string): string {
    return s.replace(/[ \t\n\r\f]+/g, ' ').trim();
  }

  cloneNode(): Node {
    return new TextNode(this._text);
  }
}

/** 属性表（保序、名字大小写不敏感）。 */
export class Attributes {
  private _names: string[] = [];
  private _values: string[] = [];

  put(name: string, value: string): void {
    const lower: string = name.toLowerCase();
    for (let i = 0; i < this._names.length; i++) {
      if (this._names[i] === lower) {
        this._values[i] = value;
        return;
      }
    }
    this._names.push(lower);
    this._values.push(value);
  }

  hasKey(name: string): boolean {
    const lower: string = name.toLowerCase();
    return this._names.indexOf(lower) >= 0;
  }

  /** 对齐 Attributes.get(String)：不存在返回空串（jsoup 的 Element.attr 也是空串）。 */
  get(name: string): string {
    const lower: string = name.toLowerCase();
    const idx: number = this._names.indexOf(lower);
    return idx < 0 ? '' : this._values[idx];
  }

  remove(name: string): void {
    const lower: string = name.toLowerCase();
    const idx: number = this._names.indexOf(lower);
    if (idx >= 0) {
      this._names.splice(idx, 1);
      this._values.splice(idx, 1);
    }
  }

  size(): number {
    return this._names.length;
  }

  key(index: number): string {
    return this._names[index];
  }

  value(index: number): string {
    return this._values[index];
  }

  cloneAttributes(): Attributes {
    const a: Attributes = new Attributes();
    for (let i = 0; i < this._names.length; i++) {
      a.put(this._names[i], this._values[i]);
    }
    return a;
  }
}

/** jsoup 的 block 元素集合（决定 text() 的空格插入位置）。 */
const BLOCK_TAGS: string[] = [
  'html', 'head', 'body', 'frameset', 'script', 'noscript', 'style', 'meta', 'link', 'title',
  'frame', 'noframes', 'section', 'nav', 'aside', 'hgroup', 'header', 'footer', 'p', 'h1', 'h2', 'h3',
  'h4', 'h5', 'h6', 'ul', 'ol', 'pre', 'div', 'blockquote', 'hr', 'address', 'figure', 'figcaption',
  'form', 'fieldset', 'ins', 'del', 'dl', 'dt', 'dd', 'li', 'table', 'caption', 'colgroup', 'col',
  'thead', 'tfoot', 'tbody', 'tr', 'th', 'td', 'video', 'audio', 'canvas', 'details', 'menu', 'plaintext',
  'template', 'article', 'main', 'svg', 'math', 'center', 'dir', 'applet', 'marquee', 'listing', 'xmp'
];

/** 元素节点。 */
export class Element extends Node {
  private _tagName: string;
  private readonly _attributes: Attributes = new Attributes();
  private readonly _childNodes: Node[] = [];

  constructor(tagName: string, baseUri: string = '') {
    super();
    this._tagName = tagName.toLowerCase();
    this._baseUri = baseUri;
  }

  nodeName(): string {
    return this._tagName;
  }

  /** 对齐 Element.tagName()：HTML 文档返回大写标签名（jsoup 行为）。 */
  tagName(): string {
    return this._tagName.toUpperCase();
  }

  /** 内部小写形式（选择器匹配用）。 */
  normalName(): string {
    return this._tagName;
  }

  /** 对齐 Element.id()：无 id 属性返回空串。 */
  id(): string {
    return this._attributes.get('id');
  }

  /** 对齐 Element.className()：class 属性原文。 */
  className(): string {
    return this._attributes.get('class');
  }

  /** 对齐 Element.hasClass(String)：按空白分隔逐个比对。 */
  hasClass(className: string): boolean {
    const cls: string = this.className();
    if (cls.length === 0) {
      return false;
    }
    const parts: string[] = cls.split(/\s+/);
    for (let i = 0; i < parts.length; i++) {
      if (parts[i] === className) {
        return true;
      }
    }
    return false;
  }

  classNames(): string[] {
    const cls: string = this.className();
    if (cls.length === 0) {
      return [];
    }
    const parts: string[] = cls.split(/\s+/);
    const out: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        out.push(parts[i]);
      }
    }
    return out;
  }

  attributes(): Attributes {
    return this._attributes;
  }

  /** 对齐 Element.attr(String)：属性不存在返回 ""。 */
  attr(name: string): string {
    return this._attributes.get(name);
  }

  hasAttr(name: string): boolean {
    return this._attributes.hasKey(name);
  }

  setAttr(name: string, value: string): void {
    this._attributes.put(name, value);
  }

  /** 对齐 Element.absUrl(String)：相对地址按 baseUri 解析；解析失败返回 ""。 */
  absUrl(name: string): string {
    const rel: string = this._attributes.get(name);
    if (rel.length === 0) {
      return '';
    }
    if (rel.indexOf('://') > 0 || rel.startsWith('data:') || rel.startsWith('mailto:')) {
      return rel;
    }
    const base: HttpUrl | null = HttpUrl.parse(this._baseUri);
    if (base === null) {
      return '';
    }
    const resolved: HttpUrl | null = base.resolve(rel);
    return resolved === null ? '' : resolved.toString();
  }

  /** 对齐 Element.html()：内部 HTML。 */
  html(): string {
    const parts: string[] = [];
    for (let i = 0; i < this._childNodes.length; i++) {
      parts.push(Element.outerHtmlOf(this._childNodes[i]));
    }
    return parts.join('');
  }

  /** 对齐 Element.outerHtml()：自身 HTML（含标签）。 */
  outerHtml(): string {
    return Element.outerHtmlOf(this);
  }

  /** 对齐 Element.val()：表单控件的值。 */
  val(): string {
    if (this._tagName === 'textarea') {
      return this.text();
    }
    if (this._tagName === 'option') {
      const v: string = this._attributes.get('value');
      return v.length > 0 ? v : this.text();
    }
    return this._attributes.get('value');
  }

  /** 对齐 Element.data()：script/style 的内容。 */
  data(): string {
    const parts: string[] = [];
    for (let i = 0; i < this._childNodes.length; i++) {
      const n: Node = this._childNodes[i];
      if (n instanceof TextNode) {
        parts.push((n as TextNode).getWholeText());
      }
    }
    return parts.join('');
  }

  childNodes(): Node[] {
    return this._childNodes.slice();
  }

  childNode(index: number): Node | null {
    if (index < 0 || index >= this._childNodes.length) {
      return null;
    }
    return this._childNodes[index];
  }

  /** 对齐 Element.child(int)：只计元素子节点。 */
  child(index: number): Element | null {
    const kids: Elements = this.children();
    if (index < 0 || index >= kids.size()) {
      return null;
    }
    return kids.get(index);
  }

  /** 对齐 Element.children()：元素子节点集合（不含文本）。 */
  children(): Elements {
    const list: Element[] = [];
    for (let i = 0; i < this._childNodes.length; i++) {
      const n: Node = this._childNodes[i];
      if (n instanceof Element) {
        list.push(n as Element);
      }
    }
    return new Elements(list);
  }

  childCount(): number {
    return this._childNodes.length;
  }

  appendChild(child: Node): Element {
    child.setParentNode(this);
    this._childNodes.push(child);
    return this;
  }

  appendText(text: string): Element {
    return this.appendChild(new TextNode(text));
  }

  removeChild(child: Node): void {
    const idx: number = this._childNodes.indexOf(child);
    if (idx >= 0) {
      this._childNodes.splice(idx, 1);
      child.setParentNode(null);
    }
  }

  /** 对齐 Element.remove()：从父节点摘除自己。 */
  remove(): void {
    const p: Node | null = this._parentNode;
    if (p instanceof Element) {
      (p as Element).removeChild(this);
    }
  }

  /** 对齐 Element.empty()。 */
  empty(): Element {
    for (let i = 0; i < this._childNodes.length; i++) {
      this._childNodes[i].setParentNode(null);
    }
    this._childNodes.length = 0;
    return this;
  }

  /** 对齐 Element.text()：空白折叠 + block/BR 前补空格。 */
  text(): string {
    const sb: string[] = [];
    Element.collectText(this, sb);
    return sb.join('');
  }

  /** 对齐 Element.ownText()：只看直接子 TextNode。 */
  ownText(): string {
    const sb: string[] = [];
    for (let i = 0; i < this._childNodes.length; i++) {
      const n: Node = this._childNodes[i];
      if (n instanceof TextNode) {
        Element.appendNormalisedText(sb, (n as TextNode).getWholeText());
      } else if (n instanceof Element) {
        const el: Element = n as Element;
        if (sb.length > 0 && (Element.isBlock(el) || el.normalName() === 'br') &&
          !Element.lastCharIsWhitespace(sb)) {
          sb.push(' ');
        }
      }
    }
    return sb.join('');
  }

  /** 对齐 Element.wholeText()（仅 Nodes 层用）。 */
  wholeText(): string {
    const sb: string[] = [];
    const walk = (el: Element): void => {
      const kids: Node[] = el.childNodes();
      for (let i = 0; i < kids.length; i++) {
        const n: Node = kids[i];
        if (n instanceof TextNode) {
          sb.push((n as TextNode).getWholeText());
        } else if (n instanceof Element) {
          walk(n as Element);
        }
      }
    };
    walk(this);
    return sb.join('');
  }

  /** 对齐 Element.textNodes()：直接子 TextNode。 */
  textNodes(): TextNode[] {
    const out: TextNode[] = [];
    for (let i = 0; i < this._childNodes.length; i++) {
      const n: Node = this._childNodes[i];
      if (n instanceof TextNode) {
        out.push(n as TextNode);
      }
    }
    return out;
  }

  // ---- 查找 ----

  /** 对齐 Element.getElementById：只在后代中找第一个。 */
  getElementById(id: string): Element | null {
    const all: Elements = this.getAllElements();
    for (let i = 0; i < all.size(); i++) {
      const e: Element = all.get(i);
      if (e.id() === id) {
        return e;
      }
    }
    return null;
  }

  /** 对齐 Element.getElementsByClass：多个类名需全部命中。 */
  getElementsByClass(className: string): Elements {
    const want: string[] = className.trim().split(/\s+/);
    const acc: Evaluator = new Evaluator();
    const out: Element[] = [];
    acc.collect(this, (e: Element): boolean => {
      for (let i = 0; i < want.length; i++) {
        if (want[i].length > 0 && !e.hasClass(want[i])) {
          return false;
        }
      }
      return true;
    }, out);
    return new Elements(out);
  }

  getElementsByTag(tagName: string): Elements {
    const lower: string = tagName.toLowerCase();
    const acc: Evaluator = new Evaluator();
    const out: Element[] = [];
    acc.collect(this, (e: Element): boolean => e.normalName() === lower, out);
    return new Elements(out);
  }

  /** 对齐 Element.getElementsByAttribute(String key)：按属性名存在性过滤。 */
  getElementsByAttribute(key: string): Elements {
    const acc: Evaluator = new Evaluator();
    const out: Element[] = [];
    acc.collect(this, (e: Element): boolean => e.hasAttr(key), out);
    return new Elements(out);
  }

  /** 对齐 Element.getElementsByAttributeValue(String key, String value)。 */
  getElementsByAttributeValue(key: string, value: string): Elements {
    const acc: Evaluator = new Evaluator();
    const out: Element[] = [];
    acc.collect(this, (e: Element): boolean => e.attr(key) === value, out);
    return new Elements(out);
  }

  /** 对齐 Element.getAllElements()：自身 + 全部后代，文档序。 */
  getAllElements(): Elements {
    const out: Element[] = [];
    const walk = (el: Element): void => {
      out.push(el);
      for (let i = 0; i < el._childNodes.length; i++) {
        const n: Node = el._childNodes[i];
        if (n instanceof Element) {
          walk(n as Element);
        }
      }
    };
    walk(this);
    return new Elements(out);
  }

  /** 对齐 Element.select(String cssQuery)：后代选择（不包含自身）。 */
  select(cssQuery: string): Elements {
    const out: Element[] = [];
    Selector.select(cssQuery, this, out);
    return new Elements(out);
  }

  /** 对齐 Element.selectFirst(String cssQuery)。 */
  selectFirst(cssQuery: string): Element | null {
    const found: Elements = this.select(cssQuery);
    return found.size() > 0 ? found.get(0) : null;
  }

  /** 对齐 Element.nextElementSibling()。 */
  nextElementSibling(): Element | null {
    const p: Node | null = this._parentNode;
    if (!(p instanceof Element)) {
      return null;
    }
    const kids: Node[] = (p as Element)._childNodes;
    const idx: number = kids.indexOf(this);
    for (let i = idx + 1; i < kids.length; i++) {
      if (kids[i] instanceof Element) {
        return kids[i] as Element;
      }
    }
    return null;
  }

  /** 对齐 Element.previousElementSibling()。 */
  previousElementSibling(): Element | null {
    const p: Node | null = this._parentNode;
    if (!(p instanceof Element)) {
      return null;
    }
    const kids: Node[] = (p as Element)._childNodes;
    const idx: number = kids.indexOf(this);
    for (let i = idx - 1; i >= 0; i--) {
      if (kids[i] instanceof Element) {
        return kids[i] as Element;
      }
    }
    return null;
  }

  /** 对齐 Element.elementSiblingIndex()。 */
  elementSiblingIndex(): number {
    const p: Node | null = this._parentNode;
    if (!(p instanceof Element)) {
      return 0;
    }
    const kids: Node[] = (p as Element)._childNodes;
    let n: number = 0;
    for (let i = 0; i < kids.length; i++) {
      if (kids[i] === this) {
        return n;
      }
      if (kids[i] instanceof Element) {
        n++;
      }
    }
    return n;
  }

  cloneNode(): Node {
    const e: Element = new Element(this._tagName, this._baseUri);
    e.setAttributes(this._attributes.cloneAttributes());
    for (let i = 0; i < this._childNodes.length; i++) {
      e.appendChild(this._childNodes[i].cloneNode());
    }
    return e;
  }

  /** 对齐 Element.clone()（返回 Element）。 */
  clone(): Element {
    return this.cloneNode() as Element;
  }

  private setAttributes(a: Attributes): void {
    // Attributes 无 clear，逐项拷贝即可（克隆场景）
    for (let i = 0; i < a.size(); i++) {
      this._attributes.put(a.key(i), a.value(i));
    }
  }

  // ---- 静态辅助 ----

  static isBlock(el: Element): boolean {
    return BLOCK_TAGS.indexOf(el.normalName()) >= 0;
  }

  private static lastCharIsWhitespace(sb: string[]): boolean {
    if (sb.length === 0) {
      return false;
    }
    const last: string = sb[sb.length - 1];
    if (last.length === 0) {
      return false;
    }
    const ch: string = last.charAt(last.length - 1);
    return ch === ' ' || ch === '\n' || ch === '\t' || ch === '\r';
  }

  /** 对齐 jsoup 的 appendNormalisedText：折叠空白，且不重复插入首空格。 */
  static appendNormalisedText(sb: string[], text: string): void {
    const normalised: string = TextNode.normaliseWhitespace(text);
    if (normalised.length === 0) {
      return;
    }
    if (Element.lastCharIsWhitespace(sb)) {
      // 已有尾空格：跳过新串的首字符（jsoup 的 same as last)
      const s: string = normalised.charAt(0) === ' ' ? normalised.substring(1) : normalised;
      sb.push(s);
    } else {
      sb.push(normalised);
    }
  }

  /** text() 的遍历体：TextNode 取文本；Element 是 block/BR 时补空格后递归。 */
  private static collectText(el: Element, sb: string[]): void {
    const kids: Node[] = el._childNodes;
    for (let i = 0; i < kids.length; i++) {
      const n: Node = kids[i];
      if (n instanceof TextNode) {
        const t: TextNode = n as TextNode;
        if (el.normalName() !== 'script' && el.normalName() !== 'style') {
          Element.appendNormalisedText(sb, t.getWholeText());
        }
      } else if (n instanceof Element) {
        const child: Element = n as Element;
        if (sb.length > 0 && (Element.isBlock(child) || child.normalName() === 'br') &&
          !Element.lastCharIsWhitespace(sb)) {
          sb.push(' ');
        }
        Element.collectText(child, sb);
      }
    }
  }

  static outerHtmlOf(node: Node): string {
    if (node instanceof TextNode) {
      return escapeText((node as TextNode).getWholeText());
    }
    const el: Element = node as Element;
    const sb: string[] = [];
    sb.push('<' + el.normalName());
    const attrs: Attributes = el.attributes();
    for (let i = 0; i < attrs.size(); i++) {
      sb.push(' ' + attrs.key(i) + '="' + escapeAttr(attrs.value(i)) + '"');
    }
    sb.push('>');
    if (VOID_TAGS.indexOf(el.normalName()) >= 0) {
      return sb.join('');
    }
    for (let i = 0; i < el._childNodes.length; i++) {
      sb.push(Element.outerHtmlOf(el._childNodes[i]));
    }
    sb.push('</' + el.normalName() + '>');
    return sb.join('');
  }
}

export const VOID_TAGS: string[] = [
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source',
  'track', 'wbr', 'keygen', 'command'
];

function escapeText(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function escapeAttr(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
}

/** 元素集合（对齐 org.jsoup.select.Elements）。 */
export class Elements {
  private readonly _list: Element[];

  constructor(list: Element[]) {
    this._list = list;
  }

  size(): number {
    return this._list.length;
  }

  isEmpty(): boolean {
    return this._list.length === 0;
  }

  get(index: number): Element {
    return this._list[index];
  }

  first(): Element | null {
    return this._list.length === 0 ? null : this._list[0];
  }

  last(): Element | null {
    return this._list.length === 0 ? null : this._list[this._list.length - 1];
  }

  /** 对齐 Elements.text()：各元素的 text() 以空格连接。 */
  text(): string {
    const sb: string[] = [];
    for (let i = 0; i < this._list.length; i++) {
      const t: string = this._list[i].text();
      if (t.length > 0) {
        sb.push(t);
      }
    }
    return sb.join(' ');
  }

  /** 对齐 Elements.attr(String)：第一个元素的属性值。 */
  attr(name: string): string {
    for (let i = 0; i < this._list.length; i++) {
      if (this._list[i].hasAttr(name)) {
        return this._list[i].attr(name);
      }
    }
    return '';
  }

  hasAttr(name: string): boolean {
    for (let i = 0; i < this._list.length; i++) {
      if (this._list[i].hasAttr(name)) {
        return true;
      }
    }
    return false;
  }

  /** 对齐 Elements.eachAttr(String)：每个元素该属性的值（无该属性用空串占位，与 jsoup 一致：只收有值的）。 */
  eachAttr(name: string): string[] {
    const out: string[] = [];
    for (let i = 0; i < this._list.length; i++) {
      if (this._list[i].hasAttr(name)) {
        out.push(this._list[i].attr(name));
      }
    }
    return out;
  }

  /** 对齐 Elements.eachText()。 */
  eachText(): string[] {
    const out: string[] = [];
    for (let i = 0; i < this._list.length; i++) {
      out.push(this._list[i].text());
    }
    return out;
  }

  select(cssQuery: string): Elements {
    const out: Element[] = [];
    for (let i = 0; i < this._list.length; i++) {
      Selector.select(cssQuery, this._list[i], out);
    }
    return new Elements(out);
  }

  toArray(): Element[] {
    return this._list.slice();
  }
}

/** 文档（对齐 org.jsoup.nodes.Document）。 */
export class Document extends Element {
  private _location: string;

  constructor(baseUri: string) {
    super('#root', baseUri);
    this._location = baseUri;
  }

  nodeName(): string {
    return '#document';
  }

  /** 对齐 Document.location()。 */
  location(): string {
    return this._location;
  }

  setLocation(location: string): void {
    this._location = location;
  }

  /** 对齐 Document.body()：不存在时返回 null。 */
  body(): Element | null {
    const html: Element | null = this.firstElementChildByName('html');
    if (html === null) {
      return null;
    }
    const kids: Elements = (html as Element).children();
    for (let i = 0; i < kids.size(); i++) {
      if (kids.get(i).normalName() === 'body') {
        return kids.get(i);
      }
    }
    return null;
  }

  /** 对齐 Document.head()。 */
  head(): Element | null {
    const html: Element | null = this.firstElementChildByName('html');
    if (html === null) {
      return null;
    }
    const kids: Elements = (html as Element).children();
    for (let i = 0; i < kids.size(); i++) {
      if (kids.get(i).normalName() === 'head') {
        return kids.get(i);
      }
    }
    return null;
  }

  private firstElementChildByName(name: string): Element | null {
    const kids: Elements = this.children();
    for (let i = 0; i < kids.size(); i++) {
      if (kids.get(i).normalName() === name) {
        return kids.get(i);
      }
    }
    return null;
  }

  cloneNode(): Node {
    const d: Document = new Document(this._location);
    const kids: Node[] = this.childNodes();
    for (let i = 0; i < kids.length; i++) {
      d.appendChild(kids[i].cloneNode());
    }
    return d;
  }
}

// =====================================================================================
// CSS 选择器引擎（jsoup 的 Selector/Evaluator 等价子集）
// 放在同一文件的原因：ArkTS 对循环 import 的容忍度低（Nodes/Selectors 互相引用），
// 合到一处避免 cycle；对上层 API 形状没有影响（index.ets 统一导出）。
//
// 上游实际用到的语法（全量 grep，见 MR）：
//   div:nth-child(1)>img
//   div:nth-child(2)>div:nth-child(2)>div:nth-child(2)
//   div:nth-child(2)>div:nth-child(2)
//   #chd + p
//   textarea[name=commenttext_edit]
// 即：tag / #id / .class / [attr] / [attr=val] / :nth-child(n) / > / + / 后代空格。
// 另外补上 :first-child、:last-child、[attr^=]、[attr$=]、[attr*=]、:not(simple)，
// 这些是移植其余 parser 时最可能遇到的扩展，实现成本低。
// =====================================================================================

/** 组合子类型。 */
enum Combinator {
  DESCENDANT = ' ',
  CHILD = '>',
  ADJACENT = '+',
  SIBLING = '~'
}

/** 单个复合选择器（如 `div.foo#bar[attr=val]:nth-child(2)`）。 */
export class CompoundSelector {
  tag: string | null = null;
  id: string | null = null;
  classes: string[] = [];
  attrs: AttrFilter[] = [];
  nthChild: number = -1;
  firstChild: boolean = false;
  lastChild: boolean = false;
  notFilter: CompoundSelector | null = null;

  /** 判断单元素是否匹配本复合选择器（不考虑祖先/兄弟）。 */
  matches(el: Element): boolean {
    if (this.tag !== null && el.normalName() !== this.tag) {
      return false;
    }
    if (this.id !== null && el.id() !== this.id) {
      return false;
    }
    for (let i = 0; i < this.classes.length; i++) {
      if (!el.hasClass(this.classes[i])) {
        return false;
      }
    }
    for (let i = 0; i < this.attrs.length; i++) {
      if (!this.attrs[i].matches(el)) {
        return false;
      }
    }
    if (this.nthChild > 0 && el.elementSiblingIndex() + 1 !== this.nthChild) {
      return false;
    }
    if (this.firstChild && el.elementSiblingIndex() !== 0) {
      return false;
    }
    if (this.lastChild) {
      const next: Element | null = el.nextElementSibling();
      if (next !== null) {
        return false;
      }
    }
    if (this.notFilter !== null && (this.notFilter as CompoundSelector).matches(el)) {
      return false;
    }
    return true;
  }
}

/** 属性过滤（[attr] / [attr=val] / [attr^=val] / [attr$=val] / [attr*=val]）。 */
export class AttrFilter {
  readonly key: string;
  readonly op: string;
  readonly value: string;

  constructor(key: string, op: string, value: string) {
    this.key = key;
    this.op = op;
    this.value = value;
  }

  matches(el: Element): boolean {
    if (!el.hasAttr(this.key)) {
      return false;
    }
    if (this.op === '') {
      return true;
    }
    const v: string = el.attr(this.key);
    switch (this.op) {
      case '=':
        return v === this.value;
      case '^=':
        return v.startsWith(this.value);
      case '$=':
        return v.endsWith(this.value);
      case '*=':
        return v.indexOf(this.value) >= 0;
      case '~=': {
        const parts: string[] = v.split(/\s+/);
        return parts.indexOf(this.value) >= 0;
      }
      default:
        return false;
    }
  }
}

/** 选择器链的一个环节：组合子 + 复合选择器。 */
export class SelectorStep {
  readonly combinator: Combinator;
  readonly compound: CompoundSelector;

  constructor(combinator: Combinator, compound: CompoundSelector) {
    this.combinator = combinator;
    this.compound = compound;
  }
}

/** 选择器引擎。 */
export class Selector {
  /**
   * 对齐 Element.select(String)：在 root 的后代中选择（不含 root 自身），文档序。
   * 匹配策略：右到左（先匹配最右复合选择器，再回溯祖先/兄弟），与 jsoup 一致。
   */
  static select(query: string, root: Element, out: Element[]): void {
    const steps: SelectorStep[] = Selector.parse(query);
    if (steps.length === 0) {
      return;
    }
    const all: Element[] = [];
    Selector.collectDescendants(root, all);
    for (let i = 0; i < all.length; i++) {
      if (Selector.matchesChain(all[i], steps, steps.length - 1)) {
        if (out.indexOf(all[i]) < 0) {
          out.push(all[i]);
        }
      }
    }
  }

  /** 解析选择器字符串为步骤链；语法错误抛 Error（与 jsoup 的 SelectorParseException 对应）。 */
  static parse(query: string): SelectorStep[] {
    const q: string = query.trim();
    if (q.length === 0) {
      throw new Error('SelectorParseException: empty query');
    }
    const steps: SelectorStep[] = [];
    let i: number = 0;
    let combinator: Combinator = Combinator.DESCENDANT;
    while (i < q.length) {
      // 跳过空白（后代组合子）
      let sawSpace: boolean = false;
      while (i < q.length && /\s/.test(q.charAt(i))) {
        sawSpace = true;
        i++;
      }
      if (i >= q.length) {
        break;
      }
      const ch: string = q.charAt(i);
      if (ch === '>' || ch === '+' || ch === '~') {
        combinator = ch === '>' ? Combinator.CHILD : (ch === '+' ? Combinator.ADJACENT : Combinator.SIBLING);
        i++;
        while (i < q.length && /\s/.test(q.charAt(i))) {
          i++;
        }
        continue;
      }
      if (sawSpace && steps.length > 0) {
        combinator = Combinator.DESCENDANT;
      }
      const parsed: ParseResult = Selector.parseCompound(q, i);
      steps.push(new SelectorStep(combinator, parsed.compound));
      i = parsed.next;
      combinator = Combinator.DESCENDANT;
    }
    return steps;
  }

  private static parseCompound(q: string, start: number): ParseResult {
    const c: CompoundSelector = new CompoundSelector();
    let i: number = start;
    let consumed: boolean = false;
    while (i < q.length) {
      const ch: string = q.charAt(i);
      if (/\s/.test(ch) || ch === '>' || ch === '+' || ch === '~' || ch === ',') {
        break;
      }
      if (ch === '*') {
        c.tag = null;
        i++;
        consumed = true;
        continue;
      }
      if (ch === '#') {
        const end: number = Selector.readIdent(q, i + 1);
        c.id = q.substring(i + 1, end);
        i = end;
        consumed = true;
        continue;
      }
      if (ch === '.') {
        const end: number = Selector.readIdent(q, i + 1);
        c.classes.push(q.substring(i + 1, end));
        i = end;
        consumed = true;
        continue;
      }
      if (ch === '[') {
        const close: number = q.indexOf(']', i);
        if (close < 0) {
          throw new Error(`SelectorParseException: unclosed attribute selector in "${q}"`);
        }
        c.attrs.push(Selector.parseAttr(q.substring(i + 1, close)));
        i = close + 1;
        consumed = true;
        continue;
      }
      if (ch === ':') {
        const end: number = Selector.readIdent(q, i + 1);
        const name: string = q.substring(i + 1, end).toLowerCase();
        i = end;
        if (name === 'nth-child') {
          if (q.charAt(i) !== '(') {
            throw new Error('SelectorParseException: nth-child requires (n)');
          }
          const close: number = q.indexOf(')', i);
          if (close < 0) {
            throw new Error('SelectorParseException: unclosed nth-child');
          }
          const arg: string = q.substring(i + 1, close).trim().toLowerCase();
          i = close + 1;
          if (arg === 'odd') {
            c.nthChild = -2; // 奇数：1,3,5...（用步长编码，见 matches）
          } else if (arg === 'even') {
            c.nthChild = -3;
          } else {
            const n: number = Number.parseInt(arg, 10);
            if (Number.isNaN(n)) {
              throw new Error(`SelectorParseException: unsupported nth-child(${arg})`);
            }
            c.nthChild = n;
          }
        } else if (name === 'first-child') {
          c.firstChild = true;
        } else if (name === 'last-child') {
          c.lastChild = true;
        } else if (name === 'not') {
          if (q.charAt(i) !== '(') {
            throw new Error('SelectorParseException: not() requires a selector');
          }
          const close: number = q.indexOf(')', i);
          if (close < 0) {
            throw new Error('SelectorParseException: unclosed not()');
          }
          const inner: string = q.substring(i + 1, close).trim();
          i = close + 1;
          c.notFilter = Selector.parseCompound(inner, 0).compound;
        } else {
          throw new Error(`SelectorParseException: unsupported pseudo-class :${name}`);
        }
        consumed = true;
        continue;
      }
      if (/[A-Za-z_]/.test(ch)) {
        const end: number = Selector.readIdent(q, i);
        c.tag = q.substring(i, end).toLowerCase();
        i = end;
        consumed = true;
        continue;
      }
      throw new Error(`SelectorParseException: unexpected char '${ch}' in "${q}"`);
    }
    if (!consumed) {
      throw new Error(`SelectorParseException: empty compound selector in "${q}"`);
    }
    return new ParseResult(c, i);
  }

  private static parseAttr(body: string): AttrFilter {
    const s: string = body.trim();
    const ops: string[] = ['^=', '$=', '*=', '~=', '='];
    for (let i = 0; i < ops.length; i++) {
      const idx: number = s.indexOf(ops[i]);
      if (idx > 0) {
        const key: string = s.substring(0, idx).trim().toLowerCase();
        let val: string = s.substring(idx + ops[i].length).trim();
        if (val.length >= 2 && ((val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith('\'') && val.endsWith('\'')))) {
          val = val.substring(1, val.length - 1);
        }
        return new AttrFilter(key, ops[i], val);
      }
    }
    return new AttrFilter(s.toLowerCase(), '', '');
  }

  private static readIdent(q: string, start: number): number {
    let i: number = start;
    while (i < q.length && /[A-Za-z0-9_\-]/.test(q.charAt(i))) {
      i++;
    }
    return i;
  }

  /** 右到左匹配：steps[idx] 是当前要匹配的复合选择器。 */
  private static matchesChain(el: Element, steps: SelectorStep[], idx: number): boolean {
    const step: SelectorStep = steps[idx];
    if (!step.compound.matches(el)) {
      return false;
    }
    if (idx === 0) {
      return true;
    }
    const prev: SelectorStep = steps[idx];
    if (prev.combinator === Combinator.CHILD) {
      const p: Element | null = el.parent();
      return p !== null && Selector.matchesChain(p, steps, idx - 1);
    }
    if (prev.combinator === Combinator.ADJACENT) {
      const sib: Element | null = el.previousElementSibling();
      return sib !== null && Selector.matchesChain(sib, steps, idx - 1);
    }
    if (prev.combinator === Combinator.SIBLING) {
      let sib: Element | null = el.previousElementSibling();
      while (sib !== null) {
        if (Selector.matchesChain(sib, steps, idx - 1)) {
          return true;
        }
        sib = sib.previousElementSibling();
      }
      return false;
    }
    // DESCENDANT：任一祖先匹配
    let anc: Element | null = el.parent();
    while (anc !== null) {
      if (Selector.matchesChain(anc, steps, idx - 1)) {
        return true;
      }
      anc = anc.parent();
    }
    return false;
  }

  /** 文档序收集 root 的全部后代（不含 root）。 */
  static collectDescendants(root: Element, out: Element[]): void {
    const kids: Element[] = root.children().toArray();
    for (let i = 0; i < kids.length; i++) {
      out.push(kids[i]);
      Selector.collectDescendants(kids[i], out);
    }
  }
}

class ParseResult {
  readonly compound: CompoundSelector;
  readonly next: number;

  constructor(compound: CompoundSelector, next: number) {
    this.compound = compound;
    this.next = next;
  }
}

/** 供 Nodes 内部复用的小工具（等价 jsoup 的 Evaluator.AllElements 遍历语义）。 */
export class Evaluator {
  /** 文档序遍历 root 的后代，predicate 为 true 的进入 out。 */
  collect(root: Element, predicate: (e: Element) => boolean, out: Element[]): void {
    const kids: Element[] = root.children().toArray();
    for (let i = 0; i < kids.length; i++) {
      const e: Element = kids[i];
      if (predicate(e)) {
        out.push(e);
      }
      this.collect(e, predicate, out);
    }
  }
}