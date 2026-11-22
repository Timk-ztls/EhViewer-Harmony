/*
 * 上游：app/src/main/res/layout/scene_select_site.xml（123 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_select_site.ets（S0662）
 *
 * ============================================================================
 * 骨架缺口（auditor-ui 量化 38/123）：**3 个"弹簧"（Space weight=1）缺失**
 * ============================================================================
 * 所谓"弹簧"= `<Space android:layout_weight="1"/>`，上游用它把上下内容**顶开**
 * （上弹簧把单选框推到中部，下弹簧把按钮推到下部）。骨架全丢 → 整页贴顶，视觉完全不对。
 *
 * 上游结构：
 *   LinearLayout(vertical)
 *     MaxSizeContainer（weight=1，限制最大宽度的容器）
 *       ScrollView（weight=1）
 *         LinearLayout(vertical)
 *           TextView(@string/select_scene)
 *           Space  ← 弹簧1（weight=1）
 *           RadioGroup#radio_group
 *             RadioButton#site_e（@string/site_e）
 *             RadioButton#site_ex（@string/site_ex）
 *           TextView(@string/select_scene_explain)
 *           Space  ← 弹簧2（weight=1）
 *           LinearLayout#buttonPanel(horizontal)
 *             View（weight=1）← 弹簧3（把 ok 推到右侧）
 *             Button#ok（weight=1，@android:string/ok）
 *
 * ⚠️ **死文件核查**（Lead 指派）：`SelectSiteScene.ets`（79 行）自带整套 UI，本文件是否被 import？
 * 结论见文件末尾注释 —— **无人 import**，但上游 XML 确实是 `SelectSiteScene` 用的布局，
 * 所以按"补齐备用"处理，并在清单 notes 记明"当前无 import 方"。
 *
 * 弹簧的等价物：ArkUI `Blank()`（可伸缩占位），**不是** `Space`（Space 是定长）。
 */

/**
 * 上游 `@android:string/ok` = **"确定"**。
 * 我们已补 `app.string.ok`（"确定"，与 `@android:string/ok` 直接对位，非自造文案），
 * 因此直接用资源键 —— 原先的 `const SYSTEM_OK_TODO = 'OK'` 字面量占位已移除
 * （字面量 "OK" 与上游"确定"并不等价）。
 */

@Component
export struct SceneSelectSiteLayout {
  /** 上游 `RadioGroup#radio_group` 的选中项：`site_e` / `site_ex` */
  @Prop selectedSite: string = 'site_e';
  /** 单选变化 */
  onSiteChange: (site: string) => void = (site: string): void => {};
  /** 上游 `Button#ok` 点击 */
  onOk: () => void = (): void => {};

  build() {
    Column() {
      // MaxSizeContainer（限制最大宽度）→ Column（最大宽度由上层注入，见 TODO）
      Column() {
        Scroll() {
          Column() {
            Text($r('app.string.select_scene'))
              .width('100%')
              .textAlign(TextAlign.Start)

            // 弹簧1
            Blank().layoutWeight(1)

            // RadioGroup#radio_group
            Row() {
              Radio({ value: 'site_e', group: 'site_group' })
                .id('site_e')
                .checked(this.selectedSite === 'site_e')
                .onChange((isChecked: boolean) => {
                  if (isChecked) { this.onSiteChange('site_e'); }
                })
              Text($r('app.string.site_e'))
              Radio({ value: 'site_ex', group: 'site_group' })
                .id('site_ex')
                .checked(this.selectedSite === 'site_ex')
                .onChange((isChecked: boolean) => {
                  if (isChecked) { this.onSiteChange('site_ex'); }
                })
              Text($r('app.string.site_ex'))
            }
            .id('radio_group')
            .width('100%')

            Text($r('app.string.select_scene_explain'))
              .width('100%')

            // 弹簧2
            Blank().layoutWeight(1)

            // buttonPanel
            Row() {
              // 弹簧3：把 ok 推到右侧
              Blank().layoutWeight(1)
        Button($r('app.string.ok'))
                .id('ok')
                .layoutWeight(1)
                .onClick(() => { this.onOk(); })
            }
            .id('buttonPanel')
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .align(Alignment.TopStart)
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 600 })
    }
    .width('100%')
    .height('100%')
  }
}
