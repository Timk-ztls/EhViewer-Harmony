/*
 * EhTopListSceneView: Material Design UI aligned with scene_gallery_top_list.xml,
 * gallery_top_list_item.xml, EhTopListScene.kt & EhTopListAdapter.java.
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
import { TopListInfo, TopListItem, TopListItemArray, TopListType } from '../../ehviewer/client/data/TopList';
import {
  EhTopListScene,
  MODE_NORMAL,
  MODE_UPLOADER,
  STATE_FAILED,
  STATE_INIT,
  STATE_REFRESH,
  VIEW_DATA
} from '../../ehviewer/ui/scene/topList/EhTopListScene';
import { EhTopListSceneShell } from '../../ehviewer/ui/scene/topList/EhTopListSceneShell';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { MainPageHost } from '../MainPageHost';

const DOMAIN: number = 0x0000;
const TAG: string = 'EhTopListSceneView';
const PD_DROPDOWN_TRIANGLE: string = 'M7,10L12,15L17,10Z';

class KindTab {
  index: number = 0;
  labelRes: Resource;

  constructor(index: number, labelRes: Resource) {
    this.index = index;
    this.labelRes = labelRes;
  }
}

class TimeframeTab {
  slotIndex: number = 0;
  labelRes: Resource;

  constructor(slotIndex: number, labelRes: Resource) {
    this.slotIndex = slotIndex;
    this.labelRes = labelRes;
  }
}

@Component
export struct EhTopListSceneView {
  shell: EhTopListSceneShell | null = null;
  host: MainPageHost | null = null;
  @Prop themeId: number = -1;
  onOpenDrawer: () => void = (): void => {
  };

  @State selectedKind: number = 0;
  // TopListInfo.get(0..3): 0=yesterday, 1=pastMonth, 2=pastYear, 3=allTime
  @State selectedTimeframe: number = 0;
  @State loading: boolean = false;
  @State failed: boolean = false;
  @State errorText: string = '';
  @State rows: TopListItem[] = [];
  @State activeType: number = TopListType.GALLERY;
  @State kindDialogOpen: boolean = false;

  private readonly kindRadioGroup: string = 'top_list_kind_group';

  private readonly kindTabs: KindTab[] = [
    new KindTab(0, $r('app.string.gallery_toplists')),
    new KindTab(1, $r('app.string.uploader_toplists')),
    new KindTab(2, $r('app.string.tagging_toplists')),
    new KindTab(3, $r('app.string.hentai_home_toplists')),
    new KindTab(4, $r('app.string.ehtracker_toplists')),
    new KindTab(5, $r('app.string.cleanup_toplists')),
    new KindTab(6, $r('app.string.rating_reviewing_toplists'))
  ];

  private readonly timeframeTabs: TimeframeTab[] = [
    new TimeframeTab(0, $r('app.string.yesterday_top_list')),
    new TimeframeTab(1, $r('app.string.past_month_top_list')),
    new TimeframeTab(2, $r('app.string.past_year_top_list')),
    new TimeframeTab(3, $r('app.string.all_time_top_list'))
  ];

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    void this.loadTopLists();
  }

  private async loadTopLists(): Promise<void> {
    const sh: EhTopListSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const logic: EhTopListScene = sh.getLogic();
    this.loading = true;
    this.failed = false;
    try {
      const viewIdx: number = await logic.onCreateView();
      this.syncFromLogic(logic);
      if (viewIdx !== VIEW_DATA && logic.getState() === STATE_FAILED) {
        this.failed = true;
      }
    } catch (err) {
      const e: Error = err as Error;
      this.failed = true;
      this.errorText = e.message;
      hilog.error(DOMAIN, TAG, 'loadTopLists failed: %{public}s', e.message);
    }
  }

  private syncFromLogic(logic: EhTopListScene): void {
    const st: number = logic.getState();
    this.loading = st === STATE_INIT || st === STATE_REFRESH;
    this.failed = st === STATE_FAILED;
    const err: Error | null = logic.getLastError();
    this.errorText = err !== null && err.message !== undefined ? err.message : '';
    this.selectedKind = logic.getPosition();
    const info: TopListInfo | null = logic.getCurrentInfo();
    if (info === null) {
      this.rows = [];
      return;
    }
    this.activeType = info.type;
    const arr: TopListItemArray | null = info.get(this.selectedTimeframe);
    this.rows = arr !== null ? arr.itemArray.slice() : [];
  }

  private selectedKindLabelRes(): Resource {
    if (this.selectedKind >= 0 && this.selectedKind < this.kindTabs.length) {
      return this.kindTabs[this.selectedKind].labelRes;
    }
    return this.kindTabs[0].labelRes;
  }

  private rankColorNum(position: number, palette: ThemePalette): number {
    const sh: EhTopListSceneShell | null = this.shell;
    if (sh === null) {
      return parseInt(palette.colorPrimary.substring(1), 16) >>> 0;
    }
    return sh.getLogic().getRandomColor(position) >>> 0;
  }

  private rankColorHex(position: number, palette: ThemePalette): string {
    const unsigned: number = this.rankColorNum(position, palette);
    return `#${unsigned.toString(16).padStart(8, '0').toUpperCase()}`;
  }

  private rankBadgeTextColor(position: number, palette: ThemePalette): string {
    const badgeColor: number = this.rankColorNum(position, palette);
    const a: number = ((badgeColor >>> 24) & 0xFF) / 255.0;
    const r: number = (badgeColor >>> 16) & 0xFF;
    const g: number = (badgeColor >>> 8) & 0xFF;
    const b: number = badgeColor & 0xFF;
    const surfaceNum: number = parseInt(palette.cardWhiteSurface.substring(1), 16) >>> 0;
    const sr: number = (surfaceNum >>> 16) & 0xFF;
    const sg: number = (surfaceNum >>> 8) & 0xFF;
    const sb: number = surfaceNum & 0xFF;
    const effR: number = r * a + sr * (1 - a);
    const effG: number = g * a + sg * (1 - a);
    const effB: number = b * a + sb * (1 - a);
    const luminance: number = 0.2126 * effR + 0.7152 * effG + 0.0722 * effB;
    return luminance >= 140 ? ThemeTokens.LIGHT.textPrimary : ThemeTokens.LIGHT.white;
  }

  private handleItemClick(item: TopListItem): void {
    const sh: EhTopListSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const searchType: number = this.activeType === TopListType.UPLOADER ? MODE_UPLOADER : MODE_NORMAL;
    sh.getLogic().onItemClick(item, searchType);
  }

  @Builder
  private hamburgerIcon(): void {
    Column({ space: 4 }) {
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
      Row().width(18).height(2).backgroundColor(this.palette().toolbarIconColor)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private kindDialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.kindDialogOpen = false;
        })

      Column() {
        Text($r('app.string.top_list'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Scroll() {
          Column() {
            ForEach(this.kindTabs, (tab: KindTab) => {
              Row({ space: ThemeDimens.SPACING_MD }) {
                Radio({ value: String(tab.index), group: this.kindRadioGroup })
                  .checked(this.selectedKind === tab.index)
                  .radioStyle({ checkedBackgroundColor: this.palette().controlActivated })
                  .hitTestBehavior(HitTestMode.None)

                Text(tab.labelRes)
                  .fontSize(ThemeTypography.PREF_TITLE)
                  .fontColor(this.palette().textPrimary)
                  .layoutWeight(1)
              }
              .width('100%')
              .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
              .padding({ left: 20, right: ThemeDimens.DIALOG_PADDING_H, top: 8, bottom: 8 })
              .onClick((): void => {
                const sh: EhTopListSceneShell | null = this.shell;
                if (sh !== null) {
                  const logic: EhTopListScene = sh.getLogic();
                  logic.onKindSelected(tab.index);
                  this.syncFromLogic(logic);
                } else {
                  this.selectedKind = tab.index;
                }
                this.kindDialogOpen = false;
              })
            }, (tab: KindTab) => String(tab.index))
          }
          .width('100%')
        }
        .align(Alignment.TopStart)
        .constraintSize({ maxHeight: 360 })
        .width('100%')

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
          .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            this.kindDialogOpen = false;
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
      .onClick((): void => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildContent(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 56vp Material Toolbar
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            this.hamburgerIcon()
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick((): void => {
            this.onOpenDrawer();
          })

          Text($r('app.string.top_lists'))
            .fontSize(ThemeTypography.TOOLBAR_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().toolbarTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: ThemeDimens.SPACING })

          Stack({ alignContent: Alignment.Center }) {
            VRefreshDarkX24({
              iconSize: ThemeDimens.ICON_SIZE_STANDARD,
              fillColor: this.palette().toolbarIconColor
            })
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick((): void => {
            void this.loadTopLists();
          })
        }
        .width('100%')
        .height(ThemeDimens.TOOLBAR_HEIGHT)
        .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
        .backgroundColor(this.palette().toolbarColor)
        .shadow(ThemeElevation.toolbar())

        // 50vp Material Spinner Card (top_list_spinner)
        Row() {
          Text(this.selectedKindLabelRes())
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().toolbarTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .layoutWeight(1)

          Shape() {
            Path()
              .commands(PD_DROPDOWN_TRIANGLE)
              .fill(this.palette().toolbarIconColor)
              .stroke(Color.Transparent)
              .strokeWidth(0)
          }
          .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
          .width(ThemeDimens.ICON_SIZE_STANDARD)
          .height(ThemeDimens.ICON_SIZE_STANDARD)
          .antiAlias(true)
        }
        .height($r('app.float.top_list_spinner_height'))
        .margin({ left: 12, right: 12, top: 12, bottom: 8 })
        .padding({ left: 24, right: 12 })
        .backgroundColor(this.palette().toolbarColor)
        .borderRadius(ThemeRadius.CARD)
        .shadow(ThemeElevation.card())
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.kindDialogOpen = true;
        })

        // Flat 48vp Material 4-tab timeframe bar
        Column() {
          Row() {
            ForEach(this.timeframeTabs, (tf: TimeframeTab) => {
              Column() {
                Column() {
                  Text(tf.labelRes)
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontWeight(this.selectedTimeframe === tf.slotIndex ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.selectedTimeframe === tf.slotIndex ? this.palette().textPrimary : this.palette().textSecondary)
                    .maxLines(2)
                    .textAlign(TextAlign.Center)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .layoutWeight(1)
                .padding({ left: 4, right: 4 })
                .justifyContent(FlexAlign.Center)

                Row()
                  .width('100%')
                  .height(2)
                  .backgroundColor(this.selectedTimeframe === tf.slotIndex ? this.palette().colorAccent : Color.Transparent)
              }
              .layoutWeight(1)
              .height('100%')
              .onClick((): void => {
                this.selectedTimeframe = tf.slotIndex;
                if (this.shell !== null) {
                  this.syncFromLogic(this.shell.getLogic());
                }
              })
            }, (tf: TimeframeTab) => String(tf.slotIndex))
          }
          .width('100%')
          .height(ThemeDimens.PREF_ROW_MIN_HEIGHT)
          .backgroundColor(this.palette().surfaceBackground)

          Divider()
            .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
            .color(this.palette().divider)
            .width('100%')
        }
        .width('100%')

        if (this.loading && this.rows.length === 0) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(ThemeDimens.ICON_SIZE_LARGE)
              .height(ThemeDimens.ICON_SIZE_LARGE)
              .color(this.palette().progressColor)
            Text($r('app.string.loading'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor(this.palette().textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.failed && this.rows.length === 0) {
          Column({ space: 12 }) {
            Text($r('app.string.load_failed'))
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().errorColor)
            if (this.errorText.length > 0) {
              Text(this.errorText)
                .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
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
            .height(ThemeDimens.DIALOG_ACTION_MIN_HEIGHT)
            .padding({ left: 16, right: 16 })
            .borderRadius(ThemeRadius.BUTTON)
            .backgroundColor(this.palette().colorPrimary)
            .onClick((): void => {
              void this.loadTopLists();
            })
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
        } else if (this.rows.length === 0) {
          Column() {
            Text($r('app.string.empty_result'))
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontColor(this.palette().textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 7 }) {
            ForEach(this.rows, (item: TopListItem, idx: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  Column() {
                    Text(`#${idx + 1}`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.rankBadgeTextColor(idx, this.palette()))
                  }
                  .width(36)
                  .height(36)
                  .borderRadius(18)
                  .backgroundColor(this.rankColorHex(idx, this.palette()))
                  .justifyContent(FlexAlign.Center)

                  Column({ space: 2 }) {
                    Text(item.value)
                      .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.palette().textPrimary)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (item.tag.length > 0) {
                      Text(item.tag)
                        .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                        .fontColor(this.palette().textSecondary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor(this.palette().cardWhiteSurface)
                .borderRadius($r('app.float.top_list_item_radius'))
                .border({ width: 1, color: this.palette().divider })
                .onClick((): void => {
                  this.handleItemClick(item);
                })
              }
            }, (item: TopListItem, idx: number) => `${idx}_${item.gid}_${item.value}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        }
      }
      .width('100%')
      .height('100%')

      if (this.kindDialogOpen) {
        this.kindDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }

  build() {
    this.buildContent();
  }
}
