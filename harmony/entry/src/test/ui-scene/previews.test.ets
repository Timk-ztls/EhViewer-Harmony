/*
 * ui-scene 纯逻辑单测：GalleryPreviewsScene（S0252，上游 487 行）
 *
 * 断言重点（都是"容易写反/漏掉"的地方）：
 *   ① 首次才刷新：`onCreateView` 连续调两次只 `firstRefresh` 一次
 *   ② `onDestroyView` **只有 tip 视图在显**时才重置首刷标记（有数据时保留）
 *   ③ 过期任务丢弃：`isCurrentTask(taskId) === false` 时 success/failure 都不应用
 *   ④ `onGetPageData(..., nextPage = 0, ...)` —— **传 0** 不是 page+1
 *   ⑤ `onItemClick` 的 null/未命中一律返回 **true**（已消费），不是 false
 *   ⑥ 页码文本 = `position + 1`；GoTo 的 `progress = 当前页 + 1`，`page = progress - 1`
 *   ⑦ GoTo 越界 → `showTip(error_out_of_range)` 且**不跳转**
 *   ⑧ `getPageRequest` 的 url 参数 `nl` **恒 false**
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter previews
 */

import {
  GalleryPreviewsScene, PreviewsSceneHost, PreviewHelperPort, GoToDialogSpec,
  ACTION_GO_TO, MENU_SCENE_GALLERY_PREVIEWS, TIP_OUT_OF_RANGE, SETTING_THUMB_SIZE_KEY,
  STRATEGY_SUITABLE_SIZE, ITEM_PADDING_VP, LAYOUT_SCENE_GALLERY_PREVIEWS, TITLE_GALLERY_PREVIEWS,
  KEY_GALLERY_INFO, ITEM_PADDING_VP as PAD
} from '../../main/ets/hippo/ehviewer/ui/scene/GalleryPreviewsScene';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { GalleryPreview } from '../../main/ets/hippo/ehviewer/client/data/GalleryPreview';
import { PreviewSet } from '../../main/ets/hippo/ehviewer/client/data/PreviewSet';

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

function mkPreview(page: number): GalleryPreview {
  const p: GalleryPreview = new GalleryPreview();
  p.position = page;
  p.imageKey = `key:${page}`;
  p.imageUrl = `https://TARGET/${page}.jpg`;
  return p;
}

/** 假 PreviewSet（上游是抽象类，测试给一个具体实现） */
class FakePreviewSet extends PreviewSet {
  count: number = 0;

  size(): number {
    return this.count;
  }

  getPosition(index: number): number {
    return index;
  }

  getPageUrlAt(index: number): string {
    return `pageUrl:${index}`;
  }

  getGalleryPreview(gid: number, index: number): GalleryPreview {
    const p: GalleryPreview = new GalleryPreview();
    p.position = index;
    p.imageKey = `key:${gid}:${index}`;
    p.imageUrl = `https://TARGET/${gid}/${index}.jpg`;
    return p;
  }

  load(view: Object, gid: number, index: number): void {
  }

  copy(): PreviewSet {
    const c: FakePreviewSet = new FakePreviewSet();
    c.count = this.count;
    return c;
  }
}

class FakeHelper implements PreviewHelperPort {
  data: GalleryPreview[] = [];
  pages: number = 0;
  canGoToFlag: boolean = true;
  pageForTop: number = 0;
  currentTask: number = 1;
  firstRefreshCalls: number = 0;
  goToCalls: number[] = [];
  pageDataCalls: number = 0;
  lastNextPage: number = -99;
  lastPages: number = -99;
  exceptionCalls: number = 0;

  firstRefresh(): void {
    this.firstRefreshCalls++;
  }

  size(): number {
    return this.data.length;
  }

  getDataAtEx(location: number): GalleryPreview | undefined {
    if (location < 0 || location >= this.data.length) {
      return undefined;
    }
    return this.data[location];
  }

  getPages(): number {
    return this.pages;
  }

