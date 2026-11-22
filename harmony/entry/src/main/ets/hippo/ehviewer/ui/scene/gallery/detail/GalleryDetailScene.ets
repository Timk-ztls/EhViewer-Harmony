/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/detail/GalleryDetailScene.java（2029 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/detail/GalleryDetailScene.ets（inventory S0251）
 *
 * ⚠ 分批移植：本文件是 **Part 1 —— 骨架 + 参数 + 数据链路**：
 *   场景身份、onNewArguments(gid/apiUrl)、详情数据持有、加载三态、请求接口化（EhClientLike 模式）。
 *   Part 2 待补：#gdd 七类 key-value 展示、标签组（三套入口）、评分/收藏夹选择。
 *   Part 3 待补：评论（两套入口）、预览集（五套正则回落由 net-parse GalleryDetailParser 覆盖）、
 *               四种非正常页（offensive/pining/unavailable/message）。
 *
 * 依赖：GalleryDetail / GalleryInfo（net-parse 已交付）；EhClient ⏳（用接口 + 未接线实现兜底）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../../../../scene/SceneTypes';
import { SceneFragment } from '../../../../../scene/SceneFragment';
import { Announcer } from '../../../../../scene/Announcer';
import { GalleryDetail } from '../../../../client/data/GalleryDetail';
import { GalleryTagGroup } from '../../../../client/data/GalleryTagGroup';
import { GalleryCommentList } from '../../../../client/data/GalleryCommentList';
import { PreviewSet } from '../../../../client/data/PreviewSet';
import { GalleryInfo } from '../../../../client/data/GalleryInfo';
import { ListUrlBuilder } from '../../../../client/data/ListUrlBuilder';
import { EhUrl } from '../../../../client/EhUrl';
import { EhUtils } from '../../../../client/EhUtils';

/** 详情请求接口（EhClient 未交付前用默认 warn 实现，同 GalleryListScene Part 3 模式） */
export interface DetailClientLike {
  getGalleryDetail(url: string): Promise<GalleryDetail | null>;
}

/** Result returned by `DetailActionClientLike.rateGallery`. */
export class GalleryRateOutcome {
  rating: number = 0;
  ratingCount: number = 0;
  ratingCls: string = '';
}

/** Optional interactive actions (favorites / rating / download / local status) for `GalleryDetailScene`. */
export interface DetailActionClientLike {
  addToFavorite(galleryInfo: GalleryInfo, slot: number, note: string): Promise<boolean>;
  removeFromFavorite(galleryInfo: GalleryInfo): Promise<boolean>;
  rateGallery(detail: GalleryDetail, rating: number): Promise<GalleryRateOutcome | null>;
  downloadGallery(galleryInfo: GalleryInfo): Promise<boolean>;
  isDownloaded(gid: number): Promise<boolean>;
  isLocalFavorited(gid: number): Promise<boolean>;
}

export class UnavailableDetailClient implements DetailClientLike {
  async getGalleryDetail(url: string): Promise<GalleryDetail | null> {
    console.warn('[ui-scene] EhClient 未接线：getGalleryDetail(url=' + url + ')');
    return null;
  }
}

/** 上游 State */
export class GalleryDetailState {
  static readonly NORMAL: number = 0;
  static readonly LOADING: number = 1;
  static readonly ERROR: number = 2;
}

export abstract class GalleryDetailScene extends SceneFragment {
  // 上游 KEY_*（详情页启动参数）
  static readonly KEY_API_URL: string = 'api_url';
  static readonly KEY_GID: string = 'gid';
  static readonly KEY_GALLERY_INFO: string = 'gallery_info';
  static readonly KEY_PREVIEW_PAGE: string = 'preview_page';

  protected apiUrl: string = '';
  protected gid: number = -1;
  /** 列表页传进来的概要（上游 getArguments().getParcelable(KEY_GALLERY_INFO)） */
  protected galleryInfo: GalleryInfo | null = null;
  protected previewPage: number = 0;

  /** 详情模型（net-parse GalleryDetail，字段直接消费） */
  protected detail: GalleryDetail | null = null;
  protected state: number = GalleryDetailState.NORMAL;
  protected errorMessage: string = '';
  protected requestSeq: number = 0;
  protected client: DetailClientLike = new UnavailableDetailClient();
  protected actionClient: DetailActionClientLike | null = null;
  protected favoritedLocal: boolean = false;
  protected downloaded: boolean = false;
  protected actionBusy: boolean = false;
  private onStateChangedListener: (() => void) | null = null;

