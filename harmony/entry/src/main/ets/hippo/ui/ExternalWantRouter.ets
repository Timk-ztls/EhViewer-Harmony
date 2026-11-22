/*
 * 外部 Want 与快捷方式路由分发器（Stage C Track P5 新增）。
 * 纯 ArkTS，无 @kit.AbilityKit / AppStorage 依赖，供 EntryAbility / Index 与 Node 单测共用。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ACTION_DIR,
  ACTION_EH,
  ACTION_VIEW,
  GalleryActivityKeys,
  KEY_ACTION,
  KEY_FILENAME,
  KEY_PAGE,
  KEY_URI
} from '../ehviewer/ui/GalleryActivity';
import { ReaderRouteRequest } from './reader/ReaderEngineCoordinator';

const DOMAIN: number = 0x0000;
const TAG: string = 'ExternalWantRouter';

export interface WantLike {
  action?: string;
  uri?: string;
  type?: string;
  parameters?: Record<string, Object>;
}

export enum LaunchIntentKind {
  HOME = 0,
  SHORTCUT = 1,
  NOTIFICATION = 2,
  READER_ARCHIVE = 3,
  READER_DIR = 4,
  READER_EH = 5
}

export class ParsedLaunchRequest {
  readonly kind: LaunchIntentKind;
  readonly isColdStart: boolean;
  readonly uri: string | null;
  readonly filename: string | null;
  readonly shortcutAction: string | null;
  readonly gid: number;
  readonly token: string;
  readonly page: number;
  readonly title: string;

  constructor(
    kind: LaunchIntentKind,
    isColdStart: boolean,
    uri: string | null,
    filename: string | null,
    shortcutAction: string | null,
    gid: number,
    token: string,
    page: number,
    title: string
  ) {
    this.kind = kind;
    this.isColdStart = isColdStart;
    this.uri = uri;
    this.filename = filename;
    this.shortcutAction = shortcutAction;
    this.gid = gid;
    this.token = token;
    this.page = page;
    this.title = title;
  }
}

export class ExternalWantRouter {
  static readonly OHOS_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';
  static readonly KEY_SHORTCUT_ACTION: string = 'shortcut_action';
  static readonly KEY_DOWNLOAD_ACTION: string = 'download_action';
  static readonly KEY_ARCHIVER_ACTION: string = 'archiver_action';
  static readonly SHORTCUT_START_ALL: string = 'start_all';
  static readonly SHORTCUT_STOP_ALL: string = 'stop_all';

  private static readParamString(params: Record<string, Object> | undefined, key: string): string | null {
    if (params === undefined) {
      return null;
    }
    const val: Object | undefined = params[key];
    if (typeof val === 'string') {
      const s: string = val as string;
      return s.length > 0 ? s : null;
    }
    return null;
  }

  private static readParamInt(params: Record<string, Object> | undefined, key: string, fallback: number): number {
    if (params === undefined) {
      return fallback;
    }
    const val: Object | undefined = params[key];
    if (typeof val === 'number' && !Number.isNaN(val as number)) {
      return Math.trunc(val as number);
    }
    return fallback;
  }

  static extractDisplayTitleFromUri(uriOrPath: string | null): string {
    return ReaderRouteRequest.extractDisplayName(uriOrPath);
  }

  static parseWant(want: WantLike | null | undefined, isColdStart: boolean): ParsedLaunchRequest {
    if (want === null || want === undefined) {
      return new ParsedLaunchRequest(LaunchIntentKind.HOME, isColdStart, null, null, null, 0, '', 0, '');
    }

    const params: Record<string, Object> | undefined = want.parameters;
    const rawAction: string | null = typeof want.action === 'string' && want.action.length > 0
      ? want.action : null;

    const paramShortcut: string | null = ExternalWantRouter.readParamString(
      params, ExternalWantRouter.KEY_SHORTCUT_ACTION
    );
    const shortcutCandidate: string | null = paramShortcut !== null
      ? paramShortcut
      : (rawAction === ExternalWantRouter.SHORTCUT_START_ALL || rawAction === ExternalWantRouter.SHORTCUT_STOP_ALL
        ? rawAction : null);
    if (shortcutCandidate === ExternalWantRouter.SHORTCUT_START_ALL ||
      shortcutCandidate === ExternalWantRouter.SHORTCUT_STOP_ALL) {
      return new ParsedLaunchRequest(
        LaunchIntentKind.SHORTCUT,
        isColdStart,
        null,
        null,
        shortcutCandidate,
        0,
        '',
        0,
        ''
      );
    }

    const dlAction: string | null = ExternalWantRouter.readParamString(
      params, ExternalWantRouter.KEY_DOWNLOAD_ACTION
    );
    const archAction: string | null = ExternalWantRouter.readParamString(
      params, ExternalWantRouter.KEY_ARCHIVER_ACTION
    );
    if (dlAction !== null || archAction !== null) {
      return new ParsedLaunchRequest(LaunchIntentKind.NOTIFICATION, isColdStart, null, null, null, 0, '', 0, '');
    }

    const uri: string | null = typeof want.uri === 'string' && want.uri.length > 0
      ? want.uri
      : ExternalWantRouter.readParamString(params, KEY_URI);
    const filename: string | null = ExternalWantRouter.readParamString(params, KEY_FILENAME);
    const gid: number = Math.max(0, ExternalWantRouter.readParamInt(params, GalleryActivityKeys.KEY_GID, 0));
    const token: string = ExternalWantRouter.readParamString(params, 'token') ?? '';
    const page: number = Math.max(0, ExternalWantRouter.readParamInt(params, KEY_PAGE, 0));
    const title: string = ExternalWantRouter.readParamString(params, 'title') ?? '';

    if ((rawAction === ACTION_EH || (gid > 0 && token.length > 0)) && gid > 0 && token.length > 0) {
      return new ParsedLaunchRequest(
        LaunchIntentKind.READER_EH,
        isColdStart,
        null,
        null,
        null,
        gid,
        token,
        page,
        title
      );
    }

    if (rawAction === ACTION_DIR && filename !== null) {
      return new ParsedLaunchRequest(
        LaunchIntentKind.READER_DIR,
        isColdStart,
        null,
        filename,
        null,
        0,
        '',
        page,
        title.length > 0 ? title : ExternalWantRouter.extractDisplayTitleFromUri(filename)
      );
    }

    const isViewIntent: boolean = rawAction === ExternalWantRouter.OHOS_ACTION_VIEW_DATA || rawAction === ACTION_VIEW;
    if (uri !== null && (isViewIntent || !uri.startsWith('http://') && !uri.startsWith('https://'))) {
      if (isViewIntent || uri.startsWith('file://') || uri.startsWith('/')) {
        return new ParsedLaunchRequest(
          LaunchIntentKind.READER_ARCHIVE,
          isColdStart,
          uri,
          null,
          null,
          0,
          '',
          page,
          title.length > 0 ? title : ExternalWantRouter.extractDisplayTitleFromUri(uri)
        );
      }
    }

    if (filename !== null) {
      return new ParsedLaunchRequest(
        LaunchIntentKind.READER_DIR,
        isColdStart,
        null,
        filename,
        null,
        0,
        '',
        page,
        title.length > 0 ? title : ExternalWantRouter.extractDisplayTitleFromUri(filename)
      );
    }

    return new ParsedLaunchRequest(LaunchIntentKind.HOME, isColdStart, null, null, null, 0, '', 0, '');
  }

  /** 外部本地归档 / 目录直达阅读器：放行门 2~5，只受门 1 应用锁管控。 */
  static shouldBypassAuthGates(req: ParsedLaunchRequest): boolean {
    return req.kind === LaunchIntentKind.READER_ARCHIVE || req.kind === LaunchIntentKind.READER_DIR;
  }

  /** ShortcutsActivity S1：仅冷启动跳转 DownloadsScene，热启动保持当前页。 */
  static shouldNavigateDownloadsOnShortcut(req: ParsedLaunchRequest): boolean {
    return req.kind === LaunchIntentKind.SHORTCUT && req.isColdStart;
  }

  static toReaderRouteParams(req: ParsedLaunchRequest): Record<string, Object> {
    if (req.kind === LaunchIntentKind.READER_ARCHIVE) {
      const uri: string = req.uri === null ? '' : req.uri;
      const resolvedTitle: string = req.title.length > 0
        ? req.title
        : ExternalWantRouter.extractDisplayTitleFromUri(uri);
      const out: Record<string, Object> = {};
      out[KEY_ACTION] = ACTION_VIEW;
      out[KEY_URI] = uri;
      out['title'] = resolvedTitle;
      out[KEY_PAGE] = req.page;
      return out;
    }
    if (req.kind === LaunchIntentKind.READER_DIR) {
      const fn: string = req.filename === null ? '' : req.filename;
      const resolvedTitle: string = req.title.length > 0
        ? req.title
        : ExternalWantRouter.extractDisplayTitleFromUri(fn);
      const out: Record<string, Object> = {};
      out[KEY_ACTION] = ACTION_DIR;
      out[KEY_FILENAME] = fn;
      out['title'] = resolvedTitle;
      out[KEY_PAGE] = req.page;
      return out;
    }
    if (req.kind === LaunchIntentKind.READER_EH) {
      const out: Record<string, Object> = {};
      out[KEY_ACTION] = ACTION_EH;
      out[GalleryActivityKeys.KEY_GID] = req.gid;
      out['token'] = req.token;
      out['title'] = req.title;
      out[KEY_PAGE] = req.page;
      return out;
    }
    return {};
  }
}

