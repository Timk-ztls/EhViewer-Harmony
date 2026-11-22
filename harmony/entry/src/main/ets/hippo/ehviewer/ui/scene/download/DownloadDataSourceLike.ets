/*
 * 契约：DownloadsScene 与 DownloadAdapter(779, S0225) 之间的数据源接口（ui-scene 定义，storage-db 消费）
 * 上游：ui/scene/download/part/DownloadAdapter.kt + AndroidX ItemTouchHelper 拖动排序
 *
 * ArkUI 没有 RecyclerView/ViewHolder，等价位：
 *   RecyclerView.Adapter.getItemCount()      → totalCount()
 *   onBindViewHolder(holder, position)       → getData(index) 返回纯数据，由 @Component 渲染
 *   ItemTouchHelper 拖动排序                  → moveItem(from, to)（LazyForEach 的 onDataMove）
 *   DRAG_ENABLE（上游常量）                   → canDrag(index) / canDrop(from, to)
 */
import { DownloadInfo } from '../../../dao/DownloadInfo';

export interface DownloadDataSourceLike {
  totalCount(): number;
  getData(index: number): DownloadInfo | null;
  /** 拖动排序：上游 ItemTouchHelper.onMove 的等价 */
  moveItem(from: number, to: number): void;
  /** 上游 ViewHolder 是否可长按拖动 */
  canDrag(index: number): boolean;
  /** 上游 canDropOver：跨分组时禁止投放 */
  canDrop(from: number, to: number): boolean;
  /** 上游 DRAG_ENABLE 常量（0=禁用，1=启用） */
  readonly DRAG_ENABLE: number;
}
