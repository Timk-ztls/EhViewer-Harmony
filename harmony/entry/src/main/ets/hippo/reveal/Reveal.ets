/**
 * 迁移自 app/src/main/java/com/hippo/reveal/Reveal.java（inventory S0452，上游 20 行）
 *
 * 上游是纯接口，两个宿主（RevealView / RevealLinearLayout）用它实现"圆形揭示"裁剪。
 * ArkUI 对位：接口原样保留（ArkTS 接口与 Java 接口同构），宿主组件通过 controller 调用它。
 *
 * 与上游的一处必要差异：Java 里接口方法的调用方（ViewAnimationUtils）能直接拿到 View 强制转型；
 * ArkTS 无 View 体系，故实现者只暴露"设置裁剪参数"的语义，具体裁剪由宿主组件在 build 里用
 * `.clip(Path)` 完成（见 RevealView / RevealLinearLayout）。
 */
export interface Reveal {
  /** 上游 setRevealEnable(boolean)：开/关圆形裁剪 */
  setRevealEnable(enable: boolean): void;

  /** 上游 setReveal(centerX, centerY, radius)：更新裁剪圆 */
  setReveal(centerX: number, centerY: number, radius: number): void;
}

/** 圆形的 SVG path（ArkUI 用 Path 组件裁剪，等价 Android Path.addCircle + canvas.clipPath） */
export class RevealGeometry {
  /** 生成圆心 (cx,cy) 半径 r 的圆形 path 命令 */
  static circlePath(cx: number, cy: number, r: number): string {
    if (r <= 0) {
      return '';
    }
    // 两段半圆弧拼成整圆：M(cx-r,cy) a r,r 0 1,0 2r,0 a r,r 0 1,0 -2r,0
    return `M${cx - r},${cy} a${r},${r} 0 1,0 ${2 * r},0 a${r},${r} 0 1,0 ${-2 * r},0`;
  }
}
