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
import { CookieJar } from '../okhttp/CookieJar';
import { HttpUrl } from '../okhttp/HttpUrl';
import { CookieSet, CookieSetResult } from './CookieSet';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/CookieRepository.java
 * （inventory S0434，200 行）
 *
 * **P4 验收项（登录态持久化）**：cookie 落库 → 重启后仍在。
 * 本层用 `CookieStoreBackend` 抽象存储（见 CookieDatabase.ets），因此「重启」= 用**同一个 backend**
 * 新建第二个 repository 实例，可在纯逻辑测试里断言，无需真机。
 *
 * 逐条照搬的关键逻辑（addCookie 的三分支是整个类的核心）：
 *   1. 过期 cookie → 从 set 移除；**非持久化**的不动数据库（它从来没进过库）
 *   2. 未过期 → 写入 set，同时拿回被替换的旧 cookie：
 *      - 新 cookie 非持久化 → 不写库
 *      - 旧 cookie 非持久化 → 视为「库里没有它」→ 不 update
 *      - 若「新不持久 + 旧存在」→ 说明旧的在库里要删掉（toRemove = 旧）
 *   3. 排序按 RFC 6265 §5.4 step 2：**path 长的排前面**（不记创建时间）
 *
 * `domainMatch` 是 okhttp3.Cookie.domainMatch 的逐行复制（含 IP 地址不参与后缀匹配的规则）。
 */
export class CookieRepository implements CookieJar {
  // 注意必须**整串匹配**（上游是 Matcher.matches() 而不是 find()）：[\d.] 能匹配普通域名里的 .，
  // 少了 ^$ 锚点会把所有含点的域名都判成 IP 地址，domainMatch 全部失效。
  private static readonly VERIFY_AS_IP_ADDRESS: RegExp =
    /^(?:(?:[0-9a-fA-F]*:[0-9a-fA-F:.]*)|(?:[\d.]+))$/;

  private _db: CookieStoreBackend;
  private _map: Map<string, CookieSet> = new Map<string, CookieSet>();

  constructor(db: CookieStoreBackend) {
    this._db = db;
    const loaded: Map<string, Cookie[]> = db.getAllCookies();
    loaded.forEach((list: Cookie[], domain: string): void => {
      const set: CookieSet = new CookieSet();
      for (let i = 0; i < list.length; i++) {
        set.add(list[i]);
      }
      this._map.set(domain, set);
    });
  }

  /** 对齐 `addCookie(Cookie)`。 */
  addCookie(cookie: Cookie): void {
    let toAdd: Cookie | null = null;
    let toUpdate: Cookie | null = null;
    let toRemove: Cookie | null = null;

    const domain: string = cookie.domain();
    let set: CookieSet | undefined = this._map.get(domain);
    if (set === undefined) {
      set = new CookieSet();
      this._map.set(domain, set);
    }
    const cookieSet: CookieSet = set;

    if (cookie.expiresAt() <= Date.now()) {
      toRemove = cookieSet.remove(cookie);
      // 非持久化的 cookie 不在数据库里
      if (toRemove !== null && !(toRemove as Cookie).persistent()) {
        toRemove = null;
      }
    } else {
      toAdd = cookie;
      toUpdate = cookieSet.add(cookie);
      if (!(toAdd as Cookie).persistent()) {
        toAdd = null;
      }
      if (toUpdate !== null && !(toUpdate as Cookie).persistent()) {
        toUpdate = null;
      }
      // 新的不持久但旧的持久 → 库里的旧记录要删
      if (toAdd === null && toUpdate !== null) {
        toRemove = toUpdate;
        toUpdate = null;
      }
    }

    if (toRemove !== null) {
      this._db.remove(toRemove as Cookie);
    }
    if (toAdd !== null) {
      if (toUpdate !== null) {
        this._db.update(toUpdate as Cookie, toAdd as Cookie);
      } else {
        this._db.add(toAdd as Cookie);
      }
    }
  }

