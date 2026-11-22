/*
 * download-sync 接手批单测：SecurityScene（S0256）+ ProgressScene（S0255）
 *
 * 钉住的语义（都是"写错也能编译，但用户会被莫名踢出 / 卡在错误页"）：
 *   Security：重试 5 次耗尽**直接 finish**、指纹失败**不扣次数**、指纹错误分级（复位 vs 隐藏）、
 *            摇一摇阈值 **== 10** 且成功后**清空安全码**、指纹入口三条件
 *   Progress：参数三缺一即无效（page 的 sentinel 是 **-1**，第 0 页合法）、初始化两段式、
 *            无效文案是**固定串**、失败回调只在视图存活时改 UI、详情页 action 是 **gid_token**
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  SecurityScene, SecuritySettings, SecurityPlatform, MAX_RETRY_TIMES, ERROR_TIMEOUT_MILLIS,
  SUCCESS_DELAY_MILLIS, SHAKE_THRESHOLD, PatternOutcome, PatternDisplayMode, FingerprintEvent,
  FingerprintErrorAction, FingerprintAvailability
} from '../../main/ets/hippo/ehviewer/ui/scene/SecurityScene';
import {
  ProgressScene, ProgressArgs, ProgressState, ProgressView, GalleryTokenRequester,
  ACTION_GALLERY_TOKEN, KEY_VALID, KEY_ERROR, KEY_GID, KEY_PTOKEN, KEY_PAGE,
  DETAIL_ACTION_GID_TOKEN, DEFAULT_GID, DEFAULT_PAGE
} from '../../main/ets/hippo/ehviewer/ui/scene/ProgressScene';
import { Cell } from '../../main/ets/hippo/widget/lockpattern/LockPatternCell';
import { LockPatternUtils } from '../../main/ets/hippo/widget/lockpattern/LockPatternUtils';

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
    fails.push(`${name}  (want true)`);
  }
}

// ---------------------------------------------------------------- 假实现

class FakeSettings implements SecuritySettings {
  security: string | null = '';
  fingerprintEnabled: boolean = true;
  putCalls: string[] = [];

  getSecurity(): string | null { return this.security; }
  putSecurity(value: string): void { this.putCalls.push(value); this.security = value; }
  getEnableFingerprint(): boolean { return this.fingerprintEnabled; }
}

class FakePlatform implements SecurityPlatform {
  enrolled: boolean = true;
  granted: number = 0;
  finished: number = 0;

  hasEnrolledFingerprints(): boolean { return this.enrolled; }
  grantAccess(): void { this.granted++; }
  finish(): void { this.finished++; }
}

class FakeRequester implements GalleryTokenRequester {
  calls: string[] = [];
  returnValue: boolean = true;
  requestGalleryToken(gid: number, pToken: string, page: number): boolean {
    this.calls.push(`${gid}|${pToken}|${page}`);
    return this.returnValue;
  }
}

/** 造一个 3 点手势（值本身不重要，只用于 patternToString 的一致性） */
function patternOf(): Cell[] {
  return [Cell.of(0, 0), Cell.of(1, 1), Cell.of(2, 2)];
}

// ---------------------------------------------------------------- Security：常量

function testSecurityConstants(): void {
  eq('最大重试 5 次', MAX_RETRY_TIMES, 5);
  eq('指纹错误显示 1200ms', ERROR_TIMEOUT_MILLIS, 1200);
  eq('成功延迟 100ms', SUCCESS_DELAY_MILLIS, 100);
  eq('摇一摇阈值 10', SHAKE_THRESHOLD, 10);
  eq('不显示左侧抽屉', SecurityScene.NEED_SHOW_LEFT_DRAWER, false);
}

// ---------------------------------------------------------------- Security：指纹可用性

function testFingerprintAvailability(): void {
  const platform: FakePlatform = new FakePlatform();
  const settings: FakeSettings = new FakeSettings();

  eq('三条件齐 → 可用', SecurityScene.fingerprintAvailable(platform, settings, true), true);

  settings.fingerprintEnabled = false;
  eq('设置关了 → 不可用', SecurityScene.fingerprintAvailable(platform, settings, true), false);
  settings.fingerprintEnabled = true;

  platform.enrolled = false;
  eq('系统没录入 → 不可用', SecurityScene.fingerprintAvailable(platform, settings, true), false);
  platform.enrolled = true;

  eq('系统不支持 → 不可用', SecurityScene.fingerprintAvailable(platform, settings, false), false);

  // 三条件的组合表（8 种，只有全真才可用）
  const av: FingerprintAvailability = new FingerprintAvailability(true, true, false);
  eq('缺 enrolled → false', av.available(), false);
  eq('全真 → true', new FingerprintAvailability(true, true, true).available(), true);
}

