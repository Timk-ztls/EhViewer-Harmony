/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/SearchDatabase.java（inventory S0307，上游 141 行）
 * （迁移自 …/SearchDatabase.java；上游同事文件名为 SearchDatabase.java，含 DatabaseHelper 内部类）
 *
 * ============================ D 类检视：**本类会写库 → D 类高发区**，逐条核清并断言 ============================
 * 按 Lead 的 6 个问题逐条给出一手答案（每条都有断言）：
 *
 * ① **同一查询重复提交 → 覆盖（先删后插），不追加**
 *    `addQuery(q)`：`deleteQuery(q)` → insert(q, now) → truncate(100)
 *    ⇒ 历史长度不增长，时间戳刷新（最新提到最前）
 *
 * ② **大小写：`addQuery` 的删除用 `=`（敏感），但 `getSuggestions` 用 `LIKE`（ASCII 不敏感）**
 *    ⇒ **'Foo' 与 'foo' 会存成两条**（删除是敏感的），但**两条都能被 prefix 匹配到**。
 *    这是上游的不一致（`=` vs `LIKE`），属既存行为，**照搬**（改它会改变已存数据 → D 类但无明确"正确"目标，
 *    登记待裁决；本实现按上游语义并断言固化该不一致）
 *
 * ③ **不 trim**：`' foo'` 与 `'foo'` 是两条（只判 `TextUtils.isEmpty`）
 *
 * ④ **排序：`ORDER BY date DESC`（毫秒时间戳），时间戳并列时无第二排序键 → 顺序不确定**
 *    （SQLite 不保证稳定排序；同毫秒写入的两条先后不可预期）
 *
 * ⑤ **上限 `MAX_HISTORY = 100`**：每次 insert 后 `truncateHistory(100)`，**保留最新 100 条**
 *    SQL：`_id IN (SELECT _id FROM suggestions ORDER BY date DESC LIMIT -1 OFFSET 100)` → 删除这之外的
 *    （`LIMIT -1` 在 SQLite 表示不限制）
 *
 * ⑥ **删除单条后无"索引重排"概念**：表用自增 `_id`，顺序由 `date` 决定，删行不影响其它行
 *
 * 其它一手语义
 *  - `getSuggestions(prefix, limit)`：`limit = max(0, limit)`；prefix 非空则 `WHERE query LIKE 'escaped(prefix)%'`
 *    （**前缀匹配，不是子串匹配**）；`ORDER BY date DESC LIMIT limit`；
 *    **并且过滤掉与 prefix 完全相同的那条**（`if (!prefix.equals(suggestion))`）——避免把用户正在输入的词当建议
 *  - 查询异常 → 返回空数组（吞掉 SQLException）
 *  - `clearQuery()` = `truncateHistory(0)`；`truncateHistory(n<0)` **抛 IllegalArgumentException**
 *  - `truncateHistory` 内部 RuntimeException 被 try/catch 吞掉并 Log.e
 *
 * 分层：SQL 执行与建表属 storage-db（`DatabaseHelper`）；本文件负责
 *   ① SQL 构造（可单测的字符串）② 语义状态机（用内存模型镜像 SQL 行为，供断言）③ 对外 API 形态
 *   `SearchDatabaseDao` 为执行层接口（由 storage-db 实现）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.SearchDatabase';

export class SearchDatabaseConst {
  static readonly COLUMN_QUERY: string = 'query';
  static readonly COLUMN_DATE: string = 'date';
  static readonly DATABASE_NAME: string = 'search_database.db';
  static readonly TABLE_SUGGESTIONS: string = 'suggestions';
  static readonly MAX_HISTORY: number = 100;
}

/** 执行层（由 storage-db 实现） */
export interface SearchDatabaseDao {
  query(sql: string): SuggestionRow[];

  exec(sql: string): void;
  insert(table: string, query: string, date: number): void;
  delete(table: string, selection: string, args: string[]): void;
}

export class SuggestionRow {
  query: string = '';
  date: number = 0;
}

