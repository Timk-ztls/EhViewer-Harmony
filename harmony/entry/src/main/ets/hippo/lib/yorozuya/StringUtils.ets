/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0424   上游: com/hippo/lib/yorozuya/StringUtils.java（518 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/StringUtils.ets
 *
 * 平台差异（方案 §5-7 无重载 + §5-9 字符串/集合 API 差异）：
 *  1. **char → string（单字符）**：ArkTS 无 char 类型。
 *     `char[]` → `string[]`；`str.charAt(i)` → `str.charAt(i)`（JS 返回单字符 string，语义一致）。
 *  2. length(String) → **strLength(String)**：TS/ArkTS 里类的静态成员名 length 与内置
 *     Function.length 冲突（TS2699），必须改名。全仓 git grep StringUtils.length = 0 调用点，
 *     改名无下游影响。
 *  3. 重载合并（ArkTS 无重载解析）：
 *       replace(text, search, repl) / replace(text, search, repl, max) → replace(text, search, repl, max?)
 *       avoidNull(value) / avoidNull(value, defaultValue)            → avoidNull(value, defaultValue?)
 *       trim(str) / trim(str, excluded)                              → trim(str, excluded?)
 *       replaceEach(text, sl, rl) / 私有 5 参版                       → replaceEach(text, sl, rl, repeat?, timeToLive?)
 *  4. `Arrays.binarySearch(excluded, ch)` → `excluded.indexOf(ch) >= 0`。
 *     上游 excluded 实际只有 WHITE_SPACE_ARRAY（已按码点升序），二分与线性查找结果完全一致；
 *     线性版对乱序数组更宽容，不改变任何现有调用点行为。
 *  5. `android.text.TextUtils.isEmpty` → 内联 isEmpty()（null 或长度 0，不 trim）。
 *  6. `java.util.ArrayList.toArray(new String[])` → 直接返回 string[]；`split(null, *)` 的 Java null
 *     返回 → `string[] | undefined`。
 *  7. IllegalArgumentException / IllegalStateException → Error，**消息串逐字保留**：
 *     "Search and Replace array lengths don't match: N vs M"
 *     "Aborting to protect against StackOverflowError - output of one loop is the input of another"
 *  8. StringBuilder → string[] 拼接后 join('')。语义等价；`increase` 容量预估在 ArkTS 无意义，
 *     保留计算只为让代码与上游逐行对应（不影响结果）。
 *  9. `str.equals(str2)` → `===`（JS 字符串值相等，与 Java String.equals 一致）。
 * 10. 上游 replaceEach 的 `repeat`/`timeToLive` 参数在本项目**无调用点**（公开 API 只暴露
 *     不重复版本），但递归保护逻辑保留，防止将来误用死循环。
 */

import { Utilities } from './Utilities';

export class StringUtils {

  static readonly EMPTY_STRING_ARRAY: string[] = [];

  /** 与上游顺序一致（已按码点升序）：TAB / SPACE / NO-BREAK SPACE / IDEOGRAPHIC SPACE */
  static readonly WHITE_SPACE_ARRAY: string[] = ['\u0009', '\u0020', '\u00A0', '\u3000'];

  private static readonly ESCAPE_CHARATER_LIST: string[] = [
    '&amp;',
    '&lt;',
    '&gt;',
    '&quot;',
    '&#039;',
    '&times;',
    '&nbsp;'
  ];

  private static readonly UNESCAPE_CHARATER_LIST: string[] = [
    '&',
    '<',
    '>',
    '"',
    '\'',
    '×',
    ' '
  ];

  /** android.text.TextUtils.isEmpty 的等价 */
  private static isEmpty(s: string | null | undefined): boolean {
    return s === null || s === undefined || s.length === 0;
  }

  /**
   * Unescape xml. It do not work perfectly.
   */
  static unescapeXml(str: string | null | undefined): string | null | undefined {
    if (str === null || str === undefined) {
      return str;
    }
    return StringUtils.replaceEach(str, StringUtils.ESCAPE_CHARATER_LIST,
      StringUtils.UNESCAPE_CHARATER_LIST);
  }

