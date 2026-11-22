/**
 * App 主入口页（Stage 宿主）。
 *
 * 流程：
 *   1. 等待 `AppWiring.whenReady()`（保证 AppConfig / Settings / EhDB / CookieStore / Hosts / Proxy 已就绪）；
 *   2. 按上游 `MainActivity.launchAnnouncerFor(gates)` 顺序判定五道启动门：
 *      Warning → Analytics → SignIn → SelectSite → GalleryListScene；
 *   3. 任一道门或登录栈 finish 清空后，经 `onEmptyStack` 重跑门链直到落入 `GalleryListScene`；
 *   4. 所有场景（列表 / 详情 / 预览 / 门页 / 登录）统一经 `MainPageHostView` + `MainPageHost` 栈管理渲染。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppWiring } from '../hippo/AppWiring';
import { EhApplication } from '../hippo/ehviewer/EhApplication';
import { Settings } from '../hippo/ehviewer/Settings';
import { EhUrl } from '../hippo/ehviewer/client/EhUrl';
import { MainActivity, StartupGates } from '../hippo/ehviewer/ui/MainActivity';
import { GalleryListAction } from '../hippo/ehviewer/ui/scene/gallery/list/GalleryListScene';
import { GalleryListClient } from '../hippo/ui/GalleryListClient';
import { MainPageHost } from '../hippo/ui/MainPageHost';
import { MainPageHostView } from '../hippo/ui/MainPageHostView';
import { OkHttpClient } from '../hippo/okhttp/OkHttpClient';
import { Announcer } from '../hippo/scene/Announcer';
import { SceneArgs } from '../hippo/scene/SceneTypes';
import { PageRoutes } from '../hippo/ui/PageRoutes';
import { ThemeMode, ThemeTokens } from '../common/theme/ThemeTokens';
import {
  APP_THEME_STORAGE_KEY,
  applySystemBarTheme,
  applyWindowPrivacyMode,
  syncAppShowJpnTitleStorage,
  syncAppThemeStorage
} from '../hippo/ui/ThemeSystemBar';
import {
  ExternalWantRouter,
  LaunchBusListener,
  LaunchIntentKind,
  ParsedLaunchRequest,
  PendingLaunchBus
} from '../hippo/ui/ExternalWantRouter';

const DOMAIN: number = 0x0000;
const TAG: string = 'Index';

@Entry
@Component
struct Index {
  @StorageLink(APP_THEME_STORAGE_KEY) appThemeId: number = ThemeMode.LIGHT;
  @State loading: boolean = true;
  @State errorText: string = '';
  @State gateScene: string = '';
  @State gateEpoch: number = 0;
  @State listUrl: string = '';

  private listClient: Object | null = null;
  private gateArgs: SceneArgs | null = null;
  private pageHost: MainPageHost = new MainPageHost();
  private securityUnlocked: boolean = false;
  private pendingExternalLaunch: ParsedLaunchRequest | null = null;
  private readonly launchListener: LaunchBusListener = (req: ParsedLaunchRequest): void => {
    this.handleIncomingLaunchRequest(req);
  };

  aboutToAppear(): void {
    PendingLaunchBus.getInstance().subscribe(this.launchListener);
    const queued: ParsedLaunchRequest | null = PendingLaunchBus.getInstance().consumePending();
    if (queued !== null) {
      this.pendingExternalLaunch = queued;
    }
    this.runEntryGate();
  }

  aboutToDisappear(): void {
    PendingLaunchBus.getInstance().unsubscribe(this.launchListener);
  }

  private needsSecurityGate(): boolean {
    const sec: string = Settings.getSecurity();
    return sec.length > 0 && !this.securityUnlocked;
  }

  private showShortcutToast(action: string | null): void {
    const msgRes: Resource = action === ExternalWantRouter.SHORTCUT_STOP_ALL
      ? $r('app.string.shortcut_stop_all_triggered')
      : $r('app.string.shortcut_start_all_triggered');
    try {
      this.getUIContext().getPromptAction().showToast({ message: msgRes, duration: 2000 });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'showShortcutToast failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private pushExternalReader(req: ParsedLaunchRequest): void {
    const params: Record<string, Object> = ExternalWantRouter.toReaderRouteParams(req);
    this.getUIContext().getRouter().pushUrl({
      url: PageRoutes.GALLERY_READER,
      params: params
    }).catch((e: Error): void => {
      hilog.error(DOMAIN, TAG, 'pushUrl GalleryReaderPage failed: %{public}s',
        e instanceof Error && e.message !== undefined ? e.message : String(e));
    });
  }

  private handleIncomingLaunchRequest(req: ParsedLaunchRequest): void {
    if (req.kind === LaunchIntentKind.HOME || req.kind === LaunchIntentKind.NOTIFICATION) {
      return;
    }
    if (req.kind === LaunchIntentKind.SHORTCUT && !req.isColdStart) {
      this.showShortcutToast(req.shortcutAction);
      return;
    }
    this.pendingExternalLaunch = req;
    if (!this.loading && AppWiring.isWired()) {
      this.processPendingExternalLaunch();
    }
  }

  private processPendingExternalLaunch(): void {
    const req: ParsedLaunchRequest | null = this.pendingExternalLaunch;
    if (req === null || this.loading || !AppWiring.isWired()) {
      return;
    }
    if (req.kind === LaunchIntentKind.SHORTCUT) {
      if (req.isColdStart && this.needsSecurityGate()) {
        if (this.gateScene !== 'SecurityScene') {
          this.evaluateGate();
        }
        return;
      }
      this.pendingExternalLaunch = null;
      this.showShortcutToast(req.shortcutAction);
      if (ExternalWantRouter.shouldNavigateDownloadsOnShortcut(req)) {
        this.gateArgs = null;
        this.gateScene = 'DownloadsScene';
        this.gateEpoch = this.gateEpoch + 1;
        this.loading = false;
        hilog.info(DOMAIN, TAG, 'shortcut cold start → DownloadsScene action=%{public}s',
          req.shortcutAction === null ? '' : req.shortcutAction);
      }
      return;
    }

    if (ExternalWantRouter.shouldBypassAuthGates(req) || req.kind === LaunchIntentKind.READER_EH) {
      if (this.needsSecurityGate()) {
        if (this.gateScene !== 'SecurityScene') {
          this.evaluateGate();
        }
        return;
      }
      this.pendingExternalLaunch = null;
      if (this.gateScene.length === 0 || this.gateScene === 'SecurityScene') {
        this.evaluateGate();
      }
      this.pushExternalReader(req);
    }
  }

  private buildStartupGates(needSignedIn: boolean): StartupGates {
    const launchAction: string = Settings.getLaunchPageGalleryListSceneAction();
    return MainActivity.buildStartupGates(
      Settings.getSecurity(),
      this.securityUnlocked,
      Settings.getShowWarning(),
      // 1A: 鸿蒙版已移除数据统计 SDK（D-006），冷启动跳过 AnalyticsScene
      false,
      needSignedIn,
      Settings.getSelectSite(),
      launchAction
    );
  }

  onPageShow(): void {
    if (AppWiring.isWired()) {
      const currentTheme: number = ThemeTokens.getThemeId();
      syncAppThemeStorage(currentTheme);
      syncAppShowJpnTitleStorage(Settings.getShowJpnTitle());
      const hostCtx = this.getUIContext().getHostContext();
      applySystemBarTheme(hostCtx, currentTheme);
      applyWindowPrivacyMode(hostCtx, Settings.getEnabledSecurity(), false);
    }
    if (this.loading || !AppWiring.isWired()) {
      return;
    }
    const cookieStore = AppWiring.getCookieStore();
    const signedIn: boolean = cookieStore !== null && cookieStore.hasSignedIn();
    const needSignedIn: boolean = Settings.getNeedSignIn() && !signedIn;
    if (this.gateScene === 'GalleryListScene') {
      if (needSignedIn) {
        this.evaluateGate();
      }
      return;
    }
    if (this.gateScene === 'DownloadsScene' && !this.needsSecurityGate()) {
      return;
    }
    if (this.pageHost.getStackDepth() <= 1) {
      const gates: StartupGates = this.buildStartupGates(needSignedIn);
      const nextScene: string = MainActivity.launchAnnouncerFor(gates).sceneName;
      if (nextScene !== this.gateScene) {
        this.evaluateGate();
      }
    }
  }

  onBackPress(): boolean {
    return this.pageHost.goBack();
  }

  private async runEntryGate(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      await AppWiring.whenReady();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.loading = false;
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'runEntryGate: whenReady 失败: %{public}s', msg);
      return;
    }

    const cookieStore = AppWiring.getCookieStore();
    if (cookieStore === null) {
      this.loading = false;
      this.errorText = 'EhCookieStore not initialized';
      hilog.error(DOMAIN, TAG, 'runEntryGate: wire done 但 getCookieStore() 为 null');
      return;
    }

    const ctx: Context | undefined = this.getUIContext().getHostContext();
    this.listClient = new GalleryListClient((): OkHttpClient => EhApplication.getOkHttpClient(ctx === undefined ? null : ctx));
    syncAppShowJpnTitleStorage(Settings.getShowJpnTitle());
    if (this.pendingExternalLaunch === null) {
      const lateQueued: ParsedLaunchRequest | null = PendingLaunchBus.getInstance().consumePending();
      if (lateQueued !== null) {
        this.pendingExternalLaunch = lateQueued;
      }
    }
    this.evaluateGate();
    this.processPendingExternalLaunch();
  }

  private evaluateGate(): void {
    const cookieStore = AppWiring.getCookieStore();
    const signedIn: boolean = cookieStore !== null && cookieStore.hasSignedIn();
    const needSignedIn: boolean = Settings.getNeedSignIn() && !signedIn;
    const gates: StartupGates = this.buildStartupGates(needSignedIn);

    const announcer: Announcer = MainActivity.launchAnnouncerFor(gates);
    const args: SceneArgs | null = announcer.getArgs();
    let targetListUrl: string = EhUrl.getHost();
    if (args !== null) {
      const actionVal: Object | undefined = args.get(GalleryListAction.KEY_ACTION);
      if (actionVal === GalleryListAction.WHATS_HOT) {
        targetListUrl = EhUrl.getPopularUrl();
      } else if (actionVal === GalleryListAction.SUBSCRIPTION) {
        targetListUrl = EhUrl.getWatchedUrl();
      } else if (actionVal === GalleryListAction.TOP_LIST) {
        targetListUrl = EhUrl.getTopListUrl();
      }
    }

    this.gateArgs = args;
    this.listUrl = targetListUrl;
    this.gateScene = announcer.sceneName;
    this.gateEpoch = this.gateEpoch + 1;
    this.loading = false;
    hilog.info(DOMAIN, TAG,
      'evaluateGate → scene=%{public}s needSignedIn=%{public}s signedIn=%{public}s showJpnTitle=%{public}s url=%{public}s',
      this.gateScene, String(needSignedIn), String(signedIn), String(Settings.getShowJpnTitle()), targetListUrl);
  }

  build() {
    Column() {
      if (this.loading) {
        Column({ space: 8 }) {
          LoadingProgress().width(48).height(48).color(ThemeTokens.of(this.appThemeId).progressColor)
          Text($r('app.string.loading')).fontSize(14).fontColor(ThemeTokens.of(this.appThemeId).textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Column({ space: 12 }) {
          Text($r('app.string.load_failed')).fontSize(18).fontWeight(FontWeight.Bold)
          Text(this.errorText).fontSize(13).fontColor('#C62828').textAlign(TextAlign.Center)
          Button($r('app.string.retry')).onClick((): void => { this.runEntryGate(); })
        }
        .width('100%')
        .height('100%')
        .padding(24)
        .justifyContent(FlexAlign.Center)
      } else {
        MainPageHostView({
          initialScene: this.gateScene,
          gateEpoch: this.gateEpoch,
          initialArgs: this.gateArgs,
          listClient: this.listClient,
          listUrl: this.listUrl,
          host: this.pageHost,
          onEmptyStack: (): void => {
            this.evaluateGate();
            this.processPendingExternalLaunch();
          },
          onSecurityUnlocked: (): void => {
            this.securityUnlocked = true;
          },
          onActiveSceneChanged: (name: string): void => {
            if (name === 'GalleryListScene' || name === 'DownloadsScene' || name === 'SignInScene') {
              this.gateScene = name;
            }
          }
        })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.of(this.appThemeId).windowBackground)
  }
}
