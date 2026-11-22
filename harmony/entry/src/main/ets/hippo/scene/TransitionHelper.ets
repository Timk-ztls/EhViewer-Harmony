/*
 * 上游：app/src/main/java/com/hippo/scene/TransitionHelper.java
 * 结构：interface { boolean onTransition(Context, FragmentTransaction, Fragment exit, Fragment enter) }
 * 平台差异：ArkUI 无 FragmentTransaction；转场参数收敛到 StageTransactor（见 SceneTypes.ets），
 *           实现方只需声明"用哪套动画 + 谁进谁出"。上游自定义转场（如 gallery 的共享元素）
 *           在 ArkUI 对应 geometryTransition(id)，实现类在具体 Scene 里提供。
 */
import { SceneTransitionHelper, StageTransactor } from './SceneTypes';

/** 默认转场：等同上游"不回 true"——由 StageActivity 套 scene_open_* / scene_close_* 动画 */
export class DefaultTransitionHelper implements SceneTransitionHelper {
  onTransition(transactor: StageTransactor, exitTag: string, enterTag: string): boolean {
    // false = 不接管，交回 StageActivity 套默认动画（与上游语义一致）
    return false;
  }
}

/** 共享元素转场占位实现：上游用 sharedElementEnterTransition，ArkUI 用 geometryTransition */
export class SharedElementTransitionHelper implements SceneTransitionHelper {
  readonly sharedId: string;

  constructor(sharedId: string) {
    this.sharedId = sharedId;
  }

  onTransition(transactor: StageTransactor, exitTag: string, enterTag: string): boolean {
    // 已接管：调用方据此跳过默认动画；geometryTransition 绑定由两个 Scene 的组件各自声明
    transactor.applySceneAnimation(enterTag, exitTag, true);
    return true;
  }
}
