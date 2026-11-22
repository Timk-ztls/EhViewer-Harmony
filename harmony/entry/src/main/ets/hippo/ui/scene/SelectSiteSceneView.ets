/*
 * W-017②：`SelectSiteScene` 的渲染层（站点选择：E-H / EX）
 *
 * 上游：`SelectSiteScene.java` + `scene_select_site.xml`（布局已 ported：`SceneSelectSiteLayout`）
 * 场景真实 API（grep 定义体）：`getCheckedSite(): number` / `onOk(checkedId: string | null): void`
 *
 * ⚠️ 顺序固定（上游 `:69-70` / `:77-78`）：
 *     `putSelectSite(false)` **先**，`putGallerySite(SITE_E|SITE_EX)` **后**
 *   反了会导致"下次启动仍然弹选择页" —— 这个顺序在场景里已实现（`onOk` 内），
 *   渲染层**不得**自己调两者，只调 `onOk(checkedId)`。
 *
 * 观测面：getLastCheckedId() / getOkCount()
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SelectSiteScene } from '../../ehviewer/ui/scene/SelectSiteScene';
import { SceneSelectSiteLayout } from '../layout/scene_select_site';

const DOMAIN: number = 0x0000;
const TAG: string = 'SelectSiteSceneView';

@Component export struct SelectSiteSceneView {
  scene: SelectSiteScene | null = null;
  /** 上游默认选中 E-H（`scene_select_site.xml` 里 site_e 默认 checked） */
  @State selectedSite: string = 'site_e';

  private lastCheckedId: string = '';
  private okCount: number = 0;

  aboutToAppear(): void {
    const s: SelectSiteScene | null = this.scene;
    if (s === null) {
      return;
    }
    // 场景里若已有选中值（从 args 恢复），尊重它；否则保持布局默认 site_e
    try {
      const checked: number = s.getCheckedSite();
      if (checked >= 0) {
        this.selectedSite = checked === 0 ? 'site_e' : 'site_ex';
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getCheckedSite 抛出: %{public}s；后果：保持默认 site_e', (e as Error).message);
    }
  }

  getLastCheckedId(): string { return this.lastCheckedId; }
  getOkCount(): number { return this.okCount; }

  private confirm(): void {
    const s: SelectSiteScene | null = this.scene;
    if (s === null) {
      return;
    }
    this.lastCheckedId = this.selectedSite;
    this.okCount = this.okCount + 1;
    try {
      // 只调 onOk：putSelectSite(false) → putGallerySite(...) 的顺序在场景内，渲染层不重复实现
      s.onOk(this.selectedSite);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'onOk 抛出: %{public}s；后果：站点未保存，下次启动仍会弹本页', (e as Error).message);
    }
  }

  build() {
    // `scene_select_site.ets:96` 本来就有 `.onClick(() => { this.onOk(); })`，
    // 之前的问题是**没把 onOk 传进去**（只传了 selectedSite），于是走到布局的 no-op 默认值；
    // 于是我在渲染层叠了一个按钮 —— 结果是"两组按钮"。现在把回调传进布局，叠加层删除。
    SceneSelectSiteLayout({
      selectedSite: this.selectedSite,
      onSiteChange: (site: string): void => { this.selectedSite = site; },
      onOk: (): void => { this.confirm(); }
    })
      .width('100%')
      .height('100%')
    // 不加根背景色：布局内部 Text 无显式 fontColor，跟随主题；加浅色背景会在深色主题下白字白底。
  }
}
