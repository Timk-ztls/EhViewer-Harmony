/**
 * 迁移自 app/src/main/java/com/hippo/reveal/ViewAnimationUtils.java（inventory S0455，上游 91 行）
 *
 * 上游逻辑：
 *   API_SUPPORT_CIRCULAR_REVEAL  = SDK >= 21
 *   API_SUPPORT_CANVAS_CLIP_PATH = SDK >= 18
 *   createCircularReveal(view, cx, cy, startR, endR)：
 *     >=21 → 系统 ViewAnimationUtils.createCircularReveal
 *     <21 且 view 实现 Reveal → 自建 ValueAnimator(startR→endR)，每帧 setReveal(cx,cy,r)；
 *         开始 setRevealEnable(true)，结束 setRevealEnable(false)
 *     <21 且未实现 Reveal → 抛 IllegalStateException
 *
 * 鸿蒙侧无 SDK 版本分支（两种能力都可用），保留同名常量以对齐调用点，语义为"总是支持"。
 * 等价实现 = 对实现 Reveal 的宿主跑同一条半径序列，每帧 setReveal；
 * 每帧节拍用 16ms 定时器（≈60fps，与上游 ValueAnimator 帧率一致），
 * 结束时关掉裁剪（对位 onAnimationEnd 的 setRevealEnable(false)）。
 */
import { Reveal } from './Reveal';

export class ViewAnimationUtils {
  private constructor() {
  }

  /** 鸿蒙侧恒为 true（上游为 SDK>=21 判断） */
  static readonly API_SUPPORT_CIRCULAR_REVEAL: boolean = true;
  /** 鸿蒙侧恒为 true（上游为 SDK>=18 判断） */
  static readonly API_SUPPORT_CANVAS_CLIP_PATH: boolean = true;

  /**
   * 上游 createCircularReveal 的等价物：半径线性插值 + 每帧 setReveal。
   * @param duration 上游由调用方 setDuration() 指定，此处必传（毫秒）
   * @returns 停止函数（对位 Animator.cancel()）
   */
  static animateCircularReveal(reveal: Reveal, centerX: number, centerY: number,
                               startRadius: number, endRadius: number, duration: number): () => void {
    reveal.setRevealEnable(true);
    reveal.setReveal(centerX, centerY, startRadius);
    const startTime: number = Date.now();
    const timerId: number = setInterval(() => {
      const elapsed: number = Date.now() - startTime;
      const frac: number = duration <= 0 ? 1 : Math.min(1, elapsed / duration);
      reveal.setReveal(centerX, centerY, ViewAnimationUtils.radiusAt(startRadius, endRadius, frac));
      if (frac >= 1) {
        clearInterval(timerId);
        // 对位 onAnimationEnd：关闭裁剪，恢复完整绘制
        reveal.setRevealEnable(false);
      }
    }, 16);
    return (): void => {
      clearInterval(timerId);
      reveal.setRevealEnable(false);
    };
  }

  /** 半径线性插值（对位 ValueAnimator.ofFloat(startRadius,endRadius) 的取值） */
  static radiusAt(startRadius: number, endRadius: number, fraction: number): number {
    const f: number = fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction);
    return startRadius + (endRadius - startRadius) * f;
  }
}