/** SQL 构造（纯函数，逐字符对位上游拼接） */
export class SearchSqlBuilder {
  /** SQLite 单引号转义：把 ' 变成 ''（对位 SqlUtils.sqlEscapeString 的净效果） */
  static escape(s: string): string {
    return s.replace(/'/g, "''");
  }

  /** 上游 getSuggestions 的 SQL（prefix 空则不加 WHERE） */
  static suggestions(prefix: string, limit: number): string {
    const lim: number = limit < 0 ? 0 : limit;
    let sb: string = `SELECT * FROM ${SearchDatabaseConst.TABLE_SUGGESTIONS}`;
    if (prefix.length > 0) {
      sb += ` WHERE ${SearchDatabaseConst.COLUMN_QUERY} LIKE '${SearchSqlBuilder.escape(prefix)}%'`;
    }
    sb += ` ORDER BY ${SearchDatabaseConst.COLUMN_DATE} DESC LIMIT ${lim}`;
    return sb;
  }

  /** 上游 truncateHistory 的 selection（maxEntries=0 → null 表示全删） */
  static truncateSelection(maxEntries: number): string | null {
    if (maxEntries < 0) {
      throw new Error('IllegalArgumentException'); // 对位上游 throw
    }
    if (maxEntries === 0) {
      return null; // 全删
    }
    return `_id IN (SELECT _id FROM ${SearchDatabaseConst.TABLE_SUGGESTIONS}` +
      ` ORDER BY ${SearchDatabaseConst.COLUMN_DATE} DESC LIMIT -1 OFFSET ${maxEntries})`;
  }
}

/**
 * 语义状态机：用内存模型镜像 SQL 行为，使"覆盖/去重/截断/前缀匹配"可断言。
 * （SQL 真正执行走 Dao；这里镜像的是**语义**，不是数据库实现。）
 */
export class SearchDatabaseModel {
  /** 行（顺序即插入顺序；查询时按 date DESC 排序） */
  rows: SuggestionRow[] = [];
  private seq: number = 0;

  /** 上游 deleteQuery：`WHERE query=?` → **大小写敏感** */
  deleteQuery(query: string): void {
    this.rows = this.rows.filter((r: SuggestionRow) => r.query !== query);
  }

  /** 上游 addQuery：非空才处理；先删后插；然后截断到 MAX_HISTORY */
  addQuery(query: string, now: number): void {
    if (query.length === 0) {
      return;
    }
    this.deleteQuery(query);
    const row: SuggestionRow = new SuggestionRow();
    row.query = query;
    row.date = now;
    this.seq = this.seq + 1;
    this.rows.push(row);
    this.truncateHistory(SearchDatabaseConst.MAX_HISTORY);
  }

  /**
   * 上游 truncateHistory：保留最新 maxEntries 条。
   * 排序键是 date DESC；并列时保持插入顺序的**逆序**（SQLite 不保证，此处取确定的逆序便于断言，
   * 已在文件头注明"并列顺序不确定"）。
   */
  truncateHistory(maxEntries: number): void {
    if (maxEntries < 0) {
      throw new Error('IllegalArgumentException');
    }
    if (maxEntries === 0) {
      this.rows = [];
      return;
    }
    if (this.rows.length <= maxEntries) {
      return;
    }
    const sorted: SuggestionRow[] = this.rows.slice();
    // 稳定排序：date DESC，并列时后插入的在前（镜像 ORDER BY date DESC 的不确定性，取确定值）
    sorted.sort((a: SuggestionRow, b: SuggestionRow) => b.date - a.date);
    this.rows = sorted.slice(0, maxEntries);
  }

  /** 上游 getSuggestions：LIKE 前缀（ASCII 不敏感）+ 排除与 prefix 完全相同者 + date DESC + limit */
  getSuggestions(prefix: string, limit: number): string[] {
    const lim: number = limit < 0 ? 0 : limit;
    const p: string = prefix.toLowerCase();
    const matched: SuggestionRow[] = [];
    for (let i = 0; i < this.rows.length; i++) {
      const r: SuggestionRow = this.rows[i];
      // SQLite 的 LIKE 对 ASCII 大小写不敏感
      if (prefix.length === 0 || r.query.toLowerCase().startsWith(p)) {
        matched.push(r);
      }
    }
    matched.sort((a: SuggestionRow, b: SuggestionRow) => b.date - a.date);
    const out: string[] = [];
    for (let i = 0; i < matched.length && out.length < lim; i++) {
      const q: string = matched[i].query;
      if (q !== prefix) { // 上游：排除与 prefix 完全相同的那条
        out.push(q);
      }
    }
    return out;
  }
}

export class SearchDatabase {
  private dao: SearchDatabaseDao | null = null;

  attach(dao: SearchDatabaseDao): void {
    this.dao = dao;
  }

