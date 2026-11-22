/*
 * 上游：app/src/main/java/com/hippo/scene/SceneFragment.java
 * 结构：场景基类（Fragment）—— 启动/结束场景、场景间结果回传、生命周期通知、返回键
 * 平台差异：
 *   - androidx Fragment 在 ArkUI 没有等价物：本类改为"场景控制器"（纯逻辑，无 UI），
 *     具体页面 = 一个 @Component 持有本类实例，把 aboutToAppear/onPageHide/onBackPress
 *     转发到这里的生命周期方法；
 *   - Fragment#getTag() → tag 字段（StageActivity 分配，递增字符串，与上游一致）；
 *   - Bundle → SceneArgs（Map<string, Object>）；
 *   - 阶段动画/共享元素：见 StageTransactor 与 TransitionHelper.ets。
 */
import {
  SceneArgs, StageHost, SceneTransitionHelper, SceneResultReceiver, SceneResultCode, LaunchMode
} from './SceneTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Announcer } from './Announcer';
import { LifeCircleScoped } from '../ehviewer/ui/annotation/DrawerLifeCircle';

export abstract class SceneFragment implements SceneResultReceiver {
  /** 上游 Fragment#getTag()：由 StageActivity 用自增整数分配 */
  private tag: string = '';
  /** 上游 getArguments() */
  args: SceneArgs | null = null;
  /** 上游 resultCode / result（场景间结果回传） */
  resultCode: number = SceneResultCode.CANCELED;
  result: SceneArgs | null = null;
  /** 上游 isDetached()：true = 被下层场景盖住（detach），不参与渲染 */
  detached: boolean = false;
  /** View 生命周期已走完（上游 onDestroyView） */
  viewDestroyed: boolean = false;

  /** 三个注解（@DrawerLifeCircle/@ViewLifeCircle/@WholeLifeCircle）的等价作用域成员（D-023） */
  private drawerScopes: LifeCircleScoped[] = [];
  private viewScopes: LifeCircleScoped[] = [];
  private wholeScopes: LifeCircleScoped[] = [];

  private requestSceneTagList: string[] = [];
  private requestCodeList: number[] = [];
  /** 所属 Stage（上游 getActivity() instanceof StageActivity 的等价物） */
  protected host: StageHost | null = null;

  /** 上游 abstract class 体里没有抽象方法，这里只要求子类给出场景名（注册键） */
  abstract getSceneName(): string;

  /** 上游 setTag（StageActivity#startScene 里 add(containerViewId, scene, tag) 实现） */
  setTag(tag: string): void {
    this.tag = tag;
  }

  getTag(): string {
    return this.tag;
  }

  setArguments(args: SceneArgs | null): void {
    this.args = args;
  }

  getArguments(): SceneArgs | null {
    return this.args;
  }

  bindHost(host: StageHost | null): void {
    this.host = host;
  }

  hasStageHost(): boolean {
    return this.host !== null;
  }

  // ---------------- 生命周期（由页面 @Component 转发） ----------------

  /** 上游 onNewArguments：SINGLE_TOP / SINGLE_TASK 复用已有场景时的参数刷新 */
  onNewArguments(args: SceneArgs): void {
  }

  /** 上游 onViewCreated */
  onSceneViewCreated(): void {
    this.viewDestroyed = false;
    if (this.host !== null) {
      this.host.notifySceneViewCreated(this);
    }
  }

  /** 上游 onDestroyView */
  onSceneViewDestroyed(): void {
    this.resetScopes(this.viewScopes);
    this.viewDestroyed = true;
    if (this.host !== null) {
      this.host.notifySceneViewDestroyed(this);
    }
  }

  /** 上游 onDestroy */
  onSceneDestroyed(): void {
    this.resetScopes(this.viewScopes);
    this.resetScopes(this.drawerScopes);
    this.resetScopes(this.wholeScopes);
    if (this.host !== null) {
      this.host.notifySceneDestroyed(this);
    }
  }

  // ---------------- 生命周期作用域（D-023：注解 → 显式持有者） ----------------

  /** 子类注册 @DrawerLifeCircle 等价的字段持有者 */
  protected trackDrawerScope(scope: LifeCircleScoped): void { this.drawerScopes.push(scope); }
  protected trackViewScope(scope: LifeCircleScoped): void { this.viewScopes.push(scope); }
  protected trackWholeScope(scope: LifeCircleScoped): void { this.wholeScopes.push(scope); }

  /** 上游抽屉关闭时把 @DrawerLifeCircle 字段置 null；StageActivity 的抽屉回调转发到这里 */
  onDrawerClosed(): void {
    this.resetScopes(this.drawerScopes);
  }

  private resetScopes(scopes: LifeCircleScoped[]): void {
    for (let i = 0; i < scopes.length; i++) {
      scopes[i].reset();
    }
  }

  /** 上游 onBackPressed（默认 finish） */
  onBackPressed(): void {
    this.finish();
  }

  /** 在出栈前拦截返回键（返回 true 表示已消费，例如关闭弹窗或退出多选）。 */
  tryConsumeBack(): boolean {
    return false;
  }

  // ---------------- 栈操作 ----------------

  startScene(announcer: Announcer): void {
    if (this.host !== null) {
      this.host.startSceneByName(announcer.sceneName, announcer.getArgs(),
        announcer.requestFrom !== null ? announcer.requestFrom.getTag() : null, announcer.requestCode);
    }
  }

  /**
   * 上游没有这个方法（Announcer#setRequestCode 是给调用方链式用的）；
   * 这里提供等价的便捷入口，语义同 "startScene(new Announcer(X).setRequestCode(this, code).setArgs(args))"。
   */
  startSceneForResult(announcer: Announcer, requestCode: number): void {
    announcer.setRequestCode(this, requestCode);
    this.startScene(announcer);
  }

  finish(): void {
    this.finishWithTransition(null);
  }

  finishWithTransition(transitionHelper: SceneTransitionHelper | null): void {
    const host: StageHost | null = this.host;
    if (host === null) {
      // 上游此处会 NPE 崩掉；ArkTS 下静默会表现为"点关闭没反应"，故显式告警
      hilog.warn(0x0000, 'SceneFragment', 'finish: host is null, scene may not be attached, tag=%{public}s', this.tag);
      return;
    }
    host.finishSceneByTag(this.tag, transitionHelper);
  }

  /** 上游 finishStage：关闭整个 Stage（单场景栈时等价于退出页面） */
  finishStage(): void {
    const host: StageHost | null = this.host;
    if (host !== null) {
      // StageActivity 侧实现：栈内只剩本场景时走 finish
      host.finishSceneByTag(this.tag, null);
    }
  }

  /** 上游 getStackIndex：不在栈内返回 -1 */
  getStackIndex(): number {
    if (this.host === null) {
      return -1;
    }
    return this.host.getSceneIndexByTag(this.tag);
  }

  // ---------------- 场景间结果回传 ----------------

  addRequest(requestSceneTag: string, requestCode: number): void {
    this.requestSceneTagList.push(requestSceneTag);
    this.requestCodeList.push(requestCode);
  }

  returnResult(host: StageHost): void {
    const size: number = Math.min(this.requestSceneTagList.length, this.requestCodeList.length);
    for (let i = 0; i < size; i++) {
      const tag: string = this.requestSceneTagList[i];
      const code: number = this.requestCodeList[i];
      const scene: SceneResultReceiver | null = host.findSceneByTag(tag);
      if (scene === null) {
        // 上游同样丢弃该结果；补 warn 以便排查"结果丢失"
        hilog.warn(0x0000, 'SceneFragment', 'returnResult: no scene with tag=%{public}s, requestCode=%{public}d', tag, code);
        continue;
      }
      scene.onSceneResult(code, this.resultCode, this.result);
    }
    this.requestSceneTagList = [];
    this.requestCodeList = [];
  }

  /** 子类覆盖以接收结果（上游 protected void onSceneResult） */
  onSceneResult(requestCode: number, resultCode: number, data: SceneArgs | null): void {
  }

  setResult(resultCode: number, result: SceneArgs | null): void {
    this.resultCode = resultCode;
    this.result = result;
  }

  /** 该场景当前是否是栈顶可见（StageLayout 排序/显示用） */
  isTopVisible(): boolean {
    return !this.detached && !this.viewDestroyed;
  }

  /** 上游 LAUNCH_MODE_* 常量转发，方便子类静态使用 */
  static readonly LAUNCH_MODE_STANDARD: number = LaunchMode.STANDARD;
  static readonly LAUNCH_MODE_SINGLE_TOP: number = LaunchMode.SINGLE_TOP;
  static readonly LAUNCH_MODE_SINGLE_TASK: number = LaunchMode.SINGLE_TASK;
  static readonly RESULT_CANCELED: number = SceneResultCode.CANCELED;
  static readonly RESULT_OK: number = SceneResultCode.OK;
}
