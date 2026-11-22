/**
 * 迁移自 app/src/main/java/com/hippo/reveal/RevealView.java（inventory S0454，上游 65 行）
 *
 * 上游：
 *   draw(canvas)：若 mReveal → canvas.save(); Path.addCircle(cx,cy,r,CW); canvas.clipPath(path);
 *                 super.draw(canvas); canvas.restoreToCount(...)
 *   setRevealEnable(boolean) / setReveal(cx,cy,r) → invalidate()
 *
 * ArkUI 对位：
 *   canvas.save()/clipPath(path)/restoreToCount → 组件级裁剪 `.clipShape(new Path({commands}))`
 *     —— ArkUI 的 clipShape 作用于组件自身及其子树，与 canvas.clipPath 对 super.draw() 的裁剪等价。
 *   Path.addCircle(cx,cy,r) → RevealGeometry.circlePath(cx,cy,r)（两段半圆弧的 SVG 命令）
 *   裁剪关闭时：传入覆盖全尺寸的矩形 path（等价"不裁剪"，避免条件属性写法）
 *
 * 差异（已登记 MR）：
 *   Android 的 clipPath 是**抗锯齿开关依赖硬件层**的路径裁剪，边缘在软件层下会有 1px 灰边；
 *   ArkUI clipShape 由渲染后端做路径裁剪，抗锯齿由系统统一处理。两者边缘处理不同，
 *   不做像素级承诺（同 DEVIATIONS D-007 的"功能对齐、不承诺像素级"口径）。
 */
import { Reveal, RevealGeometry } from './Reveal';

/** 控制器：承载上游三个字段 + invalidate 语义（组件通过 attach 接收重绘回调） */
export class RevealController implements Reveal {
  reveal: boolean = false;
  centerX: number = 0;
  centerY: number = 0;
  radius: number = 0;

  private width: number = 0;
  private height: number = 0;
  private redrawFn: (() => void) | null = null;

  attach(redrawFn: () => void): void {
    this.redrawFn = redrawFn;
  }

  detach(): void {
    this.redrawFn = null;
  }

  onSizeChanged(w: number, h: number): void {
    this.width = w;
    this.height = h;
    this.notify();
  }

  setRevealEnable(enable: boolean): void {
    this.reveal = enable;
    this.notify();
  }

  setReveal(centerX: number, centerY: number, radius: number): void {
    this.centerX = centerX;
    this.centerY = centerY;
    this.radius = radius;
    this.notify();
  }

  /** 当前裁剪 path 命令（关闭裁剪时为整块矩形） */
  clipCommands(): string {
    if (this.reveal) {
      const cmd: string = RevealGeometry.circlePath(this.centerX, this.centerY, this.radius);
      if (cmd.length > 0) {
        return cmd;
      }
    }
    const w: number = this.width > 0 ? this.width : 10000;
    const h: number = this.height > 0 ? this.height : 10000;
    return `M0,0 L${w},0 L${w},${h} L0,${h} Z`;
  }

  private notify(): void {
    if (this.redrawFn !== null) {
      this.redrawFn();
    }
  }
}

@Component
export struct RevealView {
  controller: RevealController = new RevealController();
  @BuilderParam content: () => void = this.empty;
  @State clipCmd: string = 'M0,0 L10000,0 L10000,10000 L0,10000 Z';

  @Builder
  empty(): void {
  }

  aboutToAppear(): void {
    this.controller.attach(() => {
      this.clipCmd = this.controller.clipCommands();
    });
  }

  aboutToDisappear(): void {
    this.controller.detach();
  }

  build() {
    Stack() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .clipShape(new Path({ commands: this.clipCmd }))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.controller.onSizeChanged(newValue.width as number, newValue.height as number);
    })
  }
}
