/**
 * 迁移自 app/src/main/java/com/hippo/preference/SeekBarPreference.java（inventory S0449，上游 196 行）
 *
 * ============================ 先纠正一个前提（一手核对结果） ============================
 * **Hippo 的 SeekBarPreference 没有 `seekBarIncrement` / `min` / `step`。**
 * 上游字段只有三个：`mProgress`（当前值）、`mMax`（上限）、`mTrackingTouch`（是否正在拖动）。
 * `seekBarIncrement`/`step`/`min` 是 **AndroidX 的 `androidx.preference.SeekBarPreference`** 的概念，
 * Hippo 这个类是自写的简化版（`extends Preference implements SeekBar.OnSeekBarChangeListener`）。
 * 因此本移植**不引入** min/step/seekBarIncrement —— 加了就是凭空发明 API（上游没有）。
 *
 * ============================ 真正要 1:1 的是"提交时机" ============================
 *   onProgressChanged(seekBar, progress, fromUser)：
 *       **仅当 !mTrackingTouch 时**才 setProgress(progress, true) —— 拖动过程中不写值
 *   onStartTrackingTouch：mTrackingTouch = true
 *   onStopTrackingTouch ：在 setProgress(progress, false) 之后，若 seekBar 值 != mProgress 才提交
 *     → 语义是"**拖动结束才落值**"，与 DialogPreference 的"确认才提交"是同一类时机问题
 *   setProgress(progress, notifyChanged)：先 clamp 到 mMax；notifyChanged=true 时才回调/持久化
 *   SavedState：max + progress（两个键）
 *
 * ArkUI 对位：原生 `Slider` + `SliderChangeMode`（Begin/Moving/End/Click）**天然对位三个回调**：
 *   Begin  → onStartTracking（trackingTouch = true）
 *   Moving → onProgressChanged（tracking 中，不写值）
 *   End    → onStopTracking（写值）
 *   Click  → 点击轨道跳变：直接视为一次完整操作（End）
 * 数值显示放行右侧（上游 widgetLayout 里也有一个显示当前值的 TextView）。
 *
 * 差异（已登记 MR）：
 *   1) 上游 `seekBar.setMax(mMax)` 的进度基数是 0..mMax（无 min 概念）→ Slider 的 min 固定 0
 *   2) 上游持久化走 PreferenceManager（core-runtime scope）→ 本组件暴露 onChanged 由调用方接 key
 *   3) 上游 `onBindViewHolder` 每帧从 prefs 重读 `getPersistedInt(mProgress)`；ArkUI 是受控组件，
 *      值由 state 唯一决定（重读语义由调用方在 aboutToAppear 里赋值一次即可）
 */
import { ThemeDimens, ThemePalette, ThemeTokens, ThemeTypography } from '../../common/theme/ThemeTokens';
import { SettingsItem } from '../ui/settings/SettingsItem';

export class SeekBarPreferenceState {
  /** 上游 mProgress / mMax */
  progress: number = 0;
  max: number = 100;
  /** 上游 mTrackingTouch */
  trackingTouch: boolean = false;
  /** 拖动中的临时位置（仅 UI 显示；上游由 SeekBar 自己持有，不写 mProgress） */
  transientProgress: number = 0;
  title: string = '';
  summary: string = '';

  /** 显示值：拖动中用 transientProgress，否则用已提交值 */
  displayProgress(): number {
    return this.trackingTouch ? this.transientProgress : this.progress;
  }

  /** 上游 setMax(int)：仅在新值与旧值不同时生效 */
  setMax(max: number): void {
    if (max !== this.max) {
      this.max = max;
      if (this.progress > this.max) {
        this.progress = this.max;
      }
    }
  }

  /** 上游 setProgress(progress, notifyChanged)：先 clamp，再（可选）提交 */
  setProgress(progress: number, notifyChanged: boolean): boolean {
    let v: number = progress;
    if (v > this.max) {
      v = this.max;
    }
    if (v < 0) {
      v = 0;
    }
    if (v === this.progress) {
      return false;
    }
    this.progress = v;
    this.transientProgress = v;
    return notifyChanged;
  }

