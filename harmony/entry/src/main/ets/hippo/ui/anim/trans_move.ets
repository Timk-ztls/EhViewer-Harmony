/**
 * 上游：app/src/main/res/transition/trans_move.xml
 * 结构：<transitionSet> <changeTransform/> <changeBounds/> <changeImageTransform/>
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

export const TRANS_MOVE: TransitionSpec = {
  name: 'trans_move',
  items: [
    { type: 'changeTransform' },
    { type: 'changeBounds' },
    { type: 'changeImageTransform' },
  ]
};

export default TRANS_MOVE;