  /**
   * Replaces a String with another String inside a larger String,
   * for the first max values of the search String.
   *
   * <pre>
   * replace(null, *, *, *)         = null
   * replace("", *, *, *)           = ""
   * replace("any", null, *, *)     = "any"
   * replace("any", *, null, *)     = "any"
   * replace("any", "", *, *)       = "any"
   * replace("any", *, *, 0)        = "any"
   * replace("abaa", "a", null, -1) = "abaa"
   * replace("abaa", "a", "", -1)   = "b"
   * replace("abaa", "a", "z", 0)   = "abaa"
   * replace("abaa", "a", "z", 1)   = "zbaa"
   * replace("abaa", "a", "z", 2)   = "zbza"
   * replace("abaa", "a", "z", -1)  = "zbzz"
   * </pre>
   *
   * @param max maximum number of values to replace, or -1 if no maximum
   */
  static replace(text: string | null | undefined, searchString: string | null | undefined,
    replacement: string | null | undefined, max?: number): string | null | undefined {
    const limit: number = (max === undefined) ? -1 : max;
    if (StringUtils.isEmpty(text) || StringUtils.isEmpty(searchString)
      || replacement === null || replacement === undefined || limit === 0) {
      return text;
    }
    const src: string = text as string;
    const search: string = searchString as string;
    const repl: string = replacement as string;

    let start: number = 0;
    let end: number = src.indexOf(search, start);
    if (end < 0) {
      return text;
    }
    const replLength: number = search.length;
    let increase: number = repl.length - replLength;
    increase = increase < 0 ? 0 : increase;
    increase *= limit < 0 ? 16 : (limit > 64 ? 64 : limit);

    const buf: string[] = [];
    let remaining: number = limit;
    while (end >= 0) {
      buf.push(src.substring(start, end));
      buf.push(repl);
      start = end + replLength;
      remaining--;
      if (remaining === 0) {
        break;
      }
      end = src.indexOf(search, start);
    }
    buf.push(src.substring(start));
    return buf.join('');
  }

  /**
   * Replaces all occurrences of Strings within another String.
   *
   * <pre>
   * replaceEach(null, *, *)        = null
   * replaceEach("", *, *)          = ""
   * replaceEach("aba", null, null) = "aba"
   * replaceEach("aba", new String[0], null) = "aba"
   * replaceEach("aba", null, new String[0]) = "aba"
   * replaceEach("aba", new String[]{"a"}, null)  = "aba"
   * replaceEach("aba", new String[]{"a"}, new String[]{""})  = "b"
   * replaceEach("aba", new String[]{null}, new String[]{"a"})  = "aba"
   * replaceEach("abcde", new String[]{"ab", "d"}, new String[]{"w", "t"})  = "wcte"
   * (example of how it does not repeat)
   * replaceEach("abcde", new String[]{"ab", "d"}, new String[]{"d", "t"})  = "dcte"
   * </pre>
   */
  static replaceEach(text: string | null | undefined,
    searchList: Array<string | null | undefined> | null | undefined,
    replacementList: Array<string | null | undefined> | null | undefined,
    repeat?: boolean, timeToLive?: number): string | null | undefined {
    const rp: boolean = (repeat === undefined) ? false : repeat;
    const ttl: number = (timeToLive === undefined) ? 0 : timeToLive;
    return StringUtils.replaceEachInternal(text, searchList, replacementList, rp, ttl);
  }

