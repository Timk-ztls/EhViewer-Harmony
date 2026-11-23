/*
 * 阅读器渲染引擎状态机、Watchdog 决策、外部参数解析与 API 20 按键映射（Stage C Track P5 新增）。
 * 纯逻辑模块，不依赖 @kit.ArkUI / @ohos.window，供 GalleryReaderPage 与 Node 单测共用。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ACTION_DIR,
  ACTION_EH,
  ACTION_VIEW,
  GalleryActivity,
  GalleryActivityKeys,
  KEY_ACTION,
  KEY_CURRENT_INDEX,
  KEY_FILENAME,
  KEY_PAGE,
  KEY_URI,
  KeyCode,
  ProviderPlan
} from '../../ehviewer/ui/GalleryActivity';

const DOMAIN: number = 0x0000;
const TAG: string = 'ReaderEngineCoordinator';

export const OHOS_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';

export enum RenderEngineMode {
  GL_PENDING = 0,
  GL_ACTIVE = 1,
  SWIPER_FALLBACK = 2,
  ARKUI_PRIMARY = 3
}

export enum FallbackReason {
  NONE = 0,
  WATCHDOG_TIMEOUT = 1,
  SURFACE_INIT_FAILED = 2,
  CONSECUTIVE_RENDER_ERRORS = 3,
  BACKEND_UNAVAILABLE = 4
}

export class ReaderRouteRequest {
  readonly action: string;
  readonly gid: number;
  readonly token: string;
  readonly page: number;
  readonly pages: number;
  readonly title: string;
  readonly apiUrl: string;
  readonly filename: string | null;
  readonly uri: string | null;
  readonly providerPlan: ProviderPlan;

  constructor(
    action: string,
    gid: number,
    token: string,
    page: number,
    pages: number,
    title: string,
    apiUrl: string,
    filename: string | null,
    uri: string | null,
    providerPlan: ProviderPlan
  ) {
    this.action = action;
    this.gid = gid;
    this.token = token;
    this.page = page;
    this.pages = pages;
    this.title = title;
    this.apiUrl = apiUrl;
    this.filename = filename;
    this.uri = uri;
    this.providerPlan = providerPlan;
  }

  static normalizeAction(rawAction: string | null, uri: string | null, filename: string | null): string {
    if (rawAction === OHOS_ACTION_VIEW_DATA || rawAction === ACTION_VIEW) {
      return ACTION_VIEW;
    }
    if (rawAction === ACTION_DIR || rawAction === ACTION_EH) {
      return rawAction;
    }
    if (uri !== null && uri.length > 0) {
      return ACTION_VIEW;
    }
    if (filename !== null && filename.length > 0) {
      return ACTION_DIR;
    }
    return ACTION_EH;
  }

  static extractDisplayName(uriOrPath: string | null): string {
    if (uriOrPath === null || uriOrPath.length === 0) {
      return '';
    }
    let clean: string = uriOrPath;
    const qIdx: number = clean.indexOf('?');
    if (qIdx >= 0) {
      clean = clean.substring(0, qIdx);
    }
    const hIdx: number = clean.indexOf('#');
    if (hIdx >= 0) {
      clean = clean.substring(0, hIdx);
    }
    while (clean.endsWith('/') && clean.length > 1) {
      clean = clean.substring(0, clean.length - 1);
    }
    const slash: number = clean.lastIndexOf('/');
    const segment: string = slash >= 0 && slash + 1 < clean.length ? clean.substring(slash + 1) : clean;
    try {
      return decodeURIComponent(segment);
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'decodeURIComponent skipped: %{public}s',
        e instanceof Error ? e.message : String(e));
      return segment;
    }
  }

  private static readString(rec: Record<string, Object>, key: string): string | null {
    const val: Object | undefined = rec[key];
    if (typeof val === 'string') {
      const s: string = val as string;
      return s.length > 0 ? s : null;
    }
    return null;
  }

  private static readNumber(rec: Record<string, Object>, key: string, fallback: number): number {
    const val: Object | undefined = rec[key];
    if (typeof val === 'number' && !Number.isNaN(val as number)) {
      return Math.trunc(val as number);
    }
    return fallback;
  }

  static fromParams(rec: Record<string, Object> | null): ReaderRouteRequest {
    if (rec === null) {
      const emptyPlan: ProviderPlan = GalleryActivity.buildProviderPlan(ACTION_EH, null, null, false);
      return new ReaderRouteRequest(ACTION_EH, 0, '', 0, 0, '', '', null, null, emptyPlan);
    }

    const gid: number = Math.max(0, ReaderRouteRequest.readNumber(rec, GalleryActivityKeys.KEY_GID, 0));
    const token: string = ReaderRouteRequest.readString(rec, 'token') ?? '';
    const pageRaw: number = ReaderRouteRequest.readNumber(rec, KEY_PAGE, -1);
    const curIdxRaw: number = ReaderRouteRequest.readNumber(rec, KEY_CURRENT_INDEX, 0);
    const page: number = Math.max(0, pageRaw >= 0 ? pageRaw : curIdxRaw);
    const pages: number = Math.max(0, ReaderRouteRequest.readNumber(rec, 'pages', 0));
    const rawTitle: string = ReaderRouteRequest.readString(rec, 'title') ?? '';
    const apiUrl: string = ReaderRouteRequest.readString(rec, 'apiUrl')
      ?? ReaderRouteRequest.readString(rec, GalleryActivityKeys.KEY_API_URL) ?? '';
    const filename: string | null = ReaderRouteRequest.readString(rec, KEY_FILENAME);
    const uri: string | null = ReaderRouteRequest.readString(rec, KEY_URI);
    const rawAction: string | null = ReaderRouteRequest.readString(rec, KEY_ACTION);

    const normalizedAction: string = ReaderRouteRequest.normalizeAction(rawAction, uri, filename);
    const hasGalleryInfo: boolean = gid > 0 && token.length > 0;
    const providerPlan: ProviderPlan = GalleryActivity.buildProviderPlan(
      normalizedAction, filename, uri, hasGalleryInfo
    );
    const title: string = rawTitle.length > 0
      ? rawTitle
      : ReaderRouteRequest.extractDisplayName(uri !== null ? uri : filename);

    return new ReaderRouteRequest(
      normalizedAction,
      gid,
      token,
      page,
      pages,
      title,
      apiUrl,
      filename,
      uri,
      providerPlan
    );
  }
}

/**
 * 将 OpenHarmony API 20 multimodalInput KeyCode 映射为上游 GalleryActivity.KeyCode。
 */
