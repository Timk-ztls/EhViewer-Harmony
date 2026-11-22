/*
 * 上游：app/src/main/res/layout/preference_widget_fixed_switch.xml（inventory S0643，上游 26 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/preference_widget_fixed_switch.ets
 *
 * 上游注释原文：SwitchPreference 的 switch 控件布局，被 android.R.layout.preference 内部 inflate。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                              ArkUI
 * androidx.appcompat.widget.SwitchCompat  Toggle({ type: ToggleType.Switch })（见 1）
 *   layout_width/height=wrap_content      内容撑开
 *   layout_gravity=center                  .alignSelf(ItemAlign.Center)（由宿主 Preference 行居中）
 *   padding=16dp                           .padding(16)
 *   focusable=false                        .focusable(false)（见 2）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `SwitchCompat` 是 Android 的开关控件（带拖动动画 + 轨道/滑块着色）。
 *    ArkUI 的 `Toggle(ToggleType.Switch)` 是语义等价物；两者的轨道宽度/滑块半径/动画曲线
 *    不做像素级复刻（差异登记），但"开/关 + 点击切换"行为一致。
 * 2. `android:focusable="false"` 在上游是为了让**整行**（Preference）接收点击而不是开关自己。
 *    ArkUI 侧 `.focusable(false)` 对位同一意图；真正的点击转发由宿主 Preference 行负责。
 * 3. `padding=16dp` 是开关四周留白（上游 SwitchCompat 默认还带自己的 minWidth/minHeight）：
 *    ArkUI 侧保留 16vp，不额外设固定宽高。
 * 4. 该布局只描述**控件外观**；Preference 行的标题/摘要/图标由 item_preference_header 等承担。
 */

@Component
export struct PreferenceWidgetFixedSwitchLayout {
  @Prop checked: boolean = false;
  @Prop selectedColor: ResourceColor = '#FF6200EE';
  @Prop switchPointColor: ResourceColor = '#FFFFFFFF';

  onCheckedChange: (checked: boolean) => void = (checked: boolean) => {
    // 默认空实现：使用方注入
  };

  build() {
    Toggle({ type: ToggleType.Switch, isOn: this.checked })
      .padding(16)
      .focusable(false)
      .selectedColor(this.selectedColor)
      .switchPointColor(this.switchPointColor)
      .alignSelf(ItemAlign.Center)
      .onChange((isOn: boolean) => {
        this.checked = isOn;
        this.onCheckedChange(isOn);
      })
  }
}
