/*
 * 上游：app/src/main/res/layout/item_download.xml（inventory S0608，上游 146 行 —— 本模块最大布局）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_download.ets
 *
 * 背景：下载列表项，含**多状态**（等待/下载中/暂停/失败/完成）+ 多角标（阅读进度、百分比、速度、
 * 状态文案、开始/暂停按钮）。上游靠在 DownloadItem 里 `findViewById(...).setVisibility()` 切换，
 * 布局本身把所有控件都摆好；鸿蒙侧同样"全摆好 + @Prop 控制可见性"，不做条件渲染删除节点
 * （删除/插入会改变 RelativeContainer 的锚点存在性，导致其余控件跳位）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                     ArkUI
 * CardView(style=CardView.Reactive, m=2dp)      Column + margin(2) + cardColor + radius（同 item_gallery_list）
 *   LinearLayout(horizontal)                    （单子元素，省略一层：见「无法等价」1）
 *     RelativeLayout                            RelativeContainer
 *       FixedThumb#thumb 80x120                 @BuilderParam thumbBuilder（ui-widget 未交付）+ 80x120 容器
 *         retryType=longClick / minAspect=0.333 / maxAspect=1.333
 *       TextView#title（CardTitle）              Text：text_medium + 2 行省略
 *         marginLeft/Right=8, marginTop=4          .margin({left:8,right:8,top:4})
 *         layout_toRightOf=thumb                    left: {anchor:'thumb', align: End}
 *       TextView#uploader（CardMessage）          Text：text_small + 1 行省略
 *         alignLeft=title / below=title             left→title.Start, top→title.Bottom, marginTop 2
 *       SimpleRatingView#rating                  @BuilderParam ratingBuilder
 *         alignLeft=title / below=uploader          left→title.Start, top→uploader.Bottom, marginTop 2
 *       TextView#category（CardMessage, 白字）    Text：text_small + 白 + allCaps(数据侧)
 *         alignLeft=title / alignBottom=thumb       left→title.Start, bottom→thumb.Bottom
 *         marginBottom=8 / padding 8/2              .margin({bottom:8}) + .padding({l:8,r:8,t:2,b:2})
 *       TextView#read_progress（ReadProgress）     Text：text_small + textColorPrimary + 1 行省略
 *         toRightOf=category / alignBottom=thumb     left→category.End, bottom→thumb.Bottom
 *       FrameLayout#actions（右对齐贴 thumb 底）   @BuilderParam actionsBuilder（见 2）
 *         ImageView#start 40x40 padding8 v_play_x24
 *         ImageView#stop  40x40 padding8 v_pause_x24
 *       TextView#state（贴 actions 上, 右对齐）      Text：textColorThemeAccent
 *         above=actions / marginBottom=4             right→容器.End, bottom→actions.Top
 *         paddingRight=16                            .padding({right:16}).margin({bottom:4})
 *       ProgressBar#progress_bar（Horizontal）      Progress(Linear)：左贴 title、右贴容器、在 actions 之上
 *         alignLeft=title / above=actions / indeterminate=false
 *       TextView#percent（text_super_small）        Text：text_super_small
 *         above=progress_bar / alignLeft=title       left→title.Start, bottom→progress_bar.Top
 *       TextView#speed（text_super_small）          Text：text_super_small
 *         above=progress_bar / 右对齐 / marginRight=8  right→容器.End, bottom→progress_bar.Top
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游 CardView > LinearLayout(horizontal) > RelativeLayout 三层包装里，**中间那层 LinearLayout
 *    是多余的**（单一子元素、无 orientation/gravity/weight），只为 CardView 的嵌套要求存在。
 *    ArkUI 省略它：Column 直接包 RelativeContainer，盒模型等价（CardView 的 margin 2 / padding 0 保留）。
 * 2. `FrameLayout#actions` 里 start/stop 两个 40x40 ImageView **叠放**，由可见性切换
 *    （同一位置显示"开始"或"暂停"）。ArkUI 用 Stack 保留叠放 + 两个 @BuilderParam 槽位，
 *    不写成 Row —— 写成 Row 会变成两个按钮并排（这是本文件与 widget_content_layout 同类的结构陷阱）。
 * 3. `?attr/textColorThemeAccent`（#state 用）无 ArkUI attr → @Prop stateColor 注入，
 *    默认 '#FF6200EE'（Material 强调色）。
 * 4. `?android:attr/progressBarStyleHorizontal` + `indeterminate=false` → ArkUI
 *    `Progress({value,total,type:Linear})`；上游高度 wrap_content（≈4dp）→ 取 4vp。
 * 5. `style="@style/ReadProgress"` = text_small(14fp) + textColorPrimary + singleLine + ellipsize end
 *    → 已按此落（`maxLines(1)` + Ellipsis）。
 * 6. 未交付控件（FixedThumb / SimpleRatingView）按铁律用 @BuilderParam + TODO(ui-widget)，
    不作假实现；`app:retryType="longClick"`、`minAspect/maxAspect` 属 FixedThumb 内部行为，
 *    布局层不复刻（与 item_gallery_list / item_gallery_preview 同一处理）。
 * 7. 状态机语义（哪个状态显示 start 还是 stop、state 文案内容、percent/speed 何时隐藏）
 *    属业务层：本组件只暴露 `showStart/showStop/showState/showProgress/showPercent/showSpeed` 六个开关，
 *    由 DownloadItem 等价层按上游 DownloadTask 的状态映射。
 */