  canGoTo(): boolean {
    return this.canGoToFlag;
  }

  getPageForTop(): number {
    return this.pageForTop;
  }

  goTo(page: number): void {
    this.goToCalls.push(page);
  }

  isCurrentTask(taskId: number): boolean {
    return taskId === this.currentTask;
  }

  onGetPageData(taskId: number, pages: number, nextPage: number, newData: GalleryPreview[]): void {
    this.pageDataCalls++;
    this.lastNextPage = nextPage;
    this.lastPages = pages;
    this.data = newData;
  }

  onGetException(taskId: number, e: Error): void {
    this.exceptionCalls++;
  }
}

class FakeHost implements PreviewsSceneHost {
  readers: string[] = [];
  tips: string[] = [];
  backCalls: number = 0;
  exceptions: number = 0;

  openReader(galleryInfo: GalleryInfo, page: number): void {
    this.readers.push(`${galleryInfo.gid}:${page}`);
  }

  showTip(messageKey: string, isLong: boolean): void {
    this.tips.push(messageKey);
  }

  onBackPressed(): void {
    this.backCalls++;
  }

  recordException(e: Error): void {
    this.exceptions++;
  }
}

function mkInfo(): GalleryInfo {
  const gi: GalleryInfo = new GalleryInfo();
  gi.gid = 424242;
  gi.token = 'abcdef';
  gi.title = 'T';
  return gi;
}

