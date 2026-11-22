/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/SeekBarPanel.java（inventory S0310，上游 63 行）
 * 与 app/src/main/res/layout/activity_gallery.xml (`@id/seek_bar_panel`) 对齐。
 *
 * 上游结构：
 *   SeekBarPanel (LinearLayout horizontal, height=wrap, background=?attr/gallerySliderBackgroundColor,
 *                 paddingLeft=16dp, paddingRight=16dp)
 *     TextView#left  (width=32dp, gravity=center_horizontal)
 *     FrameLayout    (width=0dp, weight=1, height=48dp) -> ReversibleSeekBar#seek_bar
 *     TextView#right (width=32dp, gravity=center_horizontal)
 */
import { ThemeDimens, ThemeTokens, ThemeTypography } from '../../../common/theme/ThemeTokens';
import { ReversibleSeekBar } from './ReversibleSeekBar';

@Component
export struct SeekBarPanel {
  /** 对位上游 R.id.seek_bar（0 基页码索引，或由外部指定 min..max） */
  @Prop @Watch('onValuePropChanged') value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 100;
  @Prop reverse: boolean = false;
  @Prop trackThickness: number = 3;
  @Prop selectedColor: ResourceColor = ThemeTokens.LIGHT.colorPrimary;
  @Prop trackColor: ResourceColor = '#4DFFFFFF';
  @Prop blockColor: ResourceColor = ThemeTokens.LIGHT.colorPrimary;
  @Prop panelBackgroundColor: ResourceColor = ThemeTokens.LIGHT.gallerySliderBackground;
  @Prop textColor: ResourceColor = ThemeTokens.LIGHT.white;
  @Prop leftText: string = '';
  @Prop rightText: string = '';
  @Prop bottomSafePadding: number = 0;

  onTrackingStart: () => void = (): void => {};
  /** 拖动中回调（对位 SeekBar.OnSeekBarChangeListener.onProgressChanged 的 fromUser=true 情形） */
  onProgressChange: (value: number) => void = (): void => {};
  /** 拖动结束或点击滑轨确认跳页（对位 onStopTrackingTouch） */
  onProgressConfirm: (value: number) => void = (): void => {};
  onStepLeft: () => void = (): void => {};
  onStepRight: () => void = (): void => {};

  @State private dragPreviewValue: number = -1;

  private onValuePropChanged(): void {
    this.dragPreviewValue = -1;
  }

  private displayStartLabel(): string {
    const activeVal: number = this.dragPreviewValue >= 0 ? this.dragPreviewValue : this.value;
    const offset: number = this.min === 0 ? 1 : 0;
    return `${Math.max(1, Math.round(activeVal) + offset)}`;
  }

  private displayEndLabel(): string {
    const offset: number = this.min === 0 ? 1 : 0;
    return `${Math.max(1, Math.round(this.max) + offset)}`;
  }

  private resolvedLeftText(): string {
    if (this.leftText.length > 0 && this.dragPreviewValue < 0) {
      return this.leftText;
    }
    return this.reverse ? this.displayEndLabel() : this.displayStartLabel();
  }

  private resolvedRightText(): string {
    if (this.rightText.length > 0 && this.dragPreviewValue < 0) {
      return this.rightText;
    }
    return this.reverse ? this.displayStartLabel() : this.displayEndLabel();
  }

  build() {
    Row() {
      Text(this.resolvedLeftText())
        .id('left')
        .width(32)
        .height(48)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .onClick((): void => {
          this.onStepLeft();
        })

      Row() {
        ReversibleSeekBar({
          value: this.value,
          min: this.min,
          max: this.max,
          reverse: this.reverse,
          trackThickness: this.trackThickness,
          selectedColor: this.selectedColor,
          trackColor: this.trackColor,
          blockColor: this.blockColor,
          onStartTracking: (): void => {
            this.onTrackingStart();
          },
          onProgressChange: (v: number, fromUser: boolean): void => {
            if (fromUser) {
              this.dragPreviewValue = v;
              this.onProgressChange(v);
            }
          },
          onStopTracking: (v: number): void => {
            this.dragPreviewValue = -1;
            this.onProgressConfirm(v);
          }
        })
      }
      .layoutWeight(1)
      .height(48)
      .alignItems(VerticalAlign.Center)

      Text(this.resolvedRightText())
        .id('right')
        .width(32)
        .height(48)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .onClick((): void => {
          this.onStepRight();
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 + this.bottomSafePadding })
    .padding({
      left: ThemeDimens.KEYLINE_MARGIN,
      right: ThemeDimens.KEYLINE_MARGIN,
      bottom: this.bottomSafePadding
    })
    .backgroundColor(this.panelBackgroundColor)
    .alignItems(VerticalAlign.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
