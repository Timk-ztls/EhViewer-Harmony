import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppWiring } from '../hippo/AppWiring';
import { EhApplication } from '../hippo/ehviewer/EhApplication';
import { OhosNetworkMonitor } from '../hippo/ehviewer/OhosNetworkMonitor';
import { AdvancedSettingsHelpers } from '../hippo/ui/settings/SettingsSectionHelpers';
import { installCrashHandler } from '../hippo/ehviewer/CrashObserver';
import { ArchiverDownloadCompleter } from '../hippo/ehviewer/download/ArchiverDownloadCompleter';
import { ArchiverDownloadService } from '../hippo/ehviewer/download/ArchiverDownloadService';
import { DownloadService } from '../hippo/ehviewer/download/DownloadService';
import { ShortcutsActivity } from '../hippo/ehviewer/shortcuts/ShortcutsActivity';
import { Settings } from '../hippo/ehviewer/Settings';
import { CachedThemeStartup, ThemeAutoSwitchHelper } from '../hippo/ui/ThemeAutoSwitchHelper';
import {
  applySystemBarTheme,
  applyWindowPrivacyMode,
  applyWindowPrivacyToWindow,
  applyWindowTheme,
  readCachedPrivacyMode,
  readCachedThemeStartup,
  resolveActiveThemeId,
  syncAppShowGalleryPagesStorage,
  syncAppShowReadProgressStorage,
  syncAppThemeStorage,
  syncSystemColorModeStorage
} from '../hippo/ui/ThemeSystemBar';
import {
  ExternalWantRouter,
  LaunchIntentKind,
  ParsedLaunchRequest,
  PendingLaunchBus,
  WantLike
} from '../hippo/ui/ExternalWantRouter';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  /**
   * 启动接线。
   *
   * **这一处是审计 L-06/L-07/L-08 的修复**：之前 `onCreate` 只有一行日志，
   * 于是 `Settings.attach` / `EhDB.attach` / 各注入点在全仓都没有真实调用者
   * → 34 个 DB 方法抛 'EhDB is not attached'、设置全读默认值、
   *   阅读页第一张图抛 'PageImageDownloader not injected'。
   *
   * `onCreate` 是 async 不安全的（框架不 await），所以 fire-and-forget + 自己 catch + 打 error 日志。
   * 不做同步阻塞：`relationalStore.getRdbStore` 与 `preferences.getPreferences` 都是 Promise，
   * 阻塞 `onCreate` 会拖慢首帧。
   */
  private syncInitialSystemColorMode(): void {
    const rawMode: number | undefined = this.context.config ? this.context.config.colorMode : undefined;
    const sysMode: number = ThemeAutoSwitchHelper.setSystemColorMode(rawMode);
    syncSystemColorModeStorage(sysMode);
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate: action=%{public}s uri=%{public}s params=%{public}s',
      String(want?.action), String(want?.uri), JSON.stringify(want?.parameters));
    this.syncInitialSystemColorMode();
    EhApplication.initialize();
    const app: EhApplication | null = EhApplication.getInstance();
    if (app !== null) {
      app.registerAbility(this.context);
    }
    // A-01 / G-1 最后一跳：通知/按钮点击会带 `archiver_action` 或 `download_action` 重新拉起本 ability
    EntryAbility.forwardArchiverWant(want);
    EntryAbility.forwardDownloadWant(want);
    EntryAbility.dispatchLaunchWant(want, true);
    AppWiring.wire(this.context, null, installCrashHandler).catch((e: Error): void => {
      hilog.error(DOMAIN, TAG, 'AppWiring failed: %{public}s', e.message);
      // **必须把失败传出去**（`ui-scene` 报的时序竞态的另一半）：
      // `AppWiring.whenReady()` 的等待者若拿到 resolve 会以为"就绪了"，
      // 然后撞一堆 `'EhDB is not attached'` —— 那比直接失败更难查。
      AppWiring.rejectReady(e);
    });
  }

  /**
   * **A-01 的最后一跳**（`auditor-ui` 落地 `ArchiverDownloadService` 后缺的那一环）。
   *
   * 只在 `onCreate` 转发是不够的：App 已在前台时框架走 **`onNewWant`**，不再走 `onCreate`
   * → 第二次点通知按钮，参数会丢（`clickSeq` 永远停在 1）。
   *
   * 验收判据（连点两次）：
   *   ① 构建侧 `serviceActionAgent: … clickSeq=1 / clickSeq=2` 必须递增
   *   ② 接收侧 `handleWantParameters: action=… clickSeq=1 / clickSeq=2` 两次都要到
   *   ③ 功能侧：点「暂停」→ 下载暂停 + 通知变「继续」；再点「继续」→ 恢复
   * 若 ② 只到一次 → `UPDATE_PRESENT_FLAG` 仍在复用同一份额外数据，
   * 下一步把 action agent 的 `actionFlags` 改成 `CONSTANT_FLAG`（按钮不需要"更新呈现项"，只需每次投递）。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant: action=%{public}s uri=%{public}s params=%{public}s',
      String(want?.action), String(want?.uri), JSON.stringify(want?.parameters));
    EntryAbility.forwardArchiverWant(want);
    EntryAbility.forwardDownloadWant(want);
    EntryAbility.dispatchLaunchWant(want, false);
  }

  private static dispatchLaunchWant(want: Want | undefined, isColdStart: boolean): void {
    if (want === undefined || want === null) {
      return;
    }
    const req: ParsedLaunchRequest = ExternalWantRouter.parseWant(want as Object as WantLike, isColdStart);
    if (req.kind === LaunchIntentKind.SHORTCUT) {
      if (isColdStart || !AppWiring.isWired()) {
        AppWiring.whenReady().then((): void => {
          ShortcutsActivity.handleWant(want);
        }).catch((err: Error): void => {
          hilog.error(DOMAIN, TAG, 'ShortcutsActivity dispatch failed: %{public}s', err.message);
        });
      } else {
        ShortcutsActivity.handleWant(want);
      }
      PendingLaunchBus.getInstance().publish(req);
      return;
    }
    if (req.kind === LaunchIntentKind.READER_ARCHIVE ||
      req.kind === LaunchIntentKind.READER_DIR ||
      req.kind === LaunchIntentKind.READER_EH) {
      PendingLaunchBus.getInstance().publish(req);
    }
  }

  /**
   * 只转发"带 `archiver_action`"的 want。
   *
   * **为什么必须判这个键**：若对任何 want 都转发，用户点图标冷启动会被当成"下载命令"吞掉
   * —— 通知按钮反而把 App 拉起来又不做事。判据在
   * `ArchiverDownloadService.handleWantParameters` 内部（无该键 → 返回 false，不认领）。
   */
  private static forwardArchiverWant(want: Want | undefined): void {
    if (ArchiverDownloadService.handleWantParameters(want?.parameters)) {
      hilog.info(DOMAIN, TAG, 'archiver want 已转发给 ArchiverDownloadService');
    }
  }

  /** 只转发带 `'download_action'` 参数的 want 给 DownloadService。 */
  private static forwardDownloadWant(want: Want | undefined): void {
    if (DownloadService.handleWantParameters(want?.parameters)) {
      hilog.info(DOMAIN, TAG, 'download want 已转发给 DownloadService');
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    OhosNetworkMonitor.stop();
    const app: EhApplication | null = EhApplication.getInstance();
    if (app !== null) {
      app.unregisterAbility(this.context);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');
    this.syncInitialSystemColorMode();
    const cachedStartup: CachedThemeStartup = readCachedThemeStartup(
      this.context,
      ThemeAutoSwitchHelper.getSystemColorMode()
    );
    const initialThemeId: number = syncAppThemeStorage(cachedStartup.themeId);
    const initialPrivacy: boolean = readCachedPrivacyMode(this.context, false);
    try {
      const mainWin: window.Window = windowStage.getMainWindowSync();
      this.mainWindow = mainWin;
      applyWindowPrivacyToWindow(mainWin, initialPrivacy);
    } catch (winErr) {
      hilog.warn(DOMAIN, TAG, 'getMainWindowSync for initial privacy mode failed: %{public}s',
        winErr instanceof Error ? winErr.message : JSON.stringify(winErr));
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      if (this.mainWindow !== null) {
        try {
          ArchiverDownloadCompleter.setUiContext(this.mainWindow.getUIContext());
        } catch (uiErr) {
          hilog.warn(DOMAIN, TAG, 'getUIContext failed: %{public}s',
            uiErr instanceof Error ? uiErr.message : JSON.stringify(uiErr));
        }
      }
      applySystemBarTheme(this.context, initialThemeId, false);
      if (this.mainWindow === null) {
        applyWindowPrivacyMode(this.context, initialPrivacy, false);
      }
      AppWiring.whenReady().then((): void => {
        AdvancedSettingsHelpers.applyAppLanguage(this.context, Settings.getAppLanguage());
        Settings.setDarkModeProvider((): boolean => ThemeAutoSwitchHelper.isSystemDark());
        const autoSwitch: boolean = Settings.isThemeAutoSwitchAvailable();
        const wiredThemeId: number = resolveActiveThemeId();
        if (autoSwitch && wiredThemeId !== Settings.getTheme()) {
          Settings.putTheme(wiredThemeId);
        }
        syncAppThemeStorage(wiredThemeId);
        syncAppShowGalleryPagesStorage(Settings.getShowGalleryPages());
        syncAppShowReadProgressStorage(Settings.getShowReadProgress());
        applySystemBarTheme(this.context, wiredThemeId, true, autoSwitch, true);
        const wiredPrivacy: boolean = Settings.getEnabledSecurity();
        applyWindowPrivacyMode(this.context, wiredPrivacy, true);
      }).catch((wireErr: Error): void => {
        hilog.warn(DOMAIN, TAG, 'sync theme/privacy after AppWiring failed: %{public}s', wireErr.message);
      });
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate: colorMode=%{public}s', String(newConfig.colorMode));
    if (newConfig.colorMode === undefined) {
      return;
    }
    const sysMode: number = ThemeAutoSwitchHelper.setSystemColorMode(newConfig.colorMode);
    syncSystemColorModeStorage(sysMode);
    const attached: boolean = Settings.isAttached();
    const cached: CachedThemeStartup = readCachedThemeStartup(this.context, sysMode);
    const autoSwitch: boolean = attached ? Settings.isThemeAutoSwitchAvailable() : cached.autoSwitch;
    if (!autoSwitch) {
      return;
    }
    const savedTheme: number = attached ? Settings.getTheme() : cached.themeId;
    const darkVariant: number = attached ? Settings.getThemeDarkVariant() : cached.darkVariant;
    const nextTheme: number = ThemeAutoSwitchHelper.resolveEffectiveTheme(savedTheme, true, sysMode, darkVariant);
    if (attached && nextTheme !== Settings.getTheme()) {
      Settings.putTheme(nextTheme);
    }
    syncAppThemeStorage(nextTheme);
    if (this.mainWindow !== null) {
      applyWindowTheme(this.mainWindow, nextTheme);
    }
    applySystemBarTheme(this.context, nextTheme, true, true, false);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
    ArchiverDownloadCompleter.setUiContext(null);
    this.mainWindow = null;
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    if (AppWiring.isWired()) {
      AppWiring.refreshNetworkStateOnChange('foreground');
    }
    const privacyEnabled: boolean = Settings.isAttached()
      ? Settings.getEnabledSecurity()
      : readCachedPrivacyMode(this.context, false);
    if (this.mainWindow !== null) {
      applyWindowPrivacyToWindow(this.mainWindow, privacyEnabled);
    } else {
      applyWindowPrivacyMode(this.context, privacyEnabled, false);
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
