/**
 * 迁移自 app/src/main/java/com/hippo/drawable/DrawerArrowDrawable.java（inventory S0027，上游 186 行）
 *
 * 上游：汉堡菜单 → 返回箭头的插值绘制（DrawerLayout 的经典实现，来自 AOSP 的 DrawerArrowDrawable）
 *   ARROW_HEAD_ANGLE = 45°（弧度）
 *   draw()：
 *     arrowSize       = lerp(barSize, topBottomArrowSize, progress)
 *     middleBarSize   = lerp(barSize, middleArrowSize, progress)
 *     middleBarCut    = round(lerp(0, maxCutForBarSize, progress))
 *     rotation        = lerp(0, 45°, progress)
 *     canvasRotate    = lerp(-180°, 0, progress)
 *     arrowWidth      = round(arrowSize*cos(rotation))；arrowHeight = round(arrowSize*sin(rotation))
 *     topBottomBarOffset = lerp(barGap+barThickness, -maxCutForBarSize, progress)
 *     arrowEdge = -middleBarSize/2
 *     path：中间横线 (arrowEdge+middleBarCut,0) → +(middleBarSize-2*cut,0)
 *           下斜线 (arrowEdge, offset) → +(arrowWidth, arrowHeight)
 *           上斜线 (arrowEdge, -offset) → +(arrowWidth, -arrowHeight)
 *     STROKE + MITER + BUTT + barThickness
 *     canvas.translate(center)；若 mSpin 则 rotate(canvasRotate * (verticalMirror ? -1 : 1))
 *   maxCutForBarSize = barThickness/2 * cos(45°)
 *   setMenu/setArrow/setShape 用 ObjectAnimator 推进 progress；progress==1 → verticalMirror=true，==0 → false
 *
 * ArkUI 对位：Canvas 的 translate/rotate + moveTo/lineTo + stroke，指令逐条对应（同 Canvas2D 原语）；
 *   ObjectAnimator → DrawableAnimator（同目录，16ms + AccelerateDecelerate）。
 *
 * 差异：上游 dimens 来自资源（dad_drawable_size/dad_bar_size/dad_top_bottom_bar_arrow_size/
 *   dad_thickness/dad_gap_between_bars/dad_middle_bar_arrow_size/dad_spin_bars），此处以 @Prop 暴露，
 *   默认值取上游常见配置（size 24 / barSize 18 / arrowSize 18 / thickness 2 / gap 4 / middleArrowSize 0），
 *   ui-scene 按实际 dimens 传入。
 */
import { DrawableAnimator } from './DrawableAnimator';

export class DrawerArrowController {
  progress: number = 0;
  verticalMirror: boolean = false;
  animator: DrawableAnimator = new DrawableAnimator();
  private redrawFn: (() => void) | null = null;

  attach(redrawFn: () => void): void {
    this.redrawFn = redrawFn;
  }

  detach(): void {
    this.redrawFn = null;
    this.animator.cancel();
  }

  setProgress(progress: number): void {
    if (progress === 1) {
      this.verticalMirror = true;
    } else if (progress === 0) {
      this.verticalMirror = false;
    }
    this.progress = progress;
    if (this.redrawFn !== null) {
      this.redrawFn();
    }
  }

  setMenu(duration: number): void {
    this.setShape(false, duration);
  }

  setArrow(duration: number): void {
    this.setShape(true, duration);
  }

  setShape(arrow: boolean, duration: number): void {
    if ((!arrow && this.progress === 0) || (arrow && this.progress === 1)) {
      return;
    }
    const end: number = arrow ? 1 : 0;
    this.animator.start(this.progress, end, duration, (v: number) => {
      this.setProgress(v);
    }, null);
  }
}