  getSceneName(): string {
    return 'GalleryDetailScene';
  }

  getClient(): DetailClientLike {
    return this.client;
  }

  setDetailClient(client: DetailClientLike): void {
    this.client = client;
  }

  setDetailActionClient(client: DetailActionClientLike | null): void {
    this.actionClient = client;
  }

  isDownloaded(): boolean {
    return this.downloaded;
  }

  isLocalFavorited(): boolean {
    return this.favoritedLocal;
  }

  isFavorited(): boolean {
    return this.favoritedLocal || (this.detail !== null && this.detail.isFavorited);
  }

  isActionBusy(): boolean {
    return this.actionBusy;
  }

  setOnStateChangedListener(fn: (() => void) | null): void {
    this.onStateChangedListener = fn;
  }

  protected notifyStateChanged(): void {
    const fn: (() => void) | null = this.onStateChangedListener;
    if (fn !== null) {
      fn();
    }
  }

  getGid(): number {
    return this.gid;
  }

  getApiUrl(): string {
    return this.apiUrl;
  }

  getGalleryInfo(): GalleryInfo | null {
    return this.galleryInfo;
  }

  getPreviewPage(): number {
    return this.previewPage;
  }

  getErrorMessage(): string {
    return this.errorMessage;
  }

  onNewArguments(args: SceneArgs): void {
    const gi: Object | undefined = args.get(GalleryDetailScene.KEY_GALLERY_INFO);
    if (gi !== undefined && gi !== null && gi instanceof GalleryInfo) {
      this.galleryInfo = gi as GalleryInfo;
      if (this.gid <= 0 && (gi as GalleryInfo).gid > 0) {
        this.gid = (gi as GalleryInfo).gid;
      }
    }
    const u: Object | undefined = args.get(GalleryDetailScene.KEY_API_URL);
    if (u !== undefined && typeof u === 'string') {
      this.apiUrl = u as string;
    }
    const g: Object | undefined = args.get(GalleryDetailScene.KEY_GID);
    if (g !== undefined && typeof g === 'number') {
      this.gid = g as number;
    }
    const p: Object | undefined = args.get(GalleryDetailScene.KEY_PREVIEW_PAGE);
    if (p !== undefined && typeof p === 'number') {
      this.previewPage = p as number;
    }
    if (this.apiUrl.length === 0 && this.gid > 0 && this.galleryInfo !== null && this.galleryInfo.token.length > 0) {
      this.apiUrl = EhUrl.getGalleryDetailUrl(this.gid, this.galleryInfo.token, 0, false);
    }
    this.ensureLoaded();
    void this.refreshStatusFlags();
  }

  /** Refresh local favorite / download badges from injected actionClient. */
  async refreshStatusFlags(): Promise<void> {
    const client: DetailActionClientLike | null = this.actionClient;
    const targetGid: number = this.detail !== null ? this.detail.gid : this.gid;
    if (client === null || targetGid <= 0) {
      return;
    }
    try {
      const results: [boolean, boolean] = await Promise.all([
        client.isDownloaded(targetGid),
        client.isLocalFavorited(targetGid)
      ]);
      this.downloaded = results[0];
      this.favoritedLocal = results[1];
      this.notifyStateChanged();
    } catch (_e) {
      // ignore probe failure
    }
  }

  private resolveActionInfo(): GalleryInfo | null {
    if (this.detail !== null) {
      return this.detail;
    }
    return this.galleryInfo;
  }

  async addToFavorite(slot: number, note: string = ''): Promise<boolean> {
    const client: DetailActionClientLike | null = this.actionClient;
    const info: GalleryInfo | null = this.resolveActionInfo();
    if (client === null || info === null || this.actionBusy) {
      return false;
    }
    this.actionBusy = true;
    this.notifyStateChanged();
    try {
      const ok: boolean = await client.addToFavorite(info, slot, note);
      if (ok) {
        if (slot === -2) {
          this.favoritedLocal = true;
        }
        if (this.detail !== null) {
          this.detail.isFavorited = true;
          this.detail.favoriteSlot = slot;
        }
        info.favoriteSlot = slot;
      }
      return ok;
    } finally {
      this.actionBusy = false;
      this.notifyStateChanged();
    }
  }