// ---------------------------------------------------------------- Security：手势

function testPatternJudge(): void {
  const pattern: Cell[] = patternOf();
  // 同样的 pattern 一定自洽（不假设具体串值，只验一致性）
  const ts: string = LockPatternUtils.patternToString(pattern);
  eq('同 pattern 与自身相等等于 true', SecurityScene.judgePattern(pattern, ts), true);
  eq('与不同串不等', SecurityScene.judgePattern(pattern, 'not-the-same'), false);
  // 目标为空/null 时，只有空手势算成功（上游 ObjectUtils.equal 语义）
  eq('目标 null + 非空手势 → false', SecurityScene.judgePattern(pattern, null), false);
  eq('空手势 vs null 目标 → 一致',
    SecurityScene.judgePattern([], null), true);
}

function testRetryExhaustion(): void {
  const settings: FakeSettings = new FakeSettings();
  settings.security = 'target-different-from-any-pattern';
  const platform: FakePlatform = new FakePlatform();

  const scene: SecurityScene = new SecurityScene();
  eq('初始 5 次', scene.remainingRetries(), 5);

  // 连续错 4 次 → 每次 WRONG，次数递减
  const outcomes: PatternOutcome[] = [];
  for (let i = 0; i < 4; i++) {
    outcomes.push(scene.checkPattern(patternOf(), settings));
  }
  eq('前 4 次都是 WRONG', outcomes.every((o: PatternOutcome): boolean => o === PatternOutcome.WRONG),
    true);
  eq('剩 1 次', scene.remainingRetries(), 1);

  // 第 5 次 → EXHAUSTED
  eq('第 5 次 → EXHAUSTED', scene.checkPattern(patternOf(), settings), PatternOutcome.EXHAUSTED);
  eq('剩 0 次', scene.remainingRetries(), 0);

  // EXHAUSTED 的处理是 finish（不是禁用输入）
  SecurityScene.closeOnExhausted(platform);
  eq('耗尽 → finish 一次', platform.finished, 1);

  // 失败时显示模式为 Wrong
  eq('WRONG → 显示模式 Wrong',
    SecurityScene.displayModeFor(PatternOutcome.WRONG), PatternDisplayMode.WRONG);
  eq('SUCCESS → 不改显示模式', SecurityScene.displayModeFor(PatternOutcome.SUCCESS), null);
}

function testRetryRestore(): void {
  eq('bundle 里没有 → 回到 5', SecurityScene.retryTimesFromSaved(null), MAX_RETRY_TIMES);
  eq('bundle 里有 3 → 用 3', SecurityScene.retryTimesFromSaved(3), 3);
  eq('从 0 恢复 → 仍是 0（上游行为，不做兜底）', SecurityScene.retryTimesFromSaved(0), 0);
  const s: SecurityScene = new SecurityScene(2);
  eq('构造时可指定初值', s.remainingRetries(), 2);
  eq('saveRetryTimes 返回当前值', s.saveRetryTimes(), 2);
}

// ---------------------------------------------------------------- Security：指纹事件

function testFingerprintEvents(): void {
  eq('成功延迟 100ms', SecurityScene.fingerprintDelayFor(FingerprintEvent.SUCCEEDED),
    SUCCESS_DELAY_MILLIS);
  eq('失败延迟 1200ms', SecurityScene.fingerprintDelayFor(FingerprintEvent.FAILED),
    ERROR_TIMEOUT_MILLIS);
  eq('错误延迟 1200ms', SecurityScene.fingerprintDelayFor(FingerprintEvent.ERROR),
    ERROR_TIMEOUT_MILLIS);

  eq('Failed → 复位图标',
    SecurityScene.fingerprintErrorAction(FingerprintEvent.FAILED), FingerprintErrorAction.RESET_ICON);
  eq('Error → 隐藏图标',
    SecurityScene.fingerprintErrorAction(FingerprintEvent.ERROR), FingerprintErrorAction.HIDE_ICON);
  eq('Succeeded → 无错误动作',
    SecurityScene.fingerprintErrorAction(FingerprintEvent.SUCCEEDED), null);
}