  private static replaceEachInternal(text: string | null | undefined,
    searchList: Array<string | null | undefined> | null | undefined,
    replacementList: Array<string | null | undefined> | null | undefined,
    repeat: boolean, timeToLive: number): string | null | undefined {

    if (text === null || text === undefined || StringUtils.isEmpty(text)
      || searchList === null || searchList === undefined || searchList.length === 0
      || replacementList === null || replacementList === undefined || replacementList.length === 0) {
      return text;
    }

    // if recursing, this shouldn't be less than 0
    if (timeToLive < 0) {
      throw new Error('Aborting to protect against StackOverflowError - '
        + 'output of one loop is the input of another');
    }

    const src: string = text as string;
    const searchLen: number = searchList.length;
    const replacementLen: number = replacementList.length;

    // make sure lengths are ok, these need to be equal
    if (searchLen !== replacementLen) {
      throw new Error(`Search and Replace array lengths don't match: ${searchLen} vs ${replacementLen}`);
    }

    // keep track of which still have matches
    const noMoreMatchesForReplIndex: boolean[] = new Array<boolean>(searchLen);
    noMoreMatchesForReplIndex.fill(false);

    // index on index that the match was found
    let textIndex: number = -1;
    let replaceIndex: number = -1;
    let tempIndex: number = -1;

    for (let i = 0; i < searchLen; i++) {
      const search: string | null | undefined = searchList[i];
      if (noMoreMatchesForReplIndex[i] || search === null || search === undefined
        || StringUtils.isEmpty(search)
        || replacementList[i] === null || replacementList[i] === undefined) {
        continue;
      }
      tempIndex = src.indexOf(search as string);

      if (tempIndex === -1) {
        noMoreMatchesForReplIndex[i] = true;
      } else {
        if (textIndex === -1 || tempIndex < textIndex) {
          textIndex = tempIndex;
          replaceIndex = i;
        }
      }
    }

    // no search strings found, we are done
    if (textIndex === -1) {
      return text;
    }

    let start: number = 0;
    let increase: number = 0;
    for (let i = 0; i < searchLen; i++) {
      const search: string | null | undefined = searchList[i];
      const repl: string | null | undefined = replacementList[i];
      if (search === null || search === undefined || repl === null || repl === undefined) {
        continue;
      }
      const greater: number = (repl as string).length - (search as string).length;
      if (greater > 0) {
        increase += 3 * greater; // assume 3 matches
      }
    }
    // have upper-bound at 20% increase
    increase = Math.min(increase, Math.floor(src.length / 5));

    const buf: string[] = [];
    while (textIndex !== -1) {
      buf.push(src.substring(start, textIndex));
      buf.push(replacementList[replaceIndex] as string);
      start = textIndex + (searchList[replaceIndex] as string).length;

      textIndex = -1;
      replaceIndex = -1;
      tempIndex = -1;
      // find the next earliest match
      for (let i = 0; i < searchLen; i++) {
        const search: string | null | undefined = searchList[i];
        if (noMoreMatchesForReplIndex[i] || search === null || search === undefined
          || StringUtils.isEmpty(search)
          || replacementList[i] === null || replacementList[i] === undefined) {
          continue;
        }
        tempIndex = src.indexOf(search as string, start);
        if (tempIndex === -1) {
          noMoreMatchesForReplIndex[i] = true;
        } else {
          if (textIndex === -1 || tempIndex < textIndex) {
            textIndex = tempIndex;
            replaceIndex = i;
          }
        }
      }
    }
    buf.push(src.substring(start));
    const result: string = buf.join('');
    if (!repeat) {
      return result;
    }
    return StringUtils.replaceEachInternal(result, searchList, replacementList, repeat, timeToLive - 1);
  }

  static endsWith(string: string, suffixs: string[]): boolean {
    for (let i = 0, n = suffixs.length; i < n; i++) {
      if (string.endsWith(suffixs[i])) {
        return true;
      }
    }
    return false;
  }

  /**
   * Splits the provided text into an array, separator specified.
   * Adjacent separators are treated as one separator.
   *
   * <pre>
   * split(null, *)         = null
   * split("", *)           = []
   * split("a.b.c", '.')    = ["a", "b", "c"]
   * split("a..b.c", '.')   = ["a", "b", "c"]
   * split("a:b:c", '.')    = ["a:b:c"]
   * split("a b c", ' ')    = ["a", "b", "c"]
   * </pre>
   *
   * @param separatorChar 分隔符（单字符字符串，ArkTS 无 char）
   */
  static split(str: string | null | undefined, separatorChar: string): string[] | undefined {
    return StringUtils.splitWorker(str, separatorChar, false);
  }

