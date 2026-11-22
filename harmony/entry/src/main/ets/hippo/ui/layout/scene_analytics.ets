/*
 * 上游：app/src/main/res/layout/scene_analytics.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_analytics.ets（inventory S0585）
 *
 * 结构：Column > [VChartAccentX48 图标] + [slot2(weight=1)] + [buttonpanel 两个 Button 各 weight=1]
 *
 * ⚠ 本布局**自己渲染 buttonpanel**，因此必须自带回调（`onAccept` / `onReject`）：
 *   生成器第一版只生成了 `Button(this.accept)` 而没有 `onClick`
 *   → 调用方若再叠一层按钮，会出现"两组按钮"；若只删叠加层，则变成"看得见点不动的死按钮"。
 *   两种都不能接受，所以回调放在布局内（形态照抄 scene_select_site.ets 的 onOk）。
 */
import { VChartAccentX48 } from '../drawable/v_chart_accent_x48';

@Component
export struct SceneAnalyticsLayout {
  @Prop accept: ResourceStr = $r('app.string.accept');
  @Prop reject: ResourceStr = $r('app.string.reject');
  /** 布局自带按钮栏，所以必须提供回调（默认 no-op：不传时按钮可见但无动作，调用方应传） */
  onAccept: () => void = (): void => {};
  onReject: () => void = (): void => {};

  @BuilderParam slot2Builder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      VChartAccentX48().padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
      Column() {
        this.slot2Builder()
      }.id('slot2').layoutWeight(1)
      Row() {
        Button(this.reject).id('reject').layoutWeight(1)
          .onClick(() => { this.onReject(); })
        Button(this.accept).id('accept').layoutWeight(1)
          .onClick(() => { this.onAccept(); })
      }.id('buttonpanel').width('100%')
    }.width('100%').height('100%').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
  }
}
