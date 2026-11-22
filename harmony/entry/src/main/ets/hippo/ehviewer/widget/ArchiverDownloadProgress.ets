/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/ArchiverDownloadProgress.kt（inventory S0285，上游 163 行）
 *
 * 上游：归档（zip）下载的进度条（statusText + ProgressBar + 暂停/继续按钮），监听 ArchiverDownloader
 *
 * ============================ D 类检视结论：**本类无 D 类风险，全部按 A 类照搬** ============================
 * 按 Lead 提的三个 D 类风险点逐条核（一手读码）：
 *  ① 进度是否写进 DownloadInfo / 通知 / 持久化？ → **不写**。只写 `progressBar.progress` 与 statusText，
 *     状态由 `ArchiverDownloader` 自己持有。⇒ 纯显示，无"发出去的数据"。
 *  ② 百分比整数还是浮点？截断还是四舍五入？ → 文本 `String.format("%.2f", progress) + "%"`（两位小数）；
 *     进度条 `progressBar.progress = progress.toInt()` → **截断**（99.9% 显示 99，避免看起来已完成却未完成）。
 *     ⇒ 显示层差异，照搬（不改成四舍五入）。
 *  ③ indeterminate 分支是否写 -1 或 0？ → `progress = if (total > 0) downloaded*100.0/total else 0.0`，
 *     即 **total<=0 时用 0.0，从不写 -1**；且**不落库**，所以不存在"-1 与 0 混在同字段无法区分"的问题。
 *     ⇒ 无歧义风险（这是本类与真正的 indeterminate 进度条的关键区别：它没有"未知"语义）。
 *
 * 其它一手语义
 *  - `initThread(galleryInfo)`：`showing && boundGid == gid` → **直接 return（去重，避免重复绑定）**；
 *    `Settings.getArchiverDownloadId(gid) == -1` → 不显示；downloader 为 null → 不显示；
 *    绑定前先 `unbindListener`（换绑），再 `showing = true; boundGid = gid; VISIBLE`，先按 (0,0,0,paused) 刷一遍
 *  - 监听回调 **全部按 gid 过滤**（`if (gid != targetGid) return`）→ 防止多画廊并发时串台
 *  - `onSuccess/onFailure/onCancel` → postDone()：解绑 + GONE + showing=false + boundGid=-1
 *    （`onFailure` 额外先 setText(download_state_failed)）
 *  - `onPauseResumeClicked`：downloader 为 null 或 `boundGid < 0` → **no-op**；否则 paused ? resume : pause
 *  - `speed < 0` 时按 0 处理（`safeSpeed`），文案 `xxxx/S`
 *  - `onDetachedFromWindow`：解绑 + showing=false + boundGid=-1（**但不改 visibility**）
 *
 * 依赖缺口（规则 ③）：`ArchiverDownloader` 属 download-sync、`Settings.getArchiverDownloadId` 属 core-runtime、
 *   `FileUtils.humanReadableByteCount` 属 yorozuya → 全部以接口/回调注入，本批不实现下载器。
 *
 * ArkUI 对位：Progress + Text + Button；`post{}` 的线程切换由 ArkUI 主线程模型天然满足，不需要显式 post。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.ArchiverDownloadProgress';

/** 对位 ArchiverDownloader.Listener 中本组件用到的部分 */
export interface ArchiverDownloadListener {
  onProgress(gid: number, downloaded: number, total: number, speed: number, paused: boolean): void;

  onSuccess(gid: number): void;

  onFailure(gid: number): void;

  onCancel(gid: number): void;
}

/** 下载器能力（注入；未注入时组件不工作而非静默空转） */
export interface ArchiverDownloaderHost {
  getProgress(gid: number): ProgressSnapshot | null;

  addListener(gid: number, listener: ArchiverDownloadListener): void;

  removeListener(listener: ArchiverDownloadListener): void;

  pause(gid: number): void;

  resume(gid: number): void;
}

export class ProgressSnapshot {
  downloaded: number = 0;
  total: number = 0;
  speed: number = 0;
  paused: boolean = false;
}

/** 进度计算（纯函数，可单测；与上游逐式一致） */
export class ArchiverProgressMath {
  /** 上游：`if (total > 0) downloaded * 100.0 / total else 0.0`（total<=0 → 0，**不是 -1**） */
  static percentage(downloaded: number, total: number): number {
    return total > 0 ? (downloaded * 100.0) / total : 0.0;
  }

  /** 上游：`String.format("%.2f", progress) + "%"` —— 两位小数 */
  static percentText(progress: number): string {
    return `${progress.toFixed(2)}%`;
  }

  /** 上游：`progressBar.progress = progress.toInt()` —— **截断**（99.9 → 99） */
  static progressBarValue(progress: number): number {
    if (progress <= 0) {
      return 0;
    }
    if (progress >= 100) {
      return 100;
    }
    return Math.trunc(progress);
  }

