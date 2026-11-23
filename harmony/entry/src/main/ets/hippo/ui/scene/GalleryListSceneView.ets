/*
 * GalleryListSceneView — Material Design aligned presentation layer for GalleryListScene.
 * Preserves GalleryListScene state binding, SearchBarMover, TagSelectorResultBus,
 * list/staggered-grid modes, floating SearchBar, SearchLayout panel, and FabLayout.
 */
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeTokens,
  ThemePalette,
  ThemeDimens,
  ThemeRadius,
  ThemeTypography,
  ThemeElevation
} from '../../../common/theme/ThemeTokens';
import { GalleryInfo } from '../../ehviewer/client/data/GalleryInfo';
import { ListUrlBuilder } from '../../ehviewer/client/data/ListUrlBuilder';
import { CategoryFlags } from '../../ehviewer/client/data/Flags';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { EhUtils } from '../../ehviewer/client/EhUtils';
import { EhCacheKeyFactory } from '../../ehviewer/client/EhCacheKeyFactory';
import { DefaultImageRequestHost } from '../../ehviewer/image/DefaultImageRequestHost';
import { LoadImageController } from '../../widget/LoadImageView';
import { GalleryDetailUrlParser, DetailUrlResult } from '../../ehviewer/client/parser/GalleryDetailUrlParser';
import { EhDB } from '../../ehviewer/EhDB';
import { EhApplication } from '../../ehviewer/EhApplication';
import { EhEngine, HttpCaller } from '../../ehviewer/client/EhEngine';
import { UserTag, UserTagList } from '../../ehviewer/client/data/UserTag';
import { QuickSearch } from '../../ehviewer/dao/QuickSearch';
import { GetText } from '../../ehviewer/GetText';
import { ReadProgressCache, ReadProgressChangeListener } from '../../ehviewer/ReadProgressCache';
import { Settings } from '../../ehviewer/Settings';
import { LocalFavoriteInfo } from '../../ehviewer/dao/LocalFavoriteInfo';
import { DownloadManager } from '../../ehviewer/download/DownloadManager';
import { GalleryDetailScene, GalleryReaderRouteParams } from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailScene';
import {
  GalleryListScene, GalleryListState, GalleryListAction, EhClientLike
} from '../../ehviewer/ui/scene/gallery/list/GalleryListScene';
import { CategoryTable } from '../../ehviewer/widget/CategoryTable';
import { AdvanceSearchTable } from '../../ehviewer/widget/AdvanceSearchTable';
import { ImageSearchLayout, HelperImpl } from '../../ehviewer/widget/ImageSearchLayout';
import { SearchBarState } from '../../ehviewer/widget/SearchBar';
import {
  SearchHistoryPrefsStore,
  SearchSuggestionEntry,
  SearchTagQueryHelper
} from '../../ehviewer/widget/SearchDatabase';
import { EhTagDatabase, TagSuggestion } from '../../ehviewer/client/EhTagDatabase';
import { EhTagDatabaseUpdater } from '../../ehviewer/client/EhTagDatabaseUpdater';
import { TagTranslationUtil } from '../../ehviewer/util/TagTranslationUtil';
import { SearchLayoutState, SearchLayoutBuilder } from '../../ehviewer/widget/SearchLayout';
import { DrawerArrowDrawable, DrawerArrowController } from '../../drawable/DrawerArrowDrawable';
import { AddDeleteDrawable, AddDeleteDrawableController } from '../../drawable/AddDeleteDrawable';
import {
  FabLayout,
  FabBehaviorState,
  OnClickFabListenerImpl,
  OnExpandListenerImpl
} from '../../widget/FabLayout';
import { SearchBarMoverHelperImpl, SearchBarMoverState } from '../../widget/SearchBarMover';
import { GalleryListClient } from '../GalleryListClient';
import { GalleryArrayDataSource } from '../GalleryListHostPage';
import { MainPageHost } from '../MainPageHost';
import { PageRoutes, RouteActionKind, RouteNavigationPlan } from '../PageRoutes';
import { TagSelectorResultBus } from '../p3/P3PageAdapters';
import {
  APP_SHOW_GALLERY_PAGES_STORAGE_KEY,
  APP_SHOW_JPN_TITLE_STORAGE_KEY,
  APP_SHOW_READ_PROGRESS_STORAGE_KEY
} from '../ThemeSystemBar';
import { Announcer } from '../../scene/Announcer';
import { OkHttpCallerAdapter } from '../../AppWiring';
import { GalleryListItemLayout } from '../layout/item_gallery_list';
import { ItemGalleryGridLayout } from '../layout/item_gallery_grid';
import { SceneGalleryListLayout, SearchBarOffsetHolder } from '../layout/scene_gallery_list';
import { VPlusDarkX24 } from '../drawable/v_plus_dark_x24';
import { VMagnifyDarkX24 } from '../drawable/v_magnify_dark_x24';
import { VGoToDarkX24 } from '../drawable/v_go_to_dark_x24';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { VRandomDarkX24 } from '../drawable/v_random_dark_x24';
import { VHelpCircleX24 } from '../drawable/v_help_circle_x24';
import { VAlertRedX48 } from '../drawable/v_alert_red_x48';
import { BigSadPandroid } from '../drawable/big_sad_pandroid';
import { VBookOpenX24 } from '../drawable/v_book_open_x24';
import { VDownloadX24 } from '../drawable/v_download_x24';
import { VDeleteX24 } from '../drawable/v_delete_x24';
import { VHeartX24 } from '../drawable/v_heart_x24';
import { VHeartBrokenX24 } from '../drawable/v_heart_broken_x24';
import { IcBaselineFilterNone24 } from '../drawable/ic_baseline_filter_none_24';
import { IcBaselineFilter24 } from '../drawable/ic_baseline_filter_24';
import { IcBaselineFilter124 } from '../drawable/ic_baseline_filter_1_24';
import { IcBaselineFilter224 } from '../drawable/ic_baseline_filter_2_24';
import { IcBaselineFilter324 } from '../drawable/ic_baseline_filter_3_24';
import { IcBaselineFilter424 } from '../drawable/ic_baseline_filter_4_24';
import { IcBaselineFilter524 } from '../drawable/ic_baseline_filter_5_24';
import { IcBaselineFilter624 } from '../drawable/ic_baseline_filter_6_24';
import { IcBaselineFilter724 } from '../drawable/ic_baseline_filter_7_24';
import { IcBaselineFilter824 } from '../drawable/ic_baseline_filter_8_24';
import { IcBaselineFilter924 } from '../drawable/ic_baseline_filter_9_24';
import { IcBaselineFilter9Plus24 } from '../drawable/ic_baseline_filter_9_plus_24';
import { IcBaselineBookmarks24 } from '../drawable/ic_baseline_bookmarks_24';
import { IcBaselineSubscriptions24 } from '../drawable/ic_baseline_subscriptions_24';
import { VSettingsDarkX24 } from '../drawable/v_settings_dark_x24';

const DOMAIN: number = 0x0000;
const TAG: string = 'GalleryListSceneView';
const SEARCH_MODE_NORMAL_DEFAULT: number = 0;
const SEARCH_MODE_SUBSCRIPTION: number = 1;
const SEARCH_MODE_UPLOADER: number = 2;
const SEARCH_MODE_TAG: number = 3;

class ListUrlSearchBuilderAdapter implements SearchLayoutBuilder {
  private readonly target: ListUrlBuilder;

  constructor(target: ListUrlBuilder) {
    this.target = target;
  }

  setCategory(category: number): void {
    this.target.setCategory(category);
  }

  setAdvanceSearch(advanceSearch: number): void {
    this.target.setAdvanceSearch(advanceSearch);
  }

  setMinRating(minRating: number): void {
    this.target.setMinRating(minRating);
  }

  setPageFrom(pageFrom: number): void {
    this.target.setPageFrom(pageFrom);
  }

  setPageTo(pageTo: number): void {
    this.target.setPageTo(pageTo);
  }

  setUseSimilarityScan(useSimilarityScan: boolean): void {
    this.target.setUseSimilarityScan(useSimilarityScan);
  }

  setOnlySearchCovers(onlySearchCovers: boolean): void {
    this.target.setOnlySearchCovers(onlySearchCovers);
  }

  setShowExpunged(showExpunged: boolean): void {
    this.target.setShowExpunged(showExpunged);
  }
}

@Component
export struct GalleryListSceneView {
  scene: GalleryListScene | null = null;
  client: EhClientLike | null = null;
  @Prop listUrl: string = '';
  onOpenDrawer: () => void = (): void => {};
  @Prop @Watch('onThemeChanged') themeId: number = -1;
  @Prop @Watch('onRightDrawerOpenSignal') rightDrawerOpenSignal: number = 0;
  @Prop @Watch('onRightDrawerCloseSignal') rightDrawerCloseSignal: number = 0;
  @Prop @Watch('onRightDrawerDragChanged') rightDrawerDragActive: boolean = false;
  @Prop @Watch('onRightDrawerDragChanged') rightDrawerDragProgress: number = 0;
  @Prop @Watch('onRightDrawerDragEnded') rightDrawerDragEndSeq: number = 0;
  @Prop rightDrawerDragSettleOpen: boolean = false;
  onRightDrawerStateChange: (open: boolean) => void = (): void => {};
  onSwipeBlockChange: (blocked: boolean) => void = (): void => {};

  private dataSource: GalleryArrayDataSource = new GalleryArrayDataSource([]);
  private readonly listScroller: ListScroller = new ListScroller();
  private readonly flowScroller: Scroller = new Scroller();
  private lastListResetSeq: number = 0;
  private scrollTopTimerId: number = -1;
  private readonly searchBarMover: SearchBarMoverState = new SearchBarMoverState();
  private readonly searchBarState: SearchBarState = new SearchBarState();
  private readonly searchLayoutState: SearchLayoutState = new SearchLayoutState();
  private readonly fabState: FabBehaviorState = new FabBehaviorState();
  private readonly drawerArrowCtrl: DrawerArrowController = new DrawerArrowController();
  private readonly addDeleteCtrl: AddDeleteDrawableController = new AddDeleteDrawableController();

  @State itemCount: number = 0;
  @State state: number = GalleryListState.NORMAL;
  @State loading: boolean = false;
  @State isPullRefreshing: boolean = false;
  @State reachEnd: boolean = false;
  @State errorMessage: string = '';
  @State activeAction: string = GalleryListAction.HOMEPAGE;
  @State searchKeyword: string = '';
  @State selectedCategory: number = CategoryFlags.NONE;
  @State renderLog: string = '';
  private localFavGidSet: Set<number> = new Set<number>();
  private downloadedGidSet: Set<number> = new Set<number>();
  private readonly searchBarOffset: SearchBarOffsetHolder = new SearchBarOffsetHolder();

  @State listMode: number = Settings.getListMode();
  @State showRating: boolean = Settings.getShowGalleryRating();
  @StorageLink(APP_SHOW_GALLERY_PAGES_STORAGE_KEY) @Watch('onPagesPrefChanged') showGalleryPages: boolean =
    Settings.getShowGalleryPages();
  @StorageLink(APP_SHOW_READ_PROGRESS_STORAGE_KEY) @Watch('onPagesPrefChanged') showReadProgress: boolean =
    Settings.getShowReadProgress();
  @StorageLink(APP_SHOW_JPN_TITLE_STORAGE_KEY) @Watch('onShowJpnTitleChanged') showJpnTitlePref: boolean =
    Settings.getShowJpnTitle();
  @State listLanes: number = 1;
  @State gridColumnsTemplate: string = '1fr 1fr';

