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

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/GalleryInfo.java
 * （inventory S0050，361 行 / 实测 393 行含注释）
 *
 * 契约：C-7（20 字段，Lead 2026-10-24 裁决：`posted` 保持 `string`，另给派生 `postedAt`）
 *
 * 为什么 `posted` 必须是 string：
 *   上游 `public String posted;`（GalleryInfo.java:113），DAO 实体
 *   `BookmarkInfo(long, String, ..., String posted, ...)` 同样吃 String，
 *   GreenDAO 把 `BOOKMARKS.POSTED` 映射为 TEXT。改成 number 会让「导入原 App 的 .db」
 *   这个 P3 验收项直接失败，并破坏 `toCSV/fromCSV` 的逐字节格式（备份/恢复依赖）。
 *
 * ArkTS 映射：
 *   Parcelable               → 不需要（ArkTS 无 Parcel；跨线程传值走 TaskPool 的可序列化约束，
 *                              本类的字段全是基本类型/数组，可直接结构化克隆）
 *   Parcelable.Creator       → 删（无等价物；序列化出口是 toJson/fromJson 与 toCSV/fromCSV）
 *   fastjson JSONObject      → toJson(): string / fromJson(s): GalleryInfo（手写映射 + 类型守卫）
 *   String[] simpleTags      → string[] | null
 *   ArrayList<String> tgList → string[] | null（上游用 List，读取方只 indexOf/遍历）
 *   float rating             → number
 *   long gid                 → number（ArkTS number 为 double，gid 实际 < 2^53，安全）
 *
 * @Observed：UI（列表/详情页）直接绑定本对象，字段变更需触发刷新。
 */

/** ISO 639-1 语言码（上游 S_LANG_*）。 */
export const S_LANG_JA: string = 'JA';
export const S_LANG_EN: string = 'EN';
export const S_LANG_ZH: string = 'ZH';
export const S_LANG_NL: string = 'NL';
export const S_LANG_FR: string = 'FR';
export const S_LANG_DE: string = 'DE';
export const S_LANG_HU: string = 'HU';
export const S_LANG_IT: string = 'IT';
export const S_LANG_KO: string = 'KO';
export const S_LANG_PL: string = 'PL';
export const S_LANG_PT: string = 'PT';
export const S_LANG_RU: string = 'RU';
export const S_LANG_ES: string = 'ES';
export const S_LANG_TH: string = 'TH';
export const S_LANG_VI: string = 'VI';

/** 顺序必须与 S_LANG_PATTERNS / S_LANG_TAGS 一一对应（上游三张表同序）。 */
export const S_LANGS: string[] = [
  S_LANG_EN, S_LANG_ZH, S_LANG_ES, S_LANG_KO, S_LANG_RU, S_LANG_FR, S_LANG_PT,
  S_LANG_TH, S_LANG_DE, S_LANG_IT, S_LANG_VI, S_LANG_PL, S_LANG_HU, S_LANG_NL
];