  async removeFromFavorite(): Promise<boolean> {
    const client: DetailActionClientLike | null = this.actionClient;
    const info: GalleryInfo | null = this.resolveActionInfo();
    if (client === null || info === null || this.actionBusy) {
      return false;
    }
    this.actionBusy = true;
    this.notifyStateChanged();
    try {
      const ok: boolean = await client.removeFromFavorite(info);
      if (ok) {
        this.favoritedLocal = false;
        if (this.detail !== null) {
          this.detail.isFavorited = false;
          this.detail.favoriteSlot = -2;
          this.detail.favoriteName = null;
        }
        info.favoriteSlot = -2;
        info.favoriteName = null;
      }
      return ok;
    } finally {
      this.actionBusy = false;
      this.notifyStateChanged();
    }
  }

  async rateGallery(rating: number): Promise<GalleryRateOutcome | null> {
    const client: DetailActionClientLike | null = this.actionClient;
    const d: GalleryDetail | null = this.detail;
    if (client === null || d === null || this.actionBusy) {
      return null;
    }
    this.actionBusy = true;
    this.notifyStateChanged();
    try {
      const res: GalleryRateOutcome | null = await client.rateGallery(d, rating);
      if (res !== null) {
        d.rating = res.rating;
        d.ratingCount = res.ratingCount;
        d.rated = true;
      }
      return res;
    } finally {
      this.actionBusy = false;
      this.notifyStateChanged();
    }
  }

  async downloadGallery(): Promise<boolean> {
    const client: DetailActionClientLike | null = this.actionClient;
    const info: GalleryInfo | null = this.resolveActionInfo();
    if (client === null || info === null || this.actionBusy) {
      return false;
    }
    this.actionBusy = true;
    this.notifyStateChanged();
    try {
      const ok: boolean = await client.downloadGallery(info);
      if (ok) {
        this.downloaded = true;
      }
      return ok;
    } finally {
      this.actionBusy = false;
      this.notifyStateChanged();
    }
  }

  openGalleryInfo(): void {
    const d: GalleryDetail | null = this.detail;
    if (d === null) {
      return;
    }
    const args: SceneArgs = new Map<string, Object>();
    args.set('gallery_detail', d);
    this.startScene(new Announcer('GalleryInfoScene').setArgs(args));
  }

  openComments(): void {
    const targetGid: number = this.detail !== null ? this.detail.gid : this.gid;
    const token: string = this.detail !== null
      ? this.detail.token
      : (this.galleryInfo !== null ? this.galleryInfo.token : '');
    const targetUrl: string = this.apiUrl.length > 0
      ? this.apiUrl
      : (targetGid > 0 && token.length > 0 ? EhUrl.getGalleryDetailUrl(targetGid, token, 0, false) : '');
    if (targetUrl.length === 0) {
      return;
    }
    const args: SceneArgs = new Map<string, Object>();
    args.set('api_url', targetUrl);
    if (targetGid > 0) {
      args.set('gid', targetGid);
    }
    if (token.length > 0) {
      args.set('token', token);
    }
    if (this.detail !== null) {
      args.set('api_uid', this.detail.apiUid);
      if (this.detail.apiKey !== null) {
        args.set('api_key', this.detail.apiKey);
      }
      if (this.detail.comments !== null) {
        args.set('comments', this.detail.comments);
      }
    }
    this.startScene(new Announcer('GalleryCommentsScene').setArgs(args));
  }

  openTagSearch(namespace: string, rawTag: string): void {
    // Tags may include vote suffix or weight metadata; keep the bare tag name before ':' if needed.
    const clean: string = rawTag.trim();
    if (clean.length === 0) {
      return;
    }
    const tagQuery: string = namespace.length > 0 && namespace !== 'misc'
      ? `${namespace}:${clean}`
      : clean;
    const ub: ListUrlBuilder = new ListUrlBuilder();
    ub.setMode(ListUrlBuilder.MODE_TAG);
    ub.setKeyword(tagQuery);
    const listUrl: string = ub.build();
    const args: SceneArgs = new Map<string, Object>();
    args.set('action', 'action_list_url_builder');
    args.set('list_url_builder', listUrl);
    args.set('search_keyword', ListUrlBuilder.wrapTagKeyword(tagQuery));
    this.startScene(new Announcer('GalleryListScene').setArgs(args));
  }

