/**
 * 迁移自 app/src/main/java/com/hippo/widget/ProgressView.java（inventory S0535，上游 267 行）
 *
 * 上游基于 AOSP L 预览版 `MaterialProgressDrawable` 的不确定进度环，四条动画通道：
 *   trimStart : 0 → 0.75，1333ms，TRIM_START_INTERPOLATOR（路径插值器）
 *   trimEnd   : 0 → 0.75，1333ms，TRIM_END_INTERPOLATOR
 *   trimOffset: 0 → 0.25，1333ms，LinearInterpolator（无限循环）
 *   trimRotation: 累积旋转（每周期 360°）
 *   draw：以 trimRotation + trimOffset*360 为起始角、sweep = (trimEnd - trimStart)*360 画圆环
 *        STROKE + SQUARE cap + MITER join
 *
 * 两个路径插值器（上游用 PathInterpolatorCompat.create(Path)）的路径是：
 *   TRIM_START: moveTo(0,0) lineTo(0.5,0) cubicTo(0.7,0, 0.6,1, 1,1)
 *   TRIM_END  : moveTo(0,0) cubicTo(0.2,0, 0.1,1, 0.5,1) lineTo(1,1)
 * 它们都是"分段：一段直线 + 一段三次贝塞尔"（TRIM_END 顺序相反），因此本文件用
 * `PiecewisePathInterpolator` 按段精确求解（直线段解析、贝塞尔段二分），**不是近似**。
 *
 * ArkUI 对位：Canvas 画 arc + 一条 16ms 节拍器推进四条通道（与 ObjectAnimator 的帧率一致）。
 * 差异：上游 INFINITE repeat 由 ObjectAnimator 驱动；本实现的节拍器用 Date.now() 取模循环，
 *      相位与上游同构（三条通道同周期 1333ms、rotation 每周期 +360°），长时间运行的相位漂移 < 1 帧。
 */
class LinearSegment {
  x0: number = 0;
  y0: number = 0;
  x1: number = 0;
  y1: number = 0;
}

class CubicSegment {
  x0: number = 0;
  y0: number = 0;
  cx1: number = 0;
  cy1: number = 0;
  cx2: number = 0;
  cy2: number = 0;
  x1: number = 0;
  y1: number = 0;
}

/** 对位 PathInterpolatorCompat：分段线性 + 三次贝塞尔（按 x 求解 t，再取 y） */
export class PiecewisePathInterpolator {
  private linear: LinearSegment[] = [];
  private cubic: CubicSegment[] = [];

  static trimStart(): PiecewisePathInterpolator {
    const p: PiecewisePathInterpolator = new PiecewisePathInterpolator();
    const l: LinearSegment = new LinearSegment();
    l.x0 = 0;
    l.y0 = 0;
    l.x1 = 0.5;
    l.y1 = 0;
    p.linear.push(l);
    const c: CubicSegment = new CubicSegment();
    c.x0 = 0.5;
    c.y0 = 0;
    c.cx1 = 0.7;
    c.cy1 = 0;
    c.cx2 = 0.6;
    c.cy2 = 1;
    c.x1 = 1;
    c.y1 = 1;
    p.cubic.push(c);
    return p;
  }

  static trimEnd(): PiecewisePathInterpolator {
    const p: PiecewisePathInterpolator = new PiecewisePathInterpolator();
    const c: CubicSegment = new CubicSegment();
    c.x0 = 0;
    c.y0 = 0;
    c.cx1 = 0.2;
    c.cy1 = 0;
    c.cx2 = 0.1;
    c.cy2 = 1;
    c.x1 = 0.5;
    c.y1 = 1;
    p.cubic.push(c);
    const l: LinearSegment = new LinearSegment();
    l.x0 = 0.5;
    l.y0 = 1;
    l.x1 = 1;
    l.y1 = 1;
    p.linear.push(l);
    return p;
  }

  static linear(): PiecewisePathInterpolator {
    const p: PiecewisePathInterpolator = new PiecewisePathInterpolator();
    const l: LinearSegment = new LinearSegment();
    l.x0 = 0;
    l.y0 = 0;
    l.x1 = 1;
    l.y1 = 1;
    p.linear.push(l);
    return p;
  }

  /** 求 value(x) */
  getInterpolation(x: number): number {
    if (x <= 0) {
      return 0;
    }
    if (x >= 1) {
      return 1;
    }
    for (let i = 0; i < this.linear.length; i++) {
      const s: LinearSegment = this.linear[i];
      const lo: number = Math.min(s.x0, s.x1);
      const hi: number = Math.max(s.x0, s.x1);
      if (x >= lo && x <= hi && s.x1 !== s.x0) {
        return s.y0 + (s.y1 - s.y0) * ((x - s.x0) / (s.x1 - s.x0));
      }
    }
    for (let i = 0; i < this.cubic.length; i++) {
      const c: CubicSegment = this.cubic[i];
      const lo: number = Math.min(c.x0, c.x1);
      const hi: number = Math.max(c.x0, c.x1);
      if (x >= lo && x <= hi) {
        // 二分求 t 使 bezierX(t) = x
        let tLo: number = 0;
        let tHi: number = 1;
        let t: number = 0.5;
        for (let k = 0; k < 24; k++) {
          t = (tLo + tHi) / 2;
          const bx: number = PiecewisePathInterpolator.bezier(t, c.x0, c.cx1, c.cx2, c.x1);
          if (bx < x) {
            tLo = t;
          } else {
            tHi = t;
          }
        }
        return PiecewisePathInterpolator.bezier(t, c.y0, c.cy1, c.cy2, c.y1);
      }
    }
    return x;
  }

