/*
 * `GalleryPreviewsScene` 的渲染层：Material Toolbar + 3 列缩略图预览网格 + Go-To 对话框 + 分页栏，
 * 通过 `EhEngine.getPreviewSet` 拉取任意预览页，点击单页跳转到 `pages/GalleryReaderPage`。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { EhApplication } from '../../ehviewer/EhApplication';
import { EhEngine, HttpCaller, PreviewSetResult } from '../../ehviewer/client/EhEngine';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { EhUtils } from '../../ehviewer/client/EhUtils';
import { GalleryInfo } from '../../ehviewer/client/data/GalleryInfo';
import { PreviewSet } from '../../ehviewer/client/data/PreviewSet';
import { GalleryPreviewsSceneShell } from '../../ehviewer/ui/scene/GalleryPreviewsSceneShell';
import { KEY_GALLERY_INFO } from '../../ehviewer/ui/scene/GalleryPreviewsScene';
import { GalleryReaderRouteParams } from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailScene';
import { SceneArgs } from '../../scene/SceneTypes';
import { OkHttpCallerAdapter } from '../../AppWiring';
import { PreviewTileView, pushGalleryReaderPage } from './GalleryDetailSceneView';
import { VArrowLeftDarkX24 } from '../drawable/v_arrow_left_dark_x24';
import { VGoToDarkX24 } from '../drawable/v_go_to_dark_x24';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { BigSadPandroid } from '../drawable/big_sad_pandroid';

const DOMAIN: number = 0x0000;
const TAG: string = 'GalleryPreviewsSceneView';

class FullPreviewTileItem {
  readonly index: number;
  readonly position: number;
  readonly pageLabel: string;

  constructor(index: number, position: number) {
    this.index = index;
    this.position = position;
    this.pageLabel = String(position + 1);
  }
}

@Component
export struct GalleryPreviewsSceneView {
  shell: GalleryPreviewsSceneShell | null = null;

  @State gid: number = 0;
  @State token: string = '';
  @State title: string = '';
  @State apiUrl: string = '';
  @State totalGalleryPages: number = 0;
  @State currentPage: number = 0;
  @State previewPages: number = 1;
  @State previewTiles: FullPreviewTileItem[] = [];
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State loadEpoch: number = 0;
  @Prop themeId: number = -1;
  @State showGoToDialog: boolean = false;
  @State goToValue: number = 1;

  private currentPreviewSet: PreviewSet | null = null;
  private initialPreviewSet: PreviewSet | null = null;
  private destroyed: boolean = false;
  private requestSeq: number = 0;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    this.destroyed = false;
    this.readArgs();
    if (this.currentPage === 0 && this.initialPreviewSet !== null && this.initialPreviewSet.size() > 0) {
      const ps: PreviewSet = this.initialPreviewSet;
      this.currentPreviewSet = ps;
      const tiles: FullPreviewTileItem[] = [];
      for (let i = 0; i < ps.size(); i++) {
        tiles.push(new FullPreviewTileItem(i, ps.getPosition(i)));
      }
      this.previewTiles = tiles;
      this.loadEpoch = this.loadEpoch + 1;
      this.loading = false;
      return;
    }
    void this.loadPreviewPage(this.currentPage);
  }

  aboutToDisappear(): void {
    this.destroyed = true;
  }

  private readArgs(): void {
    const sh: GalleryPreviewsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const args: SceneArgs | null = sh.getArguments();
    if (args === null) {
      return;
    }
    const giObj: Object | undefined = args.get(KEY_GALLERY_INFO);
    if (giObj !== undefined && giObj !== null && giObj instanceof GalleryInfo) {
      const gi: GalleryInfo = giObj as GalleryInfo;
      if (gi.gid > 0) {
        this.gid = gi.gid;
      }
      if (gi.token.length > 0) {
        this.token = gi.token;
      }
      if (gi.pages > 0) {
        this.totalGalleryPages = gi.pages;
      }
      const suitable: string = EhUtils.getSuitableTitle(gi) ?? gi.title;
      if (suitable.length > 0) {
        this.title = suitable;
      }
    }

    const gidVal: Object | undefined = args.get('gid');
    if (gidVal !== undefined && typeof gidVal === 'number' && (gidVal as number) > 0) {
      this.gid = Math.trunc(gidVal as number);
    }
    const tokenVal: Object | undefined = args.get('token');
    if (tokenVal !== undefined && typeof tokenVal === 'string' && (tokenVal as string).length > 0) {
      this.token = tokenVal as string;
    }
    const titleVal: Object | undefined = args.get('title');
    if (titleVal !== undefined && typeof titleVal === 'string' && (titleVal as string).length > 0) {
      this.title = titleVal as string;
    }
    const previewPagesVal: Object | undefined = args.get('previewPages');
    if (previewPagesVal !== undefined && typeof previewPagesVal === 'number' && (previewPagesVal as number) > 0) {
      this.previewPages = Math.trunc(previewPagesVal as number);
    }
    const pageIndexVal: Object | undefined = args.get('pageIndex');
    if (pageIndexVal !== undefined && typeof pageIndexVal === 'number' && (pageIndexVal as number) >= 0) {
      this.currentPage = Math.trunc(pageIndexVal as number);
    }
    const apiUrlVal: Object | undefined = args.get('apiUrl');
    if (apiUrlVal !== undefined && typeof apiUrlVal === 'string') {
      this.apiUrl = apiUrlVal as string;
    }
    const pagesVal: Object | undefined = args.get('pages');
    if (pagesVal !== undefined && typeof pagesVal === 'number' && (pagesVal as number) > 0) {
      this.totalGalleryPages = Math.trunc(pagesVal as number);
    }
    const initialPsVal: Object | undefined = args.get('initialPreviewSet');
    if (initialPsVal !== undefined && initialPsVal !== null && initialPsVal instanceof PreviewSet) {
      this.initialPreviewSet = initialPsVal as PreviewSet;
    }
  }

  private async loadPreviewPage(pageIndex: number): Promise<void> {
    const safePage: number = pageIndex >= 0 ? Math.trunc(pageIndex) : 0;
    if (this.gid <= 0 || this.token.length === 0) {
      this.errorMessage = 'Missing gallery gid or token';
      return;
    }
    const seq: number = ++this.requestSeq;
    this.loading = true;
    this.errorMessage = '';
    try {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      const caller: HttpCaller = new OkHttpCallerAdapter(
        EhApplication.getOkHttpClient(ctx === undefined ? null : ctx)
      );
      const url: string = EhUrl.getGalleryDetailUrl(this.gid, this.token, safePage, false);
      const result: PreviewSetResult = await EhEngine.getPreviewSet(null, caller, url);
      if (this.destroyed || seq !== this.requestSeq) {
        return;
      }
      this.currentPage = safePage;
      if (result.previewPages > 0) {
        this.previewPages = result.previewPages;
      }
      const ps: PreviewSet | null = result.previewSet;
      this.currentPreviewSet = ps;
      const tiles: FullPreviewTileItem[] = [];
      if (ps !== null) {
        for (let i = 0; i < ps.size(); i++) {
          tiles.push(new FullPreviewTileItem(i, ps.getPosition(i)));
        }
      }
      this.previewTiles = tiles;
      this.loadEpoch = this.loadEpoch + 1;
      this.loading = false;
    } catch (e) {
      if (this.destroyed || seq !== this.requestSeq) {
        return;
      }
      this.loading = false;
      this.errorMessage = e instanceof Error && e.message.length > 0 ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'loadPreviewPage failed: page=%{public}d err=%{public}s',
        safePage, this.errorMessage);
    }
  }

  private openReaderAt(pagePosition: number): void {
    const safePage: number = pagePosition >= 0 ? pagePosition : 0;
    const params: GalleryReaderRouteParams = new GalleryReaderRouteParams(
      this.gid,
      this.token,
      safePage,
      this.totalGalleryPages,
      this.title,
      this.apiUrl
    );
    pushGalleryReaderPage(this.getUIContext(), params, TAG);
  }

  @Builder
  materialToolbar() {
    Row() {
      Row() {
        VArrowLeftDarkX24({
          iconSize: ThemeDimens.ICON_SIZE_STANDARD,
          fillColor: this.palette().toolbarIconColor
        })
      }
      .width(ThemeDimens.TOUCH_TARGET_MIN)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        if (this.shell !== null) {
          this.shell.finish();
        }
      })

      Text(this.title.length > 0 ? this.title : $r('app.string.gallery_previews'))
        .fontSize(ThemeTypography.TOOLBAR_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().toolbarTitleColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: ThemeDimens.SPACING })
        .layoutWeight(1)

      if (this.previewPages > 1) {
        Row() {
          VGoToDarkX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.palette().toolbarIconColor
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.goToValue = this.currentPage + 1;
          this.showGoToDialog = true;
        })
      }

      Row() {
        VRefreshDarkX24({
          iconSize: ThemeDimens.ICON_SIZE_STANDARD,
          fillColor: this.palette().toolbarIconColor
        })
      }
      .width(ThemeDimens.TOUCH_TARGET_MIN)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        void this.loadPreviewPage(this.currentPage);
      })
    }
    .width('100%')
    .height(ThemeDimens.TOOLBAR_HEIGHT)
    .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
    .backgroundColor(this.palette().toolbarColor)
    .shadow(ThemeElevation.toolbar())
    .alignItems(VerticalAlign.Center)
    .zIndex(2)
  }

  @Builder
  paginationBar() {
    Column() {
      Row({ space: 12 }) {
        Button($r('app.string.spen_previous_page'), { type: ButtonType.Normal })
          .borderRadius(ThemeRadius.BUTTON)
          .height(36)
          .fontSize(ThemeTypography.BUTTON)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.currentPage > 0 && !this.loading
            ? this.palette().textThemeAccent
            : this.palette().textDisabled)
          .enabled(this.currentPage > 0 && !this.loading)
          .onClick((): void => {
            if (this.currentPage > 0) {
              void this.loadPreviewPage(this.currentPage - 1);
            }
          })

        Text(String(this.currentPage + 1) + ' / ' + String(Math.max(1, this.previewPages)))
          .fontColor(this.palette().textPrimary)
          .layoutWeight(1)
          .constraintSize({ minHeight: 36 })
          .textAlign(TextAlign.Center)
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontWeight(FontWeight.Medium)
          .onClick((): void => {
            this.goToValue = this.currentPage + 1;
            this.showGoToDialog = true;
          })

        Button($r('app.string.spen_next_page'), { type: ButtonType.Normal })
          .borderRadius(ThemeRadius.BUTTON)
          .height(36)
          .fontSize(ThemeTypography.BUTTON)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.palette().transparent)
          .fontColor(this.currentPage + 1 < this.previewPages && !this.loading
            ? this.palette().textThemeAccent
            : this.palette().textDisabled)
          .enabled(this.currentPage + 1 < this.previewPages && !this.loading)
          .onClick((): void => {
            if (this.currentPage + 1 < this.previewPages) {
              void this.loadPreviewPage(this.currentPage + 1);
            }
          })
      }
      .width('100%')
      .padding({ left: ThemeDimens.SPACING, right: ThemeDimens.SPACING, top: 4, bottom: 4 })
      .backgroundColor(this.palette().surfaceBackground)

      Divider()
        .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
        .color(this.palette().divider)
    }
    .width('100%')
  }

  @Builder
  goToDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.showGoToDialog = false;
        })

      Column() {
        Text($r('app.string.go_to'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Row({ space: 8 }) {
          Text('1')
            .width(32)
            .textAlign(TextAlign.Center)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textSecondary)

          Slider({
            value: this.goToValue,
            min: 1,
            max: Math.max(1, this.previewPages),
            step: 1
          })
            .layoutWeight(1)
            .selectedColor(this.palette().colorAccent)
            .trackColor(this.palette().divider)
            .blockColor(this.palette().colorAccent)
            .onChange((val: number): void => {
              this.goToValue = Math.max(1, Math.min(Math.max(1, this.previewPages), Math.round(val)));
            })

          Text(String(Math.max(1, this.previewPages)))
            .width(32)
            .textAlign(TextAlign.Center)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textSecondary)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
        .alignItems(VerticalAlign.Center)

        Text(String(this.goToValue) + ' / ' + String(Math.max(1, this.previewPages)))
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.palette().textPrimary)
          .margin({ top: 4, bottom: 8 })

        Row({ space: 8 }) {
          Button($r('app.string.cancel'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().textThemeAccent)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showGoToDialog = false;
            })

          Button($r('app.string.ok'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().textThemeAccent)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              const targetPage: number = Math.max(0, Math.min(this.previewPages - 1, this.goToValue - 1));
              this.showGoToDialog = false;
              void this.loadPreviewPage(targetPage);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 380 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
    }
    .width('100%')
    .height('100%')
    .zIndex(10)
  }

  build() {
    Stack() {
      Column() {
        this.materialToolbar()
        if (this.previewPages > 1) {
          this.paginationBar()
        }

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.palette().progressColor)
            Text($r('app.string.loading'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor(this.palette().textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.errorMessage.length > 0) {
          Column({ space: 12 }) {
            BigSadPandroid({
              iconSize: 120,
              fillColor: this.palette().drawableSecondary
            })
            Text($r('app.string.load_failed'))
              .fontSize(ThemeTypography.CARD_TITLE)
              .fontColor(this.palette().errorColor)
              .fontWeight(FontWeight.Bold)
            Text(this.errorMessage)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().errorColor)
              .textAlign(TextAlign.Center)
            Button($r('app.string.retry'), { type: ButtonType.Normal })
              .borderRadius(ThemeRadius.BUTTON)
              .constraintSize({ minWidth: 88, minHeight: 36 })
              .backgroundColor(this.palette().colorPrimary)
              .fontColor(this.palette().white)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .onClick((): void => {
                void this.loadPreviewPage(this.currentPage);
              })
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.previewTiles.length === 0) {
          Column({ space: 12 }) {
            BigSadPandroid({
              iconSize: 120,
              fillColor: this.palette().drawableSecondary
            })
            Text($r('app.string.no_previews'))
              .fontSize(ThemeTypography.TEXT_MEDIUM)
              .fontColor(this.palette().textSecondary)
            Button($r('app.string.retry'), { type: ButtonType.Normal })
              .borderRadius(ThemeRadius.BUTTON)
              .constraintSize({ minWidth: 88, minHeight: 36 })
              .backgroundColor(this.palette().colorPrimary)
              .fontColor(this.palette().white)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .onClick((): void => {
                void this.loadPreviewPage(this.currentPage);
              })
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Grid() {
            ForEach(this.previewTiles, (tile: FullPreviewTileItem) => {
              GridItem() {
                PreviewTileView({
                  gid: this.gid,
                  index: tile.index,
                  pageLabel: tile.pageLabel,
                  tileHeight: 136,
                  themeId: this.themeId,
                  loadEpoch: this.loadEpoch,
                  previewSet: this.currentPreviewSet,
                  onTileClick: (): void => {
                    this.openReaderAt(tile.position);
                  }
                })
              }
            }, (tile: FullPreviewTileItem) => 'full_' + String(this.loadEpoch) + '_' + String(tile.index))
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(ThemeDimens.SPACING_XS)
          .rowsGap(ThemeDimens.SPACING_XS)
          .padding(ThemeDimens.SPACING_XS)
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')

      if (this.showGoToDialog) {
        this.goToDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
