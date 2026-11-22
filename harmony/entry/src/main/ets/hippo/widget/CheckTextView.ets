/**
 * Material CheckTextView with circular reveal/collapse mask overlay.
 * Aligned with Android com.hippo.widget.CheckTextView.java & checkTextViewMask token.
 */

import {
  ThemePalette,
  ThemeTokens,
} from '../../common/theme/ThemeTokens';

export class ClickCurves {
  static readonly FAST_SLOW_IN_X1: number = 0.0;
  static readonly FAST_SLOW_IN_Y1: number = 0.0;
  static readonly FAST_SLOW_IN_X2: number = 0.2;
  static readonly FAST_SLOW_IN_Y2: number = 1.0;

  static readonly SLOW_FAST_IN_X1: number = 0.4;
  static readonly SLOW_FAST_IN_Y1: number = 0.0;
  static readonly SLOW_FAST_IN_X2: number = 1.0;
  static readonly SLOW_FAST_IN_Y2: number = 1.0;

  static bezier(input: number, x1: number, y1: number, x2: number, y2: number): number {
    if (input <= 0) {
      return 0;
    }
    if (input >= 1) {
      return 1;
    }
    let t: number = input;
    for (let i: number = 0; i < 6; i++) {
      const mt: number = 1 - t;
      const x: number = 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t * t * t;
      const dx: number = 3 * mt * mt * x1 + 6 * mt * t * (x2 - x1) + 3 * t * t * (1 - x2);
      if (Math.abs(dx) < 1e-6) {
        break;
      }
      t -= (x - input) / dx;
      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }
    }
    const mt: number = 1 - t;
    return 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t;
  }
}

function fastSlowInterpolate(t: number): number {
  return ClickCurves.bezier(
    t,
    ClickCurves.FAST_SLOW_IN_X1,
    ClickCurves.FAST_SLOW_IN_Y1,
    ClickCurves.FAST_SLOW_IN_X2,
    ClickCurves.FAST_SLOW_IN_Y2,
  );
}

function toCanvasRgba(hexColor: string): string {
  if (!hexColor.startsWith('#')) {
    return hexColor;
  }
  if (hexColor.length === 9) {
    const aByte: number = parseInt(hexColor.slice(1, 3), 16);
    const rByte: number = parseInt(hexColor.slice(3, 5), 16);
    const gByte: number = parseInt(hexColor.slice(5, 7), 16);
    const bByte: number = parseInt(hexColor.slice(7, 9), 16);
    if (!Number.isNaN(aByte) && !Number.isNaN(rByte) && !Number.isNaN(gByte) && !Number.isNaN(bByte)) {
      const alpha: string = (aByte / 255).toFixed(4);
      return `rgba(${rByte}, ${gByte}, ${bByte}, ${alpha})`;
    }
  }
  return hexColor;
}

export class CheckTextViewState {
  static readonly ANIMATION_DURATION: number = 200;

  checked: boolean = false;
  hotX: number = 0;
  hotY: number = 0;
  radius: number = 0;
  maxRadius: number = 0;
  private startRadius: number = 0;

  static coverageRadius(w: number, h: number, x: number, y: number): number {
    const dx: number = Math.max(x, w - x);
    const dy: number = Math.max(y, h - y);
    return Math.sqrt(dx * dx + dy * dy);
  }

  setHotspot(w: number, h: number, x: number, y: number): void {
    this.hotX = x;
    this.hotY = y;
    this.maxRadius = CheckTextViewState.coverageRadius(w, h, x, y);
  }

  setRadius(radius: number): void {
    this.radius = radius;
  }

  getRadius(): number {
    return this.radius;
  }

  prepareAnimations(): void {
    this.startRadius = this.checked ? 0 : this.maxRadius;
  }

  targetRadius(): number {
    return this.checked ? this.maxRadius : 0;
  }

  interpolate(fraction: number): number {
    const eased: number = fastSlowInterpolate(fraction);
    const target: number = this.targetRadius();
    return this.startRadius + (target - this.startRadius) * eased;
  }
}

@Component
export struct CheckTextView {
  state: CheckTextViewState = new CheckTextViewState();
  @Prop text: ResourceStr = '';
  @Prop fontSize: number = 14;
  @Prop textColor: ResourceColor = '';
  @Prop maskColor: ResourceColor = '';
  @Prop maxWidthValue: number = 160;
  @Prop bgColor: ResourceColor = Color.Transparent;
  @Prop cornerRadius: number = 0;
  @Prop minHeightValue: number = 0;
  @Prop fontWeightValue: FontWeight = FontWeight.Normal;
  @Prop textPadding: number = 0;
  @Prop themeId: number = -1;
  @Prop @Watch('onCheckedPropChanged') checked: boolean = false;
  onChange: (checked: boolean) => void = (): void => {
  };
  onLongPress?: () => void;

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private viewWidth: number = 0;
  private viewHeight: number = 0;
  private animTimerId: number = -1;

  aboutToAppear(): void {
    this.state.checked = this.checked;
    this.syncStaticRadius();
  }

  aboutToDisappear(): void {
    this.stopAnimation();
  }

