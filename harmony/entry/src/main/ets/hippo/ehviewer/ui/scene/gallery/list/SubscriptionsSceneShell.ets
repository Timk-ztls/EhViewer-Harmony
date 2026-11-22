/*
 * U-02c：`SubscriptionsScene` 的外壳子类（模板同 DownloadsSceneShell，18 行）。
 * 约束：每行只能是 ① extends ② 委托给 logic ③ getSceneName/getLogic 纯标识与取实例。无 if/循环/请求。
 * 逻辑类自身构造参数较多，外壳把构造参数原样透传；组装层通过 getLogic() 取实例。
 */
import { BaseScene } from '../../BaseScene';
import { SubscriptionsScene } from './SubscriptionsScene';

export class SubscriptionsSceneShell extends BaseScene {
  private readonly logic: SubscriptionsScene;

  constructor(logic: SubscriptionsScene) {
    super();
    this.logic = logic;
  }

  getSceneName(): string {
    return 'SubscriptionsScene';
  }

  getLogic(): SubscriptionsScene {
    return this.logic;
  }
}