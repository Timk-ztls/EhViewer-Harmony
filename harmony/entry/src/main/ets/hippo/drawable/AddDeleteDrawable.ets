/**
 * 迁移自 app/src/main/java/com/hippo/drawable/AddDeleteDrawable.java（inventory S0024，上游 140 行）
 *
 * 上游：一个"加号变成 ✕"的绘制器
 *   mPath：两条线 (0,-half)→(0,half) 与 (-half,0)→(half,0)，half = mSize/2
 *   draw()：canvas.translate(centerX, centerY); rotate(lerp(0,135,progress)) 或（verticalMirror 时）lerp(270,135,progress)
 *           drawPath(mPath, STROKE + MITER + BUTT + barThickness)
 *   progress 0 = 加号，1 = ✕；setShape(delete, duration) 用 ObjectAnimator 推进
 *   autoUpdateMirror：progress==1 时置 verticalMirror=true，progress==0 时置 false
 *   intrinsic = mSize * 6 / 5（正方形）
 *
 * ArkUI 对位：
 *   drawPath → Canvas：translate 到中心、rotate、两次 lineTo + stroke（MITTER → lineJoin='miter'，BUTT → lineCap='butt'）
 *   ObjectAnimator → DrawableAnimator（16ms + AccelerateDecelerate，见同目录文件）
 *   invalidateSelf → 每次 progress 变化 requestRedraw
 *
 * 尺寸：add_size / add_thickness 来自上游 dimens（默认 add_size=20dp, add_thickness=2dp），以 @Prop 暴露。
 */
import { DrawableAnimator } from './DrawableAnimator';

export class AddDeleteDrawableController {
  progress: number = 0;
  autoUpdateMirror: boolean = false;
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
    if (this.autoUpdateMirror) {
      if (progress === 1) {
        this.verticalMirror = true;
      } else if (progress === 0) {
        this.verticalMirror = false;
      }
    }
    this.progress = progress;
    this.notify();
  }

  /** 上游 setAdd(duration)：progress→0 */
  setAdd(duration: number): void {
    this.setShape(false, duration);
  }

  /** 上游 setDelete(duration)：progress→1 */
  setDelete(duration: number): void {
    this.setShape(true, duration);
  }

  setShape(deleteShape: boolean, duration: number): void {
    if ((!deleteShape && this.progress === 0) || (deleteShape && this.progress === 1)) {
      return;
    }
    const end: number = deleteShape ? 1 : 0;
    this.animator.start(this.progress, end, duration, (v: number) => {
      this.setProgress(v);
    }, null);
  }

  private notify(): void {
    if (this.redrawFn !== null) {
      this.redrawFn();
    }
  }
}

@Component
export struct AddDeleteDrawable {
  controller: AddDeleteDrawableController = new AddDeleteDrawableController();
  /** 上游 R.dimen.add_size = **20dp**（dimens.xml 实测；原注释误写 24dp）；intrinsic = size*6/5 */
  @Prop addSize: number = 20;
  /** 上游 R.dimen.add_thickness（默认 2dp） */
  @Prop barThickness: number = 2;
  @Prop @Watch('onColorChanged') color: ResourceColor = '#FF000000';
  @Prop alpha: number = 1.0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private boxW: number = 0;
  private boxH: number = 0;

  private onColorChanged(): void {
    this.redraw();
  }

  private redraw(): void {
    if (!this.ready || this.boxW <= 0 || this.boxH <= 0) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.ctx;
    ctx.clearRect(0, 0, this.boxW, this.boxH);
    const half: number = this.addSize / 2;
    const p: number = this.controller.progress;
    // lerp(0,135,progress)；verticalMirror 时 lerp(270,135,progress)
    const rotate: number = this.controller.verticalMirror
      ? (270 + (135 - 270) * p)
      : (0 + (135 - 0) * p);
    ctx.save();
    ctx.translate(this.boxW / 2, this.boxH / 2);
    ctx.rotate(rotate * Math.PI / 180);
    ctx.strokeStyle = this.color as string;
    ctx.lineWidth = this.barThickness;
    ctx.lineJoin = 'miter';
    ctx.lineCap = 'butt';
    ctx.globalAlpha = this.alpha;
    ctx.beginPath();
    ctx.moveTo(0, -half);
    ctx.lineTo(0, half);
    ctx.moveTo(-half, 0);
    ctx.lineTo(half, 0);
    ctx.stroke();
    ctx.restore();
    ctx.globalAlpha = 1.0;
  }

  build() {
    Canvas(this.ctx)
      .width(this.addSize * 6 / 5)
      .height(this.addSize * 6 / 5)
      .onReady(() => {
        this.ready = true;
        this.controller.attach(() => {
          this.redraw();
        });
        this.redraw();
      })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.boxW = newValue.width as number;
        this.boxH = newValue.height as number;
        this.redraw();
      })
  }
}
