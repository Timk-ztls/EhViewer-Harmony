/**
 * Material NavDrawerPanel aligned with Android activity_main.xml, nav_header_main.xml,
 * nav_drawer_main.xml, EhNavigationView.java & MainActivity.java.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeTokens,
  ThemeTypography,
} from '../../common/theme/ThemeTokens';
import { PathData } from '../drawable/PathData';
import { EhUrl } from '../ehviewer/client/EhUrl';
import { Settings } from '../ehviewer/Settings';
import { GalleryListAction } from '../ehviewer/ui/scene/gallery/list/GalleryListScene';
import { LimitsCountState, LimitsCountView, LimitsProvider } from '../ehviewer/widget/LimitsCountView';
import { DefaultAvatar } from './drawable/default_avatar';
import { MainPageHost } from './MainPageHost';
import { PageRoutes } from './PageRoutes';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'NavDrawerPanel';

@Component
export struct NavDrawerPanel {
  @Prop activeScene: string = '';
  @Prop activeListAction: string = '';
  @Prop themeId: number = ThemeMode.LIGHT;
  @Prop displayNameOverride: string = '';
  limitsProvider: LimitsProvider | null = null;
  onSelectList: (action: string, url: string) => void = (_action: string, _url: string): void => {
  };
  onSelectScene: (sceneName: string) => void = (_sceneName: string): void => {
  };
  onOpenPage: (url: string) => void = (_url: string): void => {
  };
  onToggleTheme: () => void = (): void => {
  };
  @Prop @Watch('onDragPropChanged') interactiveDragging: boolean = false;
  @Prop @Watch('onDragPropChanged') interactiveProgress: number = 1;
  @Prop @Watch('onSettleChanged') settleSeq: number = 0;
  @Prop settleOpen: boolean = true;
  @Prop limitsLoading: boolean = false;
  @Prop limitsHasData: boolean = false;
  @Prop limitsText: string = '—';
  @Prop limitsUsed: number = 0;
  @Prop limitsTotal: number = 0;
  @Prop limitsFromGallery: string = '';
  @Prop limitsFromTorrent: string = '';
  @Prop limitsFromArchive: string = '';
  @Prop limitsFromHentai: string = '';
  @Prop limitsResetCost: number = 0;
  @Prop limitsResetCostText: string = '';
  onClose: () => void = (): void => {
  };
  onLimitsNotify: (kind: number) => void = (_kind: number): void => {
  };
  @State panelTranslateX: number = -ThemeDimens.DRAWER_MAX_WIDTH;
  @State scrimOpacity: number = 0;
  @State limitsCollapseSeq: number = 0;
  private closing: boolean = false;
  private lastSettledSeq: number = 0;

  aboutToAppear(): void {
    this.closing = false;
    this.lastSettledSeq = this.settleSeq;
    if (this.interactiveDragging) {
      const p: number = Math.max(0, Math.min(1, this.interactiveProgress));
      this.panelTranslateX = -ThemeDimens.DRAWER_MAX_WIDTH * (1 - p);
      this.scrimOpacity = p;
      return;
    }
    this.panelTranslateX = -ThemeDimens.DRAWER_MAX_WIDTH;
    this.scrimOpacity = 0;
    animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
      this.panelTranslateX = 0;
      this.scrimOpacity = 1;
    });
  }

  private onDragPropChanged(): void {
    if (!this.interactiveDragging) {
      return;
    }
    this.closing = false;
    const p: number = Math.max(0, Math.min(1, this.interactiveProgress));
    this.panelTranslateX = -ThemeDimens.DRAWER_MAX_WIDTH * (1 - p);
    this.scrimOpacity = p;
  }

  private onSettleChanged(): void {
    if (this.settleSeq === this.lastSettledSeq) {
      return;
    }
    this.lastSettledSeq = this.settleSeq;
    if (this.settleOpen) {
      this.closing = false;
      animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
        this.panelTranslateX = 0;
        this.scrimOpacity = 1;
      });
    } else {
      this.closeAnimated();
    }
  }

  private closeAnimated(): void {
    if (this.closing) {
      return;
    }
    this.limitsCollapseSeq = this.limitsCollapseSeq + 1;
    this.closing = true;
    animateTo({
      duration: 180,
      curve: Curve.FastOutLinearIn,
      onFinish: (): void => {
        this.onClose();
      }
    }, (): void => {
      this.panelTranslateX = -ThemeDimens.DRAWER_MAX_WIDTH;
      this.scrimOpacity = 0;
    });
  }
  onRefreshLimits: () => void = (): void => {
  };
  onResetLimits: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  private currentThemeLabel(): Resource {
    if (this.themeId === ThemeMode.LIGHT) {
      return $r('app.string.theme_light');
    }
    if (this.themeId === ThemeMode.DARK) {
      return $r('app.string.theme_dark');
    }
    return $r('app.string.theme_black');
  }

  private isListActive(action: string): boolean {
    return this.activeScene === 'GalleryListScene' && this.activeListAction === action;
  }

  private isSceneActive(sceneName: string): boolean {
    return this.activeScene === sceneName;
  }

  private resolveDisplayName(): ResourceStr {
    if (this.displayNameOverride.length > 0) {
      return this.displayNameOverride;
    }
    try {
      if (Settings.isAttached()) {
        const name: string | null = Settings.getDisplayName();
        if (name !== null && name.trim().length > 0) {
          return name;
        }
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'resolveDisplayName failed: %{public}s', String(err));
    }
    return $r('app.string.default_display_name');
  }

  private resolveAvatarUrl(): string {
    try {
      if (Settings.isAttached()) {
        const avatar: string | null = Settings.getAvatar();
        if (avatar !== null && avatar.trim().length > 0) {
          return avatar;
        }
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'resolveAvatarUrl failed: %{public}s', String(err));
    }
    return '';
  }

  private canShowLimits(): boolean {
    try {
      if (!Settings.isAttached()) {
        return false;
      }
      return Settings.isLogin() && Settings.getShowEhLimits();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'canShowLimits check failed: %{public}s', String(err));
      return false;
    }
  }

  private buildLimitsState(): LimitsCountState {
    const state: LimitsCountState = new LimitsCountState();
    state.canShowLimits = true;
    return state;
  }

  @Builder
  private navRow(
    label: Resource,
    pathData: string,
    active: boolean,
    onTap: () => void
  ): void {
    Row() {
      Shape() {
        Path()
          .commands(pathData)
          .fill(active ? this.palette().drawerActiveColor : this.palette().drawablePrimary)
          .stroke(Color.Transparent)
          .strokeWidth(0)
      }
      .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
      .width(ThemeDimens.ICON_SIZE_STANDARD)
      .height(ThemeDimens.ICON_SIZE_STANDARD)
      .margin({ right: 32 })
      .antiAlias(true)

      Text(label)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontWeight(FontWeight.Medium)
        .fontColor(active ? this.palette().drawerActiveColor : this.palette().textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(ThemeDimens.TOUCH_TARGET_MIN)
    .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
    .backgroundColor(active ? this.palette().drawerActiveBackground : this.palette().transparent)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      onTap();
    })
  }

  build(): void {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().drawerScrim)
        .opacity(this.scrimOpacity)
        .onClick((): void => {
          this.closeAnimated();
        })

      Column() {
        Scroll() {
          Column() {
            Stack({ alignContent: Alignment.BottomStart }) {
              Image($r('app.media.sadpanda_low_poly'))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)

              Column()
                .width('100%')
                .height('100%')
                .linearGradient({
                  direction: GradientDirection.Bottom,
                  colors: [
                    ['#00000000', 0.0],
                    ['#66000000', 0.65],
                    ['#99000000', 1.0],
                  ],
                })

              Column() {
                if (this.resolveAvatarUrl().length > 0) {
                  Image(this.resolveAvatarUrl())
                    .width(ThemeDimens.NAV_AVATAR_SIZE)
                    .height(ThemeDimens.NAV_AVATAR_SIZE)
                    .borderRadius(ThemeDimens.NAV_AVATAR_SIZE / 2)
                    .objectFit(ImageFit.Cover)
                    .margin({ bottom: ThemeDimens.KEYLINE_MARGIN })
                } else {
                  Column() {
                    DefaultAvatar({ iconSize: ThemeDimens.NAV_AVATAR_SIZE })
                  }
                  .width(ThemeDimens.NAV_AVATAR_SIZE)
                  .height(ThemeDimens.NAV_AVATAR_SIZE)
                  .borderRadius(ThemeDimens.NAV_AVATAR_SIZE / 2)
                  .clip(true)
                  .margin({ bottom: ThemeDimens.KEYLINE_MARGIN })
                }

                Text(this.resolveDisplayName())
                  .fontSize(ThemeTypography.TEXT_SMALL)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().white)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Center)
              .margin({ left: 32, bottom: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
            }
            .width('100%')
            .height(ThemeDimens.NAV_HEADER_HEIGHT)
            .backgroundColor(this.palette().colorPrimaryDark)

            Column() {
              this.navRow(
                $r('app.string.homepage'),
                PathData.pd_homepage,
                this.isListActive(GalleryListAction.HOMEPAGE),
                (): void => {
                  this.onSelectList(GalleryListAction.HOMEPAGE, EhUrl.getHost());
                }
              )

              this.navRow(
                $r('app.string.subscription'),
                PathData.pd_eh_subscription,
                this.isListActive(GalleryListAction.SUBSCRIPTION),
                (): void => {
                  this.onSelectList(GalleryListAction.SUBSCRIPTION, EhUrl.getWatchedUrl());
                }
              )

              this.navRow(
                $r('app.string.whats_hot'),
                PathData.pd_fire,
                this.isListActive(GalleryListAction.WHATS_HOT),
                (): void => {
                  this.onSelectList(GalleryListAction.WHATS_HOT, EhUrl.getPopularUrl());
                }
              )

              this.navRow(
                $r('app.string.top_lists'),
                PathData.pd_top_lists,
                this.isSceneActive('EhTopListScene'),
                (): void => {
                  this.onSelectScene('EhTopListScene');
                }
              )

              this.navRow(
                $r('app.string.favourite'),
                PathData.pd_heart,
                this.isSceneActive('FavoritesScene'),
                (): void => {
                  this.onSelectScene('FavoritesScene');
                }
              )

              this.navRow(
                $r('app.string.history'),
                PathData.pd_history,
                this.isSceneActive('HistoryScene'),
                (): void => {
                  this.onSelectScene('HistoryScene');
                }
              )

              this.navRow(
                $r('app.string.downloads'),
                PathData.pd_download,
                this.isSceneActive('DownloadsScene'),
                (): void => {
                  this.onSelectScene('DownloadsScene');
                }
              )

              Divider()
                .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
                .color(this.palette().divider)
                .margin({ top: ThemeDimens.SPACING, bottom: ThemeDimens.SPACING })

              this.navRow(
                $r('app.string.settings'),
                PathData.pd_settings,
                false,
                (): void => {
                  this.onOpenPage(PageRoutes.SETTINGS);
                }
              )
            }
            .width('100%')
            .padding({ top: ThemeDimens.SPACING, bottom: ThemeDimens.SPACING })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)

        Column() {
          Divider()
            .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
            .color(this.palette().divider)

          if (this.canShowLimits()) {
            Column() {
              LimitsCountView({
                state: this.buildLimitsState(),
                provider: this.limitsProvider,
                themeId: this.themeId,
                limitsText: this.limitsText,
                usedCount: this.limitsUsed,
                totalCount: this.limitsTotal,
                fromGalleryText: this.limitsFromGallery,
                fromTorrentText: this.limitsFromTorrent,
                fromArchiveText: this.limitsFromArchive,
                fromHentaiText: this.limitsFromHentai,
                resetCostValue: this.limitsResetCost,
                resetCostText: this.limitsResetCostText,
                loading: this.limitsLoading,
                hasData: this.limitsHasData,
                collapseSignal: this.limitsCollapseSeq,
                onRequestRefresh: this.onRefreshLimits,
                onRequestReset: this.onResetLimits,
                onNotify: this.onLimitsNotify,
              })
            }
            .width('100%')
          }

          Row() {
            Text(this.currentThemeLabel())
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().themeChangeButtonText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
          .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN })
          .backgroundColor(this.palette().themeChangeButtonBg)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.onToggleTheme();
          })
        }
        .width('100%')
      }
      .width('78%')
      .constraintSize({ maxWidth: ThemeDimens.DRAWER_MAX_WIDTH })
      .height('100%')
      .backgroundColor(this.palette().drawerBackground)
      .shadow(ThemeElevation.dialog())
      .translate({ x: this.panelTranslateX })
    }
    .width('100%')
    .height('100%')
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 10 })
        .onActionUpdate((event: GestureEvent): void => {
          if (event.offsetX <= 0) {
            const clamped: number = Math.max(-ThemeDimens.DRAWER_MAX_WIDTH, event.offsetX);
            this.panelTranslateX = clamped;
            this.scrimOpacity = Math.max(0, 1 + clamped / ThemeDimens.DRAWER_MAX_WIDTH);
          }
        })
        .onActionEnd((event: GestureEvent): void => {
          MainPageHost.markSwipeGesture();
          if (event.offsetX <= -ThemeDimens.DRAWER_MAX_WIDTH * 0.35 || event.velocityX < -350) {
            this.closeAnimated();
          } else {
            animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
              this.panelTranslateX = 0;
              this.scrimOpacity = 1;
            });
          }
        })
        .onActionCancel((): void => {
          if (this.panelTranslateX <= -ThemeDimens.DRAWER_MAX_WIDTH * 0.35) {
            this.closeAnimated();
          } else {
            animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, (): void => {
              this.panelTranslateX = 0;
              this.scrimOpacity = 1;
            });
          }
        })
    )
  }
}
