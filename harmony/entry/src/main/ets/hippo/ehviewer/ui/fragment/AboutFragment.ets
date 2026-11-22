/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/fragment/AboutFragment.java（161 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/fragment/AboutFragment.ets（S0199）
 *
 * 上游事实：extends BasePreferenceFragmentCompat
 *   三个键：author / donate / check_for_updates
 *   onPreferenceClick 按 key 分支：author → 打开作者页；donate → 打开捐赠页；check_for_updates → 检查更新
 *
 * ⚠ `check_for_updates` 对应"自更新"模块 —— 用户第 5 项裁决已删除该模块（见 S0194 判 na）。
 *   本文件保留该键与分支（上游界面里确实有这一项），但动作经接口注入；
 *   接线方若不提供该动作，走 warn 兜底 —— 不静默、不编造 URL。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface AboutActionsLike {
  /** 上游 author：打开作者页 */
  openAuthorPage(): Promise<boolean>;
  /** 上游 donate：打开捐赠页 */
  openDonatePage(): Promise<boolean>;
  /** 上游 check_for_updates：已随自更新模块删除（S0194 判 na），此接口可返回 false */
  checkForUpdates(): Promise<boolean>;
}

export class UnavailableAboutActions implements AboutActionsLike {
  async openAuthorPage(): Promise<boolean> {
    hilog.warn(0x0000, 'AboutFragment', 'openAuthorPage 未接线；后果：点击作者项无反应');
    return false;
  }
  async openDonatePage(): Promise<boolean> {
    hilog.warn(0x0000, 'AboutFragment', 'openDonatePage 未接线；后果：点击捐赠项无反应');
    return false;
  }
  async checkForUpdates(): Promise<boolean> {
    hilog.info(0x0000, 'AboutFragment', 'checkForUpdates：自更新模块已按用户裁决删除（S0194=na）；后果：不检查更新');
    return false;
  }
}

export class AboutFragment {
  static readonly KEY_AUTHOR: string = 'author';
  static readonly KEY_DONATE: string = 'donate';
  static readonly KEY_CHECK_FOR_UPDATES: string = 'check_for_updates';

  private readonly actions: AboutActionsLike;

  constructor(actions: AboutActionsLike = new UnavailableAboutActions()) {
    this.actions = actions;
  }

  /** 上游三个键的顺序即界面顺序 */
  getPreferenceKeys(): string[] {
    return [AboutFragment.KEY_AUTHOR, AboutFragment.KEY_DONATE, AboutFragment.KEY_CHECK_FOR_UPDATES];
  }

  /** 上游 onPreferenceClick 分派 */
  onPreferenceClick(key: string): void {
    if (key === AboutFragment.KEY_AUTHOR) {
      this.actions.openAuthorPage().then((ok: boolean) => {
        if (!ok) {
          hilog.warn(0x0000, 'AboutFragment', 'openAuthorPage 返回 false；后果：未打开作者页');
        }
      }).catch((e: Error) => {
        hilog.error(0x0000, 'AboutFragment', 'openAuthorPage failed: err=%{public}s；后果：未打开作者页',
          e.message !== undefined ? e.message : String(e));
      });
      return;
    }
    if (key === AboutFragment.KEY_DONATE) {
      this.actions.openDonatePage().then((ok: boolean) => {
        if (!ok) {
          hilog.warn(0x0000, 'AboutFragment', 'openDonatePage 返回 false；后果：未打开捐赠页');
        }
      }).catch((e: Error) => {
        hilog.error(0x0000, 'AboutFragment', 'openDonatePage failed: err=%{public}s；后果：未打开捐赠页',
          e.message !== undefined ? e.message : String(e));
      });
      return;
    }
    if (key === AboutFragment.KEY_CHECK_FOR_UPDATES) {
      this.actions.checkForUpdates().then((ok: boolean) => {
        if (!ok) {
          hilog.info(0x0000, 'AboutFragment', 'checkForUpdates 未执行（模块已删除）；后果：不提示更新');
        }
      }).catch((e: Error) => {
        hilog.error(0x0000, 'AboutFragment', 'checkForUpdates failed: err=%{public}s；后果：不提示更新',
          e.message !== undefined ? e.message : String(e));
      });
      return;
    }
    hilog.info(0x0000, 'AboutFragment', '未处理的偏好键: %{public}s；后果：无动作', key);
  }
}