export function mapArkKeyCodeToGalleryKeyCode(arkKeyCode: number): number {
  switch (arkKeyCode) {
    case 16:
      return KeyCode.VOLUME_UP;
    case 17:
      return KeyCode.VOLUME_DOWN;
    case 2012:
      return KeyCode.DPAD_UP;
    case 2013:
      return KeyCode.DPAD_DOWN;
    case 2014:
      return KeyCode.DPAD_LEFT;
    case 2015:
      return KeyCode.DPAD_RIGHT;
    case 2016:
      return KeyCode.DPAD_CENTER;
    case 2050:
      return KeyCode.SPACE;
    case 2067:
      return KeyCode.MENU;
    case 2068:
      return KeyCode.PAGE_UP;
    case 2069:
      return KeyCode.PAGE_DOWN;
    default:
      return -1;
  }
}

export class ReaderEngineCoordinator {
  static readonly WATCHDOG_MS: number = 1500;
  static readonly MAX_CONSECUTIVE_RENDER_ERRORS: number = 3;

  private mode: RenderEngineMode = RenderEngineMode.GL_PENDING;
  private fallbackReason: FallbackReason = FallbackReason.NONE;
  private currentPage: number = 0;
  private totalPages: number = 0;
  private consecutiveErrors: number = 0;
  private glFrameCount: number = 0;

  reset(initialPage: number, totalPages: number): void {
    this.mode = RenderEngineMode.GL_PENDING;
    this.fallbackReason = FallbackReason.NONE;
    this.currentPage = Math.max(0, Math.trunc(initialPage));
    this.totalPages = Math.max(0, Math.trunc(totalPages));
    this.consecutiveErrors = 0;
    this.glFrameCount = 0;
  }

  /** 以原生 ArkUI 阅读器作为默认主引擎启动（跳过 GL Surface / Watchdog 阻塞链路）。 */
  useArkUiPrimary(initialPage: number, totalPages: number): void {
    this.mode = RenderEngineMode.ARKUI_PRIMARY;
    this.fallbackReason = FallbackReason.NONE;
    this.currentPage = Math.max(0, Math.trunc(initialPage));
    this.totalPages = Math.max(0, Math.trunc(totalPages));
    this.consecutiveErrors = 0;
    this.glFrameCount = 0;
  }

  getMode(): RenderEngineMode {
    return this.mode;
  }

  getFallbackReason(): FallbackReason {
    return this.fallbackReason;
  }

  getCurrentPage(): number {
    return this.currentPage;
  }

  getTotalPages(): number {
    return this.totalPages;
  }

  getConsecutiveErrors(): number {
    return this.consecutiveErrors;
  }

  getGlFrameCount(): number {
    return this.glFrameCount;
  }

  isGlActive(): boolean {
    return this.mode === RenderEngineMode.GL_ACTIVE;
  }

