/*
 * 上游：app/src/main/java/com/hippo/scene/SceneApplication.java
 * 结构：Application 子类，持有 IntIdGenerator + SparseArray<StageActivity>，负责 Stage 的注册/注销/查找
 * 平台差异：
 *  1. ArkTS 无 Application 子类（Stage 模型只有 Ability/AbilityStage），本类改为单例持有者，
 *     由 EntryAbility.onCreate 调用 SceneApplication.get().attach(context) 初始化（同 D-…/方案 §5-3：
 *     全局单例挂 AppStorage，不放在页面里）。
 *  2. SparseArray → Map<number, StageActivity>（core-runtime 已移植 Sparse 家族，但这里键是 stage id，
 *     非密集整数区间，Map 语义更直接）。
 *  3. 新增场景工厂注册表：Java 用 Class<?> + 反射实例化，ArkTS 无反射 → 显式 registerScene(name, factory)。
 */
import { IntIdGenerator } from '../lib/yorozuya/IntIdGenerator';
import { StageActivity } from './StageActivity';
import { SceneFragment } from './SceneFragment';

export type SceneFactory = () => SceneFragment;

export class SceneApplication {
  private static sInstance: SceneApplication | null = null;

  private readonly mIdGenerator: IntIdGenerator = new IntIdGenerator();
  private readonly mStageMap: Map<number, StageActivity> = new Map<number, StageActivity>();
  private readonly mSceneFactoryMap: Map<string, SceneFactory> = new Map<string, SceneFactory>();

  static get(): SceneApplication {
    if (SceneApplication.sInstance === null) {
      SceneApplication.sInstance = new SceneApplication();
    }
    return SceneApplication.sInstance;
  }

  // ---------------- 场景注册表（无反射的替代方案） ----------------

  /** 注册场景工厂；启动期由各页面模块集中调用（等价上游 StageActivity.registerLaunchMode 的时机） */
  registerScene(sceneName: string, factory: SceneFactory): void {
    if (this.mSceneFactoryMap.has(sceneName)) {
      throw new Error('The scene has been registered: ' + sceneName);
    }
    this.mSceneFactoryMap.set(sceneName, factory);
  }

  hasScene(sceneName: string): boolean {
    return this.mSceneFactoryMap.has(sceneName);
  }

  createScene(sceneName: string): SceneFragment {
    const factory: SceneFactory | undefined = this.mSceneFactoryMap.get(sceneName);
    if (factory === undefined) {
      throw new Error('The scene is not registered: ' + sceneName);
    }
    const scene: SceneFragment = factory();
    if (scene === null || scene === undefined) {
      throw new Error('The scene factory returned null: ' + sceneName);
    }
    return scene;
  }

  // ---------------- Stage 注册（上游 registerStageActivity 三件套） ----------------

  registerStageActivity(stage: StageActivity): void {
    const id: number = this.mIdGenerator.nextId();
    this.mStageMap.set(id, stage);
    stage.onRegister(id);
  }

  registerStageActivityWithId(stage: StageActivity, id: number): void {
    if (this.mStageMap.has(id)) {
      throw new Error('The id exists: ' + id);
    }
    this.mStageMap.set(id, stage);
    stage.onRegister(id);
  }

  unregisterStageActivity(id: number): void {
    const stage: StageActivity | undefined = this.mStageMap.get(id);
    if (stage !== undefined) {
      this.mStageMap.delete(id);
      stage.onUnregister();
    }
  }

  findStageActivityById(id: number): StageActivity | null {
    const stage: StageActivity | undefined = this.mStageMap.get(id);
    return stage === undefined ? null : stage;
  }

  /** 测试/调试用：当前 Stage 数量 */
  getStageCount(): number {
    return this.mStageMap.size;
  }
}
