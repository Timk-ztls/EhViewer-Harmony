/**
 * 上游：app/src/main/res/anim/scene_open_enter.xml
 * 结构：set shareInterpolator=false; alpha(0→1,200ms,@anim/decelerate_quart) + translate(8%→0,350ms,@anim/decelerate_quint)
 * 平台差异：ArkUI 无 AnimationSet 资源，改为声明式参数对象（数值 1:1 搬自上游），由 SceneAnimator 驱动。
 */
import { DECELERATE_QUART } from './decelerate_quart';
import { DECELERATE_QUINT } from './decelerate_quint';

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

export const SCENE_OPEN_ENTER: AnimSet = {
  name: 'scene_open_enter',
  shareInterpolator: false,
  items: [
    {
      property: 'alpha',
      from: 0.0,
      to: 1.0,
      unit: 'absolute',
      duration: 200,
      startOffset: 0,
      fillBefore: false,
      fillAfter: true,
      interpolatorName: './decelerate_quart',
      interpolatorType: 'decelerate',
      interpolatorFactor: 2.0
    },
    {
      property: 'translateY',
      from: 8,
      to: 0,
      unit: 'percent',
      duration: 350,
      startOffset: 0,
      fillBefore: true,
      fillAfter: true,
      interpolatorName: './decelerate_quint',
      interpolatorType: 'decelerate',
      interpolatorFactor: 2.5
    },
  ]
};

export default SCENE_OPEN_ENTER;
