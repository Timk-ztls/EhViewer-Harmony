/*
 * HistorySceneView: Material UI for HistoryScene (56vp Toolbar, GalleryListItemLayout list,
 * swipe-to-delete, Material Clear-All & Long-Press AlertDialogs).
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { HistoryInfo } from '../../ehviewer/dao/HistoryInfo';
import { EhCacheKeyFactory } from '../../ehviewer/client/EhCacheKeyFactory';
import { EhUtils } from '../../ehviewer/client/EhUtils';
import { Settings } from '../../ehviewer/Settings';
import { ReadProgressCache, ReadProgressChangeListener } from '../../ehviewer/ReadProgressCache';
import { DownloadManager } from '../../ehviewer/download/DownloadManager';
import { GalleryListClient } from '../GalleryListClient';
import {
  BUTTON_POSITIVE,
  HistoryScene,
  LONG_PRESS_DOWNLOAD,
  LONG_PRESS_FAVORITES,
  STATE_FAILURE,
  STATE_LOADING,
  SWIPE_DELETE
} from '../../ehviewer/ui/scene/history/HistoryScene';
import { HistorySceneShell } from '../../ehviewer/ui/scene/history/HistorySceneShell';
import { BigHistory } from '../drawable/big_history';
import { VClearAllDarkX24 } from '../drawable/v_clear_all_dark_x24';
import { VDeleteDarkX24 } from '../drawable/v_delete_dark_x24';
import { VDownloadX16 } from '../drawable/v_download_x16';
import { VHeartX16 } from '../drawable/v_heart_x16';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { GalleryListItemLayout } from '../layout/item_gallery_list';
import { MainPageHost } from '../MainPageHost';
import {
  APP_SHOW_GALLERY_PAGES_STORAGE_KEY,
  APP_SHOW_JPN_TITLE_STORAGE_KEY,
  APP_SHOW_READ_PROGRESS_STORAGE_KEY
} from '../ThemeSystemBar';

const DOMAIN: number = 0x0000;
const TAG: string = 'HistorySceneView';

@Component
export struct HistorySceneView {
  shell: HistorySceneShell | null = null;
  host: MainPageHost | null = null;
  onOpenDrawer: () => void = (): void => {
  };

  @State items: HistoryInfo[] = [];
  @State loading: boolean = false;
  @State failed: boolean = false;
  @State errorText: string = '';
  @State clearConfirmOpen: boolean = false;
  @State actionMenuIndex: number = -1;
  @State downloadedGids: number[] = [];
  @StorageLink(APP_SHOW_JPN_TITLE_STORAGE_KEY) showJpnTitle: boolean = Settings.getShowJpnTitle();
  @StorageLink(APP_SHOW_GALLERY_PAGES_STORAGE_KEY) @Watch('onPagesPrefChanged') showGalleryPages: boolean =
    Settings.getShowGalleryPages();
  @StorageLink(APP_SHOW_READ_PROGRESS_STORAGE_KEY) @Watch('onPagesPrefChanged') showReadProgress: boolean =
    Settings.getShowReadProgress();
  @State readProgressRev: number = 0;
  @Prop themeId: number = -1;

  private readonly onReadProgressChanged: ReadProgressChangeListener = (changedGids: number[]): void => {
    if (!this.showGalleryPages || !this.showReadProgress || this.items.length === 0) {
      return;
    }
    const set: Set<number> = new Set<number>(changedGids);
    for (let i = 0; i < this.items.length; i++) {
      if (set.has(this.items[i].gid)) {
        this.readProgressRev = this.readProgressRev + 1;
        return;
      }
    }
  };

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    ReadProgressCache.addListener(this.onReadProgressChanged);
    this.loadDownloadedGids();
    void this.loadHistory();
  }

  aboutToDisappear(): void {
    ReadProgressCache.removeListener(this.onReadProgressChanged);
  }

  private onPagesPrefChanged(): void {
    if (this.showGalleryPages && this.showReadProgress) {
      this.prefetchReadProgressForList(this.items);
    }
    this.readProgressRev = this.readProgressRev + 1;
  }

  private prefetchReadProgressForList(list: HistoryInfo[]): void {
    if (!this.showGalleryPages || !this.showReadProgress || list.length === 0) {
      return;
    }
    const gids: number[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].pages > 0 && list[i].gid > 0) {
        gids.push(list[i].gid);
      }
    }
    if (gids.length > 0) {
      void ReadProgressCache.prefetchGids(gids);
    }
  }

  private formatCardPages(item: HistoryInfo): string {
    const _rev: number = this.readProgressRev;
    if (_rev < 0) {
      return '';
    }
    return ReadProgressCache.formatPagesLabel(
      item.gid,
      item.pages,
      this.showGalleryPages,
      this.showReadProgress
    );
  }

  private loadDownloadedGids(): void {
    DownloadManager.getInstance().then((dm: DownloadManager): void => {
      const infos = dm.getDownloadInfoList();
      const gids: number[] = [];
      for (let i = 0; i < infos.length; i++) {
        gids.push(infos[i].gid);
      }
      this.downloadedGids = gids;
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'loadDownloadedGids failed: %{public}s', e.message);
    });
  }

  private async loadHistory(): Promise<void> {
    const sh: HistorySceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const logic: HistoryScene = sh.getLogic();
    this.loading = true;
    this.syncFromLogic(logic);
    try {
      await logic.onCreateView();
    } catch (err) {
      const e: Error = err as Error;
      hilog.error(DOMAIN, TAG, 'loadHistory failed: %{public}s', e.message);
    }
    this.syncFromLogic(logic);
  }

  private syncFromLogic(logic: HistoryScene): void {
    const st: number = logic.getState();
    this.loading = st === STATE_LOADING;
    this.failed = st === STATE_FAILURE;
    const err: Error | null = logic.getLastError();
    this.errorText = err !== null && err.message !== undefined ? err.message : '';
    this.items = logic.getItems();
    this.prefetchReadProgressForList(this.items);
  }

  private async deleteHistoryAt(idx: number): Promise<void> {
    const sh: HistorySceneShell | null = this.shell;
    if (sh === null || idx < 0 || idx >= this.items.length) {
      return;
    }
    const logic: HistoryScene = sh.getLogic();
    try {
      await logic.onSwipeItem(idx, SWIPE_DELETE);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onSwipeItem delete failed: %{public}s', (err as Error).message);
    }
    this.syncFromLogic(logic);
  }

  private displayTitle(item: HistoryInfo): string {
    const preferred: string | null = EhUtils.getSuitableTitle(item);
    if (preferred !== null && preferred.length > 0) {
      return preferred;
    }
    return item.title.length > 0 ? item.title : item.titleJpn;
  }

  private isDownloaded(gid: number): boolean {
    return this.downloadedGids.indexOf(gid) >= 0;
  }

  @Builder
  downloadedBadgeIcon(): void {
    VDownloadX16({ iconSize: 16, fillColor: this.palette().drawablePrimary })
  }

  @Builder
  favouritedBadgeIcon(): void {
    VHeartX16({ iconSize: 16, fillColor: this.palette().drawablePrimary })
  }

  @Builder
  hamburgerIcon(): void {
    Column({ space: 4 }) {
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  swipeDeleteBuilder(idx: number): void {
    Column({ space: 4 }) {
      VDeleteDarkX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().white
      })
      Text($r('app.string.delete'))
        .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
        .fontColor(this.palette().white)
    }
    .width(80)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.palette().errorColor)
    .onClick(() => {
      void this.deleteHistoryAt(idx);
    })
  }

  @Builder
  clearConfirmOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.clearConfirmOpen = false;
          if (this.shell !== null) {
            void this.shell.getLogic().confirmClearAll(0);
          }
        })

      Column() {
        Text($r('app.string.clear_all'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Text($r('app.string.clear_all_history'))
          .fontSize(ThemeTypography.PREF_TITLE)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 4, bottom: 16 })

        Row({ space: 8 }) {
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
            this.clearConfirmOpen = false;
            if (this.shell !== null) {
              void this.shell.getLogic().confirmClearAll(0);
            }
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.clear_all'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(async () => {
            this.clearConfirmOpen = false;
            if (this.shell !== null) {
              const logic: HistoryScene = this.shell.getLogic();
              await logic.confirmClearAll(BUTTON_POSITIVE);
              this.syncFromLogic(logic);
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  longPressActionOverlay(idx: number, item: HistoryInfo): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.actionMenuIndex = -1;
        })

      Column() {
        Text(this.displayTitle(item))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Row() {
          Text($r('app.string.download'))
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
        .padding({ left: 24, right: 24 })
        .onClick(() => {
          if (this.shell !== null) {
            this.shell.getLogic().onLongPressMenuClick(LONG_PRESS_DOWNLOAD);
          }
          this.actionMenuIndex = -1;
        })

        Row() {
          Text($r('app.string.add_to_favourites'))
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
        .padding({ left: 24, right: 24 })
        .onClick(() => {
          if (this.shell !== null) {
            this.shell.getLogic().onLongPressMenuClick(LONG_PRESS_FAVORITES);
          }
          this.actionMenuIndex = -1;
        })

        Row() {
          Text($r('app.string.delete'))
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().errorColor)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
        .padding({ left: 24, right: 24 })
        .onClick(() => {
          this.actionMenuIndex = -1;
          void this.deleteHistoryAt(idx);
        })

        Row() {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
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
            this.actionMenuIndex = -1;
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
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
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 56vp Material Toolbar (scene_toolbar.xml)
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            this.hamburgerIcon()
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick(() => {
            this.onOpenDrawer();
          })

          Text($r('app.string.history'))
            .fontSize(ThemeTypography.TOOLBAR_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().toolbarTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: ThemeDimens.SPACING })

          if (this.items.length > 0) {
            Stack({ alignContent: Alignment.Center }) {
              VClearAllDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick(() => {
              if (this.shell !== null) {
                this.shell.getLogic().onMenuItemClick('action_clear_all');
              }
              this.clearConfirmOpen = true;
            })
          }

          Stack({ alignContent: Alignment.Center }) {
            VRefreshDarkX24({
              iconSize: ThemeDimens.ICON_SIZE_STANDARD,
              fillColor: this.palette().toolbarIconColor
            })
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick(() => {
            void this.loadHistory();
          })
        }
        .width('100%')
        .height(ThemeDimens.TOOLBAR_HEIGHT)
        .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
        .backgroundColor(this.palette().toolbarColor)
        .shadow(ThemeElevation.toolbar())

        if (this.loading && this.items.length === 0) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.palette().progressColor)
            Text($r('app.string.loading'))
              .fontSize(ThemeTypography.CARD_MESSAGE)
              .fontColor(this.palette().textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.failed && this.items.length === 0) {
          Column({ space: 12 }) {
            Text($r('app.string.load_failed'))
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().errorColor)
            if (this.errorText.length > 0) {
              Text(this.errorText)
                .fontSize(ThemeTypography.CARD_MESSAGE)
                .fontColor(this.palette().textSecondary)
                .textAlign(TextAlign.Center)
            }
            Button({ type: ButtonType.Normal }) {
              Text($r('app.string.retry'))
                .fontSize(ThemeTypography.BUTTON)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().white)
                .textCase(TextCase.UpperCase)
            }
            .height(36)
            .padding({ left: 16, right: 16 })
            .borderRadius(ThemeRadius.BUTTON)
            .backgroundColor(this.palette().colorPrimary)
            .onClick(() => {
              void this.loadHistory();
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
        } else if (this.items.length === 0) {
          Column({ space: 16 }) {
            BigHistory({
              iconSize: 120,
              fillColor: this.palette().drawableSecondary
            })
            Text($r('app.string.no_history'))
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.items, (item: HistoryInfo, idx: number) => {
              ListItem() {
                GalleryListItemLayout({
                  title: this.displayTitle(item),
                  uploader: item.uploader,
                  rating: item.rating,
                  category: GalleryListClient.formatCategoryLabel(item.category),
                  categoryBgColor: GalleryListClient.formatCategoryColor(item.category),
                  posted: item.posted,
                  pages: this.formatCardPages(item),
                  simpleLanguage: item.simpleLanguage ?? '',
                  thumbUrl: item.thumb,
                  thumbKey: EhCacheKeyFactory.getThumbKey(item.gid),
                  downloaded: this.isDownloaded(item.gid),
                  favourited: item.favoriteSlot >= 0 && item.favoriteSlot <= 10,
                  themeId: this.themeId,
                  cardColor: this.palette().cardBackground,
                  titleColor: this.palette().textPrimary,
                  messageColor: this.palette().textSecondary,
                  downloadedIconBuilder: () => { this.downloadedBadgeIcon(); },
                  favouritedIconBuilder: () => { this.favouritedBadgeIcon(); }
                })
              }
              .swipeAction({
                end: {
                  builder: () => {
                    this.swipeDeleteBuilder(idx);
                  },
                  actionAreaDistance: 80,
                  onAction: () => {
                    void this.deleteHistoryAt(idx);
                  }
                }
              })
              .onClick(() => {
                if (this.shell !== null) {
                  this.shell.getLogic().onItemClick(idx, item.thumb.length > 0);
                }
              })
              .gesture(
                LongPressGesture({ repeat: false })
                  .onAction(() => {
                    if (this.shell !== null) {
                      this.shell.getLogic().onItemLongClick(idx);
                      this.actionMenuIndex = idx;
                    }
                  })
              )
            }, (item: HistoryInfo) => `${item.gid}_${item.time}_${this.showJpnTitle ? 1 : 0}_${this.formatCardPages(item)}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({
            left: ThemeDimens.GALLERY_LIST_MARGIN_H,
            right: ThemeDimens.GALLERY_LIST_MARGIN_H,
            top: ThemeDimens.GALLERY_LIST_MARGIN_V,
            bottom: ThemeDimens.GALLERY_LIST_MARGIN_V
          })
        }
      }
      .width('100%')
      .height('100%')

      if (this.clearConfirmOpen) {
        this.clearConfirmOverlay()
      }

      if (this.actionMenuIndex >= 0 && this.actionMenuIndex < this.items.length) {
        this.longPressActionOverlay(this.actionMenuIndex, this.items[this.actionMenuIndex])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
