/*
 * ui-scene 纯逻辑单测：HistoryScene（S0253，上游 409 行）
 *
 * 定位：历史列表页的**状态机 + 适配器 + 三项交互**。断言重点放在"容易写反/漏掉"的地方：
 *   ① 四态映射到**两个视图索引**（只有"有数据"显示 content=0，其余三态都显示 tip=1）
 *   ② `confirmClearAll(which)`：**非 BUTTON_POSITIVE 必须不清空**（上游 `which != BUTTON_POSITIVE → return`）
 *   ③ 左滑才删、右滑不动（上游 `RESULT_SWIPED_LEFT` 才走 clear）
 *   ④ `getItemId` = **gid**（稳定 id），不是 position
 *   ⑤ `category` 只在**文本变化**时才更新（避免每次 bind 重设背景造成闪烁）
 *   ⑥ 点击进详情：`hasThumb=false` 时**不挂**转场助手（上游 `if (thumb != null)`）
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter history
 */

import {
  HistoryScene, HistorySceneHost, ClearAllDialogSpec, LongPressMenuSpec,
  NAV_HISTORY_ID, MENU_SCENE_HISTORY, ACTION_CLEAR_ALL,
  VIEW_CONTENT, VIEW_TIP, SWIPE_NONE, SWIPE_DELETE,
  STATE_LOADING, STATE_READY, STATE_EMPTY, STATE_FAILURE,
  LONG_PRESS_DOWNLOAD, LONG_PRESS_FAVORITES, BUTTON_POSITIVE,
  KEY_ACTION, ACTION_GALLERY_INFO, KEY_GALLERY_INFO
} from '../../main/ets/hippo/ehviewer/ui/scene/history/HistoryScene';
import { HistoryInfo } from '../../main/ets/hippo/ehviewer/dao/HistoryInfo';
import { Announcer } from '../../main/ets/hippo/scene/Announcer';

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

function mkInfo(gid: number, title: string, category: number): HistoryInfo {
  const h: HistoryInfo = new HistoryInfo(gid);
  h.title = title;
  h.thumb = `https://TARGET/${gid}.jpg`;
  h.uploader = 'uploader';
  h.rating = 4.5;
  h.category = category;
  h.posted = '2026-01-02 03:04';
  h.simpleLanguage = 'CH';
  return h;
}

class FakeHistoryHost implements HistorySceneHost {
  list: HistoryInfo[] = [];
  failLoad: boolean = false;
  clearCalls: number = 0;
  deleteCalls: number = 0;
  scenes: Announcer[] = [];
  tips: string[] = [];
  backCalls: number = 0;
  downloads: number[] = [];
  favorites: number[] = [];
  favoriteShouldFail: boolean = false;

  loadHistory(): Promise<HistoryInfo[]> {
    if (this.failLoad) {
      return Promise.reject(new Error('load failed'));
    }
    return Promise.resolve(this.list);
  }

  clearHistory(): Promise<void> {
    this.clearCalls++;
    this.list = [];
    return Promise.resolve();
  }

  deleteHistory(info: HistoryInfo): Promise<void> {
    this.deleteCalls++;
    this.list = this.list.filter((x: HistoryInfo): boolean => x.gid !== info.gid);
    return Promise.resolve();
  }

  startScene(announcer: Announcer): void {
    this.scenes.push(announcer);
  }

  showTip(messageKey: string, isLong: boolean): void {
    this.tips.push(messageKey);
  }

  onBackPressed(): void {
    this.backCalls++;
  }

  startDownload(info: HistoryInfo): void {
    this.downloads.push(info.gid);
  }

  addToFavorites(info: HistoryInfo, onSuccess: () => void, onFailure: (e: Error) => void): void {
    this.favorites.push(info.gid);
    if (this.favoriteShouldFail) {
      onFailure(new Error('fav failed'));
    } else {
      onSuccess();
    }
  }

  thumbCacheKey(gid: number): string {
    return `thumb:${gid}`;
  }
}

