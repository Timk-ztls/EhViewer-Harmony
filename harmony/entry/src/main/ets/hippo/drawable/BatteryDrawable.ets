/**
 * 迁移自 app/src/main/java/com/hippo/drawable/BatteryDrawable.java（inventory S0025，上游 150 行）
 *
 * 上游：电池图标，5 个矩形拼成（外框上/下/右 + 正极帽 + 电量填充）
 *   onBoundsChange(bounds)：strokeWidth = sqrt(w²+h²)*0.06；turn1 = w*6/7；turn2 = h/3；secBottom = h-strokeWidth
 *     mStart = strokeWidth；mStop = turn1 - strokeWidth
 *     topRect    = (0, 0, turn1, strokeWidth)
 *     bottomRect = (0, secBottom, turn1, h)
 *     rightRect  = (turn1-strokeWidth, strokeWidth, turn1, secBottom)
 *     headRect   = (turn1, turn2, w, h-turn2)
 *     electRect  = (0, strokeWidth, mStop, secBottom)   ← draw 时 right = lerp(mStart, mStop, elect/100)
 *   draw()：elect == -1 直接不画；否则按当前电量更新 electRect.right，依次填 5 个矩形
 *   WARN_LIMIT = 15：elect <= 15 用 warningColor，否则 color
 *   setColor/setWarningColor 仅在与当前生效色不同时才换色（isWarn() 决定当前用哪个）
 *
 * ArkUI 对位：Canvas 逐矩形 fillRect（同一套原语）；绘制顺序完全一致
 *   背景透明（上游 TRANSLUCENT）→ 不画底色
 *   setAlpha → globalAlpha
 */
export class BatteryDrawableController {
  static readonly WARN_LIMIT: number = 15;
  color: string = '#FFFFFFFF';
  warningColor: string = '#FFFF0000';
  elect: number = -1;

  isWarn(): boolean {
    return this.elect <= BatteryDrawableController.WARN_LIMIT;
  }

  /** 上游 updatePaint(boolean)：当前生效色 */
  activeColor(): string {
    return this.isWarn() ? this.warningColor : this.color;
  }
}

@Component
export struct BatteryDrawable {
  controller: BatteryDrawableController = new BatteryDrawableController();
  /**
   * 电量（-1 = 未设置）。**必须带 @Watch**：controller 是普通类、字段不可观察，
   * 只改 controller.elect 不会触发 build() 重绘 ⇒ 充电动画帧不刷新（BatteryView 的隐患）。
   * 这里用 @Prop 承载会变的值，controller 只承载颜色配置。
   */
  @Prop @Watch('onElectChanged') elect: number = -1;
  @Prop drawWidth: number = 24;
  @Prop drawHeight: number = 12;
  @Prop alpha: number = 1.0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  /** @Watch 回调：电量变化即重绘（Canvas 不会自动跟随） */
  private onElectChanged(): void {
    this.redraw();
  }

  private redraw(): void {
    if (!this.ready) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.ctx;
    const w: number = this.drawWidth;
    const h: number = this.drawHeight;
    ctx.clearRect(0, 0, w, h);
    const elect: number = this.elect >= 0 ? this.elect : this.controller.elect;
    if (elect === -1) {
      return; // 上游：mElect == -1 直接 return
    }
    const strokeWidth: number = Math.floor(Math.sqrt(w * w + h * h) * 0.06);
    const turn1: number = Math.floor(w * 6 / 7);
    const turn2: number = Math.floor(h / 3);
    const secBottom: number = h - strokeWidth;
    const start: number = strokeWidth;
    const stop: number = turn1 - strokeWidth;
    const electRight: number = start + (stop - start) * (elect / 100.0);

    ctx.fillStyle = this.controller.activeColor();
    ctx.globalAlpha = this.alpha;
    // 顺序与上游一致：top → bottom → right → head → elect
    ctx.fillRect(0, 0, turn1, strokeWidth);
    ctx.fillRect(0, secBottom, turn1, h - secBottom);
    ctx.fillRect(turn1 - strokeWidth, strokeWidth, strokeWidth, secBottom - strokeWidth);
    ctx.fillRect(turn1, turn2, w - turn1, h - turn2 - turn2);
    ctx.fillRect(0, strokeWidth, electRight, secBottom - strokeWidth);
    ctx.globalAlpha = 1.0;
  }

  build() {
    Canvas(this.ctx)
      .width(this.drawWidth)
      .height(this.drawHeight)
      .onReady(() => {
        this.ready = true;
        this.redraw();
      })
  }
}
