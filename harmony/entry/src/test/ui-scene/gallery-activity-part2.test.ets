/*
 * download-sync 接手批单测：GalleryActivity Part 2（S0208）的判据层
 *
 * 钉住的语义（都是"写错也能编译、但阅读体验直接错"）：
 *   ① canFinish 只在 DATA_IN_EVENT=true 时**不**置位（跳转崩溃的修复点）
 *   ② provider 三分派各有前置条件；ACTION_VIEW 只支持 zip
 *   ③ 音量键翻页判 `RTL && !reverseVolumePage` **两个条件的合取**
 *   ④ DPAD_LEFT/RIGHT 是**绝对方向**，不随 RTL 取反（只有 PAGE_UP/DOWN、DPAD_UP/DOWN 取反）
 *   ⑤ onKeyUp 的判据与 onKeyDown **不同**：音量键只在开关开时吃掉
 *   ⑥ 滑块起始文本是 currentIndex+1（1 基），RTL 时 reverse=true；松手只在页码变化时跳页
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  GalleryActivity, GalleryActivityKeys, ProviderKind, ProviderPlan, IntentLike, IntentParseResult,
  KeyAction, KeyCode, LayoutMode, SliderState, ACTION_DIR, ACTION_EH, ACTION_VIEW,
  KEY_ACTION, KEY_FILENAME, KEY_URI, KEY_GALLERY_INFO, DATA_IN_EVENT, KEY_PAGE, KEY_CURRENT_INDEX
} from '../../main/ets/hippo/ehviewer/ui/GalleryActivity';

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

// ---------------------------------------------------------------- 常量与键集

function testConstantsAndKeys(): void {
  eq('滑块动画 150ms', GalleryActivity.SLIDER_ANIMATION_DURATION, 150);
  eq('自动隐藏 3000ms', GalleryActivity.HIDE_SLIDER_DELAY, 3000);
  eq('ACTION_DIR', ACTION_DIR, 'dir');
  eq('ACTION_EH', ACTION_EH, 'eh');
  eq('ACTION_VIEW 是系统串', ACTION_VIEW, 'android.intent.action.VIEW');
  eq('保存的 6 个键（顺序照搬）', GalleryActivity.savedKeys(),
    [KEY_ACTION, KEY_FILENAME, KEY_URI, KEY_GALLERY_INFO, KEY_PAGE, KEY_CURRENT_INDEX]);
  eq('键名逐字', [KEY_ACTION, KEY_FILENAME, KEY_URI, KEY_GALLERY_INFO, DATA_IN_EVENT, KEY_PAGE,
    KEY_CURRENT_INDEX], ['action', 'filename', 'uri', 'gallery_info', 'data_in_event', 'page',
    'current_index']);
  eq('深链键（Part 1）', [GalleryActivityKeys.KEY_GID, GalleryActivityKeys.KEY_PAGE,
    GalleryActivityKeys.KEY_SEARCH], ['gid', 'page', 'search']);
}

// ---------------------------------------------------------------- 意图解析

function testIntentParsing(): void {
  // 无 intent → 可结束
  const none: IntentParseResult = GalleryActivity.parseIntent(null);
  eq('无 intent → canFinish', none.canFinish, true);
  eq('无 intent → 无 provider', none.plan.kind, ProviderKind.NONE);

  // 普通启动（非 event）→ 可结束
  const normal: IntentParseResult = GalleryActivity.parseIntent(
    new IntentLike(ACTION_EH, null, null, true, 3, false));
  eq('普通启动 → canFinish', normal.canFinish, true);
  eq('普通启动 → 建 EH provider', normal.plan.kind, ProviderKind.EH);

  // EventBus 投递 → **不可结束**（先别 finish，等 provider 建好）
  const inEvent: IntentParseResult = GalleryActivity.parseIntent(
    new IntentLike(ACTION_EH, null, null, true, 3, true));
  eq('DATA_IN_EVENT=true → canFinish 为 false', inEvent.canFinish, false);
  eq('event 投递仍要建 provider', inEvent.plan.kind, ProviderKind.EH);
  eq('page 透传', inEvent.intent.page, 3);
}

// ---------------------------------------------------------------- provider 三分派

function testProviderPlan(): void {
  // DIR：必须有 filename
  eq('DIR + filename → DIR',
    GalleryActivity.buildProviderPlan(ACTION_DIR, '/sdcard/a', null, false).kind, ProviderKind.DIR);
  eq('DIR + 文件名带上',
    GalleryActivity.buildProviderPlan(ACTION_DIR, '/sdcard/a', null, false).filename, '/sdcard/a');
  eq('DIR + 无 filename → NONE',
    GalleryActivity.buildProviderPlan(ACTION_DIR, null, null, false).kind, ProviderKind.NONE);

  // EH：必须有 galleryInfo
  const eh: ProviderPlan = GalleryActivity.buildProviderPlan(ACTION_EH, null, null, true);
  eq('EH + galleryInfo → EH', eh.kind, ProviderKind.EH);
  eq('EH 记录 hasGalleryInfo', eh.hasGalleryInfo, true);
  eq('EH 无 galleryInfo → NONE',
    GalleryActivity.buildProviderPlan(ACTION_EH, null, null, false).kind, ProviderKind.NONE);

  // VIEW：必须有 uri（只支持 zip）
  const view: ProviderPlan = GalleryActivity.buildProviderPlan(ACTION_VIEW, null, 'content://z', false);
  eq('VIEW + uri → ARCHIVE', view.kind, ProviderKind.ARCHIVE);
  eq('VIEW 记录 uri', view.uri, 'content://z');
  eq('VIEW 无 uri → NONE',
    GalleryActivity.buildProviderPlan(ACTION_VIEW, null, null, false).kind, ProviderKind.NONE);

  // 未知 action
  eq('未知 action → NONE',
    GalleryActivity.buildProviderPlan('android.intent.action.SEND', 'f', 'u', true).kind,
    ProviderKind.NONE);
  eq('null action → NONE',
    GalleryActivity.buildProviderPlan(null, 'f', 'u', true).kind, ProviderKind.NONE);

  // EventBus：已建 provider 就不重建
  eq('已建 provider → 不处理事件', GalleryActivity.shouldHandleEvent(true), false);
  eq('未建 provider → 处理事件', GalleryActivity.shouldHandleEvent(false), true);
}

// ---------------------------------------------------------------- 音量键（RTL × 反转 的四种组合）

function testVolumeKeys(): void {
  // 开关关掉 → 音量键不管
  eq('volumePage=false → VOLUME_UP 透传',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_UP, false, false, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.PASS_THROUGH);

  // LTR + 未反转 → UP 左、DOWN 右
  eq('LTR/未反转 VOLUME_UP → 左',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_UP, true, false, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.PAGE_LEFT);
  eq('LTR/未反转 VOLUME_DOWN → 右',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_DOWN, true, false, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.PAGE_RIGHT);

  // RTL + 未反转 → 取反（UP 右、DOWN 左）—— 这是 `rtl && unReverse` 的合取
  eq('RTL/未反转 VOLUME_UP → 右',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_UP, true, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_RIGHT);
  eq('RTL/未反转 VOLUME_DOWN → 左',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_DOWN, true, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_LEFT);

  // RTL + **已反转** → 回到不取反（因为 unReverse=false）
  eq('RTL/已反转 VOLUME_UP → 左（unReverse=false）',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_UP, true, true, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_LEFT);
  eq('RTL/已反转 VOLUME_DOWN → 右',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_DOWN, true, true, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_RIGHT);

  // LTR + 反转 → 与 LTR/未反转 相同（RTL 不成立时 unReverse 不参与）
  eq('LTR/已反转 VOLUME_UP → 左',
    GalleryActivity.keyActionFor(KeyCode.VOLUME_UP, true, true, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.PAGE_LEFT);
}

// ---------------------------------------------------------------- 方向键（不对称）

function testDpadKeys(): void {
  // PAGE_UP/DPAD_UP 随 RTL 取反
  eq('LTR DPAD_UP → 左',
    GalleryActivity.keyActionFor(KeyCode.DPAD_UP, false, false, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.PAGE_LEFT);
  eq('RTL DPAD_UP → 右',
    GalleryActivity.keyActionFor(KeyCode.DPAD_UP, false, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_RIGHT);
  eq('RTL PAGE_UP → 右',
    GalleryActivity.keyActionFor(KeyCode.PAGE_UP, false, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_RIGHT);

  // PAGE_DOWN/DPAD_DOWN 随 RTL 取反
  eq('LTR DPAD_DOWN → 右',
    GalleryActivity.keyActionFor(KeyCode.DPAD_DOWN, false, false, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.PAGE_RIGHT);
  eq('RTL DPAD_DOWN → 左',
    GalleryActivity.keyActionFor(KeyCode.DPAD_DOWN, false, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_LEFT);

  // DPAD_LEFT / DPAD_RIGHT 是**绝对方向**，RTL 也不变
  eq('LTR DPAD_LEFT → 左',
    GalleryActivity.keyActionFor(KeyCode.DPAD_LEFT, false, false, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.PAGE_LEFT);
  eq('RTL DPAD_LEFT → 仍左（绝对方向）',
    GalleryActivity.keyActionFor(KeyCode.DPAD_LEFT, false, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_LEFT);
  eq('RTL DPAD_RIGHT → 仍右（绝对方向）',
    GalleryActivity.keyActionFor(KeyCode.DPAD_RIGHT, false, false, LayoutMode.RIGHT_TO_LEFT),
    KeyAction.PAGE_RIGHT);

  // 菜单键
  eq('DPAD_CENTER → 菜单',
    GalleryActivity.keyActionFor(KeyCode.DPAD_CENTER, false, false, LayoutMode.LEFT_TO_RIGHT),
    KeyAction.TAP_MENU);
  eq('SPACE → 菜单', GalleryActivity.keyActionFor(KeyCode.SPACE, false, false,
    LayoutMode.LEFT_TO_RIGHT), KeyAction.TAP_MENU);
  eq('MENU → 菜单', GalleryActivity.keyActionFor(KeyCode.MENU, false, false,
    LayoutMode.LEFT_TO_RIGHT), KeyAction.TAP_MENU);

  // 未知键
  eq('未知键 → 透传', GalleryActivity.keyActionFor(9999, false, false,
    LayoutMode.LEFT_TO_RIGHT), KeyAction.PASS_THROUGH);
}

// ---------------------------------------------------------------- 抬手判据（与按下不同）

function testKeyUp(): void {
  eq('音量键 + 开关开 → 吃掉',
    GalleryActivity.keyUpActionFor(KeyCode.VOLUME_UP, true), KeyAction.SWALLOW);
  eq('音量键 + 开关关 → 透传（要让系统调音量）',
    GalleryActivity.keyUpActionFor(KeyCode.VOLUME_UP, false), KeyAction.PASS_THROUGH);
  eq('方向键无条件吃掉',
    GalleryActivity.keyUpActionFor(KeyCode.DPAD_LEFT, false), KeyAction.SWALLOW);
  eq('翻页键无条件吃掉',
    GalleryActivity.keyUpActionFor(KeyCode.PAGE_DOWN, false), KeyAction.SWALLOW);
  eq('菜单键无条件吃掉',
    GalleryActivity.keyUpActionFor(KeyCode.MENU, false), KeyAction.SWALLOW);
  eq('空格无条件吃掉',
    GalleryActivity.keyUpActionFor(KeyCode.SPACE, false), KeyAction.SWALLOW);
  eq('未知键透传', GalleryActivity.keyUpActionFor(9999, true), KeyAction.PASS_THROUGH);
  eq('DPAD_CENTER 吃掉',
    GalleryActivity.keyUpActionFor(KeyCode.DPAD_CENTER, true), KeyAction.SWALLOW);
}

// ---------------------------------------------------------------- 滑块

function testSlider(): void {
  // 前置条件
  eq('size=0 → null', GalleryActivity.sliderState(0, 0, LayoutMode.LEFT_TO_RIGHT), null);
  eq('currentIndex<0 → null',
    GalleryActivity.sliderState(10, -1, LayoutMode.LEFT_TO_RIGHT), null);

  const ltr: SliderState | null = GalleryActivity.sliderState(20, 0, LayoutMode.LEFT_TO_RIGHT);
  eq('LTR 起始文本 = 1（1 基）', ltr === null ? null : ltr.startText, '1');
  eq('LTR 末尾文本 = 20', ltr === null ? null : ltr.endText, '20');
  eq('LTR max = size-1', ltr === null ? null : ltr.max, 19);
  eq('LTR progress = currentIndex', ltr === null ? null : ltr.progress, 0);
  eq('LTR reverse=false', ltr === null ? null : ltr.reverse, false);

  const rtl: SliderState | null = GalleryActivity.sliderState(20, 5, LayoutMode.RIGHT_TO_LEFT);
  eq('RTL 起始文本 = 6', rtl === null ? null : rtl.startText, '6');
  eq('RTL reverse=true', rtl === null ? null : rtl.reverse, true);

  // 拖动：只有 fromUser 才刷文本
  eq('拖动中（fromUser）→ progress+1',
    GalleryActivity.sliderTextWhileDragging(7, true), '8');
  eq('程序更新（非 fromUser）→ 不刷', GalleryActivity.sliderTextWhileDragging(7, false), null);

  // 松手：只有页码变化才跳
  eq('松手页码变了 → 跳页', GalleryActivity.shouldJumpOnRelease(9, 3), true);
  eq('松手页码没变 → 不跳', GalleryActivity.shouldJumpOnRelease(3, 3), false);
  eq('松手后重排隐藏延迟', GalleryActivity.hideDelayAfterRelease(), 3000);
}

// ---------------------------------------------------------------- 自动翻页

function testAutoTransfer(): void {
  eq('关 → 开', GalleryActivity.toggleAutoTransfer(false), true);
  eq('开 → 关', GalleryActivity.toggleAutoTransfer(true), false);
  eq('未开启时显示"播放"图标', GalleryActivity.autoTransferIcon(false), 'ic_start_play_24');
  eq('已开启时显示"暂停"图标', GalleryActivity.autoTransferIcon(true), 'ic_pause_circle');
}

// ---------------------------------------------------------------- 实例层：注入后算 provider

function testInstanceProvider(): void {
  const act: GalleryActivity = new GalleryActivity();
  eq('未注入 → NONE', act.providerPlanFor(ACTION_VIEW).kind, ProviderKind.NONE);

  act.setIntentFields('/sdcard/dir', null, false);
  eq('注入 filename + DIR action → DIR', act.providerPlanFor(ACTION_DIR).kind, ProviderKind.DIR);

  act.setIntentFields(null, 'content://z', false);
  eq('注入 uri + VIEW action → ARCHIVE', act.providerPlanFor(ACTION_VIEW).kind,
    ProviderKind.ARCHIVE);

  act.setIntentFields(null, null, true);
  eq('注入 galleryInfo + EH action → EH', act.providerPlanFor(ACTION_EH).kind, ProviderKind.EH);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testConstantsAndKeys();
  testIntentParsing();
  testProviderPlan();
  testVolumeKeys();
  testDpadKeys();
  testKeyUp();
  testSlider();
  testAutoTransfer();
  testInstanceProvider();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync gallery activity part2 test failed');
  }
  console.log(`✓ download-sync 阅读器 Part2 批: ${pass} 条断言全部通过`);
}

main();
