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
 * okhttp3.Headers 等价层（保序 + 大小写不敏感 + 多值）。
 *
 * 上游用到的面：
 *   headers.get("Content-Disposition" | "Content-Type" | "Content-Length" | "Location")   EhEngine.doThrowException / imageSearch
 *   response.headers("Set-Cookie")   EhApplication 的 WebView cookie 同步拦截器
 *   Headers.of(k, v, k, v ...)       EhEngine.imageSearch（multipart 分片头）
 */
export class Headers {
  private readonly namesArr: string[];
  private readonly valuesArr: string[];

  /** 内部构造：调用方应走 of()/Builder，保持 OkHttp 的不可变语义。 */
  constructor(namesArr: string[], valuesArr: string[]) {
    this.namesArr = namesArr;
    this.valuesArr = valuesArr;
  }

  /** 对齐 Headers.of(String... namesAndValues)。 */
  static of(...namesAndValues: string[]): Headers {
    if (namesAndValues.length % 2 !== 0) {
      throw new Error('Expected alternating header names and values');
    }
    const names: string[] = [];
    const values: string[] = [];
    for (let i = 0; i < namesAndValues.length; i += 2) {
      const name: string = namesAndValues[i];
      const value: string = namesAndValues[i + 1];
      if (name.length === 0) {
        throw new Error('Header name is empty');
      }
      Headers.checkName(name);
      Headers.checkValue(value, name);
      names.push(name);
      values.push(value);
    }
    return new Headers(names, values);
  }

  /** Headers.of(Map) —— ArkTS 没有泛型构造，用 Map<string, string> 版本便于 CookieRepository 迁移。 */
  static ofMap(map: Map<string, string>): Headers {
    const names: string[] = [];
    const values: string[] = [];
    map.forEach((v: string, k: string) => {
      if (k.length === 0) {
        throw new Error('Header name is empty');
      }
      Headers.checkName(k);
      Headers.checkValue(v, k);
      names.push(k);
      values.push(v);
    });
    return new Headers(names, values);
  }

  private static checkName(name: string): void {
    for (let i = 0; i < name.length; i++) {
      const c: number = name.charCodeAt(i);
      if (c <= 0x20 || c >= 0x7f) {
        throw new Error(`Unexpected char in header name: ${name}`);
      }
    }
  }

  private static checkValue(value: string, name: string): void {
    if (value.indexOf('\n') >= 0 || value.indexOf('\r') >= 0) {
      throw new Error(`Unexpected char in value for header: ${name}`);
    }
  }

  size(): number {
    return this.namesArr.length;
  }

  name(index: number): string {
    return this.namesArr[index];
  }

  value(index: number): string {
    return this.valuesArr[index];
  }

  names(): string[] {
    return this.namesArr.slice();
  }

  /** 对齐 Headers.get(String)：取第一个匹配值，没有则 null。 */
  get(name: string): string | null {
    for (let i = this.namesArr.length - 1; i >= 0; i--) {
      if (Headers.eq(this.namesArr[i], name)) {
        return this.valuesArr[i];
      }
    }
    return null;
  }

  /** 对齐 Headers.values(String)：保留全部匹配值，顺序与线上一致。 */
  values(name: string): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.namesArr.length; i++) {
      if (Headers.eq(this.namesArr[i], name)) {
        out.push(this.valuesArr[i]);
      }
    }
    return out;
  }

  /** 对齐 Headers.toMultimap()：用于把响应头交给 Cache / 日志。 */
  toMultimap(): Map<string, string[]> {
    const map: Map<string, string[]> = new Map<string, string[]>();
    for (let i = 0; i < this.namesArr.length; i++) {
      const lower: string = this.namesArr[i].toLowerCase();
      const list: string[] | undefined = map.get(lower);
      if (list === undefined) {
        map.set(lower, [this.valuesArr[i]]);
      } else {
        list.push(this.valuesArr[i]);
      }
    }
    return map;
  }

  newBuilder(): HeadersBuilder {
    const b: HeadersBuilder = new HeadersBuilder();
    for (let i = 0; i < this.namesArr.length; i++) {
      b.add(this.namesArr[i], this.valuesArr[i]);
    }
    return b;
  }

  equals(other: Headers): boolean {
    if (this.namesArr.length !== other.namesArr.length) {
      return false;
    }
    for (let i = 0; i < this.namesArr.length; i++) {
      if (!Headers.eq(this.namesArr[i], other.namesArr[i])) {
        return false;
      }
      if (this.valuesArr[i] !== other.valuesArr[i]) {
        return false;
      }
    }
    return true;
  }

  toString(): string {
    let s: string = '';
    for (let i = 0; i < this.namesArr.length; i++) {
      s += this.namesArr[i] + ': ' + this.valuesArr[i] + '\n';
    }
    return s;
  }

  private static eq(a: string, b: string): boolean {
    return a.length === b.length && a.toLowerCase() === b.toLowerCase();
  }
}

/** okhttp3.Headers.Builder 等价。 */
export class HeadersBuilder {
  private names: string[] = [];
  private values: string[] = [];

  add(name: string, value: string): HeadersBuilder {
    Headers.of(name, value); // 复用校验
    this.names.push(name);
    this.values.push(value);
    return this;
  }

  addAll(other: Headers): HeadersBuilder {
    for (let i = 0; i < other.size(); i++) {
      this.add(other.name(i), other.value(i));
    }
    return this;
  }

  /** set 语义：校验名称与值，删除全部同名头后再追加。 */
  set(name: string, value: string): HeadersBuilder {
    Headers.of(name, value);
    this.remove(name);
    this.names.push(name);
    this.values.push(value);
    return this;
  }

  remove(name: string): HeadersBuilder {
    for (let i = this.names.length - 1; i >= 0; i--) {
      if (this.names[i].toLowerCase() === name.toLowerCase()) {
        this.names.splice(i, 1);
        this.values.splice(i, 1);
      }
    }
    return this;
  }

  get(name: string): string | null {
    const idx: number = this.indexOf(name);
    return idx === -1 ? null : this.values[idx];
  }

  private indexOf(name: string): number {
    const lower: string = name.toLowerCase();
    for (let i = 0; i < this.names.length; i++) {
      if (this.names[i].toLowerCase() === lower) {
        return i;
      }
    }
    return -1;
  }

  build(): Headers {
    return new Headers(this.names.slice(), this.values.slice());
  }
}
