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
 * Phase B Track P1: Pure-logic adapters and coordinators for Authentication & Security Gate UI.
 *
 * Kept free of ArkUI `@Component` / `@kit.ArkWeb` / `@kit.UserAuthenticationKit` /
 * `@kit.SensorServiceKit` imports so all orchestration, biometric state transitions,
 * shake-to-unlock handling, SetSecurityActivity host/port wiring, WebView cookie harvesting,
 * and ProgressScene token request bridging are 100% unit-testable in Node/tsc.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  FingerprintErrorAction,
  FingerprintEvent,
  MAX_RETRY_TIMES,
  PatternDisplayMode,
  PatternOutcome,
  SecurityPlatform,
  SecurityScene,
  SecuritySettings
} from '../../ehviewer/ui/scene/SecurityScene';
import { SecuritySceneShell } from '../../ehviewer/ui/scene/SecuritySceneShell';
import {
  DISPLAY_MODE_CORRECT,
  PatternViewPort,
  SecurityHost,
  SecuritySettings as SetSecuritySettings
} from '../../ehviewer/ui/SetSecurityActivity';
import { Cell } from '../../widget/lockpattern/LockPatternCell';
import { OnShakeListener, ShakeDetector } from '../../ehviewer/widget/ShakeDetector';
import {
  WebCookie,
  WebCookieManagerLike,
  WebViewSignInScene
} from '../../ehviewer/ui/scene/sign/WebViewSignInScene';
import { ProfileCookieJar } from '../../ehviewer/ui/scene/sign/GetProfileScene';
import { GalleryTokenRequester } from '../../ehviewer/ui/scene/ProgressScene';
import { EhCookieStore } from '../../ehviewer/client/EhCookieStore';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { Cookie, CookieBuilder } from '../../okhttp/Cookie';
import { HttpUrl } from '../../okhttp/HttpUrl';
import { Settings } from '../../ehviewer/Settings';
import { SceneResultCode } from '../../scene/SceneTypes';

const DOMAIN: number = 0x0000;
const TAG: string = 'AuthSecurityAdapters';

// ============================================================================
// 1. SecurityScene: Biometric, Shake & Pattern Orchestration
// ============================================================================

/** HarmonyOS `@kit.UserAuthenticationKit` `UserAuthResultCode` 常量投影（API 12+）。 */
export const USER_AUTH_RESULT_SUCCESS: number = 12500000;
export const USER_AUTH_RESULT_FAIL: number = 12500001;
export const USER_AUTH_RESULT_GENERAL_ERROR: number = 12500002;
export const USER_AUTH_RESULT_CANCELED: number = 12500003;
export const USER_AUTH_RESULT_TIMEOUT: number = 12500004;
export const USER_AUTH_RESULT_TYPE_NOT_SUPPORT: number = 12500005;
export const USER_AUTH_RESULT_TRUST_LEVEL_NOT_SUPPORT: number = 12500006;
export const USER_AUTH_RESULT_BUSY: number = 12500007;
export const USER_AUTH_RESULT_INVALID_PARAMETERS: number = 12500008;
export const USER_AUTH_RESULT_LOCKED: number = 12500009;
export const USER_AUTH_RESULT_NOT_ENROLLED: number = 12500010;
export const USER_AUTH_RESULT_CANCELED_FROM_WIDGET: number = 12500011;
export const USER_AUTH_RESULT_PIN_EXPIRED: number = 12500013;

/**
 * 将 HarmonyOS `userAuth.UserAuthResultCode` 映射为上游 `SecurityScene` 三级指纹事件。
 * - `SUCCESS` → `SUCCEEDED`
 * - `FAIL` / `CANCELED` / `TIMEOUT` / `BUSY` / `CANCELED_FROM_WIDGET` → `FAILED`（可恢复，1200ms 后复位图标）
 * - `LOCKED` / `NOT_ENROLLED` / `TYPE_NOT_SUPPORT` / 其它致命错 → `ERROR`（不可恢复，1200ms 后隐藏图标）
 */
