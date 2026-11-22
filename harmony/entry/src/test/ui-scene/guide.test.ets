/*
 * native-image：S0226 DownloadGuideHelper（132 行）单测
 *
 * 断言重点：
 *   ① ★两步**串联**：第一步 hide → 关开关 → 立刻进第二步（不等下次进入）
 *   ② ★第二步用的是 `puttGuideDownloadLabels`（**三个 t**，上游 typo）—— 不能与两 t 合并
 *   ③ ★第二步 hide 后 `openDrawer(RIGHT)`
 *   ④ `guide()` 走"等布局"路径 vs 直接进第二步的两条分叉
 *   ⑤ 布局回调里**再判一次**开关 + **主动移除监听**
 *   ⑥ 第一步的**四条前置**全都降级到第二步（不是放弃）
 *   ⑦ 第二步的前置失败是**真 return**
 *   ⑧ `isShowing` 是 getter（destroy 后立刻 false）
 *   ⑨ `destroy()` 不关开关
 *   ⑩ 第二步 target = (屏宽, 屏高/3)
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter guide
 */

import {
  DownloadGuideHelper, GuideHost, GuideSettings, GuideStep,
  STR_THUMB_TITLE, STR_THUMB_TEXT, STR_LABELS_TITLE, STR_LABELS_TEXT,
  STEP_THUMB, STEP_POINT, DRAWER_GRAVITY_RIGHT, STYLE_GUIDE, LAYOUT_BUTTON_GUIDE
} from '../../main/ets/hippo/ehviewer/ui/scene/download/part/DownloadGuideHelper';

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

class FakeGuideSettings implements GuideSettings {
  thumb: boolean = false;
  labels: boolean = false;
  putThumbCalls: boolean[] = [];
  /** ★ 三 t 的调用记录（与两 t 分开记，见「关键行为」1） */
  puttLabelsCalls: boolean[] = [];

  getGuideDownloadThumb(): boolean { return this.thumb; }
  putGuideDownloadThumb(v: boolean): void {
    this.putThumbCalls.push(v);
    this.thumb = v;
  }
  getGuideDownloadLabels(): boolean { return this.labels; }
  puttGuideDownloadLabels(v: boolean): void {
    this.puttLabelsCalls.push(v);
    this.labels = v;
  }
}

class FakeGuideHost implements GuideHost {
  activity: boolean = true;
  recycler: boolean = true;
  layoutManager: boolean = true;
  firstPosition: number = 0;
  anchor: Object | null = null;
  screenWidth: number = 1080;
  screenHeight: number = 2340;
  layoutCallback: (() => void) | null = null;
  layoutListenerCalls: number = 0;
  removedListeners: number = 0;
  openDrawerCalls: number[] = [];
  shown: GuideStep[] = [];
  removeStepCalls: number = 0;

  hasActivity(): boolean { return this.activity; }
  hasRecyclerView(): boolean { return this.recycler; }
  hasLayoutManager(): boolean { return this.layoutManager; }
  whenLaidOut(callback: () => void): void {
    this.layoutListenerCalls++;
    this.layoutCallback = callback;
  }
  removeLayoutListener(): void { this.removedListeners++; }
  findFirstCompletelyVisiblePosition(): number { return this.firstPosition; }
  getItemThumbAnchor(position: number): Object | null { return this.anchor; }
  getScreenWidth(): number { return this.screenWidth; }
  getScreenHeight(): number { return this.screenHeight; }
  openDrawer(gravity: number): void { this.openDrawerCalls.push(gravity); }
  showStep(step: GuideStep): void { this.shown.push(step); }
  removeStepView(): void { this.removeStepCalls++; }
  resolveString(key: string): string { return key; }

  /** 模拟"布局完成" */
  fireLayout(): void {
    if (this.layoutCallback !== null) {
      this.layoutCallback();
    }
  }
}


