import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { AppConfig } from '../hippo/ehviewer/AppConfig';
import { GetText } from '../hippo/ehviewer/GetText';
import { Settings } from '../hippo/ehviewer/Settings';
import { DirPickerActivity } from '../hippo/ehviewer/ui/DirPickerActivity';
import { SceneArgs } from '../hippo/scene/SceneTypes';
import { UniFile } from '../hippo/unifile/UniFile';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VFolderMoveDarkX24 } from '../hippo/ui/drawable/v_folder_move_dark_x24';
import {
  DirPickerHelpers,
  SandboxDirectoryExplorer
} from '../hippo/ui/settings/SettingsSectionHelpers';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'DirPickerPage';

@Entry
@Component
export struct DirPickerPage {
  @State ready: boolean = false;
  @State currentPath: string = '';
  @State entries: string[] = [];
  @State loading: boolean = false;

  private hostContext: common.Context | undefined = undefined;
  private controller: DirPickerActivity = new DirPickerActivity();
  private explorer: SandboxDirectoryExplorer | null = null;

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    this.hostContext = ctx;
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.explorer = new SandboxDirectoryExplorer((loadedPath: string, list: string[]): void => {
      this.currentPath = loadedPath;
      this.entries = list.slice();
      this.loading = false;
    });
    this.controller.setExplorer(this.explorer);

