/*
 * 上游：.../ui/scene/download/part/MyPageChangeListener.java（144 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/part/MyPageChangeListener.ets（S0229）
 *
 * 上游事实：implements PaginationIndicator.OnChangedListener
 *   字段 indexPage = 1 / pageSize = 1 / needInitPage = false / doNotScroll = false
 *        mAdapter / mRecyclerView / mPageChangeCallback
 * 与 S0227 DownloadPaginationController 的分工：控制器持有分页状态与换算，
 * 本监听器负责"指示器变化 → 列表滚动/刷新"的桥接，二者共用同一套页码语义（1 基）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 上游 PageChangeCallback（控制器在页码变化后回调宿主） */
export interface PageChangeCallbackLike {
  onPageSelected(page: number): void;
}

export interface PageChangeTargetLike {
  notifyDataSetChanged(): void;
  scrollToPosition(position: number): void;
}

export class MyPageChangeListener {
  /** 与上游同名同初值（1 基，不是 0 基） */
  private indexPage: number = 1;
  private pageSize: number = 1;
  private needInitPage: boolean = false;
  private doNotScroll: boolean = false;
  private callback: PageChangeCallbackLike | null = null;
  private target: PageChangeTargetLike | null = null;

  setPageChangeCallback(cb: PageChangeCallbackLike): void { this.callback = cb; }
  setTarget(t: PageChangeTargetLike): void { this.target = t; }
  setPageSize(size: number): void { this.pageSize = size > 0 ? size : 1; }
  getPageSize(): number { return this.pageSize; }
  getIndexPage(): number { return this.indexPage; }
  isNeedInitPage(): boolean { return this.needInitPage; }
  markNeedInitPage(v: boolean): void { this.needInitPage = v; }
  setDoNotScroll(v: boolean): void { this.doNotScroll = v; }

  /**
   * 上游 onChanged(newIndexPage)：指示器把新页码交过来。
   * 顺序：记页码 → 回调宿主 → 需要时滚动（doNotScroll 期间不滚）→ 刷新列表。
   */
  onChanged(newIndexPage: number): void {
    if (newIndexPage < 1) {
      hilog.warn(0x0000, 'MyPageChangeListener', '页码非法: %{public}d；后果：忽略本次切换', newIndexPage);
      return;
    }
    this.indexPage = newIndexPage;
    if (this.callback !== null) {
      this.callback.onPageSelected(newIndexPage);
    }
    if (this.target === null) {
      hilog.warn(0x0000, 'MyPageChangeListener', 'target 未注入: 页码=%{public}d；后果：列表不刷新', newIndexPage);
      return;
    }
    if (!this.doNotScroll) {
      this.target.scrollToPosition(this.pageSize * (newIndexPage - 1));
    }
    this.target.notifyDataSetChanged();
  }

  /** 上游 needInitPage 的消费点：首次进入时把指示器拉到第 1 页 */
  applyInitPage(): void {
    if (!this.needInitPage) {
      return;
    }
    this.needInitPage = false;
    this.indexPage = 1;
    if (this.target !== null) {
      this.target.scrollToPosition(0);
      this.target.notifyDataSetChanged();
    }
  }
}
