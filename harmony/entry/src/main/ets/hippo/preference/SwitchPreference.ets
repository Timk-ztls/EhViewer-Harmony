/**
 * 迁移自 app/src/main/java/com/hippo/preference/SwitchPreference.java（inventory S0448，上游 158 行）
 *
 * 判据：**完全重复**（上游就是"标题 + 副标题 + 右侧 Switch"，无自有逻辑）→ 直接映射，不重写。
 *
 * 上游要点
 *   `extends TwoStatePreference`：持有 checked + summaryOn/summaryOff（勾选/未勾选各自的副标题）
 *   onCheckedChanged(buttonView, isChecked)：切到新状态后 `setChecked(isChecked)`
 *     —— 注意第二行 `buttonView.setChecked(!isChecked)` 是**"先反转再提交"的旧实现残留**（见差异）
 *   onBindViewHolder：把 isChecked() 同步到右侧 Checkable
 *   setSwitchTextOn/Off：Switch 上的 "ON/OFF" 文案
 *
 * ArkUI 对位：`SettingsItem`（共用行骨架）+ `Toggle({type: ToggleType.Switch})`
 *   状态机 `SwitchPreferenceState`：checked / summaryOn / summaryOff / switchTextOn / switchTextOff
 *   + effectiveSummary()（按 checked 选副标题）+ onToggle（写回并回调）
 *
 * 差异（已登记 MR）：
 *   1) 上游 `onCheckedChanged` 里的 `buttonView.setChecked(!isChecked)` 是"先把 UI 推回旧值、
 *      再由 setChecked 统一驱动"的双保险写法（防止持久化失败时 UI 与数据不一致）。
 *      ArkUI 的 `Toggle` 是受控组件（`.isOn(state.checked)`），**状态由 model 唯一决定**，
 *      因此不需要"反转再拉回"——这是平台特性差异，不是漏实现。
 *   2) 上游持久化由 PreferenceManager 完成（core-runtime 的 scope）；
 *      本组件只暴露 `onChange(checked)`，持久化由调用方接 key 常量后执行。
 *   3) `summary` 与 `summaryOn/summaryOff` 的优先级：上游 TwoStatePreference 在 checked 时用 summaryOn
 *      （若为空则回退 summary），此处按同一规则实现于 effectiveSummary()。
 */
import { ThemePalette, ThemeTokens } from '../../common/theme/ThemeTokens';
import { SettingsItem } from '../ui/settings/SettingsItem';

export class SwitchPreferenceState {
  /** 上游 isChecked()/setChecked() */
  checked: boolean = false;
  /** 上游 android:summary（基础副标题） */
  summary: string = '';
  /** 上游 summaryOn / summaryOff */
  summaryOn: string = '';
  summaryOff: string = '';
  /** 上游 setSwitchTextOn/Off（Switch 上的文案，ArkUI Toggle 不显示文字，保留供调用方渲染） */
  switchTextOn: string = 'ON';
  switchTextOff: string = 'OFF';
  enabled: boolean = true;

  /** 上游 TwoStatePreference 的副标题优先级：checked ? (summaryOn || summary) : (summaryOff || summary) */
  effectiveSummary(): string {
    if (this.checked) {
      return this.summaryOn.length > 0 ? this.summaryOn : this.summary;
    }
    return this.summaryOff.length > 0 ? this.summaryOff : this.summary;
  }

  /** 上游 setChecked(isChecked)：改状态 */
  setChecked(checked: boolean): void {
    this.checked = checked;
  }

  /** 上游 onCheckedChanged 的净效果：切到新值（受控组件由 model 驱动，无需反转） */
  onToggle(newChecked: boolean): boolean {
    if (this.checked === newChecked) {
      return false;
    }
    this.setChecked(newChecked);
    return true;
  }
}