function testFingerprintDoesNotConsumeRetries(): void {
  const scene: SecurityScene = new SecurityScene();
  // 指纹失败只走 UI 动作，不动 retryTimes
  SecurityScene.fingerprintErrorAction(FingerprintEvent.FAILED);
  SecurityScene.fingerprintErrorAction(FingerprintEvent.ERROR);
  eq('指纹失败/错误都不扣重试次数（上游注释：由系统处理）', scene.remainingRetries(), 5);
}

// ---------------------------------------------------------------- Security：摇一摇

function testShake(): void {
  const settings: FakeSettings = new FakeSettings();
  settings.security = 'abc';
  const platform: FakePlatform = new FakePlatform();

  const scene: SecurityScene = new SecurityScene();
  eq('9 次不触发', scene.handleShake(9, settings, platform), false);
  eq('11 次也不触发（阈值是 ==10，不是 >=）', scene.handleShake(11, settings, platform), false);
  eq('上述两次都没清安全码', settings.putCalls.length, 0);
  eq('也没放行', platform.granted, 0);

  eq('第 10 次触发', scene.handleShake(10, settings, platform), true);
  eq('清空安全码（putSecurity("")）', settings.putCalls, ['']);
  eq('安全码变为空串', settings.security, '');
  eq('放行一次', platform.granted, 1);
  eq('标记已清空', scene.isSecurityCleared(), true);
}

// ---------------------------------------------------------------- Progress：常量与参数

function testProgressArgs(): void {
  eq('动作键', ACTION_GALLERY_TOKEN, 'gallery_token');
  eq('gid 缺省哨兵 -1', DEFAULT_GID, -1);
  eq('page 缺省哨兵 -1（**不是 0**，第 0 页合法）', DEFAULT_PAGE, -1);
  eq('bundle 键 valid/error/gid/ptoken/page',
    [KEY_VALID, KEY_ERROR, KEY_GID, KEY_PTOKEN, KEY_PAGE], ['valid', 'error', 'gid', 'ptoken', 'page']);
  eq('详情页 action 是 gid_token（与本页 gallery_token 不同）',
    DETAIL_ACTION_GID_TOKEN, 'gid_token');

  eq('null 参数 → 无效', ProgressScene.handleArgs(null), null);
  eq('动作不对 → 无效', ProgressScene.handleArgs(new ProgressArgs('other', 1, 'p', 0)), null);

  // 三缺一
  eq('gid=-1 → 无效',
    ProgressScene.handleArgs(new ProgressArgs(ACTION_GALLERY_TOKEN, -1, 'p', 0)), null);
  eq('pToken=null → 无效',
    ProgressScene.handleArgs(new ProgressArgs(ACTION_GALLERY_TOKEN, 1, null, 0)), null);
  eq('page=-1 → 无效',
    ProgressScene.handleArgs(new ProgressArgs(ACTION_GALLERY_TOKEN, 1, 'p', -1)), null);

  // 合法：第 0 页是合法值
  const valid: ProgressArgs | null =
    ProgressScene.handleArgs(new ProgressArgs(ACTION_GALLERY_TOKEN, 1, 'p', 0));
  ok('gid/pToken/page 都有且 page=0 → 合法', valid !== null);
  eq('解出的 page', valid === null ? null : valid.page, 0);
}

// ---------------------------------------------------------------- Progress：初始化两段式

function testProgressInit(): void {
  const req: FakeRequester = new FakeRequester();

  // ① 参数非法 → 不发请求，固定错误文案
  const bad: ProgressState = ProgressScene.init(
    new ProgressArgs(ACTION_GALLERY_TOKEN, -1, 'p', 0), true, req);
  eq('参数非法 → invalid', bad.valid, false);
  eq('参数非法 → 固定错误串', bad.error, ProgressScene.ERROR_SOMETHING_WRONG);
  eq('参数非法 → 没发请求', req.calls.length, 0);

  // ② 参数合法但 context 没了 → 不发请求
  const noCtx: ProgressState = ProgressScene.init(
    new ProgressArgs(ACTION_GALLERY_TOKEN, 7, 'tok', 3), false, req);
  eq('context 失效 → invalid', noCtx.valid, false);
  eq('context 失效 → 没发请求', req.calls.length, 0);

  // ③ 正常 → 发请求
  req.returnValue = true;
  const good: ProgressState = ProgressScene.init(
    new ProgressArgs(ACTION_GALLERY_TOKEN, 7, 'tok', 3), true, req);
  eq('正常 → valid', good.valid, true);
  eq('请求参数 gid|token|page', req.calls, ['7|tok|3']);

  // ④ 请求返回 false（上游 doJobs 返回 false）→ invalid
  const req2: FakeRequester = new FakeRequester();
  req2.returnValue = false;
  const failed: ProgressState = ProgressScene.init(
    new ProgressArgs(ACTION_GALLERY_TOKEN, 7, 'tok', 3), true, req2);
  eq('doJobs 返回 false → invalid', failed.valid, false);
  eq('doJobs 返回 false → 固定错误串', failed.error, ProgressScene.ERROR_SOMETHING_WRONG);
}

