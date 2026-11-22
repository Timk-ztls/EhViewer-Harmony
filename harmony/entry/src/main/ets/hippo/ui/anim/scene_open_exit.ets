/**
 * 上游：app/src/main/res/anim/scene_open_exit.xml
 * 结构：set; alpha(1→0.7,217ms,accelerate_decelerate,fillAfter)
 * 平台差异：ArkUI 无 AnimationSet 资源，改为声明式参数对象（数值 1:1 搬自上游），由 SceneAnimator 驱动。
 */
export interface AnimItem {
  /** alpha | translateX | translateY | scaleX | scaleY */
  readonly property: string;
  readonly from: number;
  readonly to: number;
  /** percent | absolute */
  readonly unit: string;
  readonly duration: number;
  readonly startOffset: number;
  readonly fillBefore: boolean;
  readonly fillAfter: boolean;
  readonly interpolatorName: string;
  readonly interpolatorType: string;
  readonly interpolatorFactor: number;
}

export interface AnimSet {
  readonly name: string;
  readonly shareInterpolator: boolean;
  readonly items: AnimItem[];
}

export const SCENE_OPEN_EXIT: AnimSet = {
  name: 'scene_open_exit',
  shareInterpolator: false,
  items: [
    {
      property: 'alpha',
      from: 1.0,
      to: 0.7,
      unit: 'absolute',
      duration: 217,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@android.interpolator.accelerate_decelerate',
      interpolatorType: 'accelerateDecelerate',
      interpolatorFactor: 1.0
    },
  ]
};

export default SCENE_OPEN_EXIT;
