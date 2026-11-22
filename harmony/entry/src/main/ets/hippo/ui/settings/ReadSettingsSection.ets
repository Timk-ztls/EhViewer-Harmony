import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GetText } from '../../ehviewer/GetText';
import { Settings } from '../../ehviewer/Settings';
import { ListPreference } from '../../preference/ListPreference';
import { SwitchPreference } from '../../preference/SwitchPreference';
import { SeekBarPreference, SeekBarPreferenceState } from '../../preference/SeekBarPreference';
import { ReadSettingsHelpers } from './SettingsSectionHelpers';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'ReadSettingsSection';

@Component
export struct ReadSettingsSection {
  @Prop @Watch('onRefreshTriggerChanged') refreshTrigger: number = 0;
  @Prop themeId: number = -1;

  @State screenRotation: number = Settings.DEFAULT_SCREEN_ROTATION;
  @State readingRefreshRateHz: number = Settings.DEFAULT_READING_REFRESH_RATE;
  @State showRefreshRate: boolean = true;
  @State readingDirection: number = Settings.DEFAULT_READING_DIRECTION;
  @State pageScaling: number = Settings.DEFAULT_PAGE_SCALING;
  @State startPosition: number = Settings.DEFAULT_START_POSITION;
  @State keepScreenOn: boolean = Settings.DEFAULT_KEEP_SCREEN_ON;
  @State showClock: boolean = Settings.DEFAULT_SHOW_CLOCK;
  @State showProgress: boolean = Settings.DEFAULT_SHOW_PROGRESS;
  @State showBattery: boolean = Settings.DEFAULT_SHOW_BATTERY;
  @State showPageInterval: boolean = Settings.DEFAULT_SHOW_PAGE_INTERVAL;
  @State pageTurnAnimation: boolean = Settings.DEFAULT_PAGE_TURN_ANIMATION;
  @State volumePage: boolean = Settings.DEFAULT_VOLUME_PAGE;
  @State reverseVolumePage: boolean = Settings.DEFAULT_REVERSE_VOLUME_PAGE;
  @State readingFullscreen: boolean = Settings.VALUE_READING_FULLSCREEN;
  @State customScreenLightness: boolean = Settings.DEFAULT_CUSTOM_SCREEN_LIGHTNESS;

  private hostContext: common.Context | undefined = undefined;
  private autoTransferState: SeekBarPreferenceState = new SeekBarPreferenceState();
  private lightnessState: SeekBarPreferenceState = new SeekBarPreferenceState();

  aboutToAppear(): void {
    this.hostContext = this.getUIContext().getHostContext();
    if (this.hostContext !== undefined && !GetText.isInitialized()) {
      GetText.initialize(this.hostContext);
    }
    this.syncFromSettings();
  }

  private onRefreshTriggerChanged(): void {
    this.syncFromSettings();
  }

