/*
 * 上游：app/src/main/java/com/hippo/scene/StageActivity.java（527 行）
 * 结构：场景栈宿主 —— startScene / startSceneFirstly / finishScene / refreshTopScene / onBackPressed、
 *       LaunchMode（STANDARD / SINGLE_TOP / SINGLE_TASK）、场景间结果回传、Stage 生命周期回调
 * 平台差异（均为不可等价项，已在 MR 逐条登记）：
 *  1. androidx FragmentManager/FragmentTransaction 在 ArkUI 无等价物 → 事务三件套
 *     (add/attach/detach/remove) 改为对 scenes/tagList 的直接状态变更；
 *     转场动画不再由事务携带，而是记录到 pendingAnimation，由 StageLayout 用 .transition() 套用。
 *  2. 反射类不可用：上游 Class.forName(KEY_SCENE_NAME) + newInstance → sceneName 字符串 +
 *     SceneApplication 工厂注册表（方案 §5-1）。
 *  3. AtomicInteger（场景 tag 生成）→ 普通 number（同 IntIdGenerator 移植说明：不跨 Worker 共享）。
 *  4. getSupportFragmentManager().findFragmentByTag → scenes Map。
 *  5. applyOverrideConfiguration（uiMode 覆盖）无对应物：ArkUI 由 @ohos.app.ability.Configuration
 *     在 Ability 层处理，本类不参与。
 */
import { IntIdGenerator } from '../lib/yorozuya/IntIdGenerator';
import { Announcer } from './Announcer';
import { SceneFragment } from './SceneFragment';
import { SceneApplication } from './SceneApplication';
import {
  LaunchMode, SceneArgs, SceneResultReceiver, SceneTransitionHelper, StageHost, StageTransactor
} from './SceneTypes';

/** 待应用的场景切换动画（上游 FragmentTransaction#setCustomAnimations 的等价物） */
export class PendingAnimation {
  readonly enterTag: string;
  readonly exitTag: string;
  /** true = 场景打开（scene_open_enter/exit）；false = 场景关闭（scene_close_enter/exit） */
  readonly opening: boolean;
  constructor(enterTag: string, exitTag: string, opening: boolean) {
    this.enterTag = enterTag;
    this.exitTag = exitTag;
    this.opening = opening;
  }
}

export abstract class StageActivity implements StageHost, StageTransactor {
  // 上游 KEY_* 常量（状态保存用）
  static readonly ACTION_START_SCENE: string = 'start_scene';
  static readonly KEY_SCENE_NAME: string = 'stage_activity_scene_name';
  static readonly KEY_SCENE_ARGS: string = 'stage_activity_scene_args';
  static readonly KEY_STAGE_ID: string = 'stage_activity_stage_id';
  static readonly KEY_SCENE_TAG_LIST: string = 'stage_activity_scene_tag_list';
  static readonly KEY_NEXT_ID: string = 'stage_activity_next_id';

  private static readonly sLaunchModeMap: Map<string, number> = new Map<string, number>();

  /** 上游 registerLaunchMode(Class<?>, @LaunchMode int) */
  static registerLaunchMode(sceneName: string, launchMode: number): void {
    if (launchMode !== LaunchMode.STANDARD && launchMode !== LaunchMode.SINGLE_TOP &&
      launchMode !== LaunchMode.SINGLE_TASK) {
      throw new Error('Invalid launch mode: ' + launchMode);
    }
    StageActivity.sLaunchModeMap.set(sceneName, launchMode);
  }

  /** 栈内 tag，按插入序（栈底 → 栈顶） */
  protected readonly sceneTagList: string[] = [];
  /** 渲染顺序 tag（上游 mDelaySceneTagList：被移除的场景要等动画结束才从渲染序里消失） */
  protected readonly delaySceneTagList: string[] = [];
  protected readonly scenes: Map<string, SceneFragment> = new Map<string, SceneFragment>();
  /** 上游 AtomicInteger mIdGenerator（生成 scene tag） */
  private nextSceneTag: number = 0;
  private stageId: number = IntIdGenerator.INVALID_ID;
  private pendingAnimation: PendingAnimation | null = null;
  private attachedToApplication: boolean = false;

