/**
 * 上游：app/src/main/res/anim/pop_exit.xml
 * 结构：set; translate(fromXDelta=0,toXDelta=100%,duration=200)
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

export const POP_EXIT: AnimSet = {
  name: 'pop_exit',
  shareInterpolator: false,
  items: [
    {
      property: 'translateX',
      from: 0,
      to: 100,
      unit: 'percent',
      duration: 200,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@android.interpolator.accelerate_decelerate',
      interpolatorType: 'accelerateDecelerate',
      interpolatorFactor: 1.0
    },
  ]
};

export default POP_EXIT;
  // 上游未声明 interpolator → Android 默认 accelerateDecelerate
