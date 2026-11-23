/*
 * DownloadsSceneView: Material UI for DownloadsScene (Toolbar, DownloadManager live updates,
 * right Download Labels drawer, DownloadItemLayout cards with state mapping, progress, speed & actions).
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { DownloadInfo } from '../../ehviewer/dao/DownloadInfo';
import { DownloadLabel } from '../../ehviewer/dao/DownloadLabel';
import { EhDB } from '../../ehviewer/EhDB';
import { EhCacheKeyFactory } from '../../ehviewer/client/EhCacheKeyFactory';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { EhUtils } from '../../ehviewer/client/EhUtils';
import { DownloadInfoListener } from '../../ehviewer/download/DownloadInfoListener';
import { DownloadManager } from '../../ehviewer/download/DownloadManager';
import {
  ArchiverDownloader,
  ArchiverDownloaderListener,
  ArchiverTaskSnapshot
} from '../../ehviewer/download/ArchiverDownloader';
import { archiverLabel } from '../../ehviewer/download/ArchiverDownloadCompleter';
import { DownloadAdapterLike } from '../../ehviewer/ui/scene/download/DownloadAdapterContracts';
import { SpiderDen } from '../../ehviewer/spider/SpiderDen';
import { UniFile } from '../../unifile/UniFile';
import { Settings } from '../../ehviewer/Settings';
import { GetText } from '../../ehviewer/GetText';
import { DownloadsSceneShell } from '../../ehviewer/ui/scene/download/DownloadsSceneShell';
import {
  DownloadPaginationController,
  PaginationHostLike,
  PaginationIndicatorLike
} from '../../ehviewer/ui/scene/download/part/DownloadPaginationController';
import { GalleryReaderRouteParams } from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailScene';
import { FileUtils } from '../../lib/yorozuya/FileUtils';
import { Announcer } from '../../scene/Announcer';
import { FabBehaviorState, FabLayout, OnClickFabListenerImpl } from '../../widget/FabLayout';
import { BigDownload } from '../drawable/big_download';
import { VCheckAllDarkX24 } from '../drawable/v_check_all_dark_x24';
import { VCheckDarkX24 } from '../drawable/v_check_dark_x24';
import { VCloseDarkX24 } from '../drawable/v_close_dark_x24';
import { VDeleteDarkX24 } from '../drawable/v_delete_dark_x24';
import { VDownloadBoxDarkX24 } from '../drawable/v_download_box_dark_x24';
import { VFolderMoveDarkX24 } from '../drawable/v_folder_move_dark_x24';
import { VPauseDarkX24 } from '../drawable/v_pause_dark_x24';
import { VPlayDarkX24 } from '../drawable/v_play_dark_x24';
import { VPlusDarkX24 } from '../drawable/v_plus_dark_x24';
import { VRandomDarkX24 } from '../drawable/v_random_dark_x24';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { GalleryListClient } from '../GalleryListClient';
import { MainPageHost } from '../MainPageHost';
import { APP_SHOW_JPN_TITLE_STORAGE_KEY } from '../ThemeSystemBar';
import { DownloadItemLayout } from '../layout/item_download';
import { pushGalleryReaderPage } from './GalleryDetailSceneView';

const DOMAIN: number = 0x0000;
const TAG: string = 'DownloadsSceneView';

class DownloadsPaginationHost implements PaginationHostLike {
  private readonly getSizeFn: () => number;
  private readonly onNotifyFn: () => void;
  private readonly onScrollFn: (pos: number) => void;

  constructor(getSizeFn: () => number, onNotifyFn: () => void, onScrollFn: (pos: number) => void) {
    this.getSizeFn = getSizeFn;
    this.onNotifyFn = onNotifyFn;
    this.onScrollFn = onScrollFn;
  }

  getListSize(): number {
    return this.getSizeFn();
  }

  notifyAdapter(): void {
    this.onNotifyFn();
  }

  scrollToPosition(position: number): void {
    this.onScrollFn(position);
  }
}

class DownloadsPaginationIndicator implements PaginationIndicatorLike {
  private readonly onTotalFn: (total: number) => void;
  private readonly onPageFn: (page: number) => void;

  constructor(onTotalFn: (total: number) => void, onPageFn: (page: number) => void) {
    this.onTotalFn = onTotalFn;
    this.onPageFn = onPageFn;
  }

  setTotalPages(total: number): void {
    this.onTotalFn(total);
  }

  setCurrentPage(page: number): void {
    this.onPageFn(page);
  }
}

class LabelDrawerRow {
  label: string | null = null;
  displayName: string = '';
  count: number = 0;

  constructor(label: string | null, displayName: string, count: number) {
    this.label = label;
    this.displayName = displayName;
    this.count = count;
  }
}

@Observed
class ArchiverRowModel {
  gid: number = 0;
  taskId: number = 0;
  title: string = '';
  uploader: string = '';
  categoryLabel: string = '';
  readProgress: string = '';
  stateText: string = '';
  percentText: string = '';
  speedText: string = '';
  progressValue: number = 0;
  rating: number = -1;
  thumb: string = '';
  thumbKey: string = '';
  showStart: boolean = false;
  showStop: boolean = false;
  showCancel: boolean = false;
  showState: boolean = false;
  showPercent: boolean = false;
  showSpeed: boolean = false;
  importing: boolean = false;
  paused: boolean = false;
  snapshot: ArchiverTaskSnapshot;

  constructor(
    snapshot: ArchiverTaskSnapshot,
    displayTitle: string,
    categoryLabel: string,
    stateText: string,
    percentText: string
  ) {
    this.snapshot = snapshot;
    this.gid = snapshot.gid;
    this.taskId = snapshot.taskId;
    this.updateFrom(snapshot, displayTitle, categoryLabel, stateText, percentText);
  }

  updateFrom(
    task: ArchiverTaskSnapshot,
    displayTitle: string,
    categoryLabel: string,
    stateText: string,
    percentText: string
  ): void {
    this.snapshot = task;
    if (this.title !== displayTitle) {
      this.title = displayTitle;
    }
    if (this.uploader !== task.uploader) {
      this.uploader = task.uploader;
    }
    if (this.categoryLabel !== categoryLabel) {
      this.categoryLabel = categoryLabel;
    }
    const nextReadProgress: string = task.pages > 0 ? `${task.pages}P` : '';
    if (this.readProgress !== nextReadProgress) {
      this.readProgress = nextReadProgress;
    }
    if (this.stateText !== stateText) {
      this.stateText = stateText;
    }
    if (this.percentText !== percentText) {
      this.percentText = percentText;
    }
    const nextSpeed: string = task.paused || task.importing
      ? ''
      : (FileUtils.humanReadableByteCount(Math.max(0, task.speed), false) + '/S');
    if (this.speedText !== nextSpeed) {
      this.speedText = nextSpeed;
    }
    const nextProgress: number = task.importing
      ? 100
      : (task.total > 0 ? Math.min(100, Math.floor(task.downloaded * 100 / task.total)) : 0);
    if (this.progressValue !== nextProgress) {
      this.progressValue = nextProgress;
    }
    if (this.rating !== task.rating) {
      this.rating = task.rating;
    }
    if (this.thumb !== task.thumb) {
      this.thumb = task.thumb;
    }
    const nextThumbKey: string = EhCacheKeyFactory.getThumbKey(task.gid);
    if (this.thumbKey !== nextThumbKey) {
      this.thumbKey = nextThumbKey;
    }
    const nextShowStart: boolean = !task.importing && task.paused;
    if (this.showStart !== nextShowStart) {
      this.showStart = nextShowStart;
    }
    const nextShowStop: boolean = !task.importing && !task.paused;
    if (this.showStop !== nextShowStop) {
      this.showStop = nextShowStop;
    }
    const nextShowCancel: boolean = !task.importing;
    if (this.showCancel !== nextShowCancel) {
      this.showCancel = nextShowCancel;
    }
    const nextShowState: boolean = task.importing || task.paused;
    if (this.showState !== nextShowState) {
      this.showState = nextShowState;
    }
    const nextShowPercent: boolean = !task.importing;
    if (this.showPercent !== nextShowPercent) {
      this.showPercent = nextShowPercent;
    }
    const nextShowSpeed: boolean = !task.importing && !task.paused;
    if (this.showSpeed !== nextShowSpeed) {
      this.showSpeed = nextShowSpeed;
    }
    if (this.importing !== task.importing) {
      this.importing = task.importing;
    }
    if (this.paused !== task.paused) {
      this.paused = task.paused;
    }
  }
}

@Observed
class DownloadRowModel {
  gid: number = 0;
  title: string = '';
  uploader: string = '';
  categoryLabel: string = '';
  categoryColor: ResourceColor = '#FF607D8B';
  readProgress: string = '';
  stateText: string = '';
  percentText: string = '';
  speedText: string = '';
  progressValue: number = 0;
  progressTotal: number = 100;
  rating: number = -1;
  thumb: string = '';
  thumbKey: string = '';
  showStart: boolean = false;
  showStop: boolean = false;
  showState: boolean = true;
  showProgress: boolean = false;
  showPercent: boolean = false;
  showSpeed: boolean = false;
  selected: boolean = false;
  info: DownloadInfo;

  constructor(
    info: DownloadInfo,
    displayTitle: string,
    stateText: string,
    percentText: string,
    speedText: string,
    selected: boolean
  ) {
    this.info = info;
    this.gid = info.gid;
    this.updateFrom(info, displayTitle, stateText, percentText, speedText, selected);
  }

  updateFrom(
    info: DownloadInfo,
    displayTitle: string,
    stateText: string,
    percentText: string,
    speedText: string,
    selected: boolean
  ): void {
    this.info = info;
    if (this.title !== displayTitle) {
      this.title = displayTitle;
    }
    if (this.uploader !== info.uploader) {
      this.uploader = info.uploader;
    }
    const nextCategoryLabel: string = GalleryListClient.formatCategoryLabel(info.category);
    if (this.categoryLabel !== nextCategoryLabel) {
      this.categoryLabel = nextCategoryLabel;
    }
    const nextCategoryColor: ResourceColor = GalleryListClient.formatCategoryColor(info.category);
    if (this.categoryColor !== nextCategoryColor) {
      this.categoryColor = nextCategoryColor;
    }
    const nextReadProgress: string = info.pages > 0 ? `${info.pages}P` : '';
    if (this.readProgress !== nextReadProgress) {
      this.readProgress = nextReadProgress;
    }
    if (this.stateText !== stateText) {
      this.stateText = stateText;
    }
    if (this.percentText !== percentText) {
      this.percentText = percentText;
    }
    if (this.speedText !== speedText) {
      this.speedText = speedText;
    }
    const nextProgressValue: number = info.finished > 0 ? info.finished : info.downloaded;
    if (this.progressValue !== nextProgressValue) {
      this.progressValue = nextProgressValue;
    }
    const nextProgressTotal: number = info.total > 0 ? info.total : (info.pages > 0 ? info.pages : 100);
    if (this.progressTotal !== nextProgressTotal) {
      this.progressTotal = nextProgressTotal;
    }
    if (this.rating !== info.rating) {
      this.rating = info.rating;
    }
    if (this.thumb !== info.thumb) {
      this.thumb = info.thumb;
    }
    const nextThumbKey: string = EhCacheKeyFactory.getThumbKey(info.gid);
    if (this.thumbKey !== nextThumbKey) {
      this.thumbKey = nextThumbKey;
    }
    const nextShowStart: boolean = info.state === DownloadInfo.STATE_NONE || info.state === DownloadInfo.STATE_FAILED;
    if (this.showStart !== nextShowStart) {
      this.showStart = nextShowStart;
    }
    const nextShowStop: boolean = info.state === DownloadInfo.STATE_WAIT || info.state === DownloadInfo.STATE_DOWNLOAD;
    if (this.showStop !== nextShowStop) {
      this.showStop = nextShowStop;
    }
    const nextShowState: boolean = info.state !== DownloadInfo.STATE_DOWNLOAD;
    if (this.showState !== nextShowState) {
      this.showState = nextShowState;
    }
    const nextShowProgress: boolean = info.state === DownloadInfo.STATE_DOWNLOAD;
    if (this.showProgress !== nextShowProgress) {
      this.showProgress = nextShowProgress;
    }
    const nextShowPercent: boolean = info.state === DownloadInfo.STATE_DOWNLOAD && info.total > 0;
    if (this.showPercent !== nextShowPercent) {
      this.showPercent = nextShowPercent;
    }
    const nextShowSpeed: boolean = info.state === DownloadInfo.STATE_DOWNLOAD;
    if (this.showSpeed !== nextShowSpeed) {
      this.showSpeed = nextShowSpeed;
    }
    if (this.selected !== selected) {
      this.selected = selected;
    }
  }
}

@Component
struct ArchiverRowCard {
  @ObjectLink row: ArchiverRowModel;
  @Prop themeId: number = -1;
  onStartTask: (gid: number) => void = (): void => {};
  onPauseTask: (gid: number) => void = (): void => {};
  onCancelTask: (task: ArchiverTaskSnapshot) => void = (): void => {};
  onLongPressTask: (task: ArchiverTaskSnapshot) => void = (): void => {};

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  build() {
    DownloadItemLayout({
      title: this.row.title,
      uploader: this.row.uploader,
      category: this.row.categoryLabel,
      categoryBgColor: this.palette().colorAccent,
      readProgress: this.row.readProgress,
      state: this.row.stateText,
      percent: this.row.percentText,
      speed: this.row.speedText,
      progressValue: this.row.progressValue,
      progressTotal: 100,
      rating: this.row.rating,
      thumbUrl: this.row.thumb,
      thumbKey: this.row.thumbKey,
      showStart: this.row.showStart,
      showStop: this.row.showStop,
      showCancel: this.row.showCancel,
      showState: this.row.showState,
      showProgress: true,
      showPercent: this.row.showPercent,
      showSpeed: this.row.showSpeed,
      selectionMode: false,
      selected: false,
      themeId: this.themeId,
      cardColor: this.palette().cardBackground,
      titleColor: this.palette().textPrimary,
      messageColor: this.palette().textSecondary,
      accentTextColor: this.palette().textThemeAccent,
      progressColor: this.palette().progressColor,
      onThumbClick: () => {},
      onStartClick: () => {
        if (!this.row.importing) {
          this.onStartTask(this.row.gid);
        }
      },
      onStopClick: () => {
        if (!this.row.importing) {
          this.onPauseTask(this.row.gid);
        }
      },
      onCancelClick: () => {
        if (!this.row.importing) {
          this.onCancelTask(this.row.snapshot);
        }
      }
    })
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction(() => {
            if (MainPageHost.shouldSuppressClick() || this.row.importing) {
              return;
            }
            this.onLongPressTask(this.row.snapshot);
          })
      )
  }
}

@Component
struct DownloadRowCard {
  @ObjectLink row: DownloadRowModel;
  @Prop themeId: number = -1;
  @Prop selectionMode: boolean = false;
  onCardClick: (info: DownloadInfo) => void = (): void => {};
  onCardLongPress: (info: DownloadInfo) => void = (): void => {};
  onStartItem: (info: DownloadInfo) => void = (): void => {};
  onStopItem: (info: DownloadInfo) => void = (): void => {};

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  build() {
    DownloadItemLayout({
      title: this.row.title,
      uploader: this.row.uploader,
      category: this.row.categoryLabel,
      categoryBgColor: this.row.categoryColor,
      readProgress: this.row.readProgress,
      state: this.row.stateText,
      percent: this.row.percentText,
      speed: this.row.speedText,
      progressValue: this.row.progressValue,
      progressTotal: this.row.progressTotal,
      rating: this.row.rating,
      thumbUrl: this.row.thumb,
      thumbKey: this.row.thumbKey,
      showStart: this.row.showStart,
      showStop: this.row.showStop,
      showState: this.row.showState,
      showProgress: this.row.showProgress,
      showPercent: this.row.showPercent,
      showSpeed: this.row.showSpeed,
      selectionMode: this.selectionMode,
      selected: this.row.selected,
      themeId: this.themeId,
      cardColor: this.palette().cardBackground,
      titleColor: this.palette().textPrimary,
      messageColor: this.palette().textSecondary,
      accentTextColor: this.palette().textThemeAccent,
      progressColor: this.palette().progressColor,
      onThumbClick: () => {
        this.onCardClick(this.row.info);
      },
      onStartClick: () => {
        if (!this.selectionMode) {
          this.onStartItem(this.row.info);
        }
      },
      onStopClick: () => {
        if (!this.selectionMode) {
          this.onStopItem(this.row.info);
        }
      }
    })
      .onClick(() => {
        if (MainPageHost.shouldSuppressClick()) {
          return;
        }
        this.onCardClick(this.row.info);
      })
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction(() => {
            if (MainPageHost.shouldSuppressClick()) {
              return;
            }
            this.onCardLongPress(this.row.info);
          })
      )
  }
}

class DownloadsSceneObserver implements DownloadInfoListener {
  private readonly onChanged: () => void;

  constructor(onChanged: () => void) {
    this.onChanged = onChanged;
  }

  onAdd(_info: DownloadInfo, _list: DownloadInfo[], _position: number): void {
    this.onChanged();
  }

  onReplace(_newInfo: DownloadInfo, _oldInfo: DownloadInfo): void {
    this.onChanged();
  }

  onUpdate(_info: DownloadInfo, _list: DownloadInfo[], _waitList: DownloadInfo[]): void {
    this.onChanged();
  }

  onUpdateAll(): void {
    this.onChanged();
  }

  onReload(): void {
    this.onChanged();
  }

  onChange(): void {
    this.onChanged();
  }

  onRenameLabel(_from: string, _to: string): void {
    this.onChanged();
  }

  onRemove(_info: DownloadInfo, _list: DownloadInfo[], _position: number): void {
    this.onChanged();
  }

  onUpdateLabels(): void {
    this.onChanged();
  }
}

class DownloadsSceneViewAdapter implements DownloadAdapterLike {
  private readonly onNotify: () => void;
  private readonly onCount: () => number;

  constructor(onNotify: () => void, onCount: () => number) {
    this.onNotify = onNotify;
    this.onCount = onCount;
  }

  notifyDataSetChanged(): void {
    this.onNotify();
  }

  getItemCount(): number {
    return this.onCount();
  }

  isDragEnable(): boolean {
    return Settings.getDragDownloadGallery();
  }
}

class DownloadsArchiverListener implements ArchiverDownloaderListener {
  private readonly onSyncActive: () => void;
  private readonly onCompleted: () => void;

  constructor(onSyncActive: () => void, onCompleted: () => void) {
    this.onSyncActive = onSyncActive;
    this.onCompleted = onCompleted;
  }

  onProgress(_gid: number, _downloaded: number, _total: number, _speed: number, _paused: boolean): void {
    this.onSyncActive();
  }

  onSuccess(_gid: number, _taskId: number, _zipPath: string): void {
    this.onCompleted();
  }

  onFailure(_gid: number, _taskId: number, _e: Error): void {
    this.onSyncActive();
  }

  onCancel(_gid: number, _taskId: number): void {
    this.onSyncActive();
  }
}

@Component
export struct DownloadsSceneView {
  shell: DownloadsSceneShell | null = null;
  onOpenDrawer: () => void = (): void => {
  };
  @Prop themeId: number = -1;
  @StorageLink(APP_SHOW_JPN_TITLE_STORAGE_KEY) @Watch('onShowJpnTitleChanged') showJpnTitlePref: boolean =
    Settings.getShowJpnTitle();
  @Prop @Watch('onRightDrawerOpenSignal') rightDrawerOpenSignal: number = 0;
  @Prop @Watch('onRightDrawerCloseSignal') rightDrawerCloseSignal: number = 0;
  @Prop @Watch('onRightDrawerDragChanged') rightDrawerDragActive: boolean = false;
  @Prop @Watch('onRightDrawerDragChanged') rightDrawerDragProgress: number = 0;
  @Prop @Watch('onRightDrawerDragEnded') rightDrawerDragEndSeq: number = 0;
  @Prop rightDrawerDragSettleOpen: boolean = false;
  onRightDrawerStateChange: (open: boolean) => void = (): void => {
  };
  onSwipeBlockChange: (blocked: boolean) => void = (): void => {
  };

  @State items: DownloadInfo[] = [];
  @State activeArchiverTasks: ArchiverTaskSnapshot[] = [];
  @State archiverRows: ArchiverRowModel[] = [];
  @State downloadRows: DownloadRowModel[] = [];
  @State labelText: string = '';
  @State lastError: string = '';
  @State labelDrawerOpen: boolean = false;
  @State labelRows: LabelDrawerRow[] = [];
  @State selectedArchiverForMenu: ArchiverTaskSnapshot | null = null;
  @State pendingCancelArchiver: ArchiverTaskSnapshot | null = null;
  @State selectionMode: boolean = false;
  @State selectedGids: number[] = [];
  @State showLabelPickerDialog: boolean = false;
  @State showBatchDeleteDialog: boolean = false;
  @State batchDeleteRemoveFiles: boolean = false;
  @State pendingBatchDeleteItems: DownloadInfo[] = [];
  @State showBatchMoveDialog: boolean = false;
  @State pendingBatchMoveItems: DownloadInfo[] = [];
  @State rev: number = 0;
  @State paginationActive: boolean = false;
  @State paginationCurrentPage: number = 1;
  @State paginationTotalPages: number = 1;

  private readonly fabState: FabBehaviorState = new FabBehaviorState();
  private readonly listScroller: ListScroller = new ListScroller();
  private paginationController: DownloadPaginationController | null = null;
  private archiverRowMap: Map<string, ArchiverRowModel> = new Map<string, ArchiverRowModel>();
  private downloadRowMap: Map<number, DownloadRowModel> = new Map<number, DownloadRowModel>();
  private hostContext: common.Context | undefined = undefined;
  private downloadManager: DownloadManager | null = null;
  private dmListener: DownloadsSceneObserver | null = null;
  private archiverListener: DownloadsArchiverListener | null = null;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  @State labelDrawerOffsetX: number = ThemeDimens.DRAWER_MAX_WIDTH;
  @State labelDrawerScrimOpacity: number = 0;
  private labelDrawerClosing: boolean = false;
  private lastRightDragEndSeq: number = 0;

  private onRightDrawerDragChanged(): void {
    if (!this.rightDrawerDragActive || this.selectionMode) {
      return;
    }
    const p: number = Math.max(0, Math.min(1, this.rightDrawerDragProgress));
    this.labelDrawerClosing = false;
    if (!this.labelDrawerOpen) {
      this.refreshLabels();
    }
    this.labelDrawerOpen = true;
    this.labelDrawerOffsetX = ThemeDimens.DRAWER_MAX_WIDTH * (1 - p);
    this.labelDrawerScrimOpacity = p;
  }

  private onRightDrawerDragEnded(): void {
    if (this.rightDrawerDragEndSeq === this.lastRightDragEndSeq) {
      return;
    }
    this.lastRightDragEndSeq = this.rightDrawerDragEndSeq;
    if (!this.labelDrawerOpen) {
      return;
    }
    if (this.rightDrawerDragSettleOpen && !this.selectionMode) {
      this.labelDrawerClosing = false;
      this.onRightDrawerStateChange(true);
      this.refreshLabels();
      this.getUIContext().animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
        this.labelDrawerOffsetX = 0;
        this.labelDrawerScrimOpacity = 1;
      });
    } else {
      this.setLabelDrawerOpen(false);
    }
  }

  private setLabelDrawerOpen(open: boolean): void {
    if (open) {
      if (this.selectionMode) {
        return;
      }
      this.labelDrawerClosing = false;
      this.labelDrawerOffsetX = ThemeDimens.DRAWER_MAX_WIDTH;
      this.labelDrawerScrimOpacity = 0;
      this.labelDrawerOpen = true;
      this.onRightDrawerStateChange(true);
      this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
        this.labelDrawerOffsetX = 0;
        this.labelDrawerScrimOpacity = 1;
      });
      return;
    }
    if (!this.labelDrawerOpen || this.labelDrawerClosing) {
      return;
    }
    this.labelDrawerClosing = true;
    this.onRightDrawerStateChange(false);
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.FastOutLinearIn,
      onFinish: (): void => {
        this.labelDrawerOpen = false;
        this.labelDrawerClosing = false;
      }
    }, (): void => {
      this.labelDrawerOffsetX = ThemeDimens.DRAWER_MAX_WIDTH;
      this.labelDrawerScrimOpacity = 0;
    });
  }

  private onRightDrawerOpenSignal(): void {
    if (this.rightDrawerOpenSignal <= 0 || this.selectionMode) {
      return;
    }
    this.refreshLabels();
    this.setLabelDrawerOpen(true);
  }

  private onRightDrawerCloseSignal(): void {
    if (this.rightDrawerCloseSignal <= 0) {
      return;
    }
    if (this.labelDrawerOpen) {
      this.setLabelDrawerOpen(false);
    }
  }

  private onShowJpnTitleChanged(): void {
    this.syncActiveArchiverTasks();
    this.syncDownloadRows();
  }

  private archiverTitle(task: ArchiverTaskSnapshot): string {
    if (Settings.getShowJpnTitle() && task.titleJpn.length > 0) {
      return task.titleJpn;
    }
    if (task.title.length > 0) {
      return task.title;
    }
    return task.titleJpn.length > 0 ? task.titleJpn : task.fileName;
  }

  private str(key: string): string {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        return ctx.resourceManager.getStringByNameSync(key);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'getStringByNameSync failed for %{public}s: %{public}s',
          key, JSON.stringify(err));
      }
    }
    return GetText.getString(key);
  }

  aboutToAppear(): void {
    this.lastRightDragEndSeq = this.rightDrawerDragEndSeq;
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    this.hostContext = ctx;
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }

    const pCtrl: DownloadPaginationController = new DownloadPaginationController(
      new DownloadsPaginationHost(
        (): number => this.items.length,
        (): void => {
          this.syncDownloadRows();
        },
        (pos: number): void => {
          try {
            this.listScroller.scrollToIndex(pos >= 0 ? 0 : 0);
          } catch (scrollErr) {
            hilog.debug(DOMAIN, TAG, 'scrollToIndex skipped: %{public}s',
              scrollErr instanceof Error ? scrollErr.message : String(scrollErr));
          }
        }
      )
    );
    pCtrl.indicator = new DownloadsPaginationIndicator(
      (total: number): void => {
        this.paginationTotalPages = Math.max(1, total);
      },
      (page: number): void => {
        this.paginationCurrentPage = Math.max(1, page);
      }
    );
    pCtrl.pageSize = 100;
    pCtrl.isCanPagination = Settings.isAttached()
      ? Settings.getDownloadPagination()
      : Settings.IS_DOWNLOAD_LIST_PAGINATION;
    this.paginationController = pCtrl;

    // autoCancel=false 避免多选展开 6 个次级 FAB 时全屏遮罩拦截列表点击
    this.fabState.setAutoCancel(false);
    this.fabState.setExpanded(false, false);
    this.fabState.setOnClickFabListener(new OnClickFabListenerImpl(
      (): void => {
        this.onPrimaryFabClick();
      },
      (_layout: FabBehaviorState, index: number): void => {
        this.onSecondaryFabClick(index);
      }
    ));

    const sh: DownloadsSceneShell | null = this.shell;
    if (sh === null) {
      this.lastError = 'DownloadsSceneShell is null';
      return;
    }
    sh.getLogic().setBackInterceptor((): boolean => this.handleBackPress());
    try {
      sh.getLogic().setAdapter(new DownloadsSceneViewAdapter(
        (): void => {
          this.rev = this.rev + 1;
        },
        (): number => this.items.length
      ));
      sh.getLogic().handleArguments(sh.getArguments());
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      hilog.warn(DOMAIN, TAG, 'handleArguments failed: %{public}s', msg);
    }
    this.syncActiveArchiverTasks();
    const archObserver: DownloadsArchiverListener = new DownloadsArchiverListener(
      (): void => {
        this.syncActiveArchiverTasks();
      },
      (): void => {
        this.syncActiveArchiverTasks();
        this.refresh();
      }
    );
    this.archiverListener = archObserver;
    ArchiverDownloader.getInstance().addListener(archObserver);
    this.refresh();

    DownloadManager.getInstance().then((dm: DownloadManager): void => {
      this.downloadManager = dm;
      const listener: DownloadsSceneObserver = new DownloadsSceneObserver((): void => {
        this.refresh();
      });
      this.dmListener = listener;
      dm.addDownloadInfoListener(listener);
      this.refresh();
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'DownloadManager.getInstance failed: %{public}s', e.message);
    });
  }

  aboutToDisappear(): void {
    this.onSwipeBlockChange(false);
    this.fabState.setOnClickFabListener(null);
    if (this.downloadManager !== null && this.dmListener !== null) {
      this.downloadManager.removeDownloadInfoListener(this.dmListener);
    }
    if (this.archiverListener !== null) {
      ArchiverDownloader.getInstance().removeListener(this.archiverListener);
    }
    if (this.shell !== null) {
      this.shell.getLogic().setBackInterceptor(null);
      this.shell.getLogic().setAdapter(null);
    }
    this.archiverListener = null;
    this.dmListener = null;
    this.downloadManager = null;
  }

  private syncActiveArchiverTasks(): void {
    const tasks: ArchiverTaskSnapshot[] = ArchiverDownloader.getInstance().getActiveTasks();
    this.activeArchiverTasks = tasks;

    const categoryText: string = archiverLabel();
    const nextRows: ArchiverRowModel[] = [];
    const aliveKeys: Set<string> = new Set<string>();
    let sameOrder: boolean = tasks.length === this.archiverRows.length;

    for (let i = 0; i < tasks.length; i++) {
      const task: ArchiverTaskSnapshot = tasks[i];
      const mapKey: string = `${task.gid}_${task.taskId}`;
      aliveKeys.add(mapKey);
      const stateText: string = task.importing
        ? '正在解压导入…'
        : (task.paused ? this.str('archiver_download_paused') : this.str('download_state_downloading'));
      const percentText: string = this.archiverPercentText(task);
      const displayTitle: string = this.archiverTitle(task);
      let row: ArchiverRowModel | undefined = this.archiverRowMap.get(mapKey);
      if (row === undefined) {
        row = new ArchiverRowModel(task, displayTitle, categoryText, stateText, percentText);
        this.archiverRowMap.set(mapKey, row);
        sameOrder = false;
      } else {
        row.updateFrom(task, displayTitle, categoryText, stateText, percentText);
        if (sameOrder) {
          const prev: ArchiverRowModel = this.archiverRows[i];
          if (prev.gid !== row.gid || prev.taskId !== row.taskId) {
            sameOrder = false;
          }
        }
      }
      nextRows.push(row);
    }

    const oldKeys: string[] = Array.from(this.archiverRowMap.keys());
    for (let i = 0; i < oldKeys.length; i++) {
      if (!aliveKeys.has(oldKeys[i])) {
        this.archiverRowMap.delete(oldKeys[i]);
      }
    }

    if (!sameOrder) {
      this.archiverRows = nextRows;
    }
  }

  private syncDownloadRows(): void {
    const pCtrl: DownloadPaginationController | null = this.paginationController;
    let list: DownloadInfo[] = this.items;
    if (pCtrl !== null) {
      pCtrl.isCanPagination = Settings.isAttached()
        ? Settings.getDownloadPagination()
        : Settings.IS_DOWNLOAD_LIST_PAGINATION;
      pCtrl.refreshTotal();
      this.paginationActive = pCtrl.shouldPagination();
      this.paginationCurrentPage = Math.max(1, pCtrl.indexPage);
      this.paginationTotalPages = Math.max(1, pCtrl.getTotalPages());
      if (this.paginationActive) {
        const startIdx: number = (this.paginationCurrentPage - 1) * pCtrl.pageSize;
        list = this.items.slice(startIdx, startIdx + pCtrl.pageSize);
      }
    } else {
      this.paginationActive = false;
      this.paginationCurrentPage = 1;
      this.paginationTotalPages = 1;
    }
    const nextRows: DownloadRowModel[] = [];
    const aliveGids: Set<number> = new Set<number>();
    let sameOrder: boolean = list.length === this.downloadRows.length;

    for (let i = 0; i < list.length; i++) {
      const item: DownloadInfo = list[i];
      aliveGids.add(item.gid);
      const title: string = this.itemTitle(item);
      const stateText: string = this.stateText(item);
      const percentText: string = this.percentText(item);
      const speedText: string = this.speedText(item);
      const isSelected: boolean = this.selectionMode && this.selectedGids.indexOf(item.gid) >= 0;

      let row: DownloadRowModel | undefined = this.downloadRowMap.get(item.gid);
      if (row === undefined) {
        row = new DownloadRowModel(item, title, stateText, percentText, speedText, isSelected);
        this.downloadRowMap.set(item.gid, row);
        sameOrder = false;
      } else {
        row.updateFrom(item, title, stateText, percentText, speedText, isSelected);
        if (sameOrder && this.downloadRows[i].gid !== row.gid) {
          sameOrder = false;
        }
      }
      nextRows.push(row);
    }

    const oldGids: number[] = Array.from(this.downloadRowMap.keys());
    for (let i = 0; i < oldGids.length; i++) {
      if (!aliveGids.has(oldGids[i])) {
        this.downloadRowMap.delete(oldGids[i]);
      }
    }

    if (!sameOrder) {
      this.downloadRows = nextRows;
    }
  }

  /** 读一次数据（先按当前标签向 DownloadManager 拉取列表，再同步视图状态） */
  private refresh(): void {
    const sh: DownloadsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    try {
      const logic = sh.getLogic();
      logic.updateForLabel();
      const label: string | null = logic.getLabel();
      this.labelText = label === null ? '' : label;
      const list: DownloadInfo[] = logic.getList();
      this.items = list.slice();
      if (this.selectionMode && this.selectedGids.length > 0) {
        const filtered: number[] = [];
        for (let i = 0; i < this.selectedGids.length; i++) {
          const gid: number = this.selectedGids[i];
          if (this.items.some((it: DownloadInfo): boolean => it.gid === gid)) {
            filtered.push(gid);
          }
        }
        if (filtered.length !== this.selectedGids.length) {
          this.selectedGids = filtered;
        }
      }
      this.syncDownloadRows();
      this.lastError = '';
      this.refreshLabels();
    } catch (e) {
      this.items = [];
      this.downloadRows = [];
      this.lastError = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'refresh failed: %{public}s', this.lastError);
    }
  }

  private refreshLabels(): void {
    const dm: DownloadManager | null = this.downloadManager;
    if (dm === null) {
      return;
    }
    try {
      const rows: LabelDrawerRow[] = [];
      const defaultCount: number = dm.getDefaultDownloadInfoList().length;
      rows.push(new LabelDrawerRow(null, this.str('default_download_label_name'), defaultCount));
      const labels: DownloadLabel[] = dm.getLabelList();
      for (let i = 0; i < labels.length; i++) {
        const raw: string | null = labels[i].getLabel();
        if (raw !== null && raw.length > 0) {
          const list: DownloadInfo[] | null = dm.getLabelDownloadInfoList(raw);
          const count: number = list !== null ? list.length : 0;
          rows.push(new LabelDrawerRow(raw, raw, count));
        }
      }
      this.labelRows = rows;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'refreshLabels failed: %{public}s', (e as Error).message);
    }
  }

  private itemTitle(item: DownloadInfo): string {
    const suitable: string | null = EhUtils.getSuitableTitle(item);
    if (suitable !== null && suitable.length > 0) {
      return suitable;
    }
    return item.label === null ? ('#' + item.gid.toString()) : item.label;
  }

  private toolbarTitleText(): string {
    const baseName: string = this.labelText.length > 0
      ? this.labelText
      : this.str('default_download_label_name');
    const countText: string = `${this.items.length}`;
    const fmt: string = this.str('scene_download_title_new');
    if (fmt.indexOf('%s') >= 0) {
      return fmt.replace('%s', baseName).replace('%s', countText);
    }
    return `${baseName} (${countText})`;
  }

  private stateText(item: DownloadInfo): string {
    switch (item.state) {
      case DownloadInfo.STATE_NONE:
        return this.str('download_state_none');
      case DownloadInfo.STATE_WAIT:
        return this.str('download_state_wait');
      case DownloadInfo.STATE_DOWNLOAD:
        return this.str('download_state_downloading');
      case DownloadInfo.STATE_FINISH:
        if (item.legacy > 0) {
          const fmt: string = this.str('download_state_failed_2');
          if (fmt.indexOf('%d') >= 0) {
            return fmt.replace('%d', `${item.legacy}`);
          }
          return `${item.legacy}`;
        }
        return this.str('download_state_finish');
      case DownloadInfo.STATE_FAILED:
        return this.str('download_state_failed');
      default:
        return this.str('download_state_none');
    }
  }

  private speedText(item: DownloadInfo): string {
    const bytes: number = item.speed < 0 ? 0 : item.speed;
    return FileUtils.humanReadableByteCount(bytes, false) + '/S';
  }

  private percentText(item: DownloadInfo): string {
    if (item.total > 0) {
      return `${item.finished}/${item.total}`;
    }
    return '';
  }

  private archiverPercentText(task: ArchiverTaskSnapshot): string {
    const dlText: string = FileUtils.humanReadableByteCount(Math.max(0, task.downloaded), false);
    if (task.total > 0) {
      const pct: number = Math.min(100, Math.max(0, Math.round(task.downloaded * 100 / task.total)));
      const totalText: string = FileUtils.humanReadableByteCount(task.total, false);
      return `${pct}% · ${dlText}/${totalText}`;
    }
    return dlText;
  }

  private hasNonEmptyAlternateLabels(): boolean {
    if (this.labelText !== '') {
      return false;
    }
    for (let i = 0; i < this.labelRows.length; i++) {
      if (this.labelRows[i].label !== null && this.labelRows[i].count > 0) {
        return true;
      }
    }
    return false;
  }

  private startItem(item: DownloadInfo): void {
    const dm: DownloadManager | null = this.downloadManager;
    if (dm !== null) {
      dm.startDownload(item, item.label).then((): void => {
        this.refresh();
      }).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'startDownload failed: %{public}s', e.message);
      });
      return;
    }
    DownloadManager.getInstance().then((inst: DownloadManager): Promise<void> => {
      this.downloadManager = inst;
      return inst.startDownload(item, item.label);
    }).then((): void => {
      this.refresh();
    }).catch((e: Error): void => {
      hilog.error(DOMAIN, TAG, 'startDownload failed: %{public}s', e.message);
    });
  }

  private stopItem(item: DownloadInfo): void {
    const dm: DownloadManager | null = this.downloadManager;
    if (dm !== null) {
      dm.stopDownload(item.gid).then((): void => {
        this.refresh();
      }).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'stopDownload failed: %{public}s', e.message);
      });
      return;
    }
    DownloadManager.getInstance().then((inst: DownloadManager): Promise<void> => {
      this.downloadManager = inst;
      return inst.stopDownload(item.gid);
    }).then((): void => {
      this.refresh();
    }).catch((e: Error): void => {
      hilog.error(DOMAIN, TAG, 'stopDownload failed: %{public}s', e.message);
    });
  }

  private deleteItem(item: DownloadInfo): void {
    const dm: DownloadManager | null = this.downloadManager;
    if (dm !== null) {
      dm.deleteDownload(item.gid).then((): void => {
        this.refresh();
      }).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'deleteDownload failed: %{public}s', e.message);
      });
      return;
    }
    DownloadManager.getInstance().then((inst: DownloadManager): Promise<void> => {
      this.downloadManager = inst;
      return inst.deleteDownload(item.gid);
    }).then((): void => {
      this.refresh();
    }).catch((e: Error): void => {
      hilog.error(DOMAIN, TAG, 'deleteDownload failed: %{public}s', e.message);
    });
  }

  private handleStartAll(): void {
    const dm: DownloadManager | null = this.downloadManager;
    if (dm !== null) {
      dm.startAllDownload().then((): void => {
        this.refresh();
      }).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'startAllDownload failed: %{public}s', e.message);
      });
      return;
    }
    DownloadManager.getInstance().then((inst: DownloadManager): Promise<void> => {
      this.downloadManager = inst;
      return inst.startAllDownload();
    }).then((): void => {
      this.refresh();
    }).catch((e: Error): void => {
      hilog.error(DOMAIN, TAG, 'startAllDownload failed: %{public}s', e.message);
    });
  }

  private handleStopAll(): void {
    const dm: DownloadManager | null = this.downloadManager;
    if (dm !== null) {
      dm.stopAllDownload().then((): void => {
        this.refresh();
      }).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'stopAllDownload failed: %{public}s', e.message);
      });
      return;
    }
    DownloadManager.getInstance().then((inst: DownloadManager): Promise<void> => {
      this.downloadManager = inst;
      return inst.stopAllDownload();
    }).then((): void => {
      this.refresh();
    }).catch((e: Error): void => {
      hilog.error(DOMAIN, TAG, 'stopAllDownload failed: %{public}s', e.message);
    });
  }

  private openReader(item: DownloadInfo): void {
    const title: string = this.itemTitle(item);
    const detailUrl: string = item.gid > 0 && item.token.length > 0
      ? EhUrl.getGalleryDetailUrl(item.gid, item.token, 0, false) : '';
    const params: GalleryReaderRouteParams = new GalleryReaderRouteParams(
      item.gid,
      item.token,
      0,
      item.pages,
      title,
      detailUrl
    );
    pushGalleryReaderPage(this.getUIContext(), params, TAG);
  }

  /** 观测面（测试断言"渲染了几项"） */
  getItemCount(): number {
    return this.items.length;
  }

  getLastError(): string {
    return this.lastError;
  }

  private openLabelsScene(): void {
    const sh: DownloadsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    try {
      sh.startScene(new Announcer('DownloadLabelsScene'));
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.lastError = msg;
      hilog.warn(DOMAIN, TAG, 'openLabelsScene failed: %{public}s', msg);
    }
  }

  private selectLabel(label: string | null): void {
    const sh: DownloadsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    if (this.selectionMode) {
      this.exitSelectionMode();
    }
    try {
      sh.getLogic().setLabel(label);
      this.refresh();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.lastError = msg;
      hilog.warn(DOMAIN, TAG, 'selectLabel failed: %{public}s', msg);
    }
  }

  private showToastResource(res: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: res, duration: 1500 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showToast skipped: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private handleBackPress(): boolean {
    if (this.showLabelPickerDialog) {
      this.showLabelPickerDialog = false;
      return true;
    }
    if (this.showBatchDeleteDialog) {
      this.showBatchDeleteDialog = false;
      this.pendingBatchDeleteItems = [];
      return true;
    }
    if (this.showBatchMoveDialog) {
      this.showBatchMoveDialog = false;
      this.pendingBatchMoveItems = [];
      return true;
    }
    if (this.pendingCancelArchiver !== null) {
      this.pendingCancelArchiver = null;
      return true;
    }
    if (this.selectedArchiverForMenu !== null) {
      this.selectedArchiverForMenu = null;
      return true;
    }
    if (this.labelDrawerOpen) {
      this.setLabelDrawerOpen(false);
      return true;
    }
    if (this.selectionMode) {
      this.exitSelectionMode();
      return true;
    }
    return false;
  }

  private enterSelectionMode(initialGid: number | null): void {
    if (this.labelDrawerOpen) {
      this.setLabelDrawerOpen(false);
    }
    this.selectionMode = true;
    this.onSwipeBlockChange(true);
    if (initialGid !== null) {
      if (this.selectedGids.indexOf(initialGid) < 0) {
        this.selectedGids = this.selectedGids.concat([initialGid]);
      }
    } else if (this.selectedGids.length > 0) {
      this.selectedGids = [];
    }
    this.syncDownloadRows();
    this.fabState.setExpanded(true, true);
  }

  private exitSelectionMode(): void {
    this.selectionMode = false;
    this.selectedGids = [];
    this.onSwipeBlockChange(false);
    this.fabState.setExpanded(false, true);
    this.syncDownloadRows();
  }

  private toggleSelect(gid: number): void {
    if (!this.selectionMode) {
      this.enterSelectionMode(gid);
      return;
    }
    const idx: number = this.selectedGids.indexOf(gid);
    if (idx >= 0) {
      const next: number[] = this.selectedGids.slice();
      next.splice(idx, 1);
      this.selectedGids = next;
    } else {
      this.selectedGids = this.selectedGids.concat([gid]);
    }
    this.syncDownloadRows();
  }

  private toggleSelectAll(): void {
    if (this.downloadRows.length === 0) {
      this.selectedGids = [];
      this.syncDownloadRows();
      return;
    }
    if (this.selectedGids.length >= this.downloadRows.length) {
      this.selectedGids = [];
    } else {
      const all: number[] = [];
      for (let i = 0; i < this.downloadRows.length; i++) {
        all.push(this.downloadRows[i].gid);
      }
      this.selectedGids = all;
    }
    this.syncDownloadRows();
  }

  private selectedItemsSnapshot(): DownloadInfo[] {
    const out: DownloadInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: DownloadInfo = this.items[i];
      if (this.selectedGids.indexOf(item.gid) >= 0) {
        out.push(item);
      }
    }
    return out;
  }

  private async ensureDownloadManager(): Promise<DownloadManager | null> {
    if (this.downloadManager !== null) {
      return this.downloadManager;
    }
    try {
      const dm: DownloadManager = await DownloadManager.getInstance();
      this.downloadManager = dm;
      return dm;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'DownloadManager.getInstance failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      return null;
    }
  }

  private onPrimaryFabClick(): void {
    if (this.selectionMode) {
      this.exitSelectionMode();
    } else {
      this.enterSelectionMode(null);
    }
  }

  private onSecondaryFabClick(index: number): void {
    if (!this.selectionMode) {
      return;
    }
    switch (index) {
      case 0:
        this.toggleSelectAll();
        break;
      case 1:
        void this.handleBatchStart();
        break;
      case 2:
        void this.handleBatchPause();
        break;
      case 3:
        this.openBatchDeleteDialog();
        break;
      case 4:
        this.openBatchMoveDialog();
        break;
      case 5:
        this.handleRandomRead();
        break;
      default:
        break;
    }
  }

  private async handleBatchStart(): Promise<void> {
    const gids: number[] = this.selectedGids.slice();
    if (gids.length === 0) {
      this.showToastResource($r('app.string.tag_selector_selected_count', 0));
      return;
    }
    const dm: DownloadManager | null = await this.ensureDownloadManager();
    if (dm === null) {
      return;
    }
    try {
      await dm.startRangeDownload(gids);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'startRangeDownload failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    this.exitSelectionMode();
    this.refresh();
  }

  private async handleBatchPause(): Promise<void> {
    const gids: number[] = this.selectedGids.slice();
    if (gids.length === 0) {
      this.showToastResource($r('app.string.tag_selector_selected_count', 0));
      return;
    }
    const dm: DownloadManager | null = await this.ensureDownloadManager();
    if (dm === null) {
      return;
    }
    try {
      await dm.stopRangeDownload(gids);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'stopRangeDownload failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    this.exitSelectionMode();
    this.refresh();
  }

  private openBatchDeleteDialog(): void {
    const selected: DownloadInfo[] = this.selectedItemsSnapshot();
    if (selected.length === 0) {
      this.showToastResource($r('app.string.tag_selector_selected_count', 0));
      return;
    }
    this.pendingBatchDeleteItems = selected;
    this.batchDeleteRemoveFiles = Settings.getRemoveImageFiles();
    this.showBatchDeleteDialog = true;
  }

  private async confirmBatchDelete(): Promise<void> {
    const itemsToDelete: DownloadInfo[] = this.pendingBatchDeleteItems.slice();
    const removeFiles: boolean = this.batchDeleteRemoveFiles;
    this.showBatchDeleteDialog = false;
    this.pendingBatchDeleteItems = [];
    if (itemsToDelete.length === 0) {
      return;
    }
    Settings.putRemoveImageFiles(removeFiles);
    void Settings.flush();

    const dm: DownloadManager | null = await this.ensureDownloadManager();
    if (dm === null) {
      return;
    }
    const gids: number[] = [];
    for (let i = 0; i < itemsToDelete.length; i++) {
      gids.push(itemsToDelete[i].gid);
    }
    try {
      await dm.deleteRangeDownload(gids);
      if (removeFiles) {
        for (let i = 0; i < itemsToDelete.length; i++) {
          const info: DownloadInfo = itemsToDelete[i];
          try {
            const dir: UniFile | null = await SpiderDen.getExistingGalleryDownloadDir(info);
            if (dir !== null) {
              dir.delete();
            }
          } catch (dirErr) {
            hilog.warn(DOMAIN, TAG, 'delete download dir failed gid=%{public}d: %{public}s',
              info.gid, dirErr instanceof Error ? dirErr.message : String(dirErr));
          }
          try {
            await EhDB.removeDownloadDirname(info.gid);
          } catch (dbErr) {
            hilog.warn(DOMAIN, TAG, 'removeDownloadDirname failed gid=%{public}d: %{public}s',
              info.gid, dbErr instanceof Error ? dbErr.message : String(dbErr));
          }
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'deleteRangeDownload failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    this.exitSelectionMode();
    this.refresh();
  }

  private openBatchMoveDialog(): void {
    const selected: DownloadInfo[] = this.selectedItemsSnapshot();
    if (selected.length === 0) {
      this.showToastResource($r('app.string.tag_selector_selected_count', 0));
      return;
    }
    this.refreshLabels();
    this.pendingBatchMoveItems = selected;
    this.showBatchMoveDialog = true;
  }

  private async confirmBatchMove(targetLabel: string | null): Promise<void> {
    const itemsToMove: DownloadInfo[] = this.pendingBatchMoveItems.slice();
    this.showBatchMoveDialog = false;
    this.pendingBatchMoveItems = [];
    if (itemsToMove.length === 0) {
      return;
    }
    const dm: DownloadManager | null = await this.ensureDownloadManager();
    if (dm === null) {
      return;
    }
    try {
      await dm.changeLabel(itemsToMove, targetLabel);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'changeLabel failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
    this.exitSelectionMode();
    this.refresh();
  }

  private handleRandomRead(): void {
    const selected: DownloadInfo[] = this.selectedItemsSnapshot();
    const pool: DownloadInfo[] = selected.length > 0 ? selected : this.items.slice();
    if (pool.length === 0) {
      this.showToastResource($r('app.string.no_download_info'));
      return;
    }
    const idx: number = Math.floor(Math.random() * pool.length);
    const chosen: DownloadInfo = pool[idx];
    if (this.selectionMode) {
      this.exitSelectionMode();
    }
    this.openReader(chosen);
  }

  @Builder
  downloadsPrimaryFab(): void {
    if (this.selectionMode) {
      VPlusDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    } else {
      VCheckDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    }
  }

  @Builder
  downloadsSecondaryFab(index: number): void {
    if (index === 0) {
      VCheckAllDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    } else if (index === 1) {
      VPlayDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    } else if (index === 2) {
      VPauseDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    } else if (index === 3) {
      VDeleteDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    } else if (index === 4) {
      VFolderMoveDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    } else {
      VRandomDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().fabIconColor
      })
    }
  }

  @Builder
  hamburgerIcon(): void {
    Column({ space: 4 }) {
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  archiverContextDialog(task: ArchiverTaskSnapshot): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.selectedArchiverForMenu = null;
        })

      Column() {
        Text(this.archiverTitle(task))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Row() {
          Text(task.paused ? $r('app.string.archiver_download_resume') : $r('app.string.archiver_download_pause'))
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
        .padding({ left: 24, right: 24 })
        .onClick(() => {
          this.selectedArchiverForMenu = null;
          if (task.paused) {
            void ArchiverDownloader.getInstance().resume(task.gid);
          } else {
            ArchiverDownloader.getInstance().pause(task.gid);
          }
        })

        Row() {
          Text($r('app.string.archiver_download_cancel'))
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().errorColor)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
        .padding({ left: 24, right: 24 })
        .onClick(() => {
          this.selectedArchiverForMenu = null;
          this.pendingCancelArchiver = task;
        })

        Row() {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.selectedArchiverForMenu = null;
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 56vp Material Toolbar（常态 vs 多选态）
        if (this.selectionMode) {
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              VCloseDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.exitSelectionMode();
            })

            Text($r('app.string.tag_selector_selected_count', this.selectedGids.length))
              .fontSize(ThemeTypography.TOOLBAR_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().toolbarTitleColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: ThemeDimens.SPACING })

            Stack({ alignContent: Alignment.Center }) {
              VCheckAllDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.toggleSelectAll();
            })
          }
          .width('100%')
          .height(ThemeDimens.TOOLBAR_HEIGHT)
          .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
          .backgroundColor(this.palette().toolbarColor)
          .shadow(ThemeElevation.toolbar())
        } else {
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              this.hamburgerIcon()
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.onOpenDrawer();
            })

            Row({ space: 4 }) {
              Text(`${this.toolbarTitleText()} ▾`)
                .fontSize(ThemeTypography.TOOLBAR_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().toolbarTitleColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .layoutWeight(1)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .alignItems(VerticalAlign.Center)
            .margin({ left: ThemeDimens.SPACING })
            .onClick(() => {
              this.refreshLabels();
              this.showLabelPickerDialog = true;
            })

            Stack({ alignContent: Alignment.Center }) {
              VDownloadBoxDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.refreshLabels();
              this.setLabelDrawerOpen(!this.labelDrawerOpen);
            })

            Stack({ alignContent: Alignment.Center }) {
              VPlayDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.handleStartAll();
            })

            Stack({ alignContent: Alignment.Center }) {
              VPauseDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.handleStopAll();
            })

            Stack({ alignContent: Alignment.Center }) {
              VRefreshDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              this.refresh();
            })
          }
          .width('100%')
          .height(ThemeDimens.TOOLBAR_HEIGHT)
          .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
          .backgroundColor(this.palette().toolbarColor)
          .shadow(ThemeElevation.toolbar())
        }

        if (this.downloadRows.length === 0 && this.archiverRows.length === 0) {
          Column({ space: 16 }) {
            BigDownload({
              iconSize: 120,
              fillColor: this.palette().drawableSecondary
            })
            Text(this.lastError.length > 0 ? this.lastError : $r('app.string.no_download_info'))
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)

            if (this.hasNonEmptyAlternateLabels()) {
              Row({ space: 8 }) {
                ForEach(this.labelRows, (row: LabelDrawerRow) => {
                  if (row.label !== null && row.count > 0) {
                    Button({ type: ButtonType.Normal }) {
                      Text(`${row.displayName} (${row.count})`)
                        .fontSize(ThemeTypography.BUTTON)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.palette().colorPrimary)
                    }
                    .height(36)
                    .padding({ left: 12, right: 12 })
                    .borderRadius(ThemeRadius.BUTTON)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.selectLabel(row.label);
                    })
                  }
                }, (row: LabelDrawerRow) => `empty_${row.label ?? '__default__'}:${row.count}`)
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 0, scroller: this.listScroller }) {
            ForEach(this.archiverRows, (row: ArchiverRowModel) => {
              ListItem() {
                ArchiverRowCard({
                  row: row,
                  themeId: this.themeId,
                  onStartTask: (gid: number): void => {
                    void ArchiverDownloader.getInstance().resume(gid);
                  },
                  onPauseTask: (gid: number): void => {
                    ArchiverDownloader.getInstance().pause(gid);
                  },
                  onCancelTask: (task: ArchiverTaskSnapshot): void => {
                    this.pendingCancelArchiver = task;
                  },
                  onLongPressTask: (task: ArchiverTaskSnapshot): void => {
                    this.selectedArchiverForMenu = task;
                  }
                })
              }
            }, (row: ArchiverRowModel) => `arch_${row.gid}_${row.taskId}`)

            ForEach(this.downloadRows, (row: DownloadRowModel) => {
              ListItem() {
                DownloadRowCard({
                  row: row,
                  themeId: this.themeId,
                  selectionMode: this.selectionMode,
                  onCardClick: (info: DownloadInfo): void => {
                    if (this.selectionMode) {
                      this.toggleSelect(info.gid);
                    } else {
                      this.openReader(info);
                    }
                  },
                  onCardLongPress: (info: DownloadInfo): void => {
                    this.toggleSelect(info.gid);
                  },
                  onStartItem: (info: DownloadInfo): void => {
                    this.startItem(info);
                  },
                  onStopItem: (info: DownloadInfo): void => {
                    this.stopItem(info);
                  }
                })
              }
            }, (row: DownloadRowModel) => `dl_${row.gid}`)
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(2)
          .edgeEffect(EdgeEffect.Spring)
          .padding({
            left: ThemeDimens.GALLERY_LIST_MARGIN_H,
            right: ThemeDimens.GALLERY_LIST_MARGIN_H,
            top: ThemeDimens.GALLERY_LIST_MARGIN_V,
            bottom: this.paginationActive ? 8 : ThemeDimens.GALLERY_PADDING_BOTTOM_FAB
          })

          if (this.paginationActive) {
            Row({ space: 12 }) {
              Button($r('app.string.downloads_page_prev'), { type: ButtonType.Normal })
                .height(34)
                .borderRadius(ThemeRadius.BUTTON)
                .backgroundColor(this.palette().cardBackground)
                .fontColor(this.paginationCurrentPage > 1
                  ? this.palette().colorPrimary
                  : this.palette().textSecondary)
                .fontSize(ThemeTypography.TEXT_SMALL)
                .enabled(this.paginationCurrentPage > 1)
                .onClick((): void => {
                  if (this.paginationController !== null && this.paginationCurrentPage > 1) {
                    this.paginationController.onPageSelected(this.paginationCurrentPage - 1);
                  }
                })

              Text($r('app.string.downloads_page_indicator',
                this.paginationCurrentPage, this.paginationTotalPages, this.items.length))
                .fontSize(ThemeTypography.TEXT_SMALL)
                .fontColor(this.palette().textPrimary)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)

              Button($r('app.string.downloads_page_next'), { type: ButtonType.Normal })
                .height(34)
                .borderRadius(ThemeRadius.BUTTON)
                .backgroundColor(this.palette().cardBackground)
                .fontColor(this.paginationCurrentPage < this.paginationTotalPages
                  ? this.palette().colorPrimary
                  : this.palette().textSecondary)
                .fontSize(ThemeTypography.TEXT_SMALL)
                .enabled(this.paginationCurrentPage < this.paginationTotalPages)
                .onClick((): void => {
                  if (this.paginationController !== null &&
                    this.paginationCurrentPage < this.paginationTotalPages) {
                    this.paginationController.onPageSelected(this.paginationCurrentPage + 1);
                  }
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 12 })
            .backgroundColor(this.palette().windowBackground)
          }
        }
      }
      .width('100%')
      .height('100%')

      FabLayout({
        state: this.fabState,
        secondaryFabCount: 6,
        primaryColor: this.palette().colorAccent,
        accentColor: this.palette().colorAccent,
        primaryFab: () => {
          this.downloadsPrimaryFab();
        },
        secondaryFab: (index: number) => {
          this.downloadsSecondaryFab(index);
        }
      })

      // Right Download Labels Drawer (bookmarks_draw.xml)
      if (this.labelDrawerOpen && !this.selectionMode) {
        Stack({ alignContent: Alignment.End }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.palette().drawerScrim)
            .opacity(this.labelDrawerScrimOpacity)
            .onClick(() => {
              this.setLabelDrawerOpen(false);
            })

          Column() {
            Row({ space: 8 }) {
              Text($r('app.string.download_labels'))
                .fontSize(ThemeTypography.TOOLBAR_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().toolbarTitleColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.settings'))
                  .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().toolbarTitleColor)
                  .textCase(TextCase.UpperCase)
              }
              .height(36)
              .padding({ left: 8, right: 8 })
              .borderRadius(ThemeRadius.BUTTON)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.setLabelDrawerOpen(false);
                this.openLabelsScene();
              })
            }
            .width('100%')
            .height(ThemeDimens.TOOLBAR_HEIGHT)
            .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.SPACING })
            .backgroundColor(this.palette().toolbarColor)
            .shadow(ThemeElevation.toolbar())

            List() {
              ForEach(this.labelRows, (row: LabelDrawerRow) => {
                ListItem() {
                  Row() {
                    Text(row.displayName)
                      .fontSize(ThemeTypography.CARD_MESSAGE)
                      .fontWeight((row.label === null && this.labelText === '') || row.label === this.labelText
                        ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor((row.label === null && this.labelText === '') || row.label === this.labelText
                        ? this.palette().drawerActiveColor
                        : this.palette().textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                      .padding({ left: ThemeDimens.KEYLINE_MARGIN })

                    Text(`${row.count}`)
                      .fontSize(ThemeTypography.CARD_MESSAGE)
                      .fontColor((row.label === null && this.labelText === '') || row.label === this.labelText
                        ? this.palette().drawerActiveColor
                        : this.palette().textSecondary)
                      .padding({ right: ThemeDimens.KEYLINE_MARGIN })
                  }
                  .width('100%')
                  .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
                  .backgroundColor((row.label === null && this.labelText === '') || row.label === this.labelText
                    ? this.palette().drawerActiveBackground
                    : Color.Transparent)
                  .onClick(() => {
                    this.selectLabel(row.label);
                    this.setLabelDrawerOpen(false);
                  })
                }
              }, (row: LabelDrawerRow) => `${row.label ?? '__default__'}:${row.count}`)
            }
            .width('100%')
            .layoutWeight(1)
          }
          .width('78%')
          .constraintSize({ maxWidth: ThemeDimens.DRAWER_MAX_WIDTH })
          .height('100%')
          .backgroundColor(this.palette().drawerBackground)
          .shadow(ThemeElevation.dialog())
          .translate({ x: this.labelDrawerOffsetX })
        }
        .width('100%')
        .height('100%')
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
            .onActionUpdate((event: GestureEvent): void => {
              if (event.offsetX >= 0) {
                const clamped: number = Math.min(ThemeDimens.DRAWER_MAX_WIDTH, event.offsetX);
                this.labelDrawerOffsetX = clamped;
                this.labelDrawerScrimOpacity = Math.max(0, 1 - clamped / ThemeDimens.DRAWER_MAX_WIDTH);
              }
            })
            .onActionEnd((event: GestureEvent): void => {
              MainPageHost.markSwipeGesture();
              if (event.offsetX >= ThemeDimens.DRAWER_MAX_WIDTH * 0.35 || event.velocityX > 350) {
                this.setLabelDrawerOpen(false);
              } else {
                this.getUIContext().animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
                  this.labelDrawerOffsetX = 0;
                  this.labelDrawerScrimOpacity = 1;
                });
              }
            })
            .onActionCancel((): void => {
              if (this.labelDrawerOffsetX >= ThemeDimens.DRAWER_MAX_WIDTH * 0.35) {
                this.setLabelDrawerOpen(false);
              } else {
                this.getUIContext().animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
                  this.labelDrawerOffsetX = 0;
                  this.labelDrawerScrimOpacity = 1;
                });
              }
            })
        )
      }

      if (this.selectedArchiverForMenu !== null) {
        this.archiverContextDialog(this.selectedArchiverForMenu)
      }

      if (this.pendingCancelArchiver !== null) {
        this.archiverCancelConfirmDialog(this.pendingCancelArchiver)
      }

      if (this.showLabelPickerDialog) {
        this.labelPickerDialog()
      }

      if (this.showBatchDeleteDialog) {
        this.batchDeleteDialog()
      }

      if (this.showBatchMoveDialog) {
        this.batchMoveDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }

  private async confirmCancelArchiver(task: ArchiverTaskSnapshot): Promise<void> {
    this.pendingCancelArchiver = null;
    await ArchiverDownloader.getInstance().cancel(task.gid);
    this.syncActiveArchiverTasks();
    this.refresh();
    try {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.archiver_download_canceled'),
        duration: 1500
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showToast skipped: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  @Builder
  archiverCancelConfirmDialog(task: ArchiverTaskSnapshot): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick(() => {
          this.pendingCancelArchiver = null;
        })

      Column() {
        Text($r('app.string.archiver_download_cancel'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Text(this.archiverTitle(task).length > 0
          ? `${this.str('archiver_download_cancel_confirm')}\n\n${this.archiverTitle(task)}`
          : this.str('archiver_download_cancel_confirm'))
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 16 })

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textSecondary)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.pendingCancelArchiver = null;
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().errorColor)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            void this.confirmCancelArchiver(task);
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  labelPickerDialog(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick(() => {
          this.showLabelPickerDialog = false;
        })

      Column() {
        Text($r('app.string.download_labels'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        List() {
          ForEach(this.labelRows, (row: LabelDrawerRow) => {
            ListItem() {
              Row() {
                Text(row.displayName)
                  .fontSize(ThemeTypography.PREF_TITLE)
                  .fontWeight((row.label === null && this.labelText === '') || row.label === this.labelText
                    ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor((row.label === null && this.labelText === '') || row.label === this.labelText
                    ? this.palette().colorAccent : this.palette().textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                Text(`${row.count}`)
                  .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                  .fontColor((row.label === null && this.labelText === '') || row.label === this.labelText
                    ? this.palette().colorAccent : this.palette().textSecondary)
              }
              .width('100%')
              .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
              .padding({ left: 24, right: 24 })
              .backgroundColor((row.label === null && this.labelText === '') || row.label === this.labelText
                ? this.palette().drawerActiveBackground : Color.Transparent)
              .onClick(() => {
                this.showLabelPickerDialog = false;
                this.selectLabel(row.label);
              })
            }
          }, (row: LabelDrawerRow) => `picker_${row.label ?? '__default__'}:${row.count}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 280 })

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.settings'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.showLabelPickerDialog = false;
            this.openLabelsScene();
          })

          Blank()

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textSecondary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.showLabelPickerDialog = false;
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  batchDeleteDialog(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick(() => {
          this.showBatchDeleteDialog = false;
          this.pendingBatchDeleteItems = [];
        })

      Column() {
        Text($r('app.string.download_remove_dialog_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Text($r('app.string.download_remove_dialog_message_2', this.pendingBatchDeleteItems.length))
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 12 })

        Row({ space: 8 }) {
          Checkbox({ name: 'remove_image_files' })
            .select(this.batchDeleteRemoveFiles)
            .selectedColor(this.palette().colorAccent)
            .onChange((checked: boolean) => {
              this.batchDeleteRemoveFiles = checked;
            })

          Text($r('app.string.download_remove_dialog_check_text'))
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
            .onClick(() => {
              this.batchDeleteRemoveFiles = !this.batchDeleteRemoveFiles;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 24, bottom: 12 })
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textSecondary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.showBatchDeleteDialog = false;
            this.pendingBatchDeleteItems = [];
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().errorColor)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            void this.confirmBatchDelete();
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  batchMoveDialog(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick(() => {
          this.showBatchMoveDialog = false;
          this.pendingBatchMoveItems = [];
        })

      Column() {
        Text($r('app.string.download_move_dialog_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        List() {
          ForEach(this.labelRows, (row: LabelDrawerRow) => {
            ListItem() {
              Row() {
                Text(row.displayName)
                  .fontSize(ThemeTypography.PREF_TITLE)
                  .fontColor(this.palette().textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)

                Text(`${row.count}`)
                  .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                  .fontColor(this.palette().textSecondary)
              }
              .width('100%')
              .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
              .padding({ left: 24, right: 24 })
              .onClick(() => {
                void this.confirmBatchMove(row.label);
              })
            }
          }, (row: LabelDrawerRow) => `move_${row.label ?? '__default__'}:${row.count}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 280 })

        Row() {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.showBatchMoveDialog = false;
            this.pendingBatchMoveItems = [];
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}
