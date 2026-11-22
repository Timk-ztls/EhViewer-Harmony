/*
 * native-image 接手批单测：ToolbarScene（S0264）+ MyTagsActivity（S0213）+ SetSecurityActivity（S0269）
 *
 * 断言重点：
 *   ① ★`mTempTitle` 延迟设置：toolbar 未挂时 setTitle 只暂存，onViewCreated 补设并**清空暂存**
 *   ② ★`contentView == null` → attach 失败且 **toolbar 保持 null**（后续 setTitle 仍走暂存）
 *   ③ `getMenuResId() == 0` 时**不 inflate 菜单、不调 onMenuCreated**；两个监听仍无条件挂
 *   ④ `onDestroyView` 置 null 但**不清暂存标题**（上游也没清）
 *   ⑤ `setTitleRes` 先解析字符串再转调（解析发生在**调用时**）
 *   ⑥ ★`getCellSize() <= 1` → security = ""（"没有有效手势" = 清空安全码）
 *   ⑦ ★指纹启用是**三条与**：可见 && 勾选 && security 非空
 *   ⑧ `finish()` 在 if **之外**（控件不全也退出）
 *   ⑨ ★cookie 顺序：flush → removeAll → removeSession → setCookie（先删再灌）
 *   ⑩ ★URL 白名单是**完全相等**（不是同域/startsWith）
 *   ⑪ 整段 onCreate 的 catch 降级：logError + 弹框（正/取消都 finish）
 *   ⑫ onPageStarted/Finished 驱动页面级进度
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter toolbar-tags-security
 */

import {
  ToolbarScene, ToolbarLogic, ToolbarModel, ContentViewToken,
  NO_MENU, LAYOUT_SCENE_TOOLBAR, ID_CONTENT_PANEL
} from '../../main/ets/hippo/ehviewer/ui/scene/ToolbarScene';
import {
  MyTagsActivity, MyTagsHost, MyTagsInitResult, WebViewUnavailableSpec,
  STR_WEBVIEW_UNAVAILABLE_TITLE, STR_WEBVIEW_UNAVAILABLE_MESSAGE, DRAWABLE_BACK, LOG_TAG
} from '../../main/ets/hippo/ehviewer/ui/MyTagsActivity';
import {
  SetSecurityActivity, SecurityHost, SecuritySettings, PatternViewPort,
  DISPLAY_MODE_CORRECT, LAYOUT_ACTIVITY_SET_SECURITY
} from '../../main/ets/hippo/ehviewer/ui/SetSecurityActivity';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
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
    fails.push(`${name}\n    条件为 false`);
  }
}

// ---------------------------------------------------------------- S0264
/** 最小可实例化子类（ToolbarScene 是抽象类，但本仓没有抽象方法 → 直接 new 也可） */
class TestToolbarScene extends ToolbarScene {
  content: ContentViewToken | null = null;
  menuResId: number = NO_MENU;
  menuCreatedCalls: number = 0;

  onCreateView3(): ContentViewToken | null {
    return this.content;
  }

  getMenuResId(): number {
    return this.menuResId;
  }

  onMenuCreated(): void {
    this.menuCreatedCalls++;
  }

  /** `SceneFragment` 的唯一抽象成员（注册键） */
  getSceneName(): string {
    return 'TestToolbarScene';
  }
}

