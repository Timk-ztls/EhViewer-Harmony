/**
 * 上游：app/src/main/res/anim/decelerate_terz.xml
 * 结构：<decelerateInterpolator android:factor="1.5"/>
 * 平台差异：ArkUI 无插值器资源，改为声明式参数；type/factor 由 SceneAnimator 映射到 Curve（或自算进度曲线）。
 */
export interface InterpolatorSpec {
  readonly name: string;
  readonly type: string;
  readonly factor: number;
}

export const DECELERATE_TERZ: InterpolatorSpec = {
  name: 'decelerate_terz',
  type: 'decelerate',
  factor: 1.5
};

export default DECELERATE_TERZ;