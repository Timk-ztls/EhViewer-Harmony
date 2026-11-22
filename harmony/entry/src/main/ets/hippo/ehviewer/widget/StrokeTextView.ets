/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/StrokeTextView.java（inventory S0312，上游 66 行）
 *
 * 上游做法：内部持有一个 `outlineTextView`（同文本、Paint.Style.STROKE + stroke_color/stroke_width），
 *   onMeasure 时把文本同步给它，onDraw 时**先画轮廓再画自身填充**（两层叠字实现描边）。
 *
 * ArkUI 对位：Canvas 的 `strokeText()` + `fillText()` 正是同一套原语的直接等价物
 *   （Android 的 Paint.Style.STROKE + drawText 与 Canvas2D 的 strokeText 语义相同），
 *   因此不需要"两个 Text 叠加"这种权宜做法：
 *     ctx.font = '<size>px sans-serif'
 *     ctx.lineWidth = strokeWidth; ctx.strokeStyle = strokeColor; ctx.strokeText(text, x, y);
 *     ctx.fillStyle = textColor; ctx.fillText(text, x, y);
 *
 * 差异（已登记 MR）：
 *   1) 字体度量：Android 用 Paint.FontMetrics 定基线，ArkUI Canvas 用 `textBaseline='middle'` 居中对齐；
 *      同一字号下基线可能差 1–2px —— 与 DEVIATIONS D-007 的文字纹理口径一致（不承诺像素级）。
 *   2) 上游 outlineTextView 共享同一个 LayoutParams，文本变化时在 onMeasure 里同步；ArkUI 在 @Prop
 *      变化时重绘（aboutToAppear + onAreaChange + text 变化三处触发）。
 *   3) 上游未处理 gravity 以外的对齐；本实现提供 textAlign 参数映射 start/center/end。
 */
@Component
export struct StrokeTextView {
  @Prop text: string = '';
  @Prop textSize: number = 16;
  @Prop textColor: ResourceColor = '#FFFFFFFF';
  /** 上游 R.styleable.StrokeTextView_stroke_color（默认 Color.WHITE） */
  @Prop strokeColor: ResourceColor = '#FFFFFFFF';
  /** 上游 R.styleable.StrokeTextView_stroke_width（默认 2） */
  @Prop strokeWidth: number = 2;
  /** 对齐：'start' | 'center' | 'end'（对位上游 setGravity 的常用三态） */
  @Prop textAlignValue: string = 'center';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private boxW: number = 0;
  private boxH: number = 0;

  private textAlignMode(): CanvasTextAlign {
    if (this.textAlignValue === 'start') {
      return 'start';
    }
    if (this.textAlignValue === 'end') {
      return 'end';
    }
    return 'center';
  }

  private x(): number {
    if (this.textAlignValue === 'start') {
      return 0;
    }
    if (this.textAlignValue === 'end') {
      return this.boxW;
    }
    return this.boxW / 2;
  }

  private redraw(): void {
    if (!this.ready || this.boxW <= 0 || this.boxH <= 0) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.ctx;
    ctx.clearRect(0, 0, this.boxW, this.boxH);
    ctx.font = `${this.textSize}px sans-serif`;
    ctx.textAlign = this.textAlignMode();
    ctx.textBaseline = 'middle';
    // 1) 轮廓（上游 outlineTextView：STROKE + stroke_width）
    ctx.lineWidth = this.strokeWidth;
    ctx.strokeStyle = this.strokeColor as string;
    ctx.lineJoin = 'round';
    ctx.strokeText(this.text, this.x(), this.boxH / 2);
    // 2) 填充（上游 super.onDraw：Paint.FILL + textColor）
    ctx.fillStyle = this.textColor as string;
    ctx.fillText(this.text, this.x(), this.boxH / 2);
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.ready = true;
        this.redraw();
      })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.boxW = newValue.width as number;
        this.boxH = newValue.height as number;
        this.redraw();
      })
  }
}