import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { FixedThumb } from '../../ehviewer/widget/FixedThumb';
import { SimpleRatingView } from '../../ehviewer/widget/SimpleRatingView';
import { LoadImageController } from '../../widget/LoadImageView';
import { VPlayX24 } from '../drawable/v_play_x24';
import { VPauseX24 } from '../drawable/v_pause_x24';
import { VCloseDarkX24 } from '../drawable/v_close_dark_x24';
import { VCheckDarkX24 } from '../drawable/v_check_dark_x24';

@Component
export struct DownloadItemLayout {
  // ---- 数据（对应 XML 的 R.id.*） ----
  @Prop title: string = '';
  @Prop uploader: string = '';
  @Prop category: string = '';
  @Prop readProgress: string = '';
  @Prop state: string = '';
  @Prop percent: string = '';
  @Prop speed: string = '';
  @Prop progressValue: number = 0;
  @Prop progressTotal: number = 100;
  @Prop rating: number = -1;
  @Prop @Watch('onThumbChanged') thumbUrl: string = '';
  @Prop @Watch('onThumbChanged') thumbKey: string = '';

  // ---- 多状态可见性（下载项的核心：全摆好 + 切换可见性） ----
  @Prop showStart: boolean = false;
  @Prop showStop: boolean = false;
  @Prop showState: boolean = false;
  @Prop showProgress: boolean = false;
  @Prop showPercent: boolean = false;
  @Prop showSpeed: boolean = false;
  @Prop showCancel: boolean = false;
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;

  // ---- 主题注入位（上游 ?attr / CardView.Reactive） ----
  @Prop themeId: number = -1;
  @Prop cardColor: ResourceColor = '';
  @Prop titleColor: ResourceColor = '';
  @Prop messageColor: ResourceColor = '';
  @Prop accentTextColor: ResourceColor = '';
  @Prop categoryBgColor: ResourceColor = '#FF607D8B';
  @Prop categoryTextColor: ResourceColor = Color.White;
  @Prop progressColor: ResourceColor = '';

  onThumbClick: () => void = (): void => {
  };
  onStartClick: () => void = (): void => {
  };
  onStopClick: () => void = (): void => {
  };
  onCancelClick: () => void = (): void => {
  };

  private thumbController: LoadImageController = new LoadImageController();
  private lastLoadedThumbKey: string = '';
  private lastLoadedThumbUrl: string = '';

  aboutToAppear(): void {
    this.thumbController.setRetryType(LoadImageController.RETRY_TYPE_CLICK);
    this.loadThumb();
  }

