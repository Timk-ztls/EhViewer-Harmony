/*
 * 下载页的列表数据源（Part 2 渲染骨架的第一块）
 *
 * 上游对应：`DownloadAdapter.kt` 的 `getItemCount()` + `onBindViewHolder()` 的**数据部分**
 *   （`val list = mCallback.list ?: return` + `mCallback.positionInList(position)`）
 *
 * 为什么单独一层：ArkUI 的 `List` + `LazyForEach` 需要 `IDataSource`，
 * 而下载页的位置换算**不是简单的 index==index** —— 分页时屏幕位置要经
 * `DownloadAdapterCallbackLike.positionInList(pos)` 才映射到列表下标
 * （`pos + pageSize*(indexPage-1)`，且只在 `list.size > 500 && isCanPagination` 时生效）。
 * 把这段换算放进数据源，渲染层就只用 `getData(screenPos)`，不必知道分页细节。
 *
 * 线程：`IDataSource` 回调必须在 UI 线程；数据准备（DB/网络）在别处完成后整体 `reload()`。
 */

import { DownloadInfo } from '../../../dao/DownloadInfo';
import { DownloadAdapterCallbackLike } from './DownloadAdapterContracts';

/**
 * 拖动顺序持久化端口（download-sync 的 DownloadManager 实现它；参数是**列表下标**）。
 */
export interface DownloadOrderWriter {
  /** 把第 from 项移到第 to 项（列表下标，非屏幕位置）。 */
  moveDownload(from: number, to: number): void;
}

/** LazyForEach 的观察者接口（与 `hippo/ui/SceneDataSource.ets` 同一套约定）。 */
export interface DownloadDataSourceListener {
  onDataReloaded(): void;
  onDataChange(index: number): void;
}

/**
 * 下载列表数据源：屏幕位置 → 列表项。
 *
 * 两个"位置"必须分清（这是本类存在的主要理由）：
 *   - **屏幕位置**（`getData` 的入参，LazyForEach 给）：分页后仅当前页内的 0..pageSize-1
 *   - **列表下标**：整个 `mList` 的下标
 * 换算只在 `isPaginationActive()` 时不同；不分页时两者相等。
 */
export class DownloadListDataSource {
  private callback: DownloadAdapterCallbackLike;
  private listeners: DownloadDataSourceListener[] = [];

  constructor(callback: DownloadAdapterCallbackLike) {
    this.callback = callback;
  }

  // ---------------------------------------------------------------- IDataSource

  /** 对位上游 `DownloadAdapter.getItemCount()`：分页时只返回**当前页**的条数。 */
  totalCount(): number {
    const total: number = this.callback.getList().length;
    if (!this.isPaginationActive()) {
      return total;
    }
    const pageSize: number = this.callback.getPageSize();
    if (pageSize <= 0) {
      // pageSize 异常（控件还没回报）→ 不分页，避免除零/空列表
      console.warn('[DownloadListDataSource] pageSize <= 0，本次按不分页处理');
      return total;
    }
    const page: number = this.callback.getIndexPage();
    const start: number = pageSize * (page - 1);
    if (start >= total) {
      // 页号超出（数据变少后未回到第 1 页）→ 返回 0 项，由场景负责纠正页号
      return 0;
    }
    return Math.min(pageSize, total - start);
  }

  /** 屏幕位置 → 列表项。越界返回 null（上游 `list.get(pos)` 会抛，这里收敛为 null）。 */
  getData(screenPos: number): DownloadInfo | null {
    const list: DownloadInfo[] = this.callback.getList();
    const listIndex: number = this.callback.positionInList(screenPos);
    if (listIndex < 0 || listIndex >= list.length) {
      return null;
    }
    return list[listIndex];
  }

  /** 屏幕位置 → 页内位置（上游 `listIndexInPage`；渲染层做"每页第 N 项"角标时用）。 */
  indexInPage(screenPos: number): number {
    return this.callback.listIndexInPage(screenPos);
  }

  registerDataChangeListener(listener: DownloadDataSourceListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DownloadDataSourceListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }

  // ---------------------------------------------------------------- 拖动排序（对位 DownloadDataSourceLike）