@Component
export struct DrawerArrowDrawable {
  controller: DrawerArrowController = new DrawerArrowController();
  @Prop drawableSize: number = 24;
  @Prop barSize: number = 18;
  /** 上游 dad_top_bottom_bar_arrow_size = 11.31dp（dimens.xml 实测，原误写 18） */
  @Prop topBottomArrowSize: number = 11.31;
  @Prop barThickness: number = 2;
  /** 上游 dad_gap_between_bars = 3dp（dimens.xml 实测，原误写 4） */
  @Prop barGap: number = 3;
  /** 上游 dad_middle_bar_arrow_size = 16dp（dimens.xml 实测，原误写 0） */
  @Prop middleArrowSize: number = 16;
  /** 上游 R.bool.dad_spin_bars */
  @Prop spin: boolean = true;
  /** 描边色：必须是可直接赋给 ctx.strokeStyle 的字符串（上游 setColor(int)）；传 $r 资源需先解析 */
  @Prop @Watch('onColorChanged') color: string = '#FF000000';
  /** 上游 setAlpha(int)：0-255 整数（不是 0-1） */
  @Prop alpha: number = 255;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  private onColorChanged(): void {
    this.redraw();
  }

  private static lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t;
  }

  private redraw(): void {
    if (!this.ready) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.ctx;
    const w: number = this.drawableSize;
    const h: number = this.drawableSize;
    ctx.clearRect(0, 0, w, h);
    const p: number = this.controller.progress;
    const arrowHeadAngle: number = Math.PI / 4; // 45°
    const maxCut: number = this.barThickness / 2 * Math.cos(arrowHeadAngle);

    const arrowSize: number = DrawerArrowDrawable.lerp(this.barSize, this.topBottomArrowSize, p);
    const middleBarSize: number = DrawerArrowDrawable.lerp(this.barSize, this.middleArrowSize, p);
    const middleBarCut: number = Math.round(DrawerArrowDrawable.lerp(0, maxCut, p));
    const rotation: number = DrawerArrowDrawable.lerp(0, arrowHeadAngle, p);
    const canvasRotate: number = DrawerArrowDrawable.lerp(-180, 0, p);
    const arrowWidth: number = Math.round(arrowSize * Math.cos(rotation));
    const arrowHeight: number = Math.round(arrowSize * Math.sin(rotation));
    const topBottomBarOffset: number = DrawerArrowDrawable.lerp(this.barGap + this.barThickness, -maxCut, p);
    const arrowEdge: number = -middleBarSize / 2;

    ctx.save();
    ctx.translate(w / 2, h / 2);
    if (this.spin) {
      ctx.rotate(canvasRotate * (this.controller.verticalMirror ? -1 : 1) * Math.PI / 180);
    }
    ctx.strokeStyle = this.color;
    ctx.lineWidth = this.barThickness;
    ctx.lineJoin = 'miter';
    ctx.lineCap = 'butt';
    // 上游 alpha 是 0-255 → Canvas globalAlpha 是 0-1（不除会 clamp 成 1 = 全不透明）
    ctx.globalAlpha = Math.max(0, Math.min(1, this.alpha / 255));
    ctx.beginPath();
    // middle bar
    ctx.moveTo(arrowEdge + middleBarCut, 0);
    ctx.lineTo(arrowEdge + middleBarCut + (middleBarSize - middleBarCut * 2), 0);
    // bottom bar
    ctx.moveTo(arrowEdge, topBottomBarOffset);
    ctx.lineTo(arrowEdge + arrowWidth, topBottomBarOffset + arrowHeight);
    // top bar
    ctx.moveTo(arrowEdge, -topBottomBarOffset);
    ctx.lineTo(arrowEdge + arrowWidth, -topBottomBarOffset - arrowHeight);
    ctx.stroke();
    ctx.restore();
    ctx.globalAlpha = 1.0;
  }

  build() {
    Canvas(this.ctx)
      .width(this.drawableSize)
      .height(this.drawableSize)
      .onReady(() => {
        this.ready = true;
        this.controller.attach(() => {
          this.redraw();
        });
        this.redraw();
      })
  }
}