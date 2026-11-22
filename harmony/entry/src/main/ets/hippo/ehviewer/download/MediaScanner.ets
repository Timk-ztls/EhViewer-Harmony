/*
 * 相册扫描（对位上游下载完成后触发的 `MediaScannerConnection.scanFile` / `sendBroadcast(MEDIA_SCANNER_SCAN_FILE)`）。
 *
 * ============================================================================
 * 为什么需要薄薄一层接口
 * ============================================================================
 * HarmonyOS 侧没有等价的"单文件扫描广播"，对位实现是
 *   ① `photoAccessHelper.getPhotoAccessHelper(ctx).showAssetsCreationDialog(...)`（要 UI）
 *   ② `media` 库的 `MediaLibrary` 全量重扫（重）
 *   ③ 直接把文件写进 `PhotoAccessHelper` 的沙箱目录（下载目录本来就不在其内）
 * 三者都**不能**在"下载完成回调"里无条件调（会弹框 / 会卡）。
 *
 * 所以按铁律：**接口 + Noop 实现（warn-once）**，等 UI 侧确认采用哪条路线再接。
 * 这样调用点（下载完成路径）是完整正确的，缺的只是"落地动作"。
 *
 * ⚠️ 后果（没有这一层的实际情况）：用户下载的图片在系统图库里看不到，
 * 要重启或手动刷新才出现 —— 这就是上游为什么要在这里扫一次。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'MediaScanner';


/** 扫描器接口：只做"通知系统有这个文件"。 */
export interface MediaScannerLike {
  /**
   * 通知系统"某个画廊的下载目录里有新图片"（异步，失败不抛 —— 扫描失败不该影响下载状态）。
   *
   * **为什么传 gid 而不是路径**：`onFinish` 分支手里只有 `DownloadInfo`（没有 `GalleryInfo`），
   * 而路径解析要 `SpiderDen.getGalleryDownloadDir(galleryInfo)`。让实现侧去解析，
   * 调用方就不会拼出一个"看起来对但可能错"的路径字符串。
   * @param gid 画廊 gid（实现侧用 EhDB 的 gid→dirname 映射解析目录）
   */
  scanGallery(gid: number): void;
}

/**
 * 空实现：**只 warn 一次**，不假装成功。
 *
 * 「warn-once」而不是「每次都 warn」：下载完成是高频路径，每次都打会把日志淹掉；
 * 而完全不 warn 会让"图库看不到图"变成无法定位的悬案。
 */
export class NoopMediaScanner implements MediaScannerLike {
  private static sWarned: boolean = false;
  private static sCallCount: number = 0;

  scanGallery(gid: number): void {
    NoopMediaScanner.sCallCount++;
    if (!NoopMediaScanner.sWarned) {
      NoopMediaScanner.sWarned = true;
      hilog.warn(DOMAIN, TAG,
        'MediaScanner 未接线（D-NNN）：首个待扫描 gid=%{public}d；后果：下载的图片在图库里看不到，需重启或手动刷新',
        gid);
    }
  }

  /** 观测用：被要求扫描的次数（测试/巡检可读）。 */
  static callCount(): number {
    return NoopMediaScanner.sCallCount;
  }

  /** 观测用：是否已经 warn 过（断言"只 warn 一次"用）。 */
  static warned(): boolean {
    return NoopMediaScanner.sWarned;
  }

  /** 测试复位。 */
  static reset(): void {
    NoopMediaScanner.sWarned = false;
    NoopMediaScanner.sCallCount = 0;
  }
}

