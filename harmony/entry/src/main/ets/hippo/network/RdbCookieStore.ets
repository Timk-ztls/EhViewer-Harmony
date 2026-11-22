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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { Cookie } from '../okhttp/Cookie';
import { CookieStoreBackend } from './CookieRepository';
import { CookieTable } from './CookieDatabase';

const DOMAIN: number = 0x0000;
const TAG: string = 'RdbCookieStore';

/**
 * `OK_HTTP_3_COOKIE` 表的最小执行面（**测试可替身**）。
 *
 * 为什么不直接吃 `relationalStore.RdbStore`：ArkTS 不支持结构化类型，
 * 单测里无法用"形状相同的假对象"替代真实 `RdbStore`。所以这里只声明我们真正用到的两个方法，
 * 生产侧由 `AppWiring` 传一个 5 行的适配器（或由 storage-db 提供现成实现）。
 */
export interface CookieDbLike {
  /** 对齐 `RdbStore.querySql(sql)`；结果集按行游标遍历。 */
  querySql(sql: string): Promise<CookieResultSetLike>;
  /** 对齐 `RdbStore.executeSql(sql, args)`。 */
  executeSql(sql: string, args: (string | number)[]): Promise<void>;
}

/** 结果集最小面（对齐 `relationalStore.ResultSet` 我们用到的那几个方法）。 */
export interface CookieResultSetLike {
  goToNextRow(): boolean;
  getColumnIndex(name: string): number;
  isColumnNull(index: number): boolean;
  getString(index: number): string;
  getLong(index: number): number;
  close(): void;
}

/**
 * `CookieStoreBackend` 的 **RDB 持久实现**（W-022）。
 *
 * ## 为什么是"内存缓存 + 异步落库"而不是每次读写都过 RDB
 * `CookieStoreBackend` 的 6 个方法**全同步**（`CookieRepository` 在 OkHttp 拦截器链里同步调），
 * 而 `relationalStore` 全是 `Promise`。上游 Android 的解法就是这个：
 * > 启动时异步把全部 cookie 读进内存 → 之后**读全走内存**，写走「内存 + fire-and-forget 落库」。
 *
 * 于是 `open()` 是**唯一需要 await 的入口**，`AppWiring.wire()` 里 await 一次即可；
 * 之后 `EhCookieStore` 的所有同步调用路径都不变。
 *
 * ## 三条硬要求（今天全组踩过的同类坑）
 *   1. **fire-and-forget 必须 `.catch()`** —— 否则出现无人接的 Promise rejection（`check_silent_failures -Gate` 会扫）
 *   2. **"未加载" ≠ "没有 cookie"** —— 用 `isLoaded()` 观测，`open()` 之前 `getAllCookies()` 返回空 Map
 *      但那是"还没读"，不是"确实没有"；调用方（AppWiring）必须 await `open()` 之后再放行
 *   3. **过期行在加载时就过滤**（`CookieTable.isValidRow`），并把它们**从表里删掉** ——
 *      上游 `getCookie(cursor, now)` 判过期后就是删行，否则表会无限增长
 */
export class RdbCookieStore implements CookieStoreBackend {
  /** `name\0domain\0path` → Cookie（与 `InMemoryCookieStore` 的键口径一致）。 */
  private _rows: Map<string, Cookie> = new Map<string, Cookie>();
  private _loaded: boolean = false;
  private _closed: boolean = false;
  private _store: CookieDbLike | null = null;
  /** 落库失败计数（诊断用：只看数量，不刷日志）。 */
  private _flushFailures: number = 0;
  /** 串行化异步落库队列，防止 update() 的 DELETE 与 INSERT 乱序。 */
  private _writeChain: Promise<void> = Promise.resolve();