  isFallback(): boolean {
    return this.mode === RenderEngineMode.SWIPER_FALLBACK;
  }

  isArkUiPrimary(): boolean {
    return this.mode === RenderEngineMode.ARKUI_PRIMARY;
  }

  isArkUiMode(): boolean {
    return this.mode === RenderEngineMode.ARKUI_PRIMARY || this.mode === RenderEngineMode.SWIPER_FALLBACK;
  }

  setCurrentPage(page: number): void {
    const safePage: number = Math.max(0, Math.trunc(page));
    this.currentPage = this.totalPages > 0 ? Math.min(safePage, this.totalPages - 1) : safePage;
  }

  setTotalPages(total: number): void {
    this.totalPages = Math.max(0, Math.trunc(total));
    if (this.totalPages > 0 && this.currentPage >= this.totalPages) {
      this.currentPage = this.totalPages - 1;
    }
  }

  onGlSurfaceReady(): void {
    if (this.mode === RenderEngineMode.GL_PENDING) {
      this.mode = RenderEngineMode.GL_ACTIVE;
      this.consecutiveErrors = 0;
    }
  }

  onGlFrameSuccess(): void {
    this.glFrameCount++;
    this.consecutiveErrors = 0;
    if (this.mode === RenderEngineMode.GL_PENDING) {
      this.mode = RenderEngineMode.GL_ACTIVE;
    }
  }

  onGlRenderError(consecutiveCount: number, isFatalInit: boolean): boolean {
    if (this.mode === RenderEngineMode.ARKUI_PRIMARY || this.mode === RenderEngineMode.SWIPER_FALLBACK) {
      return false;
    }
    this.consecutiveErrors = Math.max(this.consecutiveErrors + 1, Math.trunc(consecutiveCount));
    if (isFatalInit) {
      return this.triggerFallback(FallbackReason.SURFACE_INIT_FAILED);
    }
    if (this.consecutiveErrors >= ReaderEngineCoordinator.MAX_CONSECUTIVE_RENDER_ERRORS) {
      return this.triggerFallback(FallbackReason.CONSECUTIVE_RENDER_ERRORS);
    }
    return false;
  }

  onWatchdogTimeout(): boolean {
    if (this.mode !== RenderEngineMode.GL_PENDING) {
      return false;
    }
    return this.triggerFallback(FallbackReason.WATCHDOG_TIMEOUT);
  }

  triggerFallback(reason: FallbackReason): boolean {
    if (this.mode === RenderEngineMode.ARKUI_PRIMARY || this.mode === RenderEngineMode.SWIPER_FALLBACK) {
      return false;
    }
    this.mode = RenderEngineMode.SWIPER_FALLBACK;
    this.fallbackReason = reason;
    return true;
  }
}

/**
 * 安全计算单页图片下载百分比 [0, 100]；
 * 未知长度 / 分块传输（contentLength <= 0）或非法数值统一返回 -1，禁止出现 NaN / Infinity。
 */
export function computeSafeDownloadPercent(contentLength: number, receivedSize: number): number {
  if (!Number.isFinite(contentLength) || contentLength <= 0 ||
    !Number.isFinite(receivedSize) || receivedSize < 0) {
    return -1;
  }
  return Math.max(0, Math.min(100, Math.round((receivedSize * 100) / contentLength)));
}

/**
 * 单页进度 UI 刷新节流器：首帧与 100% 必推，中间按时间间隔与百分比变化步长防抖，避免高频刷 @State。
 */
export class ProgressThrottle {
  private lastEmitTimeMs: number = -1;
  private lastEmitPercent: number = -1;

  reset(): void {
    this.lastEmitTimeMs = -1;
    this.lastEmitPercent = -1;
  }

  shouldEmit(
    percent: number,
    nowMs: number,
    minIntervalMs: number = 85,
    minDeltaPercent: number = 2,
    frameGuardMs: number = 32
  ): boolean {
    if (!Number.isFinite(percent) || percent < 0 || percent > 100) {
      return false;
    }
    if (percent === this.lastEmitPercent) {
      return false;
    }
    if (this.lastEmitPercent < 0 || percent >= 100) {
      this.lastEmitPercent = percent;
      this.lastEmitTimeMs = nowMs;
      return true;
    }
    const elapsed: number = nowMs - this.lastEmitTimeMs;
    if (elapsed >= minIntervalMs || (Math.abs(percent - this.lastEmitPercent) >= minDeltaPercent && elapsed >= frameGuardMs)) {
      this.lastEmitPercent = percent;
      this.lastEmitTimeMs = nowMs;
      return true;
    }
    return false;
  }
}

export type ZoomedEdgeTurn = 'none' | 'left' | 'right';