@Component
export struct SwitchPreference {
  state: SwitchPreferenceState = new SwitchPreferenceState();
  @Prop title: string = '';
  @Prop @Watch('onCheckedPropChanged') checked: boolean | null = null;
  @Prop @Watch('onSummaryPropChanged') summary: string | null = null;
  @Prop @Watch('onEnabledPropChanged') itemEnabled: boolean | null = null;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  /** 上游 onPreferenceChange 的语义：返回 false 表示拒绝变更（上游可 veto） */
  onPreferenceChange: (checked: boolean) => boolean = (checked: boolean) => true;
  /** 变更被接受后的通知（持久化由调用方在此完成） */
  onChanged: (checked: boolean) => void = () => {
  };
  /** 整行点击（上游 Preference 行的点击也会切换 Switch） */
  onItemClick: () => void = () => {
  };
  @State rev: number = 0;
  /** 程序化回填抑制位：对位上游 setOnCheckedChangeListener(null) → setChecked → 再挂回 */
  private suppressChange: boolean = false;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    if (this.checked !== null) {
      this.state.setChecked(this.checked);
    }
    if (this.summary !== null) {
      this.state.summary = this.summary;
    }
    if (this.itemEnabled !== null) {
      this.state.enabled = this.itemEnabled;
    }
  }

  private onCheckedPropChanged(): void {
    if (this.checked !== null) {
      this.setCheckedProgrammatic(this.checked);
    }
  }

  private onSummaryPropChanged(): void {
    if (this.summary !== null && this.state.summary !== this.summary) {
      this.state.summary = this.summary;
      this.rev = this.rev + 1;
    }
  }

  private onEnabledPropChanged(): void {
    if (this.itemEnabled !== null && this.state.enabled !== this.itemEnabled) {
      this.state.enabled = this.itemEnabled;
      this.rev = this.rev + 1;
    }
  }

  /** 程序化回填：同步 UI 但不触发 onPreferenceChange / onChanged */
  setCheckedProgrammatic(value: boolean): void {
    if (this.state.checked === value) {
      return;
    }
    this.suppressChange = true;
    this.state.setChecked(value);
    this.rev = this.rev + 1;
  }

  private apply(checked: boolean, fromRowClick: boolean): void {
    if (checked === this.state.checked) {
      return;
    }
    // 受控：先问调用方是否允许（veto 时 UI 不跟随）
    const accepted: boolean = this.onPreferenceChange(checked);
    if (accepted) {
      if (fromRowClick) {
        this.suppressChange = true;
      }
      this.state.onToggle(checked);
      this.onChanged(this.state.checked);
    } else {
      // veto 时 Toggle 已先于回调翻转，重绘会将其推回 model 值；抑制后续回弹回调
      this.suppressChange = true;
    }
    this.rev = this.rev + 1; // 无论接受与否都重绘，保证 veto 时 Switch 回弹到 model 值
  }

  build() {
    SettingsItem({
      title: this.title,
      summary: this.rev >= 0 ? this.state.effectiveSummary() : this.state.effectiveSummary(),
      itemEnabled: this.rev >= 0 ? this.state.enabled : this.state.enabled,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onItemClick: () => {
        this.apply(!this.state.checked, true);
        this.onItemClick();
      },
      trailing: () => {
        this.trailingSwitch()
      }
    })
  }

  @Builder
  trailingSwitch(): void {
    Toggle({ type: ToggleType.Switch, isOn: this.rev >= 0 ? this.state.checked : this.state.checked })
      .selectedColor(this.palette().controlActivated)
      .switchPointColor('#FFFFFFFF')
      .enabled(this.rev >= 0 ? this.state.enabled : this.state.enabled)
      .onChange((isOn: boolean) => {
        if (this.suppressChange) {
          this.suppressChange = false; // 程序化回填（见 suppressChange 注释），不重复回调
          if (isOn === this.state.checked) {
            return;
          }
        }
        if (isOn === this.state.checked) {
          return;
        }
        this.apply(isOn, false);
      })
  }
}