function testDownloadGuideHelper(): void {
  // ---------- 常量 ----------
  eq('四个字符串键', [STR_THUMB_TITLE, STR_THUMB_TEXT, STR_LABELS_TITLE, STR_LABELS_TEXT],
    ['app.string.guide_download_thumb_title', 'app.string.guide_download_thumb_text',
      'app.string.guide_download_labels_title', 'app.string.guide_download_labels_text']);
  eq('样式与按钮布局', [STYLE_GUIDE, LAYOUT_BUTTON_GUIDE], ['Guide', 'button_guide']);
  eq('抽屉方向 = Gravity.RIGHT(5)', DRAWER_GRAVITY_RIGHT, 5);

  // ---------- ④ guide() 两条分叉：走"等布局" ----------
  const h1: FakeGuideHost = new FakeGuideHost();
  const st1: FakeGuideSettings = new FakeGuideSettings();
  st1.thumb = true;
  st1.labels = true;
  h1.anchor = new Object();
  const g1: DownloadGuideHelper = new DownloadGuideHelper(h1, st1);
  g1.guide();
  eq('★缩略图开关开 + 有 recycler → 注册布局监听', h1.layoutListenerCalls, 1);
  eq('此刻还没弹任何步骤', h1.shown.length, 0);
  // 布局完成 → 进第一步
  h1.fireLayout();
  eq('布局完成后弹第一步', h1.shown.length, 1);
  eq('第一步类型 = thumb', h1.shown[0].kind, STEP_THUMB);
  eq('第一步标题/文案', [h1.shown[0].titleKey, h1.shown[0].textKey], [STR_THUMB_TITLE, STR_THUMB_TEXT]);
  eq('★blockAllTouches = true', h1.shown[0].blockAllTouches, true);
  eq('★布局回调里主动移除监听', h1.removedListeners, 1);
  eq('isShowing = true', g1.isShowing(), true);

  // ---------- ⑤ 回调里再判一次开关 ----------
  const h2: FakeGuideHost = new FakeGuideHost();
  const st2: FakeGuideSettings = new FakeGuideSettings();
  st2.thumb = true;
  st2.labels = true;
  h2.anchor = new Object();
  const g2: DownloadGuideHelper = new DownloadGuideHelper(h2, st2);
  g2.guide();
  st2.thumb = false;   // 布局完成前被关掉
  h2.fireLayout();
  eq('★回调里再判开关 → 不弹第一步', h2.shown.filter((s: GuideStep): boolean => s.kind === STEP_THUMB).length, 0);
  eq('但仍移除监听', h2.removedListeners, 1);

  // ---------- 直接进第二步（开关关） ----------
  const h3: FakeGuideHost = new FakeGuideHost();
  const st3: FakeGuideSettings = new FakeGuideSettings();
  st3.thumb = false;
  st3.labels = true;
  const g3: DownloadGuideHelper = new DownloadGuideHelper(h3, st3);
  g3.guide();
  eq('缩略图开关关 → 不注册监听', h3.layoutListenerCalls, 0);
  eq('直接弹标签引导', h3.shown.length, 1);
  eq('类型 = point', h3.shown[0].kind, STEP_POINT);

  // 无 recycler 也直接进第二步
  const h4: FakeGuideHost = new FakeGuideHost();
  const st4: FakeGuideSettings = new FakeGuideSettings();
  st4.thumb = true;
  st4.labels = true;
  h4.recycler = false;
  const g4: DownloadGuideHelper = new DownloadGuideHelper(h4, st4);
  g4.guide();
  eq('★无 recycler → 不注册监听', h4.layoutListenerCalls, 0);
  eq('直接弹标签引导', h4.shown[0].kind, STEP_POINT);

  // ---------- ⑩ 第二步坐标 = (屏宽, 屏高/3) ----------
  eq('★第二步 x = 屏宽', h4.shown[0].x, 1080);
  eq('★第二步 y = floor(屏高/3)', h4.shown[0].y, 780);

  // ---------- ① 两步串联 ----------
  const h5: FakeGuideHost = new FakeGuideHost();
  const st5: FakeGuideSettings = new FakeGuideSettings();
  st5.thumb = true;
  st5.labels = true;
  h5.anchor = new Object();
  const g5: DownloadGuideHelper = new DownloadGuideHelper(h5, st5);
  g5.guide();
  h5.fireLayout();
  eq('已弹第一步', h5.shown.length, 1);
  // 用户关掉第一步
  g5.onThumbStepHidden();
  eq('★第一步关闭 → 关掉缩略图开关', st5.putThumbCalls, [false]);
  eq('★第一步关闭 → 移除视图', h5.removeStepCalls, 1);
  eq('★第一步关闭 → **立刻**弹第二步（串联）', h5.shown.length, 2);
  eq('第二次是 point', h5.shown[1].kind, STEP_POINT);

  // ---------- ② 第二步用三 t ----------
  g5.onLabelsStepHidden();
  eq('★第二步关闭 → 调 puttGuideDownloadLabels（三 t）', st5.puttLabelsCalls, [false]);
  eq('★第二步关闭 → 移除视图', h5.removeStepCalls, 2);
  eq('★第二步关闭 → openDrawer(RIGHT)', h5.openDrawerCalls, [DRAWER_GRAVITY_RIGHT]);
  eq('isShowing = false', g5.isShowing(), false);

  // ---------- ⑥ 第一步四条前置全降级 ----------
  // ①无 activity
  const h6: FakeGuideHost = new FakeGuideHost();
  const st6: FakeGuideSettings = new FakeGuideSettings();
  st6.thumb = true;
  st6.labels = true;
  h6.activity = false;
  h6.anchor = new Object();
  const g6: DownloadGuideHelper = new DownloadGuideHelper(h6, st6);
  eq('无 activity → 第一步返回 false', g6.guideDownloadThumb(), false);
  // ★ 断言修正：降级到 `guideDownloadLabels()` 后，**那一层自己也要 activity** ——
  //   所以"无 activity"时两步都弹不出来（不是"降级成功"）。我第一版在这里想当然写了 shown[0]。
  //   （又一次"前置条件":降级目标分支也有它自己的前置）
  eq('★无 activity → 第二步也弹不出（降级目标同样需要 activity）', h6.shown.length, 0);
  // ②无 layoutManager
  const h7: FakeGuideHost = new FakeGuideHost();
  const st7: FakeGuideSettings = new FakeGuideSettings();
  st7.thumb = true;
  st7.labels = true;
  h7.layoutManager = false;
  h7.anchor = new Object();
  const g7: DownloadGuideHelper = new DownloadGuideHelper(h7, st7);
  eq('无 layoutManager → false', g7.guideDownloadThumb(), false);
  eq('降级弹第二步', h7.shown.length, 1);
  // ③position < 0
  const h8: FakeGuideHost = new FakeGuideHost();
  const st8: FakeGuideSettings = new FakeGuideSettings();
  st8.thumb = true;
  st8.labels = true;
  h8.firstPosition = -1;
  h8.anchor = new Object();
  const g8: DownloadGuideHelper = new DownloadGuideHelper(h8, st8);
  eq('★position<0 → false', g8.guideDownloadThumb(), false);
  eq('降级弹第二步', h8.shown.length, 1);
  // ④holder 取不到
  const h9: FakeGuideHost = new FakeGuideHost();
  const st9: FakeGuideSettings = new FakeGuideSettings();
  st9.thumb = true;
  st9.labels = true;
  h9.anchor = null;
  const g9: DownloadGuideHelper = new DownloadGuideHelper(h9, st9);
  eq('★holder null → false', g9.guideDownloadThumb(), false);
  eq('降级弹第二步', h9.shown.length, 1);

  // ---------- ⑦ 第二步前置失败是真 return ----------
  const h10: FakeGuideHost = new FakeGuideHost();
  const st10: FakeGuideSettings = new FakeGuideSettings();
  st10.labels = false;
  const g10: DownloadGuideHelper = new DownloadGuideHelper(h10, st10);
  eq('★标签开关关 → 第二步返回 false', g10.guideDownloadLabels(), false);
  eq('不弹任何步骤', h10.shown, []);
  const h11: FakeGuideHost = new FakeGuideHost();
  const st11: FakeGuideSettings = new FakeGuideSettings();
  st11.labels = true;
  h11.activity = false;
  const g11: DownloadGuideHelper = new DownloadGuideHelper(h11, st11);
  eq('无 activity → 第二步 false', g11.guideDownloadLabels(), false);
  eq('不弹任何步骤', h11.shown, []);

  // ---------- ⑧⑨ destroy ----------
  const h12: FakeGuideHost = new FakeGuideHost();
  const st12: FakeGuideSettings = new FakeGuideSettings();
  st12.labels = true;
  const g12: DownloadGuideHelper = new DownloadGuideHelper(h12, st12);
  g12.guideDownloadLabels();
  eq('弹出后 isShowing', g12.isShowing(), true);
  g12.destroy();
  eq('★destroy 后 isShowing = false', g12.isShowing(), false);
  eq('★destroy 不关开关', st12.puttLabelsCalls, []);
  eq('destroy 移除视图', h12.removeStepCalls, 1);
  // 未显示时 destroy 不做事
  const h13: FakeGuideHost = new FakeGuideHost();
  const g13: DownloadGuideHelper = new DownloadGuideHelper(h13, new FakeGuideSettings());
  g13.destroy();
  eq('未显示时 destroy 不调 removeStepView', h13.removeStepCalls, 0);

  // ---------- 第一步步骤数据 ----------
  const step: GuideStep | null = g1.getActiveStep();
  ok('activeStep 存在', step !== null);
  if (step !== null) {
    eq('第一步记录 position', step.position, 0);
    eq('style / endButton', [step.style, step.endButtonLayout], [STYLE_GUIDE, LAYOUT_BUTTON_GUIDE]);
  }
}

function main(): void {
  testDownloadGuideHelper();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('guide test failed');
  }
  console.log(`✓ 下载页新手引导批: ${pass} 条断言全部通过`);
}

main();

