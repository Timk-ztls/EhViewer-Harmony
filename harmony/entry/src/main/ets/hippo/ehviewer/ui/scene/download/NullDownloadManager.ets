/*
 * ⑤ U-02e：`DownloadManagerLike` 的空实现（**临时**）。
 *
 * 为什么需要它：`DownloadsScene(downloadManager: DownloadManagerLike | null)` 需要非 null 才能装配；
 * 传 null 时页面永远是空列表（比崩溃更难发现）。传一个空实现后：
 *   页面能打开 → 空态可见 → 日志明说"下载管理未接线"（符合"失败/缺失必须显式"）。
 *
 * ⚠ 这是临时实现：真实 `DownloadManager`（download-sync 域）就绪后**替换**本类，
 *   替换点见 `AppWiring` 里注入处的 hilog.info 提示。
 *
 * 三条设计要求（Lead 裁定）：
 *   ① 每个 warn **warn-once**（静态标志）—— 否则列表滚动/刷新会每秒刷几十条，把真警告淹掉
 *   ② 返回值安全且语义正确：列表 → []（不是 null）；bool → false；Promise → **resolve 而非 reject**
 *      （reject 会让页面显示"加载失败"，而真实状态是"未接线"）
 *   ③ 文件头 + 注入处双重说明"临时实现 + 替换点"
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadInfo } from '../../../dao/DownloadInfo';
import { DownloadManagerLike } from './DownloadsScene';

const DOMAIN: number = 0x0000;
const TAG: string = 'NullDownloadManager';

export class NullDownloadManager implements DownloadManagerLike {
  /** warn-once 标志（每个方法一个，避免刷屏） */
  private static warnedAll: boolean = false;
  private static warnedDefault: boolean = false;
  private static warnedByLabel: boolean = false;

  private static warnOnce(kind: number): void {
    if (kind === 0 && !NullDownloadManager.warnedAll) {
      NullDownloadManager.warnedAll = true;
      hilog.warn(DOMAIN, TAG,
        'getDownloadInfoList 未接线（真实 DownloadManager 未交付）；后果：下载页显示空列表。此告警只打印一次');
      return;
    }
    if (kind === 1 && !NullDownloadManager.warnedDefault) {
      NullDownloadManager.warnedDefault = true;
      hilog.warn(DOMAIN, TAG,
        'getDefaultDownloadInfoList 未接线；后果：默认标签下显示空列表。此告警只打印一次');
      return;
    }
    if (kind === 2 && !NullDownloadManager.warnedByLabel) {
      NullDownloadManager.warnedByLabel = true;
      hilog.warn(DOMAIN, TAG,
        'getLabelDownloadInfoList 未接线；后果：按标签过滤永远为空。此告警只打印一次');
    }
  }

  /** 全部下载项：返回 []（不是 null —— null 会被调用方当成"标签不存在"） */
  getDownloadInfoList(): DownloadInfo[] {
    NullDownloadManager.warnOnce(0);
    return [];
  }

  getDefaultDownloadInfoList(): DownloadInfo[] {
    NullDownloadManager.warnOnce(1);
    return [];
  }

  /**
   * 按标签：上游用 null 表示"标签已被删"。
   * 空实现**不能**返回 null（会触发上游"标签被删"分支），返回 [] 表示"该标签下没有项"。
   */
  getLabelDownloadInfoList(label: string): DownloadInfo[] | null {
    NullDownloadManager.warnOnce(2);
    return [];
  }
}
