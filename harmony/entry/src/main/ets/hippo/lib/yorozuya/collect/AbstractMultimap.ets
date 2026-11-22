/*
 * Copyright (C) 2014-2015 Markus Junginger, greenrobot (http://greenrobot.de)
 *
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
 * 条目   : S0396
 * 上游   : app/src/main/java/com/hippo/lib/yorozuya/collect/AbstractMultimap.java（158 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/AbstractMultimap.ets
 *
 * 平台差异（方案 §5-7 重载改造 + §5-9 集合 API 差异）：
 *  1. `implements Map<K, C>` 取消。ArkTS 的 Map 是具体类（size 是属性、没有 put/get 之外
 *     的视图方法、get 返回 undefined），无法作为接口实现；本类改为「内部持有 Map」并保留
 *     Java Map 的全部方法名（size()/isEmpty()/containsKey()/containsValue()/get()/put()/
 *     putAll()/remove()/clear()/keySet()/values()/entrySet()），上游调用点零改写。
 *  2. 泛型参数 C extends Collection<V> 的约束取消（ArkTS 不支持带约束的泛型实参收窄到接口实现）。
 *     改为「抽象钩子方法」显式表达集合操作：createNewCollection/collectionAdd/collectionAddAll/
 *     collectionRemove/collectionContains/collectionSize/collectionIsEmpty/collectionEquals/
 *     collectionHash/toArray。子类 Multimap 用 Array<V> 实现，MultimapSet 用 Set<V> 实现，
 *     与上游 `List<V>` / `Set<V>` 的对应关系不变，且 get() 直接返回原生集合，
 *     调用方 `List<ConacoTask<V>> list = mKeyMap.get(key)` 改写后仍是 `Array<ConacoTask<V>>`。
 *  3. Java 的 `containsElement(K,V)` / `containsElement(V)` 重载 → `containsElement(key, value)`
 *     与 `containsAnyValue(value)`。
 *  4. `get()` / `remove()` / `put()` 的 Java null 返回值 → ArkTS `C | undefined`
 *     （Map.get 的天然返回），调用方写 `const c = m.get(k); if (c === undefined) …`。
 *  5. `Set<Entry<K,C>> entrySet()` → `Array<MapEntry<K,C>>`（快照数组，非活视图）。
 *     `Collection<C> values()` → `Array<C>`（快照）。`Set<K> keySet()` → `Set<K>`（快照）。
 *     上游所有调用点都是「取出来立刻遍历」，不依赖活视图语义。
 *  6. 线程安全：上游每个方法都带 synchronized。ArkTS 没有 synchronized 关键字，
 *     且 TaskPool/Worker 之间不共享对象（方案 §5-4：跨线程只传可序列化数据），
 *     因此这里的 synchronized 等价物是「不需要」——同一对象只会在同一个 VM 线程内被访问。
 *     `threadSafeCollections` 字段保留（上游 Register 传入 false），
 *     用于决定集合实现是否用并发安全变体；语义见 Multimap.ets。
 *  7. equals()/hashCode()：ArkTS 无 Object.hashCode，改用内容比较 + FNV-1a 稳定哈希。
 *     上游对 Multimap 没有 equals/hashCode 调用点（唯一使用方 conaco/Register 只用
 *     putElement/countElements/removeElement/get），因此哈希值不参与任何可观察行为，
 *     仅保留 API 形状。
 */

/**
 * 对应 java.util.Map.Entry<K, C>。
 */
export class MapEntry<K, C> {
  key: K;
  value: C;

  constructor(key: K, value: C) {
    this.key = key;
    this.value = value;
  }
}

/**
 * Combines a Map with List values to provide simple way to store multiple values for a key (multimap).
 */
export abstract class AbstractMultimap<K, V, C> {

  protected readonly threadSafeCollections: boolean;
  protected map: Map<K, C>;

  protected constructor(map: Map<K, C>, threadSafeCollections: boolean) {
    this.map = map;
    this.threadSafeCollections = threadSafeCollections;
  }

  /** 对应上游 abstract C createNewCollection() */
  protected abstract createNewCollection(): C;

  /** 对应 C.add(value) */
  protected abstract collectionAdd(collection: C, value: V): boolean;

  /** 对应 C.addAll(values) */
  protected abstract collectionAddAll(collection: C, values: Array<V>): boolean;

  /** 对应 C.remove(value) */
  protected abstract collectionRemove(collection: C, value: V): boolean;

  /** 对应 C.contains(value) */
  protected abstract collectionContains(collection: C, value: V): boolean;

  /** 对应 C.size() */
  protected abstract collectionSize(collection: C): number;

  /** 对应 C.isEmpty() */
  protected abstract collectionIsEmpty(collection: C): boolean;

  /** 对应集合的 equals() */
  protected abstract collectionEquals(a: C, b: C): boolean;

  /** 对应集合的 hashCode() */
  protected abstract collectionHash(collection: C): number;