  getState(): number {
    return this.state;
  }

  getDetail(): GalleryDetail | null {
    return this.detail;
  }

  ensureLoaded(): void {
    if (this.detail === null && this.state !== GalleryDetailState.LOADING && this.apiUrl.length > 0) {
      this.loadDetail();
    }
  }

  reloadDetail(): void {
    if (this.apiUrl.length === 0 && this.gid > 0 && this.galleryInfo !== null && this.galleryInfo.token.length > 0) {
      this.apiUrl = EhUrl.getGalleryDetailUrl(this.gid, this.galleryInfo.token, 0, false);
    }
    this.loadDetail();
  }

  /** 加载详情：异步，不在 aboutToAppear 里同步 IO（D-012） */
  protected loadDetail(): void {
    const seq: number = ++this.requestSeq;
    if (this.apiUrl.length === 0) {
      this.errorMessage = 'Gallery detail URL is empty';
      this.state = GalleryDetailState.ERROR;
      this.notifyStateChanged();
      return;
    }
    this.errorMessage = '';
    this.state = GalleryDetailState.LOADING;
    this.notifyStateChanged();
    this.client.getGalleryDetail(this.apiUrl).then((d: GalleryDetail | null) => {
      if (seq !== this.requestSeq) {
        return;
      }
      if (d === null) {
        this.errorMessage = 'Failed to load gallery detail';
        this.state = GalleryDetailState.ERROR;
        this.notifyStateChanged();
        return;
      }
      this.detail = d;
      if (d.gid > 0) {
        this.gid = d.gid;
      }
      this.errorMessage = '';
      this.state = GalleryDetailState.NORMAL;
      this.onDetailLoaded();
      this.notifyStateChanged();
    }).catch((e: Error) => {
      if (seq !== this.requestSeq) {
        return;
      }
      const msg: string = (e.message !== undefined && e.message !== null && e.message.length > 0)
        ? e.message : String(e);
      hilog.error(0x0000, 'GalleryDetailScene', 'loadDetail failed: err=%{public}s', msg);
      this.errorMessage = msg;
      this.state = GalleryDetailState.ERROR;
      this.notifyStateChanged();
    });
  }

  /** 打开缩略图预览页（GalleryPreviewsScene）。 */
  openPreviews(previewPageIndex?: number): void {
    const d: GalleryDetail | null = this.detail;
    const gi: GalleryInfo | null = this.galleryInfo;
    const gid: number = d !== null && d.gid > 0 ? d.gid : this.gid;
    const token: string = d !== null && d.token.length > 0
      ? d.token : (gi !== null ? gi.token : '');
    const titleSource: GalleryInfo | null = d !== null ? d : gi;
    const title: string = titleSource !== null
      ? (EhUtils.getSuitableTitle(titleSource) ?? titleSource.title) : '';
    const previewPages: number = this.getPreviewPages();
    const pageIndex: number = previewPageIndex !== undefined && previewPageIndex >= 0
      ? Math.trunc(previewPageIndex) : 0;

    const args: SceneArgs = new Map<string, Object>();
    args.set('gid', gid);
    args.set('token', token);
    args.set('title', title);
    args.set('previewPages', previewPages);
    args.set('pageIndex', pageIndex);
    args.set('apiUrl', this.apiUrl);
    if (pageIndex === 0) {
      const initialPs: PreviewSet | null = this.getPreviewSet();
      if (initialPs !== null) {
        args.set('initialPreviewSet', initialPs);
      }
    }
    if (d !== null) {
      args.set('pages', d.pages);
      args.set('gallery_info', d);
    } else if (gi !== null) {
      args.set('pages', gi.pages);
      args.set('gallery_info', gi);
    }
    this.startScene(new Announcer('GalleryPreviewsScene').setArgs(args));
  }

  /** Part 2/3：详情到位后分派到各自渲染段（本轮为空实现） */
  protected onDetailLoaded(): void {
  }

  // ---------------- Part 2a：#gdd 七类 key-value 展示行 ----------------