/**
 * 放大看图单指拖拽至左右边缘继续拉动超过阈值后，判定是否切到上一张/下一张视觉页。
 */
export function resolveZoomedEdgeTurn(
  panStartX: number,
  maxX: number,
  offsetX: number,
  offsetY: number,
  msSincePinch: number,
  edgeThresholdVp: number = 72
): ZoomedEdgeTurn {
  if (msSincePinch < 250) {
    return 'none';
  }
  if (Math.abs(offsetX) <= Math.abs(offsetY) * 1.5) {
    return 'none';
  }
  const safeMaxX: number = Math.max(0, maxX);
  const rawX: number = panStartX + offsetX;
  const clampedX: number = Math.max(-safeMaxX, Math.min(safeMaxX, rawX));
  const overscrollX: number = rawX - clampedX;
  if (overscrollX <= -edgeThresholdVp) {
    return 'right';
  }
  if (overscrollX >= edgeThresholdVp) {
    return 'left';
  }
  return 'none';
}

/**
 * 网络切换 / VPN 恢复后，阅读器当前页自动重试防抖与次数上限守卫（避免无网/509/GP 不足时死循环）。
 */
export class ReaderNetworkRecoveryGuard {
  static readonly MAX_AUTO_RETRIES_PER_PAGE: number = 3;
  static readonly PENDING_FAILURE_WINDOW_MS: number = 3000;

  private lastHandledEpoch: number = -1;
  private pendingLoadingEpoch: number = -1;
  private pendingLoadingPage: number = -1;
  private pendingLoadingSetAtMs: number = 0;
  private readonly pageRetryCounts: Map<number, number> = new Map<number, number>();

  static isNonRecoverableError(errorMessage: string): boolean {
    if (errorMessage.length === 0) {
      return false;
    }
    return errorMessage.indexOf('509') >= 0
      || errorMessage.indexOf('Insufficient GP') >= 0
      || errorMessage.indexOf('GP不足') >= 0;
  }

  canRetryInit(epoch: number): boolean {
    if (epoch <= 0 || epoch === this.lastHandledEpoch) {
      return false;
    }
    this.lastHandledEpoch = epoch;
    return true;
  }

  canRetryErrorPage(epoch: number, page: number, errorMessage: string): boolean {
    if (epoch <= 0 || epoch === this.lastHandledEpoch || page < 0) {
      return false;
    }
    if (ReaderNetworkRecoveryGuard.isNonRecoverableError(errorMessage)) {
      return false;
    }
    const count: number = this.pageRetryCounts.get(page) ?? 0;
    if (count >= ReaderNetworkRecoveryGuard.MAX_AUTO_RETRIES_PER_PAGE) {
      return false;
    }
    this.lastHandledEpoch = epoch;
    this.pageRetryCounts.set(page, count + 1);
    this.pendingLoadingEpoch = -1;
    this.pendingLoadingPage = -1;
    this.pendingLoadingSetAtMs = 0;
    return true;
  }

  armPendingForLoading(epoch: number, page: number, nowMs: number = Date.now()): void {
    if (epoch <= 0 || epoch === this.lastHandledEpoch || page < 0) {
      return;
    }
    this.pendingLoadingEpoch = epoch;
    this.pendingLoadingPage = page;
    this.pendingLoadingSetAtMs = nowMs;
  }

  consumePendingRetryOnFailure(page: number, errorMessage: string, nowMs: number = Date.now()): boolean {
    if (this.pendingLoadingEpoch <= 0 || this.pendingLoadingPage !== page) {
      return false;
    }
    const epoch: number = this.pendingLoadingEpoch;
    const elapsed: number = nowMs - this.pendingLoadingSetAtMs;
    this.pendingLoadingEpoch = -1;
    this.pendingLoadingPage = -1;
    this.pendingLoadingSetAtMs = 0;
    if (elapsed > ReaderNetworkRecoveryGuard.PENDING_FAILURE_WINDOW_MS) {
      return false;
    }
    return this.canRetryErrorPage(epoch, page, errorMessage);
  }

  onPageReady(page: number): void {
    this.pageRetryCounts.delete(page);
    if (this.pendingLoadingPage === page) {
      this.pendingLoadingEpoch = -1;
      this.pendingLoadingPage = -1;
      this.pendingLoadingSetAtMs = 0;
    }
  }

  getPageRetryCount(page: number): number {
    return this.pageRetryCounts.get(page) ?? 0;
  }

  reset(): void {
    this.lastHandledEpoch = -1;
    this.pendingLoadingEpoch = -1;
    this.pendingLoadingPage = -1;
    this.pendingLoadingSetAtMs = 0;
    this.pageRetryCounts.clear();
  }
}
