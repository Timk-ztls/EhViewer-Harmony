/*
 * 阶段 A 任务 B3 单测：二级页面路由表（PageRoutes）+ 门 1 SecuritySceneShell 与 StartupGates 解除硬编码 false。
 *
 * 运行：pwsh -NoProfile -ExecutionPolicy Bypass -File harmony/entry/src/test/ui-scene/run.ps1 -Filter b3-routes
 */

import {
  PageRoutes,
  RouteActionKind,
  RouteNavigationPlan,
  SceneSlots,
} from '../../main/ets/hippo/ui/PageRoutes';
import { MainActivity, StartupGates } from '../../main/ets/hippo/ehviewer/ui/MainActivity';
import { SecuritySceneShell } from '../../main/ets/hippo/ehviewer/ui/scene/SecuritySceneShell';
import { GetProfileSceneShell } from '../../main/ets/hippo/ehviewer/ui/scene/sign/GetProfileSceneShell';
import { ProgressSceneShell } from '../../main/ets/hippo/ehviewer/ui/scene/ProgressSceneShell';
import {
  PatternOutcome,
  SecurityPlatform,
  SecurityScene,
  SecuritySettings,
} from '../../main/ets/hippo/ehviewer/ui/scene/SecurityScene';
import { SceneApplication } from '../../main/ets/hippo/scene/SceneApplication';
import { Announcer } from '../../main/ets/hippo/scene/Announcer';
import { registerAllScenes } from '../../main/ets/hippo/scene/SceneRegistry';
import { SceneFragment } from '../../main/ets/hippo/scene/SceneFragment';
import { SceneHost } from '../../main/ets/hippo/ehviewer/ui/scene/BaseScene';
import { SolidScene, SolidSceneHooks } from '../../main/ets/hippo/ehviewer/ui/scene/SolidScene';
import {
  SolidSceneSettings,
  SolidSceneSettingsHolder,
  UnwiredSolidSceneSettings,
} from '../../main/ets/hippo/ehviewer/ui/scene/SolidSceneSettings';
import { WarningScene } from '../../main/ets/hippo/ehviewer/ui/scene/WarningScene';
import { GLView } from '../../main/ets/hippo/lib/glview/view/GLView';
import { Cell } from '../../main/ets/hippo/widget/lockpattern/LockPatternCell';
import { LockPatternUtils } from '../../main/ets/hippo/widget/lockpattern/LockPatternUtils';

class NoopSceneHost implements SceneHost {
  updateProfile(): void {}
  addAboveSnackView(_view: GLView): void {}
  removeAboveSnackView(_view: GLView): void {}
  setDrawerLockMode(_lockMode: number, _edgeGravity: number): void {}
  openDrawer(_drawerGravity: number): void {}
  closeDrawer(_drawerGravity: number): void {}
  toggleDrawer(_drawerGravity: number): void {}
  setDrawerGestureBlocker(_gestureBlocker: number): void {}
  isDrawersVisible(): boolean { return false; }
  setNavCheckedItem(_resId: number): void {}
  showTipById(_id: number, _length: number): void {}
  showTip(_message: string, _length: number): void {}
  hideSoftInput(): void {}
  showSoftInput(_view: GLView): void {}
}

class StubSolidSettings implements SolidSceneSettings {
  showWarning: boolean = true;
  askAnalytics: boolean = true;
  selectSite: boolean = true;
  needSignIn: boolean = true;

  getShowWarning(): boolean { return this.showWarning; }
  getAskAnalytics(): boolean { return this.askAnalytics; }
  getSelectSite(): boolean { return this.selectSite; }
  getNeedSignIn(): boolean { return this.needSignIn; }
  getLaunchPageGalleryListSceneAction(): string { return 'action_homepage'; }
  putShowWarning(value: boolean): void { this.showWarning = value; }
  putAskAnalytics(value: boolean): void { this.askAnalytics = value; }
  putSelectSite(value: boolean): void { this.selectSite = value; }
  getGallerySite(): number { return 0; }
  putGallerySite(_value: number): void {}
  putEnableAnalytics(_value: boolean): void {}
}