  private onThumbChanged(): void {
    this.loadThumb();
  }

  private loadThumb(): void {
    if (this.thumbUrl.length > 0) {
      const key: string = this.thumbKey.length > 0 ? this.thumbKey : this.thumbUrl;
      if (this.lastLoadedThumbKey === key && this.lastLoadedThumbUrl === this.thumbUrl) {
        return;
      }
      this.lastLoadedThumbKey = key;
      this.lastLoadedThumbUrl = this.thumbUrl;
      this.thumbController.resetClip();
      this.thumbController.load(key, this.thumbUrl);
    } else {
      if (this.lastLoadedThumbKey.length === 0 && this.lastLoadedThumbUrl.length === 0) {
        return;
      }
      this.lastLoadedThumbKey = '';
      this.lastLoadedThumbUrl = '';
      this.thumbController.unload();
    }
  }

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private effectiveCardColor(): ResourceColor {
    if (this.selected) {
      return this.palette().cardActivatedBackground;
    }
    return this.cardColor !== '' ? this.cardColor : this.palette().cardBackground;
  }

  private effectiveTitleColor(): ResourceColor {
    return this.titleColor !== '' ? this.titleColor : this.palette().textPrimary;
  }

  private effectiveMessageColor(): ResourceColor {
    return this.messageColor !== '' ? this.messageColor : this.palette().textSecondary;
  }

  private effectiveAccentColor(): ResourceColor {
    return this.accentTextColor !== '' ? this.accentTextColor : this.palette().textThemeAccent;
  }

  private effectiveProgressColor(): ResourceColor {
    return this.progressColor !== '' ? this.progressColor : this.palette().progressColor;
  }

  // ---- 控件槽位 ----
  @BuilderParam thumbBuilder: () => void = this.defaultThumb;
  @BuilderParam ratingBuilder: () => void = this.emptyRating;

