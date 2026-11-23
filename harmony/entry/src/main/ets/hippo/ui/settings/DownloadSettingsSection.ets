import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EhApplication } from '../../ehviewer/EhApplication';
import { EhDB } from '../../ehviewer/EhDB';
import { GetText } from '../../ehviewer/GetText';
import { Settings } from '../../ehviewer/Settings';
import { GalleryInfo } from '../../ehviewer/client/data/GalleryInfo';
import { ComicInfoParser } from '../../ehviewer/client/parser/ComicInfoParser';
import { DetailUrlResult } from '../../ehviewer/client/parser/GalleryDetailUrlParser';
import {
  EhEngine,
  EngineCall,
  EngineHeaders,
  EngineResponse,
  HttpCaller
} from '../../ehviewer/client/EhEngine';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { DownloadInfo } from '../../ehviewer/dao/DownloadInfo';
import { DownloadManager } from '../../ehviewer/download/DownloadManager';
import { RestoreItem, SpiderHeader } from '../../ehviewer/preference/RestoreDownloadPreference';
import { SpiderInfo } from '../../ehviewer/spider/SpiderInfo';
import { UiIntent } from '../../ehviewer/ui/fragment/DownloadFragment';
import { Call as OkCall } from '../../okhttp/Call';
import { OkHttpClient } from '../../okhttp/OkHttpClient';
import { Request } from '../../okhttp/Request';
import { Response as OkResponse } from '../../okhttp/Response';
import { ResponseBody } from '../../okhttp/ResponseBody';
import { InputStream } from '../../unifile/Contracts';
import { UniFile } from '../../unifile/UniFile';
import { Utils as UniFileUtils } from '../../unifile/Utils';
import { ThemePalette, ThemeTokens } from '../../../common/theme/ThemeTokens';
import { PageRoutes } from '../PageRoutes';
import { SettingsItem } from './SettingsItem';
import { ListPreference } from '../../preference/ListPreference';
import { SwitchPreference } from '../../preference/SwitchPreference';
import { MessagePreference } from '../../preference/MessagePreference';
import {
  CleanInvalidResult,
  CleanRedundancyRunResult,
  DownloadExportResult,
  DownloadImportResult,
  DownloadSettingsController,
  RestoreRunResult,
  SettingsTextFormatter,
  UniFileTextIo
} from './SettingsSectionHelpers';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'DownloadSettingsSection';

class RestoreEngineResponse implements EngineResponse {
  private readonly resp: OkResponse;
  private readonly bodyText: string;

  constructor(resp: OkResponse) {
    this.resp = resp;
    const body: ResponseBody | null = resp.body();
    try {
      this.bodyText = body !== null ? body.string() : '';
    } finally {
      if (body !== null) {
        try {
          body.close();
        } catch (err) {
          const msg: string = err instanceof Error ? err.message : String(err);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'RestoreEngineResponse close failed: %{public}s', msg);
        }
      }
    }
  }

  code(): number {
    return this.resp.code();
  }

  headers(): EngineHeaders {
    return this.resp.headers() as Object as EngineHeaders;
  }

  body(): string {
    return this.bodyText;
  }
}

class RestoreEngineCall implements EngineCall {
  private readonly call: OkCall;

  constructor(call: OkCall) {
    this.call = call;
  }

  async execute(): Promise<EngineResponse> {
    const resp: OkResponse = await this.call.execute();
    return new RestoreEngineResponse(resp);
  }

  isCanceled(): boolean {
    return this.call.isCanceled();
  }

  cancel(): void {
    this.call.cancel();
  }
}

class RestoreHttpCaller implements HttpCaller {
  private readonly client: OkHttpClient;

  constructor(client: OkHttpClient) {
    this.client = client;
  }

  newCall(request: Request): EngineCall {
    return new RestoreEngineCall(this.client.newCall(request));
  }
}

@Component
export struct DownloadSettingsSection {
  @Prop @Watch('onRefreshTriggerChanged') refreshTrigger: number = 0;
  @Prop themeId: number = -1;

  onOpenPage: (url: string) => void = (_url: string): void => {
  };
  onShowToast: (message: ResourceStr) => void = (_message: ResourceStr): void => {
  };

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  @State downloadLocationText: string = '';
  @State mediaScan: boolean = Settings.DEFAULT_MEDIA_SCAN;
  @State multiThreadDownload: number = Settings.DEFAULT_MULTI_THREAD_DOWNLOAD;
  @State preloadImage: number = Settings.DEFAULT_PRELOAD_IMAGE;
  @State downloadPagination: boolean = Settings.IS_DOWNLOAD_LIST_PAGINATION;
  @State imageResolution: string = Settings.DEFAULT_IMAGE_RESOLUTION;
  @State downloadOriginImage: boolean = Settings.DEFAULT_DOWNLOAD_ORIGIN_IMAGE;
  @State downloadTimeout: number = Settings.DEFAULT_DOWNLOAD_TIMEOUT;
  @State downloadOrderAsc: boolean = true;
  @State syncWhileReading: boolean = Settings.DEFAULT_SYNC_DOWNLOAD_WHILE_READING;

  @State restoring: boolean = false;
  @State restoreProgress: number = 0;
  @State restoreMax: number = 100;
  @State cleaningRedundancy: boolean = false;
  @State cleaningInvalid: boolean = false;
  @State cleanProgress: number = 0;
  @State cleanMax: number = 100;

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
    this.downloadLocationText = DownloadSettingsController.getDownloadLocationSummary(
      (key: string): string => this.str(key)
    );
    this.mediaScan = Settings.getMediaScan();
    this.multiThreadDownload = Settings.getMultiThreadDownload();
    this.preloadImage = Settings.getPreloadImage();
    this.downloadPagination = Settings.getDownloadPagination();
    this.imageResolution = Settings.getImageResolution();
    this.downloadOriginImage = Settings.getDownloadOriginImage();
    this.downloadTimeout = Settings.getDownloadTimeout();
    this.downloadOrderAsc = Settings.getDownloadOrder();
    this.syncWhileReading = Settings.getSyncDownloadWhileReading();
  }

  private showIntentToast(intent: UiIntent): void {
    const template: string = this.str(intent.resKey);
    const formatted: string = SettingsTextFormatter.format(template, intent.args);
    this.onShowToast(formatted);
  }

  private handleRestoreDownloads(): void {
    if (this.restoring) {
      return;
    }
    this.restoring = true;
    this.restoreProgress = 0;
    this.restoreMax = 100;
    this.runRestoreDownloadsAsync().catch((err: Error): void => {
      this.restoring = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Restore download items failed: %{public}s', err.message);
      this.onShowToast($r('app.string.settings_download_restore_failed'));
    });
  }

  private async runRestoreDownloadsAsync(): Promise<void> {
    const dm: DownloadManager = await DownloadManager.getInstance();
    const ctx: common.Context | undefined = this.hostContext;
    const filledInfoMap: Map<number, GalleryInfo> = new Map<number, GalleryInfo>();

    const result: RestoreRunResult = await DownloadSettingsController.runRestoreDownloads(
      (gid: number): boolean => dm.containDownloadInfo(gid),
      (file: UniFile): SpiderHeader | null => {
        const info: SpiderInfo | null = SpiderInfo.readHeader(file) ?? SpiderInfo.readCborHeader(file);
        if (info === null || info.gid < 0 || info.token === null || info.token.length === 0) {
          return null;
        }
        return new SpiderHeader(info.gid, info.token);
      },
      async (items: RestoreItem[]): Promise<Map<number, string>> => {
        const list: GalleryInfo[] = [];
        for (let i = 0; i < items.length; i++) {
          const gi: GalleryInfo = new GalleryInfo();
          gi.gid = items[i].gid;
          gi.token = items[i].token !== null ? items[i].token as string : '';
          list.push(gi);
        }
        const caller: RestoreHttpCaller = new RestoreHttpCaller(
          EhApplication.getOkHttpClient(ctx !== undefined ? ctx : null)
        );
        await EhEngine.fillGalleryListByApiBestEffort(null, caller, list, EhUrl.getReferer());
        const titles: Map<number, string> = new Map<number, string>();
        for (let i = 0; i < list.length; i++) {
          const gi: GalleryInfo = list[i];
          if (gi.title !== undefined && gi.title !== null && gi.title.length > 0) {
            titles.set(gi.gid, gi.title);
            filledInfoMap.set(gi.gid, gi);
          }
        }
        return titles;
      },
      (item: RestoreItem, title: string): void => {
        const existing: GalleryInfo | undefined = filledInfoMap.get(item.gid);
        const gi: GalleryInfo = existing !== undefined ? existing : new GalleryInfo();
        gi.gid = item.gid;
        if (item.token !== null) {
          gi.token = item.token;
        }
        if (gi.title.length === 0) {
          gi.title = title;
        }
        dm.addDownloadWithStateNone(gi, null).catch((err: Error): void => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'addDownloadWithStateNone gid=%{public}d failed: %{public}s',
            item.gid, err.message);
        });
      },
      async (gid: number, dirname: string): Promise<void> => {
        await EhDB.putDownloadDirname(gid, dirname);
      },
      (progress: number, max: number): void => {
        if (max > 0) {
          this.restoreProgress = progress;
          this.restoreMax = max;
        }
      },
      undefined,
      (dir: UniFile): SpiderHeader | null => {
        const comicFile: UniFile | null = dir.findFile(ComicInfoParser.FILENAME);
        if (comicFile === null) {
          return null;
        }
        let is: InputStream | null = null;
        try {
          is = comicFile.openInputStream();
          const parsed: DetailUrlResult | null = ComicInfoParser.parseStream(is);
          if (parsed === null || parsed.gid < 0 || parsed.token.length === 0) {
            return null;
          }
          return new SpiderHeader(parsed.gid, parsed.token);
        } catch (e) {
          UniFileUtils.throwIfFatal(e);
          return null;
        } finally {
          UniFileUtils.closeQuietly(is);
        }
      }
    );

    this.restoring = false;
    if (result.toastArg !== null) {
      const msg: string = SettingsTextFormatter.format(this.str(result.toastResKey), [result.toastArg]);
      this.onShowToast(msg);
    } else {
      this.onShowToast(this.str(result.toastResKey));
    }
  }

  private handleCleanRedundancy(): void {
    if (this.cleaningRedundancy) {
      return;
    }
    this.cleaningRedundancy = true;
    this.runCleanRedundancyAsync().catch((err: Error): void => {
      this.cleaningRedundancy = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Clean redundancy failed: %{public}s', err.message);
      this.onShowToast($r('app.string.settings_download_cant_get_download_location'));
    });
  }

  private async runCleanRedundancyAsync(): Promise<void> {
    const dm: DownloadManager = await DownloadManager.getInstance();
    const res: CleanRedundancyRunResult = await DownloadSettingsController.runCleanRedundancy(
      (gid: number): boolean => dm.containDownloadInfo(gid)
    );
    this.cleaningRedundancy = false;
    if (res.toastArg !== null) {
      const msg: string = SettingsTextFormatter.format(this.str(res.toastResKey), [res.toastArg]);
      this.onShowToast(msg);
    } else {
      this.onShowToast(this.str(res.toastResKey));
    }
  }

  private handleExportDownloadItems(): void {
    this.runExportDownloadItemsAsync().catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Export download items failed: %{public}s', err.message);
      this.onShowToast($r('app.string.settings_download_export_failed'));
    });
  }

  private async runExportDownloadItemsAsync(): Promise<void> {
    const dm: DownloadManager = await DownloadManager.getInstance();
    const items: DownloadInfo[] = dm.getAllDownloadInfoList();
    const dir: UniFile | null = Settings.getDownloadLocation();
    const res: DownloadExportResult = DownloadSettingsController.exportDownloadItems(items, dir);
    this.showIntentToast(res.toast);
  }

  private handleImportDownloadItems(): void {
    this.runImportDownloadItemsAsync().catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Import download items failed: %{public}s', err.message);
      this.onShowToast($r('app.string.settings_download_import_failed'));
    });
  }

  private async runImportDownloadItemsAsync(): Promise<void> {
    const ctx: common.Context | undefined = this.hostContext;
    const docPicker: picker.DocumentViewPicker = ctx !== undefined
      ? new picker.DocumentViewPicker(ctx)
      : new picker.DocumentViewPicker();
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.csv'];

    const uris: Array<string> = await docPicker.select(options);
    if (uris.length === 0 || uris[0].length === 0) {
      return;
    }
    const file: UniFile | null = UniFile.fromUri(uris[0]);
    if (file === null) {
      this.onShowToast($r('app.string.settings_download_import_failed'));
      return;
    }
    const csvContent: string | null = UniFileTextIo.readUtf8(file);
    if (csvContent === null) {
      this.onShowToast($r('app.string.settings_download_import_failed'));
      return;
    }
    const dm: DownloadManager = await DownloadManager.getInstance();
    const res: DownloadImportResult = await DownloadSettingsController.importDownloadItemsFromContent(
      csvContent,
      (gid: number): boolean => dm.getDownloadInfo(gid) !== null,
      async (gi: GalleryInfo): Promise<void> => {
        await dm.addDownloadWithStateNone(gi, null);
      }
    );
    this.showIntentToast(res.toast);
  }

  private handleCleanInvalidDownloads(): void {
    if (this.cleaningInvalid) {
      return;
    }
    this.cleaningInvalid = true;
    this.cleanProgress = 0;
    this.cleanMax = 100;
    this.runCleanInvalidDownloadsAsync().catch((err: Error): void => {
      this.cleaningInvalid = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Clean invalid downloads failed: %{public}s', err.message);
      this.onShowToast($r('app.string.settings_download_clean_invalid_no_invalid'));
    });
  }

  private async runCleanInvalidDownloadsAsync(): Promise<void> {
    const dm: DownloadManager = await DownloadManager.getInstance();
    const dir: UniFile | null = Settings.getDownloadLocation();
    const res: CleanInvalidResult = await DownloadSettingsController.cleanInvalidDownloads(
      dir,
      async (gid: number): Promise<void> => {
        const info: DownloadInfo | null = await dm.getNoneDownloadInfo(gid);
        if (info !== null) {
          info.state = DownloadInfo.STATE_NONE;
          await EhDB.putDownloadInfo(info);
        }
      },
      undefined,
      (done: number, total: number): void => {
        if (total > 0) {
          this.cleanProgress = done;
          this.cleanMax = total;
        }
      }
    );
    this.cleaningInvalid = false;
    this.showIntentToast(res.toast);
  }

  build() {
    Column() {
      SettingsItem({
        title: this.str('settings_download_download_location'),
        summary: this.downloadLocationText.length > 0
          ? this.downloadLocationText
          : this.str('settings_download_invalid_download_location'),
        themeId: this.themeId,
        onItemClick: () => {
          this.onOpenPage(PageRoutes.DIR_PICKER);
        }
      })

      SwitchPreference({
        title: this.str('settings_download_media_scan'),
        summary: this.mediaScan
          ? this.str('settings_download_media_scan_summary_on')
          : this.str('settings_download_media_scan_summary_off'),
        checked: this.mediaScan,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.mediaScan = checked;
          DownloadSettingsController.applyMediaScanChange(checked);
        }
      })

      ListPreference({
        title: this.str('settings_download_multi_thread_download'),
        dialogTitle: this.str('settings_download_multi_thread_download'),
        entries: DownloadSettingsController.MULTI_THREAD_VALUES,
        entryValues: DownloadSettingsController.MULTI_THREAD_VALUES,
        value: `${this.multiThreadDownload}`,
        summaryFormat: this.str('settings_download_multi_thread_download_summary'),
        themeId: this.themeId,
        onChanged: (value: string) => {
          const threads: number = Number(value);
          if (!Number.isNaN(threads)) {
            Settings.putMultiThreadDownload(threads);
            this.multiThreadDownload = threads;
          }
        }
      })

      ListPreference({
        title: this.str('settings_download_preload_image'),
        dialogTitle: this.str('settings_download_preload_image'),
        entries: DownloadSettingsController.PRELOAD_IMAGE_VALUES,
        entryValues: DownloadSettingsController.PRELOAD_IMAGE_VALUES,
        value: `${this.preloadImage}`,
        summaryFormat: this.str('settings_download_preload_image_summary'),
        themeId: this.themeId,
        onChanged: (value: string) => {
          const preload: number = Number(value);
          if (!Number.isNaN(preload)) {
            Settings.putPreloadImage(preload);
            this.preloadImage = preload;
          }
        }
      })

      SwitchPreference({
        title: this.str('settings_download_download_list_pagination'),
        summary: this.str('settings_download_download_list_pagination_summary'),
        checked: this.downloadPagination,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.downloadPagination = checked;
          Settings.setDownloadPagination(checked);
        }
      })

      ListPreference({
        title: this.str('settings_download_image_resolution'),
        dialogTitle: this.str('settings_download_image_resolution'),
        entries: [
          this.str('settings_download_image_resolution_auto'),
          '780x',
          '1280x',
          '1600x',
          '2400x'
        ],
        entryValues: DownloadSettingsController.IMAGE_RESOLUTION_VALUES,
        value: this.imageResolution,
        summaryFormat: this.str('settings_download_image_resolution_summary'),
        themeId: this.themeId,
        onChanged: (value: string) => {
          const saved: string | null = DownloadSettingsController.applyImageResolution(value);
          if (saved !== null) {
            this.imageResolution = saved;
          }
        }
      })

      SwitchPreference({
        title: this.str('settings_download_download_origin_image'),
        summary: this.str('settings_download_download_origin_image_summary'),
        checked: this.downloadOriginImage,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.downloadOriginImage = checked;
          Settings.putDownloadOriginImage(checked);
        }
      })

      ListPreference({
        title: this.str('settings_download_timeout'),
        dialogTitle: this.str('settings_download_timeout'),
        entries: [
          this.str('download_timeout_unlimited'),
          '10',
          '30',
          '50',
          '100',
          '200',
          '300'
        ],
        entryValues: DownloadSettingsController.DOWNLOAD_TIMEOUT_VALUES,
        value: `${this.downloadTimeout}`,
        summaryFormat: this.str('settings_download_timeout_summary'),
        themeId: this.themeId,
        onChanged: (value: string) => {
          const timeout: number = DownloadSettingsController.applyDownloadTimeout(value);
          this.downloadTimeout = timeout;
        }
      })

      SwitchPreference({
        title: this.str('settings_download_download_order_by_asc'),
        summary: this.str('settings_download_download_order_by_asc_summary'),
        checked: this.downloadOrderAsc,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.downloadOrderAsc = checked;
          Settings.setDownloadOrder(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_download_sync_while_reading'),
        summary: this.str('settings_download_sync_while_reading_summary'),
        checked: this.syncWhileReading,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.syncWhileReading = checked;
          Settings.putSyncDownloadWhileReading(checked);
        }
      })

      SettingsItem({
        title: this.str('settings_download_restore_download_items'),
        summary: this.restoring
          ? this.str('settings_download_restoring')
          : this.str('settings_download_restore_download_items_summary'),
        selectable: !this.restoring,
        themeId: this.themeId,
        onItemClick: () => {
          this.handleRestoreDownloads();
        }
      })

      if (this.restoring) {
        Progress({ value: this.restoreProgress, total: this.restoreMax })
          .width('100%')
          .color(this.palette().progressColor)
          .backgroundColor(this.palette().divider)
          .padding({ left: 16, right: 16, bottom: 8 })
      }

      SettingsItem({
        title: this.str('settings_download_clean_redundancy'),
        summary: this.cleaningRedundancy
          ? this.str('settings_download_cleaning')
          : this.str('settings_download_clean_redundancy_summary'),
        selectable: !this.cleaningRedundancy,
        themeId: this.themeId,
        onItemClick: () => {
          this.handleCleanRedundancy();
        }
      })

      SettingsItem({
        title: this.str('settings_download_export_items'),
        summary: this.str('settings_download_export_items_summary'),
        themeId: this.themeId,
        onItemClick: () => {
          this.handleExportDownloadItems();
        }
      })

      SettingsItem({
        title: this.str('settings_download_import_items'),
        themeId: this.themeId,
        onItemClick: () => {
          this.handleImportDownloadItems();
        }
      })

      MessagePreference({
        title: this.str('settings_download_clean_invalid_download'),
        summary: this.cleaningInvalid
          ? this.str('settings_download_cleaning')
          : this.str('settings_download_clean_invalid_download_summary'),
        dialogTitle: $r('app.string.settings_download_clean_invalid_download'),
        message: $r('app.string.settings_download_clean_invalid_download_confirm'),
        showNegativeButton: true,
        itemEnabled: !this.cleaningInvalid,
        themeId: this.themeId,
        onShown: () => {
          this.handleCleanInvalidDownloads();
        }
      })

      if (this.cleaningInvalid) {
        Progress({ value: this.cleanProgress, total: this.cleanMax })
          .width('100%')
          .color(this.palette().progressColor)
          .backgroundColor(this.palette().divider)
          .padding({ left: 16, right: 16, bottom: 8 })
      }
    }
    .width('100%')
  }
}