  @State searchLayoutOpen: boolean = false;
  @State searchBarSubState: number = SearchBarState.STATE_NORMAL;
  @State searchMode: number = SearchLayoutState.SEARCH_MODE_NORMAL;
  @State normalSearchMode: number = SEARCH_MODE_NORMAL_DEFAULT;
  @State enableAdvance: boolean = false;
  @State searchSuggestions: SearchSuggestionEntry[] = [];
  @State parsedGalleryUrl: DetailUrlResult | null = null;

  @State filterOpen: boolean = false;
  @State filterTagCount: number = 0;

  @State goToDialogOpen: boolean = false;
  @State goToInput: string = '';
  @State goToErrorType: number = 0; // 0=none, 1=invalid, 2=outOfRange
  @State currentPageIndex: number = 0;
  @State totalPages: number = 0;

  @State searchTipDialogOpen: boolean = false;
  @State menuItem: GalleryInfo | null = null;
  @State menuItemIndex: number = -1;

  @State rightDrawerOpen: boolean = false;
  @State rightDrawerOffsetX: number = ThemeDimens.DRAWER_MAX_WIDTH;
  @State rightDrawerScrimOpacity: number = 0;
  @State tagDbRev: number = 0;
  private rightDrawerClosing: boolean = false;
  private lastRightDragEndSeq: number = 0;
  private readonly onTagDbUpdated: () => void = (): void => {
    this.tagDbRev = this.tagDbRev + 1;
    if (this.searchLayoutOpen) {
      this.updateSuggestions(this.searchKeyword);
    }
  };
  private readonly onReadProgressChanged: ReadProgressChangeListener = (changedGids: number[]): void => {
    if (this.showGalleryPages && this.showReadProgress) {
      this.dataSource.notifyDataChangeByGids(changedGids);
    }
  };
  @State rightDrawerPage: number = 0;
  @State quickSearchList: QuickSearch[] = [];
  @State quickSearchLoading: boolean = false;
  @State addQuickSearchDialogOpen: boolean = false;
  @State newQuickSearchName: string = '';
  @State newQuickSearchFocused: boolean = false;
  @State newQuickSearchErrorRes: Resource | null = null;
  @State subscriptionTags: UserTag[] = [];
  @State subscriptionLoading: boolean = false;
  @State subscriptionLoggedIn: boolean = false;
  @State subscriptionError: string = '';

  private viewportWidth: number = 360;
  private atListTop: boolean = true;
  private lastCount: number = 0;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private onThemeChanged(): void {
    this.dataSource.notifyDataReload();
  }

  private onShowJpnTitleChanged(): void {
    this.dataSource.notifyDataReload();
  }

  private onPagesPrefChanged(): void {
    if (this.showGalleryPages && this.showReadProgress) {
      const count: number = this.dataSource.totalCount();
      const list: GalleryInfo[] = [];
      for (let i = 0; i < count; i++) {
        list.push(this.dataSource.getData(i));
      }
      this.prefetchReadProgressForList(list);
    }
    this.dataSource.notifyDataReload();
  }