function testToolbarScene(): void {
  eq('布局与两个 id', [LAYOUT_SCENE_TOOLBAR, ID_CONTENT_PANEL], ['scene_toolbar', 'content_panel']);
  eq('NO_MENU = 0', NO_MENU, 0);

  // ---------- ① 标题延迟设置 ----------
  const s1: TestToolbarScene = new TestToolbarScene();
  s1.setTitle('before-attach');
  eq('★未挂 toolbar 时 setTitle 只暂存', s1.logic.getTempTitle(), 'before-attach');
  eq('此时没有实际标题', s1.logic.getToolbar(), null);
  // 挂上视图（有内容）
  s1.content = new ContentViewToken('content');
  eq('attach 成功', s1.onCreateView2(), true);
  eq('toolbar 已存在', s1.logic.hasToolbar(), true);
  s1.onViewCreated();
  eq('★onViewCreated 补设标题', (s1.logic.getToolbar() as ToolbarModel).title, 'before-attach');
  eq('★暂存被清空', s1.logic.getTempTitle(), null);

  // 挂上后再 setTitle → 直接生效
  s1.setTitle('after-attach');
  eq('已挂时 setTitle 立即生效', (s1.logic.getToolbar() as ToolbarModel).title, 'after-attach');
  eq('不再进暂存', s1.logic.getTempTitle(), null);

  // ---------- ② contentView == null ----------
  const s2: TestToolbarScene = new TestToolbarScene();
  s2.content = null;
  eq('★内容为 null → attach 失败', s2.onCreateView2(), false);
  eq('★toolbar 保持 null', s2.logic.hasToolbar(), false);
  s2.setTitle('t2');
  eq('失败后 setTitle 仍走暂存', s2.logic.getTempTitle(), 't2');
  s2.setNavigationIcon('icon');
  eq('无 toolbar 时 setNavigationIcon 静默无效', s2.logic.getToolbar(), null);

  // ---------- ③ 菜单：0 不 inflate ----------
  const s3: TestToolbarScene = new TestToolbarScene();
  s3.content = new ContentViewToken('c');
  s3.menuResId = NO_MENU;
  s3.onCreateView2();
  s3.onViewCreated();
  const tb3: ToolbarModel = s3.logic.getToolbar() as ToolbarModel;
  eq('★无菜单时不 inflate', tb3.inflatedMenu, null);
  eq('★无菜单时不挂菜单监听', tb3.menuListenerAttached, false);
  eq('★两个监听仍无条件挂（导航）', tb3.navListenerAttached, true);
  eq('★两个监听仍无条件挂（整体点击）', tb3.clickListenerAttached, true);

  // 有菜单
  const s4: TestToolbarScene = new TestToolbarScene();
  s4.content = new ContentViewToken('c');
  s4.menuResId = 12345;
  s4.onCreateView2();
  s4.onViewCreated();
  const tb4: ToolbarModel = s4.logic.getToolbar() as ToolbarModel;
  eq('有菜单 → inflated', tb4.inflatedMenu, '12345');
  eq('有菜单 → 挂监听', tb4.menuListenerAttached, true);
  eq('有菜单 → 回调 onMenuCreated 一次', s4.menuCreatedCalls, 1);

  // ---------- ④ onDestroyView 不清暂存 ----------
  const s5: TestToolbarScene = new TestToolbarScene();
  s5.content = new ContentViewToken('c');
  s5.onCreateView2();
  s5.setTitle('kept');
  s5.onDestroyView();
  eq('销毁后 toolbar 为 null', s5.logic.hasToolbar(), false);
  eq('★销毁不清暂存标题（上游也没清）', s5.logic.getTempTitle(), null);   // 因为已实设过

  // ---------- ⑤ setTitleRes 先解析 ----------
  const s6: TestToolbarScene = new TestToolbarScene((key: string): string => {
    return 'R:' + key;
  });
  s6.content = new ContentViewToken('c');
  s6.onCreateView2();
  s6.setTitleRes('app.string.gallery_info');
  eq('★setTitleRes 走解析器', (s6.logic.getToolbar() as ToolbarModel).title, 'R:app.string.gallery_info');
  // 未挂时 setTitleRes 也先进暂存（解析后）
  const s7: TestToolbarScene = new TestToolbarScene((key: string): string => {
    return 'R:' + key;
  });
  s7.setTitleRes('k');
  eq('未挂时 setTitleRes 解析后暂存', s7.logic.getTempTitle(), 'R:k');

  // ---------- 默认实现 ----------
  const s8: TestToolbarScene = new TestToolbarScene();
  eq('getContentIndex = 0（addView(contentView, 0)）', s8.getContentIndex(), 0);
  eq('onMenuItemClick 默认 false', s8.onMenuItemClick('x'), false);
  // 空实现可安全调用
  s8.onClickListener();
  s8.onNavigationClick();
  s8.onMenuCreated();
  ok('空实现方法可安全调用', true);
}

// ---------------------------------------------------------------- S0269
class FakePatternView implements PatternViewPort {
  cellSize: number = 3;
  patternString: string = '0124';
  setPatternCalls: string[] = [];

  setPattern(mode: number, cells: Object | null): void {
    this.setPatternCalls.push(`${mode}:${cells === null ? 'null' : 'cells'}`);
  }
  getCellSize(): number {
    return this.cellSize;
  }
  getPatternString(): string {
    return this.patternString;
  }
}

class FakeSecurityHost implements SecurityHost {
  fingerprintEnrolled: boolean = false;
  fpVisible: boolean = false;
  fpChecked: boolean = false;
  pv: PatternViewPort | null = new FakePatternView();
  finishCalls: number = 0;
  navIcon: string = '';
  throwOnFingerprint: boolean = false;