  /** 上游 onStartTrackingTouch */
  onStartTracking(): void {
    this.trackingTouch = true;
    this.transientProgress = this.progress;
  }

  /**
   * 上游 onProgressChanged：跟踪中**不写 mProgress**，只让滑杆自己走。
   * 返回 true 表示需要提交（对位 notifyChanged）。
   *
   * 关键（断言抓出的真 bug）：拖动中**不能**更新 this.progress。
   * 上游 onProgressChanged 的门控是 `if (!mTrackingTouch) setProgress(...)` ——
   * mProgress 始终是"已提交值"，滑杆位置才是临时值。若拖动中就写 mProgress，
   * 结束拖动时 setProgress(同值) 会判"未变化"而不提交 → **拖完永远存不上**。
   * 因此这里只更新 transientProgress（仅用于 UI 显示），progress 保持已提交值。
   */
  onProgressChanged(progress: number): boolean {
    const clamped: number = progress > this.max ? this.max : (progress < 0 ? 0 : progress);
    if (this.trackingTouch) {
      this.transientProgress = clamped;
      return false;
    }
    this.transientProgress = clamped;
    return this.setProgress(progress, true);
  }

  /** 上游 onStopTrackingTouch：结束拖动时才落值（值变了才提交） */
  onStopTracking(progress: number): boolean {
    this.trackingTouch = false;
    const changed: boolean = this.setProgress(progress, true);
    this.transientProgress = this.progress;
    return changed;
  }
}

@Component
export struct SeekBarPreference {
  state: SeekBarPreferenceState = new SeekBarPreferenceState();
  @Prop itemEnabled: boolean = true;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  /** 上游 onPreferenceChange 的 veto：返回 false 时不落值（UI 回弹由 model 驱动） */
  onPreferenceChange: (progress: number) => boolean = (progress: number) => true;
  onChanged: (progress: number) => void = () => {
  };
  @State rev: number = 0;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private commit(progress: number): void {
    const accepted: boolean = this.onPreferenceChange(progress);
    if (accepted) {
      if (this.state.onStopTracking(progress)) {
        this.onChanged(this.state.progress);
      }
    } else {
      this.state.trackingTouch = false;
      this.state.transientProgress = this.state.progress;
    }
    this.rev = this.rev + 1; // veto 时也重绘 → 滑杆回弹到 model 值
  }

  build() {
    SettingsItem({
      title: this.rev >= 0 ? this.state.title : this.state.title,
      summary: this.rev >= 0 ? this.state.summary : this.state.summary,
      itemEnabled: this.itemEnabled,
      themeId: this.themeId,
      showDivider: this.showDivider,
      selectable: false,
      trailing: () => {
        this.trailingSlider()
      }
    })
  }

  @Builder
  trailingSlider(): void {
    Row({ space: ThemeDimens.SPACING }) {
      Slider({
        value: this.rev >= 0 ? this.state.displayProgress() : this.state.displayProgress(),
        min: 0,
        max: this.state.max,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width(140)
        .selectedColor(this.palette().controlActivated)
        .trackColor(this.palette().divider)
        .blockColor(this.palette().controlActivated)
        .enabled(this.itemEnabled)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin) {
            this.state.onStartTracking();
          } else if (mode === SliderChangeMode.Moving) {
            this.state.onProgressChanged(value);
            this.rev = this.rev + 1; // 拖动中仅刷新显示
          } else {
            // End / Click：一次操作结束 → 落值并清除 trackingTouch
            this.commit(value);
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Cancel) {
            this.state.trackingTouch = false;
            this.state.transientProgress = this.state.progress;
            this.rev = this.rev + 1;
          } else if (event.type === TouchType.Up && this.state.trackingTouch) {
            this.commit(this.state.transientProgress);
          }
        })
      Text(`${this.rev >= 0 ? this.state.displayProgress() : this.state.displayProgress()}`)
        .fontSize(ThemeTypography.PREF_SUMMARY)
        .fontColor(this.itemEnabled ? this.palette().textPrimary : this.palette().textDisabled)
        .textAlign(TextAlign.End)
        .width(40)
    }
  }
}
