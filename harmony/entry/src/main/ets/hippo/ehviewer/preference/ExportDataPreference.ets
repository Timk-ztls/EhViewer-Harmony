/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/preference/ExportDataPreference.java（S0168，上游 67 行）
 *
 * 判据：**UI 组件行**（`extends TaskPreference`），自有逻辑只有 `onCreateTask()` 返回 `ExportDataTask`
 *   （`doInBackground` 组装数据、`onPostExecute` 处理结果）。**任务编排归基类**。
 *
 * ⚠ 修正（编译暴露的真实问题）：`TaskPreference` 在本仓库是**纯逻辑静态类**
 *   （`normalizeProgress` / `startTask` / `finishTask`，`export class TaskPreference`），
 *   **不是 `@Component`** ⇒ 不能写成 `TaskPreference({...})` 组件调用。
 *   正确形态是**组合**：本组件自己渲染（`SettingsItem` 行 + 进度行），逻辑走 `TaskPreference` 的静态方法。
 *   （这与 `CleanRedundancyPreference` / `VersionPreference` / `RestoreDownloadPreference` 三个
 *   `export class` 的逻辑类一致 —— 它们是"无头逻辑"，UI 由各自的组件承接。）
 *
 * 断言重点：`normalizeProgress` 的 indeterminate 分支（total<=0）与 clamp 上下界。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeDimens, ThemePalette, ThemeTokens } from '../../../common/theme/ThemeTokens';
import { SettingsItem } from '../../ui/settings/SettingsItem';
import { GetText } from '../GetText';
import { TaskPreference, TaskProgress } from './TaskPreference';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ExportDataPreference';

@Component
export struct ExportDataPreference {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  /** 对位 onCreateTask()：任务体（组装 + 落盘由调用方提供，属 core-runtime + storage-db） */
  runExport: () => Promise<boolean> = async (): Promise<boolean> => false;
  onFinished: (ok: boolean) => void = (ok: boolean) => {
  };
  @State running: boolean = false;
  @State progress: TaskProgress = new TaskProgress();
  @State rev: number = 0;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private loadingSummary(): string {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      if (!GetText.isInitialized()) {
        GetText.initialize(ctx);
      }
      try {
        return ctx.resourceManager.getStringByNameSync('loading');
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'resolve loading string failed: %{public}s', msg);
      }
    }
    return GetText.getString('loading');
  }

  private async start(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.progress = TaskPreference.normalizeProgress(0, 0); // 启动时未知总量 → indeterminate
    this.rev = this.rev + 1;
    let ok: boolean = false;
    try {
      ok = await this.runExport();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'runExport failed: %{public}s', msg);
      ok = false;
    }
    this.running = false;
    this.progress = TaskPreference.normalizeProgress(1, 1); // 结束：确定态满值（避免停在 indeterminate）
    this.rev = this.rev + 1;
    this.onFinished(ok);
  }

  build() {
    Column() {
      SettingsItem({
        title: this.title,
        summary: this.running ? this.loadingSummary() : this.summary,
        selectable: !this.running,
        themeId: this.themeId,
        showDivider: this.showDivider,
        onItemClick: () => {
          this.start();
        }
      })
      if (this.running && !this.progress.indeterminate) {
        Progress({ value: this.progress.progress, total: this.progress.max })
          .width('100%')
          .color(this.palette().progressColor)
          .backgroundColor(this.palette().divider)
          .height(ThemeDimens.PROGRESS_LINEAR_HEIGHT)
          .padding({ left: 16, right: 16, bottom: 8 })
      }
    }
    .width('100%')
  }
}