  hasEnrolledFingerprints(): boolean {
    if (this.throwOnFingerprint) {
      throw new Error('device boom');
    }
    return this.fingerprintEnrolled;
  }
  setFingerprintVisible(visible: boolean): void { this.fpVisible = visible; }
  setFingerprintChecked(checked: boolean): void { this.fpChecked = checked; }
  isFingerprintVisible(): boolean { return this.fpVisible; }
  isFingerprintChecked(): boolean { return this.fpChecked; }
  getPatternView(): PatternViewPort | null { return this.pv; }
  setNavigationIcon(icon: string): void { this.navIcon = icon; }
  finish(): void { this.finishCalls++; }
}

class FakeSecuritySettings implements SecuritySettings {
  security: string | null = null;
  enableFingerprint: boolean = false;
  putSecurityCalls: string[] = [];
  putFingerprintCalls: boolean[] = [];

  getSecurity(): string | null { return this.security; }
  putSecurity(s: string): void {
    this.putSecurityCalls.push(s);
    this.security = s;
  }
  getEnableFingerprint(): boolean { return this.enableFingerprint; }
  putEnableFingerprint(v: boolean): void {
    this.putFingerprintCalls.push(v);
    this.enableFingerprint = v;
  }
}

function testSetSecurityActivity(): void {
  eq('布局名', LAYOUT_ACTIVITY_SET_SECURITY, 'activity_set_security');
  eq('DisplayMode.Correct 常量', DISPLAY_MODE_CORRECT, 2);

  // ---------- 无历史安全码：不回显 ----------
  const h1: FakeSecurityHost = new FakeSecurityHost();
  const st1: FakeSecuritySettings = new FakeSecuritySettings();
  const a1: SetSecurityActivity = new SetSecurityActivity(h1, st1);
  eq('无历史安全码 → 不回显', a1.onCreate(), false);
  eq('设置了返回图标', h1.navIcon, DRAWABLE_BACK);
  eq('patternView.setPattern 未被调用', (h1.pv as FakePatternView).setPatternCalls, []);

  // ---------- 有历史安全码：回显（Correct 模式） ----------
  const h2: FakeSecurityHost = new FakeSecurityHost();
  const st2: FakeSecuritySettings = new FakeSecuritySettings();
  // ★ `LockPatternUtils.stringToPattern` 的串是**字符码 0..8**（不是数字字符 "0".."8"）：
  //   每个 char 的 charCode 拆成 row=floor(b/3), col=b%3；传 "0124" 会抛 row must be in range 0-2
  st2.security = String.fromCharCode(0, 1, 2, 4);
  const a2: SetSecurityActivity = new SetSecurityActivity(h2, st2);
  eq('有历史安全码 → 回显', a2.onCreate(), true);
  eq('★回显用 Correct 模式（2）', (h2.pv as FakePatternView).setPatternCalls.length, 1);
  ok('回显参数含模式 2', (h2.pv as FakePatternView).setPatternCalls[0].indexOf('2:') === 0);

  // ---------- 指纹：已录入才显示 ----------
  const h3: FakeSecurityHost = new FakeSecurityHost();
  const st3: FakeSecuritySettings = new FakeSecuritySettings();
  st3.enableFingerprint = true;
  const a3: SetSecurityActivity = new SetSecurityActivity(h3, st3);
  a3.onCreate();
  eq('未录入指纹 → 不显示', h3.fpVisible, false);
  const h4: FakeSecurityHost = new FakeSecurityHost();
  h4.fingerprintEnrolled = true;
  const st4: FakeSecuritySettings = new FakeSecuritySettings();
  st4.enableFingerprint = true;
  const a4: SetSecurityActivity = new SetSecurityActivity(h4, st4);
  a4.onCreate();
  eq('已录入 → 显示指纹区', h4.fpVisible, true);
  eq('按设置勾选', h4.fpChecked, true);

  // ---------- ⑥ getCellSize <= 1 → 清空 ----------
  const h5: FakeSecurityHost = new FakeSecurityHost();
  const pv5: FakePatternView = h5.pv as FakePatternView;
  pv5.cellSize = 1;
  const st5: FakeSecuritySettings = new FakeSecuritySettings();
  st5.security = String.fromCharCode(0, 1);
  const a5: SetSecurityActivity = new SetSecurityActivity(h5, st5);
  a5.onCreate();
  const written5: string | null = a5.onSet();
  eq('★cellSize=1 → security 写成空串', written5, '');
  eq('写了 putSecurity("")', st5.putSecurityCalls, ['']);
  eq('无条件 finish', h5.finishCalls, 1);

  const h6: FakeSecurityHost = new FakeSecurityHost();
  const pv6: FakePatternView = h6.pv as FakePatternView;
  pv6.cellSize = 3;
  pv6.patternString = String.fromCharCode(0, 1, 2, 4, 6, 7, 8);
  const st6: FakeSecuritySettings = new FakeSecuritySettings();
  const a6: SetSecurityActivity = new SetSecurityActivity(h6, st6);
  a6.onCreate();
  eq('cellSize>1 → 写入手势串', a6.onSet(), String.fromCharCode(0, 1, 2, 4, 6, 7, 8));
  eq('putSecurity 收到手势串', st6.putSecurityCalls, [String.fromCharCode(0, 1, 2, 4, 6, 7, 8)]);

  // ---------- ⑦ 指纹三条与 ----------
  // 可见 && 勾选 && 非空 → true
  const h7: FakeSecurityHost = new FakeSecurityHost();
  h7.fingerprintEnrolled = true;
  const pv7: FakePatternView = h7.pv as FakePatternView;
  pv7.cellSize = 3;
  const st7: FakeSecuritySettings = new FakeSecuritySettings();
  const a7: SetSecurityActivity = new SetSecurityActivity(h7, st7);
  a7.onCreate();          // 让 fpVisible = true
  h7.fpChecked = true;
  a7.onSet();
  eq('★可见+勾选+非空 → 启用指纹', st7.putFingerprintCalls, [true]);
  // 安全码为空 → 即使可见且勾选也 false
  const h8: FakeSecurityHost = new FakeSecurityHost();
  h8.fingerprintEnrolled = true;
  const pv8: FakePatternView = h8.pv as FakePatternView;
  pv8.cellSize = 0;       // 空手势
  const st8: FakeSecuritySettings = new FakeSecuritySettings();
  const a8: SetSecurityActivity = new SetSecurityActivity(h8, st8);
  a8.onCreate();
  h8.fpChecked = true;
  a8.onSet();
  eq('★安全码为空 → 强制关指纹', st8.putFingerprintCalls, [false]);
  // 指纹不可见 → false
  const h9: FakeSecurityHost = new FakeSecurityHost();
  h9.fingerprintEnrolled = false;
  const st9: FakeSecuritySettings = new FakeSecuritySettings();
  const a9: SetSecurityActivity = new SetSecurityActivity(h9, st9);
  a9.onCreate();
  h9.fpChecked = true;
  a9.onSet();
  eq('指纹区不可见 → 不启用', st9.putFingerprintCalls, [false]);

  // ---------- ⑧ 控件不全也 finish ----------
  const h10: FakeSecurityHost = new FakeSecurityHost();
  h10.pv = null;
  const st10: FakeSecuritySettings = new FakeSecuritySettings();
  const a10: SetSecurityActivity = new SetSecurityActivity(h10, st10);
  a10.onCreate();
  eq('无 patternView → 不写设置', a10.onSet(), null);
  eq('★但仍 finish', h10.finishCalls, 1);
  eq('未写 security', st10.putSecurityCalls, []);

  // ---------- 指纹探测抛异常 → false ----------
  const h11: FakeSecurityHost = new FakeSecurityHost();
  h11.throwOnFingerprint = true;
  const a11: SetSecurityActivity = new SetSecurityActivity(h11, new FakeSecuritySettings());
  eq('★硬件探测抛错 → 吞掉返回 false', a11.hasEnrolledFingerprints(), false);
  a11.onCreate();
  eq('抛错时不显示指纹区', h11.fpVisible, false);

  // ---------- 取消 / 导航 ----------
  const h12: FakeSecurityHost = new FakeSecurityHost();
  const a12: SetSecurityActivity = new SetSecurityActivity(h12, new FakeSecuritySettings());
  a12.onCreate();
  a12.onCancel();
  eq('取消 → finish', h12.finishCalls, 1);
  eq('home 返回 true', a12.onOptionsItemSelected('android.R.id.home'), true);
  eq('home → finish', h12.finishCalls, 2);
  eq('其它菜单 false', a12.onOptionsItemSelected('x'), false);
  a12.onDestroy();
  ok('onDestroy 可安全调用', true);
}