  /**
   * 载入：把表里的有效行读进内存缓存。**必须在 `wire()` 里 await 一次**。
   *
   * 过期/坏行以及旧库遗留的重复行会被删除（对齐上游 `getCookie` 里"判过期即删"）。
   */
  async open(store: CookieDbLike): Promise<void> {
    this._store = store;
    const result: CookieResultSetLike = await store.querySql(
      `SELECT * FROM ${CookieTable.TABLE_COOKIE}`);
    const now: number = Date.now();
    const obsoleteIds: number[] = [];
    const seenIds: Map<string, number> = new Map<string, number>();
    try {
      const iId: number = result.getColumnIndex(CookieTable.COLUMN_ID);
      const iName: number = result.getColumnIndex(CookieTable.COLUMN_NAME);
      const iValue: number = result.getColumnIndex(CookieTable.COLUMN_VALUE);
      const iExpires: number = result.getColumnIndex(CookieTable.COLUMN_EXPIRES_AT);
      const iDomain: number = result.getColumnIndex(CookieTable.COLUMN_DOMAIN);
      const iPath: number = result.getColumnIndex(CookieTable.COLUMN_PATH);
      const iSecure: number = result.getColumnIndex(CookieTable.COLUMN_SECURE);
      const iHttpOnly: number = result.getColumnIndex(CookieTable.COLUMN_HTTP_ONLY);
      const iPersistent: number = result.getColumnIndex(CookieTable.COLUMN_PERSISTENT);
      const iHostOnly: number = result.getColumnIndex(CookieTable.COLUMN_HOST_ONLY);
      while (result.goToNextRow()) {
        const id: number = RdbCookieStore.readLongOr(result, iId, -1);
        const name: string | null = RdbCookieStore.readNullableString(result, iName);
        const domain: string | null = RdbCookieStore.readNullableString(result, iDomain);
        const path: string | null = RdbCookieStore.readNullableString(result, iPath);
        const expiresAt: number = RdbCookieStore.readLongOr(result, iExpires, 0);
        const persistent: boolean = RdbCookieStore.readLongOr(result, iPersistent, 0) !== 0;
        if (!CookieTable.isValidRow(name, domain, path, persistent, expiresAt, now)) {
          // 上游：判过期即删（坏行 name/domain/path 为 null/空串 也在此列）
          if (id >= 0) {
            obsoleteIds.push(id);
          }
          continue;
        }
        const valueStr: string | null = RdbCookieStore.readNullableString(result, iValue);
        const secure: boolean = RdbCookieStore.readLongOr(result, iSecure, 0) !== 0;
        const httpOnly: boolean = RdbCookieStore.readLongOr(result, iHttpOnly, 0) !== 0;
        const hostOnly: boolean = RdbCookieStore.readLongOr(result, iHostOnly, 0) !== 0;
        const cookie: Cookie = new Cookie(
          name as string, valueStr === null ? '' : valueStr, expiresAt,
          domain as string, path as string, secure, httpOnly, persistent, hostOnly);
        const key: string = RdbCookieStore.keyOf(cookie);
        const prevId: number | undefined = seenIds.get(key);
        if (prevId !== undefined && prevId >= 0) {
          obsoleteIds.push(prevId);
        }
        if (id >= 0) {
          seenIds.set(key, id);
        }
        this._rows.set(key, cookie);
      }
    } finally {
      result.close();
    }
    for (let i = 0; i < obsoleteIds.length; i++) {
      this.fireAndForget(
        `DELETE FROM ${CookieTable.TABLE_COOKIE} WHERE ${CookieTable.COLUMN_ID} = ?`,
        [obsoleteIds[i]], 'deleteExpired');
    }
    this._loaded = true;
    hilog.info(DOMAIN, TAG, 'cookie store loaded: rows=%{public}d expired=%{public}d',
      this._rows.size, obsoleteIds.length);
  }

  private static readNullableString(result: CookieResultSetLike, index: number): string | null {
    if (index < 0 || result.isColumnNull(index)) {
      return null;
    }
    return result.getString(index);
  }

  private static readLongOr(result: CookieResultSetLike, index: number, fallback: number): number {
    if (index < 0 || result.isColumnNull(index)) {
      return fallback;
    }
    return result.getLong(index);
  }

  /** 观测面：缓存是否已从 DB 载入（**"未加载" ≠ "没有 cookie"**）。 */
  isLoaded(): boolean {
    return this._loaded;
  }

  /** 观测面：落库失败次数（> 0 说明持久化在丢写，需要查 RDB）。 */
  flushFailures(): number {
    return this._flushFailures;
  }

  /** 等待挂起的异步写队列排空（供测试与关闭前等待）。 */
  flush(): Promise<void> {
    return this._writeChain;
  }

  getAllCookies(): Map<string, Cookie[]> {
    const out: Map<string, Cookie[]> = new Map<string, Cookie[]>();
    const now: number = Date.now();
    this._rows.forEach((cookie: Cookie): void => {
      if (!CookieTable.isValidRow(cookie.name(), cookie.domain(), cookie.path(),
        cookie.persistent(), cookie.expiresAt(), now)) {
        return;
      }
      const domain: string = cookie.domain();
      let list: Cookie[] | undefined = out.get(domain);
      if (list === undefined) {
        list = [];
        out.set(domain, list);
      }
      (list as Cookie[]).push(cookie);
    });
    return out;
  }

  add(cookie: Cookie): void {
    if (!cookie.persistent()) {
      return; // 非持久化 cookie 不入库（上游同样跳过）
    }
    this._rows.set(RdbCookieStore.keyOf(cookie), cookie);
    this.fireAndForget(
      `INSERT OR REPLACE INTO ${CookieTable.TABLE_COOKIE} (${CookieTable.COLUMN_NAME}, ` +
      `${CookieTable.COLUMN_VALUE}, ${CookieTable.COLUMN_EXPIRES_AT}, ${CookieTable.COLUMN_DOMAIN}, ` +
      `${CookieTable.COLUMN_PATH}, ${CookieTable.COLUMN_SECURE}, ${CookieTable.COLUMN_HTTP_ONLY}, ` +
      `${CookieTable.COLUMN_PERSISTENT}, ${CookieTable.COLUMN_HOST_ONLY}) VALUES (?,?,?,?,?,?,?,?,?)`,
      [cookie.name(), cookie.value(), cookie.expiresAt(), cookie.domain(), cookie.path(),
        cookie.secure() ? 1 : 0, cookie.httpOnly() ? 1 : 0, 1, cookie.hostOnly() ? 1 : 0],
      'add');
  }

  update(oldCookie: Cookie, newCookie: Cookie): void {
    this._rows.delete(RdbCookieStore.keyOf(oldCookie));
    this.fireAndForget(
      `DELETE FROM ${CookieTable.TABLE_COOKIE} WHERE ${CookieTable.COLUMN_NAME} = ? AND ` +
      `${CookieTable.COLUMN_DOMAIN} = ? AND ${CookieTable.COLUMN_PATH} = ?`,
      [oldCookie.name(), oldCookie.domain(), oldCookie.path()], 'updateDelete');
    this.add(newCookie);
  }

  remove(cookie: Cookie): void {
    this._rows.delete(RdbCookieStore.keyOf(cookie));
    this.fireAndForget(
      `DELETE FROM ${CookieTable.TABLE_COOKIE} WHERE ${CookieTable.COLUMN_NAME} = ? AND ` +
      `${CookieTable.COLUMN_DOMAIN} = ? AND ${CookieTable.COLUMN_PATH} = ?`,
      [cookie.name(), cookie.domain(), cookie.path()], 'remove');
  }

  clear(): void {
    this._rows.clear();
    this.fireAndForget(`DELETE FROM ${CookieTable.TABLE_COOKIE}`, [], 'clear');
  }

  close(): void {
    this._closed = true;
  }

  isClosed(): boolean {
    return this._closed;
  }

  /**
   * fire-and-forget 落库，通过 `_writeChain` 严格按入队顺序串行执行。
   *
   * **`.catch()` 是硬要求**：`CookieRepository` 的调用方是同步的，没人接这个 Promise；
   * 不 catch 会产生 unhandled rejection（运行时可能直接崩，`check_silent_failures -Gate` 也会扫）。
   * 失败只计数 + 打一条 warn，**不让写失败影响内存态的读写**（上游同样：DB 异常不影响拦截器链）。
   */
  private fireAndForget(sql: string, args: (string | number)[], op: string): void {
    const store: CookieDbLike | null = this._store;
    if (store === null) {
      this._flushFailures++;
      hilog.warn(DOMAIN, TAG, 'cookie flush skipped (store not opened): op=%{public}s', op);
      return;
    }
    this._writeChain = this._writeChain.then((): Promise<void> => {
      return store.executeSql(sql, args).catch((e: Error): void => {
        this._flushFailures++;
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'cookie flush failed: op=%{public}s err=%{public}s',
          op, msg);
      });
    });
  }

  /** 与 `InMemoryCookieStore.keyOf` 同口径：`name\0domain\0path`。 */
  private static keyOf(cookie: Cookie): string {
    return `${cookie.name()}\u0000${cookie.domain()}\u0000${cookie.path()}`;
  }
}
