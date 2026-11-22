/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/ReversibleSeekBar.java（inventory S0305，上游 67 行）
 *
 * 上游：AppCompatSeekBar 子类，setReverse(true) 时
 *   draw()：canvas.scale(-1, 1, w/2, h/2) 水平镜像后再画（视觉反转）
 *   onTouchEvent：把触点 x 镜像成 w-x 再交给 super（保证"从右往左拖"手感正确）
 *
 * ArkUI 对位：原生 `Slider.reverse(true)` 同时完成"视觉反转 + 触摸映射"两件事，
 *   配合 ThemeTokens 显式覆盖 selectedColor / trackColor / blockColor 避免 HarmonyOS 默认蓝。
 */
import { ThemeTokens } from '../../../common/theme/ThemeTokens';

@Component
export struct ReversibleSeekBar {
  @Prop @Watch('onValuePropChanged') value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 100;
  /** 上游 setReverse(boolean) */
  @Prop reverse: boolean = false;
  @Prop trackThickness: number = 3;
  @Prop selectedColor: ResourceColor = ThemeTokens.LIGHT.colorPrimary;
  @Prop trackColor: ResourceColor = '#4DFFFFFF';
  @Prop blockColor: ResourceColor = ThemeTokens.LIGHT.colorPrimary;

  onStartTracking: () => void = (): void => {};
  onProgressChange: (value: number, fromUser: boolean) => void = (): void => {};
  onStopTracking: (value: number) => void = (): void => {};

  @State private sliderValue: number = 0;
  private isDragging: boolean = false;

  aboutToAppear(): void {
    this.sliderValue = this.clampValue(this.value);
  }

  private onValuePropChanged(): void {
    if (!this.isDragging) {
      this.sliderValue = this.clampValue(this.value);
    }
  }

  private clampValue(v: number): number {
    const safeMax: number = this.max > this.min ? this.max : this.min;
    return Math.max(this.min, Math.min(safeMax, Math.round(v)));
  }

  build() {
    Slider({
      value: this.sliderValue,
      min: this.min,
      max: this.max > this.min ? this.max : this.min + 1,
      step: 1,
      style: SliderStyle.OutSet,
      reverse: this.reverse
    })
      .enabled(this.max > this.min)
      .trackThickness(this.trackThickness)
      .selectedColor(this.selectedColor)
      .trackColor(this.trackColor)
      .blockColor(this.blockColor)
      .width('100%')
      .onChange((v: number, mode: SliderChangeMode): void => {
        const rounded: number = this.clampValue(v);
        this.sliderValue = rounded;
        if (mode === SliderChangeMode.Begin) {
          this.isDragging = true;
          this.onStartTracking();
          return;
        }
        if (mode === SliderChangeMode.Moving) {
          this.isDragging = true;
          this.onProgressChange(rounded, true);
          return;
        }
        if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
          this.isDragging = false;
          this.onProgressChange(rounded, true);
          this.onStopTracking(rounded);
        }
      })
  }
}
