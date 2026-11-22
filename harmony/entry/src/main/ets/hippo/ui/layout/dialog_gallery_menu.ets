/*
 * 上游：app/src/main/res/layout/dialog_gallery_menu.xml（234 行）+ GalleryActivity.GalleryMenuHelper
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_gallery_menu.ets（S0575）
 *
 * 布局规范：
 *   - Material Design 行高 >= 48vp，控件色彩全走 ThemeTokens，禁默认 #007DFF 蓝与胶囊按钮。
 *   - 保留原有全部 15 个 @Prop 字段名以兼容既有调用/测试，并补齐受控回调与本地化枚举选项。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeDimens, ThemeRadius, ThemeTokens, ThemeTypography } from '../../../common/theme/ThemeTokens';
import { GetText } from '../../ehviewer/GetText';

const DOMAIN: number = 0x0000;
const TAG: string = 'DialogGalleryMenuLayout';

const SCREEN_ROTATION_KEYS: string[] = [
  'settings_read_screen_rotation_default',
  'settings_read_screen_rotation_portrait',
  'settings_read_screen_rotation_landscape',
  'settings_read_screen_rotation_sensor'
];

const READING_DIRECTION_KEYS: string[] = [
  'settings_read_reading_direction_left_to_right',
  'settings_read_reading_direction_right_to_Left',
  'settings_read_reading_direction_top_to_bottom'
];

const PAGE_SCALING_KEYS: string[] = [
  'settings_read_page_scaling_actual_size',
  'settings_read_page_scaling_fit_to_width',
  'settings_read_page_scaling_fit_to_height',
  'settings_read_page_scaling_fit_to_screen',
  'settings_read_page_scaling_fixed_scale'
];

const START_POSITION_KEYS: string[] = [
  'settings_read_start_position_top_left',
  'settings_read_start_position_top_right',
  'settings_read_start_position_bottom_left',
  'settings_read_start_position_bottom_right',
  'settings_read_start_position_center'
];

class MenuSelectOption implements SelectOption {
  value: ResourceStr;

  constructor(value: ResourceStr) {
    this.value = value;
  }
}

@Component
export struct DialogGalleryMenuLayout {
  /** 4 个 spinner 的选中下标（上游 CuteSpinner 各自保存 position） */
  @Prop screenRotation: number = 0;
  @Prop readingDirection: number = 0;
  @Prop pageScaling: number = 0;
  @Prop startPosition: number = 0;
  /** 自动翻页间隔（秒，上游 SeekBar#start_transfer_time max=15） */
  @Prop startTransferTime: number = 2;
  /** 屏幕亮度（0..200，上游 SeekBar#screen_lightness max=200） */
  @Prop screenLightness: number = 50;
  /** 开关项 */
  @Prop keepScreenOn: boolean = false;
  @Prop showClock: boolean = false;
  @Prop showProgress: boolean = false;
  @Prop showBattery: boolean = false;
  @Prop showPageInterval: boolean = false;
  @Prop pageTurnAnimation: boolean = false;
  @Prop volumePage: boolean = false;
  @Prop reverseVolumePage: boolean = false;
  @Prop readingFullscreen: boolean = false;
  @Prop customScreenLightness: boolean = false;

  /** ThemeTokens 注入色（默认取 ThemeTokens.LIGHT，宿主按当前主题传入） */
  @Prop textPrimaryColor: ResourceColor = ThemeTokens.LIGHT.textPrimary;
  @Prop textSecondaryColor: ResourceColor = ThemeTokens.LIGHT.textSecondary;
  @Prop primaryColor: ResourceColor = ThemeTokens.LIGHT.colorPrimary;
  @Prop controlActivatedColor: ResourceColor = ThemeTokens.LIGHT.controlActivated;
  @Prop dividerColor: ResourceColor = ThemeTokens.LIGHT.divider;
  @Prop popupBgColor: ResourceColor = ThemeTokens.LIGHT.popupBackground;
  @Prop selectedOptionBgColor: ResourceColor = ThemeTokens.LIGHT.cardActivatedBackground;

  /** 可由外部注入的本地化选项文本；空时自动从资源表解析 */
  @Prop screenRotationLabels: string[] = [];
  @Prop readingDirectionLabels: string[] = [];
  @Prop pageScalingLabels: string[] = [];
  @Prop startPositionLabels: string[] = [];

  /** 变更回调 */
  onScreenRotationChange: (index: number) => void = (_index: number): void => {};
  onReadingDirectionChange: (index: number) => void = (_index: number): void => {};
  onPageScalingChange: (index: number) => void = (_index: number): void => {};
  onStartPositionChange: (index: number) => void = (_index: number): void => {};
  onStartTransferTimeChange: (value: number) => void = (_value: number): void => {};
  onKeepScreenOnChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onShowClockChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onShowProgressChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onShowBatteryChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onShowPageIntervalChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onPageTurnAnimationChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onVolumePageChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onReverseVolumePageChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onReadingFullscreenChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onCustomScreenLightnessChange: (checked: boolean) => void = (_checked: boolean): void => {};
  onScreenLightnessChange: (value: number) => void = (_value: number): void => {};

  @State private resolvedRotationLabels: string[] = [];
  @State private resolvedDirectionLabels: string[] = [];
  @State private resolvedScalingLabels: string[] = [];
  @State private resolvedPositionLabels: string[] = [];

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.resolvedRotationLabels = this.screenRotationLabels.length > 0
      ? this.screenRotationLabels
      : this.resolveStringArray(ctx, SCREEN_ROTATION_KEYS);
    this.resolvedDirectionLabels = this.readingDirectionLabels.length > 0
      ? this.readingDirectionLabels
      : this.resolveStringArray(ctx, READING_DIRECTION_KEYS);
    this.resolvedScalingLabels = this.pageScalingLabels.length > 0
      ? this.pageScalingLabels
      : this.resolveStringArray(ctx, PAGE_SCALING_KEYS);
    this.resolvedPositionLabels = this.startPositionLabels.length > 0
      ? this.startPositionLabels
      : this.resolveStringArray(ctx, START_POSITION_KEYS);
  }

  private resolveStringArray(ctx: common.Context | undefined, keys: string[]): string[] {
    const out: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      let val: string = '';
      if (ctx !== undefined) {
        try {
          val = ctx.resourceManager.getStringByNameSync(k);
        } catch (e) {
          const msg: string = e instanceof Error ? e.message : String(e);
          hilog.warn(DOMAIN, TAG, 'resolve string key %{public}s failed: %{public}s', k, msg);
        }
      }
      if (val.length === 0) {
        val = GetText.getString(k);
      }
      out.push(val.length > 0 ? val : k);
    }
    return out;
  }

  private toSelectOptions(labels: string[], keys: string[]): SelectOption[] {
    const out: SelectOption[] = [];
    if (labels.length > 0) {
      for (let i = 0; i < labels.length; i++) {
        out.push(new MenuSelectOption(labels[i]));
      }
      return out;
    }
    for (let i = 0; i < keys.length; i++) {
      out.push(new MenuSelectOption(keys[i]));
    }
    return out;
  }

  private safeSelected(index: number, count: number): number {
    if (count <= 0) {
      return 0;
    }
    if (index < 0) {
      return 0;
    }
    if (index >= count) {
      return count - 1;
    }
    return index;
  }

  private selectedLabel(labels: string[], index: number, fallbackKeys: string[]): string {
    if (labels.length > 0) {
      return labels[this.safeSelected(index, labels.length)];
    }
    return fallbackKeys[this.safeSelected(index, fallbackKeys.length)];
  }

  @Builder
  selectRow(
    controlId: string,
    labelRes: Resource,
    labels: string[],
    fallbackKeys: string[],
    selectedIndex: number,
    onSelectIndex: (index: number) => void
  ) {
    Row({ space: 8 }) {
      Text(labelRes)
        .layoutWeight(1)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.textPrimaryColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Select(this.toSelectOptions(labels, fallbackKeys))
        .id(controlId)
        .layoutWeight(2)
        .selected(this.safeSelected(selectedIndex, Math.max(labels.length, fallbackKeys.length)))
        .value(this.selectedLabel(labels, selectedIndex, fallbackKeys))
        .font({ size: ThemeTypography.TEXT_SMALL })
        .fontColor(this.textPrimaryColor)
        .selectedOptionFontColor(this.primaryColor)
        .selectedOptionBgColor(this.selectedOptionBgColor)
        .optionFontColor(this.textPrimaryColor)
        .optionBgColor(this.popupBgColor)
        .menuBackgroundColor(this.popupBgColor)
        .backgroundColor(Color.Transparent)
        .borderRadius(ThemeRadius.BUTTON)
        .onSelect((idx: number): void => {
          onSelectIndex(idx);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  switchRow(
    controlId: string,
    labelRes: Resource,
    checked: boolean,
    onToggle: (next: boolean) => void
  ) {
    Row({ space: 12 }) {
      Text(labelRes)
        .layoutWeight(1)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.textPrimaryColor)
        .onClick((): void => {
          onToggle(!checked);
        })

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .id(controlId)
        .selectedColor(this.controlActivatedColor)
        .switchPointColor(ThemeTokens.LIGHT.white)
        .onChange((isOn: boolean): void => {
          if (isOn !== checked) {
            onToggle(isOn);
          }
        })
    }
    .width('100%')
    .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Scroll() {
      Column({ space: 4 }) {
        this.selectRow(
          'screen_rotation',
          $r('app.string.settings_read_screen_rotation'),
          this.resolvedRotationLabels,
          SCREEN_ROTATION_KEYS,
          this.screenRotation,
          (idx: number): void => {
            this.screenRotation = idx;
            this.onScreenRotationChange(idx);
          }
        )

        this.selectRow(
          'reading_direction',
          $r('app.string.settings_read_reading_direction'),
          this.resolvedDirectionLabels,
          READING_DIRECTION_KEYS,
          this.readingDirection,
          (idx: number): void => {
            this.readingDirection = idx;
            this.onReadingDirectionChange(idx);
          }
        )

        this.selectRow(
          'page_scaling',
          $r('app.string.settings_read_page_scaling'),
          this.resolvedScalingLabels,
          PAGE_SCALING_KEYS,
          this.pageScaling,
          (idx: number): void => {
            this.pageScaling = idx;
            this.onPageScalingChange(idx);
          }
        )

        this.selectRow(
          'start_position',
          $r('app.string.settings_read_start_position'),
          this.resolvedPositionLabels,
          START_POSITION_KEYS,
          this.startPosition,
          (idx: number): void => {
            this.startPosition = idx;
            this.onStartPositionChange(idx);
          }
        )

        // Row#5: Auto transfer time (1:2 weight + seconds value)
        Row({ space: 8 }) {
          Text($r('app.string.settings_read_auto_transfer_time'))
            .layoutWeight(1)
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.textPrimaryColor)
            .maxLines(2)

          Row({ space: 6 }) {
            Slider({
              value: this.startTransferTime,
              min: 0,
              max: 15,
              step: 1,
              style: SliderStyle.OutSet
            })
              .id('start_transfer_time')
              .layoutWeight(1)
              .selectedColor(this.primaryColor)
              .trackColor(this.dividerColor)
              .blockColor(this.primaryColor)
              .onChange((val: number): void => {
                const rounded: number = Math.max(0, Math.min(15, Math.round(val)));
                this.startTransferTime = rounded;
                this.onStartTransferTimeChange(rounded);
              })

            Text(`${Math.round(this.startTransferTime)}s`)
              .width(32)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.textSecondaryColor)
              .textAlign(TextAlign.End)
              .maxLines(1)
          }
          .layoutWeight(2)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
        .alignItems(VerticalAlign.Center)

        Divider().color(this.dividerColor).strokeWidth(1).margin({ top: 4, bottom: 4 })

        this.switchRow('keep_screen_on', $r('app.string.settings_read_keep_screen_on'),
          this.keepScreenOn, (next: boolean): void => {
            this.keepScreenOn = next;
            this.onKeepScreenOnChange(next);
          })

        this.switchRow('show_clock', $r('app.string.settings_read_show_clock'),
          this.showClock, (next: boolean): void => {
            this.showClock = next;
            this.onShowClockChange(next);
          })

        this.switchRow('show_progress', $r('app.string.settings_read_show_progress'),
          this.showProgress, (next: boolean): void => {
            this.showProgress = next;
            this.onShowProgressChange(next);
          })

        this.switchRow('show_battery', $r('app.string.settings_read_show_battery'),
          this.showBattery, (next: boolean): void => {
            this.showBattery = next;
            this.onShowBatteryChange(next);
          })

        this.switchRow('show_page_interval', $r('app.string.settings_read_show_page_interval'),
          this.showPageInterval, (next: boolean): void => {
            this.showPageInterval = next;
            this.onShowPageIntervalChange(next);
          })

        this.switchRow('page_turn_animation', $r('app.string.settings_read_page_turn_animation'),
          this.pageTurnAnimation, (next: boolean): void => {
            this.pageTurnAnimation = next;
            this.onPageTurnAnimationChange(next);
          })

        this.switchRow('volume_page', $r('app.string.settings_read_volume_page'),
          this.volumePage, (next: boolean): void => {
            this.volumePage = next;
            this.onVolumePageChange(next);
          })

        if (this.volumePage) {
          Row({ space: 12 }) {
            Text($r('app.string.settings_read_reverse_volume_page'))
              .layoutWeight(1)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.textSecondaryColor)
              .onClick((): void => {
                const next: boolean = !this.reverseVolumePage;
                this.reverseVolumePage = next;
                this.onReverseVolumePageChange(next);
              })

            Toggle({ type: ToggleType.Switch, isOn: this.reverseVolumePage })
              .id('reverse_volume_page')
              .selectedColor(this.controlActivatedColor)
              .switchPointColor(ThemeTokens.LIGHT.white)
              .onChange((isOn: boolean): void => {
                if (isOn !== this.reverseVolumePage) {
                  this.reverseVolumePage = isOn;
                  this.onReverseVolumePageChange(isOn);
                }
              })
          }
          .width('100%')
          .constraintSize({ minHeight: 44 })
          .padding({ left: ThemeDimens.KEYLINE_MARGIN })
          .alignItems(VerticalAlign.Center)
        }

        Divider().color(this.dividerColor).strokeWidth(1).margin({ top: 4, bottom: 4 })

        this.switchRow('reading_fullscreen', $r('app.string.settings_read_reading_fullscreen'),
          this.readingFullscreen, (next: boolean): void => {
            this.readingFullscreen = next;
            this.onReadingFullscreenChange(next);
          })

        this.switchRow('custom_screen_lightness', $r('app.string.settings_read_custom_screen_lightness'),
          this.customScreenLightness, (next: boolean): void => {
            this.customScreenLightness = next;
            this.onCustomScreenLightnessChange(next);
          })

        Row({ space: 8 }) {
          Slider({
            value: this.screenLightness,
            min: 0,
            max: 200,
            step: 1,
            style: SliderStyle.OutSet
          })
            .id('screen_lightness')
            .layoutWeight(1)
            .enabled(this.customScreenLightness)
            .opacity(this.customScreenLightness ? 1.0 : 0.4)
            .selectedColor(this.primaryColor)
            .trackColor(this.dividerColor)
            .blockColor(this.primaryColor)
            .onChange((val: number): void => {
              const rounded: number = Math.max(0, Math.min(200, Math.round(val)));
              this.screenLightness = rounded;
              this.onScreenLightnessChange(rounded);
            })

          Text(`${Math.round(this.screenLightness / 2)}%`)
            .width(40)
            .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
            .fontColor(this.textSecondaryColor)
            .textAlign(TextAlign.End)
            .maxLines(1)
        }
        .width('100%')
        .constraintSize({ minHeight: 40 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 24, right: 24, top: 4, bottom: 8 })
    }
    .align(Alignment.TopStart)
    .width('100%')
    .constraintSize({ maxHeight: 440 })
    .scrollBar(BarState.Auto)
  }
}