export function classifyUserAuthResultCode(resultCode: number): FingerprintEvent {
  if (resultCode === USER_AUTH_RESULT_SUCCESS) {
    return FingerprintEvent.SUCCEEDED;
  }
  if (resultCode === USER_AUTH_RESULT_FAIL
    || resultCode === USER_AUTH_RESULT_CANCELED
    || resultCode === USER_AUTH_RESULT_TIMEOUT
    || resultCode === USER_AUTH_RESULT_BUSY
    || resultCode === USER_AUTH_RESULT_CANCELED_FROM_WIDGET) {
    return FingerprintEvent.FAILED;
  }
  return FingerprintEvent.ERROR;
}

/** 指纹图标的视觉态（对位上游 `ic_fp_40px` / `fingerprint_success` / `fingerprint_error` / `GONE|INVISIBLE`）。 */
export enum FingerprintVisualState {
  HIDDEN = 0,
  NORMAL = 1,
  SUCCESS = 2,
  ERROR = 3
}

/** 锁屏图案控件最小控制面（隔离 `LockPatternView.ets` 中的 ArkUI `struct`）。 */
export interface LockPatternControllerPort {
  setPatternCorrect(cells: Cell[]): void;
  setDisplayModeCorrect(): void;
  setDisplayModeWrong(): void;
  getCellSize(): number;
  getPatternString(): string;
}

/** 延时调度端口（便于单测同步推进 `SUCCESS_DELAY_MILLIS=100` / `ERROR_TIMEOUT_MILLIS=1200`）。 */
export interface SecurityTimerPort {
  schedule(delayMs: number, callback: () => void): number;
  cancel(timerId: number): void;
}

export class SystemSecurityTimerPort implements SecurityTimerPort {
  schedule(delayMs: number, callback: () => void): number {
    try {
      return setTimeout(callback, delayMs);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'schedule timer failed: %{public}s', msg);
      return -1;
    }
  }

  cancel(timerId: number): void {
    if (timerId < 0) {
      return;
    }
    try {
      clearTimeout(timerId);
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'cancel timer failed: %{public}s', msg);
    }
  }
}

/** 生物识别平台端口（生产实现包 `@kit.UserAuthenticationKit`）。 */
export interface BiometricAuthPort {
  isSystemSupported(): boolean;
  hasEnrolledFingerprints(): boolean;
  startAuth(
    onSucceeded: () => void,
    onFailed: () => void,
    onError: (reason: string) => void
  ): boolean;
  cancelAuth(): void;
}

/** 加速度传感器端口（生产实现包 `@kit.SensorServiceKit`）。 */
export interface ShakeSensorPort {
  start(onData: (x: number, y: number, z: number) => void): boolean;
  stop(): void;
}

/** `SecuritySceneView` 订阅的只读状态快照。 */
export class SecuritySceneViewState {
  readonly fingerprintState: FingerprintVisualState;
  readonly remainingRetries: number;
  readonly patternWrong: boolean;
  readonly biometricErrorReason: string;

  constructor(
    fingerprintState: FingerprintVisualState,
    remainingRetries: number,
    patternWrong: boolean,
    biometricErrorReason: string
  ) {
    this.fingerprintState = fingerprintState;
    this.remainingRetries = remainingRetries;
    this.patternWrong = patternWrong;
    this.biometricErrorReason = biometricErrorReason;
  }
}

/**
 * `SecuritySceneView` 核心编排器：
 * 串联 `SecuritySceneShell` / `SecurityScene`、`LockPatternControllerPort`、
 * `BiometricAuthPort`、`ShakeSensorPort` + `ShakeDetector` 与定时延迟。
 */
export class SecuritySceneCoordinator implements OnShakeListener {
  private readonly shell: SecuritySceneShell;
  private readonly patternPort: LockPatternControllerPort;
  private readonly biometricPort: BiometricAuthPort;
  private readonly shakePort: ShakeSensorPort;
  private readonly timerPort: SecurityTimerPort;
  private readonly shakeDetector: ShakeDetector;
  private readonly onStateChange: (state: SecuritySceneViewState) => void;

