/*
 * W-003 ①：场景渲染分派器（`MainPageHostView`）
 *
 * 负责：
 *   1. 将 `MainPageHost` 的场景栈与当前渲染分支同步；
 *   2. 提供 Material Design Toolbar（56vp）与左侧抽屉（`NavDrawerPanel`）；
 *   3. 分派各 Scene 的 `@Component` 视图（含 GalleryList / GalleryDetail / GalleryPreviews / Gate / SignIn / Downloads）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { EhApplication } from '../ehviewer/EhApplication';
import { EhEventPaneBus, EhEventPaneListener, EhEventPaneMessage } from '../ehviewer/EhEventPaneBus';
import { GetText } from '../ehviewer/GetText';
import { CellularNetworkWarningGuard } from '../ehviewer/OhosNetworkMonitor';
import { Settings } from '../ehviewer/Settings';
import { EhEngine } from '../ehviewer/client/EhEngine';
import { EhUrl } from '../ehviewer/client/EhUrl';
import { EhNewsDetail } from '../ehviewer/client/data/EhNewsDetail';
import { HomeDetail, HomeDetailConfig } from '../ehviewer/client/data/HomeDetail';
import { NotifyKind } from '../ehviewer/widget/LimitsCountView';
import { OkHttpCallerAdapter } from '../AppWiring';
import { SceneArgs } from '../scene/SceneTypes';
import { SceneFragment } from '../scene/SceneFragment';
import { MainPageHost } from './MainPageHost';
import { NavDrawerPanel } from './NavDrawerPanel';
import { EhEventPaneMaterialDialog } from './EhEventPaneDialog';
import { APP_THEME_STORAGE_KEY, applySystemBarTheme, syncAppThemeStorage } from './ThemeSystemBar';
import { VArrowLeftDarkX24 } from './drawable/v_arrow_left_dark_x24';
import { VSettingsDarkX24 } from './drawable/v_settings_dark_x24';
import {
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../common/theme/ThemeTokens';
import { DownloadsSceneShell } from '../ehviewer/ui/scene/download/DownloadsSceneShell';
import { DownloadsSceneView } from './scene/DownloadsSceneView';
import { FavoritesSceneView } from './scene/FavoritesSceneView';
import { FavoritesSceneConcrete } from '../ehviewer/ui/scene/gallery/list/FavoritesSceneConcrete';
import { HistorySceneView } from './scene/HistorySceneView';
import { HistorySceneShell } from '../ehviewer/ui/scene/history/HistorySceneShell';
import { EhTopListSceneView } from './scene/EhTopListSceneView';
import { EhTopListSceneShell } from '../ehviewer/ui/scene/topList/EhTopListSceneShell';
import { GalleryInfoSceneView } from './scene/GalleryInfoSceneView';
import { GalleryInfoSceneShell } from '../ehviewer/ui/scene/GalleryInfoSceneShell';
import { GalleryCommentsSceneView } from './scene/GalleryCommentsSceneView';
import { GalleryCommentsSceneConcrete } from '../ehviewer/ui/scene/GalleryCommentsSceneConcrete';
import { CookieSignInSceneView } from './scene/CookieSignInSceneView';
import { CookieSignInSceneConcrete } from '../ehviewer/ui/scene/sign/CookieSignInSceneConcrete';
import { SelectSiteSceneView } from './scene/SelectSiteSceneView';
import { AnalyticsSceneView } from './scene/AnalyticsSceneView';
import { SelectSiteScene } from '../ehviewer/ui/scene/SelectSiteScene';
import { AnalyticsScene } from '../ehviewer/ui/scene/AnalyticsScene';
import { GalleryListSceneView } from './scene/GalleryListSceneView';
import { GalleryListSceneConcrete } from '../ehviewer/ui/scene/gallery/list/GalleryListSceneConcrete';
import { EhClientLike, GalleryListAction } from '../ehviewer/ui/scene/gallery/list/GalleryListScene';
import { GalleryDetailSceneView } from './scene/GalleryDetailSceneView';
import { GalleryDetailSceneConcrete } from '../ehviewer/ui/scene/gallery/detail/GalleryDetailSceneConcrete';
import { GalleryPreviewsSceneView } from './scene/GalleryPreviewsSceneView';
import { GalleryPreviewsSceneShell } from '../ehviewer/ui/scene/GalleryPreviewsSceneShell';
import { QuickSearchSceneView } from './scene/QuickSearchSceneView';
import { QuickSearchSceneShell } from '../ehviewer/ui/scene/gallery/list/QuickSearchSceneShell';
import { DownloadLabelsSceneView } from './scene/DownloadLabelsSceneView';
import { DownloadLabelsSceneShell } from '../ehviewer/ui/scene/download/DownloadLabelsSceneShell';
import { SubscriptionsSceneView } from './scene/SubscriptionsSceneView';
import { SubscriptionsSceneShell } from '../ehviewer/ui/scene/gallery/list/SubscriptionsSceneShell';
import { WarningSceneView } from './scene/WarningSceneView';
import { WarningScene } from '../ehviewer/ui/scene/WarningScene';
import { SignInSceneView } from './scene/SignInSceneView';
import { SignInSceneConcrete } from '../ehviewer/ui/scene/sign/SignInSceneConcrete';
import { PageRoutes, RouteActionKind, RouteNavigationPlan } from './PageRoutes';
import { SecuritySceneShell } from '../ehviewer/ui/scene/SecuritySceneShell';
import { SecuritySceneView } from './scene/SecuritySceneView';
import { WebViewSignInSceneView } from './scene/WebViewSignInSceneView';
import { WebViewSignInSceneConcrete } from '../ehviewer/ui/scene/sign/WebViewSignInSceneConcrete';
import { GetProfileSceneView } from './scene/GetProfileSceneView';
import { GetProfileSceneShell } from '../ehviewer/ui/scene/sign/GetProfileSceneShell';
import { ProgressSceneView } from './scene/ProgressSceneView';
import { ProgressSceneShell } from '../ehviewer/ui/scene/ProgressSceneShell';

const DOMAIN: number = 0x0000;
const TAG: string = 'MainPageHostView';
const LIMITS_COOLDOWN_MS: number = 60000;

class LocalizedHomeDetailConfig extends HomeDetailConfig {
  override getIpBaseLimits(): string {
    const label: string = GetText.getString('ip_base_limits');
    return label.length > 0 ? label : super.getIpBaseLimits();
  }
}

@Component export struct MainPageHostView {
  @Prop @Watch('onInitialSceneChanged') initialScene: string = 'DownloadsScene';
  @Prop @Watch('onGateEpochChanged') gateEpoch: number = 0;
  initialArgs: SceneArgs | null = null;
  listClient: Object | null = null;
  @Prop listUrl: string = '';
  host: MainPageHost = new MainPageHost();
  onEmptyStack: () => void = (): void => {};
  onSecurityUnlocked: () => void = (): void => {};
  onActiveSceneChanged: (name: string) => void = (_name: string): void => {};

  @State sceneEpoch: number = 0;
  private currentScene: SceneFragment | null = null;
  @State sceneName: string = '';
  @State renderBranch: string = 'empty';
  @State lastRenderError: string = '';
  @State canBack: boolean = false;
  @State drawerOpen: boolean = false;
  @State leftDrawerDragging: boolean = false;
  @State leftDrawerClosing: boolean = false;
  @State leftDrawerProgress: number = 0;
  @State leftDrawerSettleSeq: number = 0;
  @State leftDrawerSettleOpen: boolean = false;
  @State rightDrawerOpenSignal: number = 0;
  @State rightDrawerCloseSignal: number = 0;
  @State rightDrawerDragActive: boolean = false;
  @State rightDrawerDragProgress: number = 0;
  @State rightDrawerDragEndSeq: number = 0;
  @State rightDrawerDragSettleOpen: boolean = false;
  @State childRightDrawerOpen: boolean = false;
  @State childSwipeBlocked: boolean = false;
  @State activeListUrl: string = '';
  @State activeListAction: string = GalleryListAction.HOMEPAGE;
  @StorageLink(APP_THEME_STORAGE_KEY) themeId: number = ThemeMode.LIGHT;
  @State tipText: string = '';
  @State limitsLoading: boolean = false;
  @State limitsHasData: boolean = false;
  @State limitsText: string = '—';
  @State limitsUsed: number = 0;
  @State limitsTotal: number = 0;
  @State limitsFromGallery: string = '';
  @State limitsFromTorrent: string = '';
  @State limitsFromArchive: string = '';
  @State limitsFromHentai: string = '';
  @State limitsResetCost: number = 0;
  @State limitsResetCostText: string = '';
  @State showResetLimitDialog: boolean = false;
  @State resettingLimit: boolean = false;
  private limitsLastFetchedAtMs: number = 0;
  private limitsInFlight: boolean = false;
  private panHandled: boolean = false;
  private panMovedHorizontal: boolean = false;
  private panMode: string = '';

  private renderCount: number = 0;
  private lastAttachedGateEpoch: number = -1;
  private eventDialogController: CustomDialogController | null = null;
  private eventDialogOpen: boolean = false;
  private eventQueue: EhEventPaneMessage[] = [];
  private startupNewsChecked: boolean = false;
  private readonly eventPaneListener: EhEventPaneListener = (msg: EhEventPaneMessage): void => {
    this.enqueueEventPane(msg);
  };

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  private wireSceneCallbacks(scene: SceneFragment | null): void {
    if (scene instanceof SecuritySceneShell) {
      const shell: SecuritySceneShell = scene as SecuritySceneShell;
      shell.setOnUnlockedListener((): void => {
        this.onSecurityUnlocked();
      });
    }
  }

  private syncActionFromArgs(args: SceneArgs | null): void {
    if (args !== null) {
      const actionVal: Object | undefined = args.get(GalleryListAction.KEY_ACTION);
      if (typeof actionVal === 'string' && (actionVal as string).length > 0) {
        this.activeListAction = actionVal as string;
      }
    }
  }

  aboutToAppear(): void {
    this.themeId = syncAppThemeStorage();
    this.syncActionFromArgs(this.initialArgs);
    this.host.setNavigator((name: string, scene: SceneFragment | null): void => {
      this.drawerOpen = false;
      this.childRightDrawerOpen = false;
      this.childSwipeBlocked = false;
      this.canBack = this.host.canGoBack();
      this.themeId = syncAppThemeStorage();
      if (scene === null) {
        this.currentScene = null;
        this.sceneName = '';
        this.renderBranch = 'empty';
        this.sceneEpoch = this.sceneEpoch + 1;
        hilog.info(DOMAIN, TAG, 'navigator → 栈空，renderBranch=empty');
        return;
      }
      this.wireSceneCallbacks(scene);
      this.currentScene = scene;
      this.sceneName = name;
      this.renderBranch = name;
      this.lastRenderError = '';
      this.sceneEpoch = this.sceneEpoch + 1;
      this.onActiveSceneChanged(name);
      if (name === 'GalleryListScene') {
        this.maybeFetchStartupEhNews();
      }
      hilog.info(DOMAIN, TAG, 'navigator → renderBranch=%{public}s', name);
    });
    this.host.setOnEmptyStack((): void => {
      this.drawerOpen = false;
      this.childRightDrawerOpen = false;
      this.childSwipeBlocked = false;
      this.canBack = false;
      this.onEmptyStack();
    });
    this.host.setTipHandler((message: string): void => {
      this.tipText = message;
      try {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'showToast skipped: %{public}s', e instanceof Error ? e.message : String(e));
      }
    });
    this.lastAttachedGateEpoch = this.gateEpoch;
    EhEventPaneBus.getInstance().subscribe(this.eventPaneListener);
    let pendingEvent: EhEventPaneMessage | null = EhEventPaneBus.getInstance().consumePending();
    while (pendingEvent !== null) {
      this.enqueueEventPane(pendingEvent);
      pendingEvent = EhEventPaneBus.getInstance().consumePending();
    }
    CellularNetworkWarningGuard.setWarningListener((): void => {
      this.showCellularNetworkWarning();
    });
    CellularNetworkWarningGuard.checkAndNotify();
    this.attach(this.initialScene, this.initialArgs);
    this.maybeFetchStartupEhNews();
  }

  aboutToDisappear(): void {
    EhEventPaneBus.getInstance().unsubscribe(this.eventPaneListener);
    CellularNetworkWarningGuard.setWarningListener(null);
    if (this.eventDialogController !== null) {
      try {
        this.eventDialogController.close();
      } catch (_e) {
        // Ignore dialog close errors on tear-down.
      }
      this.eventDialogController = null;
    }
    this.eventDialogOpen = false;
    this.eventQueue = [];
  }

  private enqueueEventPane(msg: EhEventPaneMessage): void {
    if (msg.body.length === 0) {
      return;
    }
    this.eventQueue.push(msg);
    this.showNextEventPane();
  }

  private showNextEventPane(): void {
    if (this.eventDialogOpen || this.eventQueue.length === 0) {
      return;
    }
    const next: EhEventPaneMessage | undefined = this.eventQueue.shift();
    if (next === undefined) {
      return;
    }
    this.eventDialogOpen = true;
    try {
      this.eventDialogController = new CustomDialogController({
        builder: EhEventPaneMaterialDialog({
          bodyText: next.body,
          themeId: this.themeId,
          onDismiss: (): void => {
            this.eventDialogOpen = false;
            this.eventDialogController = null;
            this.showNextEventPane();
          }
        }),
        customStyle: true,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        cancel: (): void => {
          this.eventDialogOpen = false;
          this.eventDialogController = null;
          this.showNextEventPane();
        }
      });
      this.eventDialogController.open();
    } catch (e) {
      this.eventDialogOpen = false;
      this.eventDialogController = null;
      hilog.warn(DOMAIN, TAG, 'open EhEventPaneMaterialDialog failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private maybeFetchStartupEhNews(): void {
    if (this.startupNewsChecked) {
      return;
    }
    try {
      if (!Settings.isAttached() || !Settings.getShowEhEvents()) {
        return;
      }
    } catch (_e) {
      return;
    }
    if (this.sceneName !== 'GalleryListScene' && this.initialScene !== 'GalleryListScene') {
      return;
    }
    this.startupNewsChecked = true;
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    const caller: OkHttpCallerAdapter = new OkHttpCallerAdapter(
      EhApplication.getOkHttpClient(ctx === undefined ? null : ctx)
    );
    EhEngine.getEhNews(null, caller).then((detail: EhNewsDetail | null): void => {
      if (detail !== null) {
        const paneHtml: string | null = detail.getEventPane();
        if (paneHtml !== null) {
          EhEventPaneBus.getInstance().publishHtml(paneHtml);
        }
      }
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'startup getEhNews failed: %{public}s', e.message);
    });
  }

  private showCellularNetworkWarning(): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.cellular_network_warning'),
        duration: 2500
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showCellularNetworkWarning skipped: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private onInitialSceneChanged(): void {
    if (this.initialScene === this.sceneName) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'initialScene 变更: %{public}s → %{public}s，重新 attach',
      this.sceneName, this.initialScene);
    this.lastAttachedGateEpoch = this.gateEpoch;
    this.drawerOpen = false;
    this.syncActionFromArgs(this.initialArgs);
    this.attach(this.initialScene, this.initialArgs);
  }

  private onGateEpochChanged(): void {
    if (this.initialScene.length === 0 || this.gateEpoch === this.lastAttachedGateEpoch) {
      return;
    }
    this.lastAttachedGateEpoch = this.gateEpoch;
    this.drawerOpen = false;
    this.syncActionFromArgs(this.initialArgs);
    this.attach(this.initialScene, this.initialArgs);
  }

  getRenderCount(): number {
    return this.renderCount;
  }

  getLastRenderError(): string {
    return this.lastRenderError;
  }

  getRenderBranch(): string {
    return this.renderBranch;
  }

  private effectiveListUrl(): string {
    if (this.activeListUrl.length > 0) {
      return this.activeListUrl;
    }
    if (this.listUrl.length > 0) {
      return this.listUrl;
    }
    return EhUrl.getHost();
  }

  private isDrawerScene(): boolean {
    return this.sceneName === 'GalleryListScene'
      || this.sceneName === 'DownloadsScene'
      || this.sceneName === 'FavoritesScene'
      || this.sceneName === 'HistoryScene'
      || this.sceneName === 'EhTopListScene';
  }

  private hasRightDrawerScene(): boolean {
    return this.sceneName === 'GalleryListScene'
      || this.sceneName === 'FavoritesScene'
      || this.sceneName === 'DownloadsScene';
  }

  private notifyChildRightDrawerState(open: boolean): void {
    if (this.childRightDrawerOpen === open) {
      return;
    }
    Promise.resolve().then((): void => {
      this.childRightDrawerOpen = open;
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'notifyChildRightDrawerState failed: %{public}s', e.message);
    });
  }

  private showToastResource(res: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: res, duration: 1500 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showToastResource skipped: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private applyHomeDetail(detail: HomeDetail): void {
    this.limitsText = detail.getImageLimits(new LocalizedHomeDetailConfig());
    this.limitsUsed = detail.getUsed();
    this.limitsTotal = detail.getTotal();
    this.limitsFromGallery = detail.getFromGalleryVisits();
    this.limitsFromTorrent = detail.getFromTorrentCompletions();
    this.limitsFromArchive = detail.getFromArchiveDownloads();
    this.limitsFromHentai = detail.getFromHentaiAtHome();
    this.limitsResetCost = detail.resetCost();
    this.limitsResetCostText = detail.getResetCost();
    this.limitsHasData = true;
    this.limitsLastFetchedAtMs = Date.now();
    hilog.info(DOMAIN, TAG,
      'homeDetail parsed: used=%{public}d total=%{public}d resetCost=%{public}d text=%{public}s',
      this.limitsUsed, this.limitsTotal, this.limitsResetCost, this.limitsText);
  }

  private fetchHomeLimits(force: boolean): void {
    try {
      if (!Settings.isAttached() || !Settings.isLogin() || !Settings.getShowEhLimits()) {
        this.limitsHasData = false;
        this.limitsText = '—';
        this.limitsResetCost = 0;
        return;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'fetchHomeLimits guard failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      return;
    }
    if (!force && this.limitsHasData && (Date.now() - this.limitsLastFetchedAtMs) < LIMITS_COOLDOWN_MS) {
      return;
    }
    if (this.limitsInFlight) {
      return;
    }
    this.limitsInFlight = true;
    this.limitsLoading = true;
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    const caller: OkHttpCallerAdapter = new OkHttpCallerAdapter(
      EhApplication.getOkHttpClient(ctx === undefined ? null : ctx)
    );
    EhEngine.getHomeDetail(null, caller).then((detail: HomeDetail): void => {
      this.applyHomeDetail(detail);
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'getHomeDetail failed: %{public}s', e.message);
    }).finally((): void => {
      this.limitsInFlight = false;
      this.limitsLoading = false;
    });
  }

  private async confirmResetLimits(): Promise<void> {
    if (this.resettingLimit) {
      return;
    }
    this.showResetLimitDialog = false;
    this.resettingLimit = true;
    this.limitsLoading = true;
    try {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      const caller: OkHttpCallerAdapter = new OkHttpCallerAdapter(
        EhApplication.getOkHttpClient(ctx === undefined ? null : ctx)
      );
      const detail: HomeDetail = await EhEngine.resetLimit(null, caller);
      this.applyHomeDetail(detail);
      this.showToastResource($r('app.string.reset_limit_success'));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'resetLimit failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.showToastResource($r('app.string.reset_limit_failed'));
    } finally {
      this.resettingLimit = false;
      this.limitsLoading = false;
    }
  }

  private openLeftDrawer(): void {
    if (this.childRightDrawerOpen) {
      this.rightDrawerCloseSignal = this.rightDrawerCloseSignal + 1;
      this.childRightDrawerOpen = false;
    }
    this.leftDrawerDragging = false;
    this.leftDrawerClosing = false;
    this.leftDrawerSettleOpen = true;
    this.drawerOpen = true;
    this.fetchHomeLimits(false);
  }

  private hasOwnTopChrome(): boolean {
    return this.sceneName === 'GalleryListScene'
      || this.sceneName === 'GalleryDetailScene'
      || this.sceneName === 'FavoritesScene'
      || this.sceneName === 'DownloadsScene'
      || this.sceneName === 'HistoryScene'
      || this.sceneName === 'GalleryCommentsScene'
      || this.sceneName === 'GalleryPreviewsScene'
      || this.sceneName === 'GalleryInfoScene'
      || this.sceneName === 'SignInScene'
      || this.sceneName === 'EhTopListScene'
      || this.sceneName === 'QuickSearchScene'
      || this.sceneName === 'SubscriptionsScene'
      || this.sceneName === 'DownloadLabelsScene';
  }

  private sceneTitleResource(): Resource {
    if (this.sceneName === 'GalleryListScene') {
      return $r('app.string.homepage');
    }
    if (this.sceneName === 'DownloadsScene') {
      return $r('app.string.downloads');
    }
    if (this.sceneName === 'DownloadLabelsScene') {
      return $r('app.string.download_labels');
    }
    if (this.sceneName === 'QuickSearchScene') {
      return $r('app.string.quick_search');
    }
    if (this.sceneName === 'SubscriptionsScene') {
      return $r('app.string.tag_title');
    }
    if (this.sceneName === 'FavoritesScene') {
      return $r('app.string.favorites');
    }
    if (this.sceneName === 'HistoryScene') {
      return $r('app.string.history');
    }
    if (this.sceneName === 'EhTopListScene') {
      return $r('app.string.top_lists');
    }
    if (this.sceneName === 'GalleryDetailScene' || this.sceneName === 'GalleryInfoScene') {
      return $r('app.string.gallery_info');
    }
    if (this.sceneName === 'GalleryPreviewsScene') {
      return $r('app.string.gallery_previews');
    }
    if (this.sceneName === 'GalleryCommentsScene') {
      return $r('app.string.gallery_comments');
    }
    if (this.sceneName === 'SignInScene') {
      return $r('app.string.sign_in');
    }
    if (this.sceneName === 'CookieSignInScene') {
      return $r('app.string.sign_in_via_cookies');
    }
    if (this.sceneName === 'SecurityScene') {
      return $r('app.string.settings_privacy_pattern_protection_title');
    }
    if (this.sceneName === 'WebViewSignInScene') {
      return $r('app.string.sign_in');
    }
    if (this.sceneName === 'GetProfileScene' || this.sceneName === 'ProgressScene') {
      return $r('app.string.loading');
    }
    if (this.sceneName === 'WarningScene') {
      return $r('app.string.waring');
    }
    if (this.sceneName === 'SelectSiteScene') {
      return $r('app.string.settings_eh_gallery_site');
    }
    return $r('app.string.app_name');
  }

  private openPage(url: string): void {
    this.drawerOpen = false;
    this.childRightDrawerOpen = false;
    this.childSwipeBlocked = false;
    const plan: RouteNavigationPlan = PageRoutes.resolveNavigation(url, true);
    if (plan.kind !== RouteActionKind.PUSH) {
      hilog.warn(DOMAIN, TAG, '路由 %{public}s 尚未注册或受限: kind=%{public}s', url, plan.kind);
      return;
    }
    this.getUIContext().getRouter().pushUrl({ url: url }).catch((e: Error): void => {
      const msg: string = e.message !== undefined ? e.message : String(e);
      this.tipText = msg;
      hilog.warn(DOMAIN, TAG, '路由打开 %{public}s 失败: %{public}s', url, msg);
    });
  }

  private navigateToList(action: string, url: string): void {
    this.drawerOpen = false;
    this.childRightDrawerOpen = false;
    this.childSwipeBlocked = false;
    this.activeListUrl = url;
    this.activeListAction = action;
    if (this.sceneName === 'GalleryListScene' && this.currentScene instanceof GalleryListSceneConcrete) {
      const listScene: GalleryListSceneConcrete = this.currentScene as GalleryListSceneConcrete;
      listScene.switchToAction(action, url);
      listScene.refreshGalleryList(true);
      return;
    }
    const args: SceneArgs = new Map<string, Object>();
    args.set(GalleryListAction.KEY_ACTION, action);
    args.set(GalleryListAction.KEY_LIST_URL_BUILDER, url);
    this.attach('GalleryListScene', args);
  }

  private pushDrawerScene(sceneName: string): void {
    this.drawerOpen = false;
    this.childRightDrawerOpen = false;
    this.childSwipeBlocked = false;
    if (this.sceneName === sceneName) {
      return;
    }
    this.host.startSceneByName(sceneName, null, null, 0);
  }

  private toggleTheme(): void {
    const next: number = (this.themeId + 1) % 3;
    try {
      if (next === ThemeMode.DARK || next === ThemeMode.BLACK) {
        Settings.putThemeDarkVariant(next);
      }
      if (Settings.isThemeAutoSwitchAvailable()) {
        Settings.putThemeAutoSwitchAvailable(false);
      }
      Settings.putTheme(next);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'putTheme failed: %{public}s', e instanceof Error ? e.message : String(e));
    }
    this.themeId = next;
    syncAppThemeStorage(next);
    applySystemBarTheme(this.getUIContext().getHostContext(), next, true, false, true);
  }

  /** 挂载根场景：失败也保留明确原因（不静默空白） */
  private attach(name: string, args: SceneArgs | null): void {
    if (name.length === 0) {
      this.renderBranch = 'empty';
      this.canBack = false;
      return;
    }
    try {
      const scene: SceneFragment | null = this.host.attachScene(name, args);
      if (scene === null) {
        this.currentScene = null;
        this.sceneName = name;
        this.renderBranch = 'unsupported';
        this.canBack = false;
        this.lastRenderError = 'attachScene 返回 null（未注册 或 非 BaseScene 子类）: ' + name;
        this.sceneEpoch = this.sceneEpoch + 1;
        hilog.error(DOMAIN, TAG, 'attach 失败: %{public}s；后果：页面显示"场景不可用"', this.lastRenderError);
        return;
      }
      this.wireSceneCallbacks(scene);
      this.currentScene = scene;
      this.sceneName = name;
      this.renderBranch = name;
      this.canBack = this.host.canGoBack();
      this.lastRenderError = '';
      this.sceneEpoch = this.sceneEpoch + 1;
      if (name === 'GalleryListScene') {
        this.maybeFetchStartupEhNews();
      }
      hilog.info(DOMAIN, TAG, 'renderBranch=%{public}s scene=%{public}s', this.renderBranch, name);
    } catch (e) {
      this.currentScene = null;
      this.sceneName = name;
      this.renderBranch = 'unsupported';
      this.canBack = false;
      this.lastRenderError = (e as Error).message;
      this.sceneEpoch = this.sceneEpoch + 1;
      hilog.error(DOMAIN, TAG, 'attach 抛出: %{public}s；后果：页面显示"场景不可用"', this.lastRenderError);
    }
  }

  @Builder
  hamburgerIcon() {
    Column({ space: 3 }) {
      Column()
        .width(18)
        .height(2)
        .backgroundColor(this.palette().toolbarIconColor)
      Column()
        .width(18)
        .height(2)
        .backgroundColor(this.palette().toolbarIconColor)
      Column()
        .width(18)
        .height(2)
        .backgroundColor(this.palette().toolbarIconColor)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  materialHostToolbar() {
    Row() {
      if (this.canBack) {
        Row() {
          VArrowLeftDarkX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.palette().toolbarIconColor
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.host.goBack();
        })
      } else if (this.isDrawerScene()) {
        Row() {
          this.hamburgerIcon()
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          if (this.drawerOpen) {
            this.drawerOpen = false;
          } else {
            this.openLeftDrawer();
          }
        })
      }

      Text(this.sceneTitleResource())
        .fontSize(ThemeTypography.TOOLBAR_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().toolbarTitleColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: this.canBack || this.isDrawerScene() ? ThemeDimens.SPACING : ThemeDimens.SPACING_MD })
        .layoutWeight(1)

      Row() {
        VSettingsDarkX24({
          iconSize: ThemeDimens.ICON_SIZE_STANDARD,
          fillColor: this.palette().toolbarIconColor
        })
      }
      .width(ThemeDimens.TOUCH_TARGET_MIN)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.openPage(PageRoutes.SETTINGS);
      })
    }
    .width('100%')
    .height(ThemeDimens.TOOLBAR_HEIGHT)
    .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
    .backgroundColor(this.palette().toolbarColor)
    .shadow(ThemeElevation.toolbar())
    .alignItems(VerticalAlign.Center)
    .zIndex(2)
  }

  build() {
    Column() {
      if (!this.hasOwnTopChrome()) {
        this.materialHostToolbar()
      }

      Stack() {
        ForEach([this.sceneEpoch], (_epoch: number): void => {
          if (this.currentScene === null) {
            Column({ space: 8 }) {
              Text($r('app.string.empty_result'))
                .fontSize(15)
                .fontColor(this.palette().textSecondary)
                .textAlign(TextAlign.Center)
              if (this.lastRenderError.length > 0) {
                Text(this.lastRenderError)
                  .fontSize(12)
                  .fontColor(this.palette().errorColor)
                  .textAlign(TextAlign.Center)
              }
            }
            .width('100%')
            .height('100%')
            .padding(24)
            .justifyContent(FlexAlign.Center)
          } else if (this.sceneName === 'DownloadsScene') {
            DownloadsSceneView({
              shell: this.currentScene as DownloadsSceneShell,
              themeId: this.themeId,
              rightDrawerOpenSignal: this.rightDrawerOpenSignal,
              rightDrawerCloseSignal: this.rightDrawerCloseSignal,
              rightDrawerDragActive: this.rightDrawerDragActive,
              rightDrawerDragProgress: this.rightDrawerDragProgress,
              rightDrawerDragEndSeq: this.rightDrawerDragEndSeq,
              rightDrawerDragSettleOpen: this.rightDrawerDragSettleOpen,
              onRightDrawerStateChange: (open: boolean): void => {
                this.notifyChildRightDrawerState(open);
              },
              onSwipeBlockChange: (blocked: boolean): void => {
                this.childSwipeBlocked = blocked;
              },
              onOpenDrawer: (): void => {
                this.openLeftDrawer();
              }
            })
          } else if (this.sceneName === 'GalleryListScene') {
            GalleryListSceneView({
              scene: this.currentScene as GalleryListSceneConcrete,
              client: this.listClient as EhClientLike | null,
              listUrl: this.effectiveListUrl(),
              themeId: this.themeId,
              rightDrawerOpenSignal: this.rightDrawerOpenSignal,
              rightDrawerCloseSignal: this.rightDrawerCloseSignal,
              rightDrawerDragActive: this.rightDrawerDragActive,
              rightDrawerDragProgress: this.rightDrawerDragProgress,
              rightDrawerDragEndSeq: this.rightDrawerDragEndSeq,
              rightDrawerDragSettleOpen: this.rightDrawerDragSettleOpen,
              onRightDrawerStateChange: (open: boolean): void => {
                this.notifyChildRightDrawerState(open);
              },
              onSwipeBlockChange: (blocked: boolean): void => {
                this.childSwipeBlocked = blocked;
              },
              onOpenDrawer: (): void => {
                this.openLeftDrawer();
              }
            })
          } else if (this.sceneName === 'GalleryDetailScene') {
            GalleryDetailSceneView({
              scene: this.currentScene as GalleryDetailSceneConcrete,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'GalleryPreviewsScene') {
            GalleryPreviewsSceneView({
              shell: this.currentScene as GalleryPreviewsSceneShell,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'GalleryInfoScene') {
            GalleryInfoSceneView({
              shell: this.currentScene as GalleryInfoSceneShell,
              host: this.host,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'GalleryCommentsScene') {
            GalleryCommentsSceneView({
              scene: this.currentScene as GalleryCommentsSceneConcrete,
              host: this.host,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'FavoritesScene') {
            FavoritesSceneView({
              scene: this.currentScene as FavoritesSceneConcrete,
              host: this.host,
              themeId: this.themeId,
              rightDrawerOpenSignal: this.rightDrawerOpenSignal,
              rightDrawerCloseSignal: this.rightDrawerCloseSignal,
              rightDrawerDragActive: this.rightDrawerDragActive,
              rightDrawerDragProgress: this.rightDrawerDragProgress,
              rightDrawerDragEndSeq: this.rightDrawerDragEndSeq,
              rightDrawerDragSettleOpen: this.rightDrawerDragSettleOpen,
              onRightDrawerStateChange: (open: boolean): void => {
                this.notifyChildRightDrawerState(open);
              },
              onOpenDrawer: (): void => {
                this.openLeftDrawer();
              }
            })
          } else if (this.sceneName === 'HistoryScene') {
            HistorySceneView({
              shell: this.currentScene as HistorySceneShell,
              host: this.host,
              themeId: this.themeId,
              onOpenDrawer: (): void => {
                this.openLeftDrawer();
              }
            })
          } else if (this.sceneName === 'QuickSearchScene') {
            QuickSearchSceneView({
              shell: this.currentScene as QuickSearchSceneShell,
              host: this.host,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'DownloadLabelsScene') {
            DownloadLabelsSceneView({
              shell: this.currentScene as DownloadLabelsSceneShell,
              host: this.host,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'SubscriptionsScene') {
            SubscriptionsSceneView({
              shell: this.currentScene as SubscriptionsSceneShell,
              host: this.host,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'EhTopListScene') {
            EhTopListSceneView({
              shell: this.currentScene as EhTopListSceneShell,
              host: this.host,
              themeId: this.themeId,
              onOpenDrawer: (): void => { this.openLeftDrawer(); }
            })
          } else if (this.sceneName === 'SignInScene') {
            SignInSceneView({
              scene: this.currentScene as SignInSceneConcrete,
              themeId: this.themeId
            })
          } else if (this.sceneName === 'CookieSignInScene') {
            CookieSignInSceneView({ scene: this.currentScene as CookieSignInSceneConcrete })
          } else if (this.sceneName === 'SelectSiteScene') {
            SelectSiteSceneView({ scene: this.currentScene as SelectSiteScene })
          } else if (this.sceneName === 'AnalyticsScene') {
            AnalyticsSceneView({ scene: this.currentScene as AnalyticsScene })
          } else if (this.sceneName === 'WarningScene') {
            WarningSceneView({ scene: this.currentScene as WarningScene })
          } else if (this.sceneName === 'SecurityScene') {
            SecuritySceneView({
              shell: this.currentScene as SecuritySceneShell,
              themeId: this.themeId,
              isLightTheme: this.themeId === ThemeMode.LIGHT
            })
          } else if (this.sceneName === 'WebViewSignInScene') {
            WebViewSignInSceneView({ scene: this.currentScene as WebViewSignInSceneConcrete })
          } else if (this.sceneName === 'GetProfileScene') {
            GetProfileSceneView({ shell: this.currentScene as GetProfileSceneShell })
          } else if (this.sceneName === 'ProgressScene') {
            ProgressSceneView({ shell: this.currentScene as ProgressSceneShell })
          } else {
            Column({ space: 8 }) {
              Text() {
                Span($r('app.string.scene_not_supported'))
                Span(' ' + this.sceneName)
              }
                .fontColor(this.palette().colorPrimaryDark)
                .fontSize(15)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .height('100%')
            .padding(24)
            .justifyContent(FlexAlign.Center)
          }
        }, (epoch: number): string => String(epoch) + ':' + this.sceneName)

        if (this.tipText.length > 0) {
          Column() {
            Text(this.tipText)
              .fontSize(13)
              .fontColor(this.palette().white)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(this.palette().readerOverlayScrim)
              .borderRadius(ThemeRadius.BUTTON)
              .onClick((): void => { this.tipText = ''; })
          }
          .width('100%')
          .height('100%')
          .padding({ bottom: 24 })
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.None)
        }

        if (this.drawerOpen || this.leftDrawerDragging || this.leftDrawerClosing) {
          NavDrawerPanel({
            interactiveDragging: this.leftDrawerDragging,
            interactiveProgress: this.leftDrawerProgress,
            settleSeq: this.leftDrawerSettleSeq,
            settleOpen: this.leftDrawerSettleOpen,
            activeScene: this.sceneName,
            activeListAction: this.activeListAction,
            themeId: this.themeId,
            limitsLoading: this.limitsLoading,
            limitsHasData: this.limitsHasData,
            limitsText: this.limitsText,
            limitsUsed: this.limitsUsed,
            limitsTotal: this.limitsTotal,
            limitsFromGallery: this.limitsFromGallery,
            limitsFromTorrent: this.limitsFromTorrent,
            limitsFromArchive: this.limitsFromArchive,
            limitsFromHentai: this.limitsFromHentai,
            limitsResetCost: this.limitsResetCost,
            limitsResetCostText: this.limitsResetCostText,
            onRefreshLimits: (): void => {
              this.fetchHomeLimits(true);
            },
            onResetLimits: (): void => {
              if (this.limitsResetCost > 0) {
                this.showResetLimitDialog = true;
              }
            },
            onLimitsNotify: (kind: number): void => {
              if (kind === NotifyKind.LIMIT_UNNEED_RESET) {
                this.showToastResource($r('app.string.limit_unneed_reset'));
              } else {
                this.showToastResource($r('app.string.reset_limit_failed'));
              }
            },
            onSelectList: (action: string, url: string): void => {
              this.navigateToList(action, url);
            },
            onSelectScene: (sceneName: string): void => {
              this.pushDrawerScene(sceneName);
            },
            onOpenPage: (url: string): void => {
              this.openPage(url);
            },
            onToggleTheme: (): void => {
              this.toggleTheme();
            },
            onClose: (): void => {
              this.drawerOpen = false;
              this.leftDrawerDragging = false;
              this.leftDrawerClosing = false;
            }
          })
        }

        if (this.showResetLimitDialog) {
          this.resetLimitConfirmOverlay()
        }
      }
      .layoutWeight(1)
      .width('100%')
      .parallelGesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
          .onActionStart((): void => {
            this.panMode = '';
            this.panHandled = false;
            this.panMovedHorizontal = false;
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (this.childSwipeBlocked || this.drawerOpen || this.childRightDrawerOpen || this.panMode === 'ignored') {
              return;
            }
            const dx: number = event.offsetX;
            const dy: number = event.offsetY;
            if (this.panMode === '') {
              if (Math.abs(dx) < 12 && Math.abs(dy) < 12) {
                return;
              }
              if (Math.abs(dy) > Math.abs(dx) * 0.85) {
                this.panMode = 'ignored';
                return;
              }
              if (dx > 0 && this.isDrawerScene()) {
                this.panMode = 'open_left';
                this.panMovedHorizontal = true;
                MainPageHost.markSwipeGesture();
                this.fetchHomeLimits(false);
              } else if (dx < 0 && this.hasRightDrawerScene()) {
                this.panMode = 'open_right';
                this.panMovedHorizontal = true;
                MainPageHost.markSwipeGesture();
              } else {
                this.panMode = 'ignored';
                return;
              }
            }
            MainPageHost.markSwipeGesture();
            if (this.panMode === 'open_left') {
              const clamped: number = Math.max(0, Math.min(1, dx / ThemeDimens.DRAWER_MAX_WIDTH));
              this.leftDrawerClosing = false;
              this.leftDrawerDragging = true;
              this.leftDrawerProgress = clamped;
            } else if (this.panMode === 'open_right') {
              const clamped: number = Math.max(0, Math.min(1, -dx / ThemeDimens.DRAWER_MAX_WIDTH));
              this.rightDrawerDragActive = true;
              this.rightDrawerDragProgress = clamped;
            }
          })
          .onActionEnd((event: GestureEvent): void => {
            if (this.panMode === 'open_left') {
              MainPageHost.markSwipeGesture();
              const progress: number = Math.max(0, Math.min(1, event.offsetX / ThemeDimens.DRAWER_MAX_WIDTH));
              const shouldOpen: boolean = progress >= 0.35 || event.velocityX > 350;
              this.leftDrawerDragging = false;
              if (shouldOpen) {
                this.drawerOpen = true;
                this.leftDrawerClosing = false;
                this.leftDrawerSettleOpen = true;
              } else {
                this.drawerOpen = false;
                this.leftDrawerClosing = true;
                this.leftDrawerSettleOpen = false;
              }
              this.leftDrawerSettleSeq = this.leftDrawerSettleSeq + 1;
            } else if (this.panMode === 'open_right') {
              MainPageHost.markSwipeGesture();
              const progress: number = Math.max(0, Math.min(1, -event.offsetX / ThemeDimens.DRAWER_MAX_WIDTH));
              const shouldOpen: boolean = progress >= 0.35 || event.velocityX < -350;
              this.rightDrawerDragActive = false;
              this.rightDrawerDragSettleOpen = shouldOpen;
              this.rightDrawerDragEndSeq = this.rightDrawerDragEndSeq + 1;
            } else if (this.panMovedHorizontal || this.panHandled) {
              MainPageHost.markSwipeGesture();
            }
            this.panMode = '';
            this.panHandled = false;
            this.panMovedHorizontal = false;
          })
          .onActionCancel((): void => {
            if (this.panMode === 'open_left') {
              const shouldOpen: boolean = this.leftDrawerProgress >= 0.35;
              this.leftDrawerDragging = false;
              if (shouldOpen) {
                this.drawerOpen = true;
                this.leftDrawerClosing = false;
                this.leftDrawerSettleOpen = true;
              } else {
                this.drawerOpen = false;
                this.leftDrawerClosing = true;
                this.leftDrawerSettleOpen = false;
              }
              this.leftDrawerSettleSeq = this.leftDrawerSettleSeq + 1;
            } else if (this.panMode === 'open_right') {
              const shouldOpen: boolean = this.rightDrawerDragProgress >= 0.35;
              this.rightDrawerDragActive = false;
              this.rightDrawerDragSettleOpen = shouldOpen;
              this.rightDrawerDragEndSeq = this.rightDrawerDragEndSeq + 1;
            }
            this.panMode = '';
            this.panHandled = false;
            this.panMovedHorizontal = false;
          })
      )
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
    .onAppear(() => {
      this.renderCount = this.renderCount + 1;
    })
  }

  @Builder
  resetLimitConfirmOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.showResetLimitDialog = false;
        })

      Column() {
        Text($r('app.string.reset_limit_confirm_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Text($r('app.string.reset_limit_confirm_message', this.limitsResetCostText))
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
          .onClick((): void => {
            this.showResetLimitDialog = false;
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            void this.confirmResetLimits();
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
      .onClick((): void => {
      })
    }
    .width('100%')
    .height('100%')
  }
}
