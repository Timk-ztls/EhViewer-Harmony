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
 * Phase B Track P1: SecuritySceneView (@Component V1).
 *
 * Renders `LockPatternView` wired to `SecuritySceneShell` / `SecurityScene`,
 * integrates HarmonyOS biometric authentication (`@kit.UserAuthenticationKit`)
 * and accelerometer shake-to-unlock (`@kit.SensorServiceKit` + `ShakeDetector`).
 */

import { userAuth } from '@kit.UserAuthenticationKit';
import { sensor } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemeMode, ThemePalette, ThemeTokens } from '../../../common/theme/ThemeTokens';
import { SecuritySceneShell } from '../../ehviewer/ui/scene/SecuritySceneShell';
import { MAX_RETRY_TIMES, FingerprintEvent } from '../../ehviewer/ui/scene/SecurityScene';
import { GetText } from '../../ehviewer/GetText';
import { Cell } from '../../widget/lockpattern/LockPatternCell';
import {
  DisplayMode,
  LockPatternController,
  LockPatternView,
  OnPatternListener
} from '../../widget/lockpattern/LockPatternView';
import { FingerprintError } from '../drawable/fingerprint_error';
import { FingerprintSuccess } from '../drawable/fingerprint_success';
import {
  BiometricAuthPort,
  classifyUserAuthResultCode,
  FingerprintVisualState,
  LockPatternControllerPort,
  SecuritySceneCoordinator,
  SecuritySceneViewState,
  ShakeSensorPort,
  SystemSecurityTimerPort,
  USER_AUTH_RESULT_NOT_ENROLLED
} from './AuthSecurityAdapters';

const DOMAIN: number = 0x0000;
const TAG: string = 'SecuritySceneView';
const ACCELEROMETER_INTERVAL_UI_NS: number = 60000000;

class ControllerPortBridge implements LockPatternControllerPort {
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

class SecurityPatternListener implements OnPatternListener {
  private readonly coordinator: SecuritySceneCoordinator;

  constructor(coordinator: SecuritySceneCoordinator) {
    this.coordinator = coordinator;
  }

  onPatternStart(): void {
    this.coordinator.onPatternStart();
  }

  onPatternCleared(): void {
    this.coordinator.onPatternCleared();
  }

  onPatternCellAdded(_pattern: Cell[]): void {
  }

  onPatternDetected(pattern: Cell[]): void {
    this.coordinator.onPatternDetected(pattern);
  }
}

class HarmonyBiometricAuthPort implements BiometricAuthPort {
  private activeInstance: userAuth.UserAuthInstance | null = null;
  private activeCallback: userAuth.IAuthCallback | null = null;

  isSystemSupported(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL1);
      return true;
    } catch (e) {
      const bizErr: BusinessError = e as BusinessError;
      if (bizErr !== undefined && bizErr !== null && bizErr.code === USER_AUTH_RESULT_NOT_ENROLLED) {
        return true;
      }
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'biometric isSystemSupported check failed: %{public}s', msg);
      return false;
    }
  }

  hasEnrolledFingerprints(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL1);
      const enrolled: userAuth.EnrolledState = userAuth.getEnrolledState(userAuth.UserAuthType.FINGERPRINT);
      return enrolled.credentialCount > 0;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'biometric hasEnrolledFingerprints check failed: %{public}s', msg);
      return false;
    }
  }

  startAuth(
    onSucceeded: () => void,
    onFailed: () => void,
    onError: (reason: string) => void
  ): boolean {
    this.cancelAuth();
    try {
      const titleText: string = GetText.getString('settings_privacy_pattern_protection_title');
      const authParam: userAuth.AuthParam = {
        challenge: new Uint8Array([0x45, 0x68, 0x56, 0x31]),
        authType: [userAuth.UserAuthType.FINGERPRINT],
        authTrustLevel: userAuth.AuthTrustLevel.ATL1
      };
      const widgetParam: userAuth.WidgetParam = {
        title: titleText.length > 0 ? titleText : 'EhViewer'
      };
      const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      let settled: boolean = false;
      // NAPI 在系统指纹认证回调时可能以非类实例 `this` 调用 `onResult`，必须使用纯对象字面量 + 闭包。
      const cb: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          const code: number = result !== undefined && result !== null ? result.result : -1;
          hilog.info(DOMAIN, TAG, 'biometric auth onResult code=%{public}d settled=%{public}s',
            code, String(settled));
          if (settled) {
            return;
          }
          settled = true;
          if (this.activeInstance === instance) {
            this.activeInstance = null;
            this.activeCallback = null;
          }
          try {
            instance.off('result', cb);
          } catch (offErr) {
            const offMsg: string = offErr instanceof Error ? offErr.message : String(offErr);
            hilog.warn(DOMAIN, TAG, 'biometric off(result) in callback failed: %{public}s', offMsg);
          }
          const event: FingerprintEvent = classifyUserAuthResultCode(code);
          if (event === FingerprintEvent.SUCCEEDED) {
            onSucceeded();
            return;
          }
          if (event === FingerprintEvent.FAILED) {
            hilog.warn(DOMAIN, TAG, 'biometric auth recoverable failure: code=%{public}d', code);
            onFailed();
            return;
          }
          hilog.warn(DOMAIN, TAG, 'biometric auth unrecoverable error: code=%{public}d', code);
          onError(String(code));
        }
      };
      this.activeInstance = instance;
      this.activeCallback = cb;
      instance.on('result', cb);
      instance.start();
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'biometric startAuth failed: %{public}s', msg);
      this.activeInstance = null;
      this.activeCallback = null;
      onError(msg);
      return false;
    }
  }

  cancelAuth(): void {
    const instance: userAuth.UserAuthInstance | null = this.activeInstance;
    const cb: userAuth.IAuthCallback | null = this.activeCallback;
    this.activeInstance = null;
    this.activeCallback = null;
    if (instance === null) {
      return;
    }
    try {
      if (cb !== null) {
        instance.off('result', cb);
      } else {
        instance.off('result');
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'biometric off(result) failed: %{public}s', msg);
    }
    try {
      instance.cancel();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'biometric cancel() failed: %{public}s', msg);
    }
  }
}