  // ---------------- 子类必须实现（上游 abstract） ----------------

  /** 上游 getContainerViewId()：ArkUI 无 view id，改为返回 StageLayout 的容器键 */
  abstract getContainerViewId(): string;

  /** 上游 abstract Announcer getLaunchAnnouncer()：MAIN 启动时的首个场景 */
  abstract getLaunchAnnouncer(): Announcer | null;

  // ---------------- 生命周期 ----------------

  /** 上游 final onCreate(savedInstanceState)：Stage 注册 + 恢复状态 + 首个场景 */
  createStage(savedInstanceState: SceneArgs | null): void {
    if (savedInstanceState !== null) {
      const idValue: Object | undefined = savedInstanceState.get(StageActivity.KEY_STAGE_ID);
      if (idValue !== undefined && typeof idValue === 'number') {
        this.stageId = idValue as number;
      }
      const tagListValue: Object | undefined = savedInstanceState.get(StageActivity.KEY_SCENE_TAG_LIST);
      if (tagListValue !== undefined && Array.isArray(tagListValue)) {
        const list: string[] = tagListValue as string[];
        for (let i = 0; i < list.length; i++) {
          this.sceneTagList.push(list[i]);
          this.delaySceneTagList.push(list[i]);
        }
      }
      const nextIdValue: Object | undefined = savedInstanceState.get(StageActivity.KEY_NEXT_ID);
      if (nextIdValue !== undefined && typeof nextIdValue === 'number') {
        this.nextSceneTag = nextIdValue as number;
      }
    }

    if (this.stageId === IntIdGenerator.INVALID_ID) {
      SceneApplication.get().registerStageActivity(this);
    } else {
      SceneApplication.get().registerStageActivityWithId(this, this.stageId);
    }
    this.attachedToApplication = true;

    // 上游 onCreate2(savedInstanceState)：子类在这里挂 StageLayout
    this.onCreateStage(savedInstanceState);

    if (savedInstanceState === null) {
      const announcer: Announcer | null = this.getLaunchAnnouncer();
      if (announcer !== null) {
        this.startScene(announcer);
      }
    }
  }

  /** 上游 abstract onCreate2(Bundle)：子类在此时 setContentView */
  protected abstract onCreateStage(savedInstanceState: SceneArgs | null): void;

  /** 上游 onSaveInstanceState */
  saveState(): SceneArgs {
    const state: SceneArgs = new Map<string, Object>();
    state.set(StageActivity.KEY_STAGE_ID, this.stageId);
    state.set(StageActivity.KEY_SCENE_TAG_LIST, this.sceneTagList.slice());
    state.set(StageActivity.KEY_NEXT_ID, this.nextSceneTag);
    return state;
  }

  /** 上游 onDestroy */
  destroyStage(): void {
    for (const scene of this.scenes.values()) {
      scene.onSceneDestroyed();
    }
    this.scenes.clear();
    if (this.attachedToApplication) {
      SceneApplication.get().unregisterStageActivity(this.stageId);
      this.attachedToApplication = false;
    }
  }

  onRegister(id: number): void {
    this.stageId = id;
  }

  onUnregister(): void {
  }

  /** 上游 onTransactScene：每次场景事务后的钩子（子类用来刷新 UI 状态） */
  protected onTransactScene(): void {
  }

  // ---------------- StageHost 通知 ----------------

  notifySceneViewCreated(scene: SceneResultReceiver): void {
    const s: SceneFragment | null = this.findSceneByTag(scene.getTag());
    if (s !== null) {
      this.onSceneViewCreated(s);
    }
  }

  notifySceneViewDestroyed(scene: SceneResultReceiver): void {
    const s: SceneFragment | null = this.findSceneByTag(scene.getTag());
    if (s !== null) {
      this.onSceneViewDestroyed(s);
    }
  }

