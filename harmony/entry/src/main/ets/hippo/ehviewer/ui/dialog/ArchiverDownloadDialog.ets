/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/dialog/ArchiverDownloadDialog.java
 *       （inventory S0190，上游 227 行；清单登记 194 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/dialog/ArchiverDownloadDialog.ets
 *
 * 背景：档案（Archiver）下载对话框。先拉一次 METHOD_ARCHIVER 拿到"当前 GP / 原档与重采样的价格+大小"，
 * 点其中一个下载按钮 → METHOD_DOWNLOAD_ARCHIVER 拿真实下载 URL → 校验 scheme → 交给 ArchiverDownloader。
 *
 * ── 关键行为（照搬，别顺手修）────────────────────────────────────────────────
 * 1. finally 里无条件切"加载中"（progressBar.VISIBLE + body.INVISIBLE）——
 *    即使 url == null 提前 return 也会把 body 藏起来。
 * 2. 当前资金文案分站点：只有 SITE_E 才加 archiver_dialog_current_funds 前缀，其它站点裸显示 data.funds。
 * 3. 两条失败路径的 dismiss 语义不同：onDownloadUrl 里无条件 dismiss；
 *    DownloadArchiverListener.onFailure 里 isShowing() 才 dismiss。
 * 4. scheme 白名单必须在下载器启动之前（http/https，忽略大小写）。
 * 5. createFileName 为空要当失败。
 * 6. dlcheck 是两个硬编码英文串（"Download Original Archive" / "Download Resample Archive"），
 *    它们会进网络请求，不是 UI 文案，不能本地化。
 * 7. 下载在应用内继续（onDismiss 空实现）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * AlertDialog + 9 个 findViewById → ArchiverDialogSpec（纯数据）；
 * EhRequest/EhClient → ArchiverApi；ArchiverDownloader.getInstance → 宿主 getDownloaderAvailable()；
 * Toast/showTip/Log.w → 宿主；Uri.getScheme() → 本文件 urlScheme()；
 * NoHAtHClientException 判定 → 宿主 isNoHathError(e)；
 * GalleryDetail.archiveUrl 在本仓是可空字段（string | null）→ archiveUrl() 归一成空串。
 */

import { ArchiverData } from '../../client/data/ArchiverData';
import { GalleryDetail } from '../../client/data/GalleryDetail';

export const STR_DIALOG_TITLE: string = 'app.string.dialog_archiver_title';
export const STR_CURRENT_FUNDS: string = 'app.string.archiver_dialog_current_funds';
export const STR_COST: string = 'app.string.archiver_dialog_cost';
export const STR_SIZE: string = 'app.string.archiver_dialog_size';
export const STR_STATE_FAILED: string = 'app.string.download_state_failed';
export const STR_ARCHIVE_STARTED: string = 'app.string.download_archive_started';
export const STR_HATH_FAILURE: string = 'app.string.download_h_h_failure_no_hath';
export const STR_ARCHIVE_FAILURE: string = 'app.string.download_archive_failure';
export const LAYOUT_DIALOG_ARCHIVER: string = 'dialog_archiver';
export const DLCHECK_ORIGINAL: string = 'Download Original Archive';
export const DLCHECK_RESAMPLE: string = 'Download Resample Archive';
export const DLTYPE_ORIGINAL: string = 'org';
export const DLTYPE_RESAMPLE: string = 'res';
export const SITE_E: number = 0;

export interface ArchiverApi {
  requestArchiver(archiveUrl: string, gid: number, token: string): Promise<ArchiverData | null>;
  requestDownload(url: string, archiveUrl: string, dltype: string, dlcheck: string): Promise<string | null>;
}

export interface ArchiverDialogHost {
  resolveString(key: string): string;
  formatString(key: string, arg: string): string;
  getGallerySite(): number;
  hasActivity(): boolean;
  showTip(key: string, isLong: boolean): void;
  showToast(key: string): void;
  logWarning(msg: string): void;
  getDownloaderAvailable(): boolean;
  startDownload(downloadUrl: string, fileName: string): void;
  createFileName(title: string, gid: number): string;
  bindArchiverProgress(): void;
  isNoHathError(e: Error): boolean;
}

export class ArchiverDialogSpec {
  title: string = STR_DIALOG_TITLE;
  layoutName: string = LAYOUT_DIALOG_ARCHIVER;
  currentFunds: string = '';
  originalCost: string = '';
  originalSize: string = '';
  resampleCost: string = '';
  resampleSize: string = '';
  progressVisible: boolean = true;
  bodyVisible: boolean = false;
}

export class ArchiverDownloadAttempt {
  requested: boolean = false;
  dltype: string = '';
  dlcheck: string = '';
}

export class ArchiverDownloadDialog {
  private host: ArchiverDialogHost;
  private api: ArchiverApi;
  private detail: GalleryDetail;
  private data: ArchiverData = new ArchiverData();
  private spec: ArchiverDialogSpec = new ArchiverDialogSpec();
  private showing: boolean = false;

