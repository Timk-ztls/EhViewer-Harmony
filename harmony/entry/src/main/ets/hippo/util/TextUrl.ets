/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0507   上游: com/hippo/util/TextUrl.java（50 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/TextUrl.ets
 *
 * 用固定正则找出文本里的 URL，给每段加 `URLSpan`。上游产物是 `Spannable`（Android），
 * 这里复用 `hippo/text/Html.ets` 已落地的 **`SpannedText`/`TextSpan`/`SpanType.URL` 模型** ——
 * 于是 `handleTextUrl(...)` 的产物可以直接喂给 `Html.toHtml(...)`，两个文件形成闭环（见断言）。
 *
 * 平台差异：
 *  1. `Spannable` / `URLSpan` → `SpannedText` / `TextSpan(type=SpanType.URL, value=url)`（D-036 口径）。
 *  2. `content instanceof Spannable` 的"原地加 span"语义 → 这里**总是返回新的 SpannedText**
 *     （ArkTS 无 Spannable 可变模型；上游对纯 CharSequence 入参也是新建 SpannableString，等价）。
 *  3. **`getSpans` 去重逻辑逐字照搬**：若区间内已有 URLSpan 则跳过（上游 `continue`）。
 *     这条等价于"不重复包裹已有 URL"；在新建 SpannedText 的场景下通常无 span，但保留该判断
 *     以便调用方传入已有 span（如先跑 `Html.fromHtml` 再补 URL）。
 *  4. `SPAN_EXCLUSIVE_EXCLUSIVE` → `TextSpan` 无 flags 字段（与 Html.ets 一致，只保留 start/end/type/value）。
 */

import { SpannedText, TextSpan, SpanType } from '../text/Html';

export class TextUrl {

  /**
   * 上游正则**逐字照搬**（注意它允许 `%` 出现在 host 段、端口 1~5 位、路径字符集里含
   * `'` `,` `;` `%` `*` `.` `?` `+` `$` `[]()` 等）：
   * `(http|https)://[a-z0-9A-Z%-]+(\.[a-z0-9A-Z%-]+)+((:\d{1,5}))?(/[...]+)?/?`
   */
  private static readonly URL_REGEX: RegExp =
    new RegExp('(http|https)://[a-z0-9A-Z%-]+(\\.[a-z0-9A-Z%-]+)+(:\\d{1,5})?'
      + "(/[a-zA-Z0-9-_~:#@!&',;=%/\\*\\.\\?\\+\\$\\[\\]\\(\\)]+)?/?", 'g');

  /**
   * 对应上游 `handleTextUrl(content)`。
   * @returns 有 URL 时返回带 `SpanType.URL` span 的 `SpannedText`；无 URL 时返回原文本（spans 为空）
   */
  static handleTextUrl(content: string): SpannedText {
    const spans: TextSpan[] = [];
    const re: RegExp = TextUrl.URL_REGEX;
    re.lastIndex = 0;
    let m: RegExpExecArray | null = re.exec(content);
    while (m !== null) {
      const start: number = m.index;
      const end: number = m.index + m[0].length;
      // 上游：区间内已有 URLSpan 则跳过（这里对已收集的 span 做同样判断）
      if (!TextUrl.hasUrlSpanIn(spans, start, end)) {
        spans.push(new TextSpan(start, end, SpanType.URL, m[0]));
      }
      // 防零长匹配导致死循环
      if (m[0].length === 0) {
        re.lastIndex++;
      }
      m = re.exec(content);
    }
    return new SpannedText(content, spans);
  }

  /** 对应上游 `spannable.getSpans(start, end, URLSpan.class).length > 0`（有交集即算） */
  private static hasUrlSpanIn(spans: TextSpan[], start: number, end: number): boolean {
    for (let i = 0; i < spans.length; i++) {
      const s: TextSpan = spans[i];
      if (s.type !== SpanType.URL) {
        continue;
      }
      if (s.start < end && s.end > start) {
        return true;
      }
    }
    return false;
  }
}