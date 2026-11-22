/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0492   上游: com/hippo/util/JsoupUtils.kt（57 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/JsoupUtils.ets
 *
 * 上游是 **jsoup** 的便利封装：`getElementsByClass` / `getElementsByTag` 取第一个，**空集合返回 null**
 * （jsoup 本身返回空 Elements，上游统一转成 null 让调用点用 `?.` 判断）。
 *
 * 平台差异：
 *  1. ArkTS 无 jsoup → 用**最小接口** `JsoupDocumentLike` / `JsoupElementLike` 承接（契约先行，
 *     与 `ConacoTaskLike`、`GalleryCommentLike` 同处理）。net-parse 若用自研 HTML 解析器，
 *     只要实现这两个接口即可复用本文件全部逻辑。
 *  2. **真正被移植的是"空集合 → null"这条判定**（上游 4 个方法里唯一有语义的部分）；
 *     取 `elements[0]` 是找选择器的事，属解析器实现。
 *  3. 接口只声明**被用到**的三个方法：`getElementsByClass` / `getElementsByTag`。
 *     上游 `Document` 版和 `Element` 版签名不同（Document 没有 getElementsByTag），故分开两个接口：
 *     `JsoupDocumentLike`（只有 byClass）+ `JsoupElementLike`（byClass + byTag）。
 */

export interface JsoupElementLike {
  getElementsByClass(className: string): JsoupElementLike[];

  getElementsByTag(tagName: string): JsoupElementLike[];
}

export interface JsoupDocumentLike {
  getElementsByClass(className: string): JsoupElementLike[];
}

export class JsoupUtils {

  /** 对应上游 `getElementByClass(doc, className)` */
  static getElementByClassFromDoc(doc: JsoupDocumentLike, className: string): JsoupElementLike | null {
    const elements: JsoupElementLike[] = doc.getElementsByClass(className);
    if (elements !== null && elements !== undefined && elements.length > 0) {
      return elements[0];
    }
    return null;
  }

  /** 对应上游 `getElementByClass(element, className)` */
  static getElementByClass(element: JsoupElementLike, className: string): JsoupElementLike | null {
    const elements: JsoupElementLike[] = element.getElementsByClass(className);
    if (elements !== null && elements !== undefined && elements.length > 0) {
      return elements[0];
    }
    return null;
  }

  /** 对应上游 `getElementsByClass(element, className)`：空 → null（不是空数组） */
  static getElementsByClass(element: JsoupElementLike, className: string): JsoupElementLike[] | null {
    const elements: JsoupElementLike[] = element.getElementsByClass(className);
    return (elements !== null && elements !== undefined && elements.length > 0) ? elements : null;
  }

  /** 对应上游 `getElementByTag(element, tagName)` */
  static getElementByTag(element: JsoupElementLike, tagName: string): JsoupElementLike | null {
    const elements: JsoupElementLike[] = element.getElementsByTag(tagName);
    return (elements !== null && elements !== undefined && elements.length > 0) ? elements[0] : null;
  }
}