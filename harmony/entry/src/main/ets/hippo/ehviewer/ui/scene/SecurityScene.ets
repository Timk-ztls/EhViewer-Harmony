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

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/SecurityScene.java（233 行）。
 *
 * ============================================================================
 * 一、上游是什么（手势锁解锁页）
 * ============================================================================
 * 三条解锁途径，谁先成功谁放行：
 *
 *   ```java
 *   手势：onPatternDetected  → LockPatternUtils.patternToString(pattern) == Settings.getSecurity()
 *                              成功 → startSceneForCheckStep(CHECK_STEP_SECURITY) + finish()
 *                              失败 → setDisplayMode(Wrong) + mRetryTimes-- ；**耗尽 → 直接 finish()**
 *   指纹：isFingerprintAuthAvailable() → authenticate(...)
 *                              onAuthenticationSucceeded → 图标换成功态，延迟 SUCCESS_DELAY_MILLIS(100) 后放行
 *                              onAuthenticationError(可恢复/不可恢复) → fingerprintError(unrecoverable)
 *                              onAuthenticationFailed → fingerprintError(false)（**不扣重试次数**）
 *   摇一摇：onShake(count) 且 **count == 10** → Settings.putSecurity("") 清空安全码 + 放行
 *   ```
 *
 * 逐行对照时最容易丢/写反的**七条**（本文件逐条保留并断言）：
 *   1. 重试次数初值 **5**（`MAX_RETRY_TIMES`），且失败一次扣一次；**扣到 0 就 finish（锁屏页消失）** ——
 *      不是"禁用输入"，是直接退出；
 *   2. **指纹失败不扣重试次数**（上游注释写明"由 Android 系统自己处理重试"）——
 *      移植时"顺手"补一个 `mRetryTimes--` 会让手势 + 指纹混算，用户被莫名踢出；
 *   3. 指纹成功要**延迟 100ms** 再放行（让成功图标有个可见的过渡）；指纹错误要延迟 **1200ms**：
 *      **可恢复错误**（`Failed`）→ 图标复位；**不可恢复错误**（`Error`）→ 图标隐藏；
 *   4. 不可恢复错误**不取消 `CancellationSignal`**、也不改 `mRetryTimes` —— 只是隐藏图标；
 *   5. 摇一摇的阈值是 **count == 10**（不是 >= 10、不是 5）；
 *   6. 摇一摇成功会**把安全码清空**（`putSecurity("")`，即"解除锁屏"），然后放行；
 *   7. 指纹入口可见需要**三个条件同时成立**：系统支持（API 23+）、`Settings.getEnableFingerprint()`、
 *      **已录入指纹**（`hasEnrolledFingerprints`）。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * 上游 233 行里约 120 行是 Android 传感器/指纹/锁屏控件胶水。移植分三层：
 *   - **判据/状态机**（本文件）：重试计数、解锁判定、指纹可用性三条件、错误分级与延迟、
 *     摇一摇阈值、放行/退出决策；
 *   - **平台能力** → 注入 `SecurityPlatform`（指纹：鸿蒙 `@ohos.userIAM.userAuth`；
 *     摇一摇：`@ohos.sensor` 加速度计；手势绘制：LockPatternView 等价物）；
 *   - **Settings** → 注入 `SecuritySettings`（`getSecurity` / `putSecurity` / `getEnableFingerprint`
 *     在 SetSecurityActivity 那侧，尚未全部导出）。
 *
 * 手势串比较用 `patternToString`（已 land：`hippo/widget/lockpattern/LockPatternUtils.ets`）。
 */

import { LockPatternUtils } from '../../../widget/lockpattern/LockPatternUtils';
import { Cell } from '../../../widget/lockpattern/LockPatternCell';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'SecurityScene';

/** 最大重试次数（上游 `MAX_RETRY_TIMES`）。 */
export const MAX_RETRY_TIMES: number = 5;
/** 指纹错误提示的显示时长（上游 `ERROR_TIMEOUT_MILLIS`）。 */
export const ERROR_TIMEOUT_MILLIS: number = 1200;
/** 指纹成功后延迟多久放行（上游 `SUCCESS_DELAY_MILLIS`）。 */
export const SUCCESS_DELAY_MILLIS: number = 100;
/** 摇一摇触发阈值（上游 `count == 10`）。 */
export const SHAKE_THRESHOLD: number = 10;
/** 重试次数的持久化键（上游 `KEY_RETRY_TIMES`）。 */
export const KEY_RETRY_TIMES: string = 'retry_times';
/** 手势失败时锁屏控件的显示模式（上游 `LockPatternView.DisplayMode.Wrong`）。 */
export enum PatternDisplayMode {
  CORRECT = 0,
  ANIMATING = 1,
  WRONG = 2
}

/** 一次手势判定的结果。 */
export enum PatternOutcome {
  /** 与设置里的安全码一致 → 放行 */
  SUCCESS = 0,
  /** 不一致 → 显示 Wrong，重试次数 -1 */
  WRONG = 1,
  /** 不一致且重试次数耗尽 → **直接 finish**（不是禁用） */
  EXHAUSTED = 2
}

/** 指纹认证回调的分级（上游三个回调）。 */
export enum FingerprintEvent {
  /** `onAuthenticationSucceeded` → 成功图标 + 延迟放行 */
  SUCCEEDED = 0,
  /** `onAuthenticationFailed` → 可恢复错误（图标复位，**不扣次数**） */
  FAILED = 1,
  /** `onAuthenticationError` → 不可恢复（延迟后**隐藏图标**，也不扣次数） */
  ERROR = 2
}

/** 指纹错误后的 UI 动作。 */
export enum FingerprintErrorAction {
  /** 复位成正常图标（可恢复） */
  RESET_ICON = 0,
  /** 延迟后隐藏图标（不可恢复） */
  HIDE_ICON = 1
}

/** 指纹入口可见的三条件（上游 `isFingerprintAuthAvailable`）。 */
export class FingerprintAvailability {
  systemSupported: boolean;
  settingEnabled: boolean;
  enrolled: boolean;

  constructor(systemSupported: boolean, settingEnabled: boolean, enrolled: boolean) {
    this.systemSupported = systemSupported;
    this.settingEnabled = settingEnabled;
    this.enrolled = enrolled;
  }

  available(): boolean {
    return this.systemSupported && this.settingEnabled && this.enrolled;
  }
}

/** 解锁页需要的设置读写（生产实现包 Settings / SetSecurityActivity）。 */
export interface SecuritySettings {
  /** 当前安全码（手势串）；未设置时为空串（上游 `Settings.getSecurity()` 可能返回 null）。 */
  getSecurity(): string | null;
  /** 清空安全码（上游 `Settings.putSecurity("")`）。 */
  putSecurity(value: string): void;
  /** 是否启用指纹解锁（上游 `Settings.getEnableFingerprint()`）。 */
  getEnableFingerprint(): boolean;
}

/** 平台能力（指纹 / 摇一摇 / 放行跳转）。 */
export interface SecurityPlatform {
  /** 系统是否支持并已录入指纹（上游 `SetSecurityActivity.hasEnrolledFingerprints`）。 */
  hasEnrolledFingerprints(): boolean;
  /** 放行：进入下一步（上游 `startSceneForCheckStep(CHECK_STEP_SECURITY)` + `finish()`）。 */
  grantAccess(): void;
  /** 退出锁屏页（上游 `finish()`）。 */
  finish(): void;
}

/**
 * 手势/指纹锁屏（对位上游 `SecurityScene`）。
 */
export class SecurityScene {
  /** 本页不显示左侧抽屉（上游 `needShowLeftDrawer() = false`）。 */
  static readonly NEED_SHOW_LEFT_DRAWER: boolean = false;

  /** 剩余重试次数（上游 `mRetryTimes`）。 */
  private retryTimes: number = MAX_RETRY_TIMES;
  /** 安全码是否已被摇一摇清空（仅用于日志/断言）。 */
  private securityCleared: boolean = false;

  constructor(retryTimes: number = MAX_RETRY_TIMES) {
    this.retryTimes = retryTimes;
  }

  /** 剩余重试次数。 */
  remainingRetries(): number {
    return this.retryTimes;
  }

  /** 安全码是否已被清空（摇一摇路径）。 */
  isSecurityCleared(): boolean {
    return this.securityCleared;
  }

  /** 恢复时忽略非法初值（上游 `savedInstanceState.getInt` 缺省 0 → 会导致一进来就 finish）。 */
  static retryTimesFromSaved(saved: number | null): number {
    return saved === null ? MAX_RETRY_TIMES : saved;
  }

