/*
 * `GalleryDetailScene` 的渲染层：Material 全出血头部、跨界操作卡、元数据区、8 项横向动作栏、
 * 评分星条、标签组、评论摘要（最多 2 条）、3 列预览缩略图网格与 Material 居中弹窗。
 */
import { UIContext } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CategoryColors,
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { EhApplication } from '../../ehviewer/EhApplication';
import { EhDB } from '../../ehviewer/EhDB';
import { EhEngine, HttpCaller } from '../../ehviewer/client/EhEngine';
import { EhCacheKeyFactory } from '../../ehviewer/client/EhCacheKeyFactory';
import { EhFilter } from '../../ehviewer/client/EhFilter';
import { EhTagDatabase } from '../../ehviewer/client/EhTagDatabase';
import { EhTagDatabaseUpdater } from '../../ehviewer/client/EhTagDatabaseUpdater';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { EhUtils } from '../../ehviewer/client/EhUtils';
import { Settings } from '../../ehviewer/Settings';
import { GetText } from '../../ehviewer/GetText';
import { DownloadInfo } from '../../ehviewer/dao/DownloadInfo';
import { Filter } from '../../ehviewer/dao/Filter';
import { DownloadManager } from '../../ehviewer/download/DownloadManager';
import { AppConfig } from '../../ehviewer/AppConfig';
import { TorrentDownloadMessage } from '../../ehviewer/client/data/TorrentDownloadMessage';
import {
  DownloadTorrentManager,
  TorrentDownloadHandler
} from '../../ehviewer/download/DownloadTorrentManager';
import { PageRoutes } from '../PageRoutes';
import {
  ArchiverDownloader,
  ArchiverDownloaderListener,
  ArchiverProgress
} from '../../ehviewer/download/ArchiverDownloader';
import { ArchiverDownloadCompleter } from '../../ehviewer/download/ArchiverDownloadCompleter';
import { ArchiverProgressMath } from '../../ehviewer/widget/ArchiverDownloadProgress';
import { FileUtils } from '../../lib/yorozuya/FileUtils';
import { SpiderQueen } from '../../ehviewer/spider/SpiderQueen';
import { ArchiverData } from '../../ehviewer/client/data/ArchiverData';
import { GalleryDetail } from '../../ehviewer/client/data/GalleryDetail';
import { GalleryInfo } from '../../ehviewer/client/data/GalleryInfo';
import { GalleryTagGroup } from '../../ehviewer/client/data/GalleryTagGroup';
import { GalleryComment } from '../../ehviewer/client/data/GalleryComment';
import { GalleryCommentList } from '../../ehviewer/client/data/GalleryCommentList';
import { ListUrlBuilder } from '../../ehviewer/client/data/ListUrlBuilder';
import { PreviewSet } from '../../ehviewer/client/data/PreviewSet';
import { TorrentInfo } from '../../ehviewer/client/data/TorrentInfo';
import { ArchiveEntry } from '../../ehviewer/client/parser/ArchiveParser';
import { NoHAtHClientException } from '../../ehviewer/client/exception/MarkerExceptions';
import {
  GalleryDetailScene,
  GalleryDetailState,
  DetailClientLike,
  UnavailableDetailClient,
  GalleryReaderRouteParams,
  GalleryRateOutcome
} from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailScene';
import { GalleryDetailSceneConcrete } from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailSceneConcrete';
import {
  GalleryDetailBind,
  MAX_SHOW_COMMENTS,
  MoreState,
  TagGroupView,
  stripTagNamespace
} from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailBind';
import { Announcer } from '../../scene/Announcer';
import { SceneArgs } from '../../scene/SceneTypes';
import { OkHttpCallerAdapter } from '../../AppWiring';
import { GalleryListClient } from '../GalleryListClient';
import { LoadImageView, LoadImageController } from '../../widget/LoadImageView';
import { ReadableTime } from '../../util/ReadableTime';
import { SceneGalleryDetailLayout } from '../layout/scene_gallery_detail';
import { GalleryDetailHeaderLayout } from '../layout/gallery_detail_header';
import { GalleryDetailInfoLayout } from '../layout/gallery_detail_info';
import { GalleryDetailActionsLayout } from '../layout/gallery_detail_actions';
import { GalleryDetailTagsLayout } from '../layout/gallery_detail_tags';
import { GalleryDetailCommentsLayout } from '../layout/gallery_detail_comments';
import { GalleryDetailPreviewsLayout } from '../layout/gallery_detail_previews';
import { APP_SHOW_JPN_TITLE_STORAGE_KEY } from '../ThemeSystemBar';
import { VStarX16 } from '../drawable/v_star_x16';
import { VStarHalfX16 } from '../drawable/v_star_half_x16';
import { VStarOutlineX16 } from '../drawable/v_star_outline_x16';
import { VPauseX24 } from '../drawable/v_pause_x24';
import { VPlayX24 } from '../drawable/v_play_x24';
import { VCloseDarkX24 } from '../drawable/v_close_dark_x24';
import { ArchiverProgressWidgetLayout } from '../layout/widget_archiver_progress';

const DOMAIN: number = 0x0000;
const TAG: string = 'GalleryDetailSceneView';

class PreviewTileRow {
  readonly rowIndex: number;
  readonly tiles: PreviewTileItem[];

  constructor(rowIndex: number, tiles: PreviewTileItem[]) {
    this.rowIndex = rowIndex;
    this.tiles = tiles;
  }
}

export { stripTagNamespace } from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailBind';

class DetailTorrentDownloadHandler implements TorrentDownloadHandler {
  private readonly callback: (message: TorrentDownloadMessage) => void;

  constructor(callback: (message: TorrentDownloadMessage) => void) {
    this.callback = callback;
  }

  onMessage(message: TorrentDownloadMessage): void {
    this.callback(message);
  }
}

/** 跳转到 `pages/GalleryReaderPage`，详情页与完整预览页共用。 */
export function pushGalleryReaderPage(
  uiContext: UIContext,
  params: GalleryReaderRouteParams,
  logTag: string
): void {
  if (params.gid <= 0 || params.token.length === 0) {
    hilog.warn(DOMAIN, logTag, 'skip pushUrl GalleryReaderPage: invalid gid=%{public}d tokenLen=%{public}d',
      params.gid, params.token.length);
    return;
  }
  uiContext.getRouter().pushUrl({
    url: 'pages/GalleryReaderPage',
    params: params
  }).catch((e: Error): void => {
    hilog.error(DOMAIN, logTag, 'pushUrl GalleryReaderPage failed: %{public}s', e.message);
  });
}

class EhEngineDetailClient implements DetailClientLike {
  private readonly caller: HttpCaller;

  constructor(caller: HttpCaller) {
    this.caller = caller;
  }

  async getGalleryDetail(url: string): Promise<GalleryDetail | null> {
    return EhEngine.getGalleryDetail(null, this.caller, url);
  }
}

class PreviewTileItem {
  readonly index: number;
  readonly position: number;
  readonly pageLabel: string;

  constructor(index: number, position: number) {
    this.index = index;
    this.position = position;
    this.pageLabel = String(position + 1);
  }
}

/** 可复用的预览图单元格（详情页与完整预览页共用，`PreviewSet.load` 自动处理精灵图裁剪）。 */
@Component
export struct PreviewTileView {
  @Prop gid: number = 0;
  @Prop index: number = 0;
  @Prop pageLabel: string = '';
  @Prop tileHeight: number = 110;
  @Prop themeId: number = -1;
  @Prop @Watch('onEpochChanged') loadEpoch: number = 0;
  previewSet: PreviewSet | null = null;
  onTileClick: () => void = (): void => {};