  private resolvePalette(): ThemePalette {
    if (this.themeId >= 0) {
      return ThemeTokens.of(this.themeId);
    }
    return ThemeTokens.current();
  }

  private effectiveTextColor(palette: ThemePalette): ResourceColor {
    if (this.textColor !== '') {
      return this.textColor;
    }
    return palette.textPrimary;
  }

  private effectiveMaskCss(palette: ThemePalette): string {
    if (typeof this.maskColor === 'string' && this.maskColor.length > 0) {
      return toCanvasRgba(this.maskColor);
    }
    return toCanvasRgba(palette.checkTextViewMask);
  }

  private stopAnimation(): void {
    if (this.animTimerId !== -1) {
      clearInterval(this.animTimerId);
      this.animTimerId = -1;
    }
  }

  private syncStaticRadius(): void {
    if (this.viewWidth <= 0 || this.viewHeight <= 0) {
      return;
    }
    this.state.setHotspot(this.viewWidth, this.viewHeight, this.viewWidth / 2, this.viewHeight / 2);
    this.state.setRadius(this.state.checked ? this.state.maxRadius : 0);
  }

  private drawMask(palette: ThemePalette): void {
    const ctx: CanvasRenderingContext2D = this.canvasContext;
    const w: number = this.viewWidth;
    const h: number = this.viewHeight;
    if (w <= 0 || h <= 0) {
      return;
    }
    ctx.clearRect(0, 0, w, h);
    if (this.state.radius <= 0.5) {
      return;
    }
    ctx.save();
    ctx.fillStyle = this.effectiveMaskCss(palette);
    ctx.beginPath();
    if (this.animTimerId === -1 && this.state.checked) {
      ctx.rect(0, 0, w, h);
    } else {
      ctx.arc(this.state.hotX, this.state.hotY, this.state.radius, 0, Math.PI * 2);
    }
    ctx.fill();
    ctx.restore();
  }

  private onCheckedPropChanged(): void {
    if (this.state.checked !== this.checked) {
      this.setChecked(this.checked, true);
    }
  }

  setChecked(value: boolean, animate: boolean): void {
    if (this.state.checked === value && this.animTimerId === -1) {
      return;
    }
    this.stopAnimation();
    this.state.checked = value;
    const w: number = this.viewWidth;
    const h: number = this.viewHeight;
    if (w <= 0 || h <= 0) {
      return;
    }
    if (!animate) {
      this.state.setHotspot(w, h, w / 2, h / 2);
      this.state.setRadius(value ? this.state.maxRadius : 0);
      this.drawMask(this.resolvePalette());
      return;
    }
    if (this.state.maxRadius <= 0) {
      this.state.setHotspot(w, h, w / 2, h / 2);
    }
    this.state.prepareAnimations();
    const startTime: number = Date.now();
    const duration: number = CheckTextViewState.ANIMATION_DURATION;
    const palette: ThemePalette = this.resolvePalette();
    this.animTimerId = setInterval((): void => {
      const elapsed: number = Date.now() - startTime;
      const fraction: number = Math.min(1, elapsed / duration);
      this.state.setRadius(this.state.interpolate(fraction));
      this.drawMask(palette);
      if (fraction >= 1) {
        this.stopAnimation();
        this.drawMask(palette);
      }
    }, 16);
  }

  private handleTap(x: number, y: number): void {
    if (this.viewWidth > 0 && this.viewHeight > 0) {
      const clampedX: number = Math.max(0, Math.min(this.viewWidth, x));
      const clampedY: number = Math.max(0, Math.min(this.viewHeight, y));
      this.state.setHotspot(this.viewWidth, this.viewHeight, clampedX, clampedY);
    }
    const next: boolean = !this.state.checked;
    this.setChecked(next, true);
    this.onChange(next);
  }

  build(): void {
    this.buildCheckTextView();
  }

  @Builder
  private buildCheckTextView(): void {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.text)
        .fontSize(this.fontSize)
        .fontWeight(this.fontWeightValue)
        .fontColor(this.effectiveTextColor(this.resolvePalette()))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding(this.textPadding)

      Canvas(this.canvasContext)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .onReady((): void => {
          this.syncStaticRadius();
          this.drawMask(this.resolvePalette());
        })
    }
    .width('100%')
    .constraintSize({
      maxWidth: this.maxWidthValue > 0 ? this.maxWidthValue : '100%',
      minHeight: this.minHeightValue > 0 ? this.minHeightValue : 0,
    })
    .backgroundColor(this.bgColor)
    .borderRadius(this.cornerRadius)
    .clip(true)
    .onAreaChange((_oldVal: Area, newVal: Area): void => {
      const w: number = Number(newVal.width);
      const h: number = Number(newVal.height);
      if (!Number.isNaN(w) && !Number.isNaN(h) && w > 0 && h > 0) {
        this.viewWidth = w;
        this.viewHeight = h;
        if (this.animTimerId === -1) {
          this.syncStaticRadius();
        }
        this.drawMask(this.resolvePalette());
      }
    })
    .onClick((event: ClickEvent): void => {
      this.handleTap(event.x, event.y);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((_event: GestureEvent): void => {
          if (this.onLongPress !== undefined) {
            this.onLongPress();
          }
        })
    )
  }
}