  private static splitWorker(str: string | null | undefined, separatorChar: string,
    preserveAllTokens: boolean): string[] | undefined {
    if (str === null || str === undefined) {
      return undefined;
    }
    const len: number = str.length;
    if (len === 0) {
      return StringUtils.EMPTY_STRING_ARRAY;
    }
    const list: string[] = [];
    let i: number = 0;
    let start: number = 0;
    let match: boolean = false;
    let lastMatch: boolean = false;
    while (i < len) {
      if (str.charAt(i) === separatorChar) {
        if (match || preserveAllTokens) {
          list.push(str.substring(start, i));
          match = false;
          lastMatch = true;
        }
        i++;
        start = i;
        continue;
      }
      lastMatch = false;
      match = true;
      i++;
    }
    if (match || (preserveAllTokens && lastMatch)) {
      list.push(str.substring(start, i));
    }
    return list;
  }

  static avoidNull(value: string | null | undefined, defaultValue?: string): string {
    if (value === null || value === undefined) {
      return (defaultValue === undefined) ? '' : defaultValue;
    }
    return value;
  }

  static isAllDigit(str: string | null | undefined): boolean {
    if (StringUtils.isEmpty(str)) {
      return false;
    }
    const s: string = str as string;
    for (let i = 0, n = s.length; i < n; i++) {
      const ch: string = s.charAt(i);
      if (ch < '0' || ch > '9') {
        return false;
      }
    }
    return true;
  }

  static strLength(str: string | null | undefined): number {
    return (str === null || str === undefined) ? 0 : str.length;
  }

  /**
   * Counts how many times the char appears in the given string.
   *
   * <pre>
   * countMatches(null, *)   = 0
   * countMatches("", *)     = 0
   * countMatches("abba", 'a') = 2
   * countMatches("abba", 'b') = 2
   * countMatches("abba", 'x') = 0
   * </pre>
   */
  static countMatches(str: string | null | undefined, ch: string): number {
    if (StringUtils.isEmpty(str)) {
      return 0;
    }
    const s: string = str as string;
    let count: number = 0;
    for (let i = 0; i < s.length; i++) {
      if (ch === s.charAt(i)) {
        count++;
      }
    }
    return count;
  }

  /**
   * All null or empty, or all not
   */
  static equals(str1: string | null | undefined, str2: string | null | undefined): boolean {
    return (StringUtils.isEmpty(str1) && StringUtils.isEmpty(str2))
      || (!StringUtils.isEmpty(str1) && !StringUtils.isEmpty(str2) && (str1 as string) === (str2 as string));
  }

  static ordinalIndexOf(str: string | null | undefined, c: string, n: number): number {
    if (str === null || str === undefined || n < 0) {
      return -1;
    }
    let pos: number = -1;
    let remaining: number = n;
    do {
      pos = str.indexOf(c, pos + 1);
      remaining--;
    } while (remaining >= 0 && pos !== -1);
    return pos;
  }

  /**
   * Works like String.trim(), but more white space is excluded (WHITE_SPACE_ARRAY).
   */
  static trim(str: string | null | undefined, excluded?: string[]): string | null | undefined {
    if (str === null || str === undefined) {
      return str;
    }
    const ex: string[] = (excluded === undefined) ? StringUtils.WHITE_SPACE_ARRAY : excluded;
    const s: string = str;
    let start: number = 0;
    let last: number = s.length - 1;
    let end: number = last;
    while (start <= end && ex.indexOf(s.charAt(start)) >= 0) {
      start++;
    }
    while (end >= start && ex.indexOf(s.charAt(end)) >= 0) {
      end--;
    }
    if (start === 0 && end === last) {
      return str;
    }
    return s.substring(start, end + 1);
  }

  static remove(str: string | null | undefined, removed: string[] | null | undefined): string | null | undefined {
    if (StringUtils.isEmpty(str) || removed === null || removed === undefined || removed.length === 0) {
      return str;
    }
    const s: string = str as string;
    const chars: string[] = [];
    for (let i = 0; i < s.length; i++) {
      chars.push(s.charAt(i));
    }
    let pos: number = 0;
    for (let i = 0; i < chars.length; i++) {
      if (!Utilities.containChar(removed, chars[i])) {
        chars[pos] = chars[i];
        pos++;
      }
    }
    return chars.slice(0, pos).join('');
  }
}
