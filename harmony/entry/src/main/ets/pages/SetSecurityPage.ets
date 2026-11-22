/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Phase B Track P1: SetSecurityPage (@Entry @Component V1).
 *
 * Wraps `SetSecurityActivity` with concrete `SecurityHost`, `SecuritySettings`,
 * and `PatternViewPort` backed by `LockPatternController` + `@kit.UserAuthenticationKit`.
 * Supports both portrait (`activity_set_security`) and landscape (`land/activity_set_security`) layouts.
 */

import { userAuth } from '@kit.UserAuthenticationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeMode, ThemePalette, ThemeRadius, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { Settings } from '../hippo/ehviewer/Settings';
import { SetSecurityActivity } from '../hippo/ehviewer/ui/SetSecurityActivity';
import { Cell } from '../hippo/widget/lockpattern/LockPatternCell';
import {
  DisplayMode,
  LockPatternController,
  LockPatternView,
  OnPatternListener
} from '../hippo/widget/lockpattern/LockPatternView';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { APP_THEME_STORAGE_KEY, syncAppThemeStorage } from '../hippo/ui/ThemeSystemBar';
import {
  LockPatternControllerPort,
  LockPatternViewPortAdapter,
  SetSecurityPageHostAdapter,
  SettingsBackedSecuritySettings
} from '../hippo/ui/scene/AuthSecurityAdapters';

const DOMAIN: number = 0x0000;
const TAG: string = 'SetSecurityPage';

class SetSecurityControllerPort implements LockPatternControllerPort {
  private readonly controller: LockPatternController;

  constructor(controller: LockPatternController) {
    this.controller = controller;
  }

  setPatternCorrect(cells: Cell[]): void {
    this.controller.setPattern(DisplayMode.Correct, cells);
  }

  setDisplayModeCorrect(): void {
    this.controller.setDisplayMode(DisplayMode.Correct);
  }

  setDisplayModeWrong(): void {
    this.controller.setDisplayMode(DisplayMode.Wrong);
  }

  getCellSize(): number {
    return this.controller.getCellSize();
  }

  getPatternString(): string {
    return this.controller.getPatternString();
  }
}

class SetSecurityPatternListener implements OnPatternListener {
  private readonly onPatternUpdated: (cellCount: number) => void;

  constructor(onPatternUpdated: (cellCount: number) => void) {
    this.onPatternUpdated = onPatternUpdated;
  }

  onPatternStart(): void {
  }

  onPatternCleared(): void {
    this.onPatternUpdated(0);
  }

  onPatternCellAdded(_pattern: Cell[]): void {
  }

  onPatternDetected(pattern: Cell[]): void {
    this.onPatternUpdated(pattern.length);
  }
}

function probeBiometricEnrolled(): boolean {
  try {
    userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL1);
    const enrolled: userAuth.EnrolledState = userAuth.getEnrolledState(userAuth.UserAuthType.FINGERPRINT);
    return enrolled.credentialCount > 0;
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'probeBiometricEnrolled failed: %{public}s', msg);
    return false;
  }
}

@Entry
@Component
export struct SetSecurityPage {
  @StorageLink(APP_THEME_STORAGE_KEY) themeId: number = ThemeMode.LIGHT;
  @State ready: boolean = false;
  @State isLandscape: boolean = false;
  @State fingerprintVisible: boolean = false;
  @State fingerprintChecked: boolean = false;
  @State drawnCellCount: number = 0;
  @State hasExistingPattern: boolean = false;

