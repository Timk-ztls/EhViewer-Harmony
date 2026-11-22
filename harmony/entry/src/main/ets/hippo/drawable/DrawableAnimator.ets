/**
 * ui-widget · Drawable 动画节拍器（新增层，登记于 inventory/ui-widget.extra.txt 的 hippo/drawable/ 前缀）
 *
 * 上游 `ObjectAnimator.ofFloat(this, "progress", end).setDuration(d)` 的等价物：
 *   - 默认插值器 AccelerateDecelerateInterpolator = cubic-bezier(0.4, 0.0, 0.4, 1.0)
 *   - 16ms 一帧（≈60fps，与 Android Choreographer 同步）
 *   - setAutoCancel(true)：被打断时不再回调（本实现用 generation 代数校验）
 *
 * 为什么单独成文件：AddDeleteDrawable 与 DrawerArrowDrawable 都要跑 `setShape(delete/arrow, duration)`，
 * 两者动画语义完全相同（progress 线性推进 + 自动取消），抽出来避免两份 16ms 定时器逻辑漂移。
 */
export class DrawableAnimator {
  private timerId: number = -1;
  private generation: number = 0;

  /** AccelerateDecelerateInterpolator */
  private static interpolate(t: number): number {
    // cubic-bezier(0.4, 0.0, 0.4, 1.0)：与 PathInterpolator 同解的二分实现
    const x1: number = 0.4;
    const y1: number = 0.0;
    const x2: number = 0.4;
    const y2: number = 1.0;
    if (t <= 0) {
      return 0;
    }
    if (t >= 1) {
      return 1;
    }
    let lo: number = 0;
    let hi: number = 1;
    let u: number = t;
    for (let i = 0; i < 20; i++) {
      u = (lo + hi) / 2;
      const mu: number = 1 - u;
      const x: number = 3 * mu * mu * u * x1 + 3 * mu * u * u * x2 + u * u * u;
      if (x < t) {
        lo = u;
      } else {
        hi = u;
      }
    }
    const mu: number = 1 - u;
    return 3 * mu * mu * u * y1 + 3 * mu * u * u * y2 + u * u * u;
  }

  /**
   * @param from 起始值（上游 ObjectAnimator 会从当前属性值开始，此处显式传）
   * @param to 目标值
   * @param duration 时长 ms；<=0 表示立即到位（上游 setShape 的 duration<=0 分支）
   */
  start(from: number, to: number, duration: number,
        onUpdate: (v: number) => void, onEnd: (() => void) | null): void {
    this.cancel();
    if (duration <= 0) {
      onUpdate(to);
      if (onEnd !== null) {
        onEnd();
      }
      return;
    }
    this.generation = this.generation + 1;
    const gen: number = this.generation;
    const startTime: number = Date.now();
    this.timerId = setInterval(() => {
      if (gen !== this.generation) {
        return;
      }
      const frac: number = Math.min(1, (Date.now() - startTime) / duration);
      onUpdate(from + (to - from) * DrawableAnimator.interpolate(frac));
      if (frac >= 1) {
        this.cancel();
        if (onEnd !== null) {
          onEnd();
        }
      }
    }, 16);
  }

  /** 对位 setAutoCancel(true)：取消后不再回调 onUpdate/onEnd */
  cancel(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.generation = this.generation + 1;
  }
}
