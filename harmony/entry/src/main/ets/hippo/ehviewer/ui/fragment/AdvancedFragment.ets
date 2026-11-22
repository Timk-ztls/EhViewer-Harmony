/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/fragment/AdvancedFragment.java（194 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/fragment/AdvancedFragment.ets（S0200）
 *
 * 上游事实：extends BasePreferenceFragmentCompat
 *   DB_LOADING = 0 / DB_LOAD_FINISH = 1                 ← 状态值
 *   LOADING_STATUS = "loading_status" / LOADING_PROGRESS = "loading_progress"   ← SharedPreferences key
 *   偏好键：dump_logcat / clear_memory_cache / app_language / import_data / wifi_server / wifi_client
 *   DbSyncHandle(Looper.getMainLooper()) 处理 DB 同步的进度回调
 *
 * 依赖处置（按 Lead 裁决）：`S0176 Settings` 仍 pending，**不直接依赖它**，
 * 用 `LoadingStatusStore` 接口注入（同 QuickSearchStore / DownloadSearchHostLike 模式），
 * 好处：单测不被拖进平台 SharedPreferences 依赖。
 *
 * Part 1（本批）：偏好键清单、DB 加载状态机（含进度）、六个动作的分派。
 * Part 2 待补：Preference UI 绑定（等 ui-widget 的 SettingsItem 完整）、各动作的具体实现。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../../Settings';

/** 上游 LOADING_STATUS / LOADING_PROGRESS 的读写（生产实现包 SharedPreferences） */
export interface LoadingStatusStore {
  getStatus(): number;
  setStatus(status: number): void;
  getProgress(): number;
  setProgress(progress: number): void;
}

export class InMemoryLoadingStatusStore implements LoadingStatusStore {
  private status: number = AdvancedFragment.DB_LOAD_FINISH;
  private progress: number = 100;
  getStatus(): number { return this.status; }
  setStatus(status: number): void { this.status = status; }
  getProgress(): number { return this.progress; }
  setProgress(progress: number): void { this.progress = progress; }
}

/** 生产实现：直接通过 Settings 持久化 LOADING_STATUS / LOADING_PROGRESS */
export class SettingsLoadingStatusStore implements LoadingStatusStore {
  getStatus(): number {
    return Settings.getInt(AdvancedFragment.LOADING_STATUS, AdvancedFragment.DB_LOAD_FINISH);
  }
  setStatus(status: number): void {
    Settings.putInt(AdvancedFragment.LOADING_STATUS, status);
  }
  getProgress(): number {
    return Settings.getInt(AdvancedFragment.LOADING_PROGRESS, 100);
  }
  setProgress(progress: number): void {
    Settings.putInt(AdvancedFragment.LOADING_PROGRESS, progress);
  }
}

/** 六个偏好动作的执行者（上游各 key 的点击处理） */
export interface AdvancedActionsLike {
  dumpLogcat(): Promise<void>;
  clearMemoryCache(): Promise<void>;
  openAppLanguage(): void;
  importData(): Promise<void>;
  openWifiServer(): void;
  openWifiClient(): void;
}

export class AdvancedFragment {
  static readonly DB_LOADING: number = 0;
  static readonly DB_LOAD_FINISH: number = 1;
  static readonly LOADING_STATUS: string = 'loading_status';
  static readonly LOADING_PROGRESS: string = 'loading_progress';

  static readonly KEY_DUMP_LOGCAT: string = 'dump_logcat';
  static readonly KEY_CLEAR_MEMORY_CACHE: string = 'clear_memory_cache';
  static readonly KEY_APP_LANGUAGE: string = 'app_language';
  static readonly KEY_IMPORT_DATA: string = 'import_data';
  static readonly KEY_WIFI_SERVER: string = 'wifi_server';
  static readonly KEY_WIFI_CLIENT: string = 'wifi_client';

  static readonly KEY_PROXY: string = 'proxy';
  static readonly KEY_BUILT_IN_HOSTS: string = Settings.KEY_BUILT_IN_HOSTS;
  static readonly KEY_BUILT_EX_HOSTS: string = Settings.KEY_BUILT_EX_HOSTS;
  static readonly KEY_CUSTOM_HOSTS: string = 'custom_hosts';
  static readonly KEY_DOH: string = Settings.KEY_DOH;
  static readonly KEY_DOMAIN_FRONTING: string = Settings.KEY_DOMAIN_FRONTING;

  private readonly store: LoadingStatusStore;
  private readonly actions: AdvancedActionsLike;

  constructor(store: LoadingStatusStore, actions: AdvancedActionsLike) {
    this.store = store;
    this.actions = actions;
  }

  /** 上游 onCreatePreferences：六个键的顺序即界面顺序 */
  getPreferenceKeys(): string[] {
    return [
      AdvancedFragment.KEY_DUMP_LOGCAT,
      AdvancedFragment.KEY_CLEAR_MEMORY_CACHE,
      AdvancedFragment.KEY_APP_LANGUAGE,
      AdvancedFragment.KEY_IMPORT_DATA,
      AdvancedFragment.KEY_WIFI_SERVER,
      AdvancedFragment.KEY_WIFI_CLIENT
    ];
  }

  /** 高级设置里的网络与 Hosts 偏好键顺序（对齐 advanced_settings.xml） */
  static getNetworkPreferenceKeys(): string[] {
    return [
      AdvancedFragment.KEY_PROXY,
      AdvancedFragment.KEY_BUILT_IN_HOSTS,
      AdvancedFragment.KEY_BUILT_EX_HOSTS,
      AdvancedFragment.KEY_CUSTOM_HOSTS,
      AdvancedFragment.KEY_DOH,
      AdvancedFragment.KEY_DOMAIN_FRONTING
    ];
  }

  /** 将网络/Hosts 布尔开关同步写入 Settings */
  static applyNetworkSwitch(key: string, value: boolean): boolean {
    switch (key) {
      case AdvancedFragment.KEY_BUILT_IN_HOSTS:
        Settings.putBuiltInHosts(value);
        return true;
      case AdvancedFragment.KEY_BUILT_EX_HOSTS:
        Settings.putBuiltEXHosts(value);
        return true;
      case AdvancedFragment.KEY_DOH:
        Settings.putDoH(value);
        return true;
      case AdvancedFragment.KEY_DOMAIN_FRONTING:
        Settings.putDF(value);
        return true;
      default:
        return false;
    }
  }

  isDbLoading(): boolean {
    return this.store.getStatus() === AdvancedFragment.DB_LOADING;
  }

  getDbProgress(): number {
    return this.store.getProgress();
  }

  /** 上游 DbSyncHandle 的回调：进度推进；到 100 视为完成 */
  onDbSyncProgress(progress: number): void {
    this.store.setProgress(progress);
    if (progress >= 100) {
      this.store.setStatus(AdvancedFragment.DB_LOAD_FINISH);
    }
  }

  /**
   * 偏好点击分派。上游 onPreferenceClick 按 key 分支；
   * 未识别的 key 只记日志（上游返回 false，等价于"未处理"）。
   */
  onPreferenceClick(key: string): void {
    switch (key) {
      case AdvancedFragment.KEY_DUMP_LOGCAT:
        this.actions.dumpLogcat().catch((e: Error) => {
          hilog.error(0x0000, 'AdvancedFragment', 'dumpLogcat failed: err=%{public}s；后果：日志未导出',
            e.message !== undefined ? e.message : String(e));
        });
        return;
      case AdvancedFragment.KEY_CLEAR_MEMORY_CACHE:
        this.actions.clearMemoryCache().catch((e: Error) => {
          hilog.error(0x0000, 'AdvancedFragment', 'clearMemoryCache failed: err=%{public}s；后果：缓存仍在',
            e.message !== undefined ? e.message : String(e));
        });
        return;
      case AdvancedFragment.KEY_APP_LANGUAGE:
        this.actions.openAppLanguage();
        return;
      case AdvancedFragment.KEY_IMPORT_DATA:
        this.actions.importData().catch((e: Error) => {
          hilog.error(0x0000, 'AdvancedFragment', 'importData failed: err=%{public}s；后果：数据未导入',
            e.message !== undefined ? e.message : String(e));
        });
        return;
      case AdvancedFragment.KEY_WIFI_SERVER:
        this.actions.openWifiServer();
        return;
      case AdvancedFragment.KEY_WIFI_CLIENT:
        this.actions.openWifiClient();
        return;
      default:
        hilog.info(0x0000, 'AdvancedFragment', '未处理的偏好键: %{public}s；后果：无动作', key);
        return;
    }
  }
}
