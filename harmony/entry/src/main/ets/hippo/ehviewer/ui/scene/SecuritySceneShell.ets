/*
 * 阶段 A 任务 B3：SecurityScene 逻辑外壳与门 1 接口隔离。
 *
 * 将无 UI 依赖的状态机 `SecurityScene` 与 `SolidScene` / `SceneFragment` 生命周期桥接，
 * 供 `SceneRegistry`、`AppWiring` 与 `MainPageHostView`（门 1 解锁链路）统一装配，
 * 并为 Track P1 独立实现 `SecuritySceneView` 预留平台注入点。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../../scene/SceneTypes';
import { SolidScene } from './SolidScene';
import { SecurityScene, SecuritySettings, SecurityPlatform, MAX_RETRY_TIMES } from './SecurityScene';

const DOMAIN: number = 0x0000;
const TAG: string = 'SecuritySceneShell';

class UnavailableSecuritySettings implements SecuritySettings {
  private warned: boolean = false;

  private warnOnce(op: string): void {
    if (!this.warned) {
      this.warned = true;
      hilog.warn(DOMAIN, TAG,
        '%{public}s: SecuritySettings 未接线（SceneRegistry 无参构造或未通过 AppWiring 装配）', op);
    }
  }

  getSecurity(): string | null {
    this.warnOnce('getSecurity');
    return '';
  }

  putSecurity(value: string): void {
    this.warnOnce('putSecurity(' + value + ')');
  }

  getEnableFingerprint(): boolean {
    this.warnOnce('getEnableFingerprint');
    return false;
  }
}

class ShellSecurityPlatform implements SecurityPlatform {
  private shell: SecuritySceneShell;
  private enrolledFn: () => boolean;

  constructor(shell: SecuritySceneShell, enrolledFn: () => boolean) {
    this.shell = shell;
    this.enrolledFn = enrolledFn;
  }

  hasEnrolledFingerprints(): boolean {
    return this.enrolledFn();
  }

  grantAccess(): void {
    this.shell.grantAccess();
  }

  finish(): void {
    this.shell.finishSecurity();
  }
}

/**
 * `SecurityScene` 的 `SolidScene` 外壳。
 */
export class SecuritySceneShell extends SolidScene {
  private logic: SecurityScene;
  private securitySettings: SecuritySettings | null;
  private enrolledFingerprintsProvider: (() => boolean) | null = null;
  private onUnlockedListener: (() => void) | null = null;
  private unlocked: boolean = false;
  private finished: boolean = false;

  constructor(settings: SecuritySettings | null = null, retryTimes: number = MAX_RETRY_TIMES) {
    super();
    this.securitySettings = settings;
    this.logic = new SecurityScene(retryTimes);
  }

  getSceneName(): string {
    return 'SecurityScene';
  }

  needShowLeftDrawer(): boolean {
    return SecurityScene.NEED_SHOW_LEFT_DRAWER;
  }

  getLogic(): SecurityScene {
    return this.logic;
  }

  getSettings(): SecuritySettings {
    if (this.securitySettings !== null) {
      return this.securitySettings;
    }
    return new UnavailableSecuritySettings();
  }

  setSettings(settings: SecuritySettings | null): void {
    this.securitySettings = settings;
  }

  setEnrolledFingerprintsProvider(provider: (() => boolean) | null): void {
    this.enrolledFingerprintsProvider = provider;
  }

  setOnUnlockedListener(listener: (() => void) | null): void {
    this.onUnlockedListener = listener;
  }

  isUnlocked(): boolean {
    return this.unlocked;
  }

  isFinished(): boolean {
    return this.finished;
  }

  createPlatform(): SecurityPlatform {
    return new ShellSecurityPlatform(this, (): boolean => {
      if (this.enrolledFingerprintsProvider !== null) {
        return this.enrolledFingerprintsProvider();
      }
      return false;
    });
  }

  /** 解锁放行：通知门控宿主 → 按 CHECK_STEP_SECURITY 继续启动链 → 关闭自身 */
  grantAccess(): void {
    this.unlocked = true;
    if (this.onUnlockedListener !== null) {
      this.onUnlockedListener();
    }
    const args: SceneArgs | null = this.getArguments();
    this.startSceneForCheckStep(SolidScene.CHECK_STEP_SECURITY, args);
    this.finish();
  }

  /** 失败次数耗尽等场景关闭安全锁页 */
  finishSecurity(): void {
    this.finished = true;
    this.finish();
  }
}
