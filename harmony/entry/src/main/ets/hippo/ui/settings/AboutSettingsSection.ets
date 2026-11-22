import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EhApplication } from '../../ehviewer/EhApplication';
import { GetText } from '../../ehviewer/GetText';
import { AboutFragment } from '../../ehviewer/ui/fragment/AboutFragment';
import { PageRoutes } from '../PageRoutes';
import { SettingsItem } from './SettingsItem';
import { MessagePreference } from '../../preference/MessagePreference';
import { UrlPreference } from '../../preference/UrlPreference';
import { DonateDialogLayout } from '../layout/dialog_donate';
import {
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { AboutSettingsHelpers, SettingsAboutActions } from './SettingsSectionHelpers';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'AboutSettingsSection';

@Component
export struct AboutSettingsSection {
  @Prop @Watch('onRefreshTriggerChanged') refreshTrigger: number = 0;
  @Prop themeId: number = -1;

  onOpenPage: (url: string) => void = (_url: string): void => {
  };
  onShowToast: (message: ResourceStr) => void = (_message: ResourceStr): void => {
  };

  @State versionText: string = '';
  @State donateSheetOpen: boolean = false;

  private hostContext: common.Context | undefined = undefined;
  private fragment: AboutFragment | null = null;

  aboutToAppear(): void {
    this.hostContext = this.getUIContext().getHostContext();
    if (this.hostContext !== undefined && !GetText.isInitialized()) {
      GetText.initialize(this.hostContext);
    }
    const actions: SettingsAboutActions = new SettingsAboutActions(
      (): Promise<boolean> => this.handleAuthorClick(),
      (): Promise<boolean> => this.handleDonateClick()
    );
    this.fragment = new AboutFragment(actions);
    this.syncSummary();
  }

  private onRefreshTriggerChanged(): void {
    this.syncSummary();
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

  private syncSummary(): void {
    this.versionText = AboutSettingsHelpers.resolveVersionSummary(this.str('error_unknown'));
  }

  private copyToClipboard(text: string, toastKey: string): boolean {
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      board.setDataSync(data);
      this.onShowToast(this.str(toastKey));
      return true;
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'copyToClipboard failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  private openExternalUrl(url: string): void {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx === undefined) {
      this.copyToClipboard(url, 'copied_to_clipboard');
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    (ctx as common.UIAbilityContext).startAbility(want).catch((err: Error): void => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'openExternalUrl failed for %{public}s: %{public}s', url, err.message);
      this.onShowToast($r('app.string.error_cant_find_activity'));
    });
  }

  private async handleAuthorClick(): Promise<boolean> {
    const email: string = EhApplication.getDeveloperEmail();
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      const want: Want = {
        action: 'ohos.want.action.sendData',
        uri: `mailto:${email}`
      };
      try {
        await (ctx as common.UIAbilityContext).startAbility(want);
        return true;
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'mailto startAbility unavailable, copying email instead: %{public}s', msg);
      }
    }
    return this.copyToClipboard(email, 'copied_to_clipboard');
  }

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private async handleDonateClick(): Promise<boolean> {
    this.donateSheetOpen = true;
    return true;
  }

  @Builder
  donateOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.donateSheetOpen = false;
        })

      Column() {
        Text($r('app.string.settings_about_donate'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Scroll() {
          Column() {
            DonateDialogLayout({
              alipayText: AboutSettingsHelpers.getDonateAlipayAccount(),
              guideText: this.str('settings_about_donate_message'),
              messageColor: this.palette().textPrimary,
              primaryThemeColor: this.palette().textThemePrimary,
              secondaryThemeColor: this.palette().textThemePrimary2,
              dividerColor: this.palette().divider,
              onCopyAlipay: () => {
                this.copyToClipboard(AboutSettingsHelpers.getDonateAlipayAccount(), 'settings_about_donate_copied');
              },
              onSaveAlipay: () => {
                this.copyToClipboard(AboutSettingsHelpers.getDonateAlipayAccount(), 'settings_about_donate_copied');
              },
              onSaveWechat: () => {
                this.copyToClipboard(AboutSettingsHelpers.getDonateAlipayAccount(), 'settings_about_donate_copied');
              }
            })
          }
          .width('100%')
        }
        .align(Alignment.TopStart)
        .width('100%')
        .constraintSize({ maxHeight: 420 })

        Row() {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
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
            this.donateSheetOpen = false;
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('88%')
      .constraintSize({ maxWidth: 380 })
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
    Column() {
      MessagePreference({
        title: this.str('settings_about_declaration'),
        summary: this.str('settings_about_declaration_summary'),
        dialogTitle: $r('app.string.settings_about_declaration'),
        message: $r('app.string.settings_about_declaration_summary'),
        showNegativeButton: false,
        themeId: this.themeId
      })

      SettingsItem({
        title: this.str('settings_about_author'),
        summary: AboutSettingsHelpers.formatAuthorSummary(this.str('settings_about_author_summary')),
        themeId: this.themeId,
        onItemClick: () => {
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AboutFragment.KEY_AUTHOR);
          }
        }
      })

      UrlPreference({
        title: this.str('settings_about_source'),
        url: AboutSettingsHelpers.URL_SOURCE,
        themeId: this.themeId,
        onOpenUrl: (url: string) => {
          this.openExternalUrl(url);
        },
        onCopyUrl: (url: string) => {
          this.copyToClipboard(url, 'copied_to_clipboard');
        }
      })

      UrlPreference({
        title: this.str('settings_about_latest_release'),
        url: AboutSettingsHelpers.URL_LATEST_RELEASE,
        themeId: this.themeId,
        onOpenUrl: (url: string) => {
          this.openExternalUrl(url);
        },
        onCopyUrl: (url: string) => {
          this.copyToClipboard(url, 'copied_to_clipboard');
        }
      })

      UrlPreference({
        title: this.str('settings_about_issue_help'),
        url: AboutSettingsHelpers.URL_ISSUE_HELP,
        themeId: this.themeId,
        onOpenUrl: (url: string) => {
          this.openExternalUrl(url);
        },
        onCopyUrl: (url: string) => {
          this.copyToClipboard(url, 'copied_to_clipboard');
        }
      })

      SettingsItem({
        title: this.str('settings_about_license'),
        summary: this.str('settings_about_license_summary'),
        themeId: this.themeId,
        onItemClick: () => {
          this.onOpenPage(PageRoutes.LICENSE);
        }
      })

      SettingsItem({
        title: this.str('settings_about_version'),
        summary: this.versionText,
        themeId: this.themeId,
        onItemClick: () => {
          this.copyToClipboard(this.versionText, 'copied_to_clipboard');
        }
      })

      // D-003 compliance: AppUpdater / check_for_updates / close_auto_updates intentionally omitted

      SettingsItem({
        title: this.str('settings_about_donate'),
        summary: this.str('settings_about_donate_message'),
        themeId: this.themeId,
        onItemClick: () => {
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AboutFragment.KEY_DONATE);
          }
        }
      })
    }
    .width('100%')
    .bindContentCover($$this.donateSheetOpen, this.donateOverlay(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        this.donateSheetOpen = false;
      }
    })
  }
}
