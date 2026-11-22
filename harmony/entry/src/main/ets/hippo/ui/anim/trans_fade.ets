/**
 * 上游：app/src/main/res/transition/trans_fade.xml
 * 结构：<transitionSet> <fade/>
 * 平台差异：ArkUI 无 TransitionSet 资源；改为声明式清单，由页面切换处（Scene 基类）映射到
 *   .transition(TransitionEffect.OPACITY / .translate(...) / .scale(...) / geometryTransition(id))
 */
export interface TransitionItem {
  readonly type: string;
}

export interface TransitionSpec {
  readonly name: string;
  readonly items: TransitionItem[];
}

export const TRANS_FADE: TransitionSpec = {
  name: 'trans_fade',
  items: [
    { type: 'fade' },
  ]
};

export default TRANS_FADE;