// ---------------------------------------------------------------- S0213
class FakeMyTagsHost implements MyTagsHost {
  calls: string[] = [];
  cookies: string[] = ['a=1', 'b=2'];
  url: string = 'https://TARGET/my_tags';
  progress: boolean[] = [];
  finishCalls: number = 0;
  logs: string[] = [];
  dialogs: WebViewUnavailableSpec[] = [];
  navIcon: string = '';
  jsEnabled: boolean = false;
  dialogsEnabled: boolean = false;
  loaded: string[] = [];
  throwOnRemove: boolean = false;

  cookieFlush(): void { this.calls.push('flush'); }
  cookieRemoveAll(): void {
    this.calls.push('removeAll');
    if (this.throwOnRemove) {
      throw new Error('cookie boom');
    }
  }
  cookieRemoveSession(): void { this.calls.push('removeSession'); }
  cookieSet(url: string, cookie: string): void { this.calls.push('set:' + cookie); }
  getCookiesFor(url: string): string[] { return this.cookies; }
  getMyTagsUrl(): string { return this.url; }
  setJavaScriptEnabled(enabled: boolean): void { this.jsEnabled = enabled; }
  enableDialogs(): void { this.dialogsEnabled = true; }
  loadUrl(url: string): void { this.loaded.push(url); }
  setProgressVisible(visible: boolean): void { this.progress.push(visible); }
  setNavigationIcon(icon: string): void { this.navIcon = icon; }
  finish(): void { this.finishCalls++; }
  logError(msg: string): void { this.logs.push(msg); }
  showUnavailableDialog(spec: WebViewUnavailableSpec): void { this.dialogs.push(spec); }
}

function testMyTagsActivity(): void {
  eq('两个字符串键', [STR_WEBVIEW_UNAVAILABLE_TITLE, STR_WEBVIEW_UNAVAILABLE_MESSAGE],
    ['app.string.webview_unavailable_title', 'app.string.webview_unavailable_message']);
  eq('日志标签', LOG_TAG, 'MyTagsActivity');

  // ---------- ⑨ cookie 顺序 ----------
  const h1: FakeMyTagsHost = new FakeMyTagsHost();
  const a1: MyTagsActivity = new MyTagsActivity(h1);
  const r1: MyTagsInitResult = a1.onCreate();
  eq('★调用顺序：flush → removeAll → removeSession → set×2',
    h1.calls, ['flush', 'removeAll', 'removeSession', 'set:a=1', 'set:b=2']);
  eq('初始化成功', r1.ok, true);
  eq('灌了 2 条 cookie', r1.cookiesSet, 2);
  eq('JS 已开启', h1.jsEnabled, true);
  eq('对话框已启用', h1.dialogsEnabled, true);
  eq('设置了返回图标', h1.navIcon, DRAWABLE_BACK);
  eq('加载了 my_tags URL', h1.loaded, ['https://TARGET/my_tags']);
  eq('URL 记录正确', a1.getUrl(), 'https://TARGET/my_tags');

  // ---------- ⑩ URL 白名单完全相等 ----------
  eq('同 URL → 不拦截（false）', a1.shouldOverrideUrlLoading('https://TARGET/my_tags'), false);
  eq('★其它 URL → 拦截', a1.shouldOverrideUrlLoading('https://TARGET/other'), true);
  eq('★同域子路径也拦截', a1.shouldOverrideUrlLoading('https://TARGET/my_tags/2'), true);
  eq('★前缀相同也拦截', a1.shouldOverrideUrlLoading('https://TARGET/my_tag'), true);

  // ---------- ⑫ 进度 ----------
  a1.onPageStarted();
  a1.onPageFinished();
  eq('进度先可见后隐藏', h1.progress, [true, false]);

  // ---------- ⑪ catch 降级 ----------
  const h2: FakeMyTagsHost = new FakeMyTagsHost();
  h2.throwOnRemove = true;
  const a2: MyTagsActivity = new MyTagsActivity(h2);
  const r2: MyTagsInitResult = a2.onCreate();
  eq('★cookies 清空抛错 → 走降级', r2.ok, false);
  eq('记了日志', h2.logs.length, 1);
  eq('弹了对话框', h2.dialogs.length, 1);
  eq('未加载 URL', h2.loaded, []);
  eq('未标记已创建', a2.isCreated(), false);
  ok('对话框是"WebView 不可用"', h2.dialogs[0].title === STR_WEBVIEW_UNAVAILABLE_TITLE);
  // 正按钮与取消都 finish
  a2.onUnavailableDialogCancel();
  eq('取消 → finish', h2.finishCalls, 1);
  a2.onUnavailableDialogConfirm();
  eq('确认 → finish', h2.finishCalls, 2);

  // ---------- 导航 ----------
  eq('home 返回 true', a1.onOptionsItemSelected('android.R.id.home'), true);
  eq('home → finish', h1.finishCalls, 1);
  eq('其它菜单 false', a1.onOptionsItemSelected('x'), false);
}

function main(): void {
  testToolbarScene();
  testSetSecurityActivity();
  testMyTagsActivity();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('toolbar/tags/security test failed');
  }
  console.log(`✓ ToolbarScene + 我的标签 + 安全设置批: ${pass} 条断言全部通过`);
}

main();



