/**
 * 迁移自 app/src/main/java/com/hippo/widget/BatteryView.java（S0512，上游 145 行）
 *
 * 上游：`extends AppCompatTextView`，把 `BatteryDrawable` 作为 compound drawable 放在文字左侧，
 *   文字是 `level + "%"`；带充电时的电量爬升动画与低电量警告色（<= 15% 且未充电）。
 *
 * ArkUI 对位：`Row({ space: 4 })` + `BatteryDrawable` + `Text`；
 *   默认读取 `@kit.BasicServicesKit` 的 `batteryInfo` 并周期刷新，同时保留 `update(level, charging)` 供外部/测试注入。
 */
import { batteryInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeElevation } from '../../common/theme/ThemeTokens';
import { BatteryDrawable, BatteryDrawableController } from '../drawable/BatteryDrawable';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.BatteryView';
const BATTERY_POLL_MS: number = 30000;

export class BatteryViewState {
  /** 上游 mLevel / mCharging */
  level: number = 0;
  charging: boolean = false;
  /** 上游 mIsChargerWorking */
  chargerWorking: boolean = false;
  /** 动画内部计数（上游 mCharger.level，与 mLevel 独立） */
  chargerLevel: number = 0;
  /** 上游 mCurrentColor 的对位用途：是否需要切 warning 色 */
  static readonly CHARGER_PERIOD_MS: number = 200;
  static readonly CHARGER_STEP: number = 2;

  /**
   * 上游 onReceive 的净效果：只有 (level, charging) 变化才处理。
   * @returns true 表示状态确实变化（调用方据此重绘）
   */
  onBatteryChanged(level: number, charging: boolean): boolean {
    if (this.level === level && this.charging === charging) {
      return false;
    }
    this.level = level;
    this.charging = charging;
    if (this.charging && this.level !== 100) {
      this.chargerWorking = true;
      this.chargerLevel = 0;
    } else {
      this.chargerWorking = false;
    }
    return true;
  }

  /** 上游 mCharger.run：level += 2，> 100 回 0 */
  tickCharger(): number {
    this.chargerLevel += BatteryViewState.CHARGER_STEP;
    if (this.chargerLevel > 100) {
      this.chargerLevel = 0;
    }
    return this.chargerLevel;
  }

  /** 上游文字颜色判定：level <= WARN_LIMIT **且未充电** → warning */
  useWarningColor(): boolean {
    return this.level <= BatteryDrawableController.WARN_LIMIT && !this.charging;
  }

  /** 显示文本：`level%` */
  text(): string {
    return `${this.level}%`;
  }

  /** 上游 init：drawable 尺寸 = 字号高，宽 = 高/0.618 */
  static drawableWidth(fontSize: number): number {
    return fontSize / 0.618;
  }
}

@Component
export struct BatteryView {
  state: BatteryViewState = new BatteryViewState();
  @Prop fontSize: number = 14;
  /** 上游 R.styleable.BatteryView_color（默认 WHITE） */
  @Prop @Watch('onColorPropChanged') color: ResourceColor = '#FFFFFFFF';
  /** 上游 R.styleable.BatteryView_warningColor（默认 @color/red_500） */
  @Prop @Watch('onColorPropChanged') warningColor: ResourceColor = '#FFF44336';
  /** 是否在挂载后自动读取系统电池电量 */
  @Prop autoRefresh: boolean = true;
  /** 可选文字阴影（供阅读器亮色页边距下保持对比度） */
  textShadowOptions: ShadowOptions | null = null;
  /** 与已交付的 BatteryDrawable 共用的绘制控制器（上游 mDrawable 的等价物） */
  batteryController: BatteryDrawableController = new BatteryDrawableController();
  @State privateTick: number = 0;
  @State privateDirty: number = 0;
  private timerId: number = -1;
  private pollTimerId: number = -1;

  private syncControllerColors(): void {
    if (typeof this.color === 'string') {
      this.batteryController.color = this.color;
    }
    if (typeof this.warningColor === 'string') {
      this.batteryController.warningColor = this.warningColor;
    }
    this.privateDirty = this.privateDirty + 1;
  }

  private onColorPropChanged(): void {
    this.syncControllerColors();
  }

  private sampleSystemBattery(): void {
    try {
      const socRaw: number = batteryInfo.batterySOC;
      const soc: number = Number.isFinite(socRaw) ? Math.max(0, Math.min(100, Math.trunc(socRaw))) : -1;
      if (soc >= 0) {
        const isCharging: boolean =
          batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE;
        this.update(soc, isCharging);
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'read batteryInfo failed: %{public}s', msg);
    }
  }

  aboutToAppear(): void {
    this.syncControllerColors();
    this.batteryController.elect = this.state.level;
    if (this.fontSize <= 0) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'fontSize <= 0 — battery drawable width would be invalid');
    }
    if (this.autoRefresh) {
      this.sampleSystemBattery();
      this.pollTimerId = setInterval((): void => {
        this.sampleSystemBattery();
      }, BATTERY_POLL_MS);
    }
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    if (this.pollTimerId >= 0) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  /** 对位广播回调：由调用方（或 @kit.BasicServicesKit batteryInfo 采样）调用 */
  update(level: number, charging: boolean): void {
    if (!this.state.onBatteryChanged(level, charging)) {
      return;
    }
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.batteryController.elect = this.state.level;
    if (this.state.chargerWorking) {
      this.timerId = setInterval((): void => {
        this.privateTick = this.state.tickCharger();
        this.batteryController.elect = this.privateTick;
      }, BatteryViewState.CHARGER_PERIOD_MS);
    }
    this.privateDirty = this.privateDirty + 1;
  }

  build() {
    Row({ space: 4 }) {
      BatteryDrawable({
        controller: this.batteryController,
        elect: this.state.chargerWorking ? this.privateTick : this.state.level,
        drawWidth: BatteryViewState.drawableWidth(this.fontSize),
        drawHeight: this.fontSize
      })
      Text(this.privateDirty >= 0 ? this.state.text() : this.state.text())
        .fontSize(this.fontSize)
        .fontColor(this.state.useWarningColor() ? this.warningColor : this.color)
        .maxLines(1)
        .textShadow(this.textShadowOptions !== null ? this.textShadowOptions : ThemeElevation.none())
    }
    .alignItems(VerticalAlign.Center)
  }
}