class HarmonyShakeSensorPort implements ShakeSensorPort {
  private subscribed: boolean = false;
  private callback: ((data: sensor.AccelerometerResponse) => void) | null = null;

  start(onData: (x: number, y: number, z: number) => void): boolean {
    this.stop();
    if (canIUse('SystemCapability.Sensors.Sensor')) {
      try {
        const cb: (data: sensor.AccelerometerResponse) => void =
          (data: sensor.AccelerometerResponse): void => {
            onData(data.x, data.y, data.z);
          };
        const opts: sensor.Options = { interval: ACCELEROMETER_INTERVAL_UI_NS };
        sensor.on(sensor.SensorId.ACCELEROMETER, cb, opts);
        this.callback = cb;
        this.subscribed = true;
        return true;
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'accelerometer sensor.on failed: %{public}s', msg);
        this.subscribed = false;
        this.callback = null;
        return false;
      }
    }
    return false;
  }

  stop(): void {
    if (!this.subscribed) {
      return;
    }
    const cb: ((data: sensor.AccelerometerResponse) => void) | null = this.callback;
    this.subscribed = false;
    this.callback = null;
    if (canIUse('SystemCapability.Sensors.Sensor')) {
      try {
        if (cb !== null) {
          sensor.off(sensor.SensorId.ACCELEROMETER, cb);
        } else {
          sensor.off(sensor.SensorId.ACCELEROMETER);
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'accelerometer sensor.off failed: %{public}s', msg);
      }
    }
  }
}

@Component
export struct SecuritySceneView {
  shell: SecuritySceneShell | null = null;
  @Prop themeId: number = ThemeMode.LIGHT;
  @Prop isLightTheme: boolean = true;

  @State fingerprintState: FingerprintVisualState = FingerprintVisualState.HIDDEN;
  @State remainingRetries: number = MAX_RETRY_TIMES;
  @State patternWrong: boolean = false;

  private lockController: LockPatternController = new LockPatternController();
  private coordinator: SecuritySceneCoordinator | null = null;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  aboutToAppear(): void {
    this.bindShell();
  }

  aboutToDisappear(): void {
    this.teardownCoordinator();
  }

  private teardownCoordinator(): void {
    if (this.coordinator !== null) {
      this.coordinator.stop();
      this.coordinator = null;
    }
  }

  private bindShell(): void {
    this.teardownCoordinator();
    const currentShell: SecuritySceneShell | null = this.shell;
    if (currentShell === null) {
      this.fingerprintState = FingerprintVisualState.HIDDEN;
      this.remainingRetries = MAX_RETRY_TIMES;
      this.patternWrong = false;
      return;
    }

    const patternPort: ControllerPortBridge = new ControllerPortBridge(this.lockController);
    const biometricPort: HarmonyBiometricAuthPort = new HarmonyBiometricAuthPort();
    const shakePort: HarmonyShakeSensorPort = new HarmonyShakeSensorPort();
    const timerPort: SystemSecurityTimerPort = new SystemSecurityTimerPort();

    const coord: SecuritySceneCoordinator = new SecuritySceneCoordinator(
      currentShell,
      patternPort,
      biometricPort,
      shakePort,
      timerPort,
      (state: SecuritySceneViewState): void => {
        this.fingerprintState = state.fingerprintState;
        this.remainingRetries = state.remainingRetries;
        this.patternWrong = state.patternWrong;
      }
    );
    this.lockController.setOnPatternListener(new SecurityPatternListener(coord));
    this.coordinator = coord;
    coord.start();
  }

  private onFingerprintTap(): void {
    if (this.coordinator !== null) {
      this.coordinator.retryBiometricAuth();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 20 }) {
        Column() {
          LockPatternView({
            controller: this.lockController,
            isLightTheme: this.themeId === ThemeMode.LIGHT && this.isLightTheme
          })
            .width('100%')
            .aspectRatio(1)
        }
        .width('100%')
        .constraintSize({ maxWidth: 320, maxHeight: 320 })

        if (this.patternWrong) {
          Text($r('app.string.error_something_wrong_happened'))
            .fontSize(13)
            .fontColor(this.palette().errorColor)
            .textAlign(TextAlign.Center)
            .width('100%')
        }

        if (this.fingerprintState === FingerprintVisualState.NORMAL) {
          Column() {
            Image($r('app.media.ic_fp_40px'))
              .width(40)
              .height(40)
              .objectFit(ImageFit.Contain)
          }
          .padding(8)
          .onClick((): void => {
            this.onFingerprintTap();
          })
        } else if (this.fingerprintState === FingerprintVisualState.SUCCESS) {
          Column() {
            FingerprintSuccess({ iconSize: 40 })
          }
          .padding(8)
        } else if (this.fingerprintState === FingerprintVisualState.ERROR) {
          Column() {
            FingerprintError({ iconSize: 40 })
          }
          .padding(8)
          .onClick((): void => {
            this.onFingerprintTap();
          })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 360 })
      .padding(32)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
