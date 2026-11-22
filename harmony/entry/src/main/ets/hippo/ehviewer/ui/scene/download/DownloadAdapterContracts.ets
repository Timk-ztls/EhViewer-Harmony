/*
 * 下载页的**消费方契约**（DownloadsScene ↔ DownloadAdapter）
 *
 * 上游：`app/src/main/java/com/hippo/ehviewer/ui/scene/download/part/DownloadAdapter.kt`
 *   - `DownloadAdapterCallback`（L~150，适配器反向读场景状态）
 *   - `DownloadAdapter : RecyclerView.Adapter<DownloadHolder>`（779 行，ui-scene 的 S0221）
 *
 * 为什么把接口放在**消费方**（本文件属于 DownloadsScene 的骨架，C-18）：
 *   适配器需要用到的场景状态（当前页、每页条数、列表、spiderInfo、manager）都是**场景持有**的，
 *   接口形状由场景定义最自然；ui-scene 实现 `DownloadAdapterLike` 时按此对接即可，
 *   不需要猜场景内部字段。
 *
 * 两处上游细节（**照抄，勿"优化"**）：
 *   1. `paginationSize = 500`（`DownloadPaginationController.kt:51`）是**开启分页的阈值**，
 *      不是每页条数；`list.size > paginationSize && isCanPagination` 才分页。
 *      所以 list 少于 500 项时 `positionInList(p) === p`（全量一页）。
 *   2. `positionInList / listIndexInPage` 的分页公式：
 *        positionInList(p)  = p + pageSize * (indexPage - 1)
 *        listIndexInPage(p) = p % pageSize
 *      仅在上面的条件成立时使用，否则原样返回 p。
 */

import { DownloadInfo } from '../../../dao/DownloadInfo';
import { SpiderInfo } from '../../../spider/SpiderInfo';

/** 开启分页的**阈值**（上游 `paginationSize = 500`），与每页条数是两件事。 */
export const PAGINATION_THRESHOLD: number = 500;

/**
 * 适配器反向读取的场景状态（上游 `DownloadAdapterCallback`）。
 *
 * ui-scene 的 `DownloadAdapter` 实现 `DownloadAdapterLike` 时，会持有本接口的实例（= DownloadsScene）。
 */
export interface DownloadAdapterCallbackLike {
  /** 当前页（1 起）。 */
  getIndexPage(): number;

  /** 每页条数（由分页控件回报，见 `DownloadsScene.setPageSize`）。 */
  getPageSize(): number;

  /** 开启分页的阈值（固定 500，见上方说明）。 */
  getPaginationSize(): number;

  /** 当前是否允许分页（上游 `isCanPagination`，默认 true）。 */
  isCanPagination(): boolean;

  /** 屏幕位置 → 列表下标（分页生效时 `p + pageSize*(indexPage-1)`）。 */
  positionInList(position: number): number;

  /** 屏幕位置 → 页内下标（分页生效时 `p % pageSize`）。 */
  listIndexInPage(position: number): number;

  /** 当前列表（适配器的数据源）。 */
  getList(): DownloadInfo[];

  /** gid → SpiderInfo（用于展示阅读进度 `3/20`；缺失表示还没读到进度文件）。 */
  getSpiderInfoMap(): Map<number, SpiderInfo>;

  /** 下载管理器（适配器用它查实时速度/状态）。 */
  getDownloadManager(): Object | null;
}

/**
 * 场景使用的适配器视图（C-18：本模块声明所需）。
 *
 * ArkTS 侧没有 `RecyclerView.Adapter`，实际是 `List` + `LazyForEach`；
 * 所以场景只需要"让适配器知道数据变了" + "问它当前项数"，不需要 bind 回调。
 */
export interface DownloadAdapterLike {
  /** 数据整体变化（上游 `notifyDataSetChanged()`）。 */
  notifyDataSetChanged(): void;

  /** 当前项数（上游 `getItemCount()`）。 */
  getItemCount(): number;

  /** 对位上游 `DRAG_ENABLE`（来自 `Settings.getDragDownloadGallery()`；false 时禁止拖动排序）。 */
  isDragEnable(): boolean;
}

/**
 * 默认适配器：**未接线时给宿主一个能跑的空实现**，但每次调用都 warn。
 *
 * 为什么不在场景里判 `adapter === null` 再跳过：
 * 跳过 = 列表永远不刷新且没有任何痕迹（陷阱 52）。这里给一个可用的空实现 + 每次 warn，
 * 至少"界面上没有内容 + 日志里有 warn" —— 可诊断。
 */
export class UnavailableDownloadAdapter implements DownloadAdapterLike {
  private static readonly TAG: string = 'UnavailableDownloadAdapter';

  notifyDataSetChanged(): void {
    console.warn(`[${UnavailableDownloadAdapter.TAG}] DownloadAdapter 未接线：` +
      'notifyDataSetChanged() 被调用但无实现（ui-scene 的 S0221 尚未交付）');
  }

  getItemCount(): number {
    return 0;
  }

  isDragEnable(): boolean {
    return false;
  }
}