  /** 对齐 `getCookieHeader(HttpUrl)`：`name=value; name2=value2`。 */
  getCookieHeader(url: HttpUrl): string {
    const cookies: Cookie[] = this.getCookies(url);
    const sb: string[] = [];
    for (let i = 0; i < cookies.length; i++) {
      sb.push(cookies[i].name() + '=' + cookies[i].value());
    }
    return sb.join('; ');
  }

  /** 对齐 `getCookies(HttpUrl)`：过滤过期（并落库删除）+ 按 path 长度降序。 */
  getCookies(url: HttpUrl): Cookie[] {
    const accepted: Cookie[] = [];
    const expired: Cookie[] = [];
    const now: number = Date.now();
    this._map.forEach((cookieSet: CookieSet, domain: string): void => {
      if (CookieRepository.domainMatch(url, domain)) {
        const r: CookieSetResult = cookieSet.get(url, now);
        for (let i = 0; i < r.accepted.length; i++) {
          accepted.push(r.accepted[i]);
        }
        for (let i = 0; i < r.expired.length; i++) {
          expired.push(r.expired[i]);
        }
      }
    });
    for (let i = 0; i < expired.length; i++) {
      if (expired[i].persistent()) {
        this._db.remove(expired[i]);
      }
    }
    // RFC 6265 §5.4 step 2：path 长的排前面；不比较创建时间
    accepted.sort((a: Cookie, b: Cookie): number => b.path().length - a.path().length);
    return accepted;
  }

  /** 对齐 `contains(HttpUrl, String name)`。 */
  contains(url: HttpUrl, name: string): boolean {
    const cookies: Cookie[] = this.getCookies(url);
    for (let i = 0; i < cookies.length; i++) {
      if (cookies[i].name() === name) {
        return true;
      }
    }
    return false;
  }

  /** 对齐 `clear()`：内存与库都清。 */
  clear(): void {
    this._map.clear();
    this._db.clear();
  }

  close(): void {
    this._db.close();
  }

  /** 对齐 `saveFromResponse(HttpUrl, List<Cookie>)`（CookieJar 接口）。 */
  saveFromResponse(httpUrl: HttpUrl, list: Cookie[]): void {
    for (let i = 0; i < list.length; i++) {
      this.addCookie(list[i]);
    }
  }

  /** 对齐 `loadForRequest(HttpUrl)`（CookieJar 接口）。 */
  loadForRequest(httpUrl: HttpUrl): Cookie[] {
    return this.getCookies(httpUrl);
  }

  /** okhttp3.Cookie.domainMatch 的逐行复制。 */
  static domainMatch(url: HttpUrl, domain: string): boolean {
    const urlHost: string = url.host();
    if (urlHost === domain) {
      return true; // example.com 匹配 example.com
    }
    if (urlHost.endsWith(domain)
      && urlHost.charAt(urlHost.length - domain.length - 1) === '.'
      && !CookieRepository.verifyAsIpAddress(urlHost)) {
      return true; // example.com 匹配 www.example.com
    }
    return false;
  }

  private static verifyAsIpAddress(host: string): boolean {
    return CookieRepository.VERIFY_AS_IP_ADDRESS.test(host);
  }
}

/**
 * 存储抽象（对应上游的 `CookieDatabase` + SQLite）。
 *
 * 为什么要抽象：HarmonyOS 侧要落 SQLite（`@ohos.data.relationalStore`），
 * 而 relationalStore 属于 storage-db 的接线面；把「行级 CRUD」抽成接口后：
 *   - 纯逻辑测试用 `InMemoryCookieStore`（可跨实例复用 → 模拟「重启后仍在」）
 *   - 生产用 `RelationalStoreCookieStore`（storage-db 接线时实现，表结构见 CookieDatabase.ets）
 */
export interface CookieStoreBackend {
  /** domain → cookies（启动时全量载入，对应 `CookieDatabase.getAllCookies`）。 */
  getAllCookies(): Map<string, Cookie[]>;

  add(cookie: Cookie): void;

  update(oldCookie: Cookie, newCookie: Cookie): void;

  remove(cookie: Cookie): void;

  clear(): void;

  close(): void;
}