  @Builder
  defaultThumb() {
    if (this.thumbUrl.length > 0) {
      FixedThumb({
        controller: this.thumbController,
        minAspect: 0.333,
        maxAspect: 1.333
      })
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().thumbPlaceholder)
    }
  }

  @Builder
  emptyRating() {
    if (this.rating >= 0) {
      SimpleRatingView({
        rating: this.rating,
        ratingSize: 16,
        ratingInterval: 1
      })
    } else {
      Row().width(0).height(0)
    }
  }

  build() {
    Row() {
      // thumb（80x120，左侧，多选态叠加选择角标）
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          this.thumbBuilder();
        }
        .width('100%')
        .height('100%')

        if (this.selectionMode || this.selected) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.selected) {
              VCheckDarkX24({
                iconSize: 14,
                fillColor: Color.White
              })
            }
          }
          .width(22)
          .height(22)
          .margin({ left: 4, top: 4 })
          .borderRadius(11)
          .backgroundColor(this.selected ? this.palette().colorAccent : '#66000000')
          .border({
            width: this.selected ? 0 : 1.5,
            color: this.selected ? Color.Transparent : '#B3FFFFFF'
          })
        }
      }
      .width(ThemeDimens.GALLERY_LIST_THUMB_WIDTH)
      .height(ThemeDimens.GALLERY_LIST_THUMB_HEIGHT)
      .onClick(() => {
        this.onThumbClick();
      })

      // 右侧信息区
      Column() {
        Column() {
          Text(this.title)
            .fontSize(ThemeTypography.CARD_TITLE)
            .fontColor(this.effectiveTitleColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.uploader.length > 0) {
            Text(this.uploader)
              .fontSize(ThemeTypography.CARD_MESSAGE)
              .fontColor(this.effectiveMessageColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
              .width('100%')
          }

          Column() {
            this.ratingBuilder();
          }
          .margin({ top: 2 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: ThemeDimens.SPACING, right: ThemeDimens.SPACING, top: ThemeDimens.SPACING_XS })
        .alignItems(HorizontalAlign.Start)

        Column() {
          if (this.showPercent || this.showSpeed) {
            Row() {
              if (this.showPercent && this.percent.length > 0) {
                Text(this.percent)
                  .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                  .fontColor(this.effectiveMessageColor())
                  .maxLines(1)
              }
              Blank()
              if (this.showSpeed && this.speed.length > 0) {
                Text(this.speed)
                  .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                  .fontColor(this.effectiveMessageColor())
                  .maxLines(1)
              }
            }
            .width('100%')
            .margin({ bottom: 2 })
          }

          if (this.showProgress) {
            Progress({
              value: this.progressValue,
              total: this.progressTotal > 0 ? this.progressTotal : 100,
              type: ProgressType.Linear
            })
              .width('100%')
              .height(4)
              .color(this.effectiveProgressColor())
              .backgroundColor(this.palette().divider)
              .margin({ bottom: 4 })
          }

          Row() {
            if (this.category.length > 0) {
              Text(this.category)
                .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                .fontColor(this.categoryTextColor)
                .textCase(TextCase.UpperCase)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor(this.categoryBgColor)
                .borderRadius(ThemeRadius.CATEGORY_BADGE)
                .margin({ bottom: 4 })
            }

            if (this.readProgress.length > 0) {
              Text(this.readProgress)
                .fontSize(ThemeTypography.CARD_MESSAGE)
                .fontColor(this.effectiveTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 8, right: 4, top: 2, bottom: 2 })
                .margin({ bottom: 4 })
            }

            Blank()

            if (this.showState && this.state.length > 0) {
              Text(this.state)
                .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                .fontColor(this.effectiveAccentColor())
                .maxLines(1)
                .margin({ right: 4, bottom: 6 })
            }

            if (this.showStart || this.showStop) {
              Stack({ alignContent: Alignment.Center }) {
                if (this.showStart) {
                  Stack({ alignContent: Alignment.Center }) {
                    VPlayX24({
                      iconSize: this.showCancel ? 20 : ThemeDimens.ICON_SIZE_STANDARD,
                      fillColor: this.palette().drawablePrimary
                    })
                  }
                  .width(this.showCancel ? 32 : 40)
                  .height(this.showCancel ? 32 : 40)
                  .padding(this.showCancel ? 6 : 8)
                  .onClick(() => {
                    this.onStartClick();
                  })
                } else if (this.showStop) {
                  Stack({ alignContent: Alignment.Center }) {
                    VPauseX24({
                      iconSize: this.showCancel ? 20 : ThemeDimens.ICON_SIZE_STANDARD,
                      fillColor: this.palette().drawablePrimary
                    })
                  }
                  .width(this.showCancel ? 32 : 40)
                  .height(this.showCancel ? 32 : 40)
                  .padding(this.showCancel ? 6 : 8)
                  .onClick(() => {
                    this.onStopClick();
                  })
                }
              }
            }

            if (this.showCancel) {
              Stack({ alignContent: Alignment.Center }) {
                VCloseDarkX24({
                  iconSize: 18,
                  fillColor: this.palette().drawablePrimary
                })
              }
              .width(32)
              .height(32)
              .padding(6)
              .margin({ left: 2 })
              .stateStyles({
                pressed: {
                  .backgroundColor('#1F000000')
                },
                normal: {
                  .backgroundColor(Color.Transparent)
                }
              })
              .onClick(() => {
                this.onCancelClick();
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .width('100%')
        .padding({ left: ThemeDimens.SPACING, right: ThemeDimens.SPACING, bottom: ThemeDimens.SPACING_XS })
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: ThemeDimens.GALLERY_LIST_THUMB_HEIGHT })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin(2)
    .backgroundColor(this.effectiveCardColor())
    .borderRadius(ThemeRadius.CARD)
    .border({
      width: this.selected ? 2 : 0,
      color: this.selected ? this.palette().colorAccent : Color.Transparent
    })
    .shadow(ThemeElevation.card())
    .clip(true)
    .alignItems(VerticalAlign.Top)
  }
}
