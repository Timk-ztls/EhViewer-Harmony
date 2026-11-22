/*
 * 上游：.../ui/scene/download/part/DownloadPaginationController.kt（250 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/part/DownloadPaginationController.ets（S0227）
 *
 * 上游常量（逐个核对，不按名字推断）：
 *   indexPage 从 1 起（不是 0）
 *   pageSize 初值 1（未初始化前的占位，真值来自 perPageCountChoices 的用户选择）
 *   paginationSize = 500 —— 这是"开启分页的阈值"，不是每页条数
 *   perPageCountChoices = [50, 100, 200, 300, 500]
 *   判定用 > 而非 >=（storage-db 独立核对得出同一结论）
 */
export interface PaginationHostLike {
  getListSize(): number;
  notifyAdapter(): void;
  scrollToPosition(position: number): void;
}

export interface PaginationIndicatorLike {
  setTotalPages(total: number): void;
  setCurrentPage(page: number): void;
}

export class DownloadPaginationController {
  static readonly PAGINATION_SIZE: number = 500;
  static readonly PER_PAGE_CHOICES: number[] = [50, 100, 200, 300, 500];

  private readonly host: PaginationHostLike;
  indexPage: number = 1;
  pageSize: number = 1;
  isCanPagination: boolean = true;
  isNeedInitPage: boolean = false;
  indicator: PaginationIndicatorLike | null = null;
  private doNotScroll: boolean = false;

  constructor(host: PaginationHostLike) {
    this.host = host;
  }

  /** 上游判定：列表长度 > paginationSize 且允许分页 */
  shouldPagination(): boolean {
    return this.isCanPagination && this.host.getListSize() > DownloadPaginationController.PAGINATION_SIZE;
  }

  /** 上游 totalPages 计算（向上取整）；未分页时为 1 */
  getTotalPages(): number {
    if (!this.shouldPagination()) {
      return 1;
    }
    const size: number = this.host.getListSize();
    const ps: number = this.pageSize > 0 ? this.pageSize : 1;
    return Math.ceil(size / ps);
  }

  /** 上游 positionInList(p) = p + pageSize * (indexPage - 1)（仅分页时） */
  positionInList(position: number): number {
    if (!this.shouldPagination()) {
      return position;
    }
    return position + this.pageSize * (this.indexPage - 1);
  }

  /** 上游 listIndexInPage(p) = p % pageSize */
  listIndexInPage(position: number): number {
    if (!this.shouldPagination()) {
      return position;
    }
    return position % this.pageSize;
  }

  /** 换页：越界拒绝；分页态才滚动，doNotScroll 期间不滚（上游 onPageSelected 里的门控） */
  onPageSelected(page: number): void {
    const total: number = this.getTotalPages();
    if (page < 1 || page > total) {
      return;
    }
    this.indexPage = page;
    if (this.doNotScroll) {
      return;
    }
    if (this.shouldPagination()) {
      this.host.scrollToPosition(page === 1 ? 0 : this.pageSize * (page - 1));
    }
    this.host.notifyAdapter();
    if (this.indicator !== null) {
      this.indicator.setCurrentPage(page);
      this.indicator.setTotalPages(total);
    }
  }

  /** 每页条数变化：夹到 choices 里最接近的合法值，重置到第 1 页 */
  setPageSize(size: number): void {
    const choices: number[] = DownloadPaginationController.PER_PAGE_CHOICES;
    let picked: number = choices[0];
    let best: number = Math.abs(choices[0] - size);
    for (let i = 1; i < choices.length; i++) {
      const d: number = Math.abs(choices[i] - size);
      if (d < best) {
        best = d;
        picked = choices[i];
      }
    }
    this.pageSize = picked;
    this.indexPage = 1;
    this.host.notifyAdapter();
    if (this.indicator !== null) {
      this.indicator.setTotalPages(this.getTotalPages());
      this.indicator.setCurrentPage(1);
    }
  }

  /** 上游 doNotScroll 的开关（批量操作期间避免列表跳动） */
  setDoNotScroll(v: boolean): void { this.doNotScroll = v; }
  isDoNotScroll(): boolean { return this.doNotScroll; }

  /** 列表内容变化后刷新页数显示 */
  refreshTotal(): void {
    if (this.indicator === null) {
      return;
    }
    const total: number = this.getTotalPages();
    if (this.indexPage > total) {
      this.indexPage = total;
    }
    this.indicator.setTotalPages(total);
    this.indicator.setCurrentPage(this.indexPage);
  }
}
