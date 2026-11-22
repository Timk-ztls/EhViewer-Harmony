/*
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

/**
 * hippo/jsoup —— jsoup 1.15.4 的 ArkTS 等价子集。
 *
 * 范围由上游 grep 统计决定（296 个 jsoup 专有调用点，13 个文件）：
 *   child 84 / text 54 / attr 32 / getElementById 29 / children 24 /
 *   getElementsByClass 18 / first 14 / html 6 / childNode 6 / select 4  ← top-10 覆盖 91.6%
 *   nextElementSibling 4 / hasClass 3 / ownText 2 / tagName 2 / eachAttr 2 /
 *   getAllElements 2 / getElementsByTag 1 / id 1 / textNodes 1 / absUrl 1 /
 *   previousElementSibling 1 / parent 1 / outerHtml 1 / selectFirst 1 / wholeText 1 /
 *   getElementsByAttribute 1
 *
 * 文件划分：
 *   Nodes.ets       —— Node / TextNode / Attributes / Element / Elements / Document + CSS 选择器引擎
 *   Parser.ets      —— Jsoup.parse（宽容 HTML 解析，含隐式闭合与实体解码）
 *   NodeVisitor.ets —— NodeTraversor / NodeVisitor（GalleryDetailParser 的 preview 遍历）
 *
 * 命名差异（ArkTS 无重载 / 无静态嵌套类）：
 *   Jsoup.parse(html, baseUri)      → Jsoup.parseWithBaseUri(html, baseUri)
 *   Elements.get(i)                 → 保留（array 语义）
 *   NodeTraversor.traverse(v, root) → 保留
 */
export {
  Node, TextNode, Attributes, Element, Elements, Document, VOID_TAGS,
  Selector, CompoundSelector, AttrFilter, SelectorStep, Evaluator
} from './Nodes';
export { Jsoup, HtmlParser } from './Parser';
export { NodeVisitor, NodeTraversor } from './NodeVisitor';
