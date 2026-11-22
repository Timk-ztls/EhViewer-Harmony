/*
 * 上游：app/src/main/java/com/hippo/scene/Announcer.java
 * 结构：场景启动参数封装（scene 类型 + 参数 + 转场 + 请求来源）
 * 平台差异：Java 用 Class<?> 标识场景，ArkTS 无反射（重构方案 §5.1）→ 改为 sceneName 字符串，
 *           由 SceneApplication.registerScene(sceneName, factory) 查表实例化。
 */
import { SceneArgs, SceneTransitionHelper, SceneResultReceiver } from './SceneTypes';

export class Announcer {
  readonly sceneName: string;
  args: SceneArgs | null = null;
  tranHelper: SceneTransitionHelper | null = null;
  requestFrom: SceneResultReceiver | null = null;
  requestCode: number = -1;
  private withResult: boolean = false;

  constructor(sceneName: string) {
    this.sceneName = sceneName;
  }

  getSceneName(): string {
    return this.sceneName;
  }

  setArgs(args: SceneArgs | null): Announcer {
    this.args = args;
    return this;
  }

  getArgs(): SceneArgs | null {
    return this.args;
  }

  setTranHelper(tranHelper: SceneTransitionHelper | null): Announcer {
    this.tranHelper = tranHelper;
    return this;
  }

  /**
   * 上游 setRequestCode(SceneFragment requestFrom, int requestCode)
   * 变体：SceneFragment#startSceneForResult(announcer, requestCode)（带结果回传的启动）
   */
  setRequestCode(requestFrom: SceneResultReceiver | null, requestCode: number): Announcer {
    this.requestFrom = requestFrom;
    this.requestCode = requestCode;
    this.withResult = requestFrom !== null;
    return this;
  }

  isStartForResult(): boolean {
    return this.withResult;
  }
}