class SpyWarningScene extends WarningScene {
  startedScenes: string[] = [];
  finishCount: number = 0;

  startScene(announcer: Announcer): void {
    this.startedScenes.push(announcer.sceneName);
  }

  finish(): void {
    this.finishCount++;
  }
}

class StubSecuritySettings implements SecuritySettings {
  private code: string;
  private fpEnabled: boolean;

  constructor(code: string, fpEnabled: boolean) {
    this.code = code;
    this.fpEnabled = fpEnabled;
  }

  getSecurity(): string | null {
    return this.code;
  }

  putSecurity(value: string): void {
    this.code = value;
  }

  getEnableFingerprint(): boolean {
    return this.fpEnabled;
  }
}

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

function main(): void {
  // 1. PageRoutes：已激活 14 页（P0 4 页 + Phase B P1~P4 10 页，0 预留）
  eq('注册页面严格对齐 main_pages.json 14 页', PageRoutes.getRegisteredUrls(), [
    'pages/Index',
    'pages/SettingsPage',
    'pages/HostsPage',
    'pages/GalleryReaderPage',
    'pages/SetSecurityPage',
    'pages/DirPickerPage',
    'pages/LicensePage',
    'pages/FilterPage',
    'pages/BlackListPage',
    'pages/MyTagsPage',
    'pages/UConfigPage',
    'pages/TagSelectorPage',
    'pages/WiFiServerPage',
    'pages/WiFiClientPage',
  ]);
  eq('总路由槽位数 = 14 已激活 + 0 预留', PageRoutes.getAllRoutes().length, 14);
  eq('Phase B 预留槽位已全部激活（0 条）', PageRoutes.RESERVED_PHASE_B_PAGES.length, 0);
  ok('SettingsPage 已注册', PageRoutes.isRegistered(PageRoutes.SETTINGS));
  ok('HostsPage 已注册', PageRoutes.isRegistered(PageRoutes.HOSTS));
  ok('SetSecurityPage 已注册（Track P1）', PageRoutes.isRegistered(PageRoutes.SET_SECURITY));
  ok('DirPickerPage 已注册（Track P2）', PageRoutes.isRegistered(PageRoutes.DIR_PICKER));
  ok('LicensePage 已注册（Track P2）', PageRoutes.isRegistered(PageRoutes.LICENSE));
  ok('FilterPage 已注册（Track P3）', PageRoutes.isRegistered(PageRoutes.FILTER));
  ok('BlackListPage 已注册（Track P3）', PageRoutes.isRegistered(PageRoutes.BLACK_LIST));
  ok('MyTagsPage 已注册（Track P3）', PageRoutes.isRegistered(PageRoutes.MY_TAGS));
  ok('UConfigPage 已注册（Track P3）', PageRoutes.isRegistered(PageRoutes.U_CONFIG));
  ok('TagSelectorPage 已注册（Track P3）', PageRoutes.isRegistered(PageRoutes.TAG_SELECTOR));
  ok('WiFiServerPage 已注册（Track P4）', PageRoutes.isRegistered(PageRoutes.WIFI_SERVER));
  ok('WiFiClientPage 已注册（Track P4）', PageRoutes.isRegistered(PageRoutes.WIFI_CLIENT));

  eq('SetSecurityActivity 映射到 P1', PageRoutes.findByActivity('SetSecurityActivity')?.track, 'P1');
  eq('DirPickerActivity URL 对齐 P2', PageRoutes.findByActivity('DirPickerActivity')?.url, PageRoutes.DIR_PICKER);
  eq('LicenseActivity 映射到 P2', PageRoutes.findByActivity('LicenseActivity')?.track, 'P2');
  eq('FilterActivity URL 对齐 P3', PageRoutes.findByActivity('FilterActivity')?.url, PageRoutes.FILTER);
  eq('BlackListActivity URL 对齐 P3', PageRoutes.findByActivity('BlackListActivity')?.url, PageRoutes.BLACK_LIST);
  eq('MyTagsActivity 标记需要登录', PageRoutes.findByActivity('MyTagsActivity')?.requiresSignIn, true);
  eq('UConfigActivity 标记需要登录', PageRoutes.findByActivity('UConfigActivity')?.requiresSignIn, true);
  eq('TagSelectorActivity URL 对齐 P3', PageRoutes.findByActivity('TagSelectorActivity')?.url, PageRoutes.TAG_SELECTOR);
  eq('WiFiServerActivity 映射到 P4', PageRoutes.findByActivity('WiFiServerActivity')?.track, 'P4');
  eq('WiFiClientActivity URL 对齐 P4', PageRoutes.findByActivity('WiFiClientActivity')?.url, PageRoutes.WIFI_CLIENT);

  const hostsPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.HOSTS, false);
  eq('已注册路由返回 PUSH', hostsPlan.kind, RouteActionKind.PUSH);
  const setSecPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.SET_SECURITY, false);
  eq('SetSecurityPage 已注册返回 PUSH', setSecPlan.kind, RouteActionKind.PUSH);
  const dirPickerPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.DIR_PICKER, false);
  eq('DirPickerPage 已注册返回 PUSH', dirPickerPlan.kind, RouteActionKind.PUSH);
  const licensePlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.LICENSE, false);
  eq('LicensePage 已注册返回 PUSH', licensePlan.kind, RouteActionKind.PUSH);
  const filterPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.FILTER, false);
  eq('FilterPage 未登录可直接 PUSH', filterPlan.kind, RouteActionKind.PUSH);
  const blackListPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.BLACK_LIST, false);
  eq('BlackListPage 未登录可直接 PUSH', blackListPlan.kind, RouteActionKind.PUSH);
  const tagSelectorPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.TAG_SELECTOR, false);
  eq('TagSelectorPage 未登录可直接 PUSH', tagSelectorPlan.kind, RouteActionKind.PUSH);
  const wifiServerPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.WIFI_SERVER, false);
  eq('WiFiServerPage 未登录可直接 PUSH', wifiServerPlan.kind, RouteActionKind.PUSH);
  const wifiClientPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.WIFI_CLIENT, false);
  eq('WiFiClientPage 未登录可直接 PUSH', wifiClientPlan.kind, RouteActionKind.PUSH);

  const myTagsGuestPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.MY_TAGS, false);
  eq('MyTagsPage 未登录返回 REQUIRE_SIGN_IN', myTagsGuestPlan.kind, RouteActionKind.REQUIRE_SIGN_IN);
  eq('MyTagsPage 未登录提示键为 need_sign_in', myTagsGuestPlan.tipResKey, 'need_sign_in');
  const myTagsSignedInPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.MY_TAGS, true);
  eq('MyTagsPage 已登录返回 PUSH', myTagsSignedInPlan.kind, RouteActionKind.PUSH);

  const uConfigGuestPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.U_CONFIG, false);
  eq('UConfigPage 未登录返回 REQUIRE_SIGN_IN', uConfigGuestPlan.kind, RouteActionKind.REQUIRE_SIGN_IN);
  eq('UConfigPage 未登录提示键为 need_sign_in', uConfigGuestPlan.tipResKey, 'need_sign_in');
  const uConfigSignedInPlan: RouteNavigationPlan = PageRoutes.resolveNavigation(PageRoutes.U_CONFIG, true);
  eq('UConfigPage 已登录返回 PUSH', uConfigSignedInPlan.kind, RouteActionKind.PUSH);

  const unknownPlan: RouteNavigationPlan = PageRoutes.resolveNavigation('pages/NonExistentPage', true);
  eq('未知路由返回 UNKNOWN', unknownPlan.kind, RouteActionKind.UNKNOWN);
  eq('UNKNOWN 提示键为 scene_not_supported', unknownPlan.tipResKey, 'scene_not_supported');

  // 2. SceneSlots 启动门判定
  ok('SecurityScene 为门控场景', SceneSlots.isGateScene('SecurityScene'));
  ok('WarningScene 为门控场景', SceneSlots.isGateScene('WarningScene'));
  ok('AnalyticsScene 为门控场景', SceneSlots.isGateScene('AnalyticsScene'));
  ok('SignInScene 为门控场景', SceneSlots.isGateScene('SignInScene'));
  ok('SelectSiteScene 为门控场景', SceneSlots.isGateScene('SelectSiteScene'));
  ok('GalleryListScene 非门控场景', !SceneSlots.isGateScene('GalleryListScene'));

  // 3. MainActivity.buildStartupGates：解除硬编码 false 并正确判门 1
  const emptyGates: StartupGates = MainActivity.buildStartupGates('', false, false, false, false, false, 'action_homepage');
  eq('安全码为空串时 hasSecurity=false', emptyGates.hasSecurity, false);
  eq('安全码为空串跳过门 1 直接进 GalleryListScene',
    MainActivity.launchAnnouncerFor(emptyGates).sceneName, 'GalleryListScene');

  const nullGates: StartupGates = MainActivity.buildStartupGates(null, false, false, false, false, false, 'action_homepage');
  eq('安全码为 null 时 hasSecurity=false', nullGates.hasSecurity, false);

  const lockedGates: StartupGates = MainActivity.buildStartupGates('0123', false, true, true, true, true, 'action_whats_hot');
  eq('安全码非空且未解锁时 hasSecurity=true', lockedGates.hasSecurity, true);
  eq('门 1 优先级高于后续所有门（进入 SecurityScene）',
    MainActivity.launchAnnouncerFor(lockedGates).sceneName, 'SecurityScene');

  const unlockedWarningGates: StartupGates = MainActivity.buildStartupGates('0123', true, true, true, true, true, 'action_whats_hot');
  eq('已解锁后 hasSecurity=false', unlockedWarningGates.hasSecurity, false);
  eq('已解锁后放行到门 2 WarningScene',
    MainActivity.launchAnnouncerFor(unlockedWarningGates).sceneName, 'WarningScene');

  const passedGates: StartupGates = MainActivity.buildStartupGates('0123', true, false, false, false, false, 'action_whats_hot');
  const passedAnnouncer = MainActivity.launchAnnouncerFor(passedGates);
  eq('全部通过后进入 GalleryListScene', passedAnnouncer.sceneName, 'GalleryListScene');
  eq('并保留 launchPageAction 参数', passedAnnouncer.args?.get('action'), 'action_whats_hot');

  // 4. SceneRegistry 注册与 SecuritySceneShell 解锁 / 耗尽闭环
  const app: SceneApplication = new SceneApplication();
  registerAllScenes(app);
  const regScene: SceneFragment | null = app.createScene('SecurityScene');
  ok('SceneRegistry 能构造 SecuritySceneShell', regScene instanceof SecuritySceneShell);
  eq('SecuritySceneShell 场景名', regScene !== null ? regScene.getSceneName() : '', 'SecurityScene');
  ok('SecuritySceneShell 禁止左侧抽屉',
    regScene instanceof SecuritySceneShell && !(regScene as SecuritySceneShell).needShowLeftDrawer());
  const profileReg: SceneFragment | null = app.createScene('GetProfileScene');
  ok('SceneRegistry 能构造 GetProfileSceneShell', profileReg instanceof GetProfileSceneShell);
  const progressReg: SceneFragment | null = app.createScene('ProgressScene');
  ok('SceneRegistry 能构造 ProgressSceneShell', progressReg instanceof ProgressSceneShell);

  let unlockCount: number = 0;
  const rightPattern: Cell[] = [Cell.of(0, 0), Cell.of(0, 1), Cell.of(0, 2)];
  const encodedPattern: string = LockPatternUtils.patternToString(rightPattern);
  const settings: StubSecuritySettings = new StubSecuritySettings(encodedPattern, false);
  const failShell: SecuritySceneShell = new SecuritySceneShell(settings, 2);
  failShell.setOnUnlockedListener((): void => {
    unlockCount++;
  });
  const failPlatform: SecurityPlatform = failShell.createPlatform();
  const wrongPattern: Cell[] = [Cell.of(2, 0), Cell.of(2, 1)];
  eq('首次错误返回 WRONG', failShell.getLogic().checkPattern(wrongPattern, failShell.getSettings()), PatternOutcome.WRONG);
  eq('第二次耗尽返回 EXHAUSTED', failShell.getLogic().checkPattern(wrongPattern, failShell.getSettings()), PatternOutcome.EXHAUSTED);
  SecurityScene.closeOnExhausted(failPlatform);
  ok('重试耗尽关闭后 finished=true 且未解锁', failShell.isFinished() && !failShell.isUnlocked());
  eq('未触发 unlockedListener', unlockCount, 0);

  const okShell: SecuritySceneShell = new SecuritySceneShell(settings, 5);
  okShell.setOnUnlockedListener((): void => {
    unlockCount++;
  });
  const okPlatform: SecurityPlatform = okShell.createPlatform();
  eq('正确手势返回 SUCCESS', okShell.getLogic().checkPattern(rightPattern, okShell.getSettings()), PatternOutcome.SUCCESS);
  SecurityScene.grantOnPatternSuccess(okPlatform);
  ok('放行后 isUnlocked()=true', okShell.isUnlocked());
  eq('触发了 onUnlockedListener', unlockCount, 1);

  // 5. D-006 回归：全新安装启动门链彻底跳过已作废的 AnalyticsScene
  const unwiredSolid: UnwiredSolidSceneSettings = new UnwiredSolidSceneSettings();
  eq('UnwiredSolidSceneSettings.getAskAnalytics() 默认为 false', unwiredSolid.getAskAnalytics(), false);

  const forcedNoAna: StartupGates = MainActivity.buildStartupGates(null, false, false, true, true, true, 'action_homepage');
  eq('MainActivity.buildStartupGates 强制屏蔽 askAnalytics', forcedNoAna.askAnalytics, false);
  eq('全新安装（跳过 Warning）直达 SignInScene 而非 AnalyticsScene',
    MainActivity.launchAnnouncerFor(forcedNoAna).sceneName, 'SignInScene');

  const solidStub: StubSolidSettings = new StubSolidSettings();
  SolidSceneSettingsHolder.set(solidStub);
  SolidSceneHooks.canCheckSignIn = (): boolean => true;
  try {
    SolidSceneHooks.needSignedIn = (): boolean => true;
    const warn1: SpyWarningScene = new SpyWarningScene();
    warn1.bindSceneHost(new NoopSceneHost());
    warn1.onAccept();
    eq('WarningScene.onAccept（即使 getAskAnalytics=true）直达 SignInScene', warn1.startedScenes[0] ?? '', 'SignInScene');
    eq('WarningScene.onAccept 记录不再显示 Warning', solidStub.showWarning, false);
    eq('WarningScene.onAccept 后关闭自身', warn1.finishCount, 1);

    SolidSceneHooks.needSignedIn = (): boolean => false;
    solidStub.selectSite = true;
    const warn2: SpyWarningScene = new SpyWarningScene();
    warn2.bindSceneHost(new NoopSceneHost());
    warn2.onAccept();
    eq('WarningScene.onAccept（已登录）直达 SelectSiteScene 而非 AnalyticsScene',
      warn2.startedScenes[0] ?? '', 'SelectSiteScene');

    solidStub.selectSite = false;
    const warn3: SpyWarningScene = new SpyWarningScene();
    warn3.bindSceneHost(new NoopSceneHost());
    warn3.onAccept();
    eq('WarningScene.onAccept（全过）直达 GalleryListScene 而非 AnalyticsScene',
      warn3.startedScenes[0] ?? '', 'GalleryListScene');
  } finally {
    SolidSceneSettingsHolder.reset();
    SolidSceneHooks.reset();
  }

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('b3-routes-and-security-gate test failed');
  }
  console.log(`✓ b3-routes-and-security-gate: ${pass} 条断言全部通过`);
}

main();