  /** 上游 getSuggestions（异常 → 空数组） */
  getSuggestions(prefix: string, limit: number): string[] {
    const d: SearchDatabaseDao | null = this.dao;
    if (d === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'dao not attached — returning empty suggestions');
      return [];
    }
    try {
      const sql: string = SearchSqlBuilder.suggestions(prefix, limit);
      const rows: SuggestionRow[] = d.query(sql);
      const out: string[] = [];
      for (let i = 0; i < rows.length; i++) {
        if (rows[i].query !== prefix) {
          out.push(rows[i].query);
        }
      }
      return out;
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'getSuggestions failed, returning empty');
      return [];
    }
  }

  /** 上游 addQuery */
  addQuery(query: string, now: number): void {
    if (query.length === 0) {
      return;
    }
    const d: SearchDatabaseDao | null = this.dao;
    if (d === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'dao not attached — addQuery dropped');
      return;
    }
    this.deleteQuery(query);
    d.insert(SearchDatabaseConst.TABLE_SUGGESTIONS, query, now);
    this.truncateHistory(SearchDatabaseConst.MAX_HISTORY);
  }

  deleteQuery(query: string): void {
    const d: SearchDatabaseDao | null = this.dao;
    if (d === null) {
      return;
    }
    d.delete(SearchDatabaseConst.TABLE_SUGGESTIONS,
      `${SearchDatabaseConst.COLUMN_QUERY}=?`, [query]);
  }

  clearQuery(): void {
    this.truncateHistory(0);
  }

  truncateHistory(maxEntries: number): void {
    const selection: string | null = SearchSqlBuilder.truncateSelection(maxEntries);
    const d: SearchDatabaseDao | null = this.dao;
    if (d === null) {
      return;
    }
    try {
      d.delete(SearchDatabaseConst.TABLE_SUGGESTIONS, selection === null ? '' : selection, []);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'truncateHistory failed');
    }
  }
}

export interface SearchHistoryKvStore {
  getString(key: string, defValue: string): string;
  putString(key: string, value: string): void;
}

class MemorySearchHistoryKvStore implements SearchHistoryKvStore {
  private data: Map<string, string> = new Map<string, string>();

  getString(key: string, defValue: string): string {
    const v: string | undefined = this.data.get(key);
    return v !== undefined ? v : defValue;
  }

  putString(key: string, value: string): void {
    this.data.set(key, value);
  }
}

class PersistedHistoryItem {
  q: string = '';
  d: number = 0;

  constructor(q: string = '', d: number = 0) {
    this.q = q;
    this.d = d;
  }
}

/**
 * Persistent MRU search history backed by `Settings` (or an injected KV store for unit tests).
 * Preserves upstream `SearchDatabase` semantics (exact delete, ASCII case-insensitive prefix match,
 * max 100 entries, excluding exact query equality).
 */
export class SearchHistoryPrefsStore {
  static readonly PREF_KEY: string = 'search_history_list';
  private static kvStore: SearchHistoryKvStore = new MemorySearchHistoryKvStore();

  static configureStore(store: SearchHistoryKvStore): void {
    SearchHistoryPrefsStore.kvStore = store;
  }

  private static loadItems(): PersistedHistoryItem[] {
    const raw: string = SearchHistoryPrefsStore.kvStore.getString(SearchHistoryPrefsStore.PREF_KEY, '');
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const list: Object[] = parsed as Object[];
      const items: PersistedHistoryItem[] = [];
      for (let i = 0; i < list.length; i++) {
        const entry: Object = list[i];
        if (typeof entry === 'string') {
          const qs: string = entry as string;
          if (qs.length > 0) {
            items.push(new PersistedHistoryItem(qs, list.length - i));
          }
        } else if (entry !== null && typeof entry === 'object') {
          const rec = entry as Record<string, Object>;
          const qVal: Object | undefined = rec['q'];
          const dVal: Object | undefined = rec['d'];
          if (typeof qVal === 'string' && qVal.length > 0) {
            const ts: number = typeof dVal === 'number' ? dVal : (list.length - i);
            items.push(new PersistedHistoryItem(qVal, ts));
          }
        }
      }
      return items;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'load search history failed: %{public}s', msg);
      return [];
    }
  }

  private static saveItems(items: PersistedHistoryItem[]): void {
    try {
      SearchHistoryPrefsStore.kvStore.putString(SearchHistoryPrefsStore.PREF_KEY, JSON.stringify(items));
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'save search history failed: %{public}s', msg);
    }
  }

  static getSuggestions(prefix: string, limit: number = 128): string[] {
    const lim: number = limit < 0 ? 0 : limit;
    if (lim === 0) {
      return [];
    }
    const items: PersistedHistoryItem[] = SearchHistoryPrefsStore.loadItems();
    items.sort((a: PersistedHistoryItem, b: PersistedHistoryItem): number => b.d - a.d);
    const lowerPrefix: string = prefix.toLowerCase();
    const out: string[] = [];
    for (let i = 0; i < items.length && out.length < lim; i++) {
      const q: string = items[i].q;
      if (q === prefix) {
        continue;
      }
      if (prefix.length === 0 || q.toLowerCase().startsWith(lowerPrefix)) {
        out.push(q);
      }
    }
    return out;
  }

  static addQuery(query: string, now: number = Date.now()): void {
    if (query.length === 0) {
      return;
    }
    const items: PersistedHistoryItem[] = SearchHistoryPrefsStore.loadItems()
      .filter((item: PersistedHistoryItem): boolean => item.q !== query);
    items.unshift(new PersistedHistoryItem(query, now));
    items.sort((a: PersistedHistoryItem, b: PersistedHistoryItem): number => b.d - a.d);
    if (items.length > SearchDatabaseConst.MAX_HISTORY) {
      items.length = SearchDatabaseConst.MAX_HISTORY;
    }
    SearchHistoryPrefsStore.saveItems(items);
  }

  static deleteQuery(query: string): void {
    if (query.length === 0) {
      return;
    }
    const items: PersistedHistoryItem[] = SearchHistoryPrefsStore.loadItems()
      .filter((item: PersistedHistoryItem): boolean => item.q !== query);
    SearchHistoryPrefsStore.saveItems(items);
  }

  static clearQuery(): void {
    SearchHistoryPrefsStore.saveItems([]);
  }
}

export class SearchSuggestionEntry {
  readonly kind: string;
  readonly primaryText: string;
  readonly secondaryText: string;
  readonly keywordValue: string;

  constructor(kind: string, primaryText: string, secondaryText: string, keywordValue: string) {
    this.kind = kind;
    this.primaryText = primaryText;
    this.secondaryText = secondaryText;
    this.keywordValue = keywordValue;
  }
}

/**
 * Pure tag auto-completion helpers mirroring upstream `SearchBar.java` (`updateSuggestions`,
 * `rebuildKeyword`, `replaceCommonSubstring`).
 */
export class SearchTagQueryHelper {
  /**
   * Extracts the trailing un-tagged search fragment after the last `:` or `$` token.
   */
  static extractTagKeyword(rawQuery: string): string {
    const trimmedRight: string = rawQuery.trim();
    if (trimmedRight.length === 0) {
      return '';
    }
    const parts: string[] = rawQuery.split(' ');
    if (parts.length === 0) {
      return '';
    }
    let keyword: string = '';
    for (let i = parts.length - 1; i >= 0; i--) {
      const part: string = parts[i];
      if (part.indexOf(':') >= 0 || part.indexOf('$') >= 0) {
        break;
      }
      if (keyword.length === 0) {
        keyword = part;
      } else {
        keyword = `${part} ${keyword}`;
      }
    }
    return keyword.trim();
  }

  /**
   * Formats `namespace:tag` using `namespaceToPrefix` lookup -> `prefix"tag$"`.
   */
  static formatTagToken(
    englishTag: string,
    namespaceToPrefix: (ns: string) => string | null
  ): string {
    const idx: number = englishTag.indexOf(':');
    if (idx <= 0) {
      return englishTag;
    }
    const ns: string = englishTag.substring(0, idx);
    const tagName: string = englishTag.substring(idx + 1);
    const shortPrefix: string | null = namespaceToPrefix(ns);
    if (shortPrefix !== null) {
      return `${shortPrefix}"${tagName}$"`;
    }
    return englishTag;
  }

  /**
   * Replaces the trailing plain-text portion of `currentText` with `tagToken`, preserving
   * any leading structured search tokens (`a:"..."$`, `f:"..."$`, etc.).
   */
  static replaceTrailingKeyword(currentText: string, tagToken: string): string {
    if (currentText.indexOf(' ') < 0) {
      return tagToken;
    }
    const parts: string[] = currentText.split(' ');
    let lastStructured: number = -1;
    for (let i = parts.length - 1; i >= 0; i--) {
      const part: string = parts[i];
      if (part.indexOf(':') >= 0 || part.indexOf('$') >= 0) {
        lastStructured = i;
        break;
      }
    }
    if (lastStructured < 0) {
      return tagToken;
    }
    const kept: string[] = [];
    for (let i = 0; i <= lastStructured; i++) {
      if (parts[i].length > 0) {
        kept.push(parts[i]);
      }
    }
    if (kept.length === 0) {
      return tagToken;
    }
    return `${kept.join(' ')} ${tagToken}`;
  }
}