/** 与上游正则逐字符一致（含全角括号与繁体字，案例：`[汉漢]化`、`中[国國][语語]`）。 */
export const S_LANG_PATTERNS: RegExp[] = [
  /[(\[]eng(?:lish)?[)\]]|英訳/i,
  /[(（\[]ch(?:inese)?[)）\]]|[汉漢]化|中[国國][语語]|中文|中国翻訳/i,
  /[(\[]spanish[)\]]|[(\[]Español[)\]]|スペイン翻訳/i,
  /[(\[]korean?[)\]]|韓国翻訳/i,
  /[(\[]rus(?:sian)?[)\]]|ロシア翻訳/i,
  /[(\[]fr(?:ench)?[)\]]|フランス翻訳/i,
  /[(\[]portuguese|ポルトガル翻訳/i,
  /[(\[]thai(?: ภาษาไทย)?[)\]]|แปลไทย|タイ翻訳/i,
  /[(\[]german[)\]]|ドイツ翻訳/i,
  /[(\[]italiano?[)\]]|イタリア翻訳/i,
  /[(\[]vietnamese(?: Tiếng Việt)?[)\]]|ベトナム翻訳/i,
  /[(\[]polish[)\]]|ポーランド翻訳/i,
  /[(\[]hun(?:garian)?[)\]]|ハンガリー翻訳/i,
  /[(\[]dutch[)\]]|オランダ翻訳/i
];

export const S_LANG_TAGS: string[] = [
  'language:english', 'language:chinese', 'language:spanish', 'language:korean',
  'language:russian', 'language:french', 'language:portuguese', 'language:thai',
  'language:german', 'language:italian', 'language:vietnamese', 'language:polish',
  'language:hungarian', 'language:dutch'
];

@Observed
export class GalleryInfo {
  // ---- C-7 基础字段 ----
  gid: number = 0;
  token: string = '';
  title: string = '';
  titleJpn: string = '';
  thumb: string = '';
  category: number = 0;
  /** 与上游一致：HTML 里的时间文本或 epoch 秒字符串。DB 列 TEXT。 */
  posted: string = '';
  uploader: string = '';
  rating: number = 0;
  simpleLanguage: string | null = null;

  // ---- C-7 DAO 列字段 ----
  rated: boolean = false;
  simpleTags: string[] | null = null;
  pages: number = 0;
  thumbWidth: number = 0;
  thumbHeight: number = 0;
  spanSize: number = 0;
  spanIndex: number = 0;
  spanGroupIndex: number = 0;
  favoriteSlot: number = -2;
  favoriteName: string | null = null;
  tgList: string[] | null = null;

  /**
   * 派生字段（不入库）：`posted` 的 epoch 毫秒表示，解析失败 = -1。
   * 用途：列表排序、时间轴。上游没有这个字段，是为 getter 依赖排序新增的（C-7 裁决）。
   */
  postedAt: number = -1;

  constructor() {
  }

  /** 对齐 generateSLang()：先按标签判语言，再退回标题正则。 */
  generateSLang(): void {
    if (this.simpleTags !== null) {
      this.generateSLangFromTags();
    }
    if (this.simpleLanguage === null && this.title.length > 0) {
      this.generateSLangFromTitle();
    }
  }

  private generateSLangFromTags(): void {
    const tags: string[] | null = this.simpleTags;
    if (tags === null) {
      return;
    }
    for (let t = 0; t < tags.length; t++) {
      for (let i = 0; i < S_LANGS.length; i++) {
        if (S_LANG_TAGS[i] === tags[t]) {
          this.simpleLanguage = S_LANGS[i];
          return;
        }
      }
    }
  }

  private generateSLangFromTitle(): void {
    for (let i = 0; i < S_LANGS.length; i++) {
      if (S_LANG_PATTERNS[i].test(this.title)) {
        this.simpleLanguage = S_LANGS[i];
        return;
      }
    }
    this.simpleLanguage = null;
  }

  /**
   * 解析 `posted` → epoch 毫秒。两种形态都要吃（Lead 要求容错，失败返回 -1 不抛）：
   *   "1287964800"          epoch **秒**（10 位）→ 1287964800000
   *   "1287964800000"       epoch 毫秒（13 位）→ 原值
   *   "2010-10-25 00:00"    本地时区日期串
   *   "2010-10-25"          仅日期
   * 其它（空串、"unknown"、"N/A"）→ -1
   */
  static parsePosted(posted: string): number {
    if (posted === null || posted === undefined) {
      return -1;
    }
    const s: string = posted.trim();
    if (s.length === 0) {
      return -1;
    }
    // 纯数字：按位数区分秒 / 毫秒
    if (/^\d+$/.test(s)) {
      const n: number = Number.parseInt(s, 10);
      if (Number.isNaN(n)) {
        return -1;
      }
      // 10 位及以下视为秒（到 2286 年都不会溢出），13 位及以上视为毫秒
      return s.length <= 10 ? n * 1000 : n;
    }
    // 日期串：YYYY-MM-DD[ HH:MM[:SS]]
    const m: RegExpMatchArray | null = s.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?/);
    if (m === null) {
      return -1;
    }
    const y: number = Number.parseInt(m[1], 10);
    const mo: number = Number.parseInt(m[2], 10) - 1;
    const d: number = Number.parseInt(m[3], 10);
    const h: number = m[4] === undefined ? 0 : Number.parseInt(m[4], 10);
    const mi: number = m[5] === undefined ? 0 : Number.parseInt(m[5], 10);
    const se: number = m[6] === undefined ? 0 : Number.parseInt(m[6], 10);
    const t: number = new Date(y, mo, d, h, mi, se).getTime();
    return Number.isNaN(t) ? -1 : t;
  }

  /** 重新计算 postedAt（posted 被赋值后调用；也可由 parser 直接调用）。 */
  refreshPostedAt(): number {
    this.postedAt = GalleryInfo.parsePosted(this.posted);
    return this.postedAt;
  }

  /** 对齐 toCSV()：19 个字段 + 换行，分隔符与顺序逐字节保持（备份/恢复依赖）。 */
  toCSV(): string {
    return `${this.gid},${this.token},${this.title},${this.titleJpn},${this.thumb},` +
      `${this.category},${this.posted},${this.uploader},${this.rating},${this.rated},` +
      `${this.simpleLanguage === null ? 'null' : this.simpleLanguage},${GalleryInfo.arrayToString(this.simpleTags)},` +
      `${this.thumbWidth},${this.thumbHeight},${this.spanSize},${this.spanIndex},` +
      `${this.spanGroupIndex},${this.favoriteSlot},${this.favoriteName === null ? 'null' : this.favoriteName},` +
      `${this.pages}\n`;
  }

  /** 对齐 fromCSV(String)：字段数 < 20 或数字解析失败返回 null。 */
  static fromCSV(csv: string): GalleryInfo | null {
    const values: string[] = csv.split(',');
    if (values.length < 20) {
      return null;
    }
    const gi: GalleryInfo = new GalleryInfo();
    try {
      gi.gid = GalleryInfo.num(values[0]);
      gi.token = values[1];
      gi.title = values[2];
      gi.titleJpn = values[3];
      gi.thumb = values[4];
      gi.category = GalleryInfo.num(values[5]);
      gi.posted = values[6];
      gi.uploader = values[7];
      gi.rating = Number.parseFloat(values[8]);
      gi.rated = values[9] === 'true';
      gi.simpleLanguage = values[10] === 'null' ? null : values[10];
      // 上游：values[11].substring(1, len-1).split(", ")  ← Arrays.toString 的 "[a, b]" 形式
      const bracket: string = values[11];
      const inner: string = bracket.length >= 2 ? bracket.substring(1, bracket.length - 1) : '';
      gi.simpleTags = inner.length === 0 ? [] : inner.split(', ');
      gi.thumbWidth = GalleryInfo.num(values[12]);
      gi.thumbHeight = GalleryInfo.num(values[13]);
      gi.spanSize = GalleryInfo.num(values[14]);
      gi.spanIndex = GalleryInfo.num(values[15]);
      gi.spanGroupIndex = GalleryInfo.num(values[16]);
      gi.favoriteSlot = GalleryInfo.num(values[17]);
      gi.favoriteName = values[18] === 'null' ? null : values[18];
      gi.pages = GalleryInfo.num(values[19].trim());
    } catch (e) {
      return null;
    }
    if (Number.isNaN(gi.gid) || Number.isNaN(gi.rating)) {
      return null;
    }
    gi.refreshPostedAt();
    return gi;
  }

  private static num(s: string): number {
    const n: number = Number.parseInt(s.trim(), 10);
    if (Number.isNaN(n)) {
      // 上游是 NumberFormatException → 由外层 catch 转 null
      throw new Error('NumberFormatException: ' + s);
    }
    return n;
  }

  /** 对齐 Arrays.toString(String[])：`[a, b]`；null → "null"。 */
  private static arrayToString(a: string[] | null): string {
    if (a === null) {
      return 'null';
    }
    return '[' + a.join(', ') + ']';
  }

  /**
   * 对齐 toJson()（返回 JSONObject）。
   * ArkTS 版返回 JSON 字符串，**保持可覆写**：DownloadInfo 在上游覆写了 toJson()，
   * 虚分派语义必须保留 —— 通过 `toJson(): string` 的实例方法实现，子类 override 即可。
   * 字段集合与上游 put 的键逐个对应（含 `tgList` 会被包成 [[...]] 这一怪异行为，见下）。
   */
  toJson(): string {
    const obj: JsonMap = new JsonMap();
    obj.putNum('gid', this.gid);
    obj.putStr('token', this.token);
    obj.putStr('title', this.title);
    obj.putStr('titleJpn', this.titleJpn);
    obj.putStr('thumb', this.thumb);
    obj.putNum('category', this.category);
    obj.putStr('posted', this.posted);
    obj.putStr('uploader', this.uploader);
    obj.putNum('rating', this.rating);
    obj.putBool('rated', this.rated);
    obj.putStrOrNull('simpleLanguage', this.simpleLanguage);
    if (this.simpleTags !== null) {
      obj.putStrArray('simpleTags', this.simpleTags);
    }
    obj.putNum('thumbHeight', this.thumbHeight);
    obj.putNum('thumbWidth', this.thumbWidth);
    obj.putNum('spanSize', this.spanSize);
    obj.putNum('spanIndex', this.spanIndex);
    obj.putNum('spanGroupIndex', this.spanGroupIndex);
    obj.putNum('favoriteSlot', this.favoriteSlot);
    obj.putStrOrNull('favoriteName', this.favoriteName);
    // 上游：put("tgList", new JSONArray(Collections.singletonList(tgList))) → 单元素数组包一层
    obj.putNestedStrArray('tgList', this.tgList);
    obj.putNum('pages', this.pages);
    return obj.toJsonString();
  }

  /**
   * 对齐 galleryInfoFromJson(JSONObject)：手写映射 + 类型守卫（ArkTS 无反射）。
   * 注意：上游第 365 行 `object.getString("")` 是上游的 bug（取空键），
   * 这里按其意图取 "simpleLanguage"（差异登记在 MR）。
   */
  static fromJson(s: string): GalleryInfo {
    const src: JsonMap = JsonMap.parse(s);
    const gi: GalleryInfo = new GalleryInfo();
    gi.posted = src.getStr('posted', '');
    gi.category = src.getNum('category', 0);
    gi.favoriteName = src.getStrOrNull('favoriteName');
    gi.favoriteSlot = src.getNum('favoriteSlot', -2);
    gi.gid = src.getNum('gid', 0);
    gi.pages = src.getNum('pages', 0);
    gi.rated = src.getBool('rated', false);
    gi.rating = src.getNum('rating', 0);
    gi.simpleLanguage = src.getStrOrNull('simpleLanguage');
    gi.simpleTags = src.getStrArrayOrNull('simpleTags');
    gi.spanGroupIndex = src.getNum('spanGroupIndex', 0);
    gi.spanIndex = src.getNum('spanIndex', 0);
    gi.spanSize = src.getNum('spanSize', 0);
    gi.tgList = src.getNestedStrArrayOrNull('tgList');
    gi.thumb = src.getStr('thumb', '');
    gi.thumbHeight = src.getNum('thumbHeight', 0);
    gi.thumbWidth = src.getNum('thumbWidth', 0);
    gi.title = src.getStr('title', '');
    gi.titleJpn = src.getStr('titleJpn', '');
    gi.token = src.getStr('token', '');
    gi.uploader = src.getStr('uploader', '');
    gi.refreshPostedAt();
    return gi;
  }
}

/**
 * 极简 JSON 映射器（替代 fastjson 的 JSONObject）。
 * 为什么不用 `JSON.parse` 直接返回对象：ArkTS 禁止对 `any`/`Object` 做索引访问
 * （arkts-no-props-by-index），必须显式取值 + 类型守卫；这里把守卫集中在一处，
 * 各数据类的 fromJson 只写字段映射。
 */
/** JSON 值联合类型（ArkTS 不允许 Map 存 null 之外的任意 Object，故显式枚举）。 */
export type JsonValue = string | number | boolean | string[] | (string[] | null)[] | null;

/**
 * 极简 JSON 映射器（替代 fastjson 的 JSONObject）。
 * 为什么不用 `JSON.parse` 直接返回对象：ArkTS 禁止对 `any`/`Object` 做索引访问
 * （arkts-no-props-by-index），必须显式取值 + 类型守卫；这里把守卫集中在一处，
 * 各数据类的 fromJson 只写字段映射。
 */
export class JsonMap {
  private readonly _map: Map<string, JsonValue> = new Map<string, JsonValue>();

  static parse(s: string): JsonMap {
    const result: JsonMap = new JsonMap();
    if (s === null || s === undefined || s.trim().length === 0) {
      return result;
    }
    const raw: Object = JSON.parse(s) as Object;
    const record: Record<string, Object> = raw as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    for (let i = 0; i < keys.length; i++) {
      const v: Object = record[keys[i]];
      result._map.set(keys[i], JsonMap.toJsonValue(v));
    }
    return result;
  }

  /** Object → JsonValue（递归收窄数组，非法类型退化为字符串）。 */
  private static toJsonValue(v: Object): JsonValue {
    if (v === null || v === undefined) {
      return null;
    }
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
      return v as JsonValue;
    }
    if (v instanceof Array) {
      const arr: Object[] = v as Object[];
      const out: string[] = [];
      let allString: boolean = true;
      for (let i = 0; i < arr.length; i++) {
        const item: Object = arr[i];
        if (item instanceof Array) {
          allString = false;
          break;
        }
        out.push(item === null || item === undefined ? '' : `${item}`);
      }
      return allString ? out : JsonMap.toNested(v);
    }
    return `${v}`;
  }

  private static toNested(v: Object): JsonValue {
    const arr: Object[] = v as Object[];
    const out: (string[] | null)[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (item === null || item === undefined) {
        out.push(null);
      } else if (item instanceof Array) {
        const inner: Object[] = item as Object[];
        const innerOut: string[] = [];
        for (let k = 0; k < inner.length; k++) {
          innerOut.push(`${inner[k]}`);
        }
        out.push(innerOut);
      } else {
        out.push([`${item}`]);
      }
    }
    return out;
  }

  putStr(key: string, value: string): void {
    this._map.set(key, value);
  }

  putStrOrNull(key: string, value: string | null): void {
    this._map.set(key, value);
  }

  putNum(key: string, value: number): void {
    this._map.set(key, value);
  }

  putBool(key: string, value: boolean): void {
    this._map.set(key, value);
  }

  putStrArray(key: string, value: string[]): void {
    this._map.set(key, value);
  }

  /** 上游 `new JSONArray(Collections.singletonList(list))` → `[[...]]`（list 为 null 时 `[null]`）。 */
  putNestedStrArray(key: string, value: string[] | null): void {
    if (value === null) {
      this._map.set(key, [null]);
    } else {
      this._map.set(key, [value]);
    }
  }

  getStr(key: string, def: string): string {
    const v: JsonValue | undefined = this._map.get(key);
    if (v === undefined || v === null) {
      return def;
    }
    if (typeof v === 'string') {
      return v as string;
    }
    if (v instanceof Array) {
      return def;
    }
    return `${v}`;
  }

  getStrOrNull(key: string): string | null {
    const v: JsonValue | undefined = this._map.get(key);
    if (v === undefined || v === null) {
      return null;
    }
    if (typeof v === 'string') {
      return v as string;
    }
    if (v instanceof Array) {
      return null;
    }
    return `${v}`;
  }

  getNum(key: string, def: number): number {
    const v: JsonValue | undefined = this._map.get(key);
    if (v === undefined || v === null || v instanceof Array) {
      return def;
    }
    if (typeof v === 'number') {
      return v as number;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 1 : 0;
    }
    const n: number = Number.parseFloat(v as string);
    return Number.isNaN(n) ? def : n;
  }

  getBool(key: string, def: boolean): boolean {
    const v: JsonValue | undefined = this._map.get(key);
    if (v === undefined || v === null || v instanceof Array) {
      return def;
    }
    if (typeof v === 'boolean') {
      return v as boolean;
    }
    if (typeof v === 'number') {
      return (v as number) !== 0;
    }
    return (v as string).toLowerCase() === 'true';
  }

  getStrArrayOrNull(key: string): string[] | null {
    const v: JsonValue | undefined = this._map.get(key);
    if (v === undefined || v === null) {
      return null;
    }
    if (!(v instanceof Array)) {
      return null;
    }
    const arr: Object[] = v as Object[];
    if (arr.length === 0) {
      return [];
    }
    // 扁平形态 [a, b]：元素是基本类型
    if (!(arr[0] instanceof Array)) {
      const flat: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        if (arr[i] !== null && arr[i] !== undefined) {
          flat.push(String(arr[i]));
        }
      }
      return flat;
    }
    // 嵌套形态 [[a, b]]：拍平第一层
    const first: Object[] = arr[0] as Object[];
    const out: string[] = [];
    for (let i = 0; i < first.length; i++) {
      if (first[i] !== null && first[i] !== undefined) {
        out.push(String(first[i]));
      }
    }
    return out;
  }

  /** 解 `[[a, b]]` 与 `[a, b]` 两种形态（上游写的是前者，fastjson 读出时会被拍平）。 */
  getNestedStrArrayOrNull(key: string): string[] | null {
    const v: JsonValue | undefined = this._map.get(key);
    if (v === undefined) {
      return null;
    }
    if (v === null) {
      return null;
    }
    if (v instanceof Array) {
      const arr: (string[] | null)[] = v as (string[] | null)[];
      const out: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        const item: string[] | null = arr[i];
        if (item === null) {
          continue;
        }
        for (let k = 0; k < item.length; k++) {
          out.push(item[k]);
        }
      }
      return out.length === 0 ? null : out;
    }
    return null;
  }

  has(key: string): boolean {
    return this._map.has(key);
  }

  toJsonString(): string {
    const rec: Record<string, Object> = {};
    this._map.forEach((v: JsonValue, k: string) => {
      rec[k] = v as Object;
    });
    return JSON.stringify(rec);
  }
}