  private prefetchReadProgressForList(list: GalleryInfo[]): void {
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

  private formatCardPages(item: GalleryInfo): string {
    return ReadProgressCache.formatPagesLabel(
      item.gid,
      item.pages,
      this.showGalleryPages,
      this.showReadProgress
    );
  }

  private onRightDrawerDragChanged(): void {
    if (!this.rightDrawerDragActive) {
      return;
    }
    if (this.searchLayoutOpen || this.addQuickSearchDialogOpen || this.goToDialogOpen
      || this.searchTipDialogOpen || this.menuItem !== null) {
      return;
    }
    const p: number = Math.max(0, Math.min(1, this.rightDrawerDragProgress));
    const firstOpen: boolean = !this.rightDrawerOpen;
    this.rightDrawerClosing = false;
    this.rightDrawerOpen = true;
    this.rightDrawerOffsetX = ThemeDimens.DRAWER_MAX_WIDTH * (1 - p);
    this.rightDrawerScrimOpacity = p;
    if (firstOpen) {
      void this.loadQuickSearches();
      if (this.rightDrawerPage === 1) {
        void this.loadSubscriptions();
      }
    }
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
      void this.loadQuickSearches();
      if (this.rightDrawerPage === 1) {
        void this.loadSubscriptions();
      }
      this.getUIContext().animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
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
      this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
        this.rightDrawerOffsetX = 0;
        this.rightDrawerScrimOpacity = 1;
      });
      void this.loadQuickSearches();
      if (this.rightDrawerPage === 1) {
        void this.loadSubscriptions();
      }
      return;
    }
    if (!this.rightDrawerOpen || this.rightDrawerClosing) {
      return;
    }
    this.rightDrawerClosing = true;
    this.onRightDrawerStateChange(false);
    this.getUIContext().animateTo({
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
    if (!this.searchLayoutOpen && !this.addQuickSearchDialogOpen && !this.goToDialogOpen
      && !this.searchTipDialogOpen && this.menuItem === null) {
      this.setRightDrawerOpen(true);
    }
  }

  private onRightDrawerCloseSignal(): void {
    if (this.rightDrawerCloseSignal <= 0) {
      return;
    }
    if (this.rightDrawerOpen) {
      this.setRightDrawerOpen(false);
    }
  }

  private async loadQuickSearches(): Promise<void> {
    this.quickSearchLoading = true;
    try {
      this.quickSearchList = await EhDB.getAllQuickSearch();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'loadQuickSearches failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    } finally {
      this.quickSearchLoading = false;
    }
  }

  private async loadSubscriptions(): Promise<void> {
    this.subscriptionLoggedIn = Settings.isLogin();
    if (!this.subscriptionLoggedIn) {
      this.subscriptionTags = [];
      this.subscriptionError = '';
      return;
    }
    this.subscriptionLoading = true;
    this.subscriptionError = '';
    try {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      const caller: HttpCaller = new OkHttpCallerAdapter(
        EhApplication.getOkHttpClient(ctx === undefined ? null : ctx)
      );
      const res: UserTagList | null = await EhEngine.getWatchedList(null, caller, EhUrl.getMyTag());
      this.subscriptionTags = res !== null ? res.userTags : [];
    } catch (e) {
      this.subscriptionError = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'loadSubscriptions failed: %{public}s', this.subscriptionError);
    } finally {
      this.subscriptionLoading = false;
    }
  }

  private applyQuickSearch(qs: QuickSearch): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      return;
    }
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.copyFromQuickSearch(qs);
    const url: string = builder.build();
    this.setRightDrawerOpen(false);
    this.activeAction = GalleryListAction.LIST_URL_BUILDER;
    this.resetSearchBarPosition();
    s.switchToAction(GalleryListAction.LIST_URL_BUILDER, url);
    this.searchKeyword = s.getSearchKey();
    this.requestRefresh(true);
  }

  private applySubscriptionTag(tag: UserTag): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null || tag.tagName.length === 0) {
      return;
    }
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_TAG);
    builder.setKeyword(tag.tagName);
    const url: string = builder.build();
    this.setRightDrawerOpen(false);
    this.activeAction = GalleryListAction.LIST_URL_BUILDER;
    this.resetSearchBarPosition();
    s.switchToAction(GalleryListAction.LIST_URL_BUILDER, url);
    this.searchKeyword = s.getSearchKey();
    this.requestRefresh(true);
  }

  private openAddQuickSearchDialog(): void {
    this.newQuickSearchName = this.searchKeyword.trim();
    this.newQuickSearchErrorRes = null;
    this.addQuickSearchDialogOpen = true;
    this.onSwipeBlockChange(true);
  }

  private async confirmAddQuickSearch(): Promise<void> {
    const name: string = this.newQuickSearchName.trim();
    if (name.length === 0) {
      this.newQuickSearchErrorRes = $r('app.string.name_is_empty');
      return;
    }
    for (let i = 0; i < this.quickSearchList.length; i++) {
      if (this.quickSearchList[i].getName() === name) {
        this.newQuickSearchErrorRes = $r('app.string.duplicate_name');
        return;
      }
    }
    const qs: QuickSearch = new QuickSearch();
    qs.setName(name);
    const kw: string = this.searchKeyword.trim();
    if (this.searchMode === SearchLayoutState.SEARCH_MODE_IMAGE) {
      qs.setMode(ListUrlBuilder.MODE_IMAGE_SEARCH);
    } else if (this.normalSearchMode === SEARCH_MODE_SUBSCRIPTION) {
      qs.setMode(ListUrlBuilder.MODE_SUBSCRIPTION);
    } else if (this.normalSearchMode === SEARCH_MODE_UPLOADER) {
      qs.setMode(ListUrlBuilder.MODE_UPLOADER);
    } else if (this.normalSearchMode === SEARCH_MODE_TAG) {
      qs.setMode(ListUrlBuilder.MODE_TAG);
    } else {
      qs.setMode(ListUrlBuilder.MODE_NORMAL);
    }
    qs.setKeyword(kw.length > 0 ? kw : null);
    qs.setCategory(this.selectedCategory);
    if (this.enableAdvance) {
      qs.setAdvanceSearch(this.searchLayoutState.advance.getAdvanceSearch());
      qs.setMinRating(this.searchLayoutState.advance.getMinRating());
      qs.setPageFrom(this.searchLayoutState.advance.getPageFrom());
      qs.setPageTo(this.searchLayoutState.advance.getPageTo());
    } else {
      qs.setAdvanceSearch(-1);
      qs.setMinRating(-1);
      qs.setPageFrom(-1);
      qs.setPageTo(-1);
    }
    qs.setTime(Date.now());
    try {
      await EhDB.insertQuickSearch(qs);
      this.addQuickSearchDialogOpen = false;
      this.newQuickSearchErrorRes = null;
      this.onSwipeBlockChange(this.searchLayoutOpen);
      await this.loadQuickSearches();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'insertQuickSearch failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private openQuickSearchManager(): void {
    this.setRightDrawerOpen(false);
    if (this.scene !== null) {
      this.scene.startScene(new Announcer('QuickSearchScene'));
    }
  }

  private openSubscriptionsManager(): void {
    this.setRightDrawerOpen(false);
    if (this.scene !== null) {
      this.scene.startScene(new Announcer('SubscriptionsScene'));
    }
  }

  private str(key: string): string {
    return GetText.getString(key);
  }

  aboutToAppear(): void {
    this.lastRightDragEndSeq = this.rightDrawerDragEndSeq;
    EhTagDatabaseUpdater.addUpdateListener(this.onTagDbUpdated);
    ReadProgressCache.addListener(this.onReadProgressChanged);
    this.syncDisplaySettings();

    this.searchBarMover.helper = new SearchBarMoverHelperImpl(
      (viewId: number): boolean => viewId === 0,
      (): number => 0,
      (): boolean => this.searchLayoutOpen || this.searchKeyword.length > 0 || this.loading
    );
    this.searchBarMover.canScrollUp = (): boolean => !this.atListTop;
    const barTotalH: number = ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR;
    this.searchBarMover.setMetrics(barTotalH, 0, barTotalH);

    this.searchLayoutState.image.setHelper(new HelperImpl((): void => {
      this.pickImageForSearch();
    }));

    this.fabState.setAutoCancel(true);
    this.fabState.setExpanded(false, false);
    this.fabState.setHidePrimaryFab(false, false);
    this.fabState.setOnClickFabListener(new OnClickFabListenerImpl(
      (): void => {
        this.fabState.toggle();
      },
      (_layout: FabBehaviorState, position: number): void => {
        this.onClickSecondaryFab(position);
      }
    ));
    this.fabState.setOnExpandListener(new OnExpandListenerImpl((_expanded: boolean): void => {
      // Visual rotation handled inside FabLayout
    }));

    this.drawerArrowCtrl.setMenu(0);
    this.addDeleteCtrl.setAdd(0);

    this.loadLocalFavGids();
    this.loadDownloadedGids();

    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      this.state = GalleryListState.ERROR;
      this.errorMessage = 'GalleryListScene is null';
      this.renderLog = 'renderBranch=GalleryListScene blocked=scene-null';
      hilog.warn(DOMAIN, TAG, '%{public}s', this.renderLog);
      return;
    }
    this.lastListResetSeq = s.getListResetSeq();
    s.setOnDataChangedListener((): void => {
      this.syncFromScene();
    });

    const effectiveUrl: string = s.getListUrl().length > 0
      ? s.getListUrl() : this.listUrl;
    if (this.client === null || effectiveUrl.length === 0) {
      this.state = GalleryListState.ERROR;
      this.errorMessage = this.client === null
        ? 'Gallery list client is not injected'
        : 'Gallery list URL is empty';
      this.renderLog = 'renderBranch=GalleryListScene blocked=client-or-url-missing'
        + ' client=' + (this.client === null ? 'null' : 'ok')
        + ' url=' + (effectiveUrl.length === 0 ? 'empty' : 'ok');
      hilog.warn(DOMAIN, TAG, '%{public}s', this.renderLog);
      return;
    }

    s.setGalleryListClient(this.client as EhClientLike);
    if (this.client instanceof GalleryListClient) {
      s.setClientMetaProvider(this.client as GalleryListClient);
    }
    if (s.getListUrl().length === 0) {
      s.setListUrl(this.listUrl);
    }

    this.searchKeyword = s.getSearchKey();
    this.selectedCategory = s.getSearchCategory();
    this.searchLayoutState.category.setCategory(this.selectedCategory);
    this.syncFromScene();

    TagSelectorResultBus.setListener((query: string): void => {
      this.applyTagSelectorResult(query);
    });
    const pendingTags: string | null = TagSelectorResultBus.consumePendingResult();
    if (pendingTags !== null) {
      this.applyTagSelectorResult(pendingTags);
    }

    if (s.getItemCount() === 0 && !s.isLoadingList()) {
      this.requestRefresh();
    }
  }

  aboutToDisappear(): void {
    if (this.scrollTopTimerId !== -1) {
      clearTimeout(this.scrollTopTimerId);
      this.scrollTopTimerId = -1;
    }
    EhTagDatabaseUpdater.removeUpdateListener(this.onTagDbUpdated);
    ReadProgressCache.removeListener(this.onReadProgressChanged);
    TagSelectorResultBus.setListener(null);
    const reqHost = LoadImageController.getDefaultRequestHost();
    if (reqHost instanceof DefaultImageRequestHost) {
      reqHost.resetVisibleRange();
    }
    if (this.scene !== null) {
      this.scene.setOnDataChangedListener(null);
    }
  }

  private syncDisplaySettings(): void {
    this.listMode = Settings.getListMode();
    this.showRating = Settings.getShowGalleryRating();
    this.updateGridMetrics();
  }

  private updateViewportWidth(width: number): void {
    if (width <= 0 || Math.abs(width - this.viewportWidth) < 1) {
      return;
    }
    this.viewportWidth = width;
    this.updateGridMetrics();
  }

  private updateGridMetrics(): void {
    const contentW: number = Math.max(1, this.viewportWidth - ThemeDimens.GALLERY_LIST_MARGIN_H * 2);
    const detailSingle: number = Settings.getDetailSize() === 0
      ? ThemeDimens.GALLERY_LIST_COL_LONG
      : ThemeDimens.GALLERY_LIST_COL_SHORT;
    this.listLanes = Math.max(1, Math.floor(contentW / detailSingle));

    const thumbSizeCode: number = Settings.getThumbSize();
    const thumbSingle: number = thumbSizeCode === 0
      ? ThemeDimens.GALLERY_GRID_COL_LARGE
      : (thumbSizeCode === 2 ? ThemeDimens.GALLERY_GRID_COL_SMALL : ThemeDimens.GALLERY_GRID_COL_MIDDLE);
    const spanCount: number = this.calculateSuitableSpanCount(contentW, thumbSingle);
    const parts: string[] = [];
    for (let i = 0; i < spanCount; i++) {
      parts.push('1fr');
    }
    this.gridColumnsTemplate = parts.join(' ');
  }

  private calculateSuitableSpanCount(totalSize: number, singleSize: number): number {
    if (singleSize <= 0 || totalSize <= singleSize) {
      return 1;
    }
    const floorSpan: number = Math.max(1, Math.floor(totalSize / singleSize));
    const ceilSpan: number = floorSpan + 1;
    const errFloor: number = Math.abs(1 - totalSize / floorSpan / singleSize);
    const errCeil: number = Math.abs(1 - totalSize / ceilSpan / singleSize);
    return errFloor <= errCeil ? floorSpan : ceilSpan;
  }

  private static sameNumberSet(a: Set<number>, b: Set<number>): boolean {
    if (a.size !== b.size) {
      return false;
    }
    let equal: boolean = true;
    a.forEach((v: number): void => {
      if (!b.has(v)) {
        equal = false;
      }
    });
    return equal;
  }

  private loadLocalFavGids(): void {
    EhDB.getAllLocalFavorites().then((list: LocalFavoriteInfo[]) => {
      const next: Set<number> = new Set<number>();
      for (let i = 0; i < list.length; i++) {
        next.add(list[i].gid);
      }
      if (!GalleryListSceneView.sameNumberSet(this.localFavGidSet, next)) {
        this.localFavGidSet = next;
        this.dataSource.notifyDataReload();
      }
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'loadLocalFavGids failed: %{public}s', e.message);
    });
  }

  private loadDownloadedGids(): void {
    DownloadManager.getInstance().then((dm: DownloadManager): void => {
      const infos = dm.getDownloadInfoList();
      const next: Set<number> = new Set<number>();
      for (let i = 0; i < infos.length; i++) {
        next.add(infos[i].gid);
      }
      if (!GalleryListSceneView.sameNumberSet(this.downloadedGidSet, next)) {
        this.downloadedGidSet = next;
        this.dataSource.notifyDataReload();
      }
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'loadDownloadedGids failed: %{public}s', e.message);
    });
  }

  private isDownloaded(gid: number): boolean {
    return this.downloadedGidSet.has(gid);
  }

  private isFavourited(item: GalleryInfo): boolean {
    if (item.favoriteSlot >= -1 && item.favoriteSlot <= 10) {
      return true;
    }
    return this.localFavGidSet.has(item.gid);
  }

  private syncFromScene(): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      this.syncDisplaySettings();
      const count: number = s.getItemCount();
      const list: GalleryInfo[] = [];
      for (let i = 0; i < count; i++) {
        const info: GalleryInfo | null = s.getItem(i);
        if (info !== null) {
          list.push(info);
        }
      }
      this.dataSource.syncItems(list);
      this.itemCount = list.length;
      this.prefetchReadProgressForList(list);
      const nextResetSeq: number = s.getListResetSeq();
      if (nextResetSeq !== this.lastListResetSeq) {
        this.lastListResetSeq = nextResetSeq;
        this.scrollToTopAfterReload(list.length > 0);
      }
      this.state = s.getListState();
      this.loading = s.isLoadingList();
      if (!this.loading) {
        this.isPullRefreshing = false;
      }
      this.reachEnd = s.isReachEndList();
      this.errorMessage = s.getLastError();
      this.activeAction = s.getAction();
      if (!this.searchLayoutOpen) {
        this.searchKeyword = s.getSearchKey();
      }
      this.selectedCategory = s.getSearchCategory();
      this.currentPageIndex = s.getPageIndex();
      this.totalPages = s.getTotalPages();
      this.filterOpen = s.isFilterOpen();
      this.filterTagCount = s.getFilterTagCount();
      this.renderLog = 'renderBranch=GalleryListScene items=' + count.toString()
        + ' (prev=' + this.lastCount.toString() + ') state=' + this.state.toString();
      this.lastCount = count;
      hilog.info(DOMAIN, TAG, '%{public}s', this.renderLog);
    } catch (e) {
      const msg: string = (e as Error).message;
      this.dataSource.setAll([]);
      this.itemCount = 0;
      this.state = GalleryListState.ERROR;
      this.loading = false;
      this.isPullRefreshing = false;
      this.errorMessage = msg;
      this.renderLog = 'renderBranch=GalleryListScene error=' + msg;
      hilog.error(DOMAIN, TAG, '%{public}s', this.renderLog);
    }
  }

  private scrollToTopAfterReload(hasItems: boolean): void {
    this.atListTop = true;
    this.resetSearchBarPosition();
    const reqHost = LoadImageController.getDefaultRequestHost();
    if (reqHost instanceof DefaultImageRequestHost) {
      reqHost.updateVisibleRange(0, 12);
    }
    if (this.scrollTopTimerId !== -1) {
      clearTimeout(this.scrollTopTimerId);
      this.scrollTopTimerId = -1;
    }
    if (!hasItems) {
      return;
    }
    const doScroll = (): void => {
      try {
        if (this.listMode === 0) {
          this.listScroller.scrollEdge(Edge.Top);
        } else {
          this.flowScroller.scrollEdge(Edge.Top);
        }
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'scrollEdge(Edge.Top) skipped: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
    };
    doScroll();
    this.scrollTopTimerId = setTimeout((): void => {
      this.scrollTopTimerId = -1;
      doScroll();
    }, 0) as number;
  }

  private requestRefresh(force: boolean = false): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      s.refreshGalleryList(force);
    } catch (e) {
      this.errorMessage = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'refreshGalleryList threw: %{public}s', this.errorMessage);
    }
  }

  private resetSearchBarPosition(): void {
    this.searchBarMover.showSearchBar(false);
    this.searchBarOffset.translationY = 0;
  }

  private showToastResource(res: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: res, duration: 1500 });
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'showToast failed: %{public}s', msg);
    }
  }

  private enterSearchState(showList: boolean): void {
    if (this.rightDrawerOpen) {
      this.setRightDrawerOpen(false);
    }
    this.onSwipeBlockChange(true);
    this.fabState.setExpanded(false, true);
    this.searchLayoutOpen = true;
    this.searchBarOffset.translationY = 0;
    this.searchBarMover.showSearchBar(true);
    this.searchLayoutState.category.setCategory(this.selectedCategory);
    const nextState: number = showList
      ? SearchBarState.STATE_SEARCH_LIST
      : SearchBarState.STATE_SEARCH;
    this.searchBarSubState = nextState;
    this.searchBarState.setState(nextState, true);
    this.drawerArrowCtrl.setArrow(SearchBarState.ANIMATE_TIME);
    this.addDeleteCtrl.setDelete(SearchBarState.ANIMATE_TIME);
    this.updateSuggestions(this.searchKeyword);
  }

  private exitSearchState(): void {
    this.searchLayoutOpen = false;
    this.onSwipeBlockChange(false);
    this.searchBarSubState = SearchBarState.STATE_NORMAL;
    this.searchBarState.setState(SearchBarState.STATE_NORMAL, true);
    this.searchSuggestions = [];
    this.parsedGalleryUrl = null;
    this.drawerArrowCtrl.setMenu(SearchBarState.ANIMATE_TIME);
    this.addDeleteCtrl.setAdd(SearchBarState.ANIMATE_TIME);
  }

  private onSearchBarBackPressed(): void {
    if (this.searchBarSubState === SearchBarState.STATE_SEARCH_LIST) {
      this.searchBarSubState = SearchBarState.STATE_SEARCH;
      this.searchBarState.setState(SearchBarState.STATE_SEARCH, true);
      this.searchSuggestions = [];
      return;
    }
    this.exitSearchState();
  }

  private onSearchKeywordEdited(value: string): void {
    this.searchKeyword = value;
    this.searchBarState.setSearch(value);
    this.updateSuggestions(value);
  }

  private updateSuggestions(rawQuery: string): void {
    const trimmed: string = rawQuery.trim();
    this.parsedGalleryUrl = GalleryDetailUrlParser.parseWithStrict(trimmed, false);
    const entries: SearchSuggestionEntry[] = [];
    const historyList: string[] = SearchHistoryPrefsStore.getSuggestions(trimmed, 12);
    for (let i = 0; i < historyList.length; i++) {
      const h: string = historyList[i];
      entries.push(new SearchSuggestionEntry('history', h, '', h));
    }

    const tagKeyword: string = SearchTagQueryHelper.extractTagKeyword(rawQuery);
    if (tagKeyword.length > 0) {
      if (!EhTagDatabaseUpdater.isDatabaseReady() && !EhTagDatabaseUpdater.isUpdating()) {
        void EhTagDatabaseUpdater.update(false);
      }
      const hints: TagSuggestion[] = EhTagDatabaseUpdater.suggest(tagKeyword);
      const useTranslation: boolean = Settings.getShowTagTranslations();
      for (let i = 0; i < hints.length; i++) {
        const hint: TagSuggestion = hints[i];
        const hasZh: boolean = useTranslation && hint.chinese.length > 0 && hint.chinese !== 'null';
        const primary: string = hint.english;
        const secondary: string = hasZh ? hint.chinese : '';
        const token: string = SearchTagQueryHelper.formatTagToken(
          hint.english,
          (ns: string): string | null => EhTagDatabase.namespaceToPrefix(ns)
        );
        entries.push(new SearchSuggestionEntry('tag', primary, secondary, token));
      }
    }

    this.searchSuggestions = entries;
    if (this.searchLayoutOpen) {
      if (entries.length > 0 || this.parsedGalleryUrl !== null) {
        this.searchBarSubState = SearchBarState.STATE_SEARCH_LIST;
        this.searchBarState.setState(SearchBarState.STATE_SEARCH_LIST, true);
      } else {
        this.searchBarSubState = SearchBarState.STATE_SEARCH;
        this.searchBarState.setState(SearchBarState.STATE_SEARCH, true);
      }
    }
  }

  private handleSuggestionClick(item: SearchSuggestionEntry): void {
    if (item.kind === 'tag') {
      const next: string = `${SearchTagQueryHelper.replaceTrailingKeyword(this.searchKeyword, item.keywordValue)} `;
      this.onSearchKeywordEdited(next);
      return;
    }
    this.onSearchKeywordEdited(item.primaryText);
  }

  private subscriptionTagDisplayName(tag: UserTag): string {
    if (Settings.getShowTagTranslations()) {
      return TagTranslationUtil.getTagCN1(tag.tagName, EhTagDatabaseUpdater.getDatabase());
    }
    return tag.tagName;
  }

  private deleteHistorySuggestion(item: SearchSuggestionEntry): void {
    SearchHistoryPrefsStore.deleteQuery(item.keywordValue);
    this.updateSuggestions(this.searchKeyword);
  }

  private recordSearchHistory(query: string): void {
    const trimmed: string = query.trim();
    if (trimmed.length === 0) {
      return;
    }
    SearchHistoryPrefsStore.addQuery(trimmed, Date.now());
  }

  private openParsedGallery(parsed: DetailUrlResult): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      return;
    }
    const gi: GalleryInfo = new GalleryInfo();
    gi.gid = parsed.gid;
    gi.token = parsed.token;
    this.exitSearchState();
    s.openGalleryDetail(gi);
  }

  private performSearchFromPanel(): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      return;
    }
    const query: string = this.searchKeyword.trim();

    if (this.searchMode === SearchLayoutState.SEARCH_MODE_IMAGE) {
      if (this.searchLayoutState.image.imagePath.length === 0) {
        this.showToastResource($r('app.string.select_image_first'));
        return;
      }
      const ub: ListUrlBuilder = new ListUrlBuilder();
      ub.setMode(ListUrlBuilder.MODE_IMAGE_SEARCH);
      this.searchLayoutState.formatListUrlBuilder(new ListUrlSearchBuilderAdapter(ub));
      this.exitSearchState();
      this.resetSearchBarPosition();
      s.switchToAction(GalleryListAction.LIST_URL_BUILDER, ub.build());
      this.requestRefresh(true);
      return;
    }

    if (query.length > 0) {
      this.recordSearchHistory(query);
    }
    const cat: number = this.searchLayoutState.category.getCategory();
    this.selectedCategory = cat;

    if (this.normalSearchMode === SEARCH_MODE_NORMAL_DEFAULT && !this.enableAdvance) {
      this.exitSearchState();
      this.resetSearchBarPosition();
      s.applySearchAndCategory(query, cat);
      return;
    }

    const ub: ListUrlBuilder = new ListUrlBuilder();
    if (this.normalSearchMode === SEARCH_MODE_SUBSCRIPTION) {
      ub.setMode(ListUrlBuilder.MODE_SUBSCRIPTION);
      ub.setKeyword(query.length > 0 ? query : null);
      this.searchLayoutState.formatListUrlBuilder(new ListUrlSearchBuilderAdapter(ub));
      if (!this.enableAdvance) {
        ub.setAdvanceSearch(-1);
        ub.setMinRating(-1);
        ub.setPageFrom(-1);
        ub.setPageTo(-1);
      }
    } else if (this.normalSearchMode === SEARCH_MODE_UPLOADER) {
      ub.setMode(ListUrlBuilder.MODE_UPLOADER);
      ub.setKeyword(query.length > 0 ? query : null);
    } else if (this.normalSearchMode === SEARCH_MODE_TAG) {
      ub.setMode(ListUrlBuilder.MODE_TAG);
      ub.setKeyword(query.length > 0 ? query : null);
    } else {
      ub.setMode(ListUrlBuilder.MODE_NORMAL);
      ub.setKeyword(query.length > 0 ? query : null);
      this.searchLayoutState.formatListUrlBuilder(new ListUrlSearchBuilderAdapter(ub));
      if (!this.enableAdvance) {
        ub.setAdvanceSearch(-1);
        ub.setMinRating(-1);
        ub.setPageFrom(-1);
        ub.setPageTo(-1);
      }
    }

    this.exitSearchState();
    this.resetSearchBarPosition();
    s.switchToAction(GalleryListAction.LIST_URL_BUILDER, ub.build());
    this.requestRefresh(true);
  }

  private pickImageForSearch(): void {
    let ctx: common.Context | undefined = undefined;
    try {
      ctx = this.getUIContext().getHostContext();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'getHostContext unavailable: %{public}s', msg);
    }
    const docPicker: picker.DocumentViewPicker = ctx !== undefined
      ? new picker.DocumentViewPicker(ctx)
      : new picker.DocumentViewPicker();
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];
    docPicker.select(options).then((uris: Array<string>): void => {
      if (uris.length > 0 && uris[0].length > 0) {
        this.searchLayoutState.image.setImagePath(uris[0]);
      }
    }).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'Image picker failed: %{public}s', err.message);
    });
  }

  private applyTagSelectorResult(query: string): void {
    const trimmed: string = query.trim();
    if (trimmed.length === 0) {
      return;
    }
    const s: GalleryListScene | null = this.scene;
    if (s !== null && this.filterOpen) {
      s.addFilterTag(trimmed);
      this.filterTagCount = s.getFilterTagCount();
      return;
    }
    this.searchKeyword = trimmed;
    this.exitSearchState();
    this.resetSearchBarPosition();
    if (s !== null) {
      s.applySearchAndCategory(trimmed, this.selectedCategory);
    }
  }

  private openTagSelectorPage(): void {
    const plan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.TAG_SELECTOR, true);
    if (plan.kind !== RouteActionKind.PUSH) {
      hilog.warn(DOMAIN, TAG, 'TagSelectorPage route unavailable: kind=%{public}s', plan.kind);
      return;
    }
    const routeParams: Record<string, Object> = {};
    routeParams['selected_tags'] = this.searchKeyword;
    this.getUIContext().getRouter().pushUrl({
      url: PageRoutes.TAG_SELECTOR,
      params: routeParams
    }).catch((e: Error): void => {
      const msg: string = e.message !== undefined ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'openTagSelectorPage failed: %{public}s', msg);
    });
  }

  private onClickSecondaryFab(position: number): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      return;
    }
    switch (position) {
      case 0: {
        const nextOpen: boolean = !s.isFilterOpen();
        s.setFilterOpen(nextOpen);
        this.filterOpen = s.isFilterOpen();
        if (!this.filterOpen) {
          s.clearFilterTags();
        }
        this.filterTagCount = s.getFilterTagCount();
        break;
      }
      case 1: {
        if (this.activeAction === GalleryListAction.TOP_LIST) {
          break;
        }
        this.goToInput = String(Math.max(1, this.currentPageIndex + 1));
        this.goToErrorType = 0;
        this.goToDialogOpen = true;
        break;
      }
      case 2:
        this.requestRefresh(true);
        break;
      case 3: {
        const count: number = s.getItemCount();
        if (count > 0) {
          const idx: number = Math.floor(Math.random() * count);
          const target: GalleryInfo | null = s.getItem(idx);
          if (target !== null) {
            s.openGalleryDetail(target);
          }
        }
        break;
      }
      default:
        break;
    }
    this.fabState.setExpanded(false, true);
  }

  private confirmGoToPage(): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      this.goToDialogOpen = false;
      return;
    }
    const trimmed: string = this.goToInput.trim();
    if (!/^\d+$/.test(trimmed)) {
      this.goToErrorType = 1;
      return;
    }
    const targetPage: number = Number.parseInt(trimmed, 10);
    if (Number.isNaN(targetPage) || targetPage < 1 || (this.totalPages > 0 && targetPage > this.totalPages)) {
      this.goToErrorType = 2;
      return;
    }
    this.goToErrorType = 0;
    this.goToDialogOpen = false;
    s.jumpToPage(targetPage);
  }

  private openItemMenu(index: number, item: GalleryInfo): void {
    this.menuItemIndex = index;
    this.menuItem = item;
  }

  private openReaderFromMenu(item: GalleryInfo): void {
    const title: string = EhUtils.getSuitableTitle(item) ?? item.title;
    const apiUrl: string = item.gid > 0 && item.token.length > 0
      ? EhUrl.getGalleryDetailUrl(item.gid, item.token, 0, false)
      : '';
    const params: GalleryReaderRouteParams = new GalleryReaderRouteParams(
      item.gid,
      item.token,
      0,
      Math.max(1, item.pages),
      title,
      apiUrl
    );
    this.getUIContext().getRouter().pushUrl({
      url: PageRoutes.GALLERY_READER,
      params: params
    }).catch((e: Error): void => {
      const msg: string = e.message !== undefined ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'openReaderFromMenu failed: %{public}s', msg);
    });
  }

  private onReachEnd(): void {
    const s: GalleryListScene | null = this.scene;
    if (s === null) {
      return;
    }
    if (s.isReachEndList()) {
      hilog.info(DOMAIN, TAG, 'onReachEnd reached end of list');
      return;
    }
    try {
      s.onReachEndList();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onReachEndList threw: %{public}s', (e as Error).message);
    }
  }

  private handleScrollDelta(scrollOffset: number, _scrollState: ScrollState): void {
    if (this.searchLayoutOpen) {
      if (this.searchBarOffset.translationY !== 0) {
        this.searchBarOffset.translationY = 0;
      }
      return;
    }
    if (Math.abs(scrollOffset) < 0.5) {
      return;
    }
    const step: number = this.searchBarMover.applyScrollDelta(scrollOffset);
    if (step !== 0) {
      const nextY: number = this.searchBarMover.translationY;
      if (Math.abs(nextY - this.searchBarOffset.translationY) >= 1) {
        this.searchBarOffset.translationY = nextY;
      }
    }
  }

  private handleScrollStop(): void {
    if (this.searchLayoutOpen) {
      if (this.searchBarOffset.translationY !== 0) {
        this.searchBarOffset.translationY = 0;
      }
      return;
    }
    this.searchBarMover.returnSearchBarPosition(true);
    const nextY: number = this.searchBarMover.translationY;
    if (Math.abs(nextY - this.searchBarOffset.translationY) >= 1) {
      this.searchBarOffset.translationY = nextY;
    }
  }

  private handleScrollIndex(start: number, end?: number): void {
    const reqHost = LoadImageController.getDefaultRequestHost();
    if (reqHost instanceof DefaultImageRequestHost) {
      const visibleEnd: number = end !== undefined && end >= start ? end : start + 12;
      reqHost.updateVisibleRange(start, visibleEnd);
    }
    const nextTop: boolean = start === 0;
    if (this.atListTop !== nextTop) {
      this.atListTop = nextTop;
    }
    if (start === 0) {
      this.searchBarMover.showSearchBar(true);
      const nextY: number = this.searchBarMover.translationY;
      if (Math.abs(nextY - this.searchBarOffset.translationY) >= 1) {
        this.searchBarOffset.translationY = nextY;
      }
    }
  }

  private resolveSearchBarPlaceholderResource(): Resource {
    if (this.activeAction === GalleryListAction.WHATS_HOT) {
      return $r('app.string.whats_hot');
    }
    if (this.activeAction === GalleryListAction.SUBSCRIPTION) {
      return $r('app.string.subscription');
    }
    if (this.activeAction === GalleryListAction.TOP_LIST) {
      return $r('app.string.gallery_toplists');
    }
    return Settings.getGallerySite() === EhUrl.SITE_EX
      ? $r('app.string.gallery_list_search_bar_hint_exhentai')
      : $r('app.string.gallery_list_search_bar_hint_e_hentai');
  }

  private getSearchHintText(): string {
    return Settings.getGallerySite() === EhUrl.SITE_EX
      ? this.str('gallery_list_search_bar_hint_exhentai')
      : this.str('gallery_list_search_bar_hint_e_hentai');
  }

  getItemCount(): number { return this.itemCount; }
  isListVisible(): boolean { return this.itemCount > 0; }
  getRenderLog(): string { return this.renderLog; }
  getState(): number { return this.state; }

  @Builder
  filterFabIcon() {
    if (!this.filterOpen) {
      IcBaselineFilterNone24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().white })
    } else if (this.filterTagCount <= 0) {
      IcBaselineFilter24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 1) {
      IcBaselineFilter124({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 2) {
      IcBaselineFilter224({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 3) {
      IcBaselineFilter324({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 4) {
      IcBaselineFilter424({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 5) {
      IcBaselineFilter524({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 6) {
      IcBaselineFilter624({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 7) {
      IcBaselineFilter724({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 8) {
      IcBaselineFilter824({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else if (this.filterTagCount === 9) {
      IcBaselineFilter924({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    } else {
      IcBaselineFilter9Plus24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD })
    }
  }

  @Builder
  floatingSearchBar() {
    Column() {
      // Main 48vp SearchBar header row (widget_search_bar.xml)
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          DrawerArrowDrawable({
            controller: this.drawerArrowCtrl,
            drawableSize: ThemeDimens.ICON_SIZE_STANDARD,
            color: this.palette().drawablePrimary
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
        .onClick((): void => {
          if (this.searchLayoutOpen) {
            this.onSearchBarBackPressed();
          } else {
            this.onOpenDrawer();
          }
        })

        if (this.searchLayoutOpen) {
          TextInput({ text: this.searchKeyword, placeholder: this.getSearchHintText() })
            .layoutWeight(1)
            .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().textHint)
            .backgroundColor(Color.Transparent)
            .borderRadius(0)
            .padding({ left: 4, right: 4 })
            .enterKeyType(EnterKeyType.Search)
            .onChange((val: string): void => {
              this.onSearchKeywordEdited(val);
            })
            .onSubmit((): void => {
              this.performSearchFromPanel();
            })
        } else {
          Row() {
            if (this.searchKeyword.trim().length > 0) {
              Text(this.searchKeyword)
                .fontColor(this.palette().textPrimary)
                .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            } else {
              Text(this.resolveSearchBarPlaceholderResource())
                .fontColor(this.palette().textHint)
                .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
          .padding({ left: 4, right: 4 })
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.enterSearchState(false);
          })
        }

        Stack({ alignContent: Alignment.Center }) {
          AddDeleteDrawable({
            controller: this.addDeleteCtrl,
            addSize: 20,
            barThickness: 2,
            color: this.palette().drawablePrimary
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)
        .onClick((): void => {
          if (this.searchLayoutOpen) {
            if (this.searchKeyword.length > 0) {
              this.searchKeyword = '';
              this.updateSuggestions('');
            } else {
              this.exitSearchState();
            }
          } else {
            this.enterSearchState(true);
          }
        })
      }
      .width('100%')
      .height(ThemeDimens.GALLERY_SEARCH_BAR_HEIGHT)

      // Expandable suggestion / URL banner area (STATE_SEARCH_LIST)
      if (this.searchLayoutOpen && this.searchBarSubState === SearchBarState.STATE_SEARCH_LIST) {
        if (this.parsedGalleryUrl !== null) {
          Divider().height(ThemeDimens.DIVIDER_HEIGHT).color(this.palette().divider)
          Row({ space: 12 }) {
            VMagnifyDarkX24({ iconSize: 20, fillColor: this.palette().textThemeAccent })
            Text($r('app.string.gallery_list_search_bar_open_gallery'))
              .fontColor(this.palette().textThemeAccent)
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick((): void => {
            if (this.parsedGalleryUrl !== null) {
              this.openParsedGallery(this.parsedGalleryUrl);
            }
          })
        }

        if (this.searchSuggestions.length > 0) {
          Divider().height(ThemeDimens.DIVIDER_HEIGHT).color(this.palette().divider)
          Scroll() {
            Column() {
              ForEach(this.searchSuggestions, (item: SearchSuggestionEntry) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(item.primaryText)
                      .fontColor(this.palette().textPrimary)
                      .fontSize(ThemeTypography.TEXT_SMALL)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')

                    if (item.secondaryText.length > 0) {
                      Text(item.secondaryText)
                        .fontColor(this.palette().textSecondary)
                        .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (item.kind === 'history') {
                    Button({ type: ButtonType.Normal }) {
                      VDeleteX24({
                        iconSize: 18,
                        fillColor: this.palette().textSecondary
                      })
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(ThemeRadius.NONE)
                    .backgroundColor(Color.Transparent)
                    .onClick((): void => {
                      this.deleteHistorySuggestion(item);
                    })
                  }
                }
                .width('100%')
                .constraintSize({ minHeight: item.secondaryText.length > 0 ? 48 : 42 })
                .padding({ left: 52, right: 12, top: 4, bottom: 4 })
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.handleSuggestionClick(item);
                })
                .gesture(
                  LongPressGesture()
                    .onAction((): void => {
                      if (item.kind === 'history') {
                        this.deleteHistorySuggestion(item);
                      }
                    })
                )
              }, (item: SearchSuggestionEntry, idx: number) => `${idx}_${item.kind}_${item.keywordValue}`)
            }
            .width('100%')
          }
          .align(Alignment.TopStart)
          .width('100%')
          .constraintSize({ maxHeight: 280 })
        }
      }
    }
    .width('100%')
    .backgroundColor(this.palette().cardWhiteSurface)
    .borderRadius(ThemeRadius.SEARCH_BAR)
    .shadow(ThemeElevation.searchBar())
    .clip(true)
  }

  @Builder
  normalSearchModeRadio(mode: number, radioVal: string, labelRes: Resource) {
    Row({ space: 4 }) {
      Radio({ value: radioVal, group: 'normalSearchModeGroup' })
        .checked(this.normalSearchMode === mode)
        .radioStyle({ checkedBackgroundColor: this.palette().controlActivated })
        .onChange((isChecked: boolean): void => {
          if (isChecked) {
            this.normalSearchMode = mode;
          }
        })
      Text(labelRes)
        .fontColor(this.palette().textPrimary)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .layoutWeight(1)
    .height(36)
    .onClick((): void => {
      this.normalSearchMode = mode;
    })
  }

  @Builder
  searchLayoutPanel() {
    Scroll() {
      Column({ space: ThemeDimens.SEARCH_ITEM_INTERVAL }) {
        if (this.searchMode === SearchLayoutState.SEARCH_MODE_NORMAL) {
          // Normal search card (search_normal.xml)
          Column({ space: 8 }) {
            Text($r('app.string.search_normal'))
              .fontColor(this.palette().textPrimary)
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontWeight(FontWeight.Medium)
              .width('100%')

            CategoryTable({
              state: this.searchLayoutState.category,
              themeId: this.themeId,
              onChange: (cat: number): void => {
                this.selectedCategory = cat;
              }
            })

            Divider().height(ThemeDimens.DIVIDER_HEIGHT).color(this.palette().divider)

            // 2-column RadioGrid matching search_normal.xml RadioGridGroup
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                this.normalSearchModeRadio(SEARCH_MODE_NORMAL_DEFAULT, 'normal', $r('app.string.search_normal_search'))
                this.normalSearchModeRadio(SEARCH_MODE_SUBSCRIPTION, 'sub', $r('app.string.search_subscription_search'))
              }
              .width('100%')

              Row({ space: 8 }) {
                this.normalSearchModeRadio(SEARCH_MODE_UPLOADER, 'uploader', $r('app.string.search_specify_uploader'))
                this.normalSearchModeRadio(SEARCH_MODE_TAG, 'tag', $r('app.string.search_specify_tag'))
              }
              .width('100%')
            }
            .width('100%')

            Row({ space: 8 }) {
              Stack({ alignContent: Alignment.Center }) {
                VHelpCircleX24({
                  iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                  fillColor: this.palette().drawablePrimary
                })
              }
              .width(36)
              .height(36)
              .onClick((): void => {
                this.searchTipDialogOpen = true;
              })

              Blank().layoutWeight(1)

              Text($r('app.string.search_enable_advance'))
                .fontColor(this.palette().textPrimary)
                .fontSize(ThemeTypography.TEXT_SMALL)

              Toggle({ type: ToggleType.Switch, isOn: this.enableAdvance })
                .selectedColor(this.palette().controlActivated)
                .onChange((isOn: boolean): void => {
                  this.enableAdvance = isOn;
                  this.searchLayoutState.enableAdvance = isOn;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(this.palette().cardBackground)
          .borderRadius(ThemeRadius.CARD)
          .shadow(ThemeElevation.card())

          if (this.enableAdvance) {
            // Advance search card (search_advance.xml)
            Column({ space: 8 }) {
              Text($r('app.string.search_advance'))
                .fontColor(this.palette().textPrimary)
                .fontSize(ThemeTypography.CARD_TITLE)
                .fontWeight(FontWeight.Medium)
                .width('100%')

              AdvanceSearchTable({
                state: this.searchLayoutState.advance,
                themeId: this.themeId,
                labelSname: this.str('search_sname'),
                labelStags: this.str('search_stags'),
                labelSdesc: this.str('search_sdesc'),
                labelStorr: this.str('search_storr'),
                labelSto: this.str('search_sto'),
                labelSdt1: this.str('search_sdt1'),
                labelSdt2: this.str('search_sdt2'),
                labelSh: this.str('search_sh'),
                labelSr: this.str('search_sr'),
                labelSp: this.str('search_sp'),
                labelSpTo: this.str('search_sp_to'),
                labelSf: this.str('search_sf'),
                labelSfl: this.str('search_sfl'),
                labelSfu: this.str('search_sfu'),
                labelSft: this.str('search_sft')
              })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.palette().cardBackground)
            .borderRadius(ThemeRadius.CARD)
            .shadow(ThemeElevation.card())
          }
        } else {
          // Image search card (search_image.xml)
          Column({ space: 8 }) {
            Text($r('app.string.search_image'))
              .fontColor(this.palette().textPrimary)
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontWeight(FontWeight.Medium)
              .width('100%')

            ImageSearchLayout({
              state: this.searchLayoutState.image,
              themeId: this.themeId,
              labelSelectImage: this.str('select_image'),
              labelUSS: this.str('search_uss'),
              labelOSC: this.str('search_osc'),
              labelSE: this.str('search_se')
            })
          }
          .width('100%')
          .padding(12)
          .backgroundColor(this.palette().cardBackground)
          .borderRadius(ThemeRadius.CARD)
          .shadow(ThemeElevation.card())
        }

        // Action card (search_action.xml)
        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text(this.searchMode === SearchLayoutState.SEARCH_MODE_NORMAL
              ? $r('app.string.image_search')
              : $r('app.string.keyword_search'))
              .fontColor(this.palette().textThemeAccent)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .height(36)
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.searchLayoutState.toggleSearchMode();
            this.searchMode = this.searchLayoutState.searchMode;
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.tag_search_entrance'))
              .fontColor(this.palette().textThemeAccent)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .height(36)
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.openTagSelectorPage();
          })
        }
        .width('100%')
        .padding(8)
        .backgroundColor(this.palette().cardBackground)
        .borderRadius(ThemeRadius.CARD)
        .shadow(ThemeElevation.card())
      }
      .width('100%')
      .padding({
        left: $r('app.float.gallery_list_margin_h'),
        right: $r('app.float.gallery_list_margin_h'),
        top: ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR,
        bottom: ThemeDimens.GALLERY_PADDING_BOTTOM_FAB
      })
    }
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .backgroundColor(this.palette().windowBackground)
  }

  @Builder
  flowFooter() {
    if (this.loading || this.reachEnd) {
      Row({ space: 8 }) {
        if (this.loading) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(this.palette().progressColor)
          Text($r('app.string.loading'))
            .fontColor(this.palette().textSecondary)
            .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
        } else if (this.reachEnd) {
          Text($r('app.string.gallery_list_no_more_data'))
            .fontColor(this.palette().textSecondary)
            .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
        }
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  listModeContent() {
    List({ space: 0, scroller: this.listScroller }) {
      LazyForEach(this.dataSource, (item: GalleryInfo, index: number) => {
        ListItem() {
          GalleryListItemLayout({
            title: EhUtils.getSuitableTitle(item) ?? item.title,
            uploader: item.uploader,
            category: GalleryListClient.formatCategoryLabel(item.category),
            categoryBgColor: GalleryListClient.formatCategoryColor(item.category),
            posted: item.posted,
            pages: this.formatCardPages(item),
            simpleLanguage: item.simpleLanguage ?? '',
            rating: item.rating,
            showRating: this.showRating,
            itemIndex: index,
            thumbUrl: item.thumb,
            thumbKey: EhCacheKeyFactory.getThumbKey(item.gid),
            downloaded: this.isDownloaded(item.gid),
            favourited: this.isFavourited(item),
            themeId: this.themeId,
            cardColor: this.palette().cardBackground,
            titleColor: this.palette().textPrimary,
            messageColor: this.palette().textSecondary
          })
            .reuseId('gallery_list_item')
        }
        .width('100%')
        .onClick((): void => {
          if (MainPageHost.shouldSuppressClick()) {
            return;
          }
          if (this.scene !== null) {
            this.scene.openGalleryDetail(item);
          }
        })
        .gesture(
          LongPressGesture()
            .onAction((): void => {
              if (MainPageHost.shouldSuppressClick()) {
                return;
              }
              this.openItemMenu(index, item);
            })
        )
      }, (item: GalleryInfo, idx: number) => this.dataSource.getItemKey(
        item, idx, this.themeId, this.formatCardPages(item)))

      if (this.loading || this.reachEnd) {
        ListItem() {
          this.flowFooter()
        }
        .width('100%')
      }
    }
    .lanes(this.listLanes)
    .cachedCount(2)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .contentStartOffset(this.state === GalleryListState.ERROR ? 0 : ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR)
    .contentEndOffset(ThemeDimens.GALLERY_PADDING_BOTTOM_FAB)
    .padding({
      left: $r('app.float.gallery_list_margin_h'),
      right: $r('app.float.gallery_list_margin_h')
    })
    .scrollBar(BarState.Auto)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportWidth(Number(newArea.width));
    })
    .onDidScroll((scrollOffset: number, scrollState: ScrollState): void => {
      this.handleScrollDelta(scrollOffset, scrollState);
    })
    .onScrollStop((): void => {
      this.handleScrollStop();
    })
    .onScrollIndex((start: number, end: number): void => {
      this.handleScrollIndex(start, end);
    })
    .onReachEnd((): void => {
      this.onReachEnd();
    })
  }

  @Builder
  gridModeContent() {
    WaterFlow({
      footer: (): void => {
        this.flowFooter();
      },
      scroller: this.flowScroller
    }) {
      LazyForEach(this.dataSource, (item: GalleryInfo, index: number) => {
        FlowItem() {
          ItemGalleryGridLayout({
            thumbUrl: item.thumb,
            thumbKey: EhCacheKeyFactory.getThumbKey(item.gid),
            thumbWidth: item.thumbWidth,
            thumbHeight: item.thumbHeight,
            category: GalleryListClient.formatCategoryLabel(item.category),
            categoryColor: GalleryListClient.formatCategoryColor(item.category),
            simpleLanguage: item.simpleLanguage ?? '',
            themeId: this.themeId,
            itemIndex: index,
            cardColor: this.palette().cardBackground
          })
            .reuseId('gallery_grid_item')
        }
        .width('100%')
        .onClick((): void => {
          if (MainPageHost.shouldSuppressClick()) {
            return;
          }
          if (this.scene !== null) {
            this.scene.openGalleryDetail(item);
          }
        })
        .gesture(
          LongPressGesture()
            .onAction((): void => {
              if (MainPageHost.shouldSuppressClick()) {
                return;
              }
              this.openItemMenu(index, item);
            })
        )
      }, (item: GalleryInfo, idx: number) => this.dataSource.getItemKey(item, idx, this.themeId))
    }
    .columnsTemplate(this.gridColumnsTemplate)
    .cachedCount(2)
    .edgeEffect(EdgeEffect.Spring)
    .columnsGap(0)
    .rowsGap(0)
    .width('100%')
    .height('100%')
    .padding({
      left: $r('app.float.gallery_grid_margin_h'),
      right: $r('app.float.gallery_grid_margin_h'),
      top: this.state === GalleryListState.ERROR ? 0 : ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR,
      bottom: ThemeDimens.GALLERY_PADDING_BOTTOM_FAB
    })
    .scrollBar(BarState.Auto)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportWidth(Number(newArea.width));
    })
    .onDidScroll((scrollOffset: number, scrollState: ScrollState): void => {
      this.handleScrollDelta(scrollOffset, scrollState);
    })
    .onScrollStop((): void => {
      this.handleScrollStop();
    })
    .onScrollIndex((start: number, end: number): void => {
      this.handleScrollIndex(start, end);
    })
    .onReachEnd((): void => {
      this.onReachEnd();
    })
  }

  @Builder
  contentLayer() {
    Refresh({ refreshing: $$this.isPullRefreshing }) {
      Column() {
        if (this.itemCount > 0 && this.state === GalleryListState.ERROR) {
          Row({ space: 10 }) {
            VAlertRedX48({ iconSize: 22 })
            Column({ space: 2 }) {
              Text($r('app.string.load_failed'))
                .fontColor(this.palette().errorColor)
                .fontSize(ThemeTypography.TEXT_SMALL)
                .fontWeight(FontWeight.Medium)
              if (this.errorMessage.length > 0) {
                Text(this.errorMessage)
                  .fontColor(this.palette().textSecondary)
                  .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Button({ type: ButtonType.Normal }) {
              Text($r('app.string.retry'))
                .fontColor(this.palette().textThemeAccent)
                .fontSize(ThemeTypography.BUTTON)
                .fontWeight(FontWeight.Medium)
            }
            .height(34)
            .padding({ left: 12, right: 12 })
            .borderRadius(ThemeRadius.BUTTON)
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.requestRefresh();
            })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 12,
            top: ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR + 4,
            bottom: 8
          })
          .backgroundColor(this.palette().cardBackground)
          .shadow(ThemeElevation.card())
        }

        if (this.itemCount > 0) {
          if (this.listMode === 0) {
            Column() {
              this.listModeContent()
            }
            .width('100%')
            .layoutWeight(1)
          } else {
            Column() {
              this.gridModeContent()
            }
            .width('100%')
            .layoutWeight(1)
          }
        } else {
          // Empty / Loading / Error state (widget_content_layout.xml)
          Column({ space: 12 }) {
            if (this.loading) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(this.palette().progressColor)
              Text($r('app.string.loading'))
                .fontColor(this.palette().textSecondary)
                .fontSize(ThemeTypography.TEXT_SMALL)
            } else if (this.state === GalleryListState.ERROR) {
              BigSadPandroid({ iconSize: 120, fillColor: this.palette().drawableSecondary })
              if (this.errorMessage.length > 0) {
                Text(this.errorMessage)
                  .fontColor(this.palette().textSecondary)
                  .fontSize(ThemeTypography.TEXT_LITTLE_LARGE)
                  .textAlign(TextAlign.Center)
                  .padding({ left: 24, right: 24 })
              } else {
                Text($r('app.string.load_failed'))
                  .fontColor(this.palette().textSecondary)
                  .fontSize(ThemeTypography.TEXT_LITTLE_LARGE)
                  .textAlign(TextAlign.Center)
              }
              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.retry'))
                  .fontColor(this.palette().white)
                  .fontSize(ThemeTypography.BUTTON)
                  .fontWeight(FontWeight.Medium)
              }
              .height(36)
              .padding({ left: 20, right: 20 })
              .borderRadius(ThemeRadius.BUTTON)
              .backgroundColor(this.palette().colorPrimary)
              .onClick((): void => {
                this.requestRefresh();
              })
            } else {
              BigSadPandroid({ iconSize: 120, fillColor: this.palette().drawableSecondary })
              Text(this.activeAction === GalleryListAction.SUBSCRIPTION
                ? $r('app.string.gallery_list_empty_hit_subscription')
                : $r('app.string.gallery_list_empty_hit'))
                .fontColor(this.palette().textSecondary)
                .fontSize(ThemeTypography.TEXT_LITTLE_LARGE)
                .textAlign(TextAlign.Center)
                .padding({ left: 24, right: 24 })
              Button({ type: ButtonType.Normal }) {
                Text($r('app.string.retry'))
                  .fontColor(this.palette().textThemeAccent)
                  .fontSize(ThemeTypography.BUTTON)
                  .fontWeight(FontWeight.Medium)
              }
              .height(36)
              .padding({ left: 16, right: 16 })
              .borderRadius(ThemeRadius.BUTTON)
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.requestRefresh();
              })
            }
          }
          .width('100%')
          .height('100%')
          .padding({ top: ThemeDimens.GALLERY_PADDING_TOP_SEARCH_BAR, bottom: 24, left: 24, right: 24 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
    }
    .onRefreshing((): void => {
      this.isPullRefreshing = true;
      this.requestRefresh();
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  primaryFabIcon(): void {
    VPlusDarkX24({
      iconSize: ThemeDimens.ICON_SIZE_STANDARD,
      fillColor: this.palette().fabIconColor
    })
  }

  @Builder
  secondaryFabIcon(index: number): void {
    if (index === 0) {
      this.filterFabIcon()
    } else if (index === 1) {
      VGoToDarkX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().white })
    } else if (index === 2) {
      VRefreshDarkX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().white })
    } else {
      VRandomDarkX24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().white })
    }
  }

  @Builder
  fabGroupLayer() {
    Column() {
      FabLayout({
        state: this.fabState,
        secondaryFabCount: 4,
        cornerPadding: 0,
        primaryColor: this.palette().widgetThemePrimary,
        accentColor: this.palette().widgetThemeAccent,
        primaryFab: (): void => {
          this.primaryFabIcon();
        },
        secondaryFab: (index: number): void => {
          this.secondaryFabIcon(index);
        }
      })
    }
    .visibility(this.searchLayoutOpen ? Visibility.None : Visibility.Visible)
    .hitTestBehavior(this.searchLayoutOpen ? HitTestMode.None : HitTestMode.Transparent)
  }

  @Builder
  searchFabButton() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        VMagnifyDarkX24({
          iconSize: ThemeDimens.ICON_SIZE_STANDARD,
          fillColor: this.palette().white
        })
      }
      .width(ThemeDimens.FAB_SIZE)
      .height(ThemeDimens.FAB_SIZE)
      .borderRadius(ThemeRadius.FAB_PRIMARY)
      .backgroundColor(this.palette().widgetThemeAccent)
      .shadow(ThemeElevation.fab())
      .onClick((): void => {
        this.performSearchFromPanel();
      })
    }
    .visibility(this.searchLayoutOpen ? Visibility.Visible : Visibility.None)
    .hitTestBehavior(this.searchLayoutOpen ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  goToPageDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.goToDialogOpen = false;
        })

      Column({ space: 12 }) {
        Text($r('app.string.go_to'))
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        Text(`${this.currentPageIndex + 1} / ${this.totalPages > 0 ? this.totalPages : '?'}`)
          .fontColor(this.palette().textSecondary)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .width('100%')

        TextInput({ text: this.goToInput, placeholder: $r('app.string.go_to_hint') })
          .type(InputType.Number)
          .width('100%')
          .height(40)
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .fontColor(this.palette().textPrimary)
          .placeholderColor(this.palette().textHint)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .border({ width: { bottom: 2 }, color: this.palette().colorAccent })
          .padding({ left: 0, right: 0 })
          .onChange((val: string): void => {
            this.goToInput = val;
            this.goToErrorType = 0;
          })
          .onSubmit((): void => {
            this.confirmGoToPage();
          })

        if (this.goToErrorType === 1) {
          Text($r('app.string.error_invalid_number'))
            .fontColor(this.palette().errorColor)
            .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
            .width('100%')
        } else if (this.goToErrorType === 2) {
          Text($r('app.string.error_out_of_range'))
            .fontColor(this.palette().errorColor)
            .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
            .width('100%')
        }

        Row({ space: 8 }) {
          Blank().layoutWeight(1)

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontColor(this.palette().textSecondary)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
          }
          .height(36)
          .padding({ left: 12, right: 12 })
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.goToDialogOpen = false;
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
              .fontColor(this.palette().textThemeAccent)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
          }
          .height(36)
          .padding({ left: 12, right: 12 })
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.confirmGoToPage();
          })
        }
        .width('100%')
        .padding({ top: 4 })
      }
      .width('84%')
      .constraintSize({ maxWidth: 340 })
      .padding({ left: 24, right: 24, top: 20, bottom: 12 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  searchTipDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.searchTipDialogOpen = false;
        })

      Column({ space: 12 }) {
        Text($r('app.string.search'))
          .fontColor(this.palette().textPrimary)
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        Text($r('app.string.search_tip'))
          .fontColor(this.palette().textSecondary)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .lineHeight(20)
          .width('100%')

        Row() {
          Blank().layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
              .fontColor(this.palette().textThemeAccent)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
          }
          .height(36)
          .padding({ left: 12, right: 12 })
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.searchTipDialogOpen = false;
          })
        }
        .width('100%')
      }
      .width('86%')
      .constraintSize({ maxWidth: 360 })
      .padding({ left: 24, right: 24, top: 20, bottom: 12 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  itemContextMenuOverlay() {
    if (this.menuItem !== null) {
      this.itemContextMenuCard(this.menuItem as GalleryInfo)
    }
  }

  @Builder
  itemContextMenuCard(target: GalleryInfo) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.menuItem = null;
          this.menuItemIndex = -1;
        })

      Column() {
        // Custom Material header (gallery_item_dialog_coustom_title.xml)
        Column({ space: 6 }) {
          Text(EhUtils.getSuitableTitle(target) ?? target.title)
            .fontColor(this.palette().textPrimary)
            .fontSize(ThemeTypography.DIALOG_TITLE)
            .fontWeight(FontWeight.Medium)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: 8 }) {
            Text(target.uploader)
              .fontColor(this.palette().textSecondary)
              .fontSize(ThemeTypography.TEXT_SMALL)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text(GalleryListClient.formatCategoryLabel(target.category))
              .fontColor(this.palette().white)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor(GalleryListClient.formatCategoryColor(target.category))
              .borderRadius(ThemeRadius.CATEGORY_BADGE)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Divider().height(ThemeDimens.DIVIDER_HEIGHT).color(this.palette().divider)

        // Read
        Row({ space: 16 }) {
          VBookOpenX24({ iconSize: 24, fillColor: this.palette().drawablePrimary })
          Text($r('app.string.read'))
            .fontColor(this.palette().textPrimary)
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 24, right: 24 })
        .onClick((): void => {
          const picked: GalleryInfo = target;
          this.menuItem = null;
          this.menuItemIndex = -1;
          this.openReaderFromMenu(picked);
        })

        // Download / Delete download
        Row({ space: 16 }) {
          if (this.isDownloaded(target.gid)) {
            VDeleteX24({ iconSize: 24, fillColor: this.palette().drawablePrimary })
          } else {
            VDownloadX24({ iconSize: 24, fillColor: this.palette().drawablePrimary })
          }
          Text(this.isDownloaded(target.gid)
            ? $r('app.string.delete_downloads')
            : $r('app.string.download'))
            .fontColor(this.palette().textPrimary)
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 24, right: 24 })
        .onClick((): void => {
          const picked: GalleryInfo = target;
          const alreadyDownloaded: boolean = this.isDownloaded(picked.gid);
          this.menuItem = null;
          this.menuItemIndex = -1;
          if (alreadyDownloaded) {
            DownloadManager.getInstance().then((dm: DownloadManager): Promise<void> => {
              return dm.deleteDownload(picked.gid);
            }).then((): void => {
              this.loadDownloadedGids();
              this.showToastResource($r('app.string.delete_downloads'));
            }).catch((e: Error): void => {
              hilog.warn(DOMAIN, TAG, 'deleteDownload failed: %{public}s', e.message);
            });
          } else {
            DownloadManager.getInstance().then((dm: DownloadManager): Promise<void> => {
              return dm.startDownload(picked, null);
            }).then((): void => {
              this.loadDownloadedGids();
              this.showToastResource($r('app.string.added_to_download_list'));
            }).catch((e: Error): void => {
              hilog.warn(DOMAIN, TAG, 'startDownload failed: %{public}s', e.message);
            });
          }
        })

        // Add / Remove favourites
        Row({ space: 16 }) {
          if (this.isFavourited(target)) {
            VHeartBrokenX24({ iconSize: 24, fillColor: this.palette().drawablePrimary })
          } else {
            VHeartX24({ iconSize: 24, fillColor: this.palette().drawablePrimary })
          }
          Text(this.isFavourited(target)
            ? $r('app.string.remove_from_favourites')
            : $r('app.string.add_to_favourites'))
            .fontColor(this.palette().textPrimary)
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 24, right: 24 })
        .onClick((): void => {
          const picked: GalleryInfo = target;
          const alreadyFav: boolean = this.isFavourited(picked);
          this.menuItem = null;
          this.menuItemIndex = -1;
          if (alreadyFav) {
            EhDB.removeLocalFavorites(picked.gid).then((): void => {
              this.loadLocalFavGids();
              this.showToastResource($r('app.string.remove_from_favorite_success'));
            }).catch((e: Error): void => {
              hilog.warn(DOMAIN, TAG, 'removeLocalFavorites failed: %{public}s', e.message);
              this.showToastResource($r('app.string.remove_from_favorite_failure'));
            });
          } else {
            EhDB.putLocalFavorite(picked).then((): void => {
              this.loadLocalFavGids();
              this.showToastResource($r('app.string.add_to_favorite_success'));
            }).catch((e: Error): void => {
              hilog.warn(DOMAIN, TAG, 'putLocalFavorite failed: %{public}s', e.message);
              this.showToastResource($r('app.string.add_to_favorite_failure'));
            });
          }
        })

        Column().width('100%').height(8)
      }
      .width('86%')
      .constraintSize({ maxWidth: 360 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  addQuickSearchDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.addQuickSearchDialogOpen = false;
          this.onSwipeBlockChange(this.searchLayoutOpen);
        })

      Column() {
        Text($r('app.string.add_quick_search_dialog_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Column({ space: 8 }) {
          TextInput({ placeholder: $r('app.string.quick_search'), text: this.newQuickSearchName })
            .width('100%')
            .height(44)
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().textPrimary)
            .placeholderColor(this.palette().textHint)
            .caretColor(this.palette().controlActivated)
            .backgroundColor(Color.Transparent)
            .borderRadius(0)
            .padding({ left: 0, right: 0 })
            .onFocus((): void => {
              this.newQuickSearchFocused = true;
            })
            .onBlur((): void => {
              this.newQuickSearchFocused = false;
            })
            .onChange((val: string): void => {
              this.newQuickSearchName = val;
              this.newQuickSearchErrorRes = null;
            })
            .onSubmit((): void => {
              void this.confirmAddQuickSearch();
            })

          Row()
            .width('100%')
            .height(this.newQuickSearchFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
            .backgroundColor(this.newQuickSearchErrorRes !== null
              ? this.palette().errorColor
              : (this.newQuickSearchFocused ? this.palette().colorAccent : this.palette().divider))

          if (this.newQuickSearchErrorRes !== null) {
            Text(this.newQuickSearchErrorRes)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().errorColor)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, bottom: 8 })

        Row({ space: 8 }) {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().textSecondary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.addQuickSearchDialogOpen = false;
              this.onSwipeBlockChange(this.searchLayoutOpen);
            })

          Button($r('app.string.ok'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().textThemeAccent)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              void this.confirmAddQuickSearch();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: ThemeDimens.DIALOG_MAX_WIDTH })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  rightDrawerOverlay() {
    Stack({ alignContent: Alignment.End }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().drawerScrim)
        .opacity(this.rightDrawerScrimOpacity)
        .onClick((): void => {
          this.setRightDrawerOpen(false);
        })

      Column() {
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            if (this.rightDrawerPage === 0) {
              IcBaselineBookmarks24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            } else {
              IcBaselineSubscriptions24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick((): void => {
            this.rightDrawerPage = this.rightDrawerPage === 0 ? 1 : 0;
            if (this.rightDrawerPage === 1) {
              void this.loadSubscriptions();
            } else {
              void this.loadQuickSearches();
            }
          })

          Text(this.rightDrawerPage === 0 ? $r('app.string.quick_search') : $r('app.string.subscription'))
            .fontSize(ThemeTypography.TOOLBAR_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().toolbarTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick((): void => {
              this.rightDrawerPage = this.rightDrawerPage === 0 ? 1 : 0;
              if (this.rightDrawerPage === 1) {
                void this.loadSubscriptions();
              } else {
                void this.loadQuickSearches();
              }
            })

          if (this.rightDrawerPage === 0) {
            Stack({ alignContent: Alignment.Center }) {
              VPlusDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick((): void => {
              this.openAddQuickSearchDialog();
            })

            Stack({ alignContent: Alignment.Center }) {
              VSettingsDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick((): void => {
              this.openQuickSearchManager();
            })
          } else {
            Stack({ alignContent: Alignment.Center }) {
              VRefreshDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick((): void => {
              void this.loadSubscriptions();
            })

            Stack({ alignContent: Alignment.Center }) {
              VSettingsDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().toolbarIconColor
              })
            }
            .width(ThemeDimens.TOUCH_TARGET_MIN)
            .height(ThemeDimens.TOUCH_TARGET_MIN)
            .onClick((): void => {
              this.openSubscriptionsManager();
            })
          }
        }
        .width('100%')
        .height(ThemeDimens.TOOLBAR_HEIGHT)
        .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
        .backgroundColor(this.palette().toolbarColor)
        .shadow(ThemeElevation.toolbar())
        .alignItems(VerticalAlign.Center)

        Row() {
          Column() {
            Text($r('app.string.quick_search'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontWeight(this.rightDrawerPage === 0 ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.rightDrawerPage === 0 ? this.palette().textThemeAccent : this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ top: 10, bottom: 8 })
            Row()
              .width('100%')
              .height(2)
              .backgroundColor(this.rightDrawerPage === 0 ? this.palette().colorAccent : Color.Transparent)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.rightDrawerPage = 0;
            void this.loadQuickSearches();
          })

          Column() {
            Text($r('app.string.subscription'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontWeight(this.rightDrawerPage === 1 ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.rightDrawerPage === 1 ? this.palette().textThemeAccent : this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ top: 10, bottom: 8 })
            Row()
              .width('100%')
              .height(2)
              .backgroundColor(this.rightDrawerPage === 1 ? this.palette().colorAccent : Color.Transparent)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .onClick((): void => {
            this.rightDrawerPage = 1;
            void this.loadSubscriptions();
          })
        }
        .width('100%')
        .backgroundColor(this.palette().surfaceBackground)

        Divider().strokeWidth(ThemeDimens.DIVIDER_HEIGHT).color(this.palette().divider)

        if (this.rightDrawerPage === 0) {
          if (this.quickSearchLoading) {
            Column() {
              LoadingProgress()
                .width(32)
                .height(32)
                .color(this.palette().progressColor)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.quickSearchList.length === 0) {
            Column({ space: 8 }) {
              IcBaselineBookmarks24({
                iconSize: ThemeDimens.ICON_SIZE_LARGE,
                fillColor: this.palette().drawableSecondary
              })
              Text($r('app.string.quick_search_tip'))
                .fontSize(ThemeTypography.TEXT_SMALL)
                .fontColor(this.palette().textSecondary)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .layoutWeight(1)
            .padding(24)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List() {
              ForEach(this.quickSearchList, (qs: QuickSearch, idx: number) => {
                ListItem() {
                  Row() {
                    Text(qs.getName() ?? '')
                      .fontSize(ThemeTypography.CARD_MESSAGE)
                      .fontColor(this.palette().textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
                  .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
                  .alignItems(VerticalAlign.Center)
                  .onClick((): void => {
                    this.applyQuickSearch(qs);
                  })
                }
              }, (qs: QuickSearch, idx: number) => `${idx}_${qs.getName() ?? ''}_${qs.getTime()}`)
            }
            .width('100%')
            .layoutWeight(1)
          }
        } else {
          if (!this.subscriptionLoggedIn) {
            Column({ space: 8 }) {
              IcBaselineSubscriptions24({
                iconSize: ThemeDimens.ICON_SIZE_LARGE,
                fillColor: this.palette().drawableSecondary
              })
              Text($r('app.string.settings_eh_identity_cookies_tourist'))
                .fontSize(ThemeTypography.TEXT_SMALL)
                .fontColor(this.palette().textSecondary)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .layoutWeight(1)
            .padding(24)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.subscriptionLoading) {
            Column() {
              LoadingProgress()
                .width(32)
                .height(32)
                .color(this.palette().progressColor)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.subscriptionTags.length === 0) {
            Column({ space: 8 }) {
              IcBaselineSubscriptions24({
                iconSize: ThemeDimens.ICON_SIZE_LARGE,
                fillColor: this.palette().drawableSecondary
              })
              Text($r('app.string.empty_subscription'))
                .fontSize(ThemeTypography.TEXT_SMALL)
                .fontColor(this.palette().textSecondary)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .layoutWeight(1)
            .padding(24)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List() {
              ForEach(this.subscriptionTags, (tag: UserTag, idx: number) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Text(this.subscriptionTagDisplayName(tag))
                      .fontSize(ThemeTypography.CARD_MESSAGE)
                      .fontColor(this.palette().textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    if (tag.watched || tag.hidden) {
                      Text(tag.watched ? $r('app.string.subscription_watched') : $r('app.string.subscription_hidden'))
                        .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                        .fontColor(tag.watched ? this.palette().textThemeAccent : this.palette().textSecondary)
                        .maxLines(1)
                    }
                  }
                  .width('100%')
                  .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
                  .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
                  .alignItems(VerticalAlign.Center)
                  .onClick((): void => {
                    this.applySubscriptionTag(tag);
                  })
                }
              }, (tag: UserTag, idx: number) => `${idx}_${tag.tagName}_${tag.watched ? 1 : 0}_${this.tagDbRev}`)
            }
            .width('100%')
            .layoutWeight(1)
          }
        }
      }
      .width(ThemeDimens.DRAWER_MAX_WIDTH)
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
            this.getUIContext().animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
              this.rightDrawerOffsetX = 0;
              this.rightDrawerScrimOpacity = 1;
            });
          }
        })
        .onActionCancel((): void => {
          if (this.rightDrawerOffsetX >= ThemeDimens.DRAWER_MAX_WIDTH * 0.35) {
            this.setRightDrawerOpen(false);
          } else {
            this.getUIContext().animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
              this.rightDrawerOffsetX = 0;
              this.rightDrawerScrimOpacity = 1;
            });
          }
        })
    )
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SceneGalleryListLayout({
        contentVisible: !this.searchLayoutOpen,
        searchLayoutVisible: this.searchLayoutOpen,
        searchBarVisible: true,
        forceSearchBarZero: this.searchLayoutOpen,
        searchBarOffset: this.searchBarOffset,
        windowBackground: this.palette().windowBackground,
        contentBuilder: (): void => {
          this.contentLayer();
        },
        searchLayoutBuilder: (): void => {
          this.searchLayoutPanel();
        },
        searchBarBuilder: (): void => {
          this.floatingSearchBar();
        },
        fabBuilder: (): void => {
          this.fabGroupLayer();
        },
        searchFabBuilder: (): void => {
          this.searchFabButton();
        }
      })

      if (this.rightDrawerOpen) {
        this.rightDrawerOverlay()
      }

      if (this.addQuickSearchDialogOpen) {
        this.addQuickSearchDialogOverlay()
      }

      if (this.goToDialogOpen) {
        this.goToPageDialogOverlay();
      }

      if (this.searchTipDialogOpen) {
        this.searchTipDialogOverlay();
      }

      if (this.menuItem !== null) {
        this.itemContextMenuOverlay();
      }
    }
    .width('100%')
    .height('100%')
  }
}
