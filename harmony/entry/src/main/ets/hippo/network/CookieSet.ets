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
import { HttpUrl } from '../okhttp/HttpUrl';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/CookieSet.java
 * （inventory S0435，104 行）
 *
 * **更正记录**：曾误判本文件为「整类被注释」的死代码 —— 那是把 javadoc 的 `/**` 误读成注释块。
 * 实际是活代码，被 `CookieRepository`（6 处）与 `CookieDatabase`（4 处）引用。
 *
 * 语义：
 *   - 键 = (name, domain, path) 三元组（`Key`），不含 value / expiresAt
 *   - `add` 返回**被替换掉的旧 cookie**（没有则 null）—— CookieRepository 靠这个返回值判断
 *     「该 insert 还是 update 数据库」
 *   - `get(url, accepted, expired)`：过期项**就地删除**并放进 expired；匹配的放进 accepted
 *
 * String[] 作键（无 HashMap）→ 用 `name\u0000domain\u0000path` 拼成字符串做键，
 * 分隔符用 `\u0000`（不会出现在 cookie 名/域/路径里），等价于三元组相等。
 */
export class CookieSet {
  private _map: Map<string, Cookie> = new Map<string, Cookie>();

  /** 对齐 `Cookie add(Cookie)`：返回同 (name,domain,path) 的旧 cookie 或 null。 */
  add(cookie: Cookie): Cookie | null {
    const key: string = CookieSet.keyOf(cookie);
    const old: Cookie | undefined = this._map.get(key);
    this._map.set(key, cookie);
    return old === undefined ? null : old;
  }

  /** 对齐 `Cookie remove(Cookie)`：返回被移除的 cookie 或 null。 */
  remove(cookie: Cookie): Cookie | null {
    const key: string = CookieSet.keyOf(cookie);
    const old: Cookie | undefined = this._map.get(key);
    if (old === undefined) {
      return null;
    }
    this._map.delete(key);
    return old;
  }

  /**
   * 对齐 `get(HttpUrl, List accepted, List expired)`：
   * 过期项就地删除并写入 expired；匹配 url 的写入 accepted。
   * ArkTS 无 out 参数 → 用结果对象返回两个数组。
   */
  get(url: HttpUrl, now: number): CookieSetResult {
    const result: CookieSetResult = new CookieSetResult();
    const expiredKeys: string[] = [];
    this._map.forEach((cookie: Cookie, key: string): void => {
      if (cookie.expiresAt() <= now) {
        expiredKeys.push(key);
        result.expired.push(cookie);
      } else if (cookie.matches(url)) {
        result.accepted.push(cookie);
      }
    });
    for (let i = 0; i < expiredKeys.length; i++) {
      this._map.delete(expiredKeys[i]);
    }
    return result;
  }

  size(): number {
    return this._map.size;
  }

  private static keyOf(cookie: Cookie): string {
    return cookie.name() + '\u0000' + cookie.domain() + '\u0000' + cookie.path();
  }
}

/** `CookieSet.get` 的双输出。 */
export class CookieSetResult {
  accepted: Cookie[] = [];
  expired: Cookie[] = [];
}
