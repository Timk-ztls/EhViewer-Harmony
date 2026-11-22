/**
 * 上游：app/src/main/res/anim/cover_enter.xml
 * 结构：set shareInterpolator=false; alpha(0→1,220ms,decelerate_cubic) + scale(0.85→1,220ms,pivot 50%/50%,decelerate_cubic)
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

export const COVER_ENTER: AnimSet = {
  name: 'cover_enter',
  shareInterpolator: false,
  items: [
    {
      property: 'alpha',
      from: 0.0,
      to: 1.0,
      unit: 'absolute',
      duration: 220,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@ohos.anim.decelerate_cubic',
      interpolatorType: 'decelerate',
      interpolatorFactor: 2.0
    },
    {
      property: 'scaleX',
      from: 0.85,
      to: 1.0,
      unit: 'absolute',
      duration: 220,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@ohos.anim.decelerate_cubic',
      interpolatorType: 'decelerate',
      interpolatorFactor: 2.0
    },
    {
      property: 'scaleY',
      from: 0.85,
      to: 1.0,
      unit: 'absolute',
      duration: 220,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@ohos.anim.decelerate_cubic',
      interpolatorType: 'decelerate',
      interpolatorFactor: 2.0
    },
  ]
};

export default COVER_ENTER;
  // pivotX/pivotY = 50%/50%：缩放中心为组件中心，ArkUI 用 .centerX('50%').centerY('50%') 等价