  notifySceneDestroyed(scene: SceneResultReceiver): void {
    const s: SceneFragment | null = this.findSceneByTag(scene.getTag());
    if (s !== null) {
      this.onSceneDestroyed(s);
    }
  }

  /** 上游 public void onSceneViewCreated(SceneFragment, Bundle)：子类可覆盖 */
  onSceneViewCreated(scene: SceneFragment): void {
  }

  /** 上游 public void onSceneViewDestroyed(SceneFragment) */
  onSceneViewDestroyed(scene: SceneFragment): void {
  }

  /** 上游 void onSceneDestroyed(SceneFragment) */
  onSceneDestroyed(scene: SceneFragment): void {
    const index: number = this.delaySceneTagList.indexOf(scene.getTag());
    if (index >= 0) {
      this.delaySceneTagList.splice(index, 1);
    }
  }

  // ---------------- 查询 ----------------

  getStageId(): number {
    return this.stageId;
  }

  /** 栈内 tag 快照（StageLayout 绑定用） */
  getSceneTagList(): string[] {
    return this.sceneTagList.slice();
  }

  getSceneCount(): number {
    return this.sceneTagList.length;
  }

  getSceneLaunchMode(sceneName: string): number {
    const mode: number | undefined = StageActivity.sLaunchModeMap.get(sceneName);
    if (mode === undefined) {
      throw new Error('Not register ' + sceneName);
    }
    return mode;
  }

  getSceneIndexByTag(tag: string): number {
    return this.getTagIndex(tag);
  }

  getTagIndex(tag: string): number {
    return this.sceneTagList.indexOf(tag);
  }

  findSceneByTag(tag: string): SceneFragment | null {
    const scene: SceneFragment | undefined = this.scenes.get(tag);
    return scene === undefined ? null : scene;
  }

  findSceneByName(sceneName: string): SceneFragment | null {
    const top: string[] = this.sceneTagList;
    for (let i = top.length - 1; i >= 0; i--) {
      const s: SceneFragment | undefined = this.scenes.get(top[i]);
      if (s !== undefined && s.getSceneName() === sceneName) {
        return s;
      }
    }
    return null;
  }

  /** 上游 getTopSceneClass()：返回栈顶场景名（ArkTS 无 Class 对象） */
  getTopSceneName(): string | null {
    const index: number = this.sceneTagList.length - 1;
    if (index < 0) {
      return null;
    }
    const s: SceneFragment | null = this.findSceneByTag(this.sceneTagList[index]);
    return s === null ? null : s.getSceneName();
  }

  /** 渲染顺序（上游 mDelaySceneTagList 的语义）：StageLayout 按此顺序绘制，后进先出 */
  getRenderOrder(): string[] {
    return this.delaySceneTagList.slice();
  }

  /** 取走并清空待应用动画（StageLayout 调用一次即消费） */
  consumePendingAnimation(): PendingAnimation | null {
    const pending: PendingAnimation | null = this.pendingAnimation;
    this.pendingAnimation = null;
    return pending;
  }

  sortSceneTags(tags: string[]): string[] {
    tags.sort((lhs: string, rhs: string): number => {
      return this.delaySceneTagList.indexOf(lhs) - this.delaySceneTagList.indexOf(rhs);
    });
    return tags;
  }

  // ---------------- StageTransactor（事务动画） ----------------

  applySceneAnimation(enterTag: string, exitTag: string, opening: boolean): void {
    this.pendingAnimation = new PendingAnimation(enterTag, exitTag, opening);
  }

  // ---------------- 场景启动 ----------------

  private newSceneInstance(sceneName: string): SceneFragment {
    return SceneApplication.get().createScene(sceneName);
  }