  /**
   * 是否启用指纹入口（上游 `isFingerprintAuthAvailable`：三条件同时成立）。
   *
   * 注意 `enableFingerprint` 是**设置开关**，`enrolled` 是**系统侧已录入**，两者不可互相替代。
   */
  static fingerprintAvailable(platform: SecurityPlatform, settings: SecuritySettings,
    systemSupported: boolean): boolean {
    const availability: FingerprintAvailability = new FingerprintAvailability(
      systemSupported, settings.getEnableFingerprint(), platform.hasEnrolledFingerprints());
    return availability.available();
  }

  /**
   * 手势判定（上游 `onPatternDetected`）。
   *
   * **相等比较用 `patternToString` 的输出 vs `getSecurity()`**；两者都为 null/空也算相等
   * （上游 `ObjectUtils.equal` 的语义：都为 null → true）。
   */
  static judgePattern(pattern: Cell[], target: string | null): boolean {
    const entered: string = LockPatternUtils.patternToString(pattern);
    if (target === null || target.length === 0) {
      return entered.length === 0;
    }
    return entered === target;
  }

  /**
   * 一次手势提交（含重试计数）。
   *
   * 顺序照上游：**先判对错，再决定是否扣次数**；扣到 0 → `EXHAUSTED`（调用方 finish）。
   */
  checkPattern(pattern: Cell[], settings: SecuritySettings): PatternOutcome {
    const target: string | null = settings.getSecurity();
    if (SecurityScene.judgePattern(pattern, target)) {
      return PatternOutcome.SUCCESS;
    }
    this.retryTimes--;
    if (this.retryTimes <= 0) {
      hilog.warn(DOMAIN, TAG, 'pattern retries exhausted, closing security scene');
      return PatternOutcome.EXHAUSTED;
    }
    return PatternOutcome.WRONG;
  }

  /** 手势失败时该设置的显示模式（上游 `mPatternView.setDisplayMode(Wrong)`）。 */
  static displayModeFor(outcome: PatternOutcome): PatternDisplayMode | null {
    return outcome === PatternOutcome.WRONG ? PatternDisplayMode.WRONG : null;
  }

  /**
   * 指纹事件分派（上游三个回调）。
   *
   * @returns 需要延迟的动作；`null` 表示无动作（成功时不返回 null —— 见 `fingerprintDelayFor`）
   */
  static fingerprintErrorAction(event: FingerprintEvent): FingerprintErrorAction | null {
    if (event === FingerprintEvent.FAILED) {
      return FingerprintErrorAction.RESET_ICON;
    }
    if (event === FingerprintEvent.ERROR) {
      return FingerprintErrorAction.HIDE_ICON;
    }
    return null;
  }

  /** 指纹事件对应的延迟毫秒（成功 100 / 错误 1200；失败也走 1200 复位）。 */
  static fingerprintDelayFor(event: FingerprintEvent): number {
    return event === FingerprintEvent.SUCCEEDED ? SUCCESS_DELAY_MILLIS : ERROR_TIMEOUT_MILLIS;
  }

  /**
   * 摇一摇（上游 `onShake`）。
   *
   * 只有 **count == 10** 才动作：清空安全码 + 放行。其它次数**什么都不做**（不是 >= 阈值）。
   *
   * @returns 是否触发了"解除锁屏并放行"
   */
  handleShake(count: number, settings: SecuritySettings, platform: SecurityPlatform): boolean {
    if (count !== SHAKE_THRESHOLD) {
      return false;
    }
    hilog.warn(DOMAIN, TAG, 'shake x%{public}d → clearing security code', count);
    settings.putSecurity('');
    this.securityCleared = true;
    platform.grantAccess();
    return true;
  }

  /** 手势成功后的放行（上游 `startSceneForCheckStep` + `finish`）。 */
  static grantOnPatternSuccess(platform: SecurityPlatform): void {
    platform.grantAccess();
  }

  /** 重试耗尽后的退出（上游 `finish()`，不提示、不禁用）。 */
  static closeOnExhausted(platform: SecurityPlatform): void {
    platform.finish();
  }

  /** 保存实例状态时写回的重试次数（上游 `onSaveInstanceState`）。 */
  saveRetryTimes(): number {
    return this.retryTimes;
  }
}