  /**
   * 构建 #gdd 的展示行（上游详情页 header 的 key-value 区）。
   * 只消费 **已核实存在** 的模型字段：
   *   GalleryDetail.parent / visible / language / isFavorited（`GalleryDetail.ets` 实测有）
   *   GalleryInfo.posted（`GalleryInfo.ets` 实测有）
   * 剩余两类（File Size / Length）字段名尚未在模型中确认，本轮不编造，留待核对后补。
   */
  buildGddRows(): GddRow[] {
    const rows: GddRow[] = [];
    const d: GalleryDetail | null = this.detail;
    const gi: GalleryInfo | null = this.galleryInfo;
    const postedVal: string = (d !== null && d.posted.length > 0)
      ? d.posted
      : (gi !== null ? gi.posted : '');
    if (postedVal.length > 0) {
      rows.push(new GddRow('posted', postedVal));
    }
    if (d === null) {
      return rows;
    }
    // 上游信息区是 5 个 TextView：language / pages / size / posted / favored_times
    // （favored_times 的模型字段名尚未核实，暂不生成，避免编造 —— 同前两次教训）
    if (d.language !== null && d.language.length > 0) {
      rows.push(new GddRow('language', d.language));
    }
    if (d.pages > 0) {
      rows.push(new GddRow('length', d.pages.toString() + 'P'));
    }
    if (d.size !== null && d.size.length > 0) {
      rows.push(new GddRow('fileSize', d.size));
    }
    return rows;
  }

  /**
   * 标签组（上游三套入口 Document / Elements / 正则由 net-parse 解析后落在模型里）。
   * 返回 [] 而非 null：调用点是 ForEach，null 会崩。
   */
  getTagGroups(): GalleryTagGroup[] {
    const d: GalleryDetail | null = this.detail;
    if (d === null || d.tags === null) {
      return [];
    }
    return d.tags;
  }

  // ---------------- Part 3：评论 / 预览集 / 非正常页分派 ----------------
  static readonly ABNORMAL_NONE: number = 0;
  static readonly ABNORMAL_OFFENSIVE: number = 1;
  static readonly ABNORMAL_PINING: number = 2;
  static readonly ABNORMAL_UNAVAILABLE: number = 3;
  static readonly ABNORMAL_MESSAGE: number = 4;

  protected abnormalType: number = 0;
  protected abnormalMessage: string = '';

  getAbnormalType(): number { return this.abnormalType; }
  getAbnormalMessage(): string { return this.abnormalMessage; }

  setAbnormal(type: number, message: string): void {
    this.abnormalType = type;
    this.abnormalMessage = message;
  }

  isAbnormal(): boolean { return this.abnormalType !== 0; }

  /** 评论：模型字段 comments: GalleryCommentList | null（扁平 comments + hasMore） */
  getComments(): GalleryCommentList | null {
    const d: GalleryDetail | null = this.detail;
    return d === null ? null : d.comments;
  }

  /** 预览页总数：网页解析 vs SpiderInfo 本地记录，取较大者 */
  getPreviewPages(): number {
    const d: GalleryDetail | null = this.detail;
    if (d === null) { return 0; }
    return d.previewPages > d.SpiderInfoPreviewPages ? d.previewPages : d.SpiderInfoPreviewPages;
  }

  /** 预览集：网页解析优先，回落 SpiderInfo */
  getPreviewSet(): PreviewSet | null {
    const d: GalleryDetail | null = this.detail;
    if (d === null) { return null; }
    if (d.previewSet !== null) { return d.previewSet; }
    return d.SpiderInfoPreviewSet;
  }

  hasTorrent(): boolean {
    const d: GalleryDetail | null = this.detail;
    return d !== null && d.torrentUrl !== null && d.torrentUrl.length > 0;
  }

  getTorrentCount(): number {
    const d: GalleryDetail | null = this.detail;
    return d === null ? 0 : d.torrentCount;
  }
}
/** #gdd 的一行 key-value */
export class GddRow {
  readonly key: string;
  readonly value: string;
  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

/** 跳转到 `pages/GalleryReaderPage` 的强类型路由参数（避免无类型对象字面量）。 */
export class GalleryReaderRouteParams {
  gid: number = 0;
  token: string = '';
  page: number = 0;
  pages: number = 0;
  title: string = '';
  apiUrl: string = '';

  constructor(gid: number, token: string, page: number, pages: number, title: string, apiUrl: string) {
    this.gid = gid;
    this.token = token;
    this.page = page;
    this.pages = pages;
    this.title = title;
    this.apiUrl = apiUrl;
  }
}
