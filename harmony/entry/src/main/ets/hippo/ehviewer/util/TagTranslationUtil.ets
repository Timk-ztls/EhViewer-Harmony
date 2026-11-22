/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0283   上游: com/hippo/ehviewer/util/TagTranslationUtil.java（77 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/util/TagTranslationUtil.ets
 *
 * 纯字符串逻辑：把 `namespace:tag` 按 `EhTagDatabase` 翻成 `译名:译名`。
 * `EhTagDatabase` 属 net-parse 且**已交付**（`prefixToNamespace` / `namespaceToPrefix` /
 * `getTranslation`），故直接 import，不做注入。
 *
 * 平台差异：无逻辑差异，逐行照搬。四处值得注意的**上游原样**：
 *  1. `getTagCN(String[], EhTagDatabase)` 里 namespace 解析用了 `prefixToNamespace(tags[0] + ":")`，
 *     **失败才回落 `tags[0]`**；而 `getTagCNBody` 直接用 `"n:" + tags[0]`（不解析前缀）——
 *     两个方法的 group 查法**不同**，这是上游原样，不统一。
 *  2. 最后那个 `else` 分支里又判了一次 `tagStr != null`（前三个分支已排除该组合），
 *     **是死代码但保留**：它等价于 `return tags[0] + ":" + tags[1]`。
 *  3. `getTagCNBody` 在 `tags.length != 2` 时，循环里 `s = new StringBuffer().append(i)`
 *     **每次重置 buffer，最终只剩最后一个元素**（不是拼接！）。这是上游的真实缺陷 ——
 *     按陷阱 63 属 **A 类（用户可感知）→ 照搬**，因为"修好"会改变多段 tag 的显示结果。
 *  4. `translationPrefix` 决定"用全名还是短前缀"查译名。
 */

import { EhTagDatabase } from '../client/EhTagDatabase';

export class TagTranslationUtil {

  /** 对应上游 `getTagCN(String tag, EhTagDatabase)` */
  static getTagCN1(tag: string, ehTags: EhTagDatabase | null): string {
    const parts: string[] = tag.split(':');
    return TagTranslationUtil.getTagCN(parts, ehTags);
  }

  /** 对应上游 `getTagCN(String[] tags, EhTagDatabase)` */
  static getTagCN(tags: string[], ehTags: EhTagDatabase | null): string {
    if (ehTags !== null && tags.length === 2) {
      let namespace: string | null = EhTagDatabase.prefixToNamespace(tags[0] + ':');
      if (namespace === null) {
        namespace = tags[0];
      }
      const group: string | null = ehTags.getTranslation('n:' + namespace);
      // 翻译标签名
      const prefix: string = TagTranslationUtil.translationPrefix(tags[0]);
      const tagStr: string | null = ehTags.getTranslation(prefix + tags[1]);

      if (group !== null && tagStr !== null) {
        return group + ':' + tagStr;
      } else if (group !== null && tagStr === null) {
        return group + ':' + tags[1];
      } else if (group === null && tagStr !== null) {
        return tags[0] + ':' + tagStr;
      } else {
        if (tagStr !== null) {
          return tags[0] + ':' + tagStr;
        }
        return tags[0] + ':' + tags[1];
      }
    }
    // tags.length != 2：用 ':' 拼接（照搬 StringBuffer 循环）
    let s: string = '';
    for (let i = 0; i < tags.length; i++) {
      if (i === 0) {
        s += tags[i];
      } else {
        s += ':' + tags[i];
      }
    }
    return s;
  }

  /** 对应上游 `getTagCNBody(String[] tags, EhTagDatabase)` */
  static getTagCNBody(tags: string[], ehTags: EhTagDatabase | null): string {
    if (ehTags !== null && tags.length === 2) {
      const group: string | null = ehTags.getTranslation('n:' + tags[0]);
      const prefix: string = TagTranslationUtil.translationPrefix(tags[0]);
      const tagStr: string | null = ehTags.getTranslation(prefix + tags[1]);

      if (group !== null && tagStr !== null) {
        return tagStr;
      } else if (group !== null && tagStr === null) {
        return tags[1];
      } else if (group === null && tagStr !== null) {
        return tagStr;
      }
      return tags[1];
    }
    // ⚠️ 上游此处**每次重置 buffer**，最终只剩最后一个元素 —— 照搬（A 类，见文件头差异 3）
    let s: string = '';
    for (let i = 0; i < tags.length; i++) {
      s = tags[i];
    }
    return s;
  }

  /**
   * 对应上游 `translationPrefix(namespaceOrPrefix)`：
   * 全名（`location`）→ `location:`；短前缀（`loc`）→ 映射后的前缀；都不是 → 空串。
   */
  private static translationPrefix(namespaceOrPrefix: string): string {
    if (EhTagDatabase.prefixToNamespace(namespaceOrPrefix + ':') !== null) {
      return namespaceOrPrefix + ':';
    }
    const prefix: string | null = EhTagDatabase.namespaceToPrefix(namespaceOrPrefix);
    return prefix !== null ? prefix : '';
  }
}