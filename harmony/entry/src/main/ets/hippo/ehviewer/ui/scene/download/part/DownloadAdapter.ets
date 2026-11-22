/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/download/part/DownloadAdapter.kt（779 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/DownloadAdapter.ets（inventory S0225）
 *
 * 本批交付 **适配器契约实现（Part 1）**：解锁 storage-db 的 DownloadsScene Part 2。
 *   - DownloadAdapterLike：notifyDataSetChanged / getItemCount / isDragEnable
 *   - DownloadAdapterCallbackLike：反向读场景状态（storage-db 实现，本类只消费）
 *   - 分页数学（storage-db 已查证的上游公式）：
 *       paginationSize = 500 是「开启分页的阈值」，判定用 > 而非 >=
 *       positionInList(p)  = p + pageSize * (indexPage - 1)
 *       listIndexInPage(p) = p % pageSize
 *   - 拖动：上游 DraggableItemAdapter + DRAG_ENABLE = Settings.getDragDownloadGallery()
 *
 * Part 2 待补：onBindViewHolder 的字段计算（thumb/title/进度/速度/状态文本）——
 *   需要 DownloadHolder 的字段清单，我下一轮读上游 holder + item_download_list 布局后补。
 */
import { DownloadInfo } from '../../../../dao/DownloadInfo';
import { SceneDataSource } from '../../../../../ui/SceneDataSource';

/** 上游 DownloadAdapterCallback：适配器反向读场景状态（storage-db 在 DownloadsScene 实现） */
export interface DownloadAdapterCallbackLike {
  getIndexPage(): number;
  getPageSize(): number;
  getPaginationSize(): number;
  isCanPagination(): boolean;
  getList(): DownloadInfo[];
  getDownloadManager(): Object | null;
}

/** 场景使用适配器的三件事（storage-db 的 Part 2 依赖此契约） */
export interface DownloadAdapterLike {
  notifyDataSetChanged(): void;
  getItemCount(): number;
  isDragEnable(): boolean;
}

export class DownloadAdapter implements DownloadAdapterLike {
  /** 上游 paginationSize = 500：超过才分页（判定用 >） */
  static readonly DEFAULT_PAGINATION_SIZE: number = 500;

  private readonly callback: DownloadAdapterCallbackLike;
  private readonly dataSource: SceneDataSource<DownloadInfo>;
  private dragEnable: boolean = false;

  constructor(callback: DownloadAdapterCallbackLike, dataSource: SceneDataSource<DownloadInfo>) {
    this.callback = callback;
    this.dataSource = dataSource;
  }

  /** 上游 DRAG_ENABLE = Settings.getDragDownloadGallery() */
  setDragEnable(enable: boolean): void {
    this.dragEnable = enable;
  }

  isDragEnable(): boolean {
    return this.dragEnable;
  }

  /** 上游 isCanPagination：list.size > paginationSize */
  isCanPagination(): boolean {
    const size: number = this.callback.getList().length;
    const threshold: number = this.callback.getPaginationSize();
    return this.callback.isCanPagination() && size > threshold;
  }

  /** 上游 positionInList(p) = p + pageSize * (indexPage - 1)（仅分页时） */
  positionInList(position: number): number {
    if (!this.isCanPagination()) {
      return position;
    }
    return position + this.callback.getPageSize() * (this.callback.getIndexPage() - 1);
  }

  /** 上游 listIndexInPage(p) = p % pageSize */
  listIndexInPage(position: number): number {
    if (!this.isCanPagination()) {
      return position;
    }
    return position % this.callback.getPageSize();
  }

  /** 上游 getItemCount：分页时返回 pageSize，否则返回整表长度 */
  getItemCount(): number {
    const total: number = this.callback.getList().length;
    if (!this.isCanPagination()) {
      return total;
    }
    const pageSize: number = this.callback.getPageSize();
    const remain: number = total - pageSize * (this.callback.getIndexPage() - 1);
    return remain < pageSize ? remain : pageSize;
  }

  /** 上游 notifyDataSetChanged → LazyForEach 的 onDataReloaded */
  notifyDataSetChanged(): void {
    this.dataSource.setAll(this.callback.getList());
  }
}
