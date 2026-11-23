import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppWiring } from '../../AppWiring';
import { AppConfig } from '../../ehviewer/AppConfig';
import { EhApplication } from '../../ehviewer/EhApplication';
import { EhDB } from '../../ehviewer/EhDB';
import { GetText } from '../../ehviewer/GetText';
import { Settings } from '../../ehviewer/Settings';
import { DownloadInfo } from '../../ehviewer/dao/DownloadInfo';
import { DownloadLabel } from '../../ehviewer/dao/DownloadLabel';
import { DownloadManager } from '../../ehviewer/download/DownloadManager';
import { ClearDownloadPathCachePreference } from '../../ehviewer/preference/ClearDownloadPathCachePreference';
import { ExportDataPreference } from '../../ehviewer/preference/ExportDataPreference';
import { PreferenceActions } from '../../ehviewer/preference/PreferenceActions';
import { AdvancedFragment, SettingsLoadingStatusStore } from '../../ehviewer/ui/fragment/AdvancedFragment';
import { Contracts } from '../../unifile/Contracts';
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { PageRoutes } from '../PageRoutes';
import { SettingsItem } from './SettingsItem';
import { ListPreference } from '../../preference/ListPreference';
import { SwitchPreference } from '../../preference/SwitchPreference';
import {
  AdvancedSettingsHelpers,
  DbExportResult,
  DbImportResult,
  LogcatDumpResult,
  SettingsAdvancedActions,
  SettingsTextFormatter
} from './SettingsSectionHelpers';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'AdvancedSettingsSection';
const IMPORT_TEMP_DB_NAME: string = 'eh.import.tmp.db';

@Component
export struct AdvancedSettingsSection {
  @Prop @Watch('onRefreshTriggerChanged') refreshTrigger: number = 0;
  @Prop themeId: number = -1;

  onOpenPage: (url: string) => void = (_url: string): void => {
  };
  onShowToast: (message: ResourceStr) => void = (_message: ResourceStr): void => {
  };

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  @State saveParseErrorBody: boolean = Settings.DEFAULT_SAVE_PARSE_ERROR_BODY;
  @State saveCrashLog: boolean = Settings.DEFAULT_SAVE_CRASH_LOG;
  @State readCacheSize: number = Settings.DEFAULT_READ_CACHE_SIZE;
  @State appLanguage: string = Settings.DEFAULT_APP_LANGUAGE;
  @State dbImporting: boolean = false;
  @State dbImportProgress: number = 0;
  @State backupSheetOpen: boolean = false;
  @State backupFiles: string[] = [];

  private hostContext: common.Context | undefined = undefined;
  private loadingStore: SettingsLoadingStatusStore = new SettingsLoadingStatusStore();
  private fragment: AdvancedFragment | null = null;
  private backupDataDir: string = '';

  aboutToAppear(): void {
    this.hostContext = this.getUIContext().getHostContext();
    if (this.hostContext !== undefined && !GetText.isInitialized()) {
      GetText.initialize(this.hostContext);
    }
    const actions: SettingsAdvancedActions = new SettingsAdvancedActions(
      (): Promise<void> => this.handleDumpLogcat(),
      (): Promise<void> => this.handleClearMemoryCache(),
      (): void => this.handleAppLanguageChanged(),
      (): Promise<void> => this.handleImportDataClick(),
      (): void => {
        this.onOpenPage(PageRoutes.WIFI_SERVER);
      },
      (): void => {
        this.onOpenPage(PageRoutes.WIFI_CLIENT);
      }
    );
    this.fragment = new AdvancedFragment(this.loadingStore, actions);
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

  private strs(keys: string[]): string[] {
    const out: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      out.push(this.str(keys[i]));
    }
    return out;
  }

  private syncFromSettings(): void {
    this.saveParseErrorBody = Settings.getSaveParseErrorBody();
    this.saveCrashLog = Settings.getSaveCrashLog();
    this.readCacheSize = Settings.getReadCacheSize();
    this.appLanguage = Settings.getAppLanguage();
    if (this.fragment !== null) {
      this.dbImporting = this.fragment.isDbLoading();
      this.dbImportProgress = this.fragment.getDbProgress();
    }
  }

  private async handleDumpLogcat(): Promise<void> {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined && !AppConfig.isInitialized()) {
      AppConfig.initialize(ctx);
    }
    const res: LogcatDumpResult = await AdvancedSettingsHelpers.dumpDiagnosticLogcat();
    if (res.ok) {
      const msg: string = SettingsTextFormatter.format(this.str(res.toastResKey), [res.filePath]);
      this.onShowToast(msg);
    } else {
      this.onShowToast($r('app.string.settings_advanced_dump_logcat_failed'));
    }
  }

  private async handleClearMemoryCache(): Promise<void> {
    const app: EhApplication | null = EhApplication.getInstance();
    if (app !== null) {
      app.clearMemoryCache();
    }
    this.onShowToast($r('app.string.settings_advanced_clear_memory_cache'));
  }

  private handleAppLanguageChanged(): void {
    this.onShowToast($r('app.string.settings_advanced_app_language_title'));
  }

  private clearDownloadPathCache(): void {
    PreferenceActions.clearDownloadPathCache((): Promise<void> => {
      return EhDB.clearDownloadDirname();
    }).then((): void => {
      this.onShowToast($r('app.string.settings_advanced_clear_download_path_cache_done'));
    }).catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to clear download path cache: %{public}s', err.message);
    });
  }

  private async runExportDb(): Promise<boolean> {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx === undefined) {
      this.onShowToast($r('app.string.settings_advanced_export_data_failed'));
      return false;
    }
    if (!AppConfig.isInitialized()) {
      AppConfig.initialize(ctx);
    }
    const result: DbExportResult = await AdvancedSettingsHelpers.runExportDatabase(
      async (targetPath: string): Promise<boolean> => {
        const mainConfig: relationalStore.StoreConfig = {
          name: AppWiring.DB_NAME,
          securityLevel: relationalStore.SecurityLevel.S1
        };
        const mainStore: relationalStore.RdbStore = await relationalStore.getRdbStore(ctx, mainConfig);
        return await EhDB.exportDB(
          mainStore,
          targetPath,
          async (exportName: string): Promise<relationalStore.RdbStore> => {
            const expConfig: relationalStore.StoreConfig = {
              name: exportName,
              securityLevel: relationalStore.SecurityLevel.S1
            };
            return await relationalStore.getRdbStore(ctx, expConfig);
          },
          async (exportName: string): Promise<void> => {
            await relationalStore.deleteRdbStore(ctx, exportName);
          }
        );
      }
    );
    if (result.ok) {
      const msg: string = SettingsTextFormatter.format(this.str(result.toastResKey), [result.filePath]);
      this.onShowToast(msg);
      return true;
    }
    this.onShowToast($r('app.string.settings_advanced_export_data_failed'));
    return false;
  }

  private async handleImportDataClick(): Promise<void> {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined && !AppConfig.isInitialized()) {
      AppConfig.initialize(ctx);
    }
    const dataDir: string | null = AppConfig.getExternalDataDir();
    if (dataDir === null) {
      this.onShowToast($r('app.string.cant_get_data_dir'));
      return;
    }
    const files: string[] | null = AdvancedSettingsHelpers.listBackupFiles(dataDir);
    if (files !== null && files.length > 0) {
      this.backupDataDir = dataDir;
      this.backupFiles = files;
      this.backupSheetOpen = true;
      return;
    }
    await this.pickAndImportDbFile();
  }

  private async pickAndImportDbFile(): Promise<void> {
    const ctx: common.Context | undefined = this.hostContext;
    const docPicker: picker.DocumentViewPicker = ctx !== undefined
      ? new picker.DocumentViewPicker(ctx)
      : new picker.DocumentViewPicker();
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.db'];
    try {
      const uris: Array<string> = await docPicker.select(options);
      if (uris.length === 0 || uris[0].length === 0) {
        return;
      }
      await this.importDbFromSourcePath(Contracts.toPath(uris[0]));
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'DocumentViewPicker DB selection failed: %{public}s', msg);
      this.onShowToast($r('app.string.cant_find_any_data'));
    }
  }

  private async importDbFromSourcePath(sourcePath: string): Promise<void> {
    const ctx: common.Context | undefined = this.hostContext;
    const frag: AdvancedFragment | null = this.fragment;
    if (ctx === undefined || frag === null) {
      this.onShowToast($r('app.string.cant_read_the_file'));
      return;
    }
    this.backupSheetOpen = false;
    this.dbImporting = true;
    this.dbImportProgress = 0;

    const result: DbImportResult = await AdvancedSettingsHelpers.runImportDatabase(
      frag,
      this.loadingStore,
      async (onProgress: (percent: number) => void): Promise<string | null> => {
        const dbDir: string = ctx.databaseDir;
        const rdbDir: string = `${dbDir}/rdb`;
        try {
          if (!fs.accessSync(rdbDir)) {
            fs.mkdirSync(rdbDir, true);
          }
        } catch (mkErr) {
          const msg: string = mkErr instanceof Error ? mkErr.message : String(mkErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'ensure rdbDir failed: %{public}s', msg);
        }
        try {
          await relationalStore.deleteRdbStore(ctx, IMPORT_TEMP_DB_NAME);
        } catch (delErr) {
          const msg: string = delErr instanceof Error ? delErr.message : String(delErr);
          hilog.debug(LOG_DOMAIN, LOG_TAG, 'pre-clean temp import db skipped: %{public}s', msg);
        }

        const tempDbPath: string = `${rdbDir}/${IMPORT_TEMP_DB_NAME}`;
        fs.copyFileSync(sourcePath, tempDbPath);

        const importConfig: relationalStore.StoreConfig = {
          name: IMPORT_TEMP_DB_NAME,
          securityLevel: relationalStore.SecurityLevel.S1
        };
        let importStore: relationalStore.RdbStore | null = null;
        try {
          importStore = await relationalStore.getRdbStore(ctx, importConfig);
          const dm: DownloadManager = await DownloadManager.getInstance();
          return await EhDB.importDB(
            importStore,
            (percent: number): void => {
              this.dbImportProgress = percent;
              onProgress(percent);
            },
            async (list: DownloadInfo[]): Promise<void> => {
              await dm.addDownloadList(list);
            },
            async (labels: DownloadLabel[]): Promise<void> => {
              await dm.addDownloadLabel(labels);
            }
          );
        } finally {
          if (importStore !== null) {
            try {
              await importStore.close();
            } catch (closeErr) {
              const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'close temp import db failed: %{public}s', msg);
            }
          }
          try {
            await relationalStore.deleteRdbStore(ctx, IMPORT_TEMP_DB_NAME);
          } catch (cleanupErr) {
            const msg: string = cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr);
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'delete temp import db failed: %{public}s', msg);
          }
        }
      }
    );

    this.dbImporting = false;
    this.dbImportProgress = 100;
    this.onShowToast(this.str(result.toastResKey));
  }

  @Builder
  backupFilesOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.backupSheetOpen = false;
        })

      Column() {
        Text($r('app.string.settings_advanced_import_data'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        List() {
          ForEach(this.backupFiles, (fileName: string) => {
            ListItem() {
              Row() {
                Text(fileName)
                  .fontSize(ThemeTypography.PREF_TITLE)
                  .fontColor(this.palette().textPrimary)
                  .layoutWeight(1)
              }
              .width('100%')
              .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
              .padding({ left: 24, right: 24, top: 10, bottom: 10 })
              .onClick(() => {
                const fullPath: string = Contracts.childOf(this.backupDataDir, fileName);
                this.importDbFromSourcePath(fullPath).catch((err: Error): void => {
                  hilog.error(LOG_DOMAIN, LOG_TAG, 'importDbFromSourcePath failed: %{public}s', err.message);
                  this.dbImporting = false;
                  this.onShowToast($r('app.string.cant_read_the_file'));
                });
              })
            }
          }, (fileName: string) => fileName)
        }
        .width('100%')
        .constraintSize({ maxHeight: 320 })

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.open_directory'))
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
            this.backupSheetOpen = false;
            this.pickAndImportDbFile().catch((err: Error): void => {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'pickAndImportDbFile failed: %{public}s', err.message);
            });
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
            this.backupSheetOpen = false;
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 360 })
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
      SwitchPreference({
        title: this.str('settings_advanced_save_parse_error_body'),
        summary: this.str('settings_advanced_save_parse_error_body_summary'),
        checked: this.saveParseErrorBody,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.saveParseErrorBody = checked;
          Settings.putSaveParseErrorBody(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_advanced_save_crash_log'),
        summary: this.str('settings_advanced_save_crash_log_summary'),
        checked: this.saveCrashLog,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.saveCrashLog = checked;
          Settings.putSaveCrashLog(checked);
        }
      })

      SettingsItem({
        title: this.str('settings_advanced_dump_logcat'),
        summary: this.str('settings_advanced_dump_logcat_summary'),
        themeId: this.themeId,
        onItemClick: () => {
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AdvancedFragment.KEY_DUMP_LOGCAT);
          }
        }
      })

      ClearDownloadPathCachePreference({
        title: this.str('settings_advanced_clear_download_path_cache'),
        summary: this.str('settings_advanced_clear_download_path_cache_summary'),
        themeId: this.themeId,
        onClear: () => {
          this.clearDownloadPathCache();
        }
      })

      SettingsItem({
        title: this.str('settings_advanced_clear_memory_cache'),
        summary: this.str('settings_advanced_clear_memory_cache_summary'),
        themeId: this.themeId,
        onItemClick: () => {
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AdvancedFragment.KEY_CLEAR_MEMORY_CACHE);
          }
        }
      })

      ListPreference({
        title: this.str('settings_advanced_read_cache_size'),
        dialogTitle: this.str('settings_advanced_read_cache_size'),
        entries: AdvancedSettingsHelpers.READ_CACHE_SIZE_ENTRIES,
        entryValues: AdvancedSettingsHelpers.READ_CACHE_SIZE_VALUES,
        value: `${this.readCacheSize}`,
        themeId: this.themeId,
        onChanged: (value: string) => {
          const size: number = Number(value);
          if (!Number.isNaN(size)) {
            Settings.putReadCacheSize(size);
            this.readCacheSize = size;
          }
        }
      })

      ListPreference({
        title: this.str('settings_advanced_app_language_title'),
        dialogTitle: this.str('settings_advanced_app_language_title'),
        entries: this.strs(AdvancedSettingsHelpers.APP_LANGUAGE_LABEL_KEYS),
        entryValues: AdvancedSettingsHelpers.APP_LANGUAGE_VALUES,
        value: this.appLanguage,
        themeId: this.themeId,
        onChanged: (value: string) => {
          Settings.putAppLanguage(value);
          this.appLanguage = value;
          const ctx: common.Context | undefined = this.getUIContext().getHostContext();
          AdvancedSettingsHelpers.applyAppLanguage(ctx, value);
          this.onShowToast($r('app.string.settings_advanced_app_language_applied'));
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AdvancedFragment.KEY_APP_LANGUAGE);
          }
        }
      })

      ExportDataPreference({
        title: this.str('settings_advanced_export_data'),
        summary: this.str('settings_advanced_export_data_summary'),
        themeId: this.themeId,
        runExport: (): Promise<boolean> => this.runExportDb(),
        onFinished: (_ok: boolean) => {
        }
      })

      SettingsItem({
        title: this.str('settings_advanced_import_data'),
        summary: this.dbImporting
          ? this.str('loading_db_file')
          : this.str('settings_advanced_import_data_summary'),
        selectable: !this.dbImporting,
        themeId: this.themeId,
        onItemClick: () => {
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AdvancedFragment.KEY_IMPORT_DATA);
          }
        }
      })

      if (this.dbImporting) {
        Progress({ value: this.dbImportProgress, total: 100 })
          .width('100%')
          .color(this.palette().progressColor)
          .backgroundColor(this.palette().divider)
          .padding({ left: 16, right: 16, bottom: 8 })
      }

      SettingsItem({
        title: this.str('settings_advanced_wifi_sender'),
        summary: this.str('settings_advanced_wifi_sander_summary'),
        themeId: this.themeId,
        onItemClick: () => {
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AdvancedFragment.KEY_WIFI_SERVER);
          }
        }
      })

      SettingsItem({
        title: this.str('settings_advanced_wifi_client'),
        summary: this.str('settings_advanced_wifi_client_summary'),
        themeId: this.themeId,
        onItemClick: () => {
          if (this.fragment !== null) {
            this.fragment.onPreferenceClick(AdvancedFragment.KEY_WIFI_CLIENT);
          }
        }
      })
    }
    .width('100%')
    .bindContentCover($$this.backupSheetOpen, this.backupFilesOverlay(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        this.backupSheetOpen = false;
      }
    })
  }
}