export type LaunchBusListener = (req: ParsedLaunchRequest) => void;

export class PendingLaunchBus {
  private static sInstance: PendingLaunchBus | null = null;
  private pending: ParsedLaunchRequest | null = null;
  private readonly listeners: LaunchBusListener[] = [];

  private constructor() {
  }

  static getInstance(): PendingLaunchBus {
    if (PendingLaunchBus.sInstance === null) {
      PendingLaunchBus.sInstance = new PendingLaunchBus();
    }
    return PendingLaunchBus.sInstance;
  }

  publish(req: ParsedLaunchRequest): void {
    if (req.kind === LaunchIntentKind.HOME || req.kind === LaunchIntentKind.NOTIFICATION) {
      return;
    }
    if (this.listeners.length === 0) {
      this.pending = req;
      hilog.info(DOMAIN, TAG, 'queued pending launch kind=%{public}d', req.kind);
      return;
    }
    this.pending = null;
    const snapshot: LaunchBusListener[] = this.listeners.slice();
    for (let i = 0; i < snapshot.length; i++) {
      snapshot[i](req);
    }
  }

  consumePending(): ParsedLaunchRequest | null {
    const req: ParsedLaunchRequest | null = this.pending;
    this.pending = null;
    return req;
  }

  peekPending(): ParsedLaunchRequest | null {
    return this.pending;
  }

  subscribe(listener: LaunchBusListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: LaunchBusListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  resetForTest(): void {
    this.pending = null;
    this.listeners.length = 0;
  }
}
