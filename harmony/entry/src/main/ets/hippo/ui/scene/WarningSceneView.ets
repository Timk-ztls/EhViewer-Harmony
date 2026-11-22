/*
 * W-017④：`WarningScene` 的渲染层（与 `AnalyticsSceneView` 同构 —— 族内契约一致）
 *
 * 上游：`WarningScene.java` + `scene_warning.xml`（布局已 ported：`SceneWarningLayout`，含 `@Prop accept/reject`）
 * 场景真实 API（grep 定义体）：`onReject(): void` / `onAccept(): void`
 *
 * 为什么重写而不是复用 WarningScene 自带的 @Component：
 *   同族的 AnalyticsScene 用 `@Prop scene` 契约；若 Warning 自带一套 `@Prop accept/reject`，
 *   分派器里就要记两套契约。**族内一致优先于"少改一个文件"**（Lead 裁定的二选一，取同构）。
 *
 * 观测面：getLastAction() / getAcceptCount() / getRejectCount()（与 AnalyticsSceneView 同名同义）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WarningScene } from '../../ehviewer/ui/scene/WarningScene';
import { SceneWarningLayout } from '../layout/scene_warning';

const DOMAIN: number = 0x0000;
const TAG: string = 'WarningSceneView';

@Component export struct WarningSceneView {
  scene: WarningScene | null = null;
  @State lastAction: string = '';
  private acceptCount: number = 0;
  private rejectCount: number = 0;

  getLastAction(): string { return this.lastAction; }
  getAcceptCount(): number { return this.acceptCount; }
  getRejectCount(): number { return this.rejectCount; }

  private accept(): void {
    const s: WarningScene | null = this.scene;
    if (s === null) {
      return;
    }
    this.acceptCount = this.acceptCount + 1;
    this.lastAction = 'accept';
    try {
      s.onAccept();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onAccept 抛出: %{public}s；后果：同意未保存，下次启动仍会弹本页',
        (e as Error).message);
    }
  }

  private reject(): void {
    const s: WarningScene | null = this.scene;
    if (s === null) {
      return;
    }
    this.rejectCount = this.rejectCount + 1;
    this.lastAction = 'reject';
    try {
      s.onReject();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onReject 抛出: %{public}s；后果：关闭警告未保存，下次启动仍会弹本页',
        (e as Error).message);
    }
  }

  @Builder
  warningBody() {
    Scroll() {
      Column({ space: 12 }) {
        Text($r('app.string.waring'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .width('100%')
        Text($r('app.string.app_waring'))
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
    // 布局自己渲染 buttonpanel（含 onClick），这里不再叠一层 Row —— 回调传进布局。
    // 不传 accept/reject → 用布局默认的 app.string.accept / app.string.reject（与上游 XML 默认一致）。
    SceneWarningLayout({
      onAccept: (): void => { this.accept(); },
      onReject: (): void => { this.reject(); },
      slot2Builder: (): void => { this.warningBody(); }
    })
      .width('100%')
      .height('100%')
    // 不加根背景色：布局内部 Text 无显式 fontColor，跟随主题；加浅色背景会在深色主题下白字白底。
  }
}
