/*
 * 上游对应：无单一文件 —— 对位 androidx RecyclerView.Adapter + com.hippo.widget.SimpleAdapter（java 版）
 * 契约：CONTRACTS C-9（Lead 批准，ui-scene 维护，ui-widget 只消费）
 *
 * 为什么需要这一层：
 *   Android 侧列表页 = RecyclerView + SimpleAdapter（+ FooterAdapter/HeaderAdapter 变体），
 *   ArkUI 侧 = List/Grid + LazyForEach，而 LazyForEach 的数据源必须是 IDataSource，
 *   且变更通知是"按索引"的（onDataAdd/onDataChange/onDataDelete/onDataMove）。
 *   SimpleAdapter 的语义（整段替换 + 追加 + 单条更新 + 清空）在这里一一映射，
 *   索引越界/负数按框架要求收敛为 0 或抛错，行为写在下面对应方法里。
 *
 * 泛型：ArkTS 支持 class 泛型；E 为列表元素（如 GalleryInfo）。
 * 线程：本类只在 UI 线程使用（ArkUI 的 IDataSource 回调必须在 UI 线程），
 *       数据准备（网络/DB）在 TaskPool 完成后整体 setAll 回 UI 线程。
 */

/** LazyForEach 要求的观察者接口（ArkUI 定义，此处只用其类型，不重复声明） */

export interface SceneDataSourceListener {
  onDataReloaded(): void;
  onDataAdd(index: number): void;
  onDataMove(from: number, to: number): void;
  onDataDelete(index: number): void;
  onDataChange(index: number): void;
  onDatasetChange(operations: DataOperation[]): void;
}

/** 只用到 add/change/delete/reload 四类操作 */
export class DataOperation {
  readonly type: string;
  readonly index: number;
  readonly count: number;
  constructor(type: string, index: number, count: number) {
    this.type = type;
    this.index = index;
    this.count = count;
  }
}

/**
 * 场景数据源：对位上游 SimpleAdapter 的公开行为。
 * 说明：ArkUI 的 IDataSource 接口签名是
 *   totalCount(): number
 *   getData(index: number): E
 *   registerDataChangeListener(listener: IDataSourceListener): void
 *   unregisterDataChangeListener(listener: IDataSourceListener): void
 * 这里逐一对位实现，另外补齐 SimpleAdapter 侧被页面直接调用的方法。
 */
export class SceneDataSource<E> {
  private data: E[] = [];
  private listeners: SceneDataSourceListener[] = [];
  /** 上游 SimpleAdapter 的 footer/header 占位：以 null 元素参与 totalCount，渲染层识别 */
  private headerCount: number = 0;
  private footerCount: number = 0;

  constructor(initial?: E[]) {
    if (initial !== undefined) {
      this.data = initial.slice();
    }
  }

  // ---------------- IDataSource ----------------

  totalCount(): number {
    return this.headerCount + this.data.length + this.footerCount;
  }

  /** 上游 SimpleAdapter#getItem / getItemViewType 的数据部分 */
  getData(index: number): E | null {
    const real: number = index - this.headerCount;
    if (real < 0 || real >= this.data.length) {
      return null;
    }
    return this.data[real];
  }

  registerDataChangeListener(listener: SceneDataSourceListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: SceneDataSourceListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // ---------------- SimpleAdapter 行为 ----------------

  /** 上游 setData(E) / setData(List<E>)：整段替换 → 一次 reload */
  setAll(items: E[]): void {
    this.data = items.slice();
    this.notifyReloaded();
  }

  /** 上游 addData(E) / addData(List<E>)：追加到尾部 */
  addAll(items: E[]): void {
    const start: number = this.headerCount + this.data.length;
    for (let i = 0; i < items.length; i++) {
      this.data.push(items[i]);
    }
    for (let i = 0; i < items.length; i++) {
      this.notifyAdd(start + i);
    }
  }

  /** 上游 setData(int index, E) */
  setAt(index: number, item: E): void {
    const real: number = index - this.headerCount;
    if (real < 0 || real >= this.data.length) {
      return;
    }
    this.data[real] = item;
    this.notifyChange(index);
  }

  /** 上游 addData(int index, E) */
  insertAt(index: number, item: E): void {
    const real: number = Math.max(0, Math.min(index - this.headerCount, this.data.length));
    this.data.splice(real, 0, item);
    this.notifyAdd(this.headerCount + real);
  }

  /** 上游 removeData(int index) */
  removeAt(index: number): E | null {
    const real: number = index - this.headerCount;
    if (real < 0 || real >= this.data.length) {
      return null;
    }
    const removed: E[] = this.data.splice(real, 1);
    this.notifyDelete(index);
    return removed.length > 0 ? removed[0] : null;
  }

  /** 上游 clearData()：整段清空 */
  clear(): void {
    this.data = [];
    this.notifyReloaded();
  }

  /** 上游 swapData(int, int)：ArkUI 侧用 onDataMove，避免整表重绘 */
  move(from: number, to: number): void {
    const fromReal: number = from - this.headerCount;
    const toReal: number = to - this.headerCount;
    if (fromReal < 0 || fromReal >= this.data.length || toReal < 0 || toReal >= this.data.length) {
      return;
    }
    const item: E[] = this.data.splice(fromReal, 1);
    this.data.splice(toReal, 0, item[0]);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataMove(from, to);
    }
  }

  /** 上游 adaper 的 getItemCount（不含 header/footer） */
  getItemCount(): number {
    return this.data.length;
  }

  /** 当前数据快照（只读用途；页面做 diff 时用） */
  snapshot(): E[] {
    return this.data.slice();
  }

  /** 上游 footer/header 支持（GalleryListScene 用 footer 显示加载态） */
  setHeaderCount(count: number): void {
    this.headerCount = Math.max(0, count);
    this.notifyReloaded();
  }

  setFooterCount(count: number): void {
    this.footerCount = Math.max(0, count);
    this.notifyReloaded();
  }

  getHeaderCount(): number {
    return this.headerCount;
  }

  getFooterCount(): number {
    return this.footerCount;
  }

  // ---------------- 通知 ----------------

  private notifyReloaded(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private notifyAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  private notifyChange(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  private notifyDelete(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}
