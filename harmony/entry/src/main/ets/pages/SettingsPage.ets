import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GetText } from '../hippo/ehviewer/GetText';
import { Settings } from '../hippo/ehviewer/Settings';
import { EhApplication } from '../hippo/ehviewer/EhApplication';
import { EhConfig } from '../hippo/ehviewer/client/EhConfig';
import { ProxyPreference, ProxyValue } from '../hippo/ehviewer/preference/ProxyPreference';
import { DefaultCategoryPreference } from '../hippo/ehviewer/preference/DefaultCategoryPreference';
import { ExcludedTagNamespacesPreference } from '../hippo/ehviewer/preference/ExcludedTagNamespacesPreference';
import { SignOutPreference } from '../hippo/ehviewer/preference/SignOutPreference';
import { ListPreference } from '../hippo/preference/ListPreference';
import { SwitchPreference } from '../hippo/preference/SwitchPreference';
import { SettingsItem } from '../hippo/ui/settings/SettingsItem';
import { ReadSettingsSection } from '../hippo/ui/settings/ReadSettingsSection';
import { DownloadSettingsSection } from '../hippo/ui/settings/DownloadSettingsSection';
import { PrivacySettingsSection } from '../hippo/ui/settings/PrivacySettingsSection';
import { AdvancedSettingsSection } from '../hippo/ui/settings/AdvancedSettingsSection';
import { AboutSettingsSection } from '../hippo/ui/settings/AboutSettingsSection';
import { ExcludedLanguagesActivity } from '../hippo/ehviewer/ui/ExcludedLanguagesActivity';
import { AdvancedFragment } from '../hippo/ehviewer/ui/fragment/AdvancedFragment';
import { AppWiring } from '../hippo/AppWiring';
import { PageRoutes, RouteActionKind, RouteNavigationPlan } from '../hippo/ui/PageRoutes';
import { UConfigPageCoordinator } from '../hippo/ui/p3/P3PageAdapters';
import {
  APP_THEME_STORAGE_KEY,
  applySystemBarTheme,
  syncAppShowJpnTitleStorage,
  syncAppThemeStorage
} from '../hippo/ui/ThemeSystemBar';
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../common/theme/ThemeTokens';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VSadPandaPrimaryX24 } from '../hippo/ui/drawable/v_sad_panda_primary_x24';
import { VBookOpenPrimaryX24 } from '../hippo/ui/drawable/v_book_open_primary_x24';
import { VDownloadPrimaryX24 } from '../hippo/ui/drawable/v_download_primary_x24';
import { VSecPrimaryX24 } from '../hippo/ui/drawable/v_sec_primary_x24';
import { VAdbPrimaryX24 } from '../hippo/ui/drawable/v_adb_primary_x24';
import { VInfoPrimaryX24 } from '../hippo/ui/drawable/v_info_primary_x24';
import { EhTagDatabaseUpdater } from '../hippo/ehviewer/client/EhTagDatabaseUpdater';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'SettingsPage';

const GALLERY_SITE_VALUES: string[] = ['0', '1'];
const THEME_VALUES: string[] = ['0', '1', '2'];
const LIST_MODE_VALUES: string[] = ['0', '1'];
const DETAIL_SIZE_VALUES: string[] = ['0', '1'];
const THUMB_SIZE_VALUES: string[] = ['0', '1', '2'];
const THUMB_RESOLUTION_VALUES: string[] = ['0', '1', '2'];

const LANGUAGE_LABEL_KEYS: string[] = [
  'language_japanese',
  'language_english',
  'language_chinese',
  'language_dutch',
  'language_french',
  'language_german',
  'language_hungarian',
  'language_italian',
  'language_korean',
  'language_polish',
  'language_portuguese',
  'language_russian',
  'language_spanish',
  'language_thai',
  'language_vietnamese',
  'language_na',
  'language_other'
];

