/*
 * 上游：app/src/main/res/layout/scene_gallery_detail.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_gallery_detail.ets（inventory S0652）
 */

import {
  ThemeMode,
  ThemePalette,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { BigSadPandroid } from '../drawable/big_sad_pandroid';

@Component
export struct SceneGalleryDetailLayout {
  @Prop tip: ResourceStr = '';
  @Prop showContent: boolean = true;
  @Prop showProgress: boolean = false;
  @Prop showTip: boolean = false;
  @Prop themeId: number = ThemeMode.LIGHT;
  onTipClick: () => void = (): void => {};

  @BuilderParam contentBuilder: () => void = this.emptySlot;
  @BuilderParam progressViewBuilder: () => void = this.defaultProgress;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  @Builder
  defaultProgress() {
    LoadingProgress()
      .width(48)
      .height(48)
      .color(this.palette().progressColor)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.showContent) {
        Scroll() {
          Column() {
            this.contentBuilder()
          }
          .width('100%')
        }
        .id('scrollView')
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .align(Alignment.Top)
      }

      if (this.showProgress) {
        Column() {
          this.progressViewBuilder()
        }
        .id('progressView')
      }

      if (this.showTip) {
        Column({ space: 8 }) {
          BigSadPandroid({
            iconSize: 120,
            fillColor: this.palette().drawableSecondary
          })
          Text(this.tip)
            .id('tip')
            .width(228)
            .fontSize(ThemeTypography.TEXT_MEDIUM)
            .fontColor(this.palette().textSecondary)
            .textAlign(TextAlign.Center)
        }
        .width(228)
        .alignItems(HorizontalAlign.Center)
        .onClick((): void => {
          this.onTipClick();
        })
      }
    }
    .id('main')
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