  private fingerprintState: FingerprintVisualState = FingerprintVisualState.HIDDEN;
  private patternWrong: boolean = false;
  private biometricErrorReason: string = '';
  private fingerprintEnabledAndAvailable: boolean = false;
  private successTimerId: number = -1;
  private errorTimerId: number = -1;
  private disposed: boolean = false;

  constructor(
    shell: SecuritySceneShell,
    patternPort: LockPatternControllerPort,
    biometricPort: BiometricAuthPort,
    shakePort: ShakeSensorPort,
    timerPort: SecurityTimerPort,
    onStateChange: (state: SecuritySceneViewState) => void,
    nowProvider?: () => number
  ) {
    this.shell = shell;
    this.patternPort = patternPort;
    this.biometricPort = biometricPort;
    this.shakePort = shakePort;
    this.timerPort = timerPort;
    this.onStateChange = onStateChange;
    this.shakeDetector = nowProvider !== undefined ? new ShakeDetector(nowProvider) : new ShakeDetector();
  }

  private safeHasEnrolledFingerprints(): boolean {
    try {
      return this.biometricPort.hasEnrolledFingerprints();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'hasEnrolledFingerprints threw: %{public}s', msg);
      return false;
    }
  }

  private safeIsSystemSupported(): boolean {
    try {
      return this.biometricPort.isSystemSupported();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'isSystemSupported threw: %{public}s', msg);
      return false;
    }
  }

  start(): void {
    this.disposed = false;
    this.shell.setEnrolledFingerprintsProvider((): boolean => this.safeHasEnrolledFingerprints());
    this.shakeDetector.setOnShakeListener(this);

    try {
      this.shakePort.start((x: number, y: number, z: number): void => {
        this.onAccelerometerData(x, y, z);
      });
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'shakePort.start failed: %{public}s', msg);
    }

    const platform: SecurityPlatform = this.shell.createPlatform();
    const settings: SecuritySettings = this.shell.getSettings();
    const available: boolean = SecurityScene.fingerprintAvailable(
      platform,
      settings,
      this.safeIsSystemSupported()
    );
    this.fingerprintEnabledAndAvailable = available;

    if (available) {
      this.fingerprintState = FingerprintVisualState.NORMAL;
      this.emitState();
      this.triggerBiometricAuth();
    } else {
      this.fingerprintState = FingerprintVisualState.HIDDEN;
      this.emitState();
    }
  }

  stop(): void {
    this.disposed = true;
    this.clearTimers();
    try {
      this.shakePort.stop();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'shakePort.stop failed: %{public}s', msg);
    }
    try {
      this.biometricPort.cancelAuth();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'biometricPort.cancelAuth failed: %{public}s', msg);
    }
  }

  /** 用户点击指纹图标重新拉起认证（仅当指纹可用且未隐藏/未成功时）。 */
  retryBiometricAuth(): boolean {
    if (this.disposed || !this.fingerprintEnabledAndAvailable) {
      return false;
    }
    if (this.fingerprintState === FingerprintVisualState.HIDDEN
      || this.fingerprintState === FingerprintVisualState.SUCCESS) {
      return false;
    }
    return this.triggerBiometricAuth();
  }

  private triggerBiometricAuth(): boolean {
    try {
      return this.biometricPort.startAuth(
        (): void => {
          this.handleBiometricEvent(FingerprintEvent.SUCCEEDED, '');
        },
        (): void => {
          this.handleBiometricEvent(FingerprintEvent.FAILED, '');
        },
        (reason: string): void => {
          this.handleBiometricEvent(FingerprintEvent.ERROR, reason);
        }
      );
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'biometricPort.startAuth threw: %{public}s', msg);
      this.handleBiometricEvent(FingerprintEvent.ERROR, msg);
      return false;
    }
  }

  onPatternStart(): void {
    if (this.disposed) {
      return;
    }
    if (this.patternWrong) {
      this.patternWrong = false;
      this.emitState();
    }
  }

  onPatternCleared(): void {
    if (this.disposed) {
      return;
    }
    if (this.patternWrong) {
      this.patternWrong = false;
      this.emitState();
    }
  }

  onPatternDetected(pattern: Cell[]): PatternOutcome {
    if (this.disposed) {
      return PatternOutcome.WRONG;
    }
    const settings: SecuritySettings = this.shell.getSettings();
    const platform: SecurityPlatform = this.shell.createPlatform();
    const outcome: PatternOutcome = this.shell.getLogic().checkPattern(pattern, settings);

    if (outcome === PatternOutcome.SUCCESS) {
      this.patternWrong = false;
      this.patternPort.setDisplayModeCorrect();
      this.emitState();
      SecurityScene.grantOnPatternSuccess(platform);
      return outcome;
    }

    const displayMode: PatternDisplayMode | null = SecurityScene.displayModeFor(outcome);
    if (displayMode === PatternDisplayMode.WRONG || outcome === PatternOutcome.EXHAUSTED) {
      this.patternPort.setDisplayModeWrong();
    }
    this.patternWrong = true;
    this.emitState();

    if (outcome === PatternOutcome.EXHAUSTED) {
      SecurityScene.closeOnExhausted(platform);
    }
    return outcome;
  }

  /**
   * 处理生物识别事件（严格对齐上游：指纹失败/错误**绝不扣减**手势重试次数）。
   */
  handleBiometricEvent(event: FingerprintEvent, reason: string = ''): void {
    if (this.disposed) {
      return;
    }
    if (this.errorTimerId >= 0) {
      this.timerPort.cancel(this.errorTimerId);
      this.errorTimerId = -1;
    }
    if (event === FingerprintEvent.SUCCEEDED) {
      this.biometricErrorReason = '';
      this.fingerprintState = FingerprintVisualState.SUCCESS;
      this.emitState();
      const delay: number = SecurityScene.fingerprintDelayFor(FingerprintEvent.SUCCEEDED);
      this.successTimerId = this.timerPort.schedule(delay, (): void => {
        this.successTimerId = -1;
        if (!this.disposed) {
          this.shell.grantAccess();
        }
      });
      return;
    }

    // FAILED (recoverable) / ERROR (unrecoverable): 不扣减 retryTimes
    this.biometricErrorReason = reason;
    this.fingerprintState = FingerprintVisualState.ERROR;
    this.emitState();
    const action: FingerprintErrorAction | null = SecurityScene.fingerprintErrorAction(event);
    const delay: number = SecurityScene.fingerprintDelayFor(event);
    this.errorTimerId = this.timerPort.schedule(delay, (): void => {
      this.errorTimerId = -1;
      if (this.disposed) {
        return;
      }
      if (action === FingerprintErrorAction.HIDE_ICON) {
        this.fingerprintState = FingerprintVisualState.HIDDEN;
      } else {
        this.fingerprintState = FingerprintVisualState.NORMAL;
      }
      this.emitState();
    });
  }

  onAccelerometerData(x: number, y: number, z: number): boolean {
    if (this.disposed) {
      return false;
    }
    return this.shakeDetector.onSensorChanged(x, y, z);
  }

  onShake(count: number): void {
    if (this.disposed) {
      return;
    }
    const settings: SecuritySettings = this.shell.getSettings();
    const platform: SecurityPlatform = this.shell.createPlatform();
    const unlocked: boolean = this.shell.getLogic().handleShake(count, settings, platform);
    if (unlocked) {
      this.emitState();
    }
  }

  getState(): SecuritySceneViewState {
    return new SecuritySceneViewState(
      this.fingerprintState,
      this.shell.getLogic().remainingRetries(),
      this.patternWrong,
      this.biometricErrorReason
    );
  }

  isFingerprintAvailable(): boolean {
    return this.fingerprintEnabledAndAvailable;
  }

  private clearTimers(): void {
    if (this.successTimerId >= 0) {
      this.timerPort.cancel(this.successTimerId);
      this.successTimerId = -1;
    }
    if (this.errorTimerId >= 0) {
      this.timerPort.cancel(this.errorTimerId);
      this.errorTimerId = -1;
    }
  }

  private emitState(): void {
    this.onStateChange(this.getState());
  }
}

