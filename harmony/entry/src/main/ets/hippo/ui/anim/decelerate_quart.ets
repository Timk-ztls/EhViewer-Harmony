/**
 * 上游：app/src/main/res/anim/decelerate_quart.xml
 * 结构：<decelerateInterpolator android:factor="2.0"/>
 * 平台差异：ArkUI 无插值器资源，改为声明式参数；type/factor 由 SceneAnimator 映射到 Curve（或自算进度曲线）。
 */
export interface InterpolatorSpec {
  readonly name: string;
  readonly type: string;
  readonly factor: number;
}

export const DECELERATE_QUART: InterpolatorSpec = {
  name: 'decelerate_quart',
  type: 'decelerate',
  factor: 2.0
};

export default DECELERATE_QUART;