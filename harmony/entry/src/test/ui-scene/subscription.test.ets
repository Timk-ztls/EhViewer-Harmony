/*
 * native-image 接手批单测：SubscriptionDraw（S0245）+ SubscriptionsScene（S0247）
 *
 * 断言重点（都是"两份实现不一致 / 容易写反"的）：
 *   ① `setUserTagList` **首次持有引用、之后只换数组**（对象上的 stageId 不能丢）
 *   ② `needLoad` 只在 onSuccess 里置 false；失败后仍为 true（下次重试）
 *   ③ `loadData` 失败**只记录不提示**，且抛的是中文原文异常
 *   ④ `bindViewSecond` 的 `not_login_text` **只在"已登录且空列表"**时显示
 *   ⑤ `resume()` 要求 scrollY 与 pos **都非空**
 *   ⑥ ★**两份实现的翻译开关不同**：本页 `?getName():tagName`；抽屉的 adapter **无条件 getName**
 *   ⑦ ★`SubscriptionsScene` 保存缓存时传的是 **result 而不是 userTagList**（result 为 null 时清空缓存）
 *   ⑧ `bindSecond` 在 `recyclerView == null` 时弹**中文原文 Toast** 并 return
 *   ⑨ 删除前 UI 状态 = progress 显示 + 列表 **INVISIBLE**
 *   ⑩ `imageView` 与 `dragHandler` 是**同一个控件**；`label`/`dragHandler` **没绑点击**
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter subscription
 */

