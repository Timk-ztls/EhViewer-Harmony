/*
 * 上游：app/src/main/res/layout/activity_gallery.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_gallery.ets（inventory S0552）
 *
 * 结构对照：
 *   FrameLayout#main (match x match) -> Stack({ alignContent: Alignment.Center })
 *     GLRootView#gl_root_view (match x match) -> glRootViewBuilder
 *     GalleryHeader#gallery_header (match x wrap, gravity=top) -> Top wrapper + galleryHeaderBuilder
 *     LinearLayout (match x wrap, gravity=bottom, fitsSystemWindows=true) -> Bottom wrapper
 *       ImageView#auto_transfer (45x45, marginEnd=16, marginBottom=12, gravity=end)
 *       SeekBarPanel#seek_bar_panel (match x wrap) -> seekBarPanelBuilder
 *     ColorView#mask (match x match, HitTestMode.None) -> maskBuilder
 */
import { ThemePalette, ThemeTokens } from '../../../common/theme/ThemeTokens';
import { IcPauseCircle } from '../drawable/ic_pause_circle';
import { IcStartPlay24 } from '../drawable/ic_start_play_24';

@Component
export struct ActivityGalleryLayout {
  @Prop autoTransferSrc: ResourceStr = '';
  @Prop autoTransferVisible: boolean = false;
  @Prop autoTransferring: boolean = false;
  @Prop headerVisible: boolean = true;
  @Prop controlsVisible: boolean = false;
  @Prop themeId: number = -1;
  onAutoTransferClick: () => void = (): void => {};

  @BuilderParam galleryHeaderBuilder: () => void = this.emptySlot;
  @BuilderParam glRootViewBuilder: () => void = this.emptySlot;
  @BuilderParam maskBuilder: () => void = this.emptySlot;
  @BuilderParam seekBarPanelBuilder: () => void = this.emptySlot;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  @Builder
  defaultAutoTransfer() {
    Column() {
      if (this.autoTransferSrc !== '') {
        Image(this.autoTransferSrc)
          .width(45)
          .height(45)
          .onClick((): void => {
            this.onAutoTransferClick();
          })
      } else {
        Button({ type: ButtonType.Normal }) {
          if (this.autoTransferring) {
            IcPauseCircle({ iconSize: 24, fillColor: this.palette().white })
          } else {
            IcStartPlay24({ iconSize: 24, fillColor: this.palette().white })
          }
        }
        .width(45)
        .height(45)
        .borderRadius(22.5)
        .backgroundColor(this.palette().readerOverlayScrim)
        .onClick((): void => {
          this.onAutoTransferClick();
        })
      }
    }
    .id('autoTransfer')
    .margin({ right: 16, bottom: 12 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.glRootViewBuilder()
      }
      .id('glRootView')
      .width('100%')
      .height('100%')

      if (this.headerVisible) {
        Column() {
          Column() {
            this.galleryHeaderBuilder()
          }
          .id('galleryHeader')
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        if (this.autoTransferVisible || this.controlsVisible) {
          this.defaultAutoTransfer()
        }
        Column() {
          this.seekBarPanelBuilder()
        }
        .id('seekBarPanel')
        .width('100%')
        .visibility(this.controlsVisible ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)

      Column() {
        this.maskBuilder()
      }
      .id('mask')
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
    .id('galleryActivityMain')
    .width('100%')
    .height('100%')
  }
}
