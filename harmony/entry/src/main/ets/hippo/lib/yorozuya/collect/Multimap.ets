/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0401
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/Multimap.java（24 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/Multimap.ets
 *
 * 平台差异：
 *  1. List<V> → Array<V>（方案 §5-9）。Java ArrayList ↔ Array，元素顺序语义一致。
 *  2. createWithThreadSafeLists() 上游用 CopyOnWriteArrayList。ArkTS 无该类，
 *     且 TaskPool/Worker 不共享对象（方案 §5-4），故 threadSafeCollections=true 与 false
 *     都产出普通 Array；标志位保留，只为让上游调用点与工厂方法名 1:1 不变。
 *     上游唯一调用点 conaco/Register 用的是 Multimap.create()（即 false 分支）。
 *  3. Collection.hashCode 的 31 倍累加（Java List.hashCode 契约）照搬，元素哈希用
 *     AbstractMultimap.hashString(`${value}`)；ArkTS 无 Object.hashCode（见
 *     AbstractMultimap.ets 差异 7）。
 *  4. 集合相等用逐元素 `===`（对应 Java 的引用相等 + 数值相等），不做深度比较。
 */

import { AbstractMultimap } from './AbstractMultimap';

/**
 * Combines a Map with List values to provide simple way to store multiple values for a key.
 */
// Top level class to get rid of 3rd generic collection parameter for more convenient usage.
export class Multimap<K, V> extends AbstractMultimap<K, V, Array<V>> {

  constructor(map: Map<K, Array<V>>, threadSafeCollections: boolean) {
    super(map, threadSafeCollections);
  }

  static create<K, V>(): Multimap<K, V> {
    return new Multimap<K, V>(new Map<K, Array<V>>(), false);
  }

  static createWithThreadSafeLists<K, V>(): Multimap<K, V> {
    return new Multimap<K, V>(new Map<K, Array<V>>(), true);
  }

  protected createNewCollection(): Array<V> {
    return [];
  }

  protected collectionAdd(collection: Array<V>, value: V): boolean {
    collection.push(value);
    return true;
  }

  protected collectionAddAll(collection: Array<V>, values: Array<V>): boolean {
    let changed: boolean = false;
    for (let i = 0; i < values.length; i++) {
      collection.push(values[i]);
      changed = true;
    }
    return changed;
  }

  protected collectionRemove(collection: Array<V>, value: V): boolean {
    for (let i = 0; i < collection.length; i++) {
      if (collection[i] === value) {
        collection.splice(i, 1);
        return true;
      }
    }
    return false;
  }

  protected collectionContains(collection: Array<V>, value: V): boolean {
    for (let i = 0; i < collection.length; i++) {
      if (collection[i] === value) {
        return true;
      }
    }
    return false;
  }

  protected collectionSize(collection: Array<V>): number {
    return collection.length;
  }

  protected collectionIsEmpty(collection: Array<V>): boolean {
    return collection.length === 0;
  }

  protected collectionEquals(a: Array<V>, b: Array<V>): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  protected collectionHash(collection: Array<V>): number {
    let h: number = 1;
    for (let i = 0; i < collection.length; i++) {
      h = (31 * h + AbstractMultimap.hashString(`${collection[i]}`)) | 0;
    }
    return h;
  }

  protected toArray(collection: Array<V>): Array<V> {
    return collection;
  }
}
