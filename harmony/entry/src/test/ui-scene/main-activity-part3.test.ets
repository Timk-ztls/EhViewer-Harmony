/*
 * download-sync 接手批单测：MainActivity Part 3（S0212）—— Activity 生命周期与意图回传
 *
 * 钉住的语义（都是"写错也能编译、但会丢意图/卡住退不出去"）：
 *   ① 启动门链五道 **first-match**，顺序 Security→Warning→Analytics→SignIn→SelectSite→列表
 *   ② `processAnnouncer` **只在 sceneCount==0 时包装**，且门场景带 target_scene/target_args；
 *      `launchAnnouncerFor` 的门**不带** target（没有原目标）—— 这两个函数必须能区分
 *   ③ handleIntent 三分支：VIEW(url) / SEND text(关键词) / SEND image/*(图搜)
 *   ④ onUnrecognizedIntent：栈顶 SolidScene → **丢弃**；栈空 + URL 失败 → **finish**
 *   ⑤ onBackPressed：抽屉开着**先关抽屉**
 *   ⑥ onNavigationItemSelected：已选中 → **返回 false（不重复选）**
 *   ⑦ setNavCheckedItem：resId==0 → `nav_stub` 占位
 *   ⑧ onActivityResult 三分支；设置页**不论 resultCode 都 return**
 *   ⑨ KEY_RESTART → **丢弃 savedInstanceState**
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  MainActivity, StartupGates, IntentSummaryLike, IntentTargetKind, UnrecognizedAction,
  UnrecognizedPlan, BackAction, ActivityResultAction, ActivityResultPlan
} from '../../main/ets/hippo/ehviewer/ui/MainActivity';
import { Announcer } from '../../main/ets/hippo/scene/Announcer';

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

function gates(all: boolean): StartupGates {
  return new StartupGates(all, all, all, all, all, 'action_homepage');
}

function none(): StartupGates {
  return new StartupGates(false, false, false, false, false, 'action_homepage');
}

// ---------------------------------------------------------------- ① 启动门链

function testLaunchChain(): void {
  eq('有安全码 → Security', MainActivity.launchAnnouncerFor(gates(true)).sceneName, 'SecurityScene');

  const noSec: StartupGates = gates(true);
  noSec.hasSecurity = false;
  eq('无安全码但需警告 → Warning', MainActivity.launchAnnouncerFor(noSec).sceneName, 'WarningScene');

  const noWarn: StartupGates = gates(true);
  noWarn.hasSecurity = false;
  noWarn.showWarning = false;
  eq('再少警告 → 跳过已作废的 AnalyticsScene 直接进 SignIn',
    MainActivity.launchAnnouncerFor(noWarn).sceneName, 'SignInScene');

  const noAna: StartupGates = gates(true);
  noAna.hasSecurity = false;
  noAna.showWarning = false;
  noAna.askAnalytics = false;
  eq('askAnalytics=false → SignIn', MainActivity.launchAnnouncerFor(noAna).sceneName, 'SignInScene');

  const noSign: StartupGates = gates(true);
  noSign.hasSecurity = false;
  noSign.showWarning = false;
  noSign.needSignedIn = false;
  eq('再少登录（即使 askAnalytics=true）→ SelectSite',
    MainActivity.launchAnnouncerFor(noSign).sceneName, 'SelectSiteScene');

  const noSiteWithAna: StartupGates = none();
  noSiteWithAna.askAnalytics = true;
  noSiteWithAna.launchPageAction = 'action_homepage';
  eq('全过（即使 askAnalytics=true）→ GalleryListScene',
    MainActivity.launchAnnouncerFor(noSiteWithAna).sceneName, 'GalleryListScene');

  // 全过 → 列表 + launchPage action（**不是写死 homepage**）
  const open: StartupGates = none();
  open.launchPageAction = 'action_subscription';
  const list: Announcer = MainActivity.launchAnnouncerFor(open);
  eq('全过 → 列表', list.sceneName, 'GalleryListScene');
  eq('列表带 launchPage action', list.args === null ? null : list.args.get('action'),
    'action_subscription');
  eq('门场景**不带** target（没有原目标）',
    MainActivity.launchAnnouncerFor(gates(true)).args, null);
}

// ---------------------------------------------------------------- ② processAnnouncer 包装

function testProcessAnnouncer(): void {
  const target: Announcer = new Announcer('GalleryDetailScene');

  // 栈里已有场景 → **不包装**
  const same: Announcer = MainActivity.processAnnouncer(target, 3, gates(true));
  eq('sceneCount != 0 → 原样返回', same.sceneName, 'GalleryDetailScene');
  eq('sceneCount != 0 → 不带 target args', same.args, null);

  // 栈空 + 有安全码 → 包成 SecurityScene，带 target
  const wrapped: Announcer = MainActivity.processAnnouncer(target, 0, gates(true));
  eq('栈空 + 有安全码 → Security', wrapped.sceneName, 'SecurityScene');
  eq('带 target_scene', wrapped.args === null ? null : wrapped.args.get('target_scene'),
    'GalleryDetailScene');

  // 门场景的 args 也要带过去
  const withArgs: Announcer = new Announcer('GalleryDetailScene');
  const inner: Map<string, Object> = new Map<string, Object>();
  inner.set('gid', 123);
  withArgs.setArgs(inner);
  const wrapped2: Announcer = MainActivity.processAnnouncer(withArgs, 0, gates(true));
  const carried: Object | undefined = wrapped2.args === null ? undefined : wrapped2.args.get('target_args');
  ok('带 target_args（原场景参数）', carried !== undefined && carried !== null);
  eq('target_args 里是原 gid',
    carried === undefined || carried === null ? null : (carried as Map<string, Object>).get('gid'), 123);

  // 栈空 + 全过 → 原样（无门可包）
  eq('栈空 + 无门 → 原样', MainActivity.processAnnouncer(target, 0, none()).sceneName,
    'GalleryDetailScene');

  // 门的顺序与 launchAnnouncerFor 一致（且 processAnnouncer 也跳过 AnalyticsScene）
  const g: StartupGates = gates(true);
  g.hasSecurity = false;
  eq('无安全码 → 包成 Warning',
    MainActivity.processAnnouncer(target, 0, g).sceneName, 'WarningScene');
  g.showWarning = false;
  eq('无安全码且无警告（即使 askAnalytics=true）→ 包成 SignIn',
    MainActivity.processAnnouncer(target, 0, g).sceneName, 'SignInScene');
}

// ---------------------------------------------------------------- ③ handleIntent

function testIntentTarget(): void {
  eq('null 意图 → NONE', MainActivity.intentTargetFor(null).kind, IntentTargetKind.NONE);

  // VIEW + url
  const view: IntentSummaryLike = new IntentSummaryLike('android.intent.action.VIEW',
    'https://e-hentai.org/g/1/tok/', null, null, null);
  eq('VIEW + url → URL', MainActivity.intentTargetFor(view).kind, IntentTargetKind.URL);
  eq('VIEW 带出 url', MainActivity.intentTargetFor(view).uri, 'https://e-hentai.org/g/1/tok/');

  // VIEW 无 url → NONE
  eq('VIEW 无 url → NONE',
    MainActivity.intentTargetFor(new IntentSummaryLike('android.intent.action.VIEW', null, null, null, null)).kind,
    IntentTargetKind.NONE);

  // SEND text/plain → 关键词
  const sendText: IntentSummaryLike = new IntentSummaryLike('android.intent.action.SEND',
    null, 'text/plain', 'blue archive', null);
  eq('SEND text/plain → KEYWORD', MainActivity.intentTargetFor(sendText).kind,
    IntentTargetKind.KEYWORD);
  eq('关键词透传', MainActivity.intentTargetFor(sendText).keyword, 'blue archive');

  // SEND image/* → 图搜
  const sendImg: IntentSummaryLike = new IntentSummaryLike('android.intent.action.SEND',
    null, 'image/png', null, 'content://img/1');
  const img = MainActivity.intentTargetFor(sendImg);
  eq('SEND image/* → IMAGE_SEARCH', img.kind, IntentTargetKind.IMAGE_SEARCH);
  eq('带出 stream', img.uri, 'content://img/1');
  eq('标记 hasStream', img.hasStream, true);

  // SEND image/* 无 stream → hasStream=false（调用方据此中止）
  eq('无 stream → hasStream=false',
    MainActivity.intentTargetFor(new IntentSummaryLike('android.intent.action.SEND', null,
      'image/jpeg', null, null)).hasStream, false);

  // 其它 action
  eq('未知 action → NONE',
    MainActivity.intentTargetFor(new IntentSummaryLike('android.intent.action.MAIN', null,
      null, null, null)).kind, IntentTargetKind.NONE);

  // 图搜参数
  const args: Map<string, Object> = MainActivity.imageSearchArgsOf('/tmp/img.png');
  eq('图搜 mode=1（MODE_IMAGE_SEARCH）', args.get('mode'), 1);
  eq('图搜 image_path', args.get('image_path'), '/tmp/img.png');
  eq('图搜 use_similarity_scan', args.get('use_similarity_scan'), true);
  eq('图搜 show_expunged', args.get('show_expunged'), true);
}

// ---------------------------------------------------------------- ④ onUnrecognizedIntent

function testUnrecognized(): void {
  // 栈顶 SolidScene → 丢弃（即使没处理、即使是 URL）
  const drop: UnrecognizedPlan = MainActivity.unrecognizedIntentPlan(true, false, true, 0);
  eq('SolidScene 栈顶 → DROP', drop.action, UnrecognizedAction.DROP);
  eq('DROP 不弹 toast', drop.toastParseError, false);

  // 已处理 → 什么都不做
  eq('已处理 → NONE', MainActivity.unrecognizedIntentPlan(false, true, true, 0).action,
    UnrecognizedAction.NONE);

  // 没处理 + 栈空 + URL → FINISH（且要有 toast）
  const finish: UnrecognizedPlan = MainActivity.unrecognizedIntentPlan(false, false, true, 0);
  eq('栈空 + URL 失败 → FINISH', finish.action, UnrecognizedAction.FINISH);
  eq('URL 失败要 toast', finish.toastParseError, true);

  // 没处理 + 栈空 + 非 URL → 进列表
  const startList: UnrecognizedPlan = MainActivity.unrecognizedIntentPlan(false, false, false, 0);
  eq('栈空 + 非 URL → START_LIST', startList.action, UnrecognizedAction.START_LIST);
  eq('非 URL 不 toast', startList.toastParseError, false);

  // 没处理 + 栈非空 → 什么都不做（但 URL 仍 toast）
  const keep: UnrecognizedPlan = MainActivity.unrecognizedIntentPlan(false, false, true, 2);
  eq('栈非空 → NONE（不 finish！）', keep.action, UnrecognizedAction.NONE);
  eq('但 URL 解析失败仍 toast', keep.toastParseError, true);
}

// ---------------------------------------------------------------- ⑤⑥⑦ 返回键 / 选中 / 占位

function testBackAndNav(): void {
  eq('抽屉开着 → 先关抽屉', MainActivity.backActionFor(true), BackAction.CLOSE_DRAWERS);
  eq('抽屉关着 → 交给场景栈', MainActivity.backActionFor(false), BackAction.TO_SCENE_STACK);

  eq('已选中 → 不再选（返回 false）', MainActivity.shouldSelectNavItem(true), false);
  eq('未选中 → 选', MainActivity.shouldSelectNavItem(false), true);

  eq('resId=0 → nav_stub 占位', MainActivity.navStubFor(0), 'nav_stub');
  eq('resId 非 0 → 用自身', MainActivity.navStubFor(7), '7');
}

// ---------------------------------------------------------------- ⑧ onActivityResult

function testActivityResult(): void {
  // 设置页 OK → 刷新栈顶
  const s1: ActivityResultPlan = MainActivity.activityResultPlan(
    MainActivity.REQUEST_CODE_SETTINGS, MainActivity.RESULT_OK, false);
  eq('设置页 OK → REFRESH_TOP_SCENE', s1.action, ActivityResultAction.REFRESH_TOP_SCENE);
  eq('设置页 OK → 真的刷新', s1.shouldRefresh, true);

  // 设置页 取消 → 仍 return（不交给父类），但不刷新
  const s2: ActivityResultPlan = MainActivity.activityResultPlan(
    MainActivity.REQUEST_CODE_SETTINGS, 0, false);
  eq('设置页取消 → 仍 REFRESH_TOP_SCENE（只是不刷）', s2.action,
    ActivityResultAction.REFRESH_TOP_SCENE);
  eq('设置页取消 → 不刷新', s2.shouldRefresh, false);

  // 相机 + OK + 有 userImageChange → 存头像
  eq('相机 OK → SAVE_USER_IMAGE', MainActivity.activityResultPlan(
    MainActivity.REQUEST_CODE_TAKE_CAMERA, MainActivity.RESULT_OK, true).action,
    ActivityResultAction.SAVE_USER_IMAGE);
  eq('相册 OK → SAVE_USER_IMAGE', MainActivity.activityResultPlan(
    MainActivity.REQUEST_CODE_PICK_PHOTO, MainActivity.RESULT_OK, true).action,
    ActivityResultAction.SAVE_USER_IMAGE);

  // 相机 + OK 但没 userImageChange → 交给父类
  eq('无 userImageChange → TO_SUPER', MainActivity.activityResultPlan(
    MainActivity.REQUEST_CODE_TAKE_CAMERA, MainActivity.RESULT_OK, false).action,
    ActivityResultAction.TO_SUPER);

  // 相机 + 取消 → 交给父类
  eq('相机取消 → TO_SUPER', MainActivity.activityResultPlan(
    MainActivity.REQUEST_CODE_TAKE_CAMERA, 0, true).action, ActivityResultAction.TO_SUPER);

  // 未知 requestCode + OK → 交给父类（场景结果）
  eq('未知 code → TO_SUPER', MainActivity.activityResultPlan(9999, MainActivity.RESULT_OK, true).action,
    ActivityResultAction.TO_SUPER);
}

// ---------------------------------------------------------------- ⑨ 状态保存

function testSavedState(): void {
  eq('只有一个键', MainActivity.savedKeys(), ['nav_checked_item']);
  eq('缺省 navChecked = 0', MainActivity.navCheckedFromSaved(null), 0);
  eq('有值就用', MainActivity.navCheckedFromSaved(5), 5);
  eq('KEY_RESTART=true → 丢弃 savedInstanceState', MainActivity.shouldDropSavedState(true), true);
  eq('正常启动 → 保留', MainActivity.shouldDropSavedState(false), false);
  eq('RESULT_OK 是 -1（Android 约定）', MainActivity.RESULT_OK, -1);
  eq('REQUEST_CODE_SETTINGS = 0', MainActivity.REQUEST_CODE_SETTINGS, 0);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testLaunchChain();
  testProcessAnnouncer();
  testIntentTarget();
  testUnrecognized();
  testBackAndNav();
  testActivityResult();
  testSavedState();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync main activity part3 test failed');
  }
  console.log(`✓ download-sync 主界面 Part3 批: ${pass} 条断言全部通过`);
}

main();
