/**
 * 上游：app/src/main/res/anim/scene_close_exit.xml
 * 结构：set shareInterpolator=false; alpha(1→0,startOffset=100,150ms,linear) + translate(0%→8%,250ms,@anim/accelerate_quart)
 * 平台差异：ArkUI 无 AnimationSet 资源，改为声明式参数对象（数值 1:1 搬自上游），由 SceneAnimator 驱动。
 */
import { ACCELERATE_QUART } from './accelerate_quart';

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

export const SCENE_CLOSE_EXIT: AnimSet = {
  name: 'scene_close_exit',
  shareInterpolator: false,
  items: [
    {
      property: 'alpha',
      from: 1.0,
      to: 0.0,
      unit: 'absolute',
      duration: 150,
      startOffset: 100,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: '@android.interpolator.linear',
      interpolatorType: 'linear',
      interpolatorFactor: 1.0
    },
    {
      property: 'translateY',
      from: 0,
      to: 8,
      unit: 'percent',
      duration: 250,
      startOffset: 0,
      fillBefore: true,
      fillAfter: true,
      interpolatorName: './accelerate_quart',
      interpolatorType: 'accelerate',
      interpolatorFactor: 2.0
    },
  ]
};

export default SCENE_CLOSE_EXIT;
