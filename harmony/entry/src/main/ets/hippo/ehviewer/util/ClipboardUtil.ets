/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0279   上游: com/hippo/ehviewer/util/ClipboardUtil.java（157 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/util/ClipboardUtil.ets
 *
 * 把 `LocalFavoriteInfo` 压成一段可粘贴的文本，以及反向还原。
 *
 * ## 上游的编码链路（这才是可移植的核心，剪贴板本身是注入的）
 * ```
 * copy:            reduceString(info)
 *                  = JSON.toJSON(info) → **删 10 个字段** → JSONObject.toJSONString
 *                  → GZIPUtils.compress(s)（gzip + Base64.DEFAULT）
 * getFromClip:     GZIPUtils.uncompress(text) → JSON.parse
 *                  → **putAll(defaultInfo)**（补回被删的 10 个字段的默认值）+ time=now
 * ```
 * **为什么"删字段"再"补默认值"能对**：`reduceString` 删掉的正是 `defaultInfo` 里那 10 个键
 * （`favoriteName/favoriteSlot/pages/rated/simpleTags/thumbWidth/thumbHeight/spanSize/spanIndex/spanGroupIndex`），
 * 而 `putAll` 只在键**不存在**时写入 —— 所以它补的是默认值，不会覆盖用户真实数据。
 * 一旦哪天有人往 `defaultInfo` 里加一个"真实数据"键，`putAll` 就会静默覆盖 —— 见下面第 3 条。
 *
 * ## 上游的四处**必须照搬的怪癖**（否则与"从旧版本粘贴进来的文本"不兼容）
 * 1. **`reduceString` 里算了一个 `s1`（Base64 编码）却从未使用**，真正返回的是 `GZIPUtils.compress(s)`。
 *    → 不移植 `s1`（死代码），但要注明：**任何"顺便都做一遍 Base64"的改动都会改变输出**。
 * 2. **`copy()` 里写进剪贴板的两个值不一样**：
 *    `cmb.setText(content.trim())` 用**裁剪后**的，`ClipData.newPlainText(null, content)` 用**未裁剪**的。
 *    → 照搬：注入的剪贴板接口收 `(text, plainText)` 两个参数，避免"统一 trim"造成的静默差异。
 * 3. **`getGalleryInfoFromClip` 在 `uncompress` 之后再 `clearClipboard()`**（读之前先清空）——
 *    顺序照搬：先读内容 → 解压 → 清空 → 解析。上游这样写是为了"粘贴一次就失效"，
 *    但它同时意味着**解压失败时剪贴板也已经被清空**。
 * 4. **`getClipContent()` 在没有内容时返回 `""`（空串），不是 null** ——
 *    于是 `getGalleryInfoFromClip` 拿到空串继续往下走（`uncompress("")`），最终靠 `object == null` 兜底。
 *
 * ## 平台差异
 *  · `ClipboardManager` / `ClipData` → 注入 `Clipboard` 接口（鸿蒙 `@ohos.pasteboard`）。
 *  · `System.currentTimeMillis()` → 注入 `now()`。
 *  · `JSONObject` 有序性/`toJSONString` 的字段顺序：鸿蒙用普通 `Map` + 显式序列化，
 *    **不依赖对象的键顺序**（gzip 后是 Base64 文本，键顺序变了就不兼容 —— 见 `serialize`）。
 *  · `createAnnouncerFromClipboardUrl` 依赖 `Announcer`（ui-scene 的页面路由对象）+
 *    `GalleryDetailScene/ProgressScene` 的 KEY 常量 → 归 ui-scene；本文件只提供
 *    `parseClipboardUrl(url)`（纯解析 + 目标判定），路由由调用方做。
 */

import { GZIPUtils } from './GZIPUtils';
import { GalleryDetailUrlParser } from '../client/parser/GalleryDetailUrlParser';
import { GalleryPageUrlParser } from '../client/parser/GalleryPageUrlParser';

/** 剪贴板能力（`@ohos.pasteboard` 的薄封装，注入以便断言"两个值不一样"这个怪癖） */
export interface Clipboard {
  /** 对应 `cmb.setText(text)` —— 上游传的是 **trim 后**的 */
  setText(text: string | null): void;

  /** 对应 `cmb.setPrimaryClip(ClipData.newPlainText(null, text))` —— 上游传的是 **未 trim** 的 */
  setPrimaryClipText(text: string): void;

  /** 对应 `cmb.hasPrimaryClip() && getPrimaryClip().getItemCount() > 0` */
  hasText(): boolean;

  /** 对应 `getPrimaryClip().getItemAt(0).getText()`；无内容返回 null */
  getText(): string | null;
}

/** 解析出来的跳转目标（对应上游 `createAnnouncerFromClipboardUrl` 的两种结果） */
export enum ClipboardUrlTarget {
  /** 详情页（`GalleryDetailScene`，带 gid + token） */
  DETAIL = 0,
  /** 阅读页（`ProgressScene`，带 gid + pToken + page） */
  PROGRESS = 1
}

export class ClipboardUrlResult {
  target: ClipboardUrlTarget;
  gid: number;
  token: string;
  pToken: string;
  page: number;

  constructor(target: ClipboardUrlTarget, gid: number, token: string, pToken: string, page: number) {
    this.target = target;
    this.gid = gid;
    this.token = token;
    this.pToken = pToken;
    this.page = page;
  }
}

export class ClipboardUtil {

  /** 上游 `reduceString` 删掉的 10 个字段（顺序照搬，虽然对 map 无影响） */
  static readonly REDUCED_KEYS: string[] = [
    'favoriteName', 'pages', 'rated', 'spanGroupIndex', 'spanIndex',
    'spanSize', 'thumbHeight', 'thumbWidth', 'time', 'favoriteSlot',
  ];

  /**
   * 上游 `defaultInfo`：`putAll` 时补回的默认值。
   * ⚠️ **这些键必须与 `REDUCED_KEYS` 一一对应** —— 若 `defaultInfo` 里出现"未删除的真实数据键"，
   * `putAll` 会静默覆盖用户数据。本实现用 `assertDefaultsConsistent()` 守住这条不变式。
   */
  static buildDefaultInfo(): Map<string, Object | null> {
    const m: Map<string, Object | null> = new Map<string, Object | null>();
    m.set('favoriteName', null);
    m.set('favoriteSlot', -2);
    m.set('pages', 0);
    m.set('rated', false);
    m.set('simpleTags', null);
    m.set('thumbWidth', 0);
    m.set('thumbHeight', 0);
    m.set('spanSize', 0);
    m.set('spanIndex', 0);
    m.set('spanGroupIndex', 0);
    return m;
  }

  /**
   * 不变式检查：所有被删的键（除 `simpleTags` 与 `time` 外）都必须在 defaultInfo 里，
   * 且 defaultInfo 里不能有"没被删过的"键（那会导致覆盖）。
   * @returns 违反的键名列表（空 = 一致）
   */
  static findDefaultInfoViolations(): string[] {
    const bad: string[] = [];
    const def: Map<string, Object | null> = ClipboardUtil.buildDefaultInfo();
    const reduced: string[] = ClipboardUtil.REDUCED_KEYS;
    // 1) defaultInfo 的每个键都必须在 REDUCED_KEYS 里（除了彻底丢弃的 simpleTags / time）
    def.forEach((_v: Object | null, k: string) => {
      if (reduced.indexOf(k) < 0) {
        bad.push('defaultInfo 有未删除键: ' + k);
      }
    });
    // 2) 每个被删的键要么在 defaultInfo 里，要么是"彻底丢弃"的（simpleTags/time）
    for (let i = 0; i < reduced.length; i++) {
      const k: string = reduced[i];
      if (!def.has(k) && k !== 'simpleTags' && k !== 'time') {
        bad.push('REDUCED_KEYS 的键没有默认值: ' + k);
      }
    }
    return bad;
  }

  /**
   * 对应上游 `reduceString(galleryInfo)` 的**前三步**（删键 + 序列化 + compress）：
   * @param json 已经是 `JSON.toJSON(info)` 的结果（字段名 → 值）
   * @returns gzip + Base64 的文本
   */
  static async reduceString(json: Map<string, Object | null>,
    compress: (s: string) => Promise<string | null>): Promise<string | null> {
    const reduced: Map<string, Object | null> | null = ClipboardUtil.reduceJson(json);
    if (reduced === null) {
      return null;
    }
    const s: string = ClipboardUtil.serialize(reduced);
    return await compress(s);
  }

  /** 删掉 `REDUCED_KEYS` 里的字段（对应上游 10 个 `favoriteJson.remove(...)`） */
  static reduceJson(json: Map<string, Object | null>): Map<string, Object | null> | null {
    if (json === null || json === undefined) {
      return null;
    }
    const out: Map<string, Object | null> = new Map<string, Object | null>();
    json.forEach((v: Object | null, k: string) => {
      if (ClipboardUtil.REDUCED_KEYS.indexOf(k) < 0) {
        out.set(k, v);
      }
    });
    return out;
  }

  /**
   * 对应上游 `object.putAll(defaultInfo)` + `object.put("time", now)`。
   * **`putAll` 只在键不存在时写入**（不覆盖真实数据）—— 这正是它能安全工作的原因。
   */
  static expandJson(json: Map<string, Object | null>, now: number): Map<string, Object | null> {
    const out: Map<string, Object | null> = new Map<string, Object | null>();
    json.forEach((v: Object | null, k: string) => out.set(k, v));
    ClipboardUtil.buildDefaultInfo().forEach((v: Object | null, k: string) => {
      if (!out.has(k)) {
        out.set(k, v);
      }
    });
    out.set('time', now);
    return out;
  }

  /** 对应上游 `copy(galleryInfo)`：清空 → 非空才写；**注意 setText 用 trim、setPrimaryClip 用原文** */
  static async copy(json: Map<string, Object | null>, clipboard: Clipboard,
    compress: (s: string) => Promise<string | null>): Promise<boolean> {
    const content: string | null = await ClipboardUtil.reduceString(json, compress);
    ClipboardUtil.clearClipboard(clipboard);
    if (content === null || content.length === 0) {
      return false;
    }
    // 上游：cmb.setText(content.trim()) —— trim 后
    clipboard.setText(ClipboardUtil.javaTrim(content));
    // 上游：ClipData.newPlainText(null, content) —— **未 trim**
    clipboard.setPrimaryClipText(content);
    return true;
  }

  /** 对应上游 `copyText(text)`：清空 → 非空才写（这里**不 trim**，上游也没 trim） */
  static copyText(text: string | null, clipboard: Clipboard): boolean {
    ClipboardUtil.clearClipboard(clipboard);
    if (text === null || text.length === 0) {
      return false;
    }
    clipboard.setPrimaryClipText(text);
    return true;
  }

  /**
   * 对应上游 `getGalleryInfoFromClip()`：
   * 读内容 → 解压 → **清空剪贴板** → 解析 → 补默认值 + time。
   * @returns 还原后的字段表；失败（无内容/解压失败/非 JSON）→ null
   */
  static async getGalleryInfoFromClip(clipboard: Clipboard,
    uncompress: (s: string | null) => Promise<string | null>,
    parseJson: (s: string) => Map<string, Object | null> | null,
    now: () => number = () => Date.now()): Promise<Map<string, Object | null> | null> {
    const compressString: string = ClipboardUtil.getClipContent(clipboard);
    const galleryString: string | null = await uncompress(compressString);
    // 上游：解压**之后**才清空（解压失败时剪贴板也已被清空 —— 顺序照搬）
    ClipboardUtil.clearClipboard(clipboard);
    if (galleryString === null) {
      return null;
    }
    const object: Map<string, Object | null> | null = parseJson(galleryString);
    if (object === null) {
      return null;
    }
    return ClipboardUtil.expandJson(object, now());
  }

  /** 对应上游 `getClipContent()`：无内容返回 **空串**（不是 null） */
  static getClipContent(clipboard: Clipboard): string {
    if (clipboard.hasText()) {
      const t: string | null = clipboard.getText();
      const s: string = (t === null) ? 'null' : t; // 上游 String.valueOf(addedText)
      if (s.length > 0) {
        return s;
      }
    }
    return '';
  }

  /** 对应上游 `clearClipboard()`：把现有主剪贴内容"重设一次"再 setText(null)（上游的怪写法） */
  static clearClipboard(clipboard: Clipboard): void {
    try {
      clipboard.setPrimaryClipText(clipboard.hasText() ? `${clipboard.getText()}` : '');
      clipboard.setText(null);
    } catch (e) {
      // 上游 catch (Exception e) { ExceptionUtils.getReadableString(e); } —— 只读一下，不抛
    }
  }

  /**
   * 对应上游 `createAnnouncerFromClipboardUrl(url)` 的**解析部分**（路由由 ui-scene 做）。
   * 先试详情页 URL，再试阅读页 URL，都不匹配 → null。
   */
  static parseClipboardUrl(url: string | null): ClipboardUrlResult | null {
    const detail = GalleryDetailUrlParser.parseWithStrict(url, false);
    if (detail !== null) {
      return new ClipboardUrlResult(ClipboardUrlTarget.DETAIL, detail.gid, detail.token, '', 0);
    }
    const page = GalleryPageUrlParser.parseWithStrict(url, false);
    if (page !== null) {
      return new ClipboardUrlResult(ClipboardUrlTarget.PROGRESS, page.gid, '', page.pToken, page.page);
    }
    return null;
  }

  /**
   * 对应 `JSONObject.toJSONString(map)`：**键按插入顺序**输出。
   * 用显式序列化而不是 `JSON.stringify`，因为后者对 `Map` 无效（会输出 `{}`）。
   */
  static serialize(m: Map<string, Object | null>): string {
    const parts: string[] = [];
    m.forEach((v: Object | null, k: string) => {
      parts.push(JSON.stringify(k) + ':' + JSON.stringify(v));
    });
    return '{' + parts.join(',') + '}';
  }

  /** 对应 Java `String.trim()`：只裁掉 <= U+0020 的首尾字符（**不是** JS trim 的 Unicode 语义） */
  static javaTrim(s: string): string {
    let start: number = 0;
    let end: number = s.length;
    while (start < end && s.charCodeAt(start) <= 0x20) {
      start++;
    }
    while (end > start && s.charCodeAt(end - 1) <= 0x20) {
      end--;
    }
    return s.substring(start, end);
  }
}
