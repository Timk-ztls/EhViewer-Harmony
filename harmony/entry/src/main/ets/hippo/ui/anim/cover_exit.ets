/**
 * 上游：app/src/main/res/anim/cover_exit.xml
 * 结构：set shareInterpolator=false; alpha(1→0,180ms,accelerate_cubic) + scale(1→0.85,180ms,pivot 50%/50%,accelerate_cubic)
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

export const COVER_EXIT: AnimSet = {
  name: 'cover_exit',
  shareInterpolator: false,
  items: [
    {
      property: 'alpha',
      from: 1.0,
      to: 0.0,
      unit: 'absolute',
      duration: 180,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@ohos.anim.accelerate_cubic',
      interpolatorType: 'accelerate',
      interpolatorFactor: 2.0
    },
    {
      property: 'scaleX',
      from: 1.0,
      to: 0.85,
      unit: 'absolute',
      duration: 180,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@ohos.anim.accelerate_cubic',
      interpolatorType: 'accelerate',
      interpolatorFactor: 2.0
    },
    {
      property: 'scaleY',
      from: 1.0,
      to: 0.85,
      unit: 'absolute',
      duration: 180,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@ohos.anim.accelerate_cubic',
      interpolatorType: 'accelerate',
      interpolatorFactor: 2.0
    },
  ]
};

export default COVER_EXIT;
  // pivotX/pivotY = 50%/50%：缩放中心为组件中心