function testGalleryPreviewsScene(): void {
  // ---------- 常量 ----------
  eq('菜单 = menu/scene_gallery_previews', MENU_SCENE_GALLERY_PREVIEWS, 'menu/scene_gallery_previews');
  eq('GoTo 菜单项 = action_go_to', ACTION_GO_TO, 'action_go_to');
  eq('越界提示键', TIP_OUT_OF_RANGE, 'app.string.error_out_of_range');
  eq('布局 = scene_gallery_previews', LAYOUT_SCENE_GALLERY_PREVIEWS, 'scene_gallery_previews');
  eq('标题键 = gallery_previews', TITLE_GALLERY_PREVIEWS, 'app.string.gallery_previews');
  eq('列策略 = SUITABLE_SIZE', STRATEGY_SUITABLE_SIZE, 'SUITABLE_SIZE');
  eq('item padding = 4（上游 dp2pix(4)）', ITEM_PADDING_VP, 4);
  eq('缩略图尺寸设置键', SETTING_THUMB_SIZE_KEY, 'thumb_size');

  // ---------- ① 首次才刷新 ----------
  const host: FakeHost = new FakeHost();
  const helper: FakeHelper = new FakeHelper();
  const scene: GalleryPreviewsScene = new GalleryPreviewsScene(host, helper);
  eq('初始未首刷', scene.hasFirstRefreshed(), false);
  scene.onCreateView();
  eq('第一次 onCreateView → firstRefresh 1 次', helper.firstRefreshCalls, 1);
  eq('首刷标记已置', scene.hasFirstRefreshed(), true);
  scene.onCreateView();
  eq('第二次 onCreateView → 仍只 1 次（不重刷）', helper.firstRefreshCalls, 1);

  // ---------- ② onDestroyView 的重置条件 ----------
  scene.onDestroyView(true);   // tip 视图在显
  eq('tip 视图退出 → 首刷标记被重置', scene.hasFirstRefreshed(), false);
  scene.onCreateView();
  eq('重置后再进来 → 又刷一次', helper.firstRefreshCalls, 2);
  scene.onDestroyView(false);  // 有数据
  eq('有数据退出 → 首刷标记保留', scene.hasFirstRefreshed(), true);
  scene.onCreateView();
  eq('有数据退出后再进来 → 不再刷', helper.firstRefreshCalls, 2);

  // ---------- ③ onInit 读 args ----------
  const args: Map<string, Object> = new Map<string, Object>();
  args.set(KEY_GALLERY_INFO, mkInfo());
  const scene2: GalleryPreviewsScene = new GalleryPreviewsScene(host, helper);
  scene2.onInit(args);
  scene2.onInit(null);   // args 为 null 时不清空已设的 info（上游直接 return）
  // 用一次 buildPageRequest 验证 galleryInfo 仍在
  const req2 = scene2.buildPageRequest(3);
  eq('onInit 后 gid 保留', req2.urlArgs !== null ? req2.urlArgs.gid : -1, 424242);

  // ---------- ④ GoTo 对话框 ----------
  helper.pages = 10;
  helper.pageForTop = 4;
  const spec: GoToDialogSpec | null = scene.buildGoToDialog();
  ok('有页数且可跳转 → 产出 GoTo 描述', spec !== null);
  if (spec !== null) {
    eq('start = 1', spec.start, 1);
    eq('end = pages', spec.end, 10);
    eq('rangeMin = 1', spec.rangeMin, 1);
    eq('rangeMax = pages', spec.rangeMax, 10);
    eq('progress = 当前顶页 + 1', spec.progress, 5);
  }
  helper.pages = 0;
  eq('pages = 0 → 不弹 GoTo', scene.buildGoToDialog(), null);
  helper.pages = 10;
  helper.canGoToFlag = false;
  eq('canGoTo = false → 不弹 GoTo', scene.buildGoToDialog(), null);
  helper.canGoToFlag = true;

  // ---------- ⑤ confirmGoTo ----------
  eq('progress=5 → 跳转到 page 4', scene.confirmGoTo(5), true);
  eq('goTo 收到 0 起页码', helper.goToCalls, [4]);
  eq('progress=1 → page 0', scene.confirmGoTo(1), true);
  eq('goTo 累计', helper.goToCalls, [4, 0]);
  eq('progress=11（> pages）→ 不跳转', scene.confirmGoTo(11), false);
  eq('越界后提示 error_out_of_range', host.tips, [TIP_OUT_OF_RANGE]);
  eq('progress=0 → page -1 → 不跳转', scene.confirmGoTo(0), false);
  eq('越界提示累计 2 次', host.tips.length, 2);
  eq('goTo 未被越界调用', helper.goToCalls, [4, 0]);

  // ---------- ⑥ bindItem：文本 = position + 1 ----------
  const helper6: FakeHelper = new FakeHelper();
  helper6.data = [mkPreview(0), mkPreview(1), mkPreview(7)];
  const scene6: GalleryPreviewsScene = new GalleryPreviewsScene(new FakeHost(), helper6);
  eq('itemCount = helper.size()', scene6.getItemCount(), 3);
  const vm0 = scene6.bindItem(0);
  ok('bindItem(0) 非空', vm0 !== null);
  if (vm0 !== null) {
    eq('第 1 项文本 = 1（页码 0 + 1）', vm0.text, '1');
    eq('第 1 项 page = 0', vm0.page, 0);
    eq('imageKey 透传', vm0.imageKey, 'key:0');
    eq('imageUrl 透传', vm0.imageUrl, 'https://TARGET/0.jpg');
  }
  const vm2 = scene6.bindItem(2);
  ok('bindItem(2) 非空', vm2 !== null);
  if (vm2 !== null) {
    eq('第 3 项文本 = 8（页码 7 + 1）', vm2.text, '8');
  }
  eq('bindItem 越界 = null', scene6.bindItem(9), null);

  // ---------- ⑦ onItemClick：null/未命中一律 true ----------
  const host7: FakeHost = new FakeHost();
  const helper7: FakeHelper = new FakeHelper();
  helper7.data = [mkPreview(0), mkPreview(3)];
  const scene7: GalleryPreviewsScene = new GalleryPreviewsScene(host7, helper7);
  // galleryInfo 未设置 → 返回 true 且不打开
  eq('galleryInfo 为 null → 点击返回 true（已消费）', scene7.onItemClick(0), true);
  eq('galleryInfo 为 null → 不打开阅读器', host7.readers.length, 0);
  // 设置 galleryInfo
  const a7: Map<string, Object> = new Map<string, Object>();
  a7.set(KEY_GALLERY_INFO, mkInfo());
  scene7.onInit(a7);
  eq('命中项点击返回 true', scene7.onItemClick(1), true);
  eq('打开阅读器且页码正确（第 2 项 page=3）', host7.readers, ['424242:3']);
  eq('越界点击仍返回 true（已消费，不交给上层）', scene7.onItemClick(9), true);
  eq('越界不打开阅读器', host7.readers.length, 1);

  // ---------- ⑧ success/failure 的过期任务丢弃 ----------
  const host8: FakeHost = new FakeHost();
  const helper8: FakeHelper = new FakeHelper();
  helper8.currentTask = 5;
  const scene8: GalleryPreviewsScene = new GalleryPreviewsScene(host8, helper8);
  const a8: Map<string, Object> = new Map<string, Object>();
  a8.set(KEY_GALLERY_INFO, mkInfo());
  scene8.onInit(a8);
  const ps: FakePreviewSet = new FakePreviewSet();
  ps.count = 4;
  eq('过期 taskId(1) 的 success 被丢弃', scene8.onGetPreviewSetSuccess(ps, 1, 1), false);
  eq('丢弃时不调用 onGetPageData', helper8.pageDataCalls, 0);
  eq('当前 taskId(5) 的 success 被应用', scene8.onGetPreviewSetSuccess(ps, 1, 5), true);
  eq('应用时调用 onGetPageData', helper8.pageDataCalls, 1);
  eq('★ nextPage 传 0（不是 page+1）', helper8.lastNextPage, 0);
  eq('pages 透传', helper8.lastPages, 1);
  eq('展开 4 个预览项', helper8.data.length, 4);
  eq('过期 taskId 的 failure 被丢弃', scene8.onGetPreviewSetFailure(new Error('x'), 1), false);
  eq('丢弃时不登记异常', helper8.exceptionCalls, 0);
  eq('当前 taskId 的 failure 被登记', scene8.onGetPreviewSetFailure(new Error('y'), 5), true);
  eq('登记异常 1 次', helper8.exceptionCalls, 1);

  // ---------- ⑨ 请求参数：nl 恒 false ----------
  const helper9: FakeHelper = new FakeHelper();
  const scene9: GalleryPreviewsScene = new GalleryPreviewsScene(new FakeHost(), helper9);
  const a9: Map<string, Object> = new Map<string, Object>();
  a9.set(KEY_GALLERY_INFO, mkInfo());
  scene9.onInit(a9);
  const req9 = scene9.buildPageRequest(2);
  eq('请求方法 = GET_PREVIEW_SET', req9.method, 'GET_PREVIEW_SET');
  eq('请求页码', req9.page, 2);
  ok('urlArgs 非空', req9.urlArgs !== null);
  if (req9.urlArgs !== null) {
    eq('url gid', req9.urlArgs.gid, 424242);
    eq('url token', req9.urlArgs.token, 'abcdef');
    eq('url page', req9.urlArgs.page, 2);
    eq('★ url nl = false（上游恒 false）', req9.urlArgs.nl, false);
  }

  // ---------- ⑩ 去重恒 false、菜单/导航 ----------
  eq('isDuplicate 恒 false（预览页不去重）', scene.isDuplicate(), false);
  const backBefore: number = host.backCalls;
  scene.onNavigationClick();
  eq('导航触发返回', host.backCalls, backBefore + 1);
  eq('菜单资源 = menu/scene_gallery_previews', scene.getMenuResId(), MENU_SCENE_GALLERY_PREVIEWS);
  eq('padding 常量引用可用', PAD, 4);
}

function main(): void {
  testGalleryPreviewsScene();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('previews test failed');
  }
  console.log(`✓ GalleryPreviewsScene 批: ${pass} 条断言全部通过`);
}

main();