async function testHistoryScene(): Promise<void> {
  // ---------- 常量（防写反）----------
  eq('VIEW_CONTENT = 0', VIEW_CONTENT, 0);
  eq('VIEW_TIP = 1', VIEW_TIP, 1);
  eq('BUTTON_POSITIVE = -1（上游 DialogInterface.BUTTON_POSITIVE）', BUTTON_POSITIVE, -1);
  eq('SWIPE_NONE = 0', SWIPE_NONE, 0);
  eq('SWIPE_DELETE = 1', SWIPE_DELETE, 1);
  eq('四态互不相同',
    new Set<number>([STATE_LOADING, STATE_READY, STATE_EMPTY, STATE_FAILURE]).size, 4);
  eq('NAV 高亮项 = nav_history', NAV_HISTORY_ID, 'nav_history');
  eq('菜单 = menu/scene_history', MENU_SCENE_HISTORY, 'menu/scene_history');
  eq('清空菜单项 = action_clear_all', ACTION_CLEAR_ALL, 'action_clear_all');
  eq('ACTION_GALLERY_INFO 透传键值', ACTION_GALLERY_INFO, 'gallery_info');

  // ---------- ① 四态 → 两视图 ----------
  const host1: FakeHistoryHost = new FakeHistoryHost();
  const s1: HistoryScene = new HistoryScene(host1);
  eq('初始为 LOADING', s1.getState(), STATE_LOADING);
  eq('LOADING 时显示 tip 视图', s1.updateView(false), VIEW_TIP);

  host1.list = [];
  eq('空列表 onCreateView 返回 tip 视图', await s1.onCreateView(), VIEW_TIP);
  eq('空列表状态 = EMPTY', s1.getState(), STATE_EMPTY);

  const host2: FakeHistoryHost = new FakeHistoryHost();
  host2.list = [mkInfo(11, 'A', 0), mkInfo(22, 'B', 1)];
  const s2: HistoryScene = new HistoryScene(host2);
  eq('有数据 onCreateView 返回 content 视图', await s2.onCreateView(), VIEW_CONTENT);
  eq('有数据状态 = READY', s2.getState(), STATE_READY);
  eq('有数据 itemCount', s2.getItemCount(), 2);

  const host3: FakeHistoryHost = new FakeHistoryHost();
  host3.failLoad = true;
  const s3: HistoryScene = new HistoryScene(host3);
  eq('加载失败 onCreateView 返回 tip 视图', await s3.onCreateView(), VIEW_TIP);
  eq('加载失败状态 = FAILURE', s3.getState(), STATE_FAILURE);
  eq('加载失败 itemCount = 0', s3.getItemCount(), 0);
  ok('加载失败保留错误对象', s3.getLastError() !== null);

  // ---------- ② getItemId = gid（稳定 id，不是 position）----------
  eq('getItemId(0) = gid 11（不是 0）', s2.getItemId(0), 11);
  eq('getItemId(1) = gid 22', s2.getItemId(1), 22);
  eq('getItemId 越界 = -1', s2.getItemId(9), -1);

  // ---------- ③ bindItem 字段映射 ----------
  const vm = s2.bindItem(0);
  ok('bindItem 非空', vm !== null);
  if (vm !== null) {
    eq('bindItem gid', vm.gid, 11);
    eq('bindItem thumbCacheKey 由宿主提供', vm.thumbCacheKey, 'thumb:11');
    eq('bindItem thumbUrl', vm.thumbUrl, 'https://TARGET/11.jpg');
    eq('bindItem title', vm.title, 'A');
    eq('bindItem uploader', vm.uploader, 'uploader');
    eq('bindItem rating', vm.rating, 4.5);
    eq('bindItem posted 保持字符串', vm.posted, '2026-01-02 03:04');
    eq('bindItem simpleLanguage', vm.simpleLanguage, 'CH');
    eq('bindItem transitionName = thumb:gid', vm.transitionName, 'thumb:11');
  }
  eq('bindItem 越界 = null', s2.bindItem(9), null);

  // ---------- ④ category 条件更新 ----------
  eq('category 文本相同 → 不更新', s2.shouldUpdateCategory('同人志', '同人志'), false);
  eq('category 文本不同 → 要更新', s2.shouldUpdateCategory('同人志', '画集'), true);

  // ---------- ⑤ 清空确认：非 POSITIVE 必须不清空 ----------
  const host5: FakeHistoryHost = new FakeHistoryHost();
  host5.list = [mkInfo(1, 'x', 0)];
  const s5: HistoryScene = new HistoryScene(host5);
  await s5.onCreateView();
  eq('清空菜单项返回 true', s5.onMenuItemClick(ACTION_CLEAR_ALL), true);
  ok('弹出了清空确认框', s5.getClearAllDialog() !== null);
  eq('取消（which=0）不清空', await s5.confirmClearAll(0), false);
  eq('取消后 clearCalls = 0', host5.clearCalls, 0);
  eq('取消后仍有 1 项', s5.getItemCount(), 1);
  // 重新弹框后确认
  s5.onMenuItemClick(ACTION_CLEAR_ALL);
  eq('确认（which=-1）执行清空', await s5.confirmClearAll(BUTTON_POSITIVE), true);
  eq('清空后 clearCalls = 1', host5.clearCalls, 1);
  eq('清空后 itemCount = 0', s5.getItemCount(), 0);
  eq('清空后状态 = EMPTY', s5.getState(), STATE_EMPTY);
  eq('清空后显示 tip 视图', s5.updateView(true), VIEW_TIP);
  eq('非清空菜单项返回 false', s5.onMenuItemClick('action_refresh'), false);

  // ---------- ⑥ 点击进详情：有/无 thumb ----------
  const host6: FakeHistoryHost = new FakeHistoryHost();
  host6.list = [mkInfo(7, 'T', 0)];
  const s6: HistoryScene = new HistoryScene(host6);
  await s6.onCreateView();
  eq('有 thumb 时点击返回 true', s6.onItemClick(0, true), true);
  eq('打开了一个 Scene', host6.scenes.length, 1);
  const an: Announcer = host6.scenes[0];
  eq('场景名 = GalleryDetailScene', an.sceneName, 'GalleryDetailScene');
  ok('挂了转场助手', an.tranHelper !== null);
  ok('args 里带 ACTION_GALLERY_INFO', an.args !== null && an.args.get(KEY_ACTION) === ACTION_GALLERY_INFO);
  ok('args 里带 galleryInfo', an.args !== null && an.args.get(KEY_GALLERY_INFO) === host6.list[0]);

  eq('无 thumb 时点击仍返回 true', s6.onItemClick(0, false), true);
  eq('无 thumb 时不挂转场助手', host6.scenes[1].tranHelper, null);
  eq('越界点击返回 false', s6.onItemClick(9, true), false);

  // ---------- ⑦ 长按菜单：两项 ----------
  const menu: LongPressMenuSpec | null = s6.onItemLongClick(0);
  ok('长按返回菜单', menu !== null);
  if (menu !== null) {
    eq('菜单两项', menu.entries.length, 2);
    eq('菜单标题 = 合适标题', menu.title, 'T');
  }
  eq('菜单 0 = 下载', LONG_PRESS_DOWNLOAD, 0);
  eq('菜单 1 = 收藏', LONG_PRESS_FAVORITES, 1);
  eq('选下载 → true', s6.onLongPressMenuClick(LONG_PRESS_DOWNLOAD), true);
  eq('下载被调用（gid 7）', host6.downloads, [7]);
  eq('下载后菜单已清空', s6.onLongPressMenuClick(LONG_PRESS_DOWNLOAD), false);

  const menu2 = s6.onItemLongClick(0);
  ok('重新长按得到菜单', menu2 !== null);
  eq('选收藏 → true', s6.onLongPressMenuClick(LONG_PRESS_FAVORITES), true);
  eq('收藏被调用（gid 7）', host6.favorites, [7]);
  eq('收藏成功 → 显示成功提示', host6.tips, ['app.string.add_to_favorite_success']);

  const host7: FakeHistoryHost = new FakeHistoryHost();
  host7.list = [mkInfo(8, 'U', 0)];
  host7.favoriteShouldFail = true;
  const s7: HistoryScene = new HistoryScene(host7);
  await s7.onCreateView();
  s7.onItemLongClick(0);
  s7.onLongPressMenuClick(LONG_PRESS_FAVORITES);
  eq('收藏失败 → 显示失败提示', host7.tips, ['app.string.add_to_favorite_failure']);

  // ---------- ⑧ 左滑删除 / 右滑不动 ----------
  const host8: FakeHistoryHost = new FakeHistoryHost();
  host8.list = [mkInfo(1, 'a', 0), mkInfo(2, 'b', 0)];
  const s8: HistoryScene = new HistoryScene(host8);
  await s8.onCreateView();
  eq('右滑（SWIPE_NONE）不删', await s8.onSwipeItem(0, SWIPE_NONE), false);
  eq('右滑后 deleteCalls = 0', host8.deleteCalls, 0);
  eq('左滑（SWIPE_DELETE）删除', await s8.onSwipeItem(0, SWIPE_DELETE), true);
  eq('左滑后 deleteCalls = 1', host8.deleteCalls, 1);
  eq('删除后剩 1 项', s8.getItemCount(), 1);
  eq('删除的是 gid=1', s8.getItems()[0].gid, 2);

  // ---------- ⑨ 导航 ----------
  const backBefore: number = host8.backCalls;
  s8.onNavigationClick();
  eq('导航返回触发 onBackPressed', host8.backCalls, backBefore + 1);
}

async function main(): Promise<void> {
  await testHistoryScene();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('history test failed');
  }
  console.log(`✓ HistoryScene 批: ${pass} 条断言全部通过`);
}

main();