  constructor(detail: GalleryDetail, host: ArchiverDialogHost, api: ArchiverApi) {
    this.detail = detail;
    this.host = host;
    this.api = api;
  }

  private archiveUrl(): string {
    const v: string | null = this.detail.archiveUrl;
    return v === null ? '' : v;
  }

  async showDialog(): Promise<ArchiverDialogSpec> {
    this.showing = true;
    this.spec = new ArchiverDialogSpec();
    try {
      const data: ArchiverData | null =
        await this.api.requestArchiver(this.archiveUrl(), this.detail.gid, this.detail.token);
      if (data !== null) {
        this.onSuccess(data);
      }
    } catch (e) {
      this.onFailure(e as Error);
    }
    return this.spec;
  }

  getSpec(): ArchiverDialogSpec {
    return this.spec;
  }

  async onArchiverDownload(original: boolean): Promise<ArchiverDownloadAttempt> {
    const attempt: ArchiverDownloadAttempt = new ArchiverDownloadAttempt();
    try {
      let url: string = '';
      let dltype: string = '';
      let dlcheck: string = '';
      if (original) {
        url = this.data.originalUrl;
        dltype = DLTYPE_ORIGINAL;
        dlcheck = DLCHECK_ORIGINAL;
      } else {
        url = this.data.resampleUrl;
        dltype = DLTYPE_RESAMPLE;
        dlcheck = DLCHECK_RESAMPLE;
      }
      if (url.length === 0) {
        return attempt;
      }
      attempt.dltype = dltype;
      attempt.dlcheck = dlcheck;
      if (this.host.hasActivity()) {
        attempt.requested = true;
        const downloadUrl: string | null =
          await this.api.requestDownload(url, this.archiveUrl(), dltype, dlcheck);
        if (downloadUrl !== null) {
          this.onDownloadUrl(downloadUrl);
        }
      }
      return attempt;
    } catch (e) {
      this.onFailure(e as Error);
      return attempt;
    } finally {
      this.spec.progressVisible = true;
      this.spec.bodyVisible = false;
    }
  }

  onSuccess(data: ArchiverData): void {
    this.data = data;
    let currentFunds: string = '';
    if (this.host.getGallerySite() === SITE_E) {
      currentFunds = this.host.resolveString(STR_CURRENT_FUNDS) + data.funds;
    } else {
      currentFunds = data.funds;
    }
    this.spec.currentFunds = currentFunds;
    this.spec.originalCost = this.host.formatString(STR_COST, data.originalCost);
    this.spec.resampleCost = this.host.formatString(STR_COST, data.resampleCost);
    this.spec.originalSize = this.host.formatString(STR_SIZE, data.originalSize);
    this.spec.resampleSize = this.host.formatString(STR_SIZE, data.resampleSize);
    this.spec.progressVisible = false;
    this.spec.bodyVisible = true;
  }

  onFailure(e: Error): void {
  }

  onDismiss(): void {
    this.showing = false;
  }

  onDownloadUrl(downloadUrl: string): void {
    if (!this.showing) {
      return;
    }
    if (downloadUrl.trim().length === 0) {
      this.host.showToast(STR_STATE_FAILED);
      return;
    }
    this.spec.progressVisible = false;
    this.spec.bodyVisible = true;
    this.showing = false;
    this.host.showTip(STR_ARCHIVE_STARTED, false);
    const fileName: string = this.host.createFileName(this.detail.title, this.detail.gid);
    if (fileName.length === 0) {
      this.host.showToast(STR_STATE_FAILED);
      return;
    }
    const scheme: string = urlScheme(downloadUrl);
    if (scheme !== 'http' && scheme !== 'https') {
      this.host.logWarning('Invalid download URL scheme: ' + downloadUrl);
      this.host.showToast(STR_STATE_FAILED);
      return;
    }
    if (!this.host.getDownloaderAvailable()) {
      this.host.showToast(STR_STATE_FAILED);
      return;
    }
    this.host.startDownload(downloadUrl, fileName);
    this.host.bindArchiverProgress();
  }

  onDownloadFailure(e: Error): void {
    if (this.showing) {
      this.showing = false;
    }
    if (this.host.isNoHathError(e)) {
      this.host.showTip(STR_HATH_FAILURE, true);
    } else {
      this.host.showTip(STR_ARCHIVE_FAILURE, true);
    }
  }

  isInstance(sceneTag: string): boolean {
    return sceneTag === 'GalleryDetailScene';
  }
}

/**
 * 上游 Uri.parse(url).getScheme() 的等价：取第一个冒号之前的部分并小写。
 * 无冒号、或冒号前出现 斜杠/问号/井号/空格 → 返回空串。
 */
export function urlScheme(url: string): string {
  const colon: number = url.indexOf(':');
  if (colon <= 0) {
    return '';
  }
  const head: string = url.substring(0, colon);
  for (let i = 0; i < head.length; i++) {
    const c: string = head.charAt(i);
    if (c === '/' || c === '?' || c === '#' || c === ' ') {
      return '';
    }
  }
  return head.toLowerCase();
}