  /**
   * 拖动顺序的持久化端口（消费方声明）。
   *
   * **为什么必须注入**：本数据源的列表是 `DownloadManager` 返回的**快照**，
   * `updateForLabel()` 会重新取 —— 在这里就地交换数组元素是**无效的**（下次刷新即被覆盖）。
   * 所以顺序必须由持有权威列表的一方落盘（download-sync 的 `DownloadManager` 或它提供的 move API）。
   *
   * 未注入时 `moveItem()` **显式返回 false 并 warn**，而不是"看起来拖动了实际没保存"
   * （那会让用户下次打开时顺序跳回去，且无痕迹）。
   */
  setOrderWriter(writer: DownloadOrderWriter | null): void {
    this.orderWriter = writer;
  }

  private orderWriter: DownloadOrderWriter | null = null;

  /** 上游 `DRAG_ENABLE`（0=禁用 / 1=启用；来自 `Settings.getDragDownloadGallery()`）。 */
  readonly DRAG_ENABLE: number = 1;

  /** 对位 `canDrag(index)`：拖动开关打开且该位置有效。 */
  canDrag(index: number): boolean {
    if (this.DRAG_ENABLE === 0) {
      return false;
    }
    return this.getData(index) !== null;
  }

  /**
   * 对位 `canDrop(from, to)`：**跨分组禁止**。
   *
   * 分组 = `DownloadInfo.label`（上游 `canDropOver` 比对两者的标签）。
   * 同列表内通常是同一标签，但"全部下载"视图里会混着不同标签 —— 那时不允许跨标签拖动，
   * 否则会**静默改变归属**（把 A 标签的项挪进 B 标签）。
   */
  canDrop(from: number, to: number): boolean {
    if (!this.canDrag(from) || !this.canDrag(to)) {
      return false;
    }
    const a: DownloadInfo | null = this.getData(from);
    const b: DownloadInfo | null = this.getData(to);
    if (a === null || b === null) {
      return false;
    }
    const la: string | null = a.getLabel();
    const lb: string | null = b.getLabel();
    const same: boolean = (la === null && lb === null) || (la !== null && lb !== null && la === lb);
    return same;
  }

  /**
   * 对位 `moveItem(from, to)`：把拖动结果交给 order writer 落盘，然后整段重载。
   *
   * 返回 false 的两种情况都会 warn（不静默）：
   *   - 未注入 writer（顺序无处可存）
   *   - `canDrop` 为 false（跨分组）
   */
  moveItem(from: number, to: number): boolean {
    if (!this.canDrop(from, to)) {
      console.warn(`[DownloadListDataSource] moveItem(${from}, ${to}) 被拒绝：跨分组或越界`);
      return false;
    }
    const writer: DownloadOrderWriter | null = this.orderWriter;
    if (writer === null) {
      console.warn('[DownloadListDataSource] moveItem: 未注入 DownloadOrderWriter，' +
        '顺序无法持久（下次刷新会被覆盖）——已拒绝本次拖动而不是假装成功');
      return false;
    }
    const listIndexFrom: number = this.callback.positionInList(from);
    const listIndexTo: number = this.callback.positionInList(to);
    writer.moveDownload(listIndexFrom, listIndexTo);
    this.reload();
    return true;
  }
  // ---------------------------------------------------------------- 变更通知

  /**
   * 整段重载（列表/标签/页号变化都走这里）。
   *
   * 为什么不用 `onDataChange(index)` 精细通知：下载页的列表是**全量重取**的
   * （`DownloadManager` 返回快照），逐条 diff 的成本高于收益，且分页生效时
   * 任何页号变化都会重排所有屏幕位置 —— 精细通知反而容易错。
   */
  reload(): void {
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }

  /** 单条变化（如某项下载进度更新；分页生效时按屏幕位置换算回调）。 */
  notifyItemChanged(listIndex: number): void {
    const screenPos: number = this.toScreenPos(listIndex);
    if (screenPos < 0) {
      return;
    }
    for (const l of this.listeners) {
      l.onDataChange(screenPos);
    }
  }

  // ---------------------------------------------------------------- 内部

  private isPaginationActive(): boolean {
    return this.callback.getList().length > this.callback.getPaginationSize()
      && this.callback.isCanPagination();
  }

  /**
   * 列表下标 → 屏幕位置（`positionInList` 的逆运算）。
   * 不在当前页时返回 -1（调用方据此跳过通知，而不是刷到错误的行）。
   */
  private toScreenPos(listIndex: number): number {
    if (!this.isPaginationActive()) {
      return listIndex;
    }
    const pageSize: number = this.callback.getPageSize();
    if (pageSize <= 0) {
      return listIndex;
    }
    const start: number = pageSize * (this.callback.getIndexPage() - 1);
    const offset: number = listIndex - start;
    return (offset >= 0 && offset < pageSize) ? offset : -1;
  }
}
