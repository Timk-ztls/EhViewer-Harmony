/*
 * FavoritesSceneView: Material UI for FavoritesScene (floating SearchBar, right collections drawer,
 * local + cloud favorites, keyword search, refresh FAB).
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { GalleryInfo } from '../../ehviewer/client/data/GalleryInfo';
import { EhCacheKeyFactory } from '../../ehviewer/client/EhCacheKeyFactory';
import { EhUtils } from '../../ehviewer/client/EhUtils';
import { GetText } from '../../ehviewer/GetText';
import { Settings } from '../../ehviewer/Settings';
import { DownloadManager } from '../../ehviewer/download/DownloadManager';
import { FavoritesCategory, FavoritesScene } from '../../ehviewer/ui/scene/gallery/list/FavoritesScene';
import { PathData } from '../../drawable/PathData';
import { VDownloadX16 } from '../drawable/v_download_x16';
import { VHeartX16 } from '../drawable/v_heart_x16';
import { VMagnifyDarkX24 } from '../drawable/v_magnify_dark_x24';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { GalleryListClient } from '../GalleryListClient';
import { GalleryListItemLayout } from '../layout/item_gallery_list';
import { MainPageHost } from '../MainPageHost';
import { APP_SHOW_JPN_TITLE_STORAGE_KEY } from '../ThemeSystemBar';
import { DataOperation, SceneDataSourceListener } from '../SceneDataSource';

const DOMAIN: number = 0x0000;
const TAG: string = 'FavoritesSceneView';

class FavDrawerSlot {
  cat: number = FavoritesCategory.LOCAL;
  label: string = '';
  countText: string = '';

  constructor(cat: number, label: string, countText: string) {
    this.cat = cat;
    this.label = label;
    this.countText = countText;
  }
}

class FavoritesDataListener implements SceneDataSourceListener {
  private readonly onChange: () => void;

  constructor(onChange: () => void) {
    this.onChange = onChange;
  }

  onDataReloaded(): void {
    this.onChange();
  }

  onDataAdd(_index: number): void {
    this.onChange();
  }

  onDataMove(_from: number, _to: number): void {
    this.onChange();
  }

  onDataDelete(_index: number): void {
    this.onChange();
  }

  onDataChange(_index: number): void {
    this.onChange();
  }

  onDatasetChange(_operations: DataOperation[]): void {
    this.onChange();
  }
}

@Component
export struct FavoritesSceneView {
  scene: FavoritesScene | null = null;
  host: MainPageHost | null = null;
  onOpenDrawer?: () => void;
  @Prop themeId: number = -1;
  @Prop @Watch('onRightDrawerOpenSignal') rightDrawerOpenSignal: number = 0;
  @Prop @Watch('onRightDrawerCloseSignal') rightDrawerCloseSignal: number = 0;
  @Prop @Watch('onRightDrawerDragChanged') rightDrawerDragActive: boolean = false;
  @Prop @Watch('onRightDrawerDragChanged') rightDrawerDragProgress: number = 0;
  @Prop @Watch('onRightDrawerDragEnded') rightDrawerDragEndSeq: number = 0;
  @Prop rightDrawerDragSettleOpen: boolean = false;
  onRightDrawerStateChange: (open: boolean) => void = (): void => {
  };

  @State items: GalleryInfo[] = [];
  @State currentFavCat: number = FavoritesCategory.LOCAL;
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State searchKeyword: string = '';
  @State searchEditing: boolean = false;
  @State rightDrawerOpen: boolean = false;
  @State defaultSlotDialogOpen: boolean = false;
  @State favCats: string[] = [];
  @State favCounts: number[] = [];
  @State localFavCount: number = 0;
  @State defaultFavSlot: number = FavoritesCategory.ALL;
  @State downloadedGids: number[] = [];
  @StorageLink(APP_SHOW_JPN_TITLE_STORAGE_KEY) showJpnTitle: boolean = Settings.getShowJpnTitle();

  private hostContext: common.Context | undefined = undefined;
  private dataListener: FavoritesDataListener | null = null;
  private slotRadioGroup: string = 'fav_default_slot_group';

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  @State rightDrawerOffsetX: number = ThemeDimens.DRAWER_MAX_WIDTH;
  @State rightDrawerScrimOpacity: number = 0;
  private rightDrawerClosing: boolean = false;
  private lastRightDragEndSeq: number = 0;

  private onRightDrawerDragChanged(): void {
    if (!this.rightDrawerDragActive) {
      return;
    }
    const p: number = Math.max(0, Math.min(1, this.rightDrawerDragProgress));
    this.rightDrawerClosing = false;
    this.rightDrawerOpen = true;
    this.rightDrawerOffsetX = ThemeDimens.DRAWER_MAX_WIDTH * (1 - p);
    this.rightDrawerScrimOpacity = p;
  }

  private onRightDrawerDragEnded(): void {
    if (this.rightDrawerDragEndSeq === this.lastRightDragEndSeq) {
      return;
    }
    this.lastRightDragEndSeq = this.rightDrawerDragEndSeq;
    if (!this.rightDrawerOpen) {
      return;
    }
    if (this.rightDrawerDragSettleOpen) {
      this.rightDrawerClosing = false;
      this.onRightDrawerStateChange(true);
      animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
        this.rightDrawerOffsetX = 0;
        this.rightDrawerScrimOpacity = 1;
      });
    } else {
      this.setRightDrawerOpen(false);
    }
  }

  private setRightDrawerOpen(open: boolean): void {
    if (open) {
      this.rightDrawerClosing = false;
      this.rightDrawerOffsetX = ThemeDimens.DRAWER_MAX_WIDTH;
      this.rightDrawerScrimOpacity = 0;
      this.rightDrawerOpen = true;
      this.onRightDrawerStateChange(true);
      animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
        this.rightDrawerOffsetX = 0;
        this.rightDrawerScrimOpacity = 1;
      });
      return;
    }
    if (!this.rightDrawerOpen || this.rightDrawerClosing) {
      return;
    }
    this.rightDrawerClosing = true;
    this.onRightDrawerStateChange(false);
    animateTo({
      duration: 180,
      curve: Curve.FastOutLinearIn,
      onFinish: (): void => {
        this.rightDrawerOpen = false;
        this.rightDrawerClosing = false;
      }
    }, (): void => {
      this.rightDrawerOffsetX = ThemeDimens.DRAWER_MAX_WIDTH;
      this.rightDrawerScrimOpacity = 0;
    });
  }

  private onRightDrawerOpenSignal(): void {
    if (this.rightDrawerOpenSignal <= 0) {
      return;
    }
    this.setRightDrawerOpen(true);
  }

  private onRightDrawerCloseSignal(): void {
    if (this.rightDrawerCloseSignal <= 0) {
      return;
    }
    if (this.rightDrawerOpen) {
      this.setRightDrawerOpen(false);
    }
  }

  private str(key: string): string {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        return ctx.resourceManager.getStringByNameSync(key);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'getStringByNameSync failed for %{public}s: %{public}s',
          key, JSON.stringify(err));
      }
    }
    return GetText.getString(key);
  }

  aboutToAppear(): void {
    this.lastRightDragEndSeq = this.rightDrawerDragEndSeq;
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    this.hostContext = ctx;
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.favCats = Settings.getFavCat();
    this.favCounts = Settings.getFavCount();
    this.localFavCount = Settings.getFavLocalCount();
    this.defaultFavSlot = Settings.getDefaultFavSlot();
    this.loadDownloadedGids();

    const s: FavoritesScene | null = this.scene;
    if (s === null) {
      return;
    }
    s.setFavMeta(this.favCats, this.favCounts);
    s.setOnMetaUpdatedListener((cats: string[], counts: number[]): void => {
      Settings.putFavCat(cats);
      Settings.putFavCount(counts);
      this.favCats = cats;
      this.favCounts = counts;
    });
    s.setOnStateChangedListener((): void => {
      this.syncFromScene();
    });
    const listener: FavoritesDataListener = new FavoritesDataListener((): void => {
      this.syncFromScene();
    });
    this.dataListener = listener;
    s.getDataSource().registerDataChangeListener(listener);
    s.ensureLoaded();
    this.syncFromScene();
  }

  aboutToDisappear(): void {
    const s: FavoritesScene | null = this.scene;
    if (s !== null) {
      s.setOnStateChangedListener(null);
      s.setOnMetaUpdatedListener(null);
      if (this.dataListener !== null) {
        s.getDataSource().unregisterDataChangeListener(this.dataListener);
      }
    }
    this.dataListener = null;
  }

  private syncFromScene(): void {
    this.localFavCount = Settings.getFavLocalCount();
    this.defaultFavSlot = Settings.getDefaultFavSlot();
    const s: FavoritesScene | null = this.scene;
    if (s === null) {
      return;
    }
    this.currentFavCat = s.getCurrentFavCat();
    this.loading = s.isLoading();
    this.errorMessage = s.getErrorMessage();
    this.searchKeyword = s.getKeyword();
    const cats: string[] = s.getFavCats();
    if (cats.length === 10) {
      this.favCats = cats;
    }
    const counts: number[] = s.getFavCounts();
    if (counts.length === 10) {
      this.favCounts = counts;
    }
    const ds = s.getDataSource();
    const total: number = ds.totalCount();
    const list: GalleryInfo[] = [];
    for (let i = 0; i < total; i++) {
      const gi: GalleryInfo | null = ds.getData(i);
      if (gi !== null) {
        list.push(gi);
      }
    }
    this.items = list;
  }

  private getSlotDisplayName(cat: number): string {
    if (cat === FavoritesCategory.LOCAL) {
      return this.str('local_favorites');
    }
    if (cat === FavoritesCategory.ALL) {
      return this.str('cloud_favorites');
    }
    if (cat >= 0 && cat < 10) {
      if (cat < this.favCats.length && this.favCats[cat].length > 0) {
        return this.favCats[cat];
      }
      return `#${cat}`;
    }
    return this.str('favorites');
  }

  private buildDrawerSlots(): FavDrawerSlot[] {
    const slots: FavDrawerSlot[] = [];
    slots.push(new FavDrawerSlot(
      FavoritesCategory.LOCAL,
      this.str('local_favorites'),
      this.localFavCount > 0 ? `${this.localFavCount}` : ''
    ));
    let cloudTotal: number = 0;
    for (let i = 0; i < this.favCounts.length; i++) {
      if (this.favCounts[i] > 0) {
        cloudTotal += this.favCounts[i];
      }
    }
    slots.push(new FavDrawerSlot(
      FavoritesCategory.ALL,
      this.str('cloud_favorites'),
      cloudTotal > 0 ? `${cloudTotal}` : ''
    ));
    for (let i = 0; i < 10; i++) {
      const name: string = i < this.favCats.length && this.favCats[i].length > 0
        ? this.favCats[i]
        : `#${i}`;
      const count: number = i < this.favCounts.length ? this.favCounts[i] : 0;
      slots.push(new FavDrawerSlot(i, name, `${count}`));
    }
    return slots;
  }

  private searchBarTitleText(): string {
    const catName: string = this.getSlotDisplayName(this.currentFavCat);
    if (this.searchKeyword.length > 0) {
      const fmt: string = this.str('favorites_title_2');
      if (fmt.indexOf('%1$s') >= 0 && fmt.indexOf('%2$s') >= 0) {
        return fmt.replace('%1$s', catName).replace('%2$s', this.searchKeyword);
      }
      return `${catName} - ${this.searchKeyword}`;
    }
    const fmt: string = this.str('favorites_title');
    if (fmt.indexOf('%s') >= 0) {
      return fmt.replace('%s', catName);
    }
    return catName;
  }

  private searchBarHintText(): string {
    const catName: string = this.getSlotDisplayName(this.currentFavCat);
    const fmt: string = this.str('favorites_search_bar_hint');
    if (fmt.indexOf('%s') >= 0) {
      return fmt.replace('%s', catName);
    }
    return this.str('search');
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

  private isDownloaded(gid: number): boolean {
    return this.downloadedGids.indexOf(gid) >= 0;
  }

  private displayTitle(item: GalleryInfo): string {
    const preferred: string | null = EhUtils.getSuitableTitle(item);
    if (preferred !== null && preferred.length > 0) {
      return preferred;
    }
    return item.title.length > 0 ? item.title : item.titleJpn;
  }

  private selectCategory(favCat: number): void {
    const s: FavoritesScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      s.setCategory(favCat);
      this.syncFromScene();
    } catch (err) {
      const e: Error = err as Error;
      hilog.error(DOMAIN, TAG, 'setCategory failed: %{public}s', e.message);
    }
  }

  private submitSearch(): void {
    const s: FavoritesScene | null = this.scene;
    if (s !== null) {
      s.applySearch(this.searchKeyword);
      this.syncFromScene();
    }
  }

  private refreshScene(): void {
    const s: FavoritesScene | null = this.scene;
    if (s !== null) {
      s.reload(true);
      this.syncFromScene();
    }
  }

  private handleLeftNavClick(): void {
    if (this.searchEditing) {
      this.searchEditing = false;
      return;
    }
    if (this.onOpenDrawer !== undefined) {
      this.onOpenDrawer();
    } else if (this.host !== null) {
      this.host.goBack();
    }
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
      Row().width(18).height(2).backgroundColor(this.palette().drawableSecondary)
      Row().width(18).height(2).backgroundColor(this.palette().drawableSecondary)
      Row().width(18).height(2).backgroundColor(this.palette().drawableSecondary)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  defaultSlotOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.defaultSlotDialogOpen = false;
        })

      Column() {
        Text($r('app.string.default_favorites_collection'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        List() {
          ListItem() {
            this.defaultSlotOptionRow(-2, this.str('let_me_select'))
          }
          ListItem() {
            this.defaultSlotOptionRow(FavoritesCategory.LOCAL, this.str('local_favorites'))
          }
          ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], (slot: number) => {
            ListItem() {
              this.defaultSlotOptionRow(slot, this.getSlotDisplayName(slot))
            }
          }, (slot: number) => String(slot))
        }
        .width('100%')
        .constraintSize({ maxHeight: 360 })

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
            this.defaultSlotDialogOpen = false;
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
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
  defaultSlotOptionRow(slot: number, label: string): void {
    Row({ space: ThemeDimens.SPACING_MD }) {
      Radio({ value: `${slot}`, group: this.slotRadioGroup })
        .checked(this.defaultFavSlot === slot)
        .radioStyle({ checkedBackgroundColor: this.palette().controlActivated })
        .hitTestBehavior(HitTestMode.None)
      Text(label)
        .fontSize(ThemeTypography.PREF_TITLE)
        .fontColor(this.palette().textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
    .padding({ left: 20, right: 24, top: 10, bottom: 10 })
    .onClick(() => {
      Settings.putDefaultFavSlot(slot);
      this.defaultFavSlot = slot;
      this.defaultSlotDialogOpen = false;
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. Main content area (underneath floating SearchBar)
      Column() {
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
          .padding({ top: ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR })
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMessage.length > 0 && this.items.length === 0) {
          Column({ space: 12 }) {
            Text($r('app.string.load_failed'))
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().errorColor)
            Text(this.errorMessage)
              .fontSize(ThemeTypography.CARD_MESSAGE)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)
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
              this.refreshScene();
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 24, right: 24, top: ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR })
          .justifyContent(FlexAlign.Center)
        } else if (this.items.length === 0) {
          Column({ space: 12 }) {
            Text($r('app.string.gallery_list_empty_hit'))
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)
            Button({ type: ButtonType.Normal }) {
              Text($r('app.string.refresh'))
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
              this.refreshScene();
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 24, right: 24, top: ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR })
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.items, (item: GalleryInfo) => {
              ListItem() {
                GalleryListItemLayout({
                  title: this.displayTitle(item),
                  uploader: item.uploader,
                  rating: item.rating,
                  category: GalleryListClient.formatCategoryLabel(item.category),
                  categoryBgColor: GalleryListClient.formatCategoryColor(item.category),
                  posted: item.posted,
                  pages: item.pages > 0 ? `${item.pages}P` : '',
                  simpleLanguage: item.simpleLanguage ?? '',
                  thumbUrl: item.thumb,
                  thumbKey: EhCacheKeyFactory.getThumbKey(item.gid),
                  downloaded: this.isDownloaded(item.gid),
                  favourited: item.favoriteSlot >= 0 || this.currentFavCat === FavoritesCategory.LOCAL,
                  themeId: this.themeId,
                  cardColor: this.palette().cardBackground,
                  titleColor: this.palette().textPrimary,
                  messageColor: this.palette().textSecondary,
                  downloadedIconBuilder: () => { this.downloadedBadgeIcon(); },
                  favouritedIconBuilder: () => { this.favouritedBadgeIcon(); }
                })
              }
              .onClick(() => {
                if (MainPageHost.shouldSuppressClick()) {
                  return;
                }
                const s: FavoritesScene | null = this.scene;
                if (s !== null) {
                  s.openGalleryDetail(item);
                }
              })
            }, (item: GalleryInfo) => `${item.gid}_${item.favoriteSlot}_${this.showJpnTitle ? 1 : 0}`)

            if (this.loading) {
              ListItem() {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(this.palette().progressColor)
                  Text($r('app.string.loading'))
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontColor(this.palette().textSecondary)
                }
                .width('100%')
                .padding(12)
                .justifyContent(FlexAlign.Center)
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(6)
          .edgeEffect(EdgeEffect.Spring)
          .padding({
            top: ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR,
            bottom: ThemeDimens.GALLERY_PADDING_BOTTOM_FAB,
            left: ThemeDimens.GALLERY_LIST_MARGIN_H,
            right: ThemeDimens.GALLERY_LIST_MARGIN_H
          })
          .onReachEnd(() => {
            const s: FavoritesScene | null = this.scene;
            if (s !== null) {
              s.loadMore();
              this.syncFromScene();
            }
          })
        }
      }
      .width('100%')
      .height('100%')

      // 2. Floating Material SearchBar (CardView.Normal)
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (this.searchEditing) {
            Shape() {
              Path()
                .commands(PathData.pd_arrow_left)
                .fill(this.palette().drawableSecondary)
                .stroke(Color.Transparent)
                .strokeWidth(0)
            }
            .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .antiAlias(true)
          } else {
            this.hamburgerIcon()
          }
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .onClick(() => {
          this.handleLeftNavClick();
        })

        if (this.searchEditing) {
          TextInput({ placeholder: this.searchBarHintText(), text: this.searchKeyword })
            .layoutWeight(1)
            .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().textHint)
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 4 })
            .enterKeyType(EnterKeyType.Search)
            .onChange((v: string) => {
              this.searchKeyword = v;
            })
            .onSubmit(() => {
              this.submitSearch();
              this.searchEditing = false;
            })
        } else {
          Row() {
            Text(this.searchBarTitleText())
              .fontSize(ThemeTypography.TEXT_LITTLE_LARGE)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .layoutWeight(1)
          .height('100%')
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.searchEditing = true;
          })
        }

        if (this.searchEditing) {
          Stack({ alignContent: Alignment.Center }) {
            Shape() {
              Path()
                .commands(PathData.pd_close)
                .fill(this.palette().drawableSecondary)
                .stroke(Color.Transparent)
                .strokeWidth(0)
            }
            .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .antiAlias(true)
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick(() => {
            if (this.searchKeyword.length > 0) {
              this.searchKeyword = '';
              this.submitSearch();
            } else {
              this.searchEditing = false;
            }
          })
        } else {
          Stack({ alignContent: Alignment.Center }) {
            VMagnifyDarkX24({
              iconSize: ThemeDimens.ICON_SIZE_STANDARD,
              fillColor: this.palette().drawableSecondary
            })
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick(() => {
            this.searchEditing = true;
          })
        }

        Stack({ alignContent: Alignment.Center }) {
          Shape() {
            Path()
              .commands(PathData.ic_bookmarks)
              .fill(this.currentFavCat >= -1 ? this.palette().colorPrimary : this.palette().drawableSecondary)
              .stroke(Color.Transparent)
              .strokeWidth(0)
          }
          .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
          .width(ThemeDimens.ICON_SIZE_STANDARD)
          .height(ThemeDimens.ICON_SIZE_STANDARD)
          .antiAlias(true)
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .onClick(() => {
          this.setRightDrawerOpen(!this.rightDrawerOpen);
        })
      }
      .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
      .margin({
        left: ThemeDimens.GALLERY_SEARCH_BAR_MARGIN_H,
        right: ThemeDimens.GALLERY_SEARCH_BAR_MARGIN_H,
        top: ThemeDimens.GALLERY_SEARCH_BAR_MARGIN_V
      })
      .backgroundColor(this.palette().cardBackground)
      .borderRadius(ThemeRadius.SEARCH_BAR)
      .shadow(ThemeElevation.searchBar())
      .alignItems(VerticalAlign.Center)

      // 3. Bottom-Right Circular Material FAB (56x56)
      Stack({ alignContent: Alignment.BottomEnd }) {
        Stack({ alignContent: Alignment.Center }) {
          VRefreshDarkX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.palette().white
          })
        }
        .width(ThemeDimens.FAB_SIZE)
        .height(ThemeDimens.FAB_SIZE)
        .margin({
          right: ThemeDimens.CORNER_FAB_MARGIN,
          bottom: ThemeDimens.CORNER_FAB_MARGIN
        })
        .borderRadius(ThemeRadius.FAB_PRIMARY)
        .backgroundColor(this.palette().widgetThemePrimary)
        .shadow(ThemeElevation.fab())
        .onClick(() => {
          this.refreshScene();
        })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      // 4. Right Collections Drawer (drawer_list_rv.xml + item_drawer_favorites.xml)
      if (this.rightDrawerOpen) {
        Stack({ alignContent: Alignment.End }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.palette().drawerScrim)
            .opacity(this.rightDrawerScrimOpacity)
            .onClick(() => {
              this.setRightDrawerOpen(false);
            })

          Column() {
            Row({ space: 8 }) {
              Text($r('app.string.collections'))
                .fontSize(ThemeTypography.TOOLBAR_TITLE)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().toolbarTitleColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.default_favorites_collection'))
                  .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().toolbarTitleColor)
                  .maxLines(1)
              }
              .height(36)
              .padding({ left: 8, right: 8 })
              .borderRadius(ThemeRadius.BUTTON)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.defaultSlotDialogOpen = true;
              })
            }
            .width('100%')
            .height(ThemeDimens.TOOLBAR_HEIGHT)
            .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.SPACING })
            .backgroundColor(this.palette().toolbarColor)
            .shadow(ThemeElevation.toolbar())

            List() {
              ForEach(this.buildDrawerSlots(), (slot: FavDrawerSlot) => {
                ListItem() {
                  Row() {
                    Text(slot.label)
                      .fontSize(ThemeTypography.CARD_MESSAGE)
                      .fontWeight(this.currentFavCat === slot.cat ? FontWeight.Medium : FontWeight.Regular)
                      .fontColor(this.currentFavCat === slot.cat
                        ? this.palette().drawerActiveColor
                        : this.palette().textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                      .padding({ left: ThemeDimens.KEYLINE_MARGIN })

                    if (slot.countText.length > 0) {
                      Text(slot.countText)
                        .fontSize(ThemeTypography.CARD_MESSAGE)
                        .fontColor(this.currentFavCat === slot.cat
                          ? this.palette().drawerActiveColor
                          : this.palette().textSecondary)
                        .padding({ right: ThemeDimens.KEYLINE_MARGIN })
                    }
                  }
                  .width('100%')
                  .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
                  .backgroundColor(this.currentFavCat === slot.cat
                    ? this.palette().drawerActiveBackground
                    : Color.Transparent)
                  .onClick(() => {
                    this.selectCategory(slot.cat);
                    this.setRightDrawerOpen(false);
                  })
                }
              }, (slot: FavDrawerSlot) => `${slot.cat}:${slot.label}:${slot.countText}`)
            }
            .width('100%')
            .layoutWeight(1)
          }
          .width('78%')
          .constraintSize({ maxWidth: ThemeDimens.DRAWER_MAX_WIDTH })
          .height('100%')
          .backgroundColor(this.palette().drawerBackground)
          .shadow(ThemeElevation.dialog())
          .translate({ x: this.rightDrawerOffsetX })
        }
        .width('100%')
        .height('100%')
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
            .onActionUpdate((event: GestureEvent): void => {
              if (event.offsetX >= 0) {
                const clamped: number = Math.min(ThemeDimens.DRAWER_MAX_WIDTH, event.offsetX);
                this.rightDrawerOffsetX = clamped;
                this.rightDrawerScrimOpacity = Math.max(0, 1 - clamped / ThemeDimens.DRAWER_MAX_WIDTH);
              }
            })
            .onActionEnd((event: GestureEvent): void => {
              MainPageHost.markSwipeGesture();
              if (event.offsetX >= ThemeDimens.DRAWER_MAX_WIDTH * 0.35 || event.velocityX > 350) {
                this.setRightDrawerOpen(false);
              } else {
                animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
                  this.rightDrawerOffsetX = 0;
                  this.rightDrawerScrimOpacity = 1;
                });
              }
            })
            .onActionCancel((): void => {
              if (this.rightDrawerOffsetX >= ThemeDimens.DRAWER_MAX_WIDTH * 0.35) {
                this.setRightDrawerOpen(false);
              } else {
                animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
                  this.rightDrawerOffsetX = 0;
                  this.rightDrawerScrimOpacity = 1;
                });
              }
            })
        )
      }

      if (this.defaultSlotDialogOpen) {
        this.defaultSlotOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