  private str(key: string): string {
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        return ctx.resourceManager.getStringByNameSync(key);
      } catch (err) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'getStringByNameSync failed for %{public}s: %{public}s',
          key, JSON.stringify(err));
      }
    }
    return GetText.getString(key);
  }

  private strs(keys: string[]): string[] {
    const out: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      out.push(this.str(keys[i]));
    }
    return out;
  }

  private syncFromSettings(): void {
    this.screenRotation = Settings.getScreenRotation();
    this.showRefreshRate = ReadSettingsHelpers.shouldShowReadingRefreshRate();
    this.readingRefreshRateHz = Settings.getReadingRefreshRateHz();
    this.readingDirection = Settings.getReadingDirection();
    this.pageScaling = Settings.getPageScaling();
    this.startPosition = Settings.getStartPosition();
    this.keepScreenOn = Settings.getKeepScreenOn();
    this.showClock = Settings.getShowClock();
    this.showProgress = Settings.getShowProgress();
    this.showBattery = Settings.getShowBattery();
    this.showPageInterval = Settings.getShowPageInterval();
    this.pageTurnAnimation = Settings.getPageTurnAnimation();
    this.volumePage = Settings.getVolumePage();
    this.reverseVolumePage = Settings.getReverseVolumePage();
    this.readingFullscreen = Settings.getReadingFullscreen();
    this.customScreenLightness = Settings.getCustomScreenLightness();

    this.autoTransferState.title = this.str('settings_read_auto_transfer_time');
    this.autoTransferState.setMax(ReadSettingsHelpers.AUTO_TRANSFER_TIME_MAX);
    this.autoTransferState.setProgress(
      ReadSettingsHelpers.clampAutoTransferTime(Settings.getStartTransferTime()), false);

    this.lightnessState.title = this.str('settings_read_screen_lightness');
    this.lightnessState.setMax(ReadSettingsHelpers.SCREEN_LIGHTNESS_MAX);
    this.lightnessState.setProgress(
      ReadSettingsHelpers.clampScreenLightness(Settings.getScreenLightness()), false);
  }

  build() {
    Column() {
      ListPreference({
        title: this.str('settings_read_screen_rotation'),
        dialogTitle: this.str('settings_read_screen_rotation'),
        entries: this.strs(ReadSettingsHelpers.SCREEN_ROTATION_LABEL_KEYS),
        entryValues: ReadSettingsHelpers.SCREEN_ROTATION_VALUES,
        value: `${this.screenRotation}`,
        themeId: this.themeId,
        onChanged: (value: string) => {
          const rotation: number = Number(value);
          if (!Number.isNaN(rotation)) {
            Settings.putScreenRotation(rotation);
            this.screenRotation = rotation;
          }
        }
      })

      // Strictly conditional per ReadSettingsRules: omit completely (do not disable) when unsupported
      if (this.showRefreshRate) {
        ListPreference({
          title: this.str('settings_read_refresh_rate'),
          dialogTitle: this.str('settings_read_refresh_rate'),
          entries: this.strs(ReadSettingsHelpers.REFRESH_RATE_LABEL_KEYS),
          entryValues: ReadSettingsHelpers.REFRESH_RATE_VALUES,
          value: `${this.readingRefreshRateHz}`,
          themeId: this.themeId,
          onChanged: (value: string) => {
            const hz: number = ReadSettingsHelpers.sanitizeRefreshRateValue(value);
            Settings.putReadingRefreshRateHz(hz);
            this.readingRefreshRateHz = hz;
          }
        })
      }

      ListPreference({
        title: this.str('settings_read_reading_direction'),
        dialogTitle: this.str('settings_read_reading_direction'),
        entries: this.strs(ReadSettingsHelpers.READING_DIRECTION_LABEL_KEYS),
        entryValues: ReadSettingsHelpers.READING_DIRECTION_VALUES,
        value: `${this.readingDirection}`,
        themeId: this.themeId,
        onChanged: (value: string) => {
          const dir: number = Number(value);
          if (!Number.isNaN(dir)) {
            Settings.putReadingDirection(dir);
            this.readingDirection = dir;
          }
        }
      })

      ListPreference({
        title: this.str('settings_read_page_scaling'),
        dialogTitle: this.str('settings_read_page_scaling'),
        entries: this.strs(ReadSettingsHelpers.PAGE_SCALING_LABEL_KEYS),
        entryValues: ReadSettingsHelpers.PAGE_SCALING_VALUES,
        value: `${this.pageScaling}`,
        themeId: this.themeId,
        onChanged: (value: string) => {
          const scaling: number = Number(value);
          if (!Number.isNaN(scaling)) {
            Settings.putPageScaling(scaling);
            this.pageScaling = scaling;
          }
        }
      })

      ListPreference({
        title: this.str('settings_read_start_position'),
        dialogTitle: this.str('settings_read_start_position'),
        entries: this.strs(ReadSettingsHelpers.START_POSITION_LABEL_KEYS),
        entryValues: ReadSettingsHelpers.START_POSITION_VALUES,
        value: `${this.startPosition}`,
        themeId: this.themeId,
        onChanged: (value: string) => {
          const pos: number = Number(value);
          if (!Number.isNaN(pos)) {
            Settings.putStartPosition(pos);
            this.startPosition = pos;
          }
        }
      })

      SeekBarPreference({
        state: this.autoTransferState,
        themeId: this.themeId,
        onChanged: (progress: number) => {
          const clamped: number = ReadSettingsHelpers.clampAutoTransferTime(progress);
          Settings.putStartTransferTime(clamped);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_keep_screen_on'),
        checked: this.keepScreenOn,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.keepScreenOn = checked;
          Settings.putKeepScreenOn(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_show_clock'),
        checked: this.showClock,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.showClock = checked;
          Settings.putShowClock(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_show_progress'),
        checked: this.showProgress,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.showProgress = checked;
          Settings.putShowProgress(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_show_battery'),
        checked: this.showBattery,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.showBattery = checked;
          Settings.putShowBattery(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_show_page_interval'),
        checked: this.showPageInterval,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.showPageInterval = checked;
          Settings.putShowPageInterval(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_page_turn_animation'),
        checked: this.pageTurnAnimation,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.pageTurnAnimation = checked;
          Settings.putPageTurnAnimation(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_volume_page'),
        checked: this.volumePage,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.volumePage = checked;
          Settings.putVolumePage(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_reverse_volume_page'),
        checked: this.reverseVolumePage,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.reverseVolumePage = checked;
          Settings.putReverseVolumePage(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_reading_fullscreen'),
        checked: this.readingFullscreen,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.readingFullscreen = checked;
          Settings.putReadingFullscreen(checked);
        }
      })

      SwitchPreference({
        title: this.str('settings_read_custom_screen_lightness'),
        checked: this.customScreenLightness,
        themeId: this.themeId,
        onChanged: (checked: boolean) => {
          this.customScreenLightness = checked;
          Settings.putCustomScreenLightness(checked);
        }
      })

      SeekBarPreference({
        state: this.lightnessState,
        itemEnabled: this.customScreenLightness,
        themeId: this.themeId,
        onChanged: (progress: number) => {
          const clamped: number = ReadSettingsHelpers.clampScreenLightness(progress);
          Settings.putScreenLightness(clamped);
        }
      })
    }
    .width('100%')
  }
}