  private lockController: LockPatternController = new LockPatternController();
  private hostAdapter: SetSecurityPageHostAdapter | null = null;
  private activity: SetSecurityActivity | null = null;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  aboutToAppear(): void {
    this.themeId = syncAppThemeStorage();
    this.lockController.setOnPatternListener(new SetSecurityPatternListener((count: number): void => {
      this.drawnCellCount = count;
    }));
    if (Settings.isAttached()) {
      this.initializeActivity();
      return;
    }
    AppWiring.whenReady().then((): void => {
      this.initializeActivity();
    }).catch((err: Error): void => {
      const msg: string = err.message !== undefined ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'AppWiring.whenReady failed, continuing with current settings: %{public}s', msg);
      this.initializeActivity();
    });
  }

  onPageShow(): void {
    this.themeId = syncAppThemeStorage();
  }

  aboutToDisappear(): void {
    if (this.activity !== null) {
      this.activity.onDestroy();
      this.activity = null;
    }
    if (this.hostAdapter !== null) {
      this.hostAdapter.detachPatternView();
      this.hostAdapter = null;
    }
  }

  onBackPress(): boolean {
    if (this.activity !== null) {
      this.activity.onCancel();
      return true;
    }
    this.navigateBack();
    return true;
  }

  private initializeActivity(): void {
    this.hasExistingPattern = Settings.hasSecurity();
    const port: LockPatternViewPortAdapter = new LockPatternViewPortAdapter(
      new SetSecurityControllerPort(this.lockController)
    );
    const host: SetSecurityPageHostAdapter = new SetSecurityPageHostAdapter(
      port,
      (): boolean => probeBiometricEnrolled(),
      (visible: boolean, checked: boolean): void => {
        this.fingerprintVisible = visible;
        this.fingerprintChecked = checked;
      },
      (): void => {
        Settings.flush().finally((): void => {
          this.navigateBack();
        });
      }
    );
    const settingsAdapter: SettingsBackedSecuritySettings = new SettingsBackedSecuritySettings();
    const act: SetSecurityActivity = new SetSecurityActivity(host, settingsAdapter);
    this.hostAdapter = host;
    this.activity = act;
    act.onCreate();
    this.drawnCellCount = this.lockController.getCellSize();
    this.ready = true;
  }

  private navigateBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'router.back failed: %{public}s', msg);
    }
  }

  private onBackButtonClick(): void {
    if (this.activity !== null) {
      this.activity.onOptionsItemSelected('android.R.id.home');
    } else {
      this.navigateBack();
    }
  }

  private onCancelClick(): void {
    if (this.activity !== null) {
      this.activity.onCancel();
    } else {
      this.navigateBack();
    }
  }

  private onSetClick(): void {
    if (this.activity !== null) {
      this.activity.onSet();
    } else {
      this.navigateBack();
    }
  }

  private async onDisableClick(): Promise<void> {
    this.lockController.clearPattern();
    this.drawnCellCount = 0;
    this.hasExistingPattern = false;
    this.fingerprintChecked = false;
    Settings.putSecurity('');
    Settings.putEnableFingerprint(false);
    await Settings.flush();
    try {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.pattern_protection_disabled'),
        duration: 1500
      });
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'showToast skipped: %{public}s', msg);
    }
    this.navigateBack();
  }

  private onFingerprintToggle(checked: boolean): void {
    this.fingerprintChecked = checked;
    if (this.hostAdapter !== null) {
      this.hostAdapter.setFingerprintChecked(checked);
    }
  }

  @Builder
  fingerprintCheckboxRow(): void {
    if (this.fingerprintVisible) {
      Row({ space: 8 }) {
        Checkbox({ name: 'fingerprint' })
          .select(this.fingerprintChecked)
          .selectedColor(this.palette().controlActivated)
          .onChange((checked: boolean): void => {
            this.onFingerprintToggle(checked);
          })

        Text($r('app.string.enable_fingerprint'))
          .fontSize(14)
          .fontColor(this.palette().textPrimary)
      }
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 20 })
      .onClick((): void => {
        this.onFingerprintToggle(!this.fingerprintChecked);
      })
    }
  }

  @Builder
  actionButtonPanel(): void {
    Row({ space: 8 }) {
      if (this.hasExistingPattern || this.drawnCellCount > 0) {
        Button($r('app.string.disable_pattern_protection'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(40)
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .fontColor(this.palette().errorColor)
          .fontWeight(FontWeight.Medium)
          .onClick((): void => {
            void this.onDisableClick();
          })
      }

      Button($r('app.string.cancel'), { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(40)
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(Color.Transparent)
        .fontColor(this.palette().textSecondary)
        .fontWeight(FontWeight.Bold)
        .onClick((): void => {
          this.onCancelClick();
        })

      Button($r('app.string.set'), { type: ButtonType.Normal })
        .layoutWeight(1)
        .height(40)
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(Color.Transparent)
        .fontColor(this.palette().colorPrimary)
        .fontWeight(FontWeight.Bold)
        .onClick((): void => {
          this.onSetClick();
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 8 })
  }

  @Builder
  patternCanvasBlock(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        LockPatternView({
          controller: this.lockController,
          isLightTheme: this.themeId === ThemeMode.LIGHT
        })
          .width('100%')
          .aspectRatio(1)
      }
      .width('100%')
      .constraintSize({ maxWidth: 320, maxHeight: 320 })
      .padding(32)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      // Top app bar (aligned with upstream ToolbarActivity + v_arrow_left_dark_x24)
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.onBackButtonClick();
        })

        Text($r('app.string.set_pattern_protection'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().toolbarTitleColor)
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor(this.palette().toolbarColor)

      if (!this.ready) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.palette().colorPrimary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.isLandscape) {
        // Landscape layout (aligned with res/layout-land/activity_set_security.xml)
        Row() {
          Column() {
            Text($r('app.string.set_pattern_protection_tip'))
              .fontSize(16)
              .fontColor(this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding($r('app.float.keyline_margin'))

            Blank().layoutWeight(1)

            this.fingerprintCheckboxRow()
            this.actionButtonPanel()
          }
          .layoutWeight(1)
          .height('100%')
          .alignItems(HorizontalAlign.Center)

          Column() {
            this.patternCanvasBlock()
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        // Portrait layout (aligned with res/layout/activity_set_security.xml)
        Column() {
          Text($r('app.string.set_pattern_protection_tip'))
            .fontSize(16)
            .fontColor(this.palette().textPrimary)
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding($r('app.float.keyline_margin'))

          Column() {
            this.patternCanvasBlock()
          }
          .width('100%')
          .layoutWeight(1)

          this.fingerprintCheckboxRow()
          this.actionButtonPanel()
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      const w: number = Number(newValue.width);
      const h: number = Number(newValue.height);
      if (w > 0 && h > 0) {
        this.isLandscape = w > h;
      }
    })
  }
}
