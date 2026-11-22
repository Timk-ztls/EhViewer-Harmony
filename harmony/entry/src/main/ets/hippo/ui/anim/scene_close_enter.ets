/**
 * 上游：app/src/main/res/anim/scene_close_enter.xml
 * 结构：set; alpha(0.7→1,duration=250,interpolator=@anim/decelerate_terz,fillBefore+fillAfter)
 * 平台差异：ArkUI 无 AnimationSet 资源，改为声明式参数对象（数值 1:1 搬自上游），由 SceneAnimator 驱动。
 */
import { DECELERATE_TERZ } from './decelerate_terz';

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

export const SCENE_CLOSE_ENTER: AnimSet = {
  name: 'scene_close_enter',
  shareInterpolator: false,
  items: [
    {
      property: 'alpha',
      from: 0.7,
      to: 1.0,
      unit: 'absolute',
      duration: 250,
      startOffset: 0,
      fillBefore: true,
      fillAfter: true,
      interpolatorName: './decelerate_terz',
      interpolatorType: 'decelerate',
      interpolatorFactor: 1.5
    },
  ]
};

export default SCENE_CLOSE_ENTER;
