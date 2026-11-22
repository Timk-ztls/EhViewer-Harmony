/*
 * Copyright 2017 Hippo Seven
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

import { Cookie } from '../okhttp/Cookie';
import { CookieStoreBackend } from './CookieRepository';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/CookieDatabase.java
 * （inventory S0433，241 行）
 *
 * 上游是 `SQLiteOpenHelper` + `MSQLiteBuilder` 建表。本层拆成两部分：
 *   1. **表结构常量与行语义**（本文件）—— 逐列照搬，供 storage-db 接线 relationalStore 时直接用
 *   2. **`InMemoryCookieStore`** —— `CookieStoreBackend` 的纯内存实现，用于单测与「重启后仍在」验证
 *
 * 为什么不在本层直接调 `@ohos.data.relationalStore`：
 *   - 数据库文件的打开/升级归 storage-db（单一 DB 打开点，避免多模块各开一个连接）
 *   - 纯逻辑单测无法开 relationalStore（无设备）
 *   → 接口 + 两实现，是本层唯一能既保语义又可测的形态。`RelationalStoreCookieStore` 由 storage-db 落地。
 *
 * 行语义（上游 `getCookie(cursor, now)` 的过滤规则，**必须照搬**）：
 *   - `name`/`domain`/`path` 任一为 null → 视为坏行，跳过
 *   - `!persistent || expiresAt <= now` → 不返回（且随后会被删除）
 */
export class CookieTable {
  static readonly TABLE_COOKIE: string = 'OK_HTTP_3_COOKIE';
  static readonly COLUMN_ID: string = '_id';
  static readonly COLUMN_NAME: string = 'NAME';
  static readonly COLUMN_VALUE: string = 'VALUE';
  static readonly COLUMN_EXPIRES_AT: string = 'EXPIRES_AT';
  static readonly COLUMN_DOMAIN: string = 'DOMAIN';
  static readonly COLUMN_PATH: string = 'PATH';
  static readonly COLUMN_SECURE: string = 'SECURE';
  static readonly COLUMN_HTTP_ONLY: string = 'HTTP_ONLY';
  static readonly COLUMN_PERSISTENT: string = 'PERSISTENT';
  static readonly COLUMN_HOST_ONLY: string = 'HOST_ONLY';
  static readonly DB_VERSION: number = 1;

  /** 建表语句（供 storage-db 的 relationalStore 实现直接执行）。 */
  static createTableSql(): string {
    return `CREATE TABLE IF NOT EXISTS ${CookieTable.TABLE_COOKIE} (` +
      `${CookieTable.COLUMN_ID} INTEGER PRIMARY KEY AUTOINCREMENT, ` +
      `${CookieTable.COLUMN_NAME} TEXT, ` +
      `${CookieTable.COLUMN_VALUE} TEXT, ` +
      `${CookieTable.COLUMN_EXPIRES_AT} INTEGER, ` +
      `${CookieTable.COLUMN_DOMAIN} TEXT, ` +
      `${CookieTable.COLUMN_PATH} TEXT, ` +
      `${CookieTable.COLUMN_SECURE} INTEGER, ` +
      `${CookieTable.COLUMN_HTTP_ONLY} INTEGER, ` +
      `${CookieTable.COLUMN_PERSISTENT} INTEGER, ` +
      `${CookieTable.COLUMN_HOST_ONLY} INTEGER, ` +
      `UNIQUE (${CookieTable.COLUMN_NAME}, ${CookieTable.COLUMN_DOMAIN}, ${CookieTable.COLUMN_PATH}))`;
  }

  /** 对齐 `getCookie(Cursor, long now)` 的过滤规则：坏行/非持久化/已过期 → null。 */
  static isValidRow(name: string | null, domain: string | null, path: string | null,
    persistent: boolean, expiresAt: number, now: number): boolean {
    if (name === null || domain === null || path === null) {
      return false;
    }
    if (name.length === 0 || domain.length === 0) {
      return false;
    }
    if (!persistent || expiresAt <= now) {
      return false;
    }
    return true;
  }
}

/**
 * 纯内存实现。**同一实例可被多个 CookieRepository 复用** —— 这就等价于
 * 「进程重启后数据库文件还在」，因此可以在测试里直接断言「重启后 cookie 仍在」。
 */
export class InMemoryCookieStore implements CookieStoreBackend {
  /** 行存储：name\0domain\0path → Cookie（与 CookieSet 的键口径一致）。 */
  private _rows: Map<string, Cookie> = new Map<string, Cookie>();
  private _closed: boolean = false;

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
    this._rows.set(InMemoryCookieStore.keyOf(cookie), cookie);
  }

  update(oldCookie: Cookie, newCookie: Cookie): void {
    this._rows.delete(InMemoryCookieStore.keyOf(oldCookie));
    this.add(newCookie);
  }

  remove(cookie: Cookie): void {
    this._rows.delete(InMemoryCookieStore.keyOf(cookie));
  }

  clear(): void {
    this._rows.clear();
  }

  close(): void {
    this._closed = true;
  }

  isClosed(): boolean {
    return this._closed;
  }

  /** 测试辅助：库里现存行数。 */
  rowCount(): number {
    return this._rows.size;
  }

  private static keyOf(cookie: Cookie): string {
    return cookie.name() + '\u0000' + cookie.domain() + '\u0000' + cookie.path();
  }
}
