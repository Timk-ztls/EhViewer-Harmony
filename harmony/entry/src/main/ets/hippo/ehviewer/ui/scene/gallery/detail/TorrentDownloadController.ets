/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/detail/TorrentDownloadController.java（337 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/detail/TorrentDownloadController.ets（S0235）
 *
 * 上游事实（grep 确认）：class TorrentDownloadController(gid, token, Host)
 *   字段：torrentList: TorrentInfo[] / downLoadAlertDialog: AlertDialog / torrentDownloadView
 *   方法：retryTorrentDownload()；下载走 DownloadTorrentManager；路径常量 EhConfig.TORRENT_PATH
 *
 * Part 1（本批）：拉取种子列表 → 选择对话框状态机 → 下载/重试，全部经接口注入。
 * Part 2 待补：对话框 UI（AlertDialog 列表样式）、下载进度回调的界面更新。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 上游 TorrentInfo 的最小投影（真实模型在 client/data，本类只用这几项） */
export interface TorrentInfoLike {
  readonly name: string;
  readonly size: string;
  readonly seeders: number;
  readonly peers: number;
  readonly url: string;
  readonly hash: string;
}

/** 上游 Host：控制器向场景回调 */
export interface TorrentDownloadHostLike {
  /** 拉种子列表（走 EhEngine.getTorrentList(gid, token)） */
  fetchTorrentList(gid: number, token: string): Promise<TorrentInfoLike[]>;
  /** 显示选择对话框（上游 downLoadAlertDialog） */
  showTorrentDialog(list: TorrentInfoLike[]): void;
  hideTorrentDialog(): void;
  /** 交给 DownloadTorrentManager */
  enqueueTorrentDownload(info: TorrentInfoLike): Promise<boolean>;
  /** 提示（上游 Toast） */
  toast(hintId: string): void;
}

/** 控制器状态（上游靠字段 + Handler 消息，这里显式化） */
export class TorrentDownloadState {
  static readonly IDLE: number = 0;
  static readonly LOADING: number = 1;
  static readonly CHOOSING: number = 2;
  static readonly DOWNLOADING: number = 3;
}

export class TorrentDownloadController {
  /** 上游静态导入 EhConfig.TORRENT_PATH；这里保留常量名，值由 download-sync 决定 */
  static readonly TORRENT_PATH_KEY: string = 'torrent_path';

  private readonly host: TorrentDownloadHostLike;
  readonly gid: number;
  readonly token: string;
  private torrentList: TorrentInfoLike[] = [];
  private state: number = TorrentDownloadState.IDLE;

  constructor(gid: number, token: string, host: TorrentDownloadHostLike) {
    this.gid = gid;
    this.token = token;
    this.host = host;
  }

  getState(): number {
    return this.state;
  }

  getTorrentList(): TorrentInfoLike[] {
    return this.torrentList;
  }

  /** 上游 showTorrentDialog 的第一步：拉列表；空列表提示后停在 IDLE */
  loadTorrentList(): void {
    if (this.state === TorrentDownloadState.LOADING) {
      return;
    }
    this.state = TorrentDownloadState.LOADING;
    this.host.fetchTorrentList(this.gid, this.token).then((list: TorrentInfoLike[]) => {
      this.torrentList = list;
      if (list.length === 0) {
        this.state = TorrentDownloadState.IDLE;
        hilog.info(0x0000, 'TorrentDownload', '种子列表为空: gid=%{public}d；后果：不弹选择框', this.gid);
        return;
      }
      this.state = TorrentDownloadState.CHOOSING;
      this.host.showTorrentDialog(list);
    }).catch((e: Error) => {
      this.state = TorrentDownloadState.IDLE;
      hilog.error(0x0000, 'TorrentDownload', 'fetchTorrentList failed: gid=%{public}d err=%{public}s；后果：无法下载种子',
        this.gid, e.message !== undefined ? e.message : String(e));
    });
  }

  /** 用户在对话框里选中一项 → 入队 */
  downloadTorrent(index: number): void {
    if (index < 0 || index >= this.torrentList.length) {
      hilog.warn(0x0000, 'TorrentDownload', 'downloadTorrent 越界: index=%{public}d size=%{public}d；后果：无动作',
        index, this.torrentList.length);
      return;
    }
    const info: TorrentInfoLike = this.torrentList[index];
    this.state = TorrentDownloadState.DOWNLOADING;
    this.host.hideTorrentDialog();
    this.host.enqueueTorrentDownload(info).then((ok: boolean) => {
      this.state = TorrentDownloadState.IDLE;
      if (!ok) {
        hilog.warn(0x0000, 'TorrentDownload', 'enqueueTorrentDownload 返回 false: hash=%{public}s；后果：种子未下载',
          info.hash);
      }
    }).catch((e: Error) => {
      this.state = TorrentDownloadState.IDLE;
      hilog.error(0x0000, 'TorrentDownload', 'enqueueTorrentDownload failed: hash=%{public}s err=%{public}s；后果：种子未下载',
        info.hash, e.message !== undefined ? e.message : String(e));
    });
  }

  /** 上游 retryTorrentDownload()：失败后重试同一次请求（列表为空时才重拉） */
  retryTorrentDownload(): void {
    if (this.torrentList.length > 0) {
      this.host.showTorrentDialog(this.torrentList);
      this.state = TorrentDownloadState.CHOOSING;
      return;
    }
    this.loadTorrentList();
  }

  /** 上游关闭对话框：状态回落（Dialog 的 onDismiss） */
  onDialogDismiss(): void {
    if (this.state === TorrentDownloadState.CHOOSING) {
      this.state = TorrentDownloadState.IDLE;
    }
  }
}
