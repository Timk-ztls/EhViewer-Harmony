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
 * Phase B Track P1 unit tests:
 *   1. SecuritySceneShell + SecuritySceneCoordinator (pattern, biometric delays/retries, shake==10, stop cleanup)
 *   2. SetSecurityPage adapters (LockPatternViewPortAdapter DisplayMode.Correct mapping,
 *      SetSecurityPageHostAdapter, <=1 clears, 3-way fingerprint AND, throw->false, SettingsBackedSecuritySettings)
 *   3. WebViewSignInSceneConcrete + ArkWebCookieManagerAdapter + EhCookieStoreProfileJar + WebViewSignInCoordinator
 *   4. GetProfileSceneShell (lifecycle, planPageFinished, JS string unquote, parse & result delivery, intercept)
 *   5. ProgressSceneShell + AsyncGalleryTokenRequester (init, failure, retry, success->GalleryDetailScene args, restore)
 *
 * Run:
 *   pwsh -NoProfile -ExecutionPolicy Bypass -File harmony/entry/src/test/ui-scene/run.ps1 -Filter p1-auth-security
 */

import {
  ERROR_TIMEOUT_MILLIS,
  FingerprintEvent,
  MAX_RETRY_TIMES,
  PatternOutcome,
  SecuritySettings,
  SUCCESS_DELAY_MILLIS
} from '../../main/ets/hippo/ehviewer/ui/scene/SecurityScene';
import { SecuritySceneShell } from '../../main/ets/hippo/ehviewer/ui/scene/SecuritySceneShell';
import {
  DISPLAY_MODE_CORRECT,
  DRAWABLE_BACK,
  SetSecurityActivity
} from '../../main/ets/hippo/ehviewer/ui/SetSecurityActivity';
import { WebViewSignInSceneConcrete } from '../../main/ets/hippo/ehviewer/ui/scene/sign/WebViewSignInSceneConcrete';
import {
  AVATAR,
  DISPLAY_NAME,
  GetProfileScene,
  HttpResponseLike,
  PageFinishedAction,
  ProfileCookieJar,
  ProfileHttpExecutor,
  ProfileResult,
  REQUEST_CODE_PROFILE,
  WebRequestLike,
  WebRequestType,
  WebResponsePlan
} from '../../main/ets/hippo/ehviewer/ui/scene/sign/GetProfileScene';
import { GetProfileSceneShell } from '../../main/ets/hippo/ehviewer/ui/scene/sign/GetProfileSceneShell';
import {
  ACTION_GALLERY_TOKEN,
  DEFAULT_GID,
  DEFAULT_PAGE,
  DETAIL_ACTION_GID_TOKEN,
  DETAIL_KEY_ACTION,
  DETAIL_KEY_GID,
  DETAIL_KEY_PAGE,
  DETAIL_KEY_TOKEN,
  GalleryTokenRequester,
  KEY_ACTION,
  KEY_GID,
  KEY_PAGE,
  KEY_PTOKEN,
  ProgressArgs,
  ProgressScene,
  ProgressState,
  ProgressView
} from '../../main/ets/hippo/ehviewer/ui/scene/ProgressScene';
import { ProgressSceneShell } from '../../main/ets/hippo/ehviewer/ui/scene/ProgressSceneShell';
import {
  ArkWebCookieManagerAdapter,
  AsyncGalleryTokenRequester,
  BiometricAuthPort,
  classifyUserAuthResultCode,
  EhCookieStoreProfileJar,
  FingerprintVisualState,
  hasEhLoginCookies,
  LockPatternControllerPort,
  LockPatternViewPortAdapter,
  RawWebCookieBackend,
  SecuritySceneCoordinator,
  SecuritySceneViewState,
  SecurityTimerPort,
  SetSecurityPageHostAdapter,
  SettingsBackedSecuritySettings,
  ShakeSensorPort,
  USER_AUTH_RESULT_CANCELED,
  USER_AUTH_RESULT_FAIL,
  USER_AUTH_RESULT_LOCKED,
  USER_AUTH_RESULT_NOT_ENROLLED,
  USER_AUTH_RESULT_SUCCESS,
  USER_AUTH_RESULT_TIMEOUT,
  USER_AUTH_RESULT_TYPE_NOT_SUPPORT,
  WebViewSignInCoordinator
} from '../../main/ets/hippo/ui/scene/AuthSecurityAdapters';
import { Cell } from '../../main/ets/hippo/widget/lockpattern/LockPatternCell';
import { LockPatternUtils } from '../../main/ets/hippo/widget/lockpattern/LockPatternUtils';
import { EhCookieStore } from '../../main/ets/hippo/ehviewer/client/EhCookieStore';
import { EhUrl } from '../../main/ets/hippo/ehviewer/client/EhUrl';
import { Cookie } from '../../main/ets/hippo/okhttp/Cookie';
import { HttpUrl } from '../../main/ets/hippo/okhttp/HttpUrl';
import { CookieStoreBackend } from '../../main/ets/hippo/network/CookieRepository';
import { Settings } from '../../main/ets/hippo/ehviewer/Settings';
import {
  SceneArgs,
  SceneResultCode,
  SceneResultReceiver,
  SceneTransitionHelper,
  StageHost
} from '../../main/ets/hippo/scene/SceneTypes';
import { SceneFragment } from '../../main/ets/hippo/scene/SceneFragment';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}\n    want true, got false`);
  }
}

// ============================================================================
// Test Doubles
// ============================================================================

class FakeSecuritySettings implements SecuritySettings {
  security: string | null;
  fingerprintEnabled: boolean;
  putSecurityLog: string[] = [];

  constructor(security: string | null, fingerprintEnabled: boolean) {
    this.security = security;
    this.fingerprintEnabled = fingerprintEnabled;
  }

  getSecurity(): string | null {
    return this.security;
  }

  putSecurity(value: string): void {
    this.putSecurityLog.push(value);
    this.security = value;
  }

  getEnableFingerprint(): boolean {
    return this.fingerprintEnabled;
  }
}

class FakeLockPatternPort implements LockPatternControllerPort {
  cells: Cell[] = [];
  mode: string = 'none';
  setCorrectCalls: number = 0;
  setWrongCalls: number = 0;

  setPatternCorrect(cells: Cell[]): void {
    this.cells = cells.slice();
    this.mode = 'correct';
    this.setCorrectCalls++;
  }

  setDisplayModeCorrect(): void {
    this.mode = 'correct';
    this.setCorrectCalls++;
  }

  setDisplayModeWrong(): void {
    this.mode = 'wrong';
    this.setWrongCalls++;
  }

  getCellSize(): number {
    return this.cells.length;
  }

  getPatternString(): string {
    return LockPatternUtils.patternToString(this.cells);
  }
}

class ScheduledTimerTask {
  readonly id: number;
  readonly delayMs: number;
  readonly callback: () => void;
  canceled: boolean = false;
  fired: boolean = false;

  constructor(id: number, delayMs: number, callback: () => void) {
    this.id = id;
    this.delayMs = delayMs;
    this.callback = callback;
  }
}

class FakeTimerPort implements SecurityTimerPort {
  private seq: number = 1;
  tasks: ScheduledTimerTask[] = [];

  schedule(delayMs: number, callback: () => void): number {
    const id: number = this.seq++;
    this.tasks.push(new ScheduledTimerTask(id, delayMs, callback));
    return id;
  }

  cancel(timerId: number): void {
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === timerId) {
        this.tasks[i].canceled = true;
      }
    }
  }

  lastActive(): ScheduledTimerTask | null {
    for (let i = this.tasks.length - 1; i >= 0; i--) {
      if (!this.tasks[i].canceled && !this.tasks[i].fired) {
        return this.tasks[i];
      }
    }
    return null;
  }

  fireLast(): boolean {
    const task: ScheduledTimerTask | null = this.lastActive();
    if (task === null) {
      return false;
    }
    task.fired = true;
    task.callback();
    return true;
  }
}

class FakeBiometricPort implements BiometricAuthPort {
  supported: boolean = true;
  enrolled: boolean = true;
  throwOnCheck: boolean = false;
  startCalls: number = 0;
  cancelCalls: number = 0;
  onSucceeded: (() => void) | null = null;
  onFailed: (() => void) | null = null;
  onError: ((reason: string) => void) | null = null;

  isSystemSupported(): boolean {
    if (this.throwOnCheck) {
      throw new Error('system check boom');
    }
    return this.supported;
  }

  hasEnrolledFingerprints(): boolean {
    if (this.throwOnCheck) {
      throw new Error('enroll check boom');
    }
    return this.enrolled;
  }

  startAuth(
    onSucceeded: () => void,
    onFailed: () => void,
    onError: (reason: string) => void
  ): boolean {
    this.startCalls++;
    this.onSucceeded = onSucceeded;
    this.onFailed = onFailed;
    this.onError = onError;
    return true;
  }

  cancelAuth(): void {
    this.cancelCalls++;
  }
}

class FakeShakeSensorPort implements ShakeSensorPort {
  startCalls: number = 0;
  stopCalls: number = 0;
  handler: ((x: number, y: number, z: number) => void) | null = null;

  start(onData: (x: number, y: number, z: number) => void): boolean {
    this.startCalls++;
    this.handler = onData;
    return true;
  }

  stop(): void {
    this.stopCalls++;
    this.handler = null;
  }

  emit(x: number, y: number, z: number): void {
    if (this.handler !== null) {
      this.handler(x, y, z);
    }
  }
}

class FakeRawWebCookieBackend implements RawWebCookieBackend {
  ops: string[] = [];
  cookiesByUrl: Map<string, string> = new Map<string, string>();
  throwOnClear: boolean = false;

  saveCookieSync(): void {
    this.ops.push('flush');
  }

  clearAllCookiesSync(): void {
    this.ops.push('clearAll');
    if (this.throwOnClear) {
      throw new Error('webview cookie store broken');
    }
    this.cookiesByUrl.clear();
  }

  clearSessionCookieSync(): void {
    this.ops.push('clearSession');
  }

  putAcceptCookieEnabled(accept: boolean): void {
    this.ops.push(`accept:${accept}`);
  }

  putAcceptThirdPartyCookieEnabled(accept: boolean): void {
    this.ops.push(`accept3p:${accept}`);
  }

  fetchCookieSync(url: string): string {
    const val: string | undefined = this.cookiesByUrl.get(url);
    return val === undefined ? '' : val;
  }

  configCookieSync(url: string, value: string): void {
    this.ops.push(`config:${url}:${value}`);
    const prev: string | undefined = this.cookiesByUrl.get(url);
    this.cookiesByUrl.set(url, prev !== undefined && prev.length > 0 ? prev + '; ' + value : value);
  }
}

class InMemoryCookieBackend implements CookieStoreBackend {
  private readonly rows: Map<string, Cookie> = new Map<string, Cookie>();

  getAllCookies(): Map<string, Cookie[]> {
    const out: Map<string, Cookie[]> = new Map<string, Cookie[]>();
    this.rows.forEach((c: Cookie): void => {
      let arr: Cookie[] | undefined = out.get(c.domain());
      if (arr === undefined) {
        arr = [];
        out.set(c.domain(), arr);
      }
      arr.push(c);
    });
    return out;
  }

  add(cookie: Cookie): void {
    if (cookie.persistent()) {
      this.rows.set(cookie.toKeyString(), cookie);
    }
  }

  update(oldCookie: Cookie, newCookie: Cookie): void {
    this.rows.delete(oldCookie.toKeyString());
    this.add(newCookie);
  }

  remove(cookie: Cookie): void {
    this.rows.delete(cookie.toKeyString());
  }

  clear(): void {
    this.rows.clear();
  }

  close(): void {
  }

  count(): number {
    return this.rows.size;
  }
}

class StartedSceneRecord {
  readonly sceneName: string;
  readonly args: SceneArgs | null;
  readonly requestFromTag: string | null;
  readonly requestCode: number;

  constructor(sceneName: string, args: SceneArgs | null, requestFromTag: string | null, requestCode: number) {
    this.sceneName = sceneName;
    this.args = args;
    this.requestFromTag = requestFromTag;
    this.requestCode = requestCode;
  }
}

class RecordingResultReceiver implements SceneResultReceiver {
  private readonly tag: string;
  receivedCode: number = -1;
  receivedResultCode: number = -1;
  receivedData: SceneArgs | null = null;
  calls: number = 0;

  constructor(tag: string = 'receiver') {
    this.tag = tag;
  }

  getTag(): string {
    return this.tag;
  }

  onSceneResult(requestCode: number, resultCode: number, data: SceneArgs | null): void {
    this.calls++;
    this.receivedCode = requestCode;
    this.receivedResultCode = resultCode;
    this.receivedData = data;
  }
}

class FakeStageHost implements StageHost {
  started: StartedSceneRecord[] = [];
  finishedTags: string[] = [];
  scenesByTag: Map<string, SceneFragment> = new Map<string, SceneFragment>();
  receiversByTag: Map<string, SceneResultReceiver> = new Map<string, SceneResultReceiver>();

  registerScene(tag: string, scene: SceneFragment): void {
    scene.setTag(tag);
    scene.bindHost(this);
    this.scenesByTag.set(tag, scene);
    this.receiversByTag.set(tag, scene);
  }

  registerReceiver(tag: string, receiver: SceneResultReceiver): void {
    this.receiversByTag.set(tag, receiver);
  }

  startSceneByName(sceneName: string, args: SceneArgs | null, requestFromTag: string | null,
    requestCode: number): void {
    this.started.push(new StartedSceneRecord(sceneName, args, requestFromTag, requestCode));
  }

  finishSceneByTag(tag: string, _transitionHelper: SceneTransitionHelper | null): void {
    this.finishedTags.push(tag);
    const s: SceneFragment | undefined = this.scenesByTag.get(tag);
    if (s !== undefined) {
      s.returnResult(this);
    }
  }

  getSceneIndexByTag(tag: string): number {
    return this.scenesByTag.has(tag) ? 0 : -1;
  }

  notifySceneViewCreated(_scene: SceneResultReceiver): void {
  }

  notifySceneViewDestroyed(_scene: SceneResultReceiver): void {
  }

  notifySceneDestroyed(_scene: SceneResultReceiver): void {
  }

  findSceneByTag(tag: string): SceneResultReceiver | null {
    const r: SceneResultReceiver | undefined = this.receiversByTag.get(tag);
    return r === undefined ? null : r;
  }
}

class FakeProfileHttpExecutor implements ProfileHttpExecutor {
  calls: string[] = [];
  nextResponse: HttpResponseLike | null = null;
  shouldThrow: boolean = false;

  execute(method: string, url: string, _headers: Map<string, string>,
    form: Map<string, string> | null): HttpResponseLike {
    this.calls.push(`${method} ${url} form=${form === null ? 0 : form.size}`);
    if (this.shouldThrow) {
      throw new Error('http exec failed');
    }
    return this.nextResponse as HttpResponseLike;
  }
}

class FakeProfileCookieJar implements ProfileCookieJar {
  writes: string[] = [];

  setCookie(url: string, cookie: string): void {
    this.writes.push(`${url}|${cookie}`);
  }

  getCookie(host: string): string {
    return `sid=ok_for_${host}`;
  }
}

class FakeGalleryTokenRequester implements GalleryTokenRequester {
  calls: string[] = [];
  returnValue: boolean = true;

  requestGalleryToken(gid: number, pToken: string, page: number): boolean {
    this.calls.push(`${gid}|${pToken}|${page}`);
    return this.returnValue;
  }
}

// ============================================================================
// 1. SecuritySceneShell + SecuritySceneCoordinator Tests
// ============================================================================

function testSecurityCoordinator(): void {
  const rightPattern: Cell[] = [Cell.of(0, 0), Cell.of(0, 1), Cell.of(0, 2), Cell.of(1, 2)];
  const wrongPattern: Cell[] = [Cell.of(2, 0), Cell.of(2, 1)];
  const targetCode: string = LockPatternUtils.patternToString(rightPattern);

  // 1a. classifyUserAuthResultCode mapping
  eq('SUCCESS maps to SUCCEEDED', classifyUserAuthResultCode(USER_AUTH_RESULT_SUCCESS), FingerprintEvent.SUCCEEDED);
  eq('FAIL maps to FAILED (recoverable)', classifyUserAuthResultCode(USER_AUTH_RESULT_FAIL), FingerprintEvent.FAILED);
  eq('CANCELED maps to FAILED', classifyUserAuthResultCode(USER_AUTH_RESULT_CANCELED), FingerprintEvent.FAILED);
  eq('TIMEOUT maps to FAILED', classifyUserAuthResultCode(USER_AUTH_RESULT_TIMEOUT), FingerprintEvent.FAILED);
  eq('LOCKED maps to ERROR (unrecoverable)', classifyUserAuthResultCode(USER_AUTH_RESULT_LOCKED), FingerprintEvent.ERROR);
  eq('NOT_ENROLLED maps to ERROR', classifyUserAuthResultCode(USER_AUTH_RESULT_NOT_ENROLLED), FingerprintEvent.ERROR);
  eq('TYPE_NOT_SUPPORT maps to ERROR', classifyUserAuthResultCode(USER_AUTH_RESULT_TYPE_NOT_SUPPORT), FingerprintEvent.ERROR);

  // 1b. Pattern wrong -> Wrong mode -> retries exhausted -> finishSecurity()
  const settings1: FakeSecuritySettings = new FakeSecuritySettings(targetCode, false);
  const shell1: SecuritySceneShell = new SecuritySceneShell(settings1, 2);
  const port1: FakeLockPatternPort = new FakeLockPatternPort();
  const bio1: FakeBiometricPort = new FakeBiometricPort();
  const shake1: FakeShakeSensorPort = new FakeShakeSensorPort();
  const timer1: FakeTimerPort = new FakeTimerPort();
  let lastState1: SecuritySceneViewState | null = null;
  const coord1: SecuritySceneCoordinator = new SecuritySceneCoordinator(
    shell1, port1, bio1, shake1, timer1,
    (st: SecuritySceneViewState): void => { lastState1 = st; }
  );
  coord1.start();
  eq('Fingerprint disabled in settings -> icon HIDDEN & auth not started',
    [lastState1 !== null ? (lastState1 as SecuritySceneViewState).fingerprintState : -1, bio1.startCalls],
    [FingerprintVisualState.HIDDEN, 0]);
  eq('Shake sensor started', shake1.startCalls, 1);

  eq('First wrong pattern -> WRONG', coord1.onPatternDetected(wrongPattern), PatternOutcome.WRONG);
  eq('Display mode switched to Wrong', port1.mode, 'wrong');
  eq('Remaining retries decremented to 1', shell1.getLogic().remainingRetries(), 1);
  ok('Not finished yet', !shell1.isFinished() && !shell1.isUnlocked());

  eq('Second wrong pattern -> EXHAUSTED', coord1.onPatternDetected(wrongPattern), PatternOutcome.EXHAUSTED);
  ok('Exhausted closes security scene without unlocking', shell1.isFinished() && !shell1.isUnlocked());
  coord1.stop();
  eq('Stop unsubscribes sensor & cancels bio', [shake1.stopCalls, bio1.cancelCalls], [1, 1]);

  // 1c. Pattern success -> grantAccess() + onUnlockedListener
  const settings2: FakeSecuritySettings = new FakeSecuritySettings(targetCode, true);
  const shell2: SecuritySceneShell = new SecuritySceneShell(settings2, MAX_RETRY_TIMES);
  let unlocked2: number = 0;
  shell2.setOnUnlockedListener((): void => { unlocked2++; });
  const port2: FakeLockPatternPort = new FakeLockPatternPort();
  const bio2: FakeBiometricPort = new FakeBiometricPort();
  const shake2: FakeShakeSensorPort = new FakeShakeSensorPort();
  const timer2: FakeTimerPort = new FakeTimerPort();
  let lastState2: SecuritySceneViewState | null = null;
  const coord2: SecuritySceneCoordinator = new SecuritySceneCoordinator(
    shell2, port2, bio2, shake2, timer2,
    (st: SecuritySceneViewState): void => { lastState2 = st; }
  );
  coord2.start();
  eq('Biometric available -> NORMAL icon & auth started',
    [lastState2 !== null ? (lastState2 as SecuritySceneViewState).fingerprintState : -1, bio2.startCalls],
    [FingerprintVisualState.NORMAL, 1]);

  // Biometric FAILED (recoverable) -> ERROR icon -> 1200ms -> NORMAL, retries UNTOUCHED
  ok('Biometric onFailed callback wired', bio2.onFailed !== null);
  if (bio2.onFailed !== null) {
    bio2.onFailed();
  }
  eq('Biometric fail shows ERROR icon',
    lastState2 !== null ? (lastState2 as SecuritySceneViewState).fingerprintState : -1,
    FingerprintVisualState.ERROR);
  eq('Biometric fail NEVER decrements pattern retry count', shell2.getLogic().remainingRetries(), MAX_RETRY_TIMES);
  const failTask: ScheduledTimerTask | null = timer2.lastActive();
  eq('Biometric fail schedules ERROR_TIMEOUT_MILLIS (1200ms)', failTask !== null ? failTask.delayMs : -1, ERROR_TIMEOUT_MILLIS);
  timer2.fireLast();
  eq('After 1200ms recoverable failure resets icon to NORMAL',
    lastState2 !== null ? (lastState2 as SecuritySceneViewState).fingerprintState : -1,
    FingerprintVisualState.NORMAL);

  // Biometric ERROR (unrecoverable) -> ERROR icon -> 1200ms -> HIDDEN, retries UNTOUCHED
  if (bio2.onError !== null) {
    bio2.onError('locked');
  }
  eq('Biometric error shows ERROR icon',
    lastState2 !== null ? (lastState2 as SecuritySceneViewState).fingerprintState : -1,
    FingerprintVisualState.ERROR);
  eq('Biometric error NEVER decrements pattern retry count', shell2.getLogic().remainingRetries(), MAX_RETRY_TIMES);
  timer2.fireLast();
  eq('After 1200ms unrecoverable error hides icon',
    lastState2 !== null ? (lastState2 as SecuritySceneViewState).fingerprintState : -1,
    FingerprintVisualState.HIDDEN);

  // Pattern still succeeds after biometric error
  eq('Correct pattern -> SUCCESS', coord2.onPatternDetected(rightPattern), PatternOutcome.SUCCESS);
  eq('Correct pattern sets DisplayMode.Correct', port2.mode, 'correct');
  ok('Correct pattern grants access', shell2.isUnlocked() && unlocked2 === 1);
  coord2.stop();

  // 1d. Biometric SUCCEEDED -> SUCCESS icon -> 100ms delay -> grantAccess()
  const settings3: FakeSecuritySettings = new FakeSecuritySettings(targetCode, true);
  const shell3: SecuritySceneShell = new SecuritySceneShell(settings3, MAX_RETRY_TIMES);
  let unlocked3: number = 0;
  shell3.setOnUnlockedListener((): void => { unlocked3++; });
  const port3: FakeLockPatternPort = new FakeLockPatternPort();
  const bio3: FakeBiometricPort = new FakeBiometricPort();
  const shake3: FakeShakeSensorPort = new FakeShakeSensorPort();
  const timer3: FakeTimerPort = new FakeTimerPort();
  let lastState3: SecuritySceneViewState | null = null;
  const coord3: SecuritySceneCoordinator = new SecuritySceneCoordinator(
    shell3, port3, bio3, shake3, timer3,
    (st: SecuritySceneViewState): void => { lastState3 = st; }
  );
  coord3.start();
  if (bio3.onSucceeded !== null) {
    bio3.onSucceeded();
  }
  eq('Biometric success shows SUCCESS icon immediately',
    lastState3 !== null ? (lastState3 as SecuritySceneViewState).fingerprintState : -1,
    FingerprintVisualState.SUCCESS);
  ok('Biometric success waits 100ms before granting access', !shell3.isUnlocked());
  const okTask: ScheduledTimerTask | null = timer3.lastActive();
  eq('Biometric success schedules SUCCESS_DELAY_MILLIS (100ms)', okTask !== null ? okTask.delayMs : -1, SUCCESS_DELAY_MILLIS);
  timer3.fireLast();
  ok('After 100ms biometric grants access', shell3.isUnlocked() && unlocked3 === 1);
  coord3.stop();

  // 1e. Shake-to-unlock via accelerometer (threshold == 10 clears security and grants access)
  const settings4: FakeSecuritySettings = new FakeSecuritySettings(targetCode, false);
  const shell4: SecuritySceneShell = new SecuritySceneShell(settings4, MAX_RETRY_TIMES);
  let nowMs: number = 10000;
  const port4: FakeLockPatternPort = new FakeLockPatternPort();
  const bio4: FakeBiometricPort = new FakeBiometricPort();
  const shake4: FakeShakeSensorPort = new FakeShakeSensorPort();
  const timer4: FakeTimerPort = new FakeTimerPort();
  const coord4: SecuritySceneCoordinator = new SecuritySceneCoordinator(
    shell4, port4, bio4, shake4, timer4,
    (_st: SecuritySceneViewState): void => {},
    (): number => nowMs
  );
  coord4.start();
  // 9 strong shakes (> 2.7G, spaced by 600ms > 500ms slop and < 3000ms reset)
  for (let i = 0; i < 9; i++) {
    nowMs += 600;
    shake4.emit(30.0, 0.0, 0.0);
  }
  ok('9 shakes do NOT unlock or clear security', !shell4.isUnlocked() && settings4.security === targetCode);
  // 10th shake triggers unlock & clears security
  nowMs += 600;
  shake4.emit(30.0, 0.0, 0.0);
  ok('10th shake clears security and grants access',
    shell4.isUnlocked() && shell4.getLogic().isSecurityCleared() && settings4.security === '');
  eq('putSecurity("") called once on 10th shake', settings4.putSecurityLog, ['']);
  coord4.stop();

  // 1f. Biometric probe throw is caught safely (-> HIDDEN, no crash)
  const settings5: FakeSecuritySettings = new FakeSecuritySettings(targetCode, true);
  const shell5: SecuritySceneShell = new SecuritySceneShell(settings5, MAX_RETRY_TIMES);
  const bio5: FakeBiometricPort = new FakeBiometricPort();
  bio5.throwOnCheck = true;
  let lastState5: SecuritySceneViewState | null = null;
  const coord5: SecuritySceneCoordinator = new SecuritySceneCoordinator(
    shell5, new FakeLockPatternPort(), bio5, new FakeShakeSensorPort(), new FakeTimerPort(),
    (st: SecuritySceneViewState): void => { lastState5 = st; }
  );
  coord5.start();
  eq('Throwing biometric probe safely hides icon',
    lastState5 !== null ? (lastState5 as SecuritySceneViewState).fingerprintState : -1,
    FingerprintVisualState.HIDDEN);
  coord5.stop();
}

// ============================================================================
// 2. SetSecurityPage Host / Port / Settings Adapter Tests
// ============================================================================

function testSetSecurityAdapters(): void {
  const existingPattern: Cell[] = [Cell.of(0, 0), Cell.of(1, 1), Cell.of(2, 2)];
  const existingCode: string = LockPatternUtils.patternToString(existingPattern);

  // 2a. Echo existing pattern in DisplayMode.Correct (DISPLAY_MODE_CORRECT=2 -> setPatternCorrect, NOT Wrong!)
  Settings.putSecurity(existingCode);
  Settings.putEnableFingerprint(true);
  const settingsBacked: SettingsBackedSecuritySettings = new SettingsBackedSecuritySettings();

  const rawPort1: FakeLockPatternPort = new FakeLockPatternPort();
  const pvAdapter1: LockPatternViewPortAdapter = new LockPatternViewPortAdapter(rawPort1);
  let uiVisible1: boolean = false;
  let uiChecked1: boolean = false;
  let finishCount1: number = 0;
  const host1: SetSecurityPageHostAdapter = new SetSecurityPageHostAdapter(
    pvAdapter1,
    (): boolean => true,
    (vis: boolean, chk: boolean): void => {
      uiVisible1 = vis;
      uiChecked1 = chk;
    },
    (): void => { finishCount1++; }
  );
  const act1: SetSecurityActivity = new SetSecurityActivity(host1, settingsBacked);
  eq('onCreate echoes existing pattern', act1.onCreate(), true);
  eq('Navigation icon set to v_arrow_left_dark_x24', host1.getNavigationIcon(), DRAWABLE_BACK);
  eq('DISPLAY_MODE_CORRECT maps to setPatternCorrect (green, NOT Wrong)',
    [DISPLAY_MODE_CORRECT, rawPort1.mode, rawPort1.setWrongCalls, rawPort1.getCellSize()],
    [2, 'correct', 0, 3]);
  eq('Enrolled biometric shows and checks checkbox from Settings', [uiVisible1, uiChecked1], [true, true]);

  // 2b. Save valid pattern with visible && checked && non-empty -> enables fingerprint
  const newPattern: Cell[] = [Cell.of(0, 0), Cell.of(0, 1), Cell.of(1, 1), Cell.of(2, 1)];
  const newCode: string = LockPatternUtils.patternToString(newPattern);
  rawPort1.cells = newPattern;
  const saved1: string | null = act1.onSet();
  eq('onSet writes new pattern to Settings', [saved1, Settings.getSecurity()], [newCode, newCode]);
  eq('3-way AND true -> Settings.getEnableFingerprint()=true', Settings.getEnableFingerprint(), true);
  eq('onSet calls finish', finishCount1, 1);

  // 2c. getCellSize() <= 1 clears security and forces fingerprint=false (3-way AND)
  rawPort1.cells = [Cell.of(0, 0)];
  const savedClear: string | null = act1.onSet();
  eq('cellSize=1 clears security to empty string', [savedClear, Settings.getSecurity()], ['', '']);
  eq('Empty security forces enableFingerprint=false even when visible & checked',
    Settings.getEnableFingerprint(), false);
  eq('onSet calls finish again', finishCount1, 2);

  // 2d. Checkbox unchecked -> 3-way AND false even with valid security
  rawPort1.cells = newPattern;
  host1.setFingerprintChecked(false);
  act1.onSet();
  eq('Unchecked checkbox -> enableFingerprint=false', Settings.getEnableFingerprint(), false);
  eq('Security still saved', Settings.getSecurity(), newCode);

  // 2e. Biometric enrollment probe throws -> caught -> returns false, hides checkbox
  const rawPort2: FakeLockPatternPort = new FakeLockPatternPort();
  const host2: SetSecurityPageHostAdapter = new SetSecurityPageHostAdapter(
    new LockPatternViewPortAdapter(rawPort2),
    (): boolean => { throw new Error('userAuth unavailable'); },
    (_vis: boolean, _chk: boolean): void => {},
    (): void => {}
  );
  const act2: SetSecurityActivity = new SetSecurityActivity(host2, settingsBacked);
  eq('Throwing biometric probe -> hasEnrolledFingerprints=false', host2.hasEnrolledFingerprints(), false);
  act2.onCreate();
  eq('Throwing probe hides fingerprint checkbox', host2.isFingerprintVisible(), false);
  host2.setFingerprintChecked(true);
  rawPort2.cells = newPattern;
  act2.onSet();
  eq('Hidden checkbox -> 3-way AND disables fingerprint', Settings.getEnableFingerprint(), false);

  // 2f. onDestroy + detachPatternView -> onSet does not write settings but still finishes
  let finishCount3: number = 0;
  const host3: SetSecurityPageHostAdapter = new SetSecurityPageHostAdapter(
    new LockPatternViewPortAdapter(new FakeLockPatternPort()),
    (): boolean => false,
    (_vis: boolean, _chk: boolean): void => {},
    (): void => { finishCount3++; }
  );
  const act3: SetSecurityActivity = new SetSecurityActivity(host3, settingsBacked);
  act3.onCreate();
  act3.onCancel();
  eq('onCancel finishes', finishCount3, 1);
  eq('home option returns true and finishes',
    [act3.onOptionsItemSelected('android.R.id.home'), finishCount3], [true, 2]);
  act3.onDestroy();
  host3.detachPatternView();
  eq('After detach, onSet returns null and still finishes', [act3.onSet(), finishCount3], [null, 3]);

  // Clean up Settings state for subsequent tests
  Settings.putSecurity('');
  Settings.putEnableFingerprint(false);
}

// ============================================================================
// 3. WebViewSignInSceneConcrete + Cookie Adapter & Coordinator Tests
// ============================================================================

function testWebViewSignInFlow(): void {
  // 3a. Normal prepareCookies order + onPageEnd auto-detect + EhCookieStore persistence
  const rawBackend: FakeRawWebCookieBackend = new FakeRawWebCookieBackend();
  const cookieAdapter: ArkWebCookieManagerAdapter = new ArkWebCookieManagerAdapter(rawBackend);
  const memBackend: InMemoryCookieBackend = new InMemoryCookieBackend();
  const ehStore: EhCookieStore = new EhCookieStore(memBackend);
  const profileJar: EhCookieStoreProfileJar = new EhCookieStoreProfileJar(ehStore);

  const stage: FakeStageHost = new FakeStageHost();
  const receiver: RecordingResultReceiver = new RecordingResultReceiver();
  stage.registerReceiver('signin-1', receiver);

  const scene: WebViewSignInSceneConcrete = new WebViewSignInSceneConcrete();
  stage.registerScene('webview-1', scene);
  scene.addRequest('signin-1', 0);

  const coord: WebViewSignInCoordinator = new WebViewSignInCoordinator(
    scene, cookieAdapter, profileJar, EhUrl.URL_SIGN_IN
  );
  eq('Coordinator init prepares cookies', coord.init(), true);
  eq('Exact 5-step prepareCookies order on backend', rawBackend.ops, [
    'flush', 'clearAll', 'clearSession', 'accept:true', 'accept3p:true'
  ]);
  ok('Not initFailed', !scene.isInitFailed());

  // Partial cookies on intermediate page -> does NOT finish yet
  rawBackend.cookiesByUrl.set(EhUrl.URL_SIGN_IN, 'ipb_member_id=12345');
  eq('Only member_id -> hasEhLoginCookies=false', hasEhLoginCookies('ipb_member_id=12345'), false);
  eq('onPageEnd does not finish before pass_hash arrives', coord.onPageEnd(EhUrl.URL_SIGN_IN), false);
  eq('Scene not finished yet', stage.finishedTags.length, 0);

  // Full login cookies split across HOST_E and URL_SIGN_IN -> merged & harvested!
  rawBackend.cookiesByUrl.set(EhUrl.HOST_E, 'ipb_pass_hash=abcdef0123456789; igneous=998877');
  eq('Adapter merges cookies from URL + HOST_E',
    hasEhLoginCookies(cookieAdapter.getCookie(EhUrl.URL_SIGN_IN)), true);

  eq('onPageEnd detects login completion and finishes OK', coord.onPageEnd(EhUrl.URL_SIGN_IN), true);
  eq('Scene finished with OK', [scene.resultCode, stage.finishedTags], [SceneResultCode.OK, ['webview-1']]);
  eq('Result delivered to SignInScene receiver', [receiver.calls, receiver.receivedResultCode], [1, SceneResultCode.OK]);
  ok('EhCookieStore now reports hasSignedIn()=true', ehStore.hasSignedIn());

  const urlE: HttpUrl = HttpUrl.parse(EhUrl.HOST_E) as HttpUrl;
  const urlEx: HttpUrl = HttpUrl.parse(EhUrl.HOST_EX) as HttpUrl;
  ok('Cookies mirrored to e-hentai.org',
    ehStore.contains(urlE, EhCookieStore.KEY_IPD_MEMBER_ID)
    && ehStore.contains(urlE, EhCookieStore.KEY_IPD_PASS_HASH)
    && ehStore.contains(urlE, EhCookieStore.KEY_IGNEOUS));
  ok('Cookies mirrored to exhentai.org',
    ehStore.contains(urlEx, EhCookieStore.KEY_IPD_MEMBER_ID)
    && ehStore.contains(urlEx, EhCookieStore.KEY_IPD_PASS_HASH)
    && ehStore.contains(urlEx, EhCookieStore.KEY_IGNEOUS));
  ok('Persisted to CookieStoreBackend (RdbCookieStore equivalent)', memBackend.count() >= 6);

  // 3b. Init failure path -> dialog dismissed -> CANCELED + finish
  const brokenBackend: FakeRawWebCookieBackend = new FakeRawWebCookieBackend();
  brokenBackend.throwOnClear = true;
  const brokenScene: WebViewSignInSceneConcrete = new WebViewSignInSceneConcrete();
  stage.registerScene('webview-2', brokenScene);
  const brokenCoord: WebViewSignInCoordinator = new WebViewSignInCoordinator(
    brokenScene, new ArkWebCookieManagerAdapter(brokenBackend), profileJar
  );
  eq('Broken cookie backend -> init returns false', brokenCoord.init(), false);
  ok('Scene marks initFailed=true', brokenScene.isInitFailed());
  brokenCoord.dismissInitFailedDialog();
  eq('Dismissing init-failed dialog finishes with CANCELED',
    [brokenScene.resultCode, brokenScene.result, stage.finishedTags.includes('webview-2')],
    [SceneResultCode.CANCELED, null, true]);
}

// ============================================================================
// 4. GetProfileSceneShell Tests
// ============================================================================

function testGetProfileSceneShell(): void {
  const executor: FakeProfileHttpExecutor = new FakeProfileHttpExecutor();
  const jar: FakeProfileCookieJar = new FakeProfileCookieJar();
  const stage: FakeStageHost = new FakeStageHost();
  const receiver: RecordingResultReceiver = new RecordingResultReceiver();
  stage.registerReceiver('signin-caller', receiver);

  const shell: GetProfileSceneShell = new GetProfileSceneShell(executor, jar);
  stage.registerScene('profile-1', shell);
  shell.addRequest('signin-caller', REQUEST_CODE_PROFILE);

  let listenerName: string = '';
  shell.setOnProfileLoadedListener((p: ProfileResult): void => {
    listenerName = p.displayName;
  });

  eq('Scene name is GetProfileScene', shell.getSceneName(), 'GetProfileScene');
  eq('Left drawer disabled', shell.needShowLeftDrawer(), false);
  eq('Start URL is forums', shell.getStartUrl(), GetProfileScene.START_URL);
  eq('Read JS matches GetProfileScene.READ_CONTENT_JS', shell.getReadContentJs(), GetProfileScene.READ_CONTENT_JS);

  // planPageFinished
  eq('Valid http URL -> READ_CONTENT',
    shell.planPageFinished('https://forums.e-hentai.org/index.php'), PageFinishedAction.READ_CONTENT);
  eq('Non-http URL -> NONE', shell.planPageFinished('about:blank'), PageFinishedAction.NONE);

  // normalizeJavaScriptStringResult
  eq('Unquotes JSON-encoded HTML from runJavaScript',
    GetProfileSceneShell.normalizeJavaScriptStringResult('"<html><div id=\\"userlinks\\"></div></html>"'),
    '<html><div id="userlinks"></div></html>');
  eq('Passes raw HTML unchanged',
    GetProfileSceneShell.normalizeJavaScriptStringResult('<html><body>hi</body></html>'),
    '<html><body>hi</body></html>');
  eq('Maps JS literal "null" to null', GetProfileSceneShell.normalizeJavaScriptStringResult('null'), null);

  // interceptRequest with executor
  const headers: Map<string, string> = new Map<string, string>();
  headers.set('Set-Cookie', 'u=1; Path=/');
  executor.nextResponse = new HttpResponseLike(200, 'OK', headers, 'text/html; charset=utf-8', new ArrayBuffer(8));
  const plan: WebResponsePlan | null = shell.interceptRequest(
    new WebRequestLike('https://forums.e-hentai.org/', new Map<string, string>(), WebRequestType.HTML, new Map<string, string>())
  );
  ok('Http request intercepted via executor', plan !== null && plan.statusCode === 200);
  eq('Set-Cookie synced to ProfileCookieJar', jar.writes.length, 1);

  // Invalid HTML does NOT finish
  const badParsed: ProfileResult | null = shell.handlePageContent('"<html><body>no userlinks</body></html>"');
  eq('Invalid HTML returns null', badParsed, null);
  ok('Invalid HTML keeps scene alive (not completed/finished)', !shell.isCompleted() && stage.finishedTags.length === 0);

  // Valid JSON-quoted HTML with #userlinks -> parses displayName, delivers result, finishes
  const rawJsHtml: string = JSON.stringify(
    '<html><body><div id="userlinks"><div><div><b>HarmonyTester</b></div></div></div></body></html>'
  );
  const parsed: ProfileResult | null = shell.handlePageContent(rawJsHtml);
  ok('Valid HTML parsed into ProfileResult', parsed !== null);
  eq('displayName extracted', parsed !== null ? parsed.displayName : '', 'HarmonyTester');
  eq('onProfileLoadedListener notified', listenerName, 'HarmonyTester');
  ok('Shell marked completed', shell.isCompleted());
  eq('Result delivered to caller with REQUEST_CODE_PROFILE & OK',
    [receiver.calls, receiver.receivedCode, receiver.receivedResultCode],
    [1, REQUEST_CODE_PROFILE, SceneResultCode.OK]);
  eq('Result bundle carries DISPLAY_NAME',
    receiver.receivedData !== null ? receiver.receivedData.get(DISPLAY_NAME) : null,
    'HarmonyTester');
  eq('Avatar omitted when null',
    receiver.receivedData !== null ? receiver.receivedData.has(AVATAR) : true,
    false);

  // Destroyed view -> planPageFinished returns NONE
  shell.onSceneViewDestroyed();
  eq('Destroyed view -> planPageFinished returns NONE',
    shell.planPageFinished('https://forums.e-hentai.org/'), PageFinishedAction.NONE);

  // Null executor falls back cleanly (returns null) & initFailed dialog dismiss finishes CANCELED
  const fallbackShell: GetProfileSceneShell = new GetProfileSceneShell(null, null);
  stage.registerScene('profile-2', fallbackShell);
  eq('Missing executor passes request through as null',
    fallbackShell.interceptRequest(
      new WebRequestLike('https://forums.e-hentai.org/', new Map<string, string>(), WebRequestType.HTML, new Map<string, string>())
    ),
    null);
  fallbackShell.onInitFailed('webview unavailable');
  ok('Init failed flag set', fallbackShell.isInitFailed() && fallbackShell.getLastError() === 'webview unavailable');
  fallbackShell.onInitFailedDialogDismissed();
  eq('Init failed dismissal finishes CANCELED',
    [fallbackShell.resultCode, stage.finishedTags.includes('profile-2')],
    [SceneResultCode.CANCELED, true]);
}

// ============================================================================
// 5. ProgressSceneShell + AsyncGalleryTokenRequester Tests
// ============================================================================

async function testProgressSceneShell(): Promise<void> {
  // 5a. extractProgressArgs
  eq('Null args -> null', ProgressSceneShell.extractProgressArgs(null), null);
  const goodArgs: SceneArgs = new Map<string, Object>();
  goodArgs.set(KEY_ACTION, ACTION_GALLERY_TOKEN);
  goodArgs.set(KEY_GID, 1001);
  goodArgs.set(KEY_PTOKEN, 'ptok_abc');
  goodArgs.set(KEY_PAGE, 0);
  const extracted: ProgressArgs | null = ProgressSceneShell.extractProgressArgs(goodArgs);
  ok('Valid args extracted (including page=0)',
    extracted !== null && extracted.action === ACTION_GALLERY_TOKEN
    && extracted.gid === 1001 && extracted.pToken === 'ptok_abc' && extracted.page === 0);

  // 5b. Invalid args -> TIP with ERROR_SOMETHING_WRONG, no request sent
  const req1: FakeGalleryTokenRequester = new FakeGalleryTokenRequester();
  const badShell: ProgressSceneShell = new ProgressSceneShell(req1);
  const badArgs: SceneArgs = new Map<string, Object>();
  badArgs.set(KEY_ACTION, ACTION_GALLERY_TOKEN);
  badArgs.set(KEY_GID, DEFAULT_GID);
  badArgs.set(KEY_PAGE, DEFAULT_PAGE);
  badShell.setArguments(badArgs);
  const badState: ProgressState = badShell.initFromArguments(true);
  eq('Invalid args -> TIP view', badShell.getCurrentView(), ProgressView.TIP);
  eq('Invalid args -> fixed error key', badState.error, ProgressScene.ERROR_SOMETHING_WRONG);
  eq('Invalid args -> requester not called', req1.calls.length, 0);

  // 5c. Valid args -> init -> failure -> retry -> success -> startScene(GalleryDetailScene) + finish
  const stage: FakeStageHost = new FakeStageHost();
  const req2: FakeGalleryTokenRequester = new FakeGalleryTokenRequester();
  const shell: ProgressSceneShell = new ProgressSceneShell(req2);
  stage.registerScene('progress-1', shell);
  shell.setArguments(goodArgs);

  let stateChanges: number = 0;
  shell.setStateChangeListener((_st: ProgressState): void => {
    stateChanges++;
  });

  eq('Scene name is ProgressScene', shell.getSceneName(), 'ProgressScene');
  eq('Left drawer disabled', shell.needShowLeftDrawer(), false);

  const initState: ProgressState = shell.ensureInitialized(true);
  eq('Valid init -> PROGRESS view', [initState.valid, shell.getCurrentView()], [true, ProgressView.PROGRESS]);
  eq('Requester invoked once with gid|ptoken|page', req2.calls, ['1001|ptok_abc|0']);
  // Calling ensureInitialized again does NOT re-fire request
  shell.ensureInitialized(true);
  eq('ensureInitialized is idempotent', req2.calls.length, 1);

  // Failure while view alive -> transitions to TIP & notifies UI
  const beforeFailChanges: number = stateChanges;
  eq('Failure while view alive returns true', shell.onGetGalleryTokenFailure('Network timeout', true), true);
  eq('View switches to TIP with readable error',
    [shell.getCurrentView(), shell.getErrorText()],
    [ProgressView.TIP, 'Network timeout']);
  ok('State change listener notified on failure', stateChanges > beforeFailChanges);

  // Retry -> relaunches request & switches back to PROGRESS
  eq('Retry returns true', shell.retry(true), true);
  eq('After retry view returns to PROGRESS', shell.getCurrentView(), ProgressView.PROGRESS);
  eq('Requester called a second time', req2.calls.length, 2);

  // Success -> launches GalleryDetailScene with DETAIL_ACTION_GID_TOKEN & finishes
  const detailArgs: Map<string, Object> = shell.onGetGalleryTokenSuccess('resolved_gtoken');
  eq('detailArgs action/gid/token/page',
    [
      detailArgs.get(DETAIL_KEY_ACTION),
      detailArgs.get(DETAIL_KEY_GID),
      detailArgs.get(DETAIL_KEY_TOKEN),
      detailArgs.get(DETAIL_KEY_PAGE)
    ],
    [DETAIL_ACTION_GID_TOKEN, 1001, 'resolved_gtoken', 0]);
  eq('Started GalleryDetailScene', stage.started.length, 1);
  eq('Started scene name is GalleryDetailScene', stage.started[0].sceneName, 'GalleryDetailScene');
  eq('ProgressScene finished after navigation', stage.finishedTags, ['progress-1']);

  // Failure after view destroyed -> updates state only, does NOT notify UI
  const deadShell: ProgressSceneShell = new ProgressSceneShell(req2);
  deadShell.setArguments(goodArgs);
  deadShell.initFromArguments(true);
  let deadListenerCalls: number = 0;
  deadShell.setStateChangeListener((_s: ProgressState): void => { deadListenerCalls++; });
  deadShell.onSceneViewDestroyed();
  eq('Failure when viewDestroyed returns false', deadShell.onGetGalleryTokenFailure('late error', true), false);
  eq('State updated without notifying UI', [deadShell.getCurrentView(), deadListenerCalls], [ProgressView.TIP, 0]);

  // Restore does NOT launch request
  const req3: FakeGalleryTokenRequester = new FakeGalleryTokenRequester();
  const restoredShell: ProgressSceneShell = new ProgressSceneShell(req3);
  restoredShell.restoreFromSaved(true, null, new ProgressArgs(ACTION_GALLERY_TOKEN, 88, 'pt', 2));
  eq('Restore keeps PROGRESS view without issuing request',
    [restoredShell.getCurrentView(), req3.calls.length], [ProgressView.PROGRESS, 0]);

  // 5d. AsyncGalleryTokenRequester bridges Promise<string> -> callbacks
  let resolvedToken: string = '';
  let failedErr: string = '';
  const asyncOk: AsyncGalleryTokenRequester = new AsyncGalleryTokenRequester(
    async (gid: number, pToken: string, page: number): Promise<string> => {
      return `tok_${gid}_${pToken}_${page}`;
    },
    (tok: string): void => { resolvedToken = tok; },
    (err: string): void => { failedErr = err; }
  );
  eq('Async requester returns true synchronously', asyncOk.requestGalleryToken(55, 'abc', 4), true);
  await Promise.resolve();
  await Promise.resolve();
  eq('Async requester delivers resolved token', [resolvedToken, failedErr], ['tok_55_abc_4', '']);

  let failOut: string = '';
  const asyncFail: AsyncGalleryTokenRequester = new AsyncGalleryTokenRequester(
    async (_gid: number, _pToken: string, _page: number): Promise<string> => {
      throw new Error('503 service down');
    },
    (_tok: string): void => {},
    (err: string): void => { failOut = err; }
  );
  eq('Async failing requester returns true synchronously', asyncFail.requestGalleryToken(55, 'abc', 4), true);
  await Promise.resolve();
  await Promise.resolve();
  eq('Async failing requester delivers error message', failOut, '503 service down');
}

// ============================================================================
// Entry
// ============================================================================

async function main(): Promise<void> {
  testSecurityCoordinator();
  testSetSecurityAdapters();
  testWebViewSignInFlow();
  await testProgressSceneShell();
  testGetProfileSceneShell();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} failed / ${pass + fails.length} assertions`);
    for (let i = 0; i < fails.length; i++) {
      console.error('  - ' + fails[i]);
    }
    throw new Error('p1-auth-security test failed');
  }
  console.log(`✓ p1-auth-security: ${pass} assertions passed`);
}

main().catch((e: Error): void => {
  console.error(e.message !== undefined ? e.message : String(e));
  throw e;
});