const EXCLUDED_LANGUAGE_PATTERNS: string[] = [
  EhConfig.JAPANESE_ORIGINAL, EhConfig.JAPANESE_TRANSLATED, EhConfig.JAPANESE_REWRITE,
  EhConfig.ENGLISH_ORIGINAL, EhConfig.ENGLISH_TRANSLATED, EhConfig.ENGLISH_REWRITE,
  EhConfig.CHINESE_ORIGINAL, EhConfig.CHINESE_TRANSLATED, EhConfig.CHINESE_REWRITE,
  EhConfig.DUTCH_ORIGINAL, EhConfig.DUTCH_TRANSLATED, EhConfig.DUTCH_REWRITE,
  EhConfig.FRENCH_ORIGINAL, EhConfig.FRENCH_TRANSLATED, EhConfig.FRENCH_REWRITE,
  EhConfig.GERMAN_ORIGINAL, EhConfig.GERMAN_TRANSLATED, EhConfig.GERMAN_REWRITE,
  EhConfig.HUNGARIAN_ORIGINAL, EhConfig.HUNGARIAN_TRANSLATED, EhConfig.HUNGARIAN_REWRITE,
  EhConfig.ITALIAN_ORIGINAL, EhConfig.ITALIAN_TRANSLATED, EhConfig.ITALIAN_REWRITE,
  EhConfig.KOREAN_ORIGINAL, EhConfig.KOREAN_TRANSLATED, EhConfig.KOREAN_REWRITE,
  EhConfig.POLISH_ORIGINAL, EhConfig.POLISH_TRANSLATED, EhConfig.POLISH_REWRITE,
  EhConfig.PORTUGUESE_ORIGINAL, EhConfig.PORTUGUESE_TRANSLATED, EhConfig.PORTUGUESE_REWRITE,
  EhConfig.RUSSIAN_ORIGINAL, EhConfig.RUSSIAN_TRANSLATED, EhConfig.RUSSIAN_REWRITE,
  EhConfig.SPANISH_ORIGINAL, EhConfig.SPANISH_TRANSLATED, EhConfig.SPANISH_REWRITE,
  EhConfig.THAI_ORIGINAL, EhConfig.THAI_TRANSLATED, EhConfig.THAI_REWRITE,
  EhConfig.VIETNAMESE_ORIGINAL, EhConfig.VIETNAMESE_TRANSLATED, EhConfig.VIETNAMESE_REWRITE,
  EhConfig.NA_ORIGINAL, EhConfig.NA_TRANSLATED, EhConfig.NA_REWRITE,
  EhConfig.OTHER_ORIGINAL, EhConfig.OTHER_TRANSLATED, EhConfig.OTHER_REWRITE
];

@Entry
@Component
export struct SettingsPage {
  @State settingsReady: boolean = false;
  @State activeSection: string = '';
  @State excludedLangSheetOpen: boolean = false;
  @State sectionRefreshSeq: number = 0;

  // Network & Proxy states
  @State domainFronting: boolean = false;
  @State builtInHosts: boolean = false;
  @State builtExHosts: boolean = false;
  @State dohEnabled: boolean = false;

  // E-Hentai states
  @State gallerySite: number = 0;
  @State theme: number = 0;
  @State listMode: number = 0;
  @State detailSize: number = 0;
  @State thumbSize: number = 1;
  @State thumbResolution: number = 0;
  @State showJpnTitle: boolean = false;
  @State showGalleryPages: boolean = false;
  @State showGalleryComment: boolean = true;
  @State needSignIn: boolean = true;
  @State excludedLanguages: string = '';
  @State showTagTranslations: boolean = true;
  @State tagDbUpdating: boolean = false;
  @State tagDbReady: boolean = false;

  private hostContext: common.Context | undefined = undefined;

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    this.hostContext = ctx;
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    if (Settings.isAttached() || ctx === undefined) {
      this.syncFromSettings();
      this.settingsReady = true;
      return;
    }
    Settings.attach(ctx).then((): void => {
      this.syncFromSettings();
      this.settingsReady = true;
    }).catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', `Settings.attach failed: ${err.message}`);
      this.syncFromSettings();
      this.settingsReady = true;
    });
  }

  onPageShow(): void {
    if (Settings.isAttached()) {
      this.syncFromSettings();
      this.sectionRefreshSeq += 1;
    }
  }

  private syncFromSettings(): void {
    this.domainFronting = Settings.getDF();
    this.builtInHosts = Settings.getBuiltInHosts();
    this.builtExHosts = Settings.getBuiltEXHosts();
    this.dohEnabled = Settings.getDoH();

    this.gallerySite = Settings.getGallerySite();
    this.theme = Settings.getTheme();
    this.listMode = Settings.getListMode();
    this.detailSize = Settings.getDetailSize();
    this.thumbSize = Settings.getThumbSize();
    this.thumbResolution = Settings.getThumbResolution();
    this.showJpnTitle = Settings.getShowJpnTitle();
    this.showGalleryPages = Settings.getShowGalleryPages();
    this.showGalleryComment = Settings.getShowGalleryComment();
    this.needSignIn = Settings.getNeedSignIn();
    const rawExcluded: string | null = Settings.getExcludedLanguages();
    this.excludedLanguages = rawExcluded === null ? '' : rawExcluded;
    this.showTagTranslations = Settings.getShowTagTranslations();
    this.tagDbReady = EhTagDatabaseUpdater.isDatabaseReady();
  }

  private str(key: string): string {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        return ctx.resourceManager.getStringByNameSync(key);
      } catch (err) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', `getStringByNameSync failed for ${key}: ${JSON.stringify(err)}`);
      }
    }
    return GetText.getString(key);
  }

  private strs(keys: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      result.push(this.str(keys[i]));
    }
    return result;
  }

  onBackPress(): boolean {
    if (this.excludedLangSheetOpen) {
      this.excludedLangSheetOpen = false;
      return true;
    }
    if (this.activeSection.length > 0) {
      this.activeSection = '';
      return true;
    }
    return false;
  }

  private navigateBack(): void {
    if (this.activeSection.length > 0) {
      this.activeSection = '';
      return;
    }
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', `Router back failed: ${JSON.stringify(err)}`);
    }
  }

  private toolbarTitle(): Resource {
    if (this.activeSection === 'eh') {
      return $r('app.string.settings_eh');
    }
    if (this.activeSection === 'read') {
      return $r('app.string.settings_read');
    }
    if (this.activeSection === 'download') {
      return $r('app.string.settings_download');
    }
    if (this.activeSection === 'privacy') {
      return $r('app.string.settings_privacy');
    }
    if (this.activeSection === 'advanced') {
      return $r('app.string.settings_advanced');
    }
    if (this.activeSection === 'about') {
      return $r('app.string.settings_about');
    }
    return $r('app.string.settings');
  }

  private tagTranslationsSourceSummary(): string {
    const baseUrl: string = this.str('settings_eh_tag_translations_source_url');
    if (this.tagDbUpdating) {
      return `${baseUrl} (...)`;
    }
    if (this.tagDbReady) {
      return `${baseUrl} (已缓存)`;
    }
    return baseUrl;
  }

  private triggerTagDbUpdate(): void {
    if (this.tagDbUpdating) {
      return;
    }
    this.tagDbUpdating = true;
    this.showToast($r('app.string.download_state_downloading'));
    EhTagDatabaseUpdater.update(true).then((ok: boolean): void => {
      this.tagDbUpdating = false;
      this.tagDbReady = EhTagDatabaseUpdater.isDatabaseReady();
      this.showToast(ok ? $r('app.string.download_state_finish') : $r('app.string.error_unknown'));
    }).catch((err: Error): void => {
      this.tagDbUpdating = false;
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'manual tag db update failed: %{public}s', err.message);
      this.showToast($r('app.string.error_unknown'));
    });
  }

  @Builder
  settingsHeaderIcon(sectionKey: string): void {
    if (sectionKey === 'eh') {
      VSadPandaPrimaryX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().colorPrimary })
    } else if (sectionKey === 'read') {
      VBookOpenPrimaryX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().colorPrimary })
    } else if (sectionKey === 'download') {
      VDownloadPrimaryX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().colorPrimary })
    } else if (sectionKey === 'privacy') {
      VSecPrimaryX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().colorPrimary })
    } else if (sectionKey === 'advanced') {
      VAdbPrimaryX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().colorPrimary })
    } else {
      VInfoPrimaryX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().colorPrimary })
    }
  }

  @Builder
  settingsHeaderRow(sectionKey: string, titleRes: Resource): void {
    Row({ space: 20 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.settingsHeaderIcon(sectionKey)
      }
      .width(32)
      .height(32)

      Text(titleRes)
        .fontSize(16)
        .fontWeight(FontWeight.Normal)
        .fontColor(this.palette().textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN, top: 12, bottom: 12 })
    .backgroundColor(this.palette().windowBackground)
    .onClick((): void => {
      this.activeSection = sectionKey;
      this.sectionRefreshSeq += 1;
    })
  }

  @Builder
  settingsHeadersMenu(): void {
    Column() {
      this.settingsHeaderRow('eh', $r('app.string.settings_eh'))
      this.settingsHeaderRow('read', $r('app.string.settings_read'))
      this.settingsHeaderRow('download', $r('app.string.settings_download'))
      this.settingsHeaderRow('privacy', $r('app.string.settings_privacy'))
      this.settingsHeaderRow('advanced', $r('app.string.settings_advanced'))
      this.settingsHeaderRow('about', $r('app.string.settings_about'))
    }
    .width('100%')
  }

  private isUserSignedIn(): boolean {
    if (!AppWiring.isWired()) {
      return false;
    }
    const cookieStore = AppWiring.getCookieStore();
    return cookieStore !== null && cookieStore.hasSignedIn();
  }

  private openSecondaryPage(url: string, params?: Record<string, Object>): void {
    const plan: RouteNavigationPlan = PageRoutes.resolveNavigation(url, this.isUserSignedIn());
    if (plan.kind === RouteActionKind.REQUIRE_SIGN_IN) {
      this.showToast(this.str(plan.tipResKey));
      return;
    }
    if (plan.kind === RouteActionKind.UNREGISTERED || plan.kind === RouteActionKind.UNKNOWN) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Secondary page %{public}s awaiting registration (kind=%{public}s)',
        url, plan.kind);
      this.showToast(this.str(plan.tipResKey));
      return;
    }
    try {
      if (params !== undefined) {
        this.getUIContext().getRouter().pushUrl({ url: url, params: params });
      } else {
        this.getUIContext().getRouter().pushUrl({ url: url });
      }
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', `Failed to open ${url}: ${JSON.stringify(err)}`);
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', `Toast failed: ${JSON.stringify(err)}`);
    }
  }

  private excludedLanguagesSummary(): string {
    if (this.excludedLanguages.length > 0) {
      return this.excludedLanguages;
    }
    return this.str('settings_eh_excluded_languages_summary');
  }

  private palette(): ThemePalette {
    return ThemeTokens.of(this.theme);
  }

  @Builder
  sectionHeader(title: ResourceStr): void {
    Text(title)
      .fontSize(ThemeTypography.PREF_CATEGORY)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.palette().colorPrimary)
      .width('100%')
      .padding({
        left: ThemeDimens.KEYLINE_MARGIN,
        right: ThemeDimens.KEYLINE_MARGIN,
        top: ThemeDimens.KEYLINE_MARGIN,
        bottom: ThemeDimens.SPACING
      })
  }

  @Builder
  sectionDivider(): void {
    Divider()
      .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
      .color(this.palette().divider)
      .margin({ top: ThemeDimens.SPACING_XS, bottom: ThemeDimens.SPACING_XS })
  }

  @Builder
  excludedLanguagesOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick(() => {
          this.excludedLangSheetOpen = false;
        })

      Column() {
        ExcludedLanguagesActivity({
          title: this.str('settings_eh_excluded_languages'),
          languageLabels: this.strs(LANGUAGE_LABEL_KEYS),
          patterns: EXCLUDED_LANGUAGE_PATTERNS,
          excludedFromSettings: this.excludedLanguages,
          themeId: this.theme,
          onSave: (excluded: string) => {
            Settings.putExcludedLanguages(excluded);
            this.excludedLanguages = excluded;
            this.excludedLangSheetOpen = false;
          },
          onCancel: () => {
            this.excludedLangSheetOpen = false;
          }
        })
      }
      .width('90%')
      .height('82%')
      .constraintSize({ maxWidth: 420, maxHeight: 620 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .clip(true)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.palette().toolbarIconColor
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .borderRadius(ThemeRadius.NONE)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.navigateBack();
        })

        Text(this.toolbarTitle())
          .fontSize(ThemeTypography.TOOLBAR_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().toolbarTitleColor)
          .layoutWeight(1)
      }
      .width('100%')
      .height(ThemeDimens.TOOLBAR_HEIGHT)
      .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.KEYLINE_MARGIN })
      .backgroundColor(this.palette().toolbarColor)
      .shadow(ThemeElevation.toolbar())

      if (!this.settingsReady) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.palette().progressColor)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            if (this.activeSection === '') {
              this.settingsHeadersMenu()
            } else if (this.activeSection === 'advanced') {
              Column() {
                this.sectionHeader($r('app.string.settings_advanced'))

                AdvancedSettingsSection({
                  refreshTrigger: this.sectionRefreshSeq,
                  themeId: this.theme,
                  onOpenPage: (url: string): void => {
                    this.openSecondaryPage(url);
                  },
                  onShowToast: (msg: ResourceStr): void => {
                    this.showToast(msg);
                  }
                })

                this.sectionDivider()

                this.sectionHeader($r('app.string.settings_network_proxy'))

            ProxyPreference({
              title: this.str('settings_advanced_proxy'),
              dialogTitle: this.str('settings_advanced_proxy'),
              themeId: this.theme,
              onChanged: (value: ProxyValue) => {
                EhApplication.getEhProxySelector(null).updateProxy();
                EhApplication.resetOkHttpClients();
                this.showToast($r('app.string.proxy_saved'));
              }
            })

            SwitchPreference({
              title: this.str('settings_advanced_domain_fronting_title'),
              summary: this.str('settings_advanced_domain_fronting_summary'),
              checked: this.domainFronting,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.domainFronting = checked;
                AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_DOMAIN_FRONTING, checked);
                EhApplication.resetOkHttpClients();
              }
            })

            SwitchPreference({
              title: this.str('settings_advanced_built_in_hosts_title'),
              summary: this.str('settings_advanced_built_in_hosts_summary'),
              checked: this.builtInHosts,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.builtInHosts = checked;
                AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_BUILT_IN_HOSTS, checked);
              }
            })

            SwitchPreference({
              title: this.str('settings_advanced_built_ex_hosts_title'),
              summary: this.str('settings_advanced_built_ex_hosts_summary'),
              checked: this.builtExHosts,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.builtExHosts = checked;
                AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_BUILT_EX_HOSTS, checked);
              }
            })

            SwitchPreference({
              title: this.str('settings_advanced_dns_over_http_title'),
              summary: this.str('settings_advanced_dns_over_http_summary'),
              checked: this.dohEnabled,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.dohEnabled = checked;
                AdvancedFragment.applyNetworkSwitch(AdvancedFragment.KEY_DOH, checked);
              }
            })

            SettingsItem({
              title: this.str('settings_advanced_custom_hosts_title'),
              summary: this.str('settings_advanced_custom_hosts_summary'),
              themeId: this.theme,
              onItemClick: () => {
                this.openSecondaryPage(PageRoutes.HOSTS);
              }
            })
              }
              .width('100%')
            } else if (this.activeSection === 'eh') {
              Column() {
                this.sectionHeader($r('app.string.settings_eh'))

            ListPreference({
              title: this.str('settings_eh_gallery_site'),
              dialogTitle: this.str('settings_eh_gallery_site'),
              entries: this.strs(['site_e', 'site_ex']),
              entryValues: GALLERY_SITE_VALUES,
              value: `${this.gallerySite}`,
              themeId: this.theme,
              onChanged: (value: string) => {
                const site: number = Number(value);
                if (!Number.isNaN(site)) {
                  Settings.putGallerySite(site);
                  this.gallerySite = site;
                }
              }
            })

            DefaultCategoryPreference({
              title: this.str('settings_eh_default_categories'),
              summary: this.str('settings_eh_default_categories_summary'),
              dialogTitle: this.str('settings_eh_default_categories'),
              themeId: this.theme
            })

            ExcludedTagNamespacesPreference({
              title: this.str('settings_eh_excluded_tag_namespaces'),
              summary: this.str('settings_eh_excluded_tag_namespaces_summary'),
              dialogTitle: this.str('settings_eh_excluded_tag_namespaces'),
              themeId: this.theme
            })

            SettingsItem({
              title: this.str('settings_eh_excluded_languages'),
              summary: this.excludedLanguagesSummary(),
              themeId: this.theme,
              onItemClick: () => {
                this.excludedLangSheetOpen = true;
              }
            })

            SettingsItem({
              title: this.str('settings_u_config'),
              summary: this.str('settings_u_config_summary'),
              themeId: this.theme,
              onItemClick: () => {
                this.openSecondaryPage(PageRoutes.U_CONFIG);
              }
            })

            SettingsItem({
              title: this.str('settings_my_tags'),
              summary: this.str('settings_my_tags_summary'),
              themeId: this.theme,
              onItemClick: () => {
                this.openSecondaryPage(PageRoutes.MY_TAGS);
              }
            })

            SettingsItem({
              title: this.str('settings_eh_filter'),
              summary: this.str('settings_eh_filter_summary'),
              themeId: this.theme,
              onItemClick: () => {
                this.openSecondaryPage(PageRoutes.FILTER);
              }
            })

            SettingsItem({
              title: this.str('settings_eh_blacklist'),
              summary: this.str('settings_eh_blacklist_summary'),
              themeId: this.theme,
              onItemClick: () => {
                this.openSecondaryPage(PageRoutes.BLACK_LIST);
              }
            })

            ListPreference({
              title: this.str('settings_eh_theme'),
              dialogTitle: this.str('settings_eh_theme'),
              entries: this.strs(['settings_eh_theme_light', 'settings_eh_theme_dark', 'settings_eh_theme_black']),
              entryValues: THEME_VALUES,
              value: `${this.theme}`,
              themeId: this.theme,
              onChanged: (value: string) => {
                const nextTheme: number = Number(value);
                if (!Number.isNaN(nextTheme)) {
                  Settings.putTheme(nextTheme);
                  syncAppThemeStorage(nextTheme);
                  applySystemBarTheme(this.getUIContext().getHostContext(), nextTheme);
                  this.theme = nextTheme;
                  this.sectionRefreshSeq += 1;
                }
              }
            })

            ListPreference({
              title: this.str('settings_eh_list_mode'),
              dialogTitle: this.str('settings_eh_list_mode'),
              entries: this.strs(['settings_eh_list_mode_detail', 'settings_eh_list_mode_thumb']),
              entryValues: LIST_MODE_VALUES,
              value: `${this.listMode}`,
              themeId: this.theme,
              onChanged: (value: string) => {
                const mode: number = Number(value);
                if (!Number.isNaN(mode)) {
                  Settings.putListMode(mode);
                  this.listMode = mode;
                }
              }
            })

            ListPreference({
              title: this.str('settings_eh_detail_size'),
              dialogTitle: this.str('settings_eh_detail_size'),
              entries: this.strs(['settings_eh_detail_size_long', 'settings_eh_detail_size_short']),
              entryValues: DETAIL_SIZE_VALUES,
              value: `${this.detailSize}`,
              themeId: this.theme,
              onChanged: (value: string) => {
                const size: number = Number(value);
                if (!Number.isNaN(size)) {
                  Settings.putDetailSize(size);
                  this.detailSize = size;
                }
              }
            })

            ListPreference({
              title: this.str('settings_eh_thumb_size'),
              dialogTitle: this.str('settings_eh_thumb_size'),
              entries: this.strs(['settings_eh_thumb_size_large', 'settings_eh_thumb_size_middle', 'settings_eh_thumb_size_small']),
              entryValues: THUMB_SIZE_VALUES,
              value: `${this.thumbSize}`,
              themeId: this.theme,
              onChanged: (value: string) => {
                const size: number = Number(value);
                if (!Number.isNaN(size)) {
                  Settings.putThumbSize(size);
                  this.thumbSize = size;
                }
              }
            })

            ListPreference({
              title: this.str('settings_eh_thumb_resolution'),
              dialogTitle: this.str('settings_eh_thumb_resolution'),
              entries: [this.str('settings_eh_thumb_resolution_auto'), '250x', '300x'],
              entryValues: THUMB_RESOLUTION_VALUES,
              value: `${this.thumbResolution}`,
              summaryFormat: this.str('settings_eh_thumb_resolution_summary'),
              themeId: this.theme,
              onChanged: (value: string) => {
                const res: number = Number(value);
                if (!Number.isNaN(res)) {
                  Settings.putThumbResolution(res);
                  this.thumbResolution = res;
                }
              }
            })

            SwitchPreference({
              title: this.str('settings_eh_show_jpn_title'),
              summary: this.str('settings_eh_show_jpn_title_summary'),
              checked: this.showJpnTitle,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.showJpnTitle = checked;
                Settings.putShowJpnTitle(checked);
                void Settings.flush();
                UConfigPageCoordinator.syncShowJpnTitleToCookieStore(AppWiring.getCookieStore(), checked);
                syncAppShowJpnTitleStorage(checked);
              }
            })

            SwitchPreference({
              title: this.str('settings_eh_show_gallery_pages'),
              summary: this.str('settings_eh_show_gallery_pages_summary'),
              checked: this.showGalleryPages,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.showGalleryPages = checked;
                Settings.putShowGalleryPages(checked);
              }
            })

            SwitchPreference({
              title: this.str('settings_eh_show_gallery_comment'),
              checked: this.showGalleryComment,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.showGalleryComment = checked;
                Settings.putShowGalleryComment(checked);
              }
            })

            SwitchPreference({
              title: this.str('need_sign_in'),
              summary: this.str('settings_eh_need_sign_in_summary'),
              checked: this.needSignIn,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.needSignIn = checked;
                Settings.putNeedSignIn(checked);
              }
            })

            SignOutPreference({
              title: this.str('settings_eh_sign_out'),
              summary: this.str('settings_eh_sign_out_summary'),
              themeId: this.theme,
              onSignOut: () => {
                this.showToast($r('app.string.settings_eh_sign_out_tip'));
              }
            })

            SwitchPreference({
              title: this.str('settings_eh_show_tag_translations'),
              summary: this.str('settings_eh_show_tag_translations_summary'),
              checked: this.showTagTranslations,
              themeId: this.theme,
              onChanged: (checked: boolean) => {
                this.showTagTranslations = checked;
                Settings.putShowTagTranslations(checked);
                if (checked) {
                  void EhTagDatabaseUpdater.update(false);
                }
              }
            })

            SettingsItem({
              title: this.str('settings_eh_tag_translations_source'),
              summary: this.tagTranslationsSourceSummary(),
              themeId: this.theme,
              onItemClick: () => {
                this.triggerTagDbUpdate();
              }
            })
              }
              .width('100%')
            } else if (this.activeSection === 'read') {
              Column() {
                this.sectionHeader($r('app.string.settings_read'))

                ReadSettingsSection({
                  refreshTrigger: this.sectionRefreshSeq,
                  themeId: this.theme
                })
              }
              .width('100%')
            } else if (this.activeSection === 'download') {
              Column() {
                this.sectionHeader($r('app.string.settings_download'))

                DownloadSettingsSection({
                  refreshTrigger: this.sectionRefreshSeq,
                  themeId: this.theme,
                  onOpenPage: (url: string): void => {
                    this.openSecondaryPage(url);
                  },
                  onShowToast: (msg: ResourceStr): void => {
                    this.showToast(msg);
                  }
                })
              }
              .width('100%')
            } else if (this.activeSection === 'privacy') {
              Column() {
                this.sectionHeader($r('app.string.settings_privacy'))

                PrivacySettingsSection({
                  refreshTrigger: this.sectionRefreshSeq,
                  themeId: this.theme,
                  onOpenPage: (url: string): void => {
                    this.openSecondaryPage(url);
                  },
                  onShowToast: (msg: ResourceStr): void => {
                    this.showToast(msg);
                  }
                })
              }
              .width('100%')
            } else if (this.activeSection === 'about') {
              Column() {
                this.sectionHeader($r('app.string.settings_about'))

                AboutSettingsSection({
                  refreshTrigger: this.sectionRefreshSeq,
                  themeId: this.theme,
                  onOpenPage: (url: string): void => {
                    this.openSecondaryPage(url);
                  },
                  onShowToast: (msg: ResourceStr): void => {
                    this.showToast(msg);
                  }
                })
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ bottom: 24 })
        }
        .align(Alignment.TopStart)
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
    .bindContentCover($$this.excludedLangSheetOpen, this.excludedLanguagesOverlay(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        this.excludedLangSheetOpen = false;
      }
    })
  }
}
