/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0154   上游: com/hippo/ehviewer/FavouriteStatusRouter.java（59 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/FavouriteStatusRouter.ets
 *
 * **长生命周期单例**：收藏状态变化时，通知所有已注册 listener，并**就地改写**所有已登记的
 * `gid → GalleryInfo` 映射表（这样列表里已显示的项下次刷新就是新状态，不必重查）。
 *
 * 调用点契约（`git grep FavouriteStatusRouter` 核过）：
 *   · `EhApplication.getFavouriteStatusRouter()` → 应用级单例（本类由 EhApplication 持有）
 *   · `CommonOperations` → `modifyFavourites(gid, slot)` 发通知
 *   · `GalleryListScene` → `addListener`（onCreateScene）/ `removeListener`（onDestroyScene）**成对**
 *   · `GalleryInfoContentHelper` → `addListener`（构造）/ `removeListener`（destroy）**成对**
 * → 所以 **`addListener` 与 `removeListener` 必须都在**，否则页面 destroy 后无法解绑
 *   （Lead 指出的"页面泄漏 + 退出后仍回调到已销毁页面"的双重问题）。
 *
 * 平台差异：
 *  1. `IntIdGenerator` / `Settings.getInt/putInt` 都用已交付实现；`KEY_DATA_MAP_NEXT_ID` 的
 *     **持久化语义照搬**：`saveDataMap` 里 `nextId()` 调两次（一次作为返回值，一次写回 Settings）。
 *  2. `Map<Long, GalleryInfo>` → `Map<number, GalleryInfo>`（gid 是 safe integer）。
 *  3. `restoreDataMap` 是 **remove（一次性消费）**，不是 get —— 恢复后表即销毁，照搬。
 *  4. **`modifyFavourites` 遍历 listeners 时若某个 listener 在回调里 `removeListener`（或 `addListener`）**：
 *     上游用 `for (Listener l : listeners)`，Java 会抛 `ConcurrentModificationException`；
 *     本实现按下标遍历普通数组，**不会抛**（遍历到的是快照式语义）。
 *     这是**行为差异**，但方向是"更不脆" —— 按陷阱 63 属 B 类（用户不可感知、崩溃→不崩溃）→ 修，并在此注明。
 */

import { GalleryInfo } from './client/data/GalleryInfo';
import { IntIdGenerator } from '../lib/yorozuya/IntIdGenerator';
import { Settings } from './Settings';

/** 上游 `FavouriteStatusRouter.Listener` */
export interface FavouriteStatusListener {
  onModifyFavourites(gid: number, slot: number): void;
}

export class FavouriteStatusRouter {

  /** 上游 `KEY_DATA_MAP_NEXT_ID = "data_map_next_id"` */
  static readonly KEY_DATA_MAP_NEXT_ID: string = 'data_map_next_id';

  private readonly idGenerator: IntIdGenerator;
  private readonly maps: Map<number, Map<number, GalleryInfo>> = new Map<number, Map<number, GalleryInfo>>();
  private listeners: FavouriteStatusListener[] = [];

  constructor() {
    this.idGenerator = new IntIdGenerator(Settings.getInt(FavouriteStatusRouter.KEY_DATA_MAP_NEXT_ID, 0));
  }

  /**
   * 对应上游 `saveDataMap(map)`：分配 id 登记该映射表，并把**下一个 id** 持久化
   * （上游 `Settings.putInt(KEY, idGenerator.nextId())` —— 注意是 `nextId()`，不是当前 id）。
   */
  saveDataMap(map: Map<number, GalleryInfo>): number {
    const id: number = this.idGenerator.nextId();
    this.maps.set(id, map);
    Settings.putInt(FavouriteStatusRouter.KEY_DATA_MAP_NEXT_ID, this.idGenerator.nextId());
    return id;
  }

  /** 对应上游 `restoreDataMap(id)`：**取出并移除**（一次性消费，恢复后表就没了） */
  restoreDataMap(id: number): Map<number, GalleryInfo> | null {
    const map: Map<number, GalleryInfo> | undefined = this.maps.get(id);
    this.maps.delete(id);
    return (map === undefined) ? null : map;
  }

  /**
   * 对应上游 `modifyFavourites(gid, slot)`：
   *   1. 改写**所有**已登记映射表里该 gid 的 `favoriteSlot`
   *   2. 通知所有 listener
   * 顺序照搬（先改数据再通知 —— listener 里读到的已是新值）。
   */
  modifyFavourites(gid: number, slot: number): void {
    this.maps.forEach((map: Map<number, GalleryInfo>) => {
      const info: GalleryInfo | undefined = map.get(gid);
      if (info !== undefined) {
        info.favoriteSlot = slot;
      }
    });
    // 快照遍历（见文件头差异 4）：回调里增删 listener 不会破坏本次遍历
    const snapshot: FavouriteStatusListener[] = this.listeners.slice();
    for (let i = 0; i < snapshot.length; i++) {
      snapshot[i].onModifyFavourites(gid, slot);
    }
  }

  /**
   * 注册 listener。**同一 listener 重复注册会被注册多次**（上游 `ArrayList.add` 语义，不去重）——
   * 照搬：去重会让"注册两次、注销一次"的调用方留下一份悬挂引用。
   */
  addListener(listener: FavouriteStatusListener): void {
    this.listeners.push(listener);
  }

  /** 注销 listener（**只移除第一个匹配项**，对应上游 `ArrayList.remove(o)`） */
  removeListener(listener: FavouriteStatusListener): void {
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] === listener) {
        this.listeners.splice(i, 1);
        return;
      }
    }
  }

  /** 当前 listener 数量（诊断/测试用；上游无此方法） */
  getListenerCount(): number {
    return this.listeners.length;
  }
}
