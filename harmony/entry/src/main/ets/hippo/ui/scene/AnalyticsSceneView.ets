/*
 * W-017③：`AnalyticsScene` 的渲染层（统计同意：允许 / 不允许）
 *
 * 上游：`AnalyticsScene.java` + `scene_analytics.xml`（布局已 ported：`SceneAnalyticsLayout`，
 *       有 `@Prop accept` / `@Prop reject`）
 * 场景真实 API（grep 定义体）：`getExplainResId(): number` / `onReject(): void` / `onAccept(): void`
 *
 * 观测面：getLastAction()（'accept' / 'reject' / ''）+ callCount，供真机验收脚本断言"点了哪个"。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AnalyticsScene } from '../../ehviewer/ui/scene/AnalyticsScene';
import { SceneAnalyticsLayout } from '../layout/scene_analytics';

const DOMAIN: number = 0x0000;
const TAG: string = 'AnalyticsSceneView';

@Component export struct AnalyticsSceneView {
  scene: AnalyticsScene | null = null;
  @State lastAction: string = '';
  private acceptCount: number = 0;
  private rejectCount: number = 0;

  getLastAction(): string { return this.lastAction; }
  getAcceptCount(): number { return this.acceptCount; }
  getRejectCount(): number { return this.rejectCount; }

  private accept(): void {
    const s: AnalyticsScene | null = this.scene;
    if (s === null) {
      return;
    }
    this.acceptCount = this.acceptCount + 1;
    this.lastAction = 'accept';
    try {
      s.onAccept();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onAccept 抛出: %{public}s；后果：同意未保存，下次启动仍会弹本页', (e as Error).message);
    }
  }

  private reject(): void {
    const s: AnalyticsScene | null = this.scene;
    if (s === null) {
      return;
    }
    this.rejectCount = this.rejectCount + 1;
    this.lastAction = 'reject';
    try {
      s.onReject();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onReject 抛出: %{public}s；后果：拒绝未保存，下次启动仍会弹本页', (e as Error).message);
    }
  }

  @Builder
  analyticsBody() {
    Scroll() {
      Column({ space: 12 }) {
        Text($r('app.string.analytics_explain'))
          .fontSize(15)
          .lineHeight(22)
          .width('100%')
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 8, bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }

  build() {
    // 布局自己渲染 buttonpanel（两个 Button + onClick），这里**不再叠一层 Row**：
    // 叠加会出现"两组按钮"，只删叠加层又会出现"看得见点不动的死按钮"——
    // 正解是把回调传进布局（onAccept / onReject）。
    // 不传 accept/reject → 用布局默认的 app.string.accept / app.string.reject（与上游 XML 默认一致）。
    SceneAnalyticsLayout({
      onAccept: (): void => { this.accept(); },
      onReject: (): void => { this.reject(); },
      slot2Builder: (): void => { this.analyticsBody(); }
    })
      .width('100%')
      .height('100%')
    // 本视图不为根容器设置 backgroundColor：布局内部的 Text 无显式 fontColor，文字色跟随主题；
    // 强行加浅色背景会在深色主题下变成白字白底。交给主题同时决定背景与文字色。
  }
}
