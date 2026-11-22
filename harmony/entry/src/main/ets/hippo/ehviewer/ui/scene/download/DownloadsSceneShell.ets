/*
 * U-02c 样板：`DownloadsScene` 的外壳子类（上游是 Scene，我们现在是逻辑类 → 外壳补场景身份）。
 *
 * 约束（Lead 裁定）：外壳每行只能是
 *   ① extends / ② 委托给 logic 实例 / ③ 生命周期回调里的委托调用
 * 出现 if/循环/请求 → 那是逻辑，应该在 DownloadsScene 里。
 *
 * 依据（读 SceneFragment 得）：它只有 **一个** abstract 成员 `getSceneName()`；
 * 其余 34 个"missing properties" 不是"要你实现"，而是"逻辑类没有继承基类"（外壳靠继承自动获得）。
 * 所以外壳不需要搬任何成员。
 */
import { BaseScene } from '../BaseScene';
import { DownloadsScene } from './DownloadsScene';
import { DownloadManagerLike } from './DownloadsScene';

export class DownloadsSceneShell extends BaseScene {
  private readonly logic: DownloadsScene;

  constructor(downloadManager: DownloadManagerLike | null) {
    super();
    this.logic = new DownloadsScene(downloadManager);
  }

  getSceneName(): string {
    return 'DownloadsScene';
  }

  /** 组装层/渲染层取逻辑实例的唯一入口（外壳不复制它的方法） */
  getLogic(): DownloadsScene {
    return this.logic;
  }

  tryConsumeBack(): boolean {
    return this.logic.tryConsumeBack();
  }

  onBackPressed(): void {
    if (this.logic.tryConsumeBack()) {
      return;
    }
    super.onBackPressed();
  }
}
