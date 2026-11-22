/*
 * 上游：.../ui/fragment/EhFragment.java（132 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/fragment/EhFragment.ets（S0204）
 *
 * 上游事实：extends BasePreferenceFragmentCompat
 *   onCreatePreferences + onPreferenceChange（返回 false 表示"不改设置值"，true 表示接受）
 *   getSystemThemeSummary()：把系统主题状态翻成一句摘要（设置项的 summary 文案）
 * 与 S0200 AdvancedFragment 的区别：本文件是"外观/主题"分区，而 Advanced 是"工具/数据"分区。
 *
 * 依赖处置同 S0200：Settings 仍 pending → 主题读写经接口注入（ThemeStore），不直接依赖 Settings。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 上游 Settings 的主题相关子集（注入，避免直接依赖 pending 的 S0176） */
export interface ThemeStoreLike {
  getThemeMode(): number;
  setThemeMode(mode: number): void;
  getSystemThemeMode(): number;
}

export class InMemoryThemeStore implements ThemeStoreLike {
  private mode: number = 0;
  private systemMode: number = 0;
  getThemeMode(): number { return this.mode; }
  setThemeMode(mode: number): void { this.mode = mode; }
  getSystemThemeMode(): number { return this.systemMode; }
}

export class EhFragment {
  /** 主题模式取值（0=浅色 / 1=暗色 / 2=黑色；与 Settings.THEME_* 和 SettingsActivity 一致） */
  static readonly THEME_LIGHT: number = 0;
  static readonly THEME_DARK: number = 1;
  static readonly THEME_BLACK: number = 2;
  static readonly KEY_THEME: string = 'theme';

  private readonly store: ThemeStoreLike;

  constructor(store: ThemeStoreLike = new InMemoryThemeStore()) {
    this.store = store;
  }

  getPreferenceKeys(): string[] {
    return [EhFragment.KEY_THEME];
  }

  /** 上游 getSystemThemeSummary()：把系统主题翻成摘要文案标识（文案由 UI 层取资源键） */
  getSystemThemeSummary(): string {
    const sys: number = this.store.getSystemThemeMode();
    return (sys === EhFragment.THEME_DARK || sys === EhFragment.THEME_BLACK)
      ? 'theme_summary_dark'
      : 'theme_summary_light';
  }

  /**
   * 上游 onPreferenceChange：上游对 theme 返回 true（接受新值）并落盘。
   * 返回值语义保持：true = 已接受并写入；false = 拒绝（不改值）。
   */
  onPreferenceChange(key: string, newValue: number): boolean {
    if (key !== EhFragment.KEY_THEME) {
      hilog.info(0x0000, 'EhFragment', '未处理的偏好键: %{public}s；后果：值不变', key);
      return false;
    }
    if (newValue !== EhFragment.THEME_LIGHT
      && newValue !== EhFragment.THEME_DARK
      && newValue !== EhFragment.THEME_BLACK) {
      hilog.warn(0x0000, 'EhFragment', '主题取值非法: %{public}d；后果：拒绝修改，保持原值', newValue);
      return false;
    }
    this.store.setThemeMode(newValue);
    return true;
  }
}
