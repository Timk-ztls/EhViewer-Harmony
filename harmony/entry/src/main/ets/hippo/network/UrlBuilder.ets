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

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/UrlBuilder.java
 * （inventory S0443，49 行）
 *
 * 简单的 query 拼装器：`root?k1=v1&k2=v2`。上游用 HashMap，ArkTS 用 Map。
 *
 * 差异（已登记 MR）：Java `HashMap` 的迭代顺序是**未定义**的（按 hash 桶序），
 * ArkTS `Map` 按插入序。因此同一个 UrlBuilder 在两端可能产出参数顺序不同的 URL。
 * 影响面：
 *   - 服务端语义不受影响（query 参数无序）
 *   - 金样本比对按「解析出的字段」比，不按 URL 字节比
 *   - 缓存键若按完整 URL 做键（EhCacheKeyFactory 不这么做），会受影响
 * 结论：保持插入序（更可预测），不模拟 Java 的桶序。
 */
export class UrlBuilder {
  private readonly _rootUrl: string;
  private readonly _queryMap: Map<string, QueryValue> = new Map<string, QueryValue>();

  constructor(rootUrl: string) {
    this._rootUrl = rootUrl;
  }

  /** 对齐 addQuery(String key, Object value)：同名覆盖（HashMap.put 语义）。 */
  addQuery(key: string, value: QueryValue): void {
    this._queryMap.set(key, value);
  }

  /** 对齐 build()：无 query 时返回原串；否则 `root?k=v&k2=v2`。 */
  build(): string {
    if (this._queryMap.size === 0) {
      return this._rootUrl;
    }
    const parts: string[] = [];
    this._queryMap.forEach((value: QueryValue, key: string) => {
      parts.push(`${key}=${value}`);
    });
    return `${this._rootUrl}?${parts.join('&')}`;
  }

  /** 供调试/日志（上游无此方法）。 */
  size(): number {
    return this._queryMap.size;
  }
}

/** 对应 Java 的 Object value：实际只用 String 与 number（ListUrlBuilder 全量调用点如此）。 */
export type QueryValue = string | number;
