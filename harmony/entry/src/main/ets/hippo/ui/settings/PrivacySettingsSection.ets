import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GetText } from '../../ehviewer/GetText';
import { Settings } from '../../ehviewer/Settings';
import { PageRoutes } from '../PageRoutes';
import { applyWindowPrivacyMode, writeCachedPrivacyMode } from '../ThemeSystemBar';
import { SettingsItem } from './SettingsItem';
import { SwitchPreference } from '../../preference/SwitchPreference';
import { PrivacySettingsHelpers } from './SettingsSectionHelpers';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'PrivacySettingsSection';

@Component
export struct PrivacySettingsSection {
  @Prop @Watch('onRefreshTriggerChanged') refreshTrigger: number = 0;
  @Prop themeId: number = -1;

  onOpenPage: (url: string) => void = (_url: string): void => {
  };
  onShowToast: (message: ResourceStr) => void = (_message: ResourceStr): void => {
  };

  @State securityPattern: string = '';
  @State enabledSecurity: boolean = Settings.VALUE_SEC_SECURITY;

  private hostContext: common.Context | undefined = undefined;

  aboutToAppear(): void {
    this.hostContext = this.getUIContext().getHostContext();
    if (this.hostContext !== undefined && !GetText.isInitialized()) {
      GetText.initialize(this.hostContext);
    }
    this.syncFromSettings();
  }

  private onRefreshTriggerChanged(): void {
    this.syncFromSettings();
  }

  private str(key: string): string {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        return ctx.resourceManager.getStringByNameSync(key);
      } catch (err) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'getStringByNameSync failed for %{public}s: %{public}s',
          key, JSON.stringify(err));
      }
    }
    return GetText.getString(key);
  }

  private syncFromSettings(): void {
    this.securityPattern = Settings.getSecurity();
    this.enabledSecurity = Settings.getEnabledSecurity();
  }

  private applyWindowPrivacyMode(privacyEnabled: boolean): void {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx === undefined) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'applyWindowPrivacyMode(%{public}s): hostContext is undefined',
        String(privacyEnabled));
      this.enabledSecurity = PrivacySettingsHelpers.applySecureScreenToggle(!privacyEnabled);
      this.onShowToast(`${this.str('settings_privacy_secure')}: ${this.str('error_unknown')}`);
      return;
    }
    applyWindowPrivacyMode(ctx, privacyEnabled, true, (detail: string): void => {
      // 系统接口失败时回滚设置与缓存，避免开关显示“已开启”但实际未防截屏
      this.enabledSecurity = PrivacySettingsHelpers.applySecureScreenToggle(!privacyEnabled);
      writeCachedPrivacyMode(ctx, !privacyEnabled);
      this.onShowToast(`${this.str('settings_privacy_secure')}: ${this.str('error_unknown')} (${detail})`);
    });
  }

  build() {
    Column() {
      SettingsItem({
        title: this.str('settings_privacy_pattern_protection_title'),
        summary: this.str(PrivacySettingsHelpers.patternProtectionSummaryRes(this.securityPattern)),
        themeId: this.themeId,
        onItemClick: () => {
          this.onOpenPage(PageRoutes.SET_SECURITY);
        }
      })

      SwitchPreference({
        title: this.str('settings_privacy_secure'),
        summary: this.str('settings_privacy_secure_summary'),
        checked: this.enabledSecurity,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.enabledSecurity = PrivacySettingsHelpers.applySecureScreenToggle(checked);
          this.applyWindowPrivacyMode(checked);
        }
      })
    }
    .width('100%')
  }
}
