/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0402   上游: com/hippo/lib/yorozuya/collect/MultimapSet.java（25 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/collect/MultimapSet.ets
 *
 * Combines a Map with Set values to provide simple way to store multiple values for a key.
 *
 * 平台差异：
 *  1. `Set<V>` → `Array<V>` + **去重语义**（与 `Multimap` 的差别就在这一层：Set 不允许重复元素）。
 *     ArkTS 的 `Set` 与 `Array` 之间没有 `Collection` 共同父接口（AbstractMultimap 用的是
 *     显式钩子方法，见其差异 1），故这里用 Array 承载并实现"加入前判重"。
 *  2. `createWithThreadSafeLists()` 上游用 `CopyOnWriteArraySet`。ArkTS 无该类，且 TaskPool/Worker
 *     不共享对象 → threadSafe 标志保留、行为不变（与 `Multimap` 同口径）。
 *  3. **`collectionAdd` 的返回值**：Array 版（Multimap）恒 true；Set 版在"元素已存在"时必须返回
 *     **false**（`putElement` 用它判断"是否真的新增"）。这是 Set 与 List 唯一的行为差异，
 *     也是最容易漏掉的一处 —— 若照抄 Multimap 的 `return true`，去重就失效了。
 */

import { AbstractMultimap } from './AbstractMultimap';

/**
 * Combines a Map with Set values to provide simple way to store multiple values for a key.
 * Like Multimap, but element values are stored in Sets.
 */
export class MultimapSet<K, V> extends AbstractMultimap<K, V, Array<V>> {

  constructor(map: Map<K, Array<V>>, threadSafeCollections: boolean) {
    super(map, threadSafeCollections);
  }

  static create<K, V>(): MultimapSet<K, V> {
    return new MultimapSet<K, V>(new Map<K, Array<V>>(), false);
  }

  static createWithThreadSafeLists<K, V>(): MultimapSet<K, V> {
    return new MultimapSet<K, V>(new Map<K, Array<V>>(), true);
  }

  protected createNewCollection(): Array<V> {
    return [];
  }

  /** Set 语义：已存在则不加入，返回 false */
  protected collectionAdd(collection: Array<V>, value: V): boolean {
    for (let i = 0; i < collection.length; i++) {
      if (collection[i] === value) {
        return false;
      }
    }
    collection.push(value);
    return true;
  }

  /** 只有真的新增了元素才返回 true（对齐 `Set.addAll` 的返回值） */
  protected collectionAddAll(collection: Array<V>, values: Array<V>): boolean {
    let changed: boolean = false;
    for (let i = 0; i < values.length; i++) {
      const added: boolean = this.collectionAdd(collection, values[i]);
      if (added) {
        changed = true;
      }
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
    // Java Set.hashCode 契约：**元素哈希之和**（不是 List 的 31 倍累加）
    let h: number = 0;
    for (let i = 0; i < collection.length; i++) {
      h = (h + AbstractMultimap.hashString(`${collection[i]}`)) | 0;
    }
    return h;
  }

  protected toArray(collection: Array<V>): Array<V> {
    return collection;
  }
}