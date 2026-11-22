/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/GalleryInfoContentHelper.java（inventory S0297，上游 91 行）
 *
 * ============================ 同源判断（先核，不预设） ============================
 * 上游：`public abstract class GalleryInfoContentHelper extends ContentLayout.ContentHelper<GalleryInfo>`
 * ⇒ **与已交付的 `ContentHelper` 是同一条继承链**（`ContentHelper` 已在 `hippo/widget/ContentLayout.ets` 交付）。
 *
 * 它只加了**两件事**，选择/刷新/分页语义一个字没改：
 *   1) `Map<Long, GalleryInfo> map`（@SuppressLint UseSparseArrays）—— 按 **gid** 建索引，供详情页 O(1) 取同一对象
 *   2) `FavouriteStatusRouter.Listener` —— 收藏槽位变化时**就地改写缓存对象的 favoriteSlot**，
 *      不重新请求、不重建列表（列表项持有同一个对象引用 ⇒ 界面自动反映）
 *   并覆写 onAddData(单个/列表) / onRemoveData(单个/列表) / onClearData 维护该 map；
 *   `destroy()` 里 `removeListener(listener)`。
 *
 * ⇒ 判据结论：**分叉（扩展）→ 组合已交付的 ContentHelper + 本类只加索引与收藏同步**
 *   （不重写 ContentHelper 的任何状态机逻辑 —— 重写就是陷阱 76「同一算法两处实现」）
 *
 * ArkTS 侧落地方式：**组合而非继承**。
 *   理由：`ContentHelper<E>` 是带泛型的抽象类，ArkTS 严格模式对泛型抽象类子类化限制较多；
 *   而且本类真正新增的只有"索引 + 监听器"两块，与基类的状态机无耦合。
 *   页面侧把 `ContentHelper` 的 onAddData/onRemoveData/onClearData 钩子转调本类即可（同序、同语义）。
 *   **这是已登记差异**：继承链变成组合，公开方法名与语义保持一致。
 *
 * ============================ 一条容易漏的资源语义 ============================
 * `destroy()` 必须 `removeListener` —— 上游 `FavouriteStatusRouter` 是**长生命周期单例**，
 * 持有 listener 就持有页面强引用。**不 destroy 就是页面泄漏**（且是"退出页面后收藏变化仍回调到已销毁页面"的双重问题）。
 * 本实现把 destroy 做成**幂等**（重复调用安全），并加装配期提示。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.GalleryInfoContentHelper';

/** 对位 GalleryInfo 中本类用到的字段（其余字段由 storage-db 的 GalleryInfo 提供） */
export interface GalleryInfoLike {
  gid: number;
  favoriteSlot: number;
}

/** 对位 FavouriteStatusRouter.Listener */
export interface FavouriteStatusListener {
  onFavouriteSlotChanged(gid: number, slot: number): void;
}

/** 收藏状态路由（长生命周期单例，由 core-runtime 提供） */
export interface FavouriteStatusRouter {
  addListener(listener: FavouriteStatusListener): void;

  removeListener(listener: FavouriteStatusListener): void;
}

/** 具名实现类（ArkTS 禁止无类型对象字面量） */
export class FavouriteStatusListenerImpl implements FavouriteStatusListener {
  private host: GalleryInfoContentHelper;

  constructor(host: GalleryInfoContentHelper) {
    this.host = host;
  }

  onFavouriteSlotChanged(gid: number, slot: number): void {
    this.host.applyFavouriteSlot(gid, slot);
  }
}

/** 可序列化的 map 快照（对位上游 Bundle 里的 KEY_DATA_MAP） */
export class GalleryInfoMapSnapshot {
  keys: number[] = [];
  slots: number[] = [];
}

export class GalleryInfoContentHelper {
  /** 上游 map：gid → GalleryInfo（同一对象引用，就地改 favoriteSlot 才能让列表自动刷新） */
  private map: Map<number, GalleryInfoLike> = new Map<number, GalleryInfoLike>();
  private router: FavouriteStatusRouter | null = null;
  private listener: FavouriteStatusListener | null = null;
  private destroyed: boolean = false;
  /** 恢复出的收藏槽位覆盖表（对位上游反序列化后的 map） */
  private slotOverrides: Map<number, number> = new Map<number, number>();

  constructor(router: FavouriteStatusRouter | null) {
    this.router = router;
    if (router === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG,
        '%{public}s', 'FavouriteStatusRouter not injected — favourite slot changes will NOT reflect in list');
      return;
    }
    const l: FavouriteStatusListener = new FavouriteStatusListenerImpl(this);
    this.listener = l;
    router.addListener(l);   // 用已收窄的局部变量，避免 this.router 的可空性丢失
  }

  /**
   * 上游 listener 的净效果：`GalleryInfo info = map.get(gid); if (info != null) info.favoriteSlot = slot;`
   * 就地改写同一对象引用 ⇒ 列表项自动反映，无需重新请求。
   */
  applyFavouriteSlot(gid: number, slot: number): void {
    const info: GalleryInfoLike | undefined = this.map.get(gid);
    if (info !== undefined) {
      info.favoriteSlot = slot;
    }
  }

  /** 上游 destroy()：必须解绑，否则长生命周期 router 持有页面引用 → 泄漏 + 回调到已销毁页面 */
  destroy(): void {
    if (this.destroyed) {
      return; // 幂等
    }
    this.destroyed = true;
    const router: FavouriteStatusRouter | null = this.router;
    const listener: FavouriteStatusListener | null = this.listener;
    if (router !== null && listener !== null) {
      router.removeListener(listener);
    }
    this.listener = null;
  }

  /** 上游 onAddData(GalleryInfo) */
  onAddData(data: GalleryInfoLike): void {
    // 恢复出来的槽位覆盖值优先（对位上游反序列化 map 后再 onAddData 的顺序）
    const restored: number | undefined = this.slotOverrides.get(data.gid);
    if (restored !== undefined) {
      data.favoriteSlot = restored;
      this.slotOverrides.delete(data.gid);
    }
    this.map.set(data.gid, data);
  }

  /** 上游 onAddData(List<GalleryInfo>) */
  onAddDataList(data: GalleryInfoLike[]): void {
    for (let i = 0; i < data.length; i++) {
      this.map.set(data[i].gid, data[i]);
    }
  }

  /** 上游 onRemoveData(GalleryInfo) */
  onRemoveData(data: GalleryInfoLike): void {
    this.map.delete(data.gid);
  }

  /** 上游 onRemoveData(List<GalleryInfo>) */
  onRemoveDataList(data: GalleryInfoLike[]): void {
    for (let i = 0; i < data.length; i++) {
      this.map.delete(data[i].gid);
    }
  }

  /** 上游 onClearData() */
  onClearData(): void {
    this.map.clear();
  }

  /**
   * 上游 `saveInstanceState`（审计员报的唯一缺口，P2）：
   * 上游把 `map` 序列化进 Bundle（`KEY_DATA_MAP`），配置变更/进程重建后 `restoreInstanceState` 恢复，
   * 否则**恢复后 map 为空 → 收藏槽位同步失效**（列表还在，但收藏状态不再跟随）。
   * ArkTS 侧用"可序列化的键值对数组"承载（Map 不能直接进 AppStorage）。
   */
  saveState(): GalleryInfoMapSnapshot {
    const snap: GalleryInfoMapSnapshot = new GalleryInfoMapSnapshot();
    this.map.forEach((value: GalleryInfoLike, key: number) => {
      snap.keys.push(key);
      snap.slots.push(value.favoriteSlot);
    });
    return snap;
  }

  /**
   * 上游 `restoreInstanceState`：恢复 map。
   * ⚠ 只恢复 **gid + favoriteSlot**（上游存的就是这两项），**不恢复完整 GalleryInfo**
   *   —— 列表项由 ContentHelper 重新加载时再 `onAddData` 填入，避免"恢复出半截对象"。
   *   因此恢复的是"收藏槽位覆盖表"，`getByGid` 在未重新 add 前返回 undefined（与上游一致：
   *   上游 map 里存的是对象引用，序列化后同样是新对象）。
   */
  restoreState(snap: GalleryInfoMapSnapshot): void {
    this.slotOverrides.clear();
    for (let i = 0; i < snap.keys.length; i++) {
      this.slotOverrides.set(snap.keys[i], snap.slots[i]);
    }
  }

  /** 索引查询（本类存在的主要理由：详情页按 gid 取同一对象） */
  getByGid(gid: number): GalleryInfoLike | undefined {
    return this.map.get(gid);
  }

  size(): number {
    return this.map.size;
  }

  /** 测试/诊断用：是否仍在监听 */
  isListening(): boolean {
    return this.listener !== null;
  }
}