function testProgressViewAndRetry(): void {
  const valid: ProgressState = new ProgressState(true, null,
    new ProgressArgs(ACTION_GALLERY_TOKEN, 1, 'p', 0));
  const invalid: ProgressState = new ProgressState(false, 'err',
    new ProgressArgs(ACTION_GALLERY_TOKEN, 1, 'p', 0));
  eq('valid → 显示进度圈', ProgressScene.viewFor(valid), ProgressView.PROGRESS);
  eq('invalid → 显示错误提示', ProgressScene.viewFor(invalid), ProgressView.TIP);

  // 点重试：成功才切进度圈
  const req: FakeRequester = new FakeRequester();
  const state: ProgressState = new ProgressState(false, 'err',
    new ProgressArgs(ACTION_GALLERY_TOKEN, 5, 'tk', 2));
  eq('重试成功', ProgressScene.retry(state, true, req), true);
  eq('重试成功后 valid=true', state.valid, true);
  eq('重试发了请求', req.calls, ['5|tk|2']);

  // 参数不全时重试：什么都不做
  const req2: FakeRequester = new FakeRequester();
  const badState: ProgressState = new ProgressState(false, 'err',
    new ProgressArgs(ACTION_GALLERY_TOKEN, -1, 'tk', 2));
  eq('参数不全重试 → false', ProgressScene.retry(badState, true, req2), false);
  eq('参数不全重试 → 没发请求', req2.calls.length, 0);
  eq('状态仍是 invalid', badState.valid, false);
}

function testProgressCallbacks(): void {
  const state: ProgressState = new ProgressState(true, null,
    new ProgressArgs(ACTION_GALLERY_TOKEN, 42, 'pt', 7));

  // 成功 → 详情页参数
  const args: Map<string, Object> = ProgressScene.detailArgsOnSuccess(state, 'new-token');
  eq('详情页 action', args.get('action'), DETAIL_ACTION_GID_TOKEN);
  eq('详情页 gid', args.get('gid'), 42);
  eq('详情页 token 用返回值', args.get('token'), 'new-token');
  eq('详情页 page', args.get('page'), 7);

  // 失败：视图存活 → 要刷 UI
  const s1: ProgressState = new ProgressState(true, null,
    new ProgressArgs(ACTION_GALLERY_TOKEN, 1, 'p', 0));
  eq('视图存活 → 要刷 UI', ProgressScene.applyFailure(s1, true, true, '网络错误'), true);
  eq('失败后 valid=false', s1.valid, false);
  eq('失败后 error 是可读串', s1.error, '网络错误');

  // 失败：视图已销毁 → 只改状态
  const s2: ProgressState = new ProgressState(true, null,
    new ProgressArgs(ACTION_GALLERY_TOKEN, 1, 'p', 0));
  eq('视图销毁 → 不刷 UI', ProgressScene.applyFailure(s2, true, false, 'err'), false);
  eq('但状态仍更新', s2.valid, false);
  eq('error 仍写入', s2.error, 'err');

  // context 失效 → 也不刷 UI
  const s3: ProgressState = new ProgressState(true, null,
    new ProgressArgs(ACTION_GALLERY_TOKEN, 1, 'p', 0));
  eq('context 失效 → 不刷 UI', ProgressScene.applyFailure(s3, false, true, 'err'), false);

  // 恢复：直接按 bundle，不发请求
  const restored: ProgressState = ProgressScene.restore(true, null,
    new ProgressArgs(ACTION_GALLERY_TOKEN, 9, 'x', 1));
  eq('恢复 valid', restored.valid, true);
  eq('恢复后显示进度圈', ProgressScene.viewFor(restored), ProgressView.PROGRESS);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testSecurityConstants();
  testFingerprintAvailability();
  testPatternJudge();
  testRetryExhaustion();
  testRetryRestore();
  testFingerprintEvents();
  testFingerprintDoesNotConsumeRetries();
  testShake();
  testProgressArgs();
  testProgressInit();
  testProgressViewAndRetry();
  testProgressCallbacks();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync security/progress test failed');
  }
  console.log(`✓ download-sync 锁屏/进度批: ${pass} 条断言全部通过`);
}

main();