  /** 上游 startScene(Announcer) */
  startScene(announcer: Announcer): void {
    const sceneName: string = announcer.sceneName;
    const args: SceneArgs | null = announcer.args;
    const tranHelper: SceneTransitionHelper | null = announcer.tranHelper;
    const launchMode: number = this.getSceneLaunchMode(sceneName);

    // LAUNCH_MODE_SINGLE_TASK：栈内已有同类型场景 → 复用并清掉其上的场景
    if (launchMode === LaunchMode.SINGLE_TASK) {
      const count: number = this.sceneTagList.length;
      for (let i = 0; i < count; i++) {
        const tag: string = this.sceneTagList[i];
        const scene: SceneFragment | null = this.findSceneByTag(tag);
        if (scene === null) {
          continue;
        }
        if (scene.getSceneName() === sceneName) {
          // 默认动画
          this.pendingAnimation = new PendingAnimation(tag, '', true);
          // 摘掉其上所有场景
          for (let j = i + 1; j < count; j++) {
            const topTag: string = this.sceneTagList[j];
            const topScene: SceneFragment | null = this.findSceneByTag(topTag);
            if (topScene === null) {
              continue;
            }
            this.scenes.delete(topTag);
          }
          this.sceneTagList.splice(i + 1, this.sceneTagList.length - (i + 1));
          // 重新挂上
          scene.detached = false;
          this.onTransactScene();
          if (args !== null) {
            scene.onNewArguments(args);
          }
          return;
        }
      }
    }

    // 当前栈顶场景
    let currentScene: SceneFragment | null = null;
    if (this.sceneTagList.length > 0) {
      const tag: string = this.sceneTagList[this.sceneTagList.length - 1];
      currentScene = this.findSceneByTag(tag);
    }

    // LAUNCH_MODE_SINGLE_TOP
    if (currentScene !== null && currentScene.getSceneName() === sceneName &&
      launchMode === LaunchMode.SINGLE_TOP) {
      if (args !== null) {
        currentScene.onNewArguments(args);
      }
      return;
    }

    // 新场景
    const newScene: SceneFragment = this.newSceneInstance(sceneName);
    newScene.setArguments(args);
    newScene.bindHost(this);

    const newTag: string = this.nextSceneTag.toString();
    this.nextSceneTag++;

    this.sceneTagList.push(newTag);
    this.delaySceneTagList.push(newTag);
    this.scenes.set(newTag, newScene);
    newScene.setTag(newTag);

    if (currentScene !== null) {
      // 转场：自定义优先，否则默认动画
      const handled: boolean = tranHelper !== null &&
        tranHelper.onTransition(this, currentScene.getTag(), newTag);
      if (!handled) {
        this.applySceneAnimation(newTag, currentScene.getTag(), true);
      }
      // detach 当前场景
      currentScene.detached = true;
    }

    this.onTransactScene();

    // 结果回传登记
    if (announcer.requestFrom !== null) {
      newScene.addRequest(announcer.requestFrom.getTag(), announcer.requestCode);
    }
  }

  /** StageHost 实现：按 sceneName 启动（SceneFragment#startScene 的入口） */
  startSceneByName(sceneName: string, args: SceneArgs | null,
                   requestFromTag: string | null, requestCode: number): void {
    const announcer: Announcer = new Announcer(sceneName).setArgs(args);
    if (requestFromTag !== null) {
      const from: SceneFragment | null = this.findSceneByTag(requestFromTag);
      if (from !== null) {
        announcer.setRequestCode(from, requestCode);
      }
    }
    this.startScene(announcer);
  }

