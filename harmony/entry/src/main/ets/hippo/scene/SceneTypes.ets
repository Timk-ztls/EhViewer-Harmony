/*
 * 上游：无对应文件（ArkTS 扩展文件，用于打断 Java 里的循环引用）
 * Android 侧 SceneFragment ⇄ StageActivity ⇄ Announcer 三方互相引用，
 * 在 ArkTS 的 ES 模块下会形成环。这里把纯类型抽出来：
 *   SceneTypes(无依赖) → Announcer → SceneFragment → StageActivity → StageLayout
 * 依赖方向单一，无环。
 */

/**
 * 上游 android.os.Bundle → ArkTS：可序列化键值集合。
 * 取值只用 Object（string/number/boolean/Map/Array），跨线程（TaskPool）可直接传。
 */
export type SceneArgs = Map<string, Object>;

/**
 * 上游 SceneFragment.LaunchMode（@IntDef）。
 * Java 用 Class<?> 做键，ArkTS 无反射（方案 §5.1）→ 场景身份改为字符串 sceneName。
 */
export class LaunchMode {
  static readonly STANDARD: number = 0;
  static readonly SINGLE_TOP: number = 1;
  static readonly SINGLE_TASK: number = 2;
}

/** 上游 SceneFragment.RESULT_CANCELED / RESULT_OK（取值与 Android 一致） */
export class SceneResultCode {
  static readonly CANCELED: number = 0;
  static readonly OK: number = -1;
}

/** 上游 TransitionHelper#onTransition 的参数：把 FragmentTransaction 收敛成这一层 */
export interface StageTransactor {
  /**
   * 对应事务 setCustomAnimations(enterAnim, exitAnim) + attach/detach/remove。
   * open=true 用 anim/scene_open_enter + scene_open_exit；open=false 用 scene_close_enter + scene_close_exit。
   */
  applySceneAnimation(enterTag: string, exitTag: string, opening: boolean): void;
}

/**
 * 上游 androidx.fragment.app.Fragment 的引用收敛：
 * StageHost 是 SceneFragment 眼里的宿主（StageActivity 实现它），避免 SceneFragment ↔ StageActivity 环。
 */
export interface StageHost {
  /** 上游 StageActivity#startScene(Announcer) */
  startSceneByName(sceneName: string, args: SceneArgs | null, requestFromTag: string | null, requestCode: number): void;
  /** 上游 StageActivity#finishScene(SceneFragment, TransitionHelper) */
  finishSceneByTag(tag: string, transitionHelper: SceneTransitionHelper | null): void;
  /** 上游 StageActivity#getSceneIndex(SceneFragment) → 负数表示不在栈内 */
  getSceneIndexByTag(tag: string): number;
  /** 上游 StageActivity#onSceneViewCreated / onSceneViewDestroyed / onSceneDestroyed 的通知口 */
  notifySceneViewCreated(scene: SceneResultReceiver): void;
  notifySceneViewDestroyed(scene: SceneResultReceiver): void;
  notifySceneDestroyed(scene: SceneResultReceiver): void;
  /** 上游 StageActivity#findSceneByTag */
  findSceneByTag(tag: string): SceneResultReceiver | null;
}

/** 只暴露"回传结果"这一面，避免 StageHost 依赖 SceneFragment 具体类 */
export interface SceneResultReceiver {
  getTag(): string;
  onSceneResult(requestCode: number, resultCode: number, data: SceneArgs | null): void;
}

/**
 * 上游 TransitionHelper：自定义场景切换转场。
 * 返回 true 表示已自行处理转场（不再套默认动画）。
 */
export interface SceneTransitionHelper {
  onTransition(transactor: StageTransactor, exitTag: string, enterTag: string): boolean;
}