// ============================================================================
// 2. SetSecurityPage: PatternViewPort, SecuritySettings & SecurityHost Adapters
// ============================================================================

/**
 * 将 `LockPatternControllerPort` 适配为 `SetSecurityActivity` 的 `PatternViewPort`。
 * 注意：`SetSecurityActivity.DISPLAY_MODE_CORRECT = 2`，而 `LockPatternView.DisplayMode.Correct = 0`；
 * 本适配器显式映射到 `setPatternCorrect()`（绿态回显），避免误传入 `DisplayMode.Wrong`。
 */
export class LockPatternViewPortAdapter implements PatternViewPort {
  private readonly controller: LockPatternControllerPort;

  constructor(controller: LockPatternControllerPort) {
    this.controller = controller;
  }

  setPattern(mode: number, cells: Object | null): void {
    const cellList: Cell[] = Array.isArray(cells) ? (cells as Cell[]) : [];
    if (mode === DISPLAY_MODE_CORRECT || mode === 0) {
      this.controller.setPatternCorrect(cellList);
      return;
    }
    this.controller.setPatternCorrect(cellList);
    this.controller.setDisplayModeWrong();
  }

  getCellSize(): number {
    return this.controller.getCellSize();
  }

  getPatternString(): string {
    return this.controller.getPatternString();
  }
}

/** 生产侧接入 `Settings.getSecurity/putSecurity/getEnableFingerprint/putEnableFingerprint`。 */
export class SettingsBackedSecuritySettings implements SetSecuritySettings {
  getSecurity(): string | null {
    return Settings.getSecurity();
  }

  putSecurity(security: string): void {
    Settings.putSecurity(security);
  }

  getEnableFingerprint(): boolean {
    return Settings.getEnableFingerprint();
  }

  putEnableFingerprint(enabled: boolean): void {
    Settings.putEnableFingerprint(enabled);
  }
}

/** `SetSecurityPage` 对接 `SetSecurityActivity` 的 `SecurityHost` 实现。 */
export class SetSecurityPageHostAdapter implements SecurityHost {
  private patternPort: PatternViewPort | null;
  private readonly enrolledChecker: () => boolean;
  private readonly onFingerprintUiUpdate: (visible: boolean, checked: boolean) => void;
  private readonly onFinish: () => void;

  private fingerprintVisible: boolean = false;
  private fingerprintChecked: boolean = false;
  private navigationIcon: string = '';

  constructor(
    patternPort: PatternViewPort | null,
    enrolledChecker: () => boolean,
    onFingerprintUiUpdate: (visible: boolean, checked: boolean) => void,
    onFinish: () => void
  ) {
    this.patternPort = patternPort;
    this.enrolledChecker = enrolledChecker;
    this.onFingerprintUiUpdate = onFingerprintUiUpdate;
    this.onFinish = onFinish;
  }

  hasEnrolledFingerprints(): boolean {
    try {
      return this.enrolledChecker();
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'SetSecurityPage biometric enrollment check failed: %{public}s', msg);
      return false;
    }
  }

  setFingerprintVisible(visible: boolean): void {
    this.fingerprintVisible = visible;
    this.onFingerprintUiUpdate(this.fingerprintVisible, this.fingerprintChecked);
  }

  setFingerprintChecked(checked: boolean): void {
    this.fingerprintChecked = checked;
    this.onFingerprintUiUpdate(this.fingerprintVisible, this.fingerprintChecked);
  }

  isFingerprintVisible(): boolean {
    return this.fingerprintVisible;
  }

  isFingerprintChecked(): boolean {
    return this.fingerprintChecked;
  }

  getPatternView(): PatternViewPort | null {
    return this.patternPort;
  }

  /** 对位上游 `onDestroy`: 释放对图案控件的引用。 */
  detachPatternView(): void {
    this.patternPort = null;
  }

  setNavigationIcon(icon: string): void {
    this.navigationIcon = icon;
  }

  getNavigationIcon(): string {
    return this.navigationIcon;
  }

  finish(): void {
    this.onFinish();
  }
}

// ============================================================================
// 3. WebViewSignInScene & GetProfileScene: Cookie Manager & Store Adapters
// ============================================================================

/** 对位 `@kit.ArkWeb` `webview.WebCookieManager` 静态方法的后端接口。 */
export interface RawWebCookieBackend {
  saveCookieSync(): void;
  clearAllCookiesSync(): void;
  clearSessionCookieSync(): void;
  putAcceptCookieEnabled(accept: boolean): void;
  putAcceptThirdPartyCookieEnabled(accept: boolean): void;
  fetchCookieSync(url: string): string;
  configCookieSync(url: string, value: string): void;
}

/**
 * 将 ArkWeb `WebCookieManager` 适配为 `WebCookieManagerLike` + `ProfileCookieJar`。
 * 读取登录 Cookie 时会同时合并 `url`、`EhUrl.HOST_E` 与 `EhUrl.URL_FORUMS` 下的键值对，
 * 对齐上游登录后从 `EhUrl.HOST_E` 收获 `ipb_member_id` / `ipb_pass_hash` 的行为。
 */
export class ArkWebCookieManagerAdapter implements WebCookieManagerLike, ProfileCookieJar {
  private readonly backend: RawWebCookieBackend;

  constructor(backend: RawWebCookieBackend) {
    this.backend = backend;
  }

  flush(): void {
    this.backend.saveCookieSync();
  }

  removeAllCookies(): void {
    this.backend.clearAllCookiesSync();
  }

  removeSessionCookies(): void {
    this.backend.clearSessionCookieSync();
  }

  setAcceptCookie(accept: boolean): void {
    this.backend.putAcceptCookieEnabled(accept);
  }

  setAcceptFileSchemeCookies(accept: boolean): void {
    this.backend.putAcceptThirdPartyCookieEnabled(accept);
  }

  setCookie(url: string, cookie: string): void {
    this.backend.configCookieSync(url, cookie);
  }

  getCookie(url: string): string {
    const urls: string[] = [];
    if (url.length > 0) {
      urls.push(url);
    }
    if (url !== EhUrl.HOST_E) {
      urls.push(EhUrl.HOST_E);
    }
    if (url !== EhUrl.URL_FORUMS) {
      urls.push(EhUrl.URL_FORUMS);
    }
    const merged: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < urls.length; i++) {
      const targetUrl: string = urls[i];
      try {
        const raw: string = this.backend.fetchCookieSync(targetUrl);
        if (raw.length === 0) {
          continue;
        }
        const parsed: WebCookie[] = WebViewSignInScene.parseCookies(raw, targetUrl);
        for (let j = 0; j < parsed.length; j++) {
          const item: WebCookie = parsed[j];
          if (!merged.has(item.name) || item.value.length > 0) {
            merged.set(item.name, item.value);
          }
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'fetchCookieSync(%{public}s) failed: %{public}s', targetUrl, msg);
      }
    }
    const pairs: string[] = [];
    merged.forEach((value: string, name: string): void => {
      pairs.push(name + '=' + value);
    });
    return pairs.join('; ');
  }
}

/**
 * 将 `ProfileCookieJar` 写回 `EhCookieStore`（由 `RdbCookieStore` 持久化落库）。
 * 与上游 `WebViewSignInScene.addCookie` 逐条对齐：同步写入 `e-hentai.org` 与 `exhentai.org` 双域，
 * `forcePersistent=true / forceLongLive=true / forceNotHostOnly=true`。
 */
export class EhCookieStoreProfileJar implements ProfileCookieJar {
  private readonly store: EhCookieStore;

  constructor(store: EhCookieStore) {
    this.store = store;
  }

  setCookie(url: string, cookieLine: string): void {
    const targetUrl: string = url.length > 0 ? url : EhUrl.HOST_E;
    const parsedUrl: HttpUrl | null = HttpUrl.parse(targetUrl);
    if (parsedUrl === null) {
      hilog.warn(DOMAIN, TAG, 'EhCookieStoreProfileJar.setCookie: invalid url=%{public}s', targetUrl);
      return;
    }
    const parsed: Cookie | null = Cookie.parse(parsedUrl, cookieLine);
    if (parsed === null) {
      const eq: number = cookieLine.indexOf('=');
      if (eq <= 0) {
        hilog.warn(DOMAIN, TAG, 'EhCookieStoreProfileJar.setCookie: unparsable cookie skipped');
        return;
      }
      const name: string = cookieLine.substring(0, eq).trim();
      const value: string = cookieLine.substring(eq + 1).trim();
      this.writeForEhDomains(
        new CookieBuilder()
          .name(name)
          .value(value)
          .domain(EhUrl.DOMAIN_E)
          .path('/')
          .expiresAt(EhCookieStore.MAX_EXPIRES)
          .build(),
        parsedUrl.host()
      );
      return;
    }
    this.writeForEhDomains(parsed, parsedUrl.host());
  }

  getCookie(host: string): string {
    const normalized: string = host.startsWith('http://') || host.startsWith('https://')
      ? host
      : 'https://' + host + '/';
    const parsedUrl: HttpUrl | null = HttpUrl.parse(normalized);
    if (parsedUrl === null) {
      hilog.warn(DOMAIN, TAG, 'EhCookieStoreProfileJar.getCookie: invalid host=%{public}s', host);
      return '';
    }
    return this.store.getCookieHeader(parsedUrl);
  }

  private writeForEhDomains(cookie: Cookie, requestHost: string): void {
    const domains: string[] = [EhUrl.DOMAIN_E, EhUrl.DOMAIN_EX];
    if (requestHost.length > 0
      && requestHost !== EhUrl.DOMAIN_E
      && requestHost !== EhUrl.DOMAIN_EX) {
      domains.push(requestHost);
    }
    for (let i = 0; i < domains.length; i++) {
      const mirrored: Cookie = EhCookieStore.newCookie(cookie, domains[i], true, true, true);
      this.store.addCookie(mirrored);
    }
    if (this.store.hasSignedIn()) {
      Settings.setLoginState(true);
    }
  }
}

/** 判定原始 Cookie 串是否已同时包含 E-Hentai 必需的两枚登录 Cookie。 */
export function hasEhLoginCookies(rawCookieString: string): boolean {
  if (rawCookieString.length === 0) {
    return false;
  }
  const cookies: WebCookie[] = WebViewSignInScene.parseCookies(rawCookieString, EhUrl.HOST_E);
  let hasMemberId: boolean = false;
  let hasPassHash: boolean = false;
  for (let i = 0; i < cookies.length; i++) {
    const c: WebCookie = cookies[i];
    if (c.name === EhCookieStore.KEY_IPD_MEMBER_ID && c.value.length > 0) {
      hasMemberId = true;
    } else if (c.name === EhCookieStore.KEY_IPD_PASS_HASH && c.value.length > 0) {
      hasPassHash = true;
    }
  }
  return hasMemberId && hasPassHash;
}

/**
 * `WebViewSignInSceneView` 编排器：
 * 负责在加载前执行 `prepareCookies()`、`onPageEnd` 自动检测登录完成、
 * 以及手动收获 Cookie 并回写 `ProfileCookieJar` / `RdbCookieStore`。
 */
export class WebViewSignInCoordinator {
  private readonly scene: WebViewSignInScene;
  private readonly cookieManager: WebCookieManagerLike;
  private readonly cookieJar: ProfileCookieJar | null;
  private readonly signInUrl: string;
  private finished: boolean = false;

  constructor(
    scene: WebViewSignInScene,
    cookieManager: WebCookieManagerLike,
    cookieJar: ProfileCookieJar | null,
    signInUrl: string = EhUrl.URL_SIGN_IN
  ) {
    this.scene = scene;
    this.cookieManager = cookieManager;
    this.cookieJar = cookieJar;
    this.signInUrl = signInUrl.length > 0 ? signInUrl : EhUrl.URL_SIGN_IN;
  }

  getSignInUrl(): string {
    return this.signInUrl;
  }

  /** 在 `Web` 加载之前配置 CookieManager 并执行 5 步 `prepareCookies()`。 */
  init(): boolean {
    this.finished = false;
    this.scene.setCookieManager(this.cookieManager);
    if (this.cookieJar !== null) {
      this.scene.setCookieJar(this.cookieJar);
    }
    this.scene.setSignInUrl(this.signInUrl);
    return this.scene.prepareCookies();
  }

  /** 上游 `onPageFinished`：检测到 `ipb_member_id` + `ipb_pass_hash` 后自动收割并结束。 */
  onPageEnd(url: string): boolean {
    if (this.finished || this.scene.isInitFailed()) {
      return false;
    }
    const raw: string = this.cookieManager.getCookie(url.length > 0 ? url : this.signInUrl);
    if (!hasEhLoginCookies(raw)) {
      return false;
    }
    this.finished = true;
    this.scene.finishWithCookies();
    return this.scene.resultCode === SceneResultCode.OK;
  }

  /** 用户主动点击“完成/确认”时显式收获当前 WebView Cookie。 */
  harvestCookiesManually(): boolean {
    if (this.finished) {
      return this.scene.resultCode === SceneResultCode.OK;
    }
    this.finished = true;
    this.scene.finishWithCookies();
    return this.scene.resultCode === SceneResultCode.OK;
  }

  /** 检查当前是否已检测到登录 Cookie（用于 UI 提示）。 */
  hasDetectedLoginCookies(): boolean {
    const raw: string = this.cookieManager.getCookie(this.signInUrl);
    return hasEhLoginCookies(raw);
  }

  /** 初始化失败弹窗确认/取消。 */
  dismissInitFailedDialog(): void {
    this.finished = true;
    this.scene.onInitFailedDialogDismissed();
  }

  isFinished(): boolean {
    return this.finished;
  }
}

// ============================================================================
// 4. ProgressScene: Async EhEngine.getGalleryToken Bridge
// ============================================================================

/**
 * 将异步 `Promise<string>` 的 token 拉取器（如 `EhEngine.getGalleryToken`）
 * 适配为 `ProgressScene` 所需的同步 `GalleryTokenRequester` 接口。
 */
export class AsyncGalleryTokenRequester implements GalleryTokenRequester {
  private readonly fetcher: (gid: number, pToken: string, page: number) => Promise<string>;
  private readonly onSuccess: (token: string) => void;
  private readonly onFailure: (readableError: string) => void;
  private inFlight: boolean = false;

  constructor(
    fetcher: (gid: number, pToken: string, page: number) => Promise<string>,
    onSuccess: (token: string) => void,
    onFailure: (readableError: string) => void
  ) {
    this.fetcher = fetcher;
    this.onSuccess = onSuccess;
    this.onFailure = onFailure;
  }

  isInFlight(): boolean {
    return this.inFlight;
  }

  requestGalleryToken(gid: number, pToken: string, page: number): boolean {
    if (this.inFlight) {
      return true;
    }
    this.inFlight = true;
    this.fetcher(gid, pToken, page).then((token: string): void => {
      this.inFlight = false;
      this.onSuccess(token);
    }).catch((err: Object): void => {
      this.inFlight = false;
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG,
        'requestGalleryToken failed (gid=%{public}d page=%{public}d): %{public}s',
        gid, page, msg);
      this.onFailure(msg);
    });
    return true;
  }
}

/** 供测试及视图读取的默认重试上限常量转出口。 */
export const DEFAULT_SECURITY_MAX_RETRIES: number = MAX_RETRY_TIMES;