  private controller: LoadImageController = new LoadImageController();

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    this.controller.setRetryType(LoadImageController.RETRY_TYPE_CLICK);
    this.loadPreview();
  }

  private onEpochChanged(): void {
    this.loadPreview();
  }

  private loadPreview(): void {
    const ps: PreviewSet | null = this.previewSet;
    if (ps !== null && this.index >= 0 && this.index < ps.size()) {
      ps.load(this.controller, this.gid, this.index);
    }
  }

  build() {
    Column({ space: ThemeDimens.SPACING_XS }) {
      Stack() {
        LoadImageView({
          controller: this.controller,
          imageFit: ImageFit.Contain
        })
      }
      .width('100%')
      .height(this.tileHeight)
      .backgroundColor(this.palette().thumbPlaceholder)
      .borderRadius(ThemeRadius.CARD)
      .clip(true)

      Text(this.pageLabel)
        .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
        .fontColor(this.palette().textSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width('100%')
    .padding(2)
    .onClick((): void => {
      this.onTileClick();
    })
  }
}

class DetailArchiverListener implements ArchiverDownloaderListener {
  private readonly onProgressCb: (gid: number, downloaded: number, total: number, speed: number, paused: boolean) => void;
  private readonly onSuccessCb: (gid: number, taskId: number, zipPath: string) => void;
  private readonly onFailureCb: (gid: number, taskId: number, e: Error) => void;
  private readonly onCancelCb: (gid: number, taskId: number) => void;

  constructor(
    onProgressCb: (gid: number, downloaded: number, total: number, speed: number, paused: boolean) => void,
    onSuccessCb: (gid: number, taskId: number, zipPath: string) => void,
    onFailureCb: (gid: number, taskId: number, e: Error) => void,
    onCancelCb: (gid: number, taskId: number) => void
  ) {
    this.onProgressCb = onProgressCb;
    this.onSuccessCb = onSuccessCb;
    this.onFailureCb = onFailureCb;
    this.onCancelCb = onCancelCb;
  }

  onProgress(gid: number, downloaded: number, total: number, speed: number, paused: boolean): void {
    this.onProgressCb(gid, downloaded, total, speed, paused);
  }

  onSuccess(gid: number, taskId: number, zipPath: string): void {
    this.onSuccessCb(gid, taskId, zipPath);
  }

  onFailure(gid: number, taskId: number, e: Error): void {
    this.onFailureCb(gid, taskId, e);
  }

  onCancel(gid: number, taskId: number): void {
    this.onCancelCb(gid, taskId);
  }
}

@Component
export struct GalleryDetailSceneView {
  scene: GalleryDetailSceneConcrete | null = null;

  @Prop themeId: number = -1;
  @StorageLink(APP_SHOW_JPN_TITLE_STORAGE_KEY) @Watch('onShowJpnTitleChanged') showJpnTitlePref: boolean =
    Settings.getShowJpnTitle();
  @State state: number = GalleryDetailState.NORMAL;
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State gid: number = 0;
  @State token: string = '';
  @State displayTitle: string = '';
  @State uploader: string = '';
  @State categoryValue: number = EhUtils.UNKNOWN;
  @State categoryLabel: string = '';
  @State categoryColor: string = CategoryColors.UNKNOWN;
  @State ratingValue: number = 0;
  @State ratingCount: number = 0;
  @State ratingText: string = '';
  @State totalPages: number = 0;
  @State readStartPage: number = -1;
  @State languageText: string = '';
  @State fileSizeText: string = '';
  @State postedText: string = '';
  @State favoriteCount: number = 0;
  @State favoredTimesText: string = '';
  @State torrentCount: number = 0;
  @State torrentUrl: string = '';
  @State torrentLabel: string = '';
  @State favoriteLabel: string = '';
  @State hasNewVersion: boolean = false;
  @State previewPages: number = 0;
  @State tagGroupViews: TagGroupView[] = [];
  @State previewTiles: PreviewTileItem[] = [];
  @State previewRows: PreviewTileRow[] = [];
  @State comments: GalleryComment[] = [];
  @State totalCommentCount: number = 0;
  @State hasMoreComments: boolean = false;
  @State detailLoaded: boolean = false;
  @State previewEpoch: number = 0;
  @State downloaded: boolean = false;
  @State downloadState: number = DownloadInfo.STATE_INVALID;
  @State favorited: boolean = false;
  @State rated: boolean = false;
  @State actionBusy: boolean = false;
  @State showGalleryRating: boolean = true;
  @State showGalleryComment: boolean = true;

  @State showOverflowMenu: boolean = false;
  @State showCoverDialog: boolean = false;
  @State showFavPicker: boolean = false;
  @State showRatePicker: boolean = false;
  @State ratePickerValue: number = 5.0;
  @State showRemoveDownloadDialog: boolean = false;
  @State showFilterUploaderDialog: boolean = false;
  @State selectedTagForDialog: string = '';

  @State showTorrentDialog: boolean = false;
  @State torrentLoading: boolean = false;
  @State torrentList: TorrentInfo[] = [];
  @State torrentError: string = '';
  @State showTorrentActionDialog: boolean = false;
  @State downloadedTorrentPath: string = '';
  @State downloadedTorrentName: string = '';

  @State showArchiveDialog: boolean = false;
  @State archiveLoading: boolean = false;
  @State archiveParamOr: string = '';
  @State archiveList: ArchiveEntry[] = [];
  @State archiveError: string = '';

  @State showArchiverDialog: boolean = false;
  @State archiverLoading: boolean = false;
  @State archiverData: ArchiverData | null = null;
  @State archiverError: string = '';

  @State archiverTaskActive: boolean = false;
  @State archiverDownloaded: number = 0;
  @State archiverTotal: number = 0;
  @State archiverSpeed: number = 0;
  @State archiverPaused: boolean = false;
  @State archiverImporting: boolean = false;
  @State showCancelArchiverDialog: boolean = false;

  @State rememberFavSlot: boolean = false;
  @State favSlotNames: string[] = [];

  private coverController: LoadImageController = new LoadImageController();
  private fullCoverController: LoadImageController = new LoadImageController();
  private loadedCoverUrl: string = '';
  private currentPreviewSet: PreviewSet | null = null;
  private archiverListener: ArchiverDownloaderListener | null = null;
  private archiverRefreshTimers: number[] = [];

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private buildPreviewRows(tiles: PreviewTileItem[]): PreviewTileRow[] {
    const rows: PreviewTileRow[] = [];
    for (let i = 0; i < tiles.length; i += 3) {
      rows.push(new PreviewTileRow(Math.floor(i / 3), tiles.slice(i, i + 3)));
    }
    return rows;
  }

  private readonly onTagDbUpdated: () => void = (): void => {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s !== null) {
      this.rebuildTagGroups(s.getTagGroups());
    }
  };

  private rebuildTagGroups(rawGroups: GalleryTagGroup[]): void {
    this.tagGroupViews = GalleryDetailBind.buildTagGroups(
      rawGroups,
      (key: string): string | null => EhTagDatabaseUpdater.translateKey(key),
      (groupName: string): string | null => EhTagDatabase.namespaceToPrefix(groupName)
    );
  }

  aboutToAppear(): void {
    EhTagDatabaseUpdater.addUpdateListener(this.onTagDbUpdated);
    if (EhTagDatabaseUpdater.isTranslationEnabled() &&
      !EhTagDatabaseUpdater.isDatabaseReady() &&
      !EhTagDatabaseUpdater.isUpdating()) {
      void EhTagDatabaseUpdater.update(false);
    }
    this.favSlotNames = Settings.getFavCat();
    this.showGalleryRating = Settings.getShowGalleryRating();
    this.showGalleryComment = Settings.getShowGalleryComment();
    if (!ReadableTime.isInitialized()) {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      if (ctx !== undefined) {
        ReadableTime.initialize(ctx);
      }
    }
    this.coverController.setRetryType(LoadImageController.RETRY_TYPE_CLICK);
    this.fullCoverController.setRetryType(LoadImageController.RETRY_TYPE_CLICK);

    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      this.state = GalleryDetailState.ERROR;
      this.errorMessage = 'GalleryDetailScene is null';
      return;
    }
    s.setOnStateChangedListener((): void => {
      this.syncFromScene();
    });

    if (s.getClient() instanceof UnavailableDetailClient) {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      const okClient = EhApplication.getOkHttpClient(ctx === undefined ? null : ctx);
      s.setDetailClient(new EhEngineDetailClient(new OkHttpCallerAdapter(okClient)));
      if (s.getDetail() === null) {
        s.reloadDetail();
      }
    } else if (s.getState() === GalleryDetailState.NORMAL && s.getDetail() === null) {
      s.ensureLoaded();
    }
    void s.refreshStatusFlags();
    void this.refreshDownloadState();
    this.syncFromScene();
    this.attachArchiverProgress();
  }

  aboutToDisappear(): void {
    EhTagDatabaseUpdater.removeUpdateListener(this.onTagDbUpdated);
    if (this.scene !== null) {
      this.scene.setOnStateChangedListener(null);
    }
    this.detachArchiverProgress();
  }

  private attachArchiverProgress(): void {
    this.detachArchiverProgress();
    const listener: ArchiverDownloaderListener = new DetailArchiverListener(
      (gid: number, downloaded: number, total: number, speed: number, paused: boolean): void => {
        if (gid !== this.gid || this.gid <= 0) {
          return;
        }
        this.archiverTaskActive = true;
        this.archiverDownloaded = downloaded;
        this.archiverTotal = total;
        this.archiverSpeed = speed;
        this.archiverPaused = paused;
        this.syncArchiverImportingState();
      },
      (gid: number, _taskId: number, _zipPath: string): void => {
        if (gid !== this.gid || this.gid <= 0) {
          return;
        }
        this.archiverTaskActive = false;
        this.archiverImporting = false;
        void this.refreshDownloadState();
        const delays: number[] = [600, 1800, 4000];
        for (let i = 0; i < delays.length; i++) {
          const tid: number = setTimeout((): void => {
            void this.refreshDownloadState();
          }, delays[i]) as number;
          this.archiverRefreshTimers.push(tid);
        }
      },
      (gid: number, _taskId: number, _e: Error): void => {
        if (gid !== this.gid || this.gid <= 0) {
          return;
        }
        this.archiverTaskActive = false;
        this.archiverImporting = false;
        this.showActionToast($r('app.string.download_archive_failure'));
      },
      (gid: number, _taskId: number): void => {
        if (gid !== this.gid || this.gid <= 0) {
          return;
        }
        this.archiverTaskActive = false;
        this.archiverImporting = false;
      }
    );
    this.archiverListener = listener;
    ArchiverDownloader.getInstance().addListener(listener);
    if (this.gid > 0) {
      const snap: ArchiverProgress | null = ArchiverDownloader.getInstance().getProgress(this.gid);
      if (snap !== null) {
        this.archiverTaskActive = true;
        this.archiverDownloaded = snap.downloaded;
        this.archiverTotal = snap.total;
        this.archiverSpeed = snap.speed;
        this.archiverPaused = snap.paused;
        this.syncArchiverImportingState();
      }
    }
  }

  private syncArchiverImportingState(): void {
    if (this.gid <= 0) {
      this.archiverImporting = false;
      return;
    }
    const activeTasks = ArchiverDownloader.getInstance().getActiveTasks();
    for (let i = 0; i < activeTasks.length; i++) {
      if (activeTasks[i].gid === this.gid && activeTasks[i].importing) {
        this.archiverImporting = true;
        return;
      }
    }
    this.archiverImporting = false;
  }

  private async confirmCancelArchiver(): Promise<void> {
    this.showCancelArchiverDialog = false;
    this.archiverTaskActive = false;
    this.archiverImporting = false;
    if (this.gid > 0) {
      await ArchiverDownloader.getInstance().cancel(this.gid);
    }
    await this.refreshDownloadState();
    this.showActionToast($r('app.string.archiver_download_canceled'));
  }

  private detachArchiverProgress(): void {
    if (this.archiverListener !== null) {
      ArchiverDownloader.getInstance().removeListener(this.archiverListener);
      this.archiverListener = null;
    }
    for (let i = 0; i < this.archiverRefreshTimers.length; i++) {
      clearTimeout(this.archiverRefreshTimers[i]);
    }
    this.archiverRefreshTimers = [];
  }

  private buildArchiverProgressText(): string {
    if (this.gid > 0) {
      const activeTasks = ArchiverDownloader.getInstance().getActiveTasks();
      for (let i = 0; i < activeTasks.length; i++) {
        if (activeTasks[i].gid === this.gid && activeTasks[i].importing) {
          return '正在解压导入…';
        }
      }
    }
    const pct: number = ArchiverProgressMath.percentage(this.archiverDownloaded, this.archiverTotal);
    const pctText: string = ArchiverProgressMath.percentText(pct);
    const dlText: string = FileUtils.humanReadableByteCount(this.archiverDownloaded, false);
    if (this.archiverPaused) {
      const pausedLabel: string = GetText.getString('archiver_download_paused');
      const prefix: string = pausedLabel.length > 0 ? pausedLabel : 'Paused';
      if (this.archiverTotal > 0) {
        const totalText: string = FileUtils.humanReadableByteCount(this.archiverTotal, false);
        return `${prefix} · ${pctText} · ${dlText}/${totalText}`;
      }
      return `${prefix} · ${dlText}`;
    }
    const speedStr: string = FileUtils.humanReadableByteCount(ArchiverProgressMath.safeSpeed(this.archiverSpeed), false) + '/s';
    if (this.archiverTotal > 0) {
      const totalText: string = FileUtils.humanReadableByteCount(this.archiverTotal, false);
      return `${pctText} · ${dlText}/${totalText} · ${speedStr}`;
    }
    return `${dlText} · ${speedStr}`;
  }

  private async refreshDownloadState(): Promise<void> {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    const targetGid: number = s !== null && s.getDetail() !== null
      ? (s.getDetail() as GalleryDetail).gid
      : this.gid;
    if (targetGid <= 0) {
      return;
    }
    try {
      const dm: DownloadManager = await DownloadManager.getInstance();
      this.downloadState = dm.getDownloadState(targetGid);
      this.downloaded = this.downloadState !== DownloadInfo.STATE_INVALID;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'refreshDownloadState failed: %{public}s', msg);
    }
  }

  private onShowJpnTitleChanged(): void {
    this.syncFromScene();
  }

  private syncFromScene(): void {
    this.showGalleryRating = Settings.getShowGalleryRating();
    this.showGalleryComment = Settings.getShowGalleryComment();

    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    const d: GalleryDetail | null = s.getDetail();
    const gi: GalleryInfo | null = s.getGalleryInfo();
    const base: GalleryInfo | null = d !== null ? d : gi;

    this.state = s.getState();
    this.loading = this.state === GalleryDetailState.LOADING;
    this.errorMessage = s.getErrorMessage();
    this.detailLoaded = d !== null;

    if (base !== null) {
      this.gid = base.gid > 0 ? base.gid : s.getGid();
      this.token = base.token;
      const preferred: string = EhUtils.getSuitableTitle(base) ?? base.title;
      this.displayTitle = preferred.length > 0 ? preferred : base.title;
      hilog.info(DOMAIN, TAG,
        'detail title resolved: gid=%{public}d showJpn=%{public}s titleLen=%{public}d titleJpnLen=%{public}d chosenJpn=%{public}s',
        this.gid, String(Settings.getShowJpnTitle()), base.title.length, base.titleJpn.length,
        String(Settings.getShowJpnTitle() && base.titleJpn.length > 0));
      this.uploader = base.uploader;
      this.categoryValue = base.category;
      this.categoryLabel = GalleryListClient.formatCategoryLabel(base.category);
      this.categoryColor = CategoryColors.forCategory(base.category);
      this.totalPages = d !== null && d.pages > 0 ? d.pages : base.pages;
      this.postedText = (d !== null && d.posted.length > 0) ? d.posted : base.posted;
      this.ratingValue = base.rating >= 0 ? base.rating : 0;
      this.ratingCount = d !== null ? d.ratingCount : 0;
      this.ratingText = this.buildRatingText(this.ratingValue, this.ratingCount);

      try {
        this.readStartPage = SpiderQueen.findStartPage(base);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'findStartPage skipped: %{public}s', e instanceof Error ? e.message : String(e));
        this.readStartPage = -1;
      }

      const thumbUrl: string = (d !== null && d.thumb.length > 0) ? d.thumb : base.thumb;
      if (thumbUrl.length > 0 && thumbUrl !== this.loadedCoverUrl) {
        this.loadedCoverUrl = thumbUrl;
        this.coverController.resetClip();
        this.coverController.load(EhCacheKeyFactory.getThumbKey(this.gid), thumbUrl);
        this.fullCoverController.resetClip();
        this.fullCoverController.load(EhCacheKeyFactory.getThumbKey(this.gid), thumbUrl);
      }
    } else {
      this.gid = s.getGid();
    }

    if (d !== null) {
      this.languageText = d.language !== null ? d.language : '';
      this.fileSizeText = d.size !== null ? d.size : '';
      this.favoriteCount = d.favoriteCount;
      this.favoredTimesText = d.favoriteCount > 0 ? this.formatCountString('favored_times', d.favoriteCount) : '';
      this.torrentCount = d.torrentCount;
      this.torrentUrl = d.torrentUrl !== null ? d.torrentUrl : '';
      this.torrentLabel = this.formatCountString('torrent_count', d.torrentCount);
      this.hasNewVersion = d.newVersions !== null && d.newVersions.length > 0;
      this.favoriteLabel = d.favoriteName !== null && d.favoriteName.length > 0
        ? d.favoriteName
        : (s.isLocalFavorited() ? GetText.getString('local_favorites') : '');
    } else {
      this.languageText = '';
      this.fileSizeText = '';
      this.favoriteCount = 0;
      this.favoredTimesText = '';
      this.torrentCount = 0;
      this.torrentUrl = '';
      this.torrentLabel = this.formatCountString('torrent_count', 0);
      this.hasNewVersion = false;
      this.favoriteLabel = s.isLocalFavorited() ? GetText.getString('local_favorites') : '';
    }

    const rawGroups: GalleryTagGroup[] = s.getTagGroups();
    this.rebuildTagGroups(rawGroups);
    this.previewPages = s.getPreviewPages();

    const ps: PreviewSet | null = s.getPreviewSet();
    this.currentPreviewSet = ps;
    const tiles: PreviewTileItem[] = [];
    if (ps !== null) {
      const count: number = ps.size();
      for (let i = 0; i < count; i++) {
        tiles.push(new PreviewTileItem(i, ps.getPosition(i)));
      }
    }
    this.previewTiles = tiles;
    this.previewRows = this.buildPreviewRows(tiles);
    this.previewEpoch = this.previewEpoch + 1;

    const cl: GalleryCommentList | null = s.getComments();
    if (cl !== null && cl.comments.length > 0) {
      this.totalCommentCount = cl.comments.length;
      this.comments = cl.comments.slice(0, MAX_SHOW_COMMENTS);
      this.hasMoreComments = cl.hasMore || cl.comments.length > MAX_SHOW_COMMENTS;
    } else {
      this.totalCommentCount = 0;
      this.comments = [];
      this.hasMoreComments = false;
    }

    this.downloaded = s.isDownloaded();
    if (!this.downloaded) {
      this.downloadState = DownloadInfo.STATE_INVALID;
    } else if (this.downloadState === DownloadInfo.STATE_INVALID) {
      void this.refreshDownloadState();
    }
    this.favorited = s.isFavorited();
    this.rated = (d !== null && d.rated) || (gi !== null && gi.rated);
    this.actionBusy = s.isActionBusy();
  }

  private formatCountString(key: string, count: number): string {
    const tmpl: string = GetText.getString(key);
    if (tmpl.length > 0 && tmpl.indexOf('%d') >= 0) {
      return tmpl.replace('%d', String(count));
    }
    if (key === 'favored_times') {
      return `♥ ${count}`;
    }
    return `Torrent (${count})`;
  }

  private formatTextArgString(key: string, arg: string): string {
    const tmpl: string = GetText.getString(key);
    if (tmpl.length > 0 && tmpl.indexOf('%s') >= 0) {
      return tmpl.replace('%s', arg);
    }
    return arg;
  }

  private ratingWordResource(rating: number): string {
    switch (Math.round(rating * 2)) {
      case 0:
        return 'rating0';
      case 1:
        return 'rating1';
      case 2:
        return 'rating2';
      case 3:
        return 'rating3';
      case 4:
        return 'rating4';
      case 5:
        return 'rating5';
      case 6:
        return 'rating6';
      case 7:
        return 'rating7';
      case 8:
        return 'rating8';
      case 9:
        return 'rating9';
      case 10:
        return 'rating10';
      default:
        return 'rating_none';
    }
  }

  private buildRatingText(rating: number, count: number): string {
    const word: string = GetText.getString(this.ratingWordResource(rating));
    const tmpl: string = GetText.getString('rating_text');
    if (tmpl.length > 0 && tmpl.indexOf('%1$s') >= 0) {
      return tmpl
        .replace('%1$s', word)
        .replace('%2$.2f', rating.toFixed(2))
        .replace('%3$d', String(count));
    }
    return `${word} (${rating.toFixed(2)}, ${count})`;
  }

  private clampHalfStar(rating: number): number {
    if (rating <= 0.5) {
      return 0.5;
    }
    if (rating >= 5.0) {
      return 5.0;
    }
    return Math.round(rating * 2) / 2;
  }

  private downloadStateResource(): Resource {
    switch (this.downloadState) {
      case DownloadInfo.STATE_NONE:
        return $r('app.string.download_state_none');
      case DownloadInfo.STATE_WAIT:
        return $r('app.string.download_state_wait');
      case DownloadInfo.STATE_DOWNLOAD:
        return $r('app.string.download_state_downloading');
      case DownloadInfo.STATE_FINISH:
        return $r('app.string.download_state_downloaded');
      case DownloadInfo.STATE_FAILED:
        return $r('app.string.download_state_failed');
      default:
        return this.downloaded ? $r('app.string.download_state_downloaded') : $r('app.string.download');
    }
  }

  private commentsButtonResource(): Resource {
    if (this.totalCommentCount === 0) {
      return $r('app.string.no_comments');
    }
    const state: MoreState = GalleryDetailBind.moreStateOf(this.totalCommentCount, MAX_SHOW_COMMENTS);
    if (state === MoreState.MORE_AVAILABLE || this.hasMoreComments) {
      return $r('app.string.more_comment');
    }
    return $r('app.string.no_more_comments');
  }

  private previewsButtonResource(): Resource {
    if (this.previewPages <= 0 || this.previewTiles.length === 0) {
      return $r('app.string.no_previews');
    }
    if (this.previewPages === 1) {
      return $r('app.string.no_more_previews');
    }
    return $r('app.string.more_previews');
  }

  private pagesDisplayText(): string {
    if (this.totalPages <= 0) {
      return '';
    }
    return GalleryDetailBind.pagesText(this.readStartPage, this.totalPages);
  }

  private showActionToast(msg: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showActionToast skipped: %{public}s', e instanceof Error ? e.message : String(e));
    }
  }

  private showActionToastText(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showActionToastText skipped: %{public}s', e instanceof Error ? e.message : String(e));
    }
  }

  private copyTextToClipboard(text: string): void {
    if (text.length === 0) {
      return;
    }
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      board.setDataSync(data);
      this.showActionToast($r('app.string.copied_to_clipboard'));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'copyTextToClipboard failed: %{public}s', e instanceof Error ? e.message : String(e));
    }
  }

  private detailShareUrl(): string {
    if (this.gid > 0 && this.token.length > 0) {
      return EhUrl.getGalleryDetailUrlSimple(this.gid, this.token);
    }
    return this.scene !== null ? this.scene.getApiUrl() : '';
  }

  private openUrlInBrowser(url: string): void {
    if (url.length === 0) {
      return;
    }
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    (ctx as common.UIAbilityContext).startAbility(want).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'openUrlInBrowser failed: %{public}s', e.message);
    });
  }

  private openUrlInInAppBrowser(url: string, title: string = ''): void {
    if (url.length === 0) {
      return;
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: PageRoutes.IN_APP_BROWSER,
        params: {
          url: url,
          title: title
        }
      }).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'pushUrl InAppBrowser failed: %{public}s', e.message);
        this.openUrlInBrowser(url);
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'openUrlInInAppBrowser threw: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.openUrlInBrowser(url);
    }
  }

  private startTorrentDownload(item: TorrentInfo): void {
    if (item.url.length === 0) {
      return;
    }
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    let saveDir: string | null = AppConfig.getExternalTempDir() ?? AppConfig.getTempDir();
    if ((saveDir === null || saveDir.length === 0) && ctx !== undefined && ctx.cacheDir.length > 0) {
      saveDir = `${ctx.cacheDir}/torrent`;
    }
    if (saveDir === null || saveDir.length === 0) {
      this.openUrlInBrowser(item.url);
      return;
    }
    const d: GalleryDetail | null = this.scene !== null ? this.scene.getDetail() : null;
    const displayName: string = d !== null && d.title.length > 0 ? d.title : item.name;
    const fileName: string = DownloadTorrentManager.createTorrentFileName(displayName, item.url);
    this.showActionToast($r('app.string.download_state_downloading'));
    const handler: TorrentDownloadHandler = new DetailTorrentDownloadHandler((msg: TorrentDownloadMessage): void => {
      if (msg.failed) {
        this.showActionToast($r('app.string.download_state_failed'));
        return;
      }
      if (msg.progress >= 100 && msg.path.length > 0) {
        this.downloadedTorrentPath = msg.path;
        this.downloadedTorrentName = msg.name.length > 0 ? msg.name : fileName;
        this.showTorrentActionDialog = true;
      }
    });
    DownloadTorrentManager.get(null).download(item.url, saveDir, fileName, handler);
  }

  private async saveTorrentToFiles(): Promise<void> {
    const localPath: string = this.downloadedTorrentPath;
    const fileName: string = this.downloadedTorrentName.length > 0 ? this.downloadedTorrentName : 'gallery.torrent';
    if (localPath.length === 0) {
      return;
    }
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    let srcFile: fs.File | null = null;
    let dstFile: fs.File | null = null;
    try {
      const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      saveOptions.fileSuffixChoices = ['.torrent'];
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const uris: Array<string> = await docPicker.save(saveOptions);
      if (uris.length === 0 || uris[0].length === 0) {
        return;
      }
      const stat: fs.Stat = fs.statSync(localPath);
      const buf: ArrayBuffer = new ArrayBuffer(Math.max(1, stat.size));
      srcFile = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
      const readLen: number = stat.size > 0 ? fs.readSync(srcFile.fd, buf, { offset: 0, length: stat.size }) : 0;
      dstFile = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      if (readLen > 0) {
        fs.writeSync(dstFile.fd, buf.slice(0, readLen));
      }
      this.showTorrentActionDialog = false;
      this.showActionToast($r('app.string.torrent_saved_success'));
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'saveTorrentToFiles failed: %{public}s', msg);
      this.showActionToastText(msg);
    } finally {
      if (srcFile !== null) {
        try {
          fs.closeSync(srcFile);
        } catch (e) {
          hilog.debug(DOMAIN, TAG, 'close torrent src failed: %{public}s',
            e instanceof Error ? e.message : String(e));
        }
      }
      if (dstFile !== null) {
        try {
          fs.closeSync(dstFile);
        } catch (e) {
          hilog.debug(DOMAIN, TAG, 'close torrent dst failed: %{public}s',
            e instanceof Error ? e.message : String(e));
        }
      }
    }
  }

  private openTorrentWithExternalApp(): void {
    const localPath: string = this.downloadedTorrentPath;
    if (localPath.length === 0) {
      return;
    }
    const ctx: common.UIAbilityContext | undefined =
      this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (ctx === undefined) {
      return;
    }
    try {
      const uri: string = fileUri.getUriFromPath(localPath);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        type: 'application/x-bittorrent',
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      ctx.startAbility(want).then((): void => {
        this.showTorrentActionDialog = false;
      }).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'openTorrentWithExternalApp failed: %{public}s', e.message);
        this.showActionToast($r('app.string.torrent_no_bt_app'));
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'openTorrentWithExternalApp threw: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.showActionToast($r('app.string.torrent_no_bt_app'));
    }
  }

  private startListSearch(ub: ListUrlBuilder): void {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    const listUrl: string = ub.build();
    const args: SceneArgs = new Map<string, Object>();
    args.set('action', 'action_list_url_builder');
    args.set('list_url_builder', listUrl);
    const rawKw: string | null = ub.getKeyword();
    if (rawKw !== null && rawKw.trim().length > 0) {
      const cleanKw: string = rawKw.trim();
      let displayKw: string = cleanKw;
      if (ub.getMode() === ListUrlBuilder.MODE_TAG) {
        displayKw = ListUrlBuilder.wrapTagKeyword(cleanKw);
      } else if (ub.getMode() === ListUrlBuilder.MODE_UPLOADER) {
        displayKw = cleanKw.indexOf(' ') >= 0 ? `uploader:"${cleanKw}"` : `uploader:${cleanKw}`;
      }
      args.set('search_keyword', displayKw);
    }
    s.startScene(new Announcer('GalleryListScene').setArgs(args));
  }

  private openUploaderSearch(): void {
    if (this.uploader.length === 0) {
      return;
    }
    const ub: ListUrlBuilder = new ListUrlBuilder();
    ub.setMode(ListUrlBuilder.MODE_UPLOADER);
    ub.setKeyword(this.uploader);
    this.startListSearch(ub);
  }

  private openCategorySearch(): void {
    if (this.categoryValue === EhUtils.UNKNOWN || this.categoryValue < 0) {
      return;
    }
    const ub: ListUrlBuilder = new ListUrlBuilder();
    ub.setCategory(this.categoryValue);
    this.startListSearch(ub);
  }

  private openSimilarGalleryList(): void {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    const d: GalleryDetail | null = s.getDetail();
    if (d === null) {
      return;
    }
    const keyword: string | null = EhUtils.extractTitle(d.title);
    if (keyword !== null && keyword.length > 0) {
      const ub: ListUrlBuilder = new ListUrlBuilder();
      ub.setMode(ListUrlBuilder.MODE_NORMAL);
      ub.setKeyword(`"${keyword}"`);
      this.startListSearch(ub);
      return;
    }
    if (d.tags !== null) {
      for (let i = 0; i < d.tags.length; i++) {
        const tg: GalleryTagGroup = d.tags[i];
        if (tg.groupName === 'artist' && tg.size() > 0) {
          s.openTagSearch('artist', tg.getTagAt(0));
          return;
        }
      }
    }
    if (d.uploader.length > 0) {
      this.openUploaderSearch();
    }
  }

  private openTagFromFull(fullTag: string): void {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    const colonIdx: number = fullTag.indexOf(':');
    if (colonIdx >= 0) {
      s.openTagSearch(fullTag.substring(0, colonIdx), fullTag.substring(colonIdx + 1));
    } else {
      s.openTagSearch('', fullTag);
    }
  }

  private addFilterEntry(mode: number, text: string): void {
    const f: Filter = new Filter();
    f.mode = mode;
    f.text = text;
    f.enable = true;
    EhDB.addFilter(f).then((): void => {
      this.showActionToast($r('app.string.filter_added'));
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'addFilterEntry failed: %{public}s', e.message);
    });
  }

  private async handleDownloadClick(): Promise<void> {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    if (this.downloaded || this.downloadState !== DownloadInfo.STATE_INVALID) {
      this.showRemoveDownloadDialog = true;
      return;
    }
    const ok: boolean = await s.downloadGallery();
    await this.refreshDownloadState();
    this.syncFromScene();
    this.showActionToast(ok ? $r('app.string.added_to_download_list') : $r('app.string.load_failed'));
  }

  private async confirmRemoveDownload(): Promise<void> {
    this.showRemoveDownloadDialog = false;
    if (this.gid <= 0) {
      return;
    }
    try {
      const dm: DownloadManager = await DownloadManager.getInstance();
      await dm.deleteDownload(this.gid);
      this.downloadState = DownloadInfo.STATE_INVALID;
      this.downloaded = false;
      if (this.scene !== null) {
        await this.scene.refreshStatusFlags();
      }
      this.syncFromScene();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'deleteDownload failed: %{public}s', e instanceof Error ? e.message : String(e));
    }
  }

  private resolveFavSlotName(slot: number): string {
    if (this.favSlotNames.length > slot && this.favSlotNames[slot].length > 0) {
      return this.favSlotNames[slot];
    }
    return `#${slot}`;
  }

  private async handleHeartClick(): Promise<void> {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    // 对齐原版：已收藏时单击直接取消收藏；未收藏时按默认收藏夹直加或弹窗选夹
    if (this.favorited) {
      await this.handleRemoveFavorite();
      return;
    }
    const defSlot: number = Settings.getDefaultFavSlot();
    if (defSlot === -1) {
      const ok: boolean = await s.addToFavorite(-2, '');
      const d: GalleryDetail | null = s.getDetail();
      if (ok && d !== null) {
        d.favoriteName = null;
      }
      this.syncFromScene();
      this.showActionToast(ok ? $r('app.string.add_to_favorite_success') : $r('app.string.add_to_favorite_failure'));
      return;
    }
    if (defSlot >= 0 && defSlot <= 9) {
      const ok: boolean = await s.addToFavorite(defSlot, '');
      const d: GalleryDetail | null = s.getDetail();
      if (ok && d !== null) {
        d.favoriteName = this.resolveFavSlotName(defSlot);
      }
      this.syncFromScene();
      this.showActionToast(ok ? $r('app.string.add_to_favorite_success') : $r('app.string.add_to_favorite_failure'));
      return;
    }
    this.showRatePicker = false;
    this.showFavPicker = true;
  }

  private handleHeartLongClick(): void {
    // 长按心形始终弹窗选择或切换收藏夹（对位原版换夹入口）
    this.showRatePicker = false;
    this.showFavPicker = true;
  }

  private async handleFavoriteSlot(slot: number): Promise<void> {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    this.showFavPicker = false;
    if (this.rememberFavSlot) {
      Settings.putDefaultFavSlot(slot === -2 ? -1 : slot);
      void Settings.flush();
    }
    const ok: boolean = await s.addToFavorite(slot, '');
    const d: GalleryDetail | null = s.getDetail();
    if (ok && d !== null) {
      d.favoriteName = slot === -2 ? null : this.resolveFavSlotName(slot);
    }
    this.syncFromScene();
    this.showActionToast(ok ? $r('app.string.add_to_favorite_success') : $r('app.string.add_to_favorite_failure'));
  }

  private async handleRemoveFavorite(): Promise<void> {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    this.showFavPicker = false;
    const ok: boolean = await s.removeFromFavorite();
    this.syncFromScene();
    this.showActionToast(ok ? $r('app.string.remove_from_favorite_success') : $r('app.string.remove_from_favorite_failure'));
  }

  private async handleRateValue(rating: number): Promise<void> {
    const s: GalleryDetailSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    this.showRatePicker = false;
    const outcome: GalleryRateOutcome | null = await s.rateGallery(rating);
    this.syncFromScene();
    this.showActionToast(outcome !== null ? $r('app.string.rate_successfully') : $r('app.string.rate_failed'));
  }

  private getHttpCaller(): HttpCaller {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    return new OkHttpCallerAdapter(EhApplication.getOkHttpClient(ctx === undefined ? null : ctx));
  }

  private async openTorrentModal(): Promise<void> {
    const d: GalleryDetail | null = this.scene !== null ? this.scene.getDetail() : null;
    if (d === null || this.torrentUrl.length === 0) {
      this.showActionToast($r('app.string.no_torrents'));
      return;
    }
    this.showTorrentDialog = true;
    this.torrentLoading = true;
    this.torrentError = '';
    this.torrentList = [];
    try {
      const list: TorrentInfo[] = await EhEngine.getTorrentList(
        null, this.getHttpCaller(), this.torrentUrl, d.gid, d.token);
      this.torrentList = list;
      this.torrentLoading = false;
    } catch (e) {
      this.torrentLoading = false;
      this.torrentError = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'getTorrentList failed: %{public}s', this.torrentError);
    }
  }

  private async openArchiveListModal(): Promise<void> {
    const d: GalleryDetail | null = this.scene !== null ? this.scene.getDetail() : null;
    if (d === null) {
      return;
    }
    if (d.apiUid < 0) {
      this.showActionToast($r('app.string.sign_in_first'));
      return;
    }
    if (d.archiveUrl === null || d.archiveUrl.length === 0) {
      this.showActionToast($r('app.string.no_archives'));
      return;
    }
    this.showArchiveDialog = true;
    this.archiveLoading = true;
    this.archiveError = '';
    this.archiveList = [];
    try {
      const res = await EhEngine.getArchiveList(
        null, this.getHttpCaller(), d.archiveUrl, d.gid, d.token);
      this.archiveParamOr = res.paramOr;
      this.archiveList = res.archiveList;
      this.archiveLoading = false;
    } catch (e) {
      this.archiveLoading = false;
      this.archiveError = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'getArchiveList failed: %{public}s', this.archiveError);
    }
  }

  private async triggerDownloadArchive(entry: ArchiveEntry): Promise<void> {
    const d: GalleryDetail | null = this.scene !== null ? this.scene.getDetail() : null;
    if (d === null) {
      return;
    }
    this.showArchiveDialog = false;
    try {
      await EhEngine.downloadArchive(null, this.getHttpCaller(), d.gid, d.token, this.archiveParamOr, entry.res);
      this.showActionToast($r('app.string.download_archive_started'));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'downloadArchive failed: %{public}s', e instanceof Error ? e.message : String(e));
      if (e instanceof NoHAtHClientException) {
        this.showActionToast($r('app.string.download_h_h_failure_no_hath'));
      } else {
        this.showActionToast($r('app.string.download_archive_failure'));
      }
    }
  }

  private async openArchiverModal(): Promise<void> {
    const d: GalleryDetail | null = this.scene !== null ? this.scene.getDetail() : null;
    if (d === null) {
      return;
    }
    if (d.apiUid < 0) {
      this.showActionToast($r('app.string.sign_in_first'));
      return;
    }
    if (d.archiveUrl === null || d.archiveUrl.length === 0) {
      this.showActionToast($r('app.string.no_archives'));
      return;
    }
    this.showArchiverDialog = true;
    this.archiverLoading = true;
    this.archiverError = '';
    this.archiverData = null;
    try {
      const data: ArchiverData = await EhEngine.getArchiver(
        null, this.getHttpCaller(), d.archiveUrl, d.gid, d.token);
      this.archiverData = data;
      this.archiverLoading = false;
    } catch (e) {
      this.archiverLoading = false;
      this.archiverError = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'getArchiver failed: %{public}s', this.archiverError);
    }
  }

  private async triggerDownloadArchiver(dltype: string, dlcheck: string): Promise<void> {
    const d: GalleryDetail | null = this.scene !== null ? this.scene.getDetail() : null;
    if (d === null || d.archiveUrl === null || this.archiverLoading) {
      return;
    }
    // 对齐原版 ArchiverDownloadDialog：点击下载选项后保留弹窗并立刻切换转圈，待拿到直链后再关窗入队
    this.archiverLoading = true;
    this.archiverError = '';
    const archData: ArchiverData | null = this.archiverData;
    const candidateUrl: string = archData !== null
      ? (dltype === 'org' ? archData.originalUrl : archData.resampleUrl)
      : '';
    const postUrl: string = candidateUrl.startsWith('http') ? candidateUrl : d.archiveUrl;
    try {
      const downloadUrl: string | null = await EhEngine.downloadArchiver(
        null, this.getHttpCaller(), postUrl, d.archiveUrl, dltype, dlcheck);
      this.archiverLoading = false;
      this.showArchiverDialog = false;
      if (downloadUrl !== null && downloadUrl.length > 0) {
        const archTitle: string = EhUtils.getSuitableTitle(d) ?? d.title;
        const fileName: string = ArchiverDownloadCompleter.createFileName(
          archTitle.length > 0 ? archTitle : d.title, d.gid);
        this.archiverTaskActive = true;
        this.archiverDownloaded = 0;
        this.archiverTotal = 0;
        this.archiverSpeed = 0;
        this.archiverPaused = false;
        this.showActionToast($r('app.string.download_archive_started'));
        await ArchiverDownloader.getInstance().start(d, downloadUrl, fileName);
      } else {
        this.showActionToast($r('app.string.download_archive_failure'));
      }
    } catch (e) {
      this.archiverLoading = false;
      this.showArchiverDialog = false;
      hilog.warn(DOMAIN, TAG, 'downloadArchiver failed: %{public}s', e instanceof Error ? e.message : String(e));
      this.showActionToast($r('app.string.download_archive_failure'));
    }
  }

  private favSlotIndexes(): number[] {
    return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  }

  private starIndexes(): number[] {
    return [0, 1, 2, 3, 4];
  }

  private openReaderAt(pageIndex: number): void {
    const safePage: number = pageIndex >= 0 ? pageIndex : 0;
    const apiUrl: string = this.scene !== null ? this.scene.getApiUrl() : '';
    const params: GalleryReaderRouteParams = new GalleryReaderRouteParams(
      this.gid,
      this.token,
      safePage,
      this.totalPages,
      this.displayTitle,
      apiUrl
    );
    pushGalleryReaderPage(this.getUIContext(), params, TAG);
  }

  private formatCommentTime(epochMs: number): string {
    if (epochMs <= 0) {
      return '';
    }
    return ReadableTime.getTimeAgo(epochMs);
  }

  private stripHtml(html: string): string {
    return html
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .trim();
  }

  private formatCommentScore(c: GalleryComment): string {
    if (c.id === 0 || c.score === 0) {
      return '';
    }
    return c.score > 0 ? `+${c.score}` : String(c.score);
  }

  @Builder
  coverThumbSlot() {
    LoadImageView({
      controller: this.coverController,
      imageFit: ImageFit.Contain
    })
  }

  @Builder
  previewGridSlot() {
    Column({ space: ThemeDimens.SPACING_XS }) {
      ForEach(this.previewRows, (row: PreviewTileRow) => {
        Row({ space: ThemeDimens.SPACING_XS }) {
          ForEach(row.tiles, (tile: PreviewTileItem) => {
            Column() {
              PreviewTileView({
                gid: this.gid,
                index: tile.index,
                pageLabel: tile.pageLabel,
                tileHeight: 112,
                themeId: this.themeId,
                loadEpoch: this.previewEpoch,
                previewSet: this.currentPreviewSet,
                onTileClick: (): void => {
                  this.openReaderAt(tile.position);
                }
              })
            }
            .layoutWeight(1)
          }, (tile: PreviewTileItem) => 'teaser_' + String(this.previewEpoch) + '_' + String(tile.index))

          if (row.tiles.length < 3) {
            Column().layoutWeight(1)
          }
          if (row.tiles.length < 2) {
            Column().layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (row: PreviewTileRow) => 'row_' + String(this.previewEpoch) + '_' + String(row.rowIndex))
    }
    .width('100%')
  }

  @Builder
  sectionDivider() {
    Divider()
      .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
      .color(this.palette().divider)
      .margin({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
  }

  @Builder
  archiverPauseButtonSlot() {
    Column() {
      if (this.archiverPaused) {
        VPlayX24({
          iconSize: 22,
          fillColor: this.palette().galleryDetailHeaderTitle
        })
      } else {
        VPauseX24({
          iconSize: 22,
          fillColor: this.palette().galleryDetailHeaderTitle
        })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (this.archiverPaused) {
        void ArchiverDownloader.getInstance().resume(this.gid);
      } else {
        ArchiverDownloader.getInstance().pause(this.gid);
      }
    })
  }

  @Builder
  archiverCancelButtonSlot() {
    Column() {
      VCloseDarkX24({
        iconSize: 18,
        fillColor: this.palette().galleryDetailHeaderTitle
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (!this.archiverImporting) {
        this.showCancelArchiverDialog = true;
      }
    })
  }

  @Builder
  archiverProgressHeaderSlot() {
    ArchiverProgressWidgetLayout({
      downloadingText: this.buildArchiverProgressText(),
      textColorHighlight: this.themeId === ThemeMode.LIGHT ? this.palette().white : this.palette().colorAccent,
      progressColor: this.palette().colorAccent,
      trackColor: this.themeId === ThemeMode.LIGHT ? '#4DFFFFFF' : '#33FFFFFF',
      value: ArchiverProgressMath.progressBarValue(
        ArchiverProgressMath.percentage(this.archiverDownloaded, this.archiverTotal)
      ),
      total: 100,
      showCancel: !this.archiverImporting,
      pauseButtonBuilder: (): void => {
        this.archiverPauseButtonSlot();
      },
      cancelButtonBuilder: (): void => {
        this.archiverCancelButtonSlot();
      }
    })
  }

  @Builder
  detailContent() {
    Column() {
      GalleryDetailHeaderLayout({
        category: this.categoryLabel,
        categoryColor: this.categoryColor,
        title: this.displayTitle,
        uploader: this.uploader,
        downloadText: this.downloadStateResource(),
        downloadEnabled: !this.actionBusy,
        showBackButton: true,
        showOverflowMenu: true,
        archiverProgressVisibility: this.archiverTaskActive ? Visibility.Visible : Visibility.None,
        newVersionVisibility: this.hasNewVersion ? Visibility.Visible : Visibility.None,
        themeId: this.themeId,
        thumbBuilder: (): void => {
          this.coverThumbSlot();
        },
        archiverDownloadProgressBuilder: (): void => {
          this.archiverProgressHeaderSlot();
        },
        onBackClick: (): void => {
          if (this.scene !== null) {
            this.scene.finish();
          }
        },
        onMenuClick: (): void => {
          this.showOverflowMenu = !this.showOverflowMenu;
        },
        onThumbClick: (): void => {
          if (this.loadedCoverUrl.length > 0) {
            this.showCoverDialog = true;
          }
        },
        onTitleClick: (): void => {
          this.copyTextToClipboard(this.displayTitle);
        },
        onUploaderClick: (): void => {
          this.openUploaderSearch();
        },
        onUploaderLongClick: (): void => {
          if (this.uploader.length > 0) {
            this.showFilterUploaderDialog = true;
          }
        },
        onCategoryClick: (): void => {
          this.openCategorySearch();
        },
        onDownloadClick: (): void => {
          void this.handleDownloadClick();
        },
        onDownloadLongClick: (): void => {
          void this.handleDownloadClick();
        },
        onReadClick: (): void => {
          this.openReaderAt(this.readStartPage > 0 ? this.readStartPage : 0);
        }
      })

      if (this.loading && !this.detailLoaded) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(this.palette().progressColor)
        }
        .width('100%')
        .padding(ThemeDimens.KEYLINE_MARGIN)
        .alignItems(HorizontalAlign.Center)
      } else {
        this.sectionDivider()

        GalleryDetailInfoLayout({
          language: this.languageText,
          pages: this.pagesDisplayText(),
          sizeText: this.fileSizeText,
          favoredTimes: this.favoredTimesText,
          posted: this.postedText,
          themeId: this.themeId,
          onInfoClick: (): void => {
            if (this.scene !== null) {
              this.scene.openGalleryInfo();
            }
          }
        })

        this.sectionDivider()

        GalleryDetailActionsLayout({
          favorited: this.favorited,
          favoriteLabel: this.favoriteLabel,
          rating: this.ratingValue,
          rated: this.rated,
          ratingText: this.ratingText,
          showRating: this.showGalleryRating,
          torrentText: this.torrentLabel,
          showTorrent: this.torrentCount > 0 || this.torrentUrl.length > 0,
          themeId: this.themeId,
          onHeartClick: (): void => {
            void this.handleHeartClick();
          },
          onHeartLongClick: (): void => {
            this.handleHeartLongClick();
          },
          onRateClick: (): void => {
            const d: GalleryDetail | null = this.scene !== null ? this.scene.getDetail() : null;
            if (d === null) {
              return;
            }
            if (d.apiUid < 0) {
              this.showActionToast($r('app.string.sign_in_first'));
              return;
            }
            this.showFavPicker = false;
            this.ratePickerValue = this.clampHalfStar(this.ratingValue);
            this.showRatePicker = true;
          },
          onShareClick: (): void => {
            this.copyTextToClipboard(this.detailShareUrl());
          },
          onTorrentClick: (): void => {
            void this.openTorrentModal();
          },
          onArchiverClick: (): void => {
            void this.openArchiverModal();
          },
          onHhClick: (): void => {
            void this.openArchiveListModal();
          },
          onSimilarClick: (): void => {
            this.openSimilarGalleryList();
          },
          onSearchCoverClick: (): void => {
            this.openSimilarGalleryList();
          }
        })

        this.sectionDivider()

        GalleryDetailTagsLayout({
          tagGroups: this.tagGroupViews,
          themeId: this.themeId,
          onTagClick: (fullTag: string): void => {
            this.openTagFromFull(fullTag);
          },
          onTagLongClick: (fullTag: string): void => {
            this.selectedTagForDialog = fullTag;
          }
        })

        if (this.showGalleryComment) {
          this.sectionDivider()

          GalleryDetailCommentsLayout({
            comments: this.comments,
            commentsText: this.commentsButtonResource(),
            themeId: this.themeId,
            formatTime: (ms: number): string => this.formatCommentTime(ms),
            formatBody: (html: string): string => this.stripHtml(html),
            formatScore: (c: GalleryComment): string => this.formatCommentScore(c),
            onCommentsClick: (): void => {
              if (this.scene !== null) {
                this.scene.openComments();
              }
            }
          })
        }

        this.sectionDivider()

        GalleryDetailPreviewsLayout({
          previewText: this.previewsButtonResource(),
          hasPreviews: this.previewTiles.length > 0,
          themeId: this.themeId,
          gridLayoutBuilder: (): void => {
            this.previewGridSlot();
          },
          onMoreClick: (): void => {
            if (this.scene !== null) {
              this.scene.openPreviews(0);
            }
          }
        })
      }
    }
    .width('100%')
  }

  @Builder
  overflowMenuOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().transparent)
        .onClick((): void => {
          this.showOverflowMenu = false;
        })

      Column() {
        Button($r('app.string.refresh'), { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .borderRadius(ThemeRadius.NONE)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .align(Alignment.Start)
          .onClick((): void => {
            this.showOverflowMenu = false;
            if (this.scene !== null) {
              this.scene.reloadDetail();
            }
          })

        Button($r('app.string.open_in_other_app'), { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .borderRadius(ThemeRadius.NONE)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .align(Alignment.Start)
          .onClick((): void => {
            this.showOverflowMenu = false;
            this.openUrlInBrowser(this.detailShareUrl());
          })
      }
      .width(196)
      .padding({ top: 4, bottom: 4 })
      .margin({ top: 8, right: 8 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(8)
  }

  @Builder
  favPickerOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.showFavPicker = false;
        })

      Column() {
        Text($r('app.string.add_favorites_dialog_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        List() {
          ListItem() {
            Row() {
              Text($r('app.string.local_favorites'))
                .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                .fontColor(this.palette().textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .padding({ left: 24, right: 24 })
            .onClick((): void => {
              void this.handleFavoriteSlot(-2);
            })
          }

          ForEach(this.favSlotIndexes(), (slot: number) => {
            ListItem() {
              Row() {
                Text(this.favSlotNames.length > slot && this.favSlotNames[slot].length > 0
                  ? this.favSlotNames[slot] : `#${slot}`)
                  .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                  .fontColor(this.palette().textPrimary)
                  .layoutWeight(1)
              }
              .width('100%')
              .height(ThemeDimens.TOUCH_TARGET_MIN)
              .padding({ left: 24, right: 24 })
              .onClick((): void => {
                void this.handleFavoriteSlot(slot);
              })
            }
          }, (slot: number) => String(slot))
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .divider({
          strokeWidth: ThemeDimens.DIVIDER_HEIGHT,
          color: this.palette().divider,
          startMargin: 24,
          endMargin: 24
        })

        Row({ space: 8 }) {
          Checkbox({ name: 'remember_fav' })
            .select(this.rememberFavSlot)
            .selectedColor(this.palette().controlActivated)
            .onChange((checked: boolean): void => {
              this.rememberFavSlot = checked;
            })
          Text($r('app.string.remember_favorite_collection'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 24, top: 8, bottom: 4 })
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          if (this.favorited) {
            Button($r('app.string.remove_from_favourites'), { type: ButtonType.Normal })
              .borderRadius(ThemeRadius.BUTTON)
              .constraintSize({ minWidth: 64, minHeight: 36 })
              .backgroundColor(this.palette().transparent)
              .fontColor(this.palette().errorColor)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .onClick((): void => {
                void this.handleRemoveFavorite();
              })
          }

          Blank().layoutWeight(1)

          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showFavPicker = false;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 400 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
  }

  @Builder
  ratePickerOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.showRatePicker = false;
        })

      Column() {
        Text($r('app.string.rate'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Text(GetText.getString(this.ratingWordResource(this.ratePickerValue))
          + ' (' + this.ratePickerValue.toFixed(1) + ')')
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, bottom: 16 })

        Row({ space: 6 }) {
          ForEach(this.starIndexes(), (starIdx: number) => {
            Stack({ alignContent: Alignment.Center }) {
              if (this.ratePickerValue >= starIdx + 1) {
                VStarX16({ iconSize: 34 })
              } else if (this.ratePickerValue >= starIdx + 0.5) {
                VStarHalfX16({ iconSize: 34 })
              } else {
                VStarOutlineX16({ iconSize: 34 })
              }

              Row() {
                Column()
                  .width('50%')
                  .height('100%')
                  .onClick((): void => {
                    this.ratePickerValue = this.clampHalfStar(starIdx + 0.5);
                  })
                Column()
                  .width('50%')
                  .height('100%')
                  .onClick((): void => {
                    this.ratePickerValue = this.clampHalfStar(starIdx + 1.0);
                  })
              }
              .width(34)
              .height(34)
            }
            .width(34)
            .height(34)
          }, (starIdx: number) => String(starIdx))
        }
        .justifyContent(FlexAlign.Center)
        .padding({ left: 16, right: 16, bottom: 12 })

        Row({ space: 8 }) {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showRatePicker = false;
            })

          Button($r('app.string.ok'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              void this.handleRateValue(this.ratePickerValue);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 360 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
  }

  @Builder
  confirmDialogOverlay(
    titleRes: Resource | null,
    messageText: ResourceStr,
    onCancel: () => void,
    onConfirm: () => void
  ) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick(onCancel)

      Column() {
        if (titleRes !== null) {
          Text(titleRes)
            .fontSize(ThemeTypography.DIALOG_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textPrimary)
            .width('100%')
            .padding({ left: 24, right: 24, top: 20, bottom: 12 })
        }

        Text(messageText)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: titleRes === null ? 20 : 0, bottom: 16 })

        Row({ space: 8 }) {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick(onCancel)

          Button($r('app.string.ok'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick(onConfirm)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 380 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(11)
  }

  @Builder
  tagActionDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.selectedTagForDialog = '';
        })

      Column() {
        Text(this.selectedTagForDialog)
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 8 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button($r('app.string.copy_tag'), { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .padding({ left: 24, right: 24 })
          .borderRadius(ThemeRadius.NONE)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .align(Alignment.Start)
          .onClick((): void => {
            const tagText: string = this.selectedTagForDialog;
            this.selectedTagForDialog = '';
            this.copyTextToClipboard(tagText);
          })

        Button($r('app.string.tag_filter'), { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .padding({ left: 24, right: 24 })
          .borderRadius(ThemeRadius.NONE)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .align(Alignment.Start)
          .onClick((): void => {
            const tagText: string = this.selectedTagForDialog;
            this.selectedTagForDialog = '';
            this.addFilterEntry(EhFilter.MODE_TAG, tagText);
          })

        Button($r('app.string.open_in_other_app'), { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .padding({ left: 24, right: 24 })
          .borderRadius(ThemeRadius.NONE)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .align(Alignment.Start)
          .onClick((): void => {
            const tagText: string = this.selectedTagForDialog;
            this.selectedTagForDialog = '';
            const tagName: string = stripTagNamespace(tagText).trim().replace(/ /g, '_');
            this.openUrlInInAppBrowser('https://ehwiki.org/wiki/' + encodeURIComponent(tagName), tagName);
          })
      }
      .width('84%')
      .constraintSize({ maxWidth: 360 })
      .padding({ bottom: 8 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(11)
  }

  @Builder
  torrentDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.showTorrentDialog = false;
        })

      Column() {
        Text($r('app.string.torrents'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        if (this.torrentLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(this.palette().progressColor)
          }
          .width('100%')
          .padding(24)
          .alignItems(HorizontalAlign.Center)
        } else if (this.torrentError.length > 0) {
          Text(this.torrentError)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().errorColor)
            .padding({ left: 24, right: 24, bottom: 16 })
        } else if (this.torrentList.length === 0) {
          Text($r('app.string.no_torrents'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textSecondary)
            .padding({ left: 24, right: 24, bottom: 16 })
        } else {
          List() {
            ForEach(this.torrentList, (item: TorrentInfo, idx: number) => {
              ListItem() {
                Column({ space: 2 }) {
                  Text(item.name)
                    .fontSize(ThemeTypography.TEXT_SMALL)
                    .fontColor(this.palette().textPrimary)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (item.posted.length > 0) {
                    Text(item.posted)
                      .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                      .fontColor(this.palette().textSecondary)
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 24, right: 24, top: 10, bottom: 10 })
                .onClick((): void => {
                  this.showTorrentDialog = false;
                  this.startTorrentDownload(item);
                })
              }
            }, (item: TorrentInfo, idx: number) => `${idx}_${item.url}`)
          }
          .width('100%')
          .constraintSize({ maxHeight: 320 })
          .divider({
            strokeWidth: ThemeDimens.DIVIDER_HEIGHT,
            color: this.palette().divider,
            startMargin: 24,
            endMargin: 24
          })
        }

        Row() {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showTorrentDialog = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 400 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(11)
  }

  @Builder
  torrentActionDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.showTorrentActionDialog = false;
        })

      Column() {
        Text($r('app.string.torrent_download_complete'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 8 })

        Text(this.downloadedTorrentName)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 12 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button($r('app.string.torrent_action_save_to_files'), { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .padding({ left: 24, right: 24 })
          .borderRadius(ThemeRadius.NONE)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .align(Alignment.Start)
          .onClick((): void => {
            void this.saveTorrentToFiles();
          })

        Button($r('app.string.torrent_action_open_bt_app'), { type: ButtonType.Normal })
          .width('100%')
          .height(48)
          .padding({ left: 24, right: 24 })
          .borderRadius(ThemeRadius.NONE)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .align(Alignment.Start)
          .onClick((): void => {
            this.openTorrentWithExternalApp();
          })

        Row() {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showTorrentActionDialog = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 360 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside torrent action card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(12)
  }

  @Builder
  archiveDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.showArchiveDialog = false;
        })

      Column() {
        Text($r('app.string.dialog_archive_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        if (this.archiveLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(this.palette().progressColor)
          }
          .width('100%')
          .padding(24)
          .alignItems(HorizontalAlign.Center)
        } else if (this.archiveError.length > 0) {
          Text(this.archiveError)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().errorColor)
            .padding({ left: 24, right: 24, bottom: 16 })
        } else if (this.archiveList.length === 0) {
          Text($r('app.string.no_archives'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textSecondary)
            .padding({ left: 24, right: 24, bottom: 16 })
        } else {
          List() {
            ForEach(this.archiveList, (entry: ArchiveEntry, idx: number) => {
              ListItem() {
                Row() {
                  Text(entry.name)
                    .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                    .fontColor(this.palette().textPrimary)
                    .layoutWeight(1)
                }
                .width('100%')
                .height(ThemeDimens.TOUCH_TARGET_MIN)
                .padding({ left: 24, right: 24 })
                .onClick((): void => {
                  void this.triggerDownloadArchive(entry);
                })
              }
            }, (entry: ArchiveEntry, idx: number) => `${idx}_${entry.res}`)
          }
          .width('100%')
          .constraintSize({ maxHeight: 300 })
          .divider({
            strokeWidth: ThemeDimens.DIVIDER_HEIGHT,
            color: this.palette().divider,
            startMargin: 24,
            endMargin: 24
          })
        }

        Row() {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showArchiveDialog = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 380 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(11)
  }

  @Builder
  archiverDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          if (!this.archiverLoading) {
            this.showArchiverDialog = false;
          }
        })

      Column() {
        Text($r('app.string.dialog_archiver_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        if (this.archiverLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(this.palette().progressColor)
          }
          .width('100%')
          .padding(24)
          .alignItems(HorizontalAlign.Center)
        } else if (this.archiverError.length > 0) {
          Text(this.archiverError)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().errorColor)
            .padding({ left: 24, right: 24, bottom: 16 })
        } else if (this.archiverData !== null) {
          Column({ space: 10 }) {
            if (this.archiverData.funds.length > 0) {
              Row({ space: 6 }) {
                Text($r('app.string.archiver_dialog_current_funds'))
                  .fontSize(ThemeTypography.TEXT_SMALL)
                  .fontColor(this.palette().textSecondary)
                Text(this.archiverData.funds)
                  .fontSize(ThemeTypography.TEXT_SMALL)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().textPrimary)
              }
              .width('100%')
            }

            Column({ space: 6 }) {
              if (this.archiverData.originalCost.length > 0 || this.archiverData.originalSize.length > 0) {
                if (this.archiverData.originalCost.length > 0) {
                  Text(this.formatTextArgString('archiver_dialog_cost', this.archiverData.originalCost))
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontColor(this.palette().textSecondary)
                }
                if (this.archiverData.originalSize.length > 0) {
                  Text(this.formatTextArgString('archiver_dialog_size', this.archiverData.originalSize))
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontColor(this.palette().textSecondary)
                }
              }
              Button($r('app.string.archiver_dialog_download_original'), { type: ButtonType.Normal })
                .width('100%')
                .height(40)
                .borderRadius(ThemeRadius.BUTTON)
                .backgroundColor(this.palette().colorPrimary)
                .fontColor(this.palette().white)
                .fontSize(ThemeTypography.BUTTON)
                .fontWeight(FontWeight.Medium)
                .onClick((): void => {
                  void this.triggerDownloadArchiver('org', 'Download Original Archive');
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 6 }) {
              if (this.archiverData.resampleCost.length > 0 || this.archiverData.resampleSize.length > 0) {
                if (this.archiverData.resampleCost.length > 0) {
                  Text(this.formatTextArgString('archiver_dialog_cost', this.archiverData.resampleCost))
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontColor(this.palette().textSecondary)
                }
                if (this.archiverData.resampleSize.length > 0) {
                  Text(this.formatTextArgString('archiver_dialog_size', this.archiverData.resampleSize))
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontColor(this.palette().textSecondary)
                }
              }
              Button($r('app.string.archiver_dialog_download_resample'), { type: ButtonType.Normal })
                .width('100%')
                .height(40)
                .borderRadius(ThemeRadius.BUTTON)
                .backgroundColor(this.palette().galleryDetailButtonBackground)
                .fontColor(this.palette().textPrimary)
                .fontSize(ThemeTypography.BUTTON)
                .fontWeight(FontWeight.Medium)
                .onClick((): void => {
                  void this.triggerDownloadArchiver('res', 'Download Resample Archive');
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 8 })
        }

        Row() {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showArchiverDialog = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 400 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick((): void => {
        // Consume clicks inside archiver dialog card
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(11)
  }

  @Builder
  coverDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      LoadImageView({
        controller: this.fullCoverController,
        imageFit: ImageFit.Contain
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().black)
    .zIndex(12)
    .onClick((): void => {
      this.showCoverDialog = false;
    })
  }

  build() {
    Stack() {
      SceneGalleryDetailLayout({
        tip: this.errorMessage.length > 0 ? this.errorMessage : $r('app.string.error_cannot_find_gallery'),
        showContent: this.state !== GalleryDetailState.ERROR && !(this.loading && !this.detailLoaded && this.displayTitle.length === 0),
        showProgress: this.state !== GalleryDetailState.ERROR && this.loading && !this.detailLoaded && this.displayTitle.length === 0,
        showTip: this.state === GalleryDetailState.ERROR,
        themeId: this.themeId,
        onTipClick: (): void => {
          if (this.scene !== null) {
            this.scene.reloadDetail();
          }
        },
        contentBuilder: (): void => {
          this.detailContent();
        }
      })

      if (this.showOverflowMenu) {
        this.overflowMenuOverlay()
      }

      if (this.showFavPicker) {
        this.favPickerOverlay()
      }

      if (this.showRatePicker) {
        this.ratePickerOverlay()
      }

      if (this.showRemoveDownloadDialog) {
        this.confirmDialogOverlay(
          $r('app.string.download_remove_dialog_title'),
          this.formatTextArgString('download_remove_dialog_message', this.displayTitle),
          (): void => {
            this.showRemoveDownloadDialog = false;
          },
          (): void => {
            void this.confirmRemoveDownload();
          }
        )
      }

      if (this.showCancelArchiverDialog) {
        this.confirmDialogOverlay(
          $r('app.string.archiver_download_cancel'),
          $r('app.string.archiver_download_cancel_confirm'),
          (): void => {
            this.showCancelArchiverDialog = false;
          },
          (): void => {
            void this.confirmCancelArchiver();
          }
        )
      }

      if (this.showFilterUploaderDialog) {
        this.confirmDialogOverlay(
          null,
          this.formatTextArgString('filter_the_uploader', this.uploader),
          (): void => {
            this.showFilterUploaderDialog = false;
          },
          (): void => {
            this.showFilterUploaderDialog = false;
            this.addFilterEntry(EhFilter.MODE_UPLOADER, this.uploader);
          }
        )
      }

      if (this.selectedTagForDialog.length > 0) {
        this.tagActionDialogOverlay()
      }

      if (this.showTorrentDialog) {
        this.torrentDialogOverlay()
      }

      if (this.showTorrentActionDialog) {
        this.torrentActionDialogOverlay()
      }

      if (this.showArchiveDialog) {
        this.archiveDialogOverlay()
      }

      if (this.showArchiverDialog) {
        this.archiverDialogOverlay()
      }

      if (this.showCoverDialog) {
        this.coverDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