  /**
   * 无 Java Object.hashCode 的等价物，用 FNV-1a over 键的字符串形式得到稳定 32 位哈希。
   * 仅用于 equals/hashCode 的 API 形状，不参与持久化与业务判断（见差异 7）。
   */
  protected static hashString(s: string): number {
    let h: number = 0x811c9dc5;
    for (let i = 0; i < s.length; i++) {
      h = h ^ s.charCodeAt(i);
      h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
    }
    return h;
  }

  putAll(m: Map<K, C>): void {
    m.forEach((value: C, key: K) => {
      this.map.set(key, value);
    });
  }

  size(): number {
    return this.map.size;
  }

  isEmpty(): boolean {
    return this.map.size === 0;
  }

  containsKey(key: K): boolean {
    return this.map.has(key);
  }

  containsValue(value: C): boolean {
    let found: boolean = false;
    this.map.forEach((v: C) => {
      if (!found && this.collectionEquals(v, value)) {
        found = true;
      }
    });
    return found;
  }

  get(key: K): C | undefined {
    return this.map.get(key);
  }

  remove(key: K): C | undefined {
    const old: C | undefined = this.map.get(key);
    this.map.delete(key);
    return old;
  }

  clear(): void {
    this.map.clear();
  }

  keySet(): Set<K> {
    const result: Set<K> = new Set<K>();
    this.map.forEach((_value: C, key: K) => {
      result.add(key);
    });
    return result;
  }

  values(): Array<C> {
    const result: Array<C> = [];
    this.map.forEach((value: C) => {
      result.push(value);
    });
    return result;
  }

  entrySet(): Array<MapEntry<K, C>> {
    const result: Array<MapEntry<K, C>> = [];
    this.map.forEach((value: C, key: K) => {
      result.push(new MapEntry<K, C>(key, value));
    });
    return result;
  }

  equals(o: Object): boolean {
    if (o === this) {
      return true;
    }
    if (!(o instanceof AbstractMultimap)) {
      return false;
    }
    const other: AbstractMultimap<K, V, C> = o as AbstractMultimap<K, V, C>;
    if (other.size() !== this.size()) {
      return false;
    }
    let same: boolean = true;
    this.map.forEach((value: C, key: K) => {
      if (!same) {
        return;
      }
      const otherValue: C | undefined = other.get(key);
      if (otherValue === undefined || !this.collectionEquals(value, otherValue)) {
        same = false;
      }
    });
    return same;
  }

  hashCode(): number {
    let h: number = 0;
    const entries: Array<MapEntry<K, C>> = this.entrySet();
    for (let i = 0; i < entries.length; i++) {
      const keyHash: number = AbstractMultimap.hashString(`${entries[i].key}`);
      h = (h + ((keyHash ^ this.collectionHash(entries[i].value)) >>> 0)) >>> 0;
    }
    return h | 0;
  }

  /**
   * @return number of elements stored for given key after storing the given value.
   */
  putElement(key: K, value: V): number {
    let collection: C | undefined = this.map.get(key);
    if (collection === undefined) {
      collection = this.createNewCollection();
      this.map.set(key, collection);
    }
    this.collectionAdd(collection, value);
    return this.collectionSize(collection);
  }

  put(key: K, value: C): C | undefined {
    const old: C | undefined = this.map.get(key);
    this.map.set(key, value);
    return old;
  }

  /**
   * @return true if the collection was changed.
   */
  putElements(key: K, values: Array<V>): boolean {
    let collection: C | undefined = this.map.get(key);
    if (collection === undefined) {
      collection = this.createNewCollection();
      this.map.set(key, collection);
    }
    return this.collectionAddAll(collection, values);
  }

  /**
   * @return true if the given element was removed.
   */
  removeElement(key: K, value: V): boolean {
    const collection: C | undefined = this.map.get(key);
    if (collection === undefined) {
      return false;
    } else {
      const removed: boolean = this.collectionRemove(collection, value);
      if (this.collectionIsEmpty(collection)) {
        this.map.delete(key);
      }
      return removed;
    }
  }

  countElements(key: K): number {
    const collection: C | undefined = this.map.get(key);
    if (collection === undefined) {
      return 0;
    } else {
      return this.collectionSize(collection);
    }
  }

  containsElement(key: K, value: V): boolean {
    const collection: C | undefined = this.map.get(key);
    if (collection === undefined) {
      return false;
    } else {
      return this.collectionContains(collection, value);
    }
  }

  /**
   * 对应上游重载 containsElement(V value)（ArkTS 无重载，改名保留语义）。
   */
  containsAnyValue(value: V): boolean {
    let found: boolean = false;
    this.map.forEach((collection: C) => {
      if (!found && this.collectionContains(collection, value)) {
        found = true;
      }
    });
    return found;
  }

  valuesElements(): C {
    const all: C = this.createNewCollection();
    this.map.forEach((collection: C) => {
      this.collectionAddAll(all, this.toArray(collection));
    });
    return all;
  }

  /** 把内部集合摊平成数组，供 valuesElements 复用 collectionAddAll */
  protected abstract toArray(collection: C): Array<V>;
}