  /** 上游：`if (speed < 0) 0 else speed` */
  static safeSpeed(speed: number): number {
    return speed < 0 ? 0 : speed;
  }
}

export class ArchiverProgressState {
  showing: boolean = false;
  paused: boolean = false;
  /** 上游 boundGid（-1 表示未绑定） */
  boundGid: number = -1;
  downloaded: number = 0;
  total: number = 0;
  speed: number = 0;
  /** 上游 onFailure 会先把文案切成"失败"，再 postDone 隐藏 */
  failed: boolean = false;

  /** 上游 initThread 的去重判断 */
  canBind(gid: number): boolean {
    return !(this.showing && this.boundGid === gid);
  }

  bind(gid: number, paused: boolean): void {
    this.showing = true;
    this.boundGid = gid;
    this.failed = false;
    this.paused = paused;
    this.downloaded = 0;
    this.total = 0;
    this.speed = 0;
  }

  /** 上游 onProgress：**按 gid 过滤** */
  applyProgress(gid: number, downloaded: number, total: number, speed: number, paused: boolean): boolean {
    if (gid !== this.boundGid) {
      return false; // 其它画廊的进度，忽略
    }
    this.downloaded = downloaded;
    this.total = total;
    this.speed = speed;
    this.paused = paused;
    return true;
  }

  fail(gid: number): boolean {
    if (gid !== this.boundGid) {
      return false;
    }
    this.failed = true;
    this.done();
    return true;
  }

  /** 上游 postDone：解绑 + 隐藏 + 复位 */
  done(): void {
    this.showing = false;
    this.boundGid = -1;
  }

  /** 上游 onPauseResumeClicked 的前置判断：downloader 为 null 或 boundGid < 0 → no-op */
  canTogglePause(): boolean {
    return this.boundGid >= 0;
  }

  /** 当前应执行的动作为 'pause' | 'resume' | 'noop' */
  pauseAction(): string {
    if (!this.canTogglePause()) {
      return 'noop';
    }
    return this.paused ? 'resume' : 'pause';
  }

  percentage(): number {
    return ArchiverProgressMath.percentage(this.downloaded, this.total);
  }

  statusText(humanSize: string): string {
    const percent: string = ArchiverProgressMath.percentText(this.percentage());
    if (this.paused) {
      return `${percent}`; // 前缀"已暂停"文案由调用方拼接（上游用 string 资源）
    }
    const speedText: string = `${humanSize}/S`;
    return `${percent}  ${speedText}`;
  }
}

@Component
export struct ArchiverDownloadProgress {
  state: ArchiverProgressState = new ArchiverProgressState();
  host: ArchiverDownloaderHost | null = null;
  /** 人类可读的速率文本（上游 FileUtils.humanReadableByteCount，属 yorozuya） */
  humanSize: (bytes: number) => string = (bytes: number) => `${bytes}`;
  onResume: () => void = () => {
  };
  onPause: () => void = () => {
  };
  @State rev: number = 0;

  aboutToAppear(): void {
    // 装配期检查（陷阱 52）：host 未注入 → 面板永远不显示且不报错
    if (this.host === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG,
        '%{public}s', 'ArchiverDownloaderHost not injected — progress panel will never appear');
    }
  }

  /** 对位 initThread：由调用方在进入画廊时触发 */
  bind(gid: number, paused: boolean): void {
    if (!this.state.canBind(gid)) {
      return; // 去重
    }
    const h: ArchiverDownloaderHost | null = this.host;
    if (h === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'host is null, cannot bind');
      return;
    }
    this.state.bind(gid, paused);
    const snap: ProgressSnapshot | null = h.getProgress(gid);
    if (snap !== null) {
      this.state.applyProgress(gid, snap.downloaded, snap.total, snap.speed, snap.paused);
    }
    this.rev = this.rev + 1;
  }

  private togglePause(): void {
    const action: string = this.state.pauseAction();
    if (action === 'noop') {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'pause/resume ignored: no bound download');
      return;
    }
    if (action === 'resume') {
      this.onResume();
    } else {
      this.onPause();
    }
    this.state.paused = !this.state.paused;
    this.rev = this.rev + 1;
  }

  build() {
    if (this.state.showing) {
      Row({ space: 8 }) {
        Text(this.state.failed ? 'Failed' : this.state.statusText(this.humanSize(this.state.speed)))
          .fontSize(14)
          .layoutWeight(1)
        Progress({ value: ArchiverProgressMath.progressBarValue(this.state.percentage()), total: 100 })
          .width(100)
        Button(this.state.paused ? '▶' : '⏸')
          .onClick(() => {
            this.togglePause();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    }
  }
}
