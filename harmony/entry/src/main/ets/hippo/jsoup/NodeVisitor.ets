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

import { Element, Node, TextNode } from './Nodes';

/**
 * jsoup 的 NodeVisitor / NodeTraversor 等价层。
 *
 * 上游唯一使用点：`GalleryDetailParser:566` 用 NodeTraversor.traverse 遍历
 * preview 区，把文本节点按出现顺序拼成 `previewPages` 的页码/提示文本。
 * 因此只需要 head/tail 两个回调 + 深度参数，不需要过滤器与替换能力。
 */
export interface NodeVisitor {
  /** 进入节点（前序）。 */
  head(node: Node, depth: number): void;

  /** 离开节点（后序）。 */
  tail(node: Node, depth: number): void;
}

export class NodeTraversor {
  /** 对齐 NodeTraversor.traverse(NodeVisitor, Node)。 */
  static traverse(visitor: NodeVisitor, root: Node): void {
    NodeTraversor.walk(visitor, root, 0);
  }

  private static walk(visitor: NodeVisitor, node: Node, depth: number): void {
    visitor.head(node, depth);
    if (node instanceof Element) {
      const kids: Node[] = (node as Element).childNodes();
      for (let i = 0; i < kids.length; i++) {
        NodeTraversor.walk(visitor, kids[i], depth + 1);
      }
    }
    visitor.tail(node, depth);
  }

  /**
   * 便利封装：按文档序收集文本节点内容（上游 GalleryDetailParser 的用法）。
   * 单独提供是因为 ArkTS 里写匿名 visitor 类比较啰嗦，parser 侧可直接用。
   */
  static collectTextNodes(root: Node): string[] {
    const out: string[] = [];
    const walk = (node: Node): void => {
      if (node instanceof TextNode) {
        out.push((node as TextNode).getWholeText());
        return;
      }
      if (node instanceof Element) {
        const kids: Node[] = (node as Element).childNodes();
        for (let i = 0; i < kids.length; i++) {
          walk(kids[i]);
        }
      }
    };
    walk(root);
    return out;
  }
}