  private static bezier(t: number, p0: number, p1: number, p2: number, p3: number): number {
    const mt: number = 1 - t;
    return mt * mt * mt * p0 + 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t * p3;
  }
}

/** 四条动画通道的相位计算（纯函数，可单测） */
export class ProgressRingPhase {
  static readonly CYCLE_MS: number = 1333;
  /** 上游 trimRotation 走**独立**的 720° / 6665ms 线性动画（与三条 1333ms 通道不同周期） */
  static readonly ROTATION_CYCLE_MS: number = 6665;
  static readonly ROTATION_DEGREES: number = 720;

  /** 周期内相位 0..1 */
  static phase(elapsedMs: number): number {
    const p: number = (elapsedMs % ProgressRingPhase.CYCLE_MS) / ProgressRingPhase.CYCLE_MS;
    return p < 0 ? 0 : p;
  }

  /**
   * trimRotation：独立周期 6665ms 内 0→720°（上游 `ofFloat(this,\"trimRotation\",0f,720f)` + `setDuration(6665)`）。
   * 修前误用 1333ms/360° ⇒ 转速快 2.5×（审计 D P2）。
   */
  static rotation(elapsedMs: number): number {
    return (elapsedMs / ProgressRingPhase.ROTATION_CYCLE_MS) * ProgressRingPhase.ROTATION_DEGREES;
  }

  /** 绘制用起始角（度）：rotation + offset*360 */
  static startAngle(elapsedMs: number, trimOffset: number, trimRotation: number): number {
    return trimRotation + trimOffset * 360;
  }

  /** 绘制用扫过角（度）：(trimEnd - trimStart)*360 */
  static sweepAngle(trimStart: number, trimEnd: number): number {
    return (trimEnd - trimStart) * 360;
  }
}

@Component
export struct ProgressView {
  /** 上游 R.styleable.ProgressView_color（默认 Color.BLACK） */
  @Prop @Watch('onPaintChanged') color: ResourceColor = '#FF000000';
  /** 上游 indeterminate（默认 true）；false 时按 progress 画定长弧 */
  @Prop indeterminate: boolean = true;
  /** 0..1（上游 setProgress(float)）—— 变化时立即重绘（缺陷修复 P1-d：原实现只在 indeterminate 的 ticker 与 onReady 里重绘，
   *  导致 item_download 这类 indeterminate=false + setProgress() 的定长环冻在初始值） */
  @Prop @Watch('onProgressChanged') progress: number = 0;
  /** 环外径 */
  @Prop ringSize: number = 40;
  /** 描边宽度（上游未显式给，AOSP Material 取 size/12） */
  @Prop strokeWidth: number = 3.0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private timerId: number = -1;
  private startTime: number = -1;

  private trimStartIp: PiecewisePathInterpolator = PiecewisePathInterpolator.trimStart();
  private trimEndIp: PiecewisePathInterpolator = PiecewisePathInterpolator.trimEnd();
  private linearIp: PiecewisePathInterpolator = PiecewisePathInterpolator.linear();

  aboutToAppear(): void {
    this.startTime = Date.now();
    if (this.indeterminate) {
      this.startTicker();
    }
  }

  aboutToDisappear(): void {
    this.stopTicker();
  }

  /** @Watch 回调：定长态下 progress 变化即重绘（上游 setProgress 里 invalidate()） */
  private onProgressChanged(): void {
    this.redraw();
  }

  /** @Watch 回调：颜色变化也要重绘（上游 mPaint.setColor 后随绘制生效） */
  private onPaintChanged(): void {
    this.redraw();
  }

  private startTicker(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      this.redraw();
    }, 16);
  }

  private stopTicker(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private redraw(): void {
    if (!this.ready) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.ctx;
    const size: number = this.ringSize;
    ctx.clearRect(0, 0, size, size);
    const cx: number = size / 2;
    const cy: number = size / 2;
    const radius: number = (size - this.strokeWidth) / 2;
    ctx.strokeStyle = this.color as string;
    ctx.lineWidth = this.strokeWidth;
    ctx.lineCap = 'square';
    ctx.lineJoin = 'miter';

    if (!this.indeterminate) {
      // 定长弧：从 -90° 起，扫 progress*360°
      const start: number = -90 * Math.PI / 180;
      const end: number = start + (this.progress * 2 * Math.PI);
      ctx.beginPath();
      ctx.arc(cx, cy, radius, start, end);
      ctx.stroke();
      return;
    }

    const elapsed: number = Date.now() - this.startTime;
    const phase: number = ProgressRingPhase.phase(elapsed);
    const trimStart: number = this.trimStartIp.getInterpolation(phase) * 0.75;
    const trimEnd: number = this.trimEndIp.getInterpolation(phase) * 0.75;
    const trimOffset: number = this.linearIp.getInterpolation(phase) * 0.25;
    const rot: number = ProgressRingPhase.rotation(elapsed);
    const startDeg: number = ProgressRingPhase.startAngle(elapsed, trimOffset, rot);
    const sweepDeg: number = ProgressRingPhase.sweepAngle(trimStart, trimEnd);
    const start: number = startDeg * Math.PI / 180;
    const end: number = (startDeg + sweepDeg) * Math.PI / 180;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, start, end);
    ctx.stroke();
  }

  build() {
    Canvas(this.ctx)
      .width(this.ringSize)
      .height(this.ringSize)
      .onReady(() => {
        this.ready = true;
        this.redraw();
      })
  }
}