    this.initializeDirPicker(ctx).catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'initializeDirPicker failed: %{public}s', err.message);
      this.ready = true;
      this.loading = false;
    });
  }

  private async initializeDirPicker(ctx: common.Context | undefined): Promise<void> {
    if (ctx !== undefined && !AppConfig.isInitialized()) {
      AppConfig.initialize(ctx);
    }
    if (AppWiring.isWired()) {
      await AppWiring.whenReady();
    } else if (ctx !== undefined && !Settings.isAttached()) {
      await Settings.attach(ctx);
    }

    let paramPath: string | null = null;
    try {
      const rawParams: Object = this.getUIContext().getRouter().getParams();
      if (rawParams !== undefined && rawParams !== null) {
        const record: Record<string, Object> = rawParams as Record<string, Object>;
        const pathVal: Object | undefined = record[DirPickerActivity.KEY_FILE_PATH];
        const uriVal: Object | undefined = record[DirPickerActivity.KEY_FILE_URI];
        if (typeof pathVal === 'string' && pathVal.length > 0) {
          paramPath = pathVal;
        } else if (typeof uriVal === 'string' && uriVal.length > 0) {
          paramPath = uriVal;
        }
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to read DirPickerPage router params: %{public}s', JSON.stringify(err));
    }

    const currentLoc: UniFile | null = Settings.getDownloadLocation();
    const defaultDir: string | null = AppConfig.getDefaultDownloadDir();
    const initialPath: string = DirPickerHelpers.resolveInitialPath(paramPath, currentLoc, defaultDir);

    this.currentPath = initialPath;
    this.loading = true;
    const args: SceneArgs = new Map<string, Object>();
    args.set(DirPickerActivity.KEY_FILE_PATH, initialPath);
    this.controller.init(args);
    this.ready = true;
  }

  private navigateBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Router back failed: %{public}s', JSON.stringify(err));
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Toast failed: %{public}s', JSON.stringify(err));
    }
  }

  private onGoUp(): void {
    if (!DirPickerHelpers.canGoUp(this.currentPath)) {
      return;
    }
    this.loading = true;
    this.controller.goUp();
    this.currentPath = this.controller.getCurrentPath();
  }

  private onEnterDirectory(path: string): void {
    this.loading = true;
    this.controller.enter(path);
    this.currentPath = this.controller.getCurrentPath();
  }

  private onResetDefault(): void {
    const defaultDir: string | null = AppConfig.getDefaultDownloadDir();
    if (defaultDir === null || defaultDir.length === 0) {
      this.showToast($r('app.string.directory_not_writable'));
      return;
    }
    this.loading = true;
    this.controller.resetToDefault(defaultDir);
    this.currentPath = this.controller.getCurrentPath();
  }

  private onPickViaSystemPicker(): void {
    this.launchSystemDirectoryPicker().catch((err: Error): void => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'DocumentViewPicker directory pick failed: %{public}s', err.message);
      this.showToast($r('app.string.directory_not_writable'));
    });
  }

  private async launchSystemDirectoryPicker(): Promise<void> {
    const ctx: common.Context | undefined = this.hostContext;
    const viewPicker: picker.DocumentViewPicker = ctx !== undefined
      ? new picker.DocumentViewPicker(ctx)
      : new picker.DocumentViewPicker();
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.selectMode = picker.DocumentSelectMode.FOLDER;

    let selected: Array<string> = [];
    try {
      selected = await viewPicker.select(options);
    } catch (folderErr) {
      const msg: string = folderErr instanceof Error ? folderErr.message : String(folderErr);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'DocumentSelectMode.FOLDER unsupported or failed, trying default picker: %{public}s',
        msg);
      const fallbackOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      fallbackOptions.maxSelectNumber = 1;
      selected = await viewPicker.select(fallbackOptions);
    }

    if (selected.length === 0 || selected[0].length === 0) {
      return;
    }
    const pickedUri: string = selected[0];
    if (this.explorer !== null) {
      this.explorer.markAuthorizedPickerUri(pickedUri);
    }
    this.loading = true;
    this.controller.enter(pickedUri);
    this.currentPath = pickedUri;
  }

  private onConfirm(): void {
    this.controller.confirm().then((confirmedPath: string | null): void => {
      if (confirmedPath === null || confirmedPath.length === 0) {
        this.showToast($r('app.string.directory_not_writable'));
        return;
      }
      const location: UniFile | null = DirPickerHelpers.resolveDownloadLocationUniFile(confirmedPath);
      if (location === null) {
        this.showToast($r('app.string.settings_download_invalid_download_location'));
        return;
      }
      Settings.putDownloadLocation(location);
      this.navigateBack();
    }).catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'DirPicker confirm failed: %{public}s', err.message);
      this.showToast($r('app.string.directory_not_writable'));
    });
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.navigateBack();
        })

        Text($r('app.string.dir_picker'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor($r('app.color.teal_500'))

      // Current path header
      Column({ space: 6 }) {
        Text($r('app.string.settings_download_download_location'))
          .fontSize(12)
          .fontColor($r('app.color.teal_500'))
          .width('100%')

        Text(this.currentPath.length > 0 ? this.currentPath : '/')
          .fontSize(14)
          .fontColor('#DE000000')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.content_light'))

      // Navigation & system picker action bar
      Row({ space: 12 }) {
        Button($r('app.string.key_parent'))
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor(DirPickerHelpers.canGoUp(this.currentPath) ? $r('app.color.teal_500') : '#61000000')
          .backgroundColor(Color.Transparent)
          .enabled(DirPickerHelpers.canGoUp(this.currentPath))
          .onClick(() => {
            this.onGoUp();
          })

        Blank()

        Button($r('app.string.open_directory'))
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor($r('app.color.teal_500'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onPickViaSystemPicker();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })

      Divider()
        .strokeWidth(1)
        .color('#1F000000')

      // Directory list
      if (!this.ready || this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.teal_500'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.entries.length === 0) {
        Column() {
          Text($r('app.string.empty_result'))
            .fontSize(14)
            .fontColor('#8A000000')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.entries, (entry: string) => {
            ListItem() {
              Row({ space: 12 }) {
                VFolderMoveDarkX24({ iconSize: 22, fillColor: ThemeTokens.LIGHT.drawablePrimary })
                Text(DirPickerHelpers.basenameOf(entry))
                  .fontSize(16)
                  .fontColor('#DE000000')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
            .onClick(() => {
              this.onEnterDirectory(entry);
            })
          }, (entry: string) => entry)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: '#14000000' })
      }

      Divider()
        .strokeWidth(1)
        .color('#1F000000')

      // Bottom bar: Default + OK
      Row({ space: 12 }) {
        Button($r('app.string.default_directory'))
          .type(ButtonType.Normal)
          .fontSize(15)
          .fontColor($r('app.color.teal_500'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onResetDefault();
          })

        Blank()

        Button($r('app.string.ok'))
          .type(ButtonType.Normal)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .backgroundColor($r('app.color.teal_500'))
          .borderRadius(6)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .onClick(() => {
            this.onConfirm();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 14 })
      .backgroundColor($r('app.color.start_window_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