import {
  SubscriptionDraw, DrawHost, SubscriptionCallbackLike, TagApi, AddTagDialogSpec,
  SUBSCRIPTION_DRAW_SCROLL_Y, SUBSCRIPTION_DRAW_POS, TIP_SUBSCRIPTION, TITLE_SUBSCRIPTION,
  TOAST_TOURIST, TOAST_EMPTY_SUBSCRIPTION, TOAST_CANNOT_USE_TAG, TITLE_ADD_TAG_DIALOG,
  BTN_WATCHED, BTN_HIDDEN, ERR_REQUEST_FAILED, MENU_ACTION_ADD, MENU_ACTION_SETTINGS,
  MY_TAG_URL
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/SubscriptionDraw';
import {
  SubscriptionsScene, SubscriptionsSceneHost, SubscriptionsApi, SubscriptionRowViewModel,
  SubscriptionDeleteDialogSpec, TITLE_TAG, TIP_NO_QUICK_SEARCH, TITLE_DELETE_SUBSCRIPTION,
  DRAWABLE_BIG_SEARCH, TOAST_RECYCLER_MISSING, ICON_VISIBILITY, ICON_VISIBILITY_OFF,
  VIEW_LIST, VIEW_TIP, NO_POSITION, MY_TAG_URL as SUB_MY_TAG_URL
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/SubscriptionsScene';
import { UserTag, UserTagList, TagPushParam } from '../../main/ets/hippo/ehviewer/client/data/UserTag';

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

function mkTag(id: string, name: string, watched: boolean, hidden: boolean): UserTag {
  const t: UserTag = new UserTag();
  t.userTagId = id;
  t.tagName = name;
  t.watched = watched;
  t.hidden = hidden;
  return t;
}

// ---------------------------------------------------------------- S0245 fakes
class FakeDrawHost implements DrawHost {
  login: boolean = true;
  cachedList: UserTagList | null = null;
  savedLists: (UserTagList | null)[] = [];
  stageIdSet: number[] = [];
  stageId: number = 42;
  tempCache: Map<string, Object> = new Map<string, Object>();
  toasts: string[] = [];
  startedSubscriptions: number = 0;
  pagerItems: number[] = [];
  progressVisible: boolean[] = [];
  listAreaVisible: boolean[] = [];
  notLoginVisible: boolean[] = [];
  boundAdapters: number = 0;
  selection: number[] = [];

  isLogin(): boolean {
    return this.login;
  }

  getUserTagList(): UserTagList | null {
    return this.cachedList;
  }

  saveUserTagList(list: UserTagList | null): void {
    this.savedLists.push(list);
  }

  setStageId(list: UserTagList, stageId: number): void {
    this.stageIdSet.push(stageId);
  }

  getStageId(): number {
    return this.stageId;
  }

  getTempCache(key: string): Object | null {
    const v = this.tempCache.get(key);
    return v === undefined ? null : v;
  }

  putTempCache(key: string, value: Object): void {
    this.tempCache.set(key, value);
  }

  showToast(key: string): void {
    this.toasts.push(key);
  }

  startSubscriptionsScene(): void {
    this.startedSubscriptions++;
  }

  setPagerItem(index: number): void {
    this.pagerItems.push(index);
  }

  setProgressVisible(visible: boolean): void {
    this.progressVisible.push(visible);
  }

  setListAreaVisible(visible: boolean): void {
    this.listAreaVisible.push(visible);
  }

  setNotLoginTextVisible(visible: boolean): void {
    this.notLoginVisible.push(visible);
  }

  bindAdapter(adapter: Object, onItemClick: (position: number) => void): void {
    this.boundAdapters++;
    this.clickHandler = onItemClick;
  }

  clickHandler: ((position: number) => void) | null = null;

  setListSelection(position: number): void {
    this.selection.push(position);
  }

  simulateClick(position: number): void {
    if (this.clickHandler !== null) {
      this.clickHandler(position);
    }
  }
}

class FakeCallback implements SubscriptionCallbackLike {
  clicks: string[] = [];
  addName: string | null = 'newtag';

  onSubscriptionItemClick(tagName: string): void {
    this.clicks.push(tagName);
  }

  getAddTagName(list: UserTagList | null): string | null {
    return this.addName;
  }
}

class FakeTagApi implements TagApi {
  watchedResult: UserTagList | null = null;
  addResult: UserTagList | null = null;
  failWatched: boolean = false;
  failAdd: boolean = false;
  watchedCalls: number = 0;
  addParams: TagPushParam[] = [];

  fetchWatched(url: string): Promise<UserTagList | null> {
    this.watchedCalls++;
    if (this.failWatched) {
      return Promise.reject(new Error('net'));
    }
    return Promise.resolve(this.watchedResult);
  }

  addTag(url: string, param: TagPushParam): Promise<UserTagList | null> {
    this.addParams.push(param);
    if (this.failAdd) {
      return Promise.reject(new Error('net'));
    }
    return Promise.resolve(this.addResult);
  }
}

function mkList(tags: UserTag[]): UserTagList {
  const l: UserTagList = new UserTagList();
  l.userTags = tags;
  return l;
}

// ---------------------------------------------------------------- S0247 fakes
class FakeSceneHost implements SubscriptionsSceneHost {
  cached: UserTagList | null = null;
  saved: (UserTagList | null)[] = [];
  progress: boolean[] = [];
  recycler: boolean[] = [];
  rawTips: string[] = [];
  tr: boolean = false;
  tags: Object | null = null;
  backCalls: number = 0;

  getUserTagList(): UserTagList | null {
    return this.cached;
  }

  saveUserTagList(result: UserTagList | null): void {
    this.saved.push(result);
  }

  setProgressVisible(visible: boolean): void {
    this.progress.push(visible);
  }

  setRecyclerViewVisible(visible: boolean): void {
    this.recycler.push(visible);
  }

  showTipRaw(text: string): void {
    this.rawTips.push(text);
  }

  getShowTagTranslations(): boolean {
    return this.tr;
  }

  getEhTagDatabase(): Object | null {
    return this.tags;
  }

  onBackPressed(): void {
    this.backCalls++;
  }
}

class FakeSubApi implements SubscriptionsApi {
  result: UserTagList | null = null;
  calls: number = 0;

  deleteWatched(url: string, tag: UserTag): Promise<UserTagList | null> {
    this.calls++;
    return Promise.resolve(this.result);
  }
}

async function testSubscriptionDraw(): Promise<void> {
  // ---------- 常量 ----------
  eq('两个 tempCache 键', [SUBSCRIPTION_DRAW_SCROLL_Y, SUBSCRIPTION_DRAW_POS],
    ['SubscriptionDrawScrollY', 'SubscriptionDrawPos']);
  eq('两个菜单项', [MENU_ACTION_ADD, MENU_ACTION_SETTINGS], ['action_add', 'action_settings']);
  eq('异常消息 = 上游中文原文', ERR_REQUEST_FAILED, '请求数据失败请更换IP地址或检查网络设置是否正确~');
  eq('两个按钮文案键', [BTN_WATCHED, BTN_HIDDEN],
    ['app.string.subscription_watched', 'app.string.subscription_hidden']);

  // ---------- ① setUserTagList：首次持引用，之后只换数组 ----------
  const h1: FakeDrawHost = new FakeDrawHost();
  const c1: FakeCallback = new FakeCallback();
  const api1: FakeTagApi = new FakeTagApi();
  const d1: SubscriptionDraw = new SubscriptionDraw(h1, api1, c1);
  const first: UserTagList = mkList([mkTag('usertag_1', 'a', false, false)]);
  d1.setUserTagList(first);
  eq('首次持有该对象', d1.getUserTagList() === first, true);
  const second: UserTagList = mkList([mkTag('usertag_2', 'b', true, false), mkTag('usertag_3', 'c', false, true)]);
  d1.setUserTagList(second);
  eq('★第二次仍持有**原对象**（未被替换）', d1.getUserTagList() === first, true);
  eq('★但数组已替换成新的', d1.getUserTagList() !== null ? (d1.getUserTagList() as UserTagList).userTags.length : -1, 2);
  eq('数组内容来自 second', (d1.getUserTagList() as UserTagList).userTags[0].tagName, 'b');

  // ---------- ② needLoad 闸门 ----------
  const h2: FakeDrawHost = new FakeDrawHost();
  const api2: FakeTagApi = new FakeTagApi();
  api2.watchedResult = mkList([mkTag('usertag_9', 'x', false, false)]);
  const d2: SubscriptionDraw = new SubscriptionDraw(h2, api2, new FakeCallback());
  eq('初始 needLoad = true', d2.isNeedLoad(), true);
  await d2.onCreate();
  eq('首次 onCreate 发了请求', api2.watchedCalls, 1);
  eq('成功后 needLoad = false', d2.isNeedLoad(), false);
  await d2.onCreate();
  eq('再次 onCreate 不再请求', api2.watchedCalls, 1);

  // ---------- ③ 请求失败：只记录不提示 ----------
  const h3: FakeDrawHost = new FakeDrawHost();
  const api3: FakeTagApi = new FakeTagApi();
  api3.failWatched = true;
  const d3: SubscriptionDraw = new SubscriptionDraw(h3, api3, new FakeCallback());
  await d3.onCreate();
  ok('失败被记录', d3.getLastError() !== null);
  eq('★失败不弹提示（上游只 printStackTrace）', h3.toasts.length, 0);
  eq('★失败后 needLoad 仍为 true（下次重试）', d3.isNeedLoad(), true);

  // ---------- ④ not_login_text 只在"已登录且空"时显示 ----------
  const h4: FakeDrawHost = new FakeDrawHost();
  const d4: SubscriptionDraw = new SubscriptionDraw(h4, new FakeTagApi(), new FakeCallback());
  d4.setUserTagList(mkList([]));
  h4.login = true;
  d4.bindViewSecond();
  eq('已登录 + 空列表 → 显示 not_login_text', h4.notLoginVisible, [true]);
  const h5: FakeDrawHost = new FakeDrawHost();
  const d5: SubscriptionDraw = new SubscriptionDraw(h5, new FakeTagApi(), new FakeCallback());
  d5.setUserTagList(mkList([]));
  h5.login = false;
  d5.bindViewSecond();
  eq('★未登录 + 空列表 → 不显示 not_login_text', h5.notLoginVisible, []);
  eq('未登录空列表也不绑 adapter', h5.boundAdapters, 0);

  // ---------- 绑定 adapter + 点击回 tagName ----------
  const h6: FakeDrawHost = new FakeDrawHost();
  const c6: FakeCallback = new FakeCallback();
  const d6: SubscriptionDraw = new SubscriptionDraw(h6, new FakeTagApi(), c6);
  d6.setUserTagList(mkList([mkTag('usertag_1', 'alpha', false, false), mkTag('usertag_2', 'beta', true, false)]));
  d6.bindViewSecond();
  eq('绑定了 adapter', h6.boundAdapters, 1);
  h6.simulateClick(1);
  eq('★点击回传的是 tagName（不是 UserTag）', c6.clicks, ['beta']);
  h6.simulateClick(9);
  eq('越界点击不回调', c6.clicks, ['beta']);

  // ---------- ⑤ resume 要求两者都非空 ----------
  const h7: FakeDrawHost = new FakeDrawHost();
  const d7: SubscriptionDraw = new SubscriptionDraw(h7, new FakeTagApi(), new FakeCallback());
  d7.resume();
  eq('无缓存 → 不设置选中', h7.selection, []);
  h7.putTempCache(SUBSCRIPTION_DRAW_POS, 3);
  d7.resume();
  eq('★只有 pos 没有 scrollY → 仍不恢复', h7.selection, []);
  h7.putTempCache(SUBSCRIPTION_DRAW_SCROLL_Y, 120);
  d7.resume();
  eq('两者都有 → 恢复', h7.selection, [3]);

  // ---------- 滚动缓存计算 ----------
  const h8: FakeDrawHost = new FakeDrawHost();
  const d8: SubscriptionDraw = new SubscriptionDraw(h8, new FakeTagApi(), new FakeCallback());
  d8.onScrollStateChanged(2, 100, 30, true);
  eq('scrollY = firstPos*height - top = 170', h8.getTempCache(SUBSCRIPTION_DRAW_SCROLL_Y), 170);
  eq('pos = firstPos', h8.getTempCache(SUBSCRIPTION_DRAW_POS), 2);
  const h9: FakeDrawHost = new FakeDrawHost();
  const d9: SubscriptionDraw = new SubscriptionDraw(h9, new FakeTagApi(), new FakeCallback());
  d9.onScrollStateChanged(5, 100, 10, false);
  eq('★没有子项 → 不写缓存', h9.getTempCache(SUBSCRIPTION_DRAW_POS), null);

  // ---------- 加标签对话框 ----------
  const h10: FakeDrawHost = new FakeDrawHost();
  const c10: FakeCallback = new FakeCallback();
  const api10: FakeTagApi = new FakeTagApi();
  const d10: SubscriptionDraw = new SubscriptionDraw(h10, api10, c10);
  d10.setUserTagList(mkList([]));
  h10.login = false;
  eq('未登录 → 不加标签', d10.addNewTag(), null);
  eq('未登录 → toast 游客文案', h10.toasts, [TOAST_TOURIST]);
  h10.login = true;
  c10.addName = null;
  eq('★名字不可用 → 不弹对话框', d10.addNewTag(), null);
  eq('名字不可用 → toast 对应文案', h10.toasts, [TOAST_TOURIST, TOAST_CANNOT_USE_TAG]);
  c10.addName = 'mytag';
  const spec: AddTagDialogSpec | null = d10.addNewTag();
  ok('合法 → 产出对话框', spec !== null);
  if (spec !== null) {
    eq('对话框 title', spec.title, TITLE_ADD_TAG_DIALOG);
    eq('对话框初值 = 名字', spec.text, 'mytag');
    eq('两个按钮', [spec.positiveText, spec.negativeText], [BTN_WATCHED, BTN_HIDDEN]);
  }
  // 正按钮 → tagWatchNew = 'on'
  await d10.onDialogPositive();
  eq('加标签方法收到 1 次', api10.addParams.length, 1);
  eq('tagNameNew', api10.addParams[0].tagNameNew, 'mytag');
  eq('★正按钮 → tagWatchNew = on', api10.addParams[0].tagWatchNew, 'on');
  eq('tagHiddenNew 保持 null', api10.addParams[0].tagHiddenNew, null);
  // 负按钮 → tagHiddenNew = 'on'
  d10.addNewTag();
  await d10.onDialogNegative();
  eq('★负按钮 → tagHiddenNew = on', api10.addParams[1].tagHiddenNew, 'on');
  eq('tagWatchNew 保持 null', api10.addParams[1].tagWatchNew, null);
  eq('加标签后 needLoad = false', d10.isNeedLoad(), false);

  // ---------- 菜单：恒返回 true ----------
  const h11: FakeDrawHost = new FakeDrawHost();
  const d11: SubscriptionDraw = new SubscriptionDraw(h11, new FakeTagApi(), new FakeCallback());
  eq('未知菜单项也返回 true', d11.onMenuItemClick('action_unknown'), true);
  eq('action_add 返回 true', d11.onMenuItemClick(MENU_ACTION_ADD), true);
  d11.setUserTagList(mkList([]));
  eq('action_settings 返回 true', d11.onMenuItemClick(MENU_ACTION_SETTINGS), true);
  eq('已登录有列表 → 进订阅页', h11.startedSubscriptions, 1);
  eq('设置了 stageId', h11.stageIdSet, [42]);
  d11.onToolbarClick();
  eq('toolbar 点击回第 0 页', h11.pagerItems, [0]);

  // 未登录进订阅页 → toast
  const h12: FakeDrawHost = new FakeDrawHost();
  const d12: SubscriptionDraw = new SubscriptionDraw(h12, new FakeTagApi(), new FakeCallback());
  h12.login = false;
  eq('未登录 → 不进订阅页', d12.seeDetailPage(), false);
  eq('未登录 toast 游客', h12.toasts, [TOAST_TOURIST]);
  h12.login = true;
  eq('已登录但无列表 → 不进订阅页', d12.seeDetailPage(), false);
  eq('无列表 toast 空订阅', h12.toasts, [TOAST_TOURIST, TOAST_EMPTY_SUBSCRIPTION]);
  eq('未进页时 startedSubscriptions = 0', h12.startedSubscriptions, 0);
}

async function testSubscriptionsScene(): Promise<void> {
  // ---------- 常量 ----------
  eq('标题键是 tag_title（不是 subscriptions）', TITLE_TAG, 'app.string.tag_title');
  eq('tip 文案 = no_quick_search', TIP_NO_QUICK_SEARCH, 'app.string.no_quick_search');
  eq('删除确认标题', TITLE_DELETE_SUBSCRIPTION, 'app.string.delete_subscription_title');
  eq('tip 图标 = big_search', DRAWABLE_BIG_SEARCH, 'big_search');
  eq('视图索引', [VIEW_LIST, VIEW_TIP], [0, 1]);
  eq('NO_POSITION = -1', NO_POSITION, -1);
  eq('★中文 Toast 原文照搬', TOAST_RECYCLER_MISSING, '描述文件未找到？？？重启试试~');

  // ---------- updateView / 计数 / 稳定 id ----------
  const h1: FakeSceneHost = new FakeSceneHost();
  const s1: SubscriptionsScene = new SubscriptionsScene(h1, new FakeSubApi());
  s1.onCreate();
  eq('空 → tip 视图', s1.updateView(), VIEW_TIP);
  h1.cached = mkList([mkTag('usertag_1', 'a', false, false), mkTag('usertag_2', 'b', true, false)]);
  s1.onCreate();
  eq('有数据 → 列表视图', s1.updateView(), VIEW_LIST);
  eq('itemCount', s1.getItemCount(), 2);
  eq('★getItemId = 标签 id', s1.getItemId(1), 2);
  eq('越界 = 0', s1.getItemId(9), 0);

  // ---------- ⑥ 翻译开关两条路 ----------
  const h2: FakeSceneHost = new FakeSceneHost();
  h2.cached = mkList([mkTag('usertag_5', 'language:chinese', true, false)]);
  const s2: SubscriptionsScene = new SubscriptionsScene(h2, new FakeSubApi());
  s2.onCreate();
  h2.tr = false;
  const vmOff: SubscriptionRowViewModel | null = s2.bindItem(0);
  ok('关翻译时绑定非空', vmOff !== null);
  if (vmOff !== null) {
    eq('★关翻译 → 直接用 tagName', vmOff.label, 'language:chinese');
  }
  h2.tr = true;
  const vmOn: SubscriptionRowViewModel | null = s2.bindItem(0);
  ok('开翻译时绑定非空', vmOn !== null);
  if (vmOn !== null) {
    // UserTagConfig 默认 getShowTagTranslations()=false，故 getName 返回原名
    eq('开翻译 → 走 getName（本项目默认不翻译，仍原名）', vmOn.label, 'language:chinese');
  }

  // ---------- 图标：hidden/watched 两个独立 if ----------
  const h3: FakeSceneHost = new FakeSceneHost();
  h3.cached = mkList([
    mkTag('usertag_1', 'none', false, false),
    mkTag('usertag_2', 'watched', true, false),
    mkTag('usertag_3', 'hidden', false, true),
    mkTag('usertag_4', 'both', true, true)
  ]);
  const s3: SubscriptionsScene = new SubscriptionsScene(h3, new FakeSubApi());
  s3.onCreate();
  eq('都不满足 → null', (s3.bindItem(0) as SubscriptionRowViewModel).stateIcon, null);
  eq('仅 watched → on', (s3.bindItem(1) as SubscriptionRowViewModel).stateIcon, ICON_VISIBILITY);
  eq('仅 hidden → off', (s3.bindItem(2) as SubscriptionRowViewModel).stateIcon, ICON_VISIBILITY_OFF);
  eq('★两者都真 → watched 覆盖 hidden', (s3.bindItem(3) as SubscriptionRowViewModel).stateIcon, ICON_VISIBILITY);

  // ---------- ⑧ bindSecond 的 recyclerView == null 分支 ----------
  const h4: FakeSceneHost = new FakeSceneHost();
  const s4: SubscriptionsScene = new SubscriptionsScene(h4, new FakeSubApi());
  eq('★无 recyclerView → 返回 false', s4.bindSecond(false), false);
  eq('★弹出中文原文 Toast', h4.rawTips, [TOAST_RECYCLER_MISSING]);
  eq('progress 仍被关掉', h4.progress, [false]);
  eq('不设列表可见', h4.recycler, []);
  eq('有 recyclerView → true', s4.bindSecond(true), true);
  eq('设列表可见', h4.recycler, [true]);
  eq('userTagList 为 null 时新建空列表', s4.getItemCount(), 0);

  // ---------- ⑨ 删除：progress 显示 + 列表 INVISIBLE ----------
  const h5: FakeSceneHost = new FakeSceneHost();
  h5.cached = mkList([mkTag('usertag_7', 'del-me', false, false)]);
  const api5: FakeSubApi = new FakeSubApi();
  api5.result = mkList([]);
  const s5: SubscriptionsScene = new SubscriptionsScene(h5, api5);
  s5.onCreate();
  eq('NO_POSITION → 不产对话框', s5.buildDeleteDialog(NO_POSITION), null);
  const dlg: SubscriptionDeleteDialogSpec | null = s5.buildDeleteDialog(0);
  ok('产出删除对话框', dlg !== null);
  if (dlg !== null) {
    eq('对话框 title', dlg.title, TITLE_DELETE_SUBSCRIPTION);
    eq('对话框 message 带 tagName', dlg.message, 'del-me');
  }
  eq('删除执行成功', await s5.deleteTag(), true);
  // ★ 断言的是**完整序列**，不是终态：
  //   `deleteTag()` 先把 progress 显示 + 列表 INVISIBLE（上游 deleteTag 里那两行），
  //   然后请求成功走 `onSuccess → bindSecond()`，后者把 progress 关掉 + 列表显示（上游同样如此）。
  //   所以正确序列是 [true,false] / [false,true] —— **我第一版只断言了中间态，是断言写错、不是实现错**。
  eq('★删除时先显示 progress，成功后 bindSecond 关掉它', h5.progress, [true, false]);
  eq('★删除时先把列表藏起来，成功后 bindSecond 再显示', h5.recycler, [false, true]);
  eq('删除接口被调 1 次', api5.calls, 1);

  // ---------- ⑦ 保存缓存时传的是 result 而不是 userTagList ----------
  const h6: FakeSceneHost = new FakeSceneHost();
  const s6: SubscriptionsScene = new SubscriptionsScene(h6, new FakeSubApi());
  s6.onCreate();
  const resultList: UserTagList = mkList([mkTag('usertag_1', 'r', false, false)]);
  s6.applyResult(resultList);
  eq('★保存的是 result 对象本身', h6.saved[0] === resultList, true);
  eq('本地列表被填充', s6.getItemCount(), 1);
  // result 为 null → 保存 null（清空缓存）+ 本地空数组
  const h7: FakeSceneHost = new FakeSceneHost();
  const s7: SubscriptionsScene = new SubscriptionsScene(h7, new FakeSubApi());
  s7.onCreate();
  s7.applyResult(null);
  eq('★result 为 null → 保存 null（清空缓存语义）', h7.saved, [null]);
  eq('本地 userTags 置空', s7.getItemCount(), 0);
  // result.userTags 为 null → 本地置空但仍保存 result
  const h8: FakeSceneHost = new FakeSceneHost();
  const s8: SubscriptionsScene = new SubscriptionsScene(h8, new FakeSubApi());
  s8.onCreate();
  const nullTags: UserTagList = new UserTagList();
  nullTags.userTags = null as unknown as UserTag[];
  s8.applyResult(nullTags);
  eq('userTags 为 null → 本地置空数组', s8.getItemCount(), 0);
  eq('仍保存 result（非 null）', h8.saved[0] === nullTags, true);

  // ---------- 拖拽：本页上游没有 DraggableItemAdapter 实现 ----------
  eq('★canStartDrag 恒 false（上游未实现拖拽适配）', s5.canStartDrag(), false);

  // ---------- 导航 ----------
  const backBefore: number = h5.backCalls;
  s5.onNavigationClick();
  eq('导航触发返回', h5.backCalls, backBefore + 1);
  s5.onDestroy();
  eq('onDestroy 后列表清空', s5.getItemCount(), 0);
  eq('两个模块的 MY_TAG_URL 常量一致', MY_TAG_URL, SUB_MY_TAG_URL);
}

async function main(): Promise<void> {
  await testSubscriptionDraw();
  await testSubscriptionsScene();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('subscription test failed');
  }
  console.log(`✓ 订阅抽屉 + 订阅管理页批: ${pass} 条断言全部通过`);
}

main();