  /** 上游 startSceneFirstly(Announcer)：清栈后只保留目标场景 */
  startSceneFirstly(announcer: Announcer): void {
    const sceneName: string = announcer.sceneName;
    const args: SceneArgs | null = announcer.args;
    const launchMode: number = this.getSceneLaunchMode(sceneName);
    const forceNewScene: boolean = launchMode === LaunchMode.STANDARD;
    let createNewScene: boolean = true;
    let findScene: boolean = false;
    let scene: SceneFragment | null = null;
    let findSceneTag: string | null = null;

    // 默认动画（上游在事务开头就设，即使中途被覆盖）
    const count: number = this.sceneTagList.length;
    for (let i = 0; i < count; i++) {
      const tag: string = this.sceneTagList[i];
      const fragment: SceneFragment | null = this.findSceneByTag(tag);
      if (fragment === null) {
        continue;
      }
      if (!forceNewScene && !findScene && fragment.getSceneName() === sceneName &&
        (launchMode === LaunchMode.SINGLE_TASK || !fragment.detached)) {
        scene = fragment;
        findScene = true;
        createNewScene = false;
        findSceneTag = tag;
        fragment.detached = false;
      } else {
        // 移除
        fragment.onSceneDestroyed();
        this.scenes.delete(tag);
        const delayIndex: number = this.delaySceneTagList.indexOf(tag);
        if (delayIndex >= 0) {
          this.delaySceneTagList.splice(delayIndex, 1);
        }
      }
    }

    this.sceneTagList.splice(0, this.sceneTagList.length);
    if (findSceneTag !== null) {
      this.sceneTagList.push(findSceneTag);
    }

    if (createNewScene) {
      const created: SceneFragment = this.newSceneInstance(sceneName);
      created.setArguments(args);
      created.bindHost(this);
      const tag: string = this.nextSceneTag.toString();
      this.nextSceneTag++;
      this.sceneTagList.push(tag);
      this.delaySceneTagList.push(tag);
      this.scenes.set(tag, created);
      created.setTag(tag);
      scene = created;
      this.applySceneAnimation(tag, '', true);
    }

    this.onTransactScene();

    if (!createNewScene && args !== null && scene !== null) {
      scene.onNewArguments(args);
    }
  }

  // ---------------- 场景结束 ----------------

  /** 上游 finishScene(SceneFragment, TransitionHelper) */
  finishScene(scene: SceneFragment, transitionHelper: SceneTransitionHelper | null): void {
    this.finishSceneByTag(scene.getTag(), transitionHelper);
  }

  /** StageHost 实现 */
  finishSceneByTag(tag: string, transitionHelper: SceneTransitionHelper | null): void {
    const scene: SceneFragment | null = this.findSceneByTag(tag);
    if (scene === null) {
      return;
    }

    const index: number = this.sceneTagList.indexOf(tag);
    if (index < 0) {
      return;
    }

    // 栈里只剩这一个场景 → 结束 Stage
    if (this.sceneTagList.length === 1) {
      this.onFinishStage();
      return;
    }

    let next: SceneFragment | null = null;
    if (index === this.sceneTagList.length - 1) {
      // 栈顶 → 显示下一层
      next = this.findSceneByTag(this.sceneTagList[index - 1]);
    }

    if (next !== null) {
      const handled: boolean = transitionHelper !== null &&
        transitionHelper.onTransition(this, tag, next.getTag());
      if (!handled) {
        this.applySceneAnimation(next.getTag(), tag, false);
      }
      next.detached = false;
    }

    // 移除
    this.scenes.delete(tag);
    scene.bindHost(null);
    scene.onSceneDestroyed();

    this.onTransactScene();

    this.sceneTagList.splice(index, 1);

    // 结果回传
    scene.returnResult(this);
  }

  /** 上游 finish()（Activity 层）：子类接 EntryAbility 的 terminateSelf */
  protected onFinishStage(): void {
  }

  /** 上游 refreshTopScene：强制重建栈顶场景（detach + attach） */
  refreshTopScene(): void {
    const index: number = this.sceneTagList.length - 1;
    if (index < 0) {
      return;
    }
    const tag: string = this.sceneTagList[index];
    const scene: SceneFragment | null = this.findSceneByTag(tag);
    if (scene === null) {
      return;
    }
    scene.onSceneViewDestroyed();
    scene.detached = true;
    scene.detached = false;
    scene.onSceneViewCreated();
    this.applySceneAnimation(tag, tag, true);
    this.onTransactScene();
  }

  /** 上游 onBackPressed：交给栈顶场景处理 */
  onBackPressed(): void {
    const size: number = this.sceneTagList.length;
    if (size === 0) {
      return;
    }
    const tag: string = this.sceneTagList[size - 1];
    const scene: SceneFragment | null = this.findSceneByTag(tag);
    if (scene === null) {
      return;
    }
    scene.onBackPressed();
  }
}
