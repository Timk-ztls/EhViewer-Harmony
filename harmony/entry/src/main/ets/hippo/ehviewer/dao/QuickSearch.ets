/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/QuickSearch.java（GreenDAO 生成实体）
 *
 * 列映射逐字保留（10 列）：
 *   id→"_id"(INTEGER PK)、name→"NAME"、mode→"MODE"、category→"CATEGORY"、keyword→"KEYWORD"、
 *   advanceSearch→"ADVANCE_SEARCH"、minRating→"MIN_RATING"、pageFrom→"PAGE_FROM"、pageTo→"PAGE_TO"、
 *   time→"TIME"
 * 上游 `Long id` / `String name` 可空 → ArkTS `number | undefined` / `string | undefined`；
 * 其余 int/long 为非空基本类型 → number（默认 0，与建表 NOT NULL + DEFAULT 语义一致）。
 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */

import { JsonMap } from '../client/data/GalleryInfo';
import { QuickSearchLike } from '../client/data/ListUrlBuilder';

export class QuickSearch implements QuickSearchLike {
  public id: number | null = null;
  public name: string | null = null;
  public mode: number = 0;
  public category: number = 0;
  public keyword: string | null = null;
  public advanceSearch: number = 0;
  public minRating: number = 0;
  public pageFrom: number = 0;
  public pageTo: number = 0;
  public time: number = 0;

  constructor(id?: number, name?: string, mode?: number, category?: number, keyword?: string,
    advanceSearch?: number, minRating?: number, pageFrom?: number, pageTo?: number, time?: number) {
    this.id = id !== undefined ? id : null;
    this.name = name !== undefined ? name : null;
    this.mode = mode !== undefined ? mode : 0;
    this.category = category !== undefined ? category : 0;
    this.keyword = keyword !== undefined ? keyword : null;
    this.advanceSearch = advanceSearch !== undefined ? advanceSearch : 0;
    this.minRating = minRating !== undefined ? minRating : 0;
    this.pageFrom = pageFrom !== undefined ? pageFrom : 0;
    this.pageTo = pageTo !== undefined ? pageTo : 0;
    this.time = time !== undefined ? time : 0;
  }

  getId(): number | null {
    return this.id !== null ? this.id : null;
  }

  setId(id: number | null): void {
    this.id = id;
  }

  getName(): string | null {
    return this.name !== null ? this.name : null;
  }

  setName(name: string | null): void {
    this.name = name;
  }

  getMode(): number {
    return this.mode;
  }

  setMode(mode: number): void {
    this.mode = mode;
  }

  getCategory(): number {
    return this.category;
  }

  setCategory(category: number): void {
    this.category = category;
  }

  getKeyword(): string | null {
    return this.keyword !== null ? this.keyword : null;
  }

  setKeyword(keyword: string | null): void {
    this.keyword = keyword;
  }

  getAdvanceSearch(): number {
    return this.advanceSearch;
  }

  setAdvanceSearch(advanceSearch: number): void {
    this.advanceSearch = advanceSearch;
  }

  getMinRating(): number {
    return this.minRating;
  }

  setMinRating(minRating: number): void {
    this.minRating = minRating;
  }

  getPageFrom(): number {
    return this.pageFrom;
  }

  setPageFrom(pageFrom: number): void {
    this.pageFrom = pageFrom;
  }

  getPageTo(): number {
    return this.pageTo;
  }

  setPageTo(pageTo: number): void {
    this.pageTo = pageTo;
  }

  getTime(): number {
    return this.time;
  }

  setTime(time: number): void {
    this.time = time;
  }

  toString(): string {
    return this.name !== null ? this.name : '';
  }

  toJson(): string {
    const parts: string[] = [
      `"name":${this.name !== null ? JSON.stringify(this.name) : 'null'}`,
      `"mode":${this.mode}`,
      `"category":${this.category}`,
      `"keyword":${this.keyword !== null ? JSON.stringify(this.keyword) : 'null'}`,
      `"advanceSearch":${this.advanceSearch}`,
      `"minRating":${this.minRating}`,
      `"pageFrom":${this.pageFrom}`,
      `"pageTo":${this.pageTo}`,
      `"time":${this.time}`
    ];
    return `{${parts.join(',')}}`;
  }

  static quickSearchFromJson(s: string): QuickSearch {
    const map: JsonMap = JsonMap.parse(s);
    const qs: QuickSearch = new QuickSearch();
    qs.setName(map.getStrOrNull('name'));
    qs.setMode(map.getNum('mode', 0));
    qs.setCategory(map.getNum('category', 0));
    qs.setKeyword(map.getStrOrNull('keyword'));
    qs.setAdvanceSearch(map.getNum('advanceSearch', 0));
    qs.setMinRating(map.getNum('minRating', 0));
    qs.setPageFrom(map.getNum('pageFrom', 0));
    qs.setPageTo(map.getNum('pageTo', 0));
    qs.setTime(map.getNum('time', 0));
    return qs;
  }
}
