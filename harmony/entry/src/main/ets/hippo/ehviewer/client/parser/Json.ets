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
 * Android `org.json` 的最小等价实现（JSONObject / JSONArray）。
 *
 * 为什么不用 JsonMap：`JsonMap` 是扁平 `Record<string,string>`，只够 GalleryInfo 的序列化；
 * 而 parser 需要**嵌套结构与数组**（`tokenlist[0].token`、`gmetadata[i].tags[j]`）。
 *
 * 与 Android org.json 对齐的关键语义（不是标准 JS 语义）：
 *   1. `getString` **会强制转换**：数字 3 → "3"，布尔 true → "true"（Android 的 JSON.toString(object)）
 *   2. `getLong` **会解析字符串**："1234" → 1234；解析失败抛错（Android JSON.toLong）
 *   3. `getString` 遇到 null / 缺失 → 抛错（与 JSONException 对齐）
 *   4. `optString(key, def)` 缺失时返回默认值
 *   5. `has(key)` 为真即键存在（值可以显式为 null）；`isNull(key)` 只判断显式 null 或缺失
 *
 * 错误统一抛 `Error`，由各 parser 自己转换成 `ParseException`（与上游把 JSONException
 * 包成 ParseException 的写法一致）。
 */
export class JsonArray {
  private _items: Object[];

  constructor(items: Object[]) {
    this._items = items;
  }

  static parse(text: string): JsonArray {
    const v: Object = JsonObject.parseValue(text);
    if (!Array.isArray(v)) {
      throw new Error('not a json array');
    }
    return new JsonArray(v as Object[]);
  }

  length(): number {
    return this._items.length;
  }

  getJSONObject(index: number): JsonObject {
    const v: Object = this._items[index];
    if (v === null || v === undefined || typeof v !== 'object') {
      throw new Error('json array item ' + index + ' is not an object');
    }
    return JsonObject.wrap(v);
  }

  getString(index: number): string {
    return JsonObject.coerceToString(this._items[index]);
  }
}

export class JsonObject {
  private _raw: Record<string, Object>;
  private _keys: string[];

  private constructor(raw: Record<string, Object>) {
    this._raw = raw;
    this._keys = Object.keys(raw);
  }

  /** 内部：解析顶层值（对象/数组都可以）。 */
  static parseValue(text: string): Object {
    let v: Object;
    try {
      v = JSON.parse(text) as Object;
    } catch (e) {
      throw new Error('invalid json: ' + (e as Error).message);
    }
    if (v === null || v === undefined) {
      throw new Error('invalid json: empty');
    }
    return v;
  }

  static parse(text: string): JsonObject {
    const v: Object = JsonObject.parseValue(text);
    if (Array.isArray(v)) {
      throw new Error('not a json object');
    }
    if (typeof v !== 'object') {
      throw new Error('not a json object');
    }
    return JsonObject.wrap(v);
  }

  static wrap(v: Object): JsonObject {
    return new JsonObject(v as Record<string, Object>);
  }

  /** 原始 JSON 文本（供需要嵌入/透传子对象的调用方使用）。 */
  rawText(): string {
    return JSON.stringify(this._raw);
  }

  has(key: string): boolean {
    // ArkTS 禁用 Object.prototype / Function.call，故在构造时缓存键列表
    return this._keys.indexOf(key) >= 0;
  }

  /** 对齐 isNull：缺失或值为显式 null 都算 null。 */
  isNull(key: string): boolean {
    if (!this.has(key)) {
      return true;
    }
    const v: Object = this._raw[key];
    return v === null || v === undefined;
  }

  private get(key: string): Object {
    if (!this.has(key)) {
      throw new Error('no value for ' + key);
    }
    return this._raw[key];
  }

  /** 对齐 Android getString：数字/布尔会被转成字符串；null 抛错。 */
  getString(key: string): string {
    return JsonObject.coerceToString(this.get(key));
  }

  /** 对齐 Android optString。 */
  optString(key: string, def: string): string {
    if (!this.has(key) || this.isNull(key)) {
      return def;
    }
    return JsonObject.coerceToString(this._raw[key]);
  }

  getLong(key: string): number {
    return JsonObject.coerceToNumber(this.get(key), true);
  }

  getInt(key: string): number {
    return Math.trunc(JsonObject.coerceToNumber(this.get(key), true));
  }

  getDouble(key: string): number {
    return JsonObject.coerceToNumber(this.get(key), false);
  }

  getJSONArray(key: string): JsonArray {
    const v: Object = this.get(key);
    if (!Array.isArray(v)) {
      throw new Error(key + ' is not a json array');
    }
    return new JsonArray(v as Object[]);
  }

  getJSONObject(key: string): JsonObject {
    const v: Object = this.get(key);
    if (v === null || v === undefined || typeof v !== 'object' || Array.isArray(v)) {
      throw new Error(key + ' is not a json object');
    }
    return JsonObject.wrap(v);
  }

  static coerceToString(v: Object): string {
    if (v === null || v === undefined) {
      throw new Error('value is null');
    }
    if (typeof v === 'string') {
      return v as string;
    }
    if (typeof v === 'number') {
      const n: number = v as number;
      // Android 的 JSON.toString(double) 会去掉多余的 .0
      return Number.isInteger(n) ? `${n}` : `${n}`;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 'true' : 'false';
    }
    // 对象/数组：Android 返回 toString()（对解析用途等于不可用）
    throw new Error('value is not a primitive');
  }

  static coerceToNumber(v: Object, integer: boolean): number {
    if (v === null || v === undefined) {
      throw new Error('value is null');
    }
    if (typeof v === 'number') {
      const n: number = v as number;
      return integer ? Math.trunc(n) : n;
    }
    if (typeof v === 'string') {
      const s: string = (v as string).trim();
      const n: number = integer ? Number.parseInt(s, 10) : Number.parseFloat(s);
      if (Number.isNaN(n)) {
        throw new Error('not a number: ' + s);
      }
      return n;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 1 : 0;
    }
    throw new Error('value is not a number');
  }
}
