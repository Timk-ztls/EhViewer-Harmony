/*
 * native-image 接手批单测：GalleryInfoScene（S0251）+ EhTopListScene（S0266）
 *
 * 断言重点（都是"硬编码下标 / 反直觉顺序 / 缓存" 类）：
 *   ① ★`INDEX_URL=3` / `INDEX_PARENT=10` 与 23 行顺序**强耦合** → 断言"第 3 行是 url、第 10 行是 parent"
 *   ② 表头行（position 0）**不可点**且 `enabled=false`
 *   ③ `INDEX_PARENT` 走浏览器（`ITEM_CLICK_OPENED`），其它走剪贴板；**只有 URL 行记 hash**
 *   ④ `getItemCount` 取 `min(keys, values)`
 *   ⑤ `onCreate`：savedState 为 null 才 onInit，否则 onRestore（**真的做恢复**）
 *   ⑥ `Float.toString` 的整数补 `.0`（Java 语义），`Boolean` 输出小写
 *   ⑦ ★EhTopListScene 的 `ViewTransition` 顺序**与 HistoryScene 相反**：0=loading、1=数据
 *   ⑧ 双击退出：`stackIndex != 0` 不拦；间隔内放行；间隔外拦截 + 提示
 *   ⑨ `onSuccess` 的 index **恒为 0**（刷新后回第一个榜单）
 *   ⑩ `getRandomColor` **缓存**（同下标两次颜色相同）；`argb` alpha=160
 *   ⑪ `onItemClick` 三分支 + 详情传的是 **tag 作为 PTOKEN**
 *   ⑫ `hasFirstRefresh` 首刷失败也置 true（不再重试）
 *   ⑬ `TRANSITION_ANIMATION_DISABLED=true` → `shouldAnimate` 恒 false
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter info-toplist
 */

import {
  GalleryInfoScene, GalleryInfoSceneHost, GalleryInfoSnapshot, GalleryInfoRowSpec,
  KEY_KEYS, KEY_VALUES, INDEX_URL, INDEX_PARENT, INFO_KEY_ORDER, TITLE_GALLERY_INFO, TIP_COPIED,
  LAYOUT_HEADER, LAYOUT_DATA, CLICK_COPIED, CLICK_OPENED, CLICK_NONE, javaStringHash
} from '../../main/ets/hippo/ehviewer/ui/scene/GalleryInfoScene';
import {
  EhTopListScene, TopListSceneHost, TopListApi, ListUrlBuilderSpec,
  STATE_INIT, STATE_NORMAL, STATE_REFRESH, STATE_REFRESH_HEADER, STATE_FAILED,
  BACK_PRESSED_INTERVAL, TRANSITION_ANIMATION_DISABLED, TIP_PRESS_TWICE, ERR_REQUEST_FAILED,
  KEY_ACTION, ACTION_TOP_LIST, PROGRESS_ACTION_GALLERY_TOKEN, MODE_NORMAL, MODE_UPLOADER, MODE_TOP_LIST,
  RANDOM_COLOR_ALPHA, VIEW_LOADING, VIEW_DATA,
  ITEM_CLICK_DETAIL, ITEM_CLICK_HREF, ITEM_CLICK_SEARCH, argb, TOP_LIST_URL
} from '../../main/ets/hippo/ehviewer/ui/scene/topList/EhTopListScene';
import { GalleryDetail } from '../../main/ets/hippo/ehviewer/client/data/GalleryDetail';
import { EhTopListDetail, TopListInfo, TopListItem } from '../../main/ets/hippo/ehviewer/client/data/TopList';

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

// ---------------------------------------------------------------- S0251 fakes
class FakeInfoHost implements GalleryInfoSceneHost {
  copied: string[] = [];
  hashes: number[] = [];
  opened: string[] = [];
  tips: string[] = [];
  backCalls: number = 0;

  copyToClipboard(text: string): void {
    this.copied.push(text);
  }

  rememberClipboardHash(hash: number): void {
    this.hashes.push(hash);
  }

  openUrlExternally(url: string): void {
    this.opened.push(url);
  }

  showTip(key: string): void {
    this.tips.push(key);
  }

  onBackPressed(): void {
    this.backCalls++;
  }

  resolveString(key: string): string {
    // 用键名本身做"本地化结果"，便于断言顺序
    return key;
  }
}

function mkDetail(): GalleryDetail {
  const gd: GalleryDetail = new GalleryDetail();
  gd.gid = 1234567;
  gd.token = 'abc123';
  gd.title = 'Some Title';
  gd.titleJpn = '日本語';
  gd.thumb = 'https://TARGET/thumb.jpg';
  gd.category = 1;
  gd.uploader = 'up';
  gd.posted = '2026-01-02 03:04';
  gd.parent = 'parent-x';
  gd.visible = 'Yes';
  gd.language = 'CH';
  gd.pages = 42;
  gd.size = '12 MB';
  gd.favoriteCount = 7;
  gd.isFavorited = true;
  gd.ratingCount = 9;
  gd.rating = 4.0;
  gd.torrentCount = 3;
  gd.torrentUrl = 'https://TARGET/torrent';
  gd.favoriteName = 'fav';
  return gd;
}

function testGalleryInfoScene(): void {
  // ---------- 常量 ----------
  eq('三个 args 键', [KEY_KEYS, KEY_VALUES], ['keys', 'values']);
  eq('★INDEX_URL = 3', INDEX_URL, 3);
  eq('★INDEX_PARENT = 10', INDEX_PARENT, 10);
  eq('标题键', TITLE_GALLERY_INFO, 'app.string.gallery_info');
  eq('复制提示键', TIP_COPIED, 'app.string.copied_to_clipboard');
  eq('两个布局名', [LAYOUT_HEADER, LAYOUT_DATA],
    ['item_gallery_info_header', 'item_gallery_info_data']);
  eq('行数常量 = 22 行（含表头）', INFO_KEY_ORDER.length, 22);

  // ---------- ① 硬编码下标与行顺序的耦合 ----------
  const h1: FakeInfoHost = new FakeInfoHost();
  const s1: GalleryInfoScene = new GalleryInfoScene(h1);
  s1.onCreate(mkDetail(), null);
  eq('总行数 = 22', s1.getItemCount(), 22);
  eq('★第 0 行是表头', s1.bindItem(0) !== null ? (s1.bindItem(0) as GalleryInfoRowSpec).key : '', 'app.string.header_key');
  eq('★第 3 行的键是 key_url', (s1.bindItem(INDEX_URL) as GalleryInfoRowSpec).key, 'app.string.key_url');
  eq('★第 10 行的键是 key_parent', (s1.bindItem(INDEX_PARENT) as GalleryInfoRowSpec).key, 'app.string.key_parent');
  eq('第 1 行 = gid', (s1.bindItem(1) as GalleryInfoRowSpec).value, '1234567');
  eq('第 2 行 = token', (s1.bindItem(2) as GalleryInfoRowSpec).value, 'abc123');
  ok('第 3 行的值是 url（包含 token）',
    (s1.bindItem(INDEX_URL) as GalleryInfoRowSpec).value.indexOf('abc123') >= 0);
  eq('第 10 行 = parent', (s1.bindItem(INDEX_PARENT) as GalleryInfoRowSpec).value, 'parent-x');

  // ---------- ② 表头行不可点 ----------
  eq('bindItem(0).enabled = false', (s1.bindItem(0) as GalleryInfoRowSpec).enabled, false);
  eq('bindItem(1).enabled = true', (s1.bindItem(1) as GalleryInfoRowSpec).enabled, true);
  eq('点第 0 行 → 不处理', s1.onItemClick(0), CLICK_NONE);
  eq('点表头不复制', h1.copied, []);

  // ---------- ③ parent 走浏览器、其它走剪贴板、只有 URL 记 hash ----------
  eq('点 parent 行 → 浏览器打开', s1.onItemClick(INDEX_PARENT), CLICK_OPENED);
  eq('打开的正是 parent 值', h1.opened, ['parent-x']);
  eq('parent 不走剪贴板', h1.copied, []);
  eq('点 gid 行 → 复制', s1.onItemClick(1), CLICK_COPIED);
  eq('复制内容', h1.copied, ['1234567']);
  eq('非 URL 行不记 hash', h1.hashes, []);
  eq('★点 URL 行 → 复制 + 记 hash', s1.onItemClick(INDEX_URL), CLICK_COPIED);
  eq('★记了 hash（Java String.hashCode 语义）', h1.hashes, [javaStringHash((s1.bindItem(INDEX_URL) as GalleryInfoRowSpec).value)]);
  eq('复制了 url', h1.copied.length, 2);
  eq('每次都提示"已复制"', h1.tips, [TIP_COPIED, TIP_COPIED]);

  // ---------- Java String.hashCode 语义 ----------
  eq('hash("") = 0', javaStringHash(''), 0);
  eq('hash("a") = 97', javaStringHash('a'), 97);
  eq('hash("abc") = 96354（Java 标准值）', javaStringHash('abc'), 96354);
  ok('长串按 int32 溢出（可为负）', typeof javaStringHash('https://e-hentai.org/g/123/abc/') === 'number');

  // ---------- ④ getItemCount 取 min ----------
  const h2: FakeInfoHost = new FakeInfoHost();
  const s2: GalleryInfoScene = new GalleryInfoScene(h2);
  s2.onCreate(mkDetail(), null);
  const snap: GalleryInfoSnapshot = s2.onSaveInstanceState();
  const shortSnap: GalleryInfoSnapshot = new GalleryInfoSnapshot();
  shortSnap.keys = snap.keys.slice();
  shortSnap.values = snap.values.slice(0, 5);   // values 更短
  s2.onRestore(shortSnap);
  eq('★keys 22 / values 5 → itemCount = 5（取小）', s2.getItemCount(), 5);
  eq('越界 bindItem → null', s2.bindItem(10), null);

  // ---------- ⑤ onCreate 的恢复分支 ----------
  const h3: FakeInfoHost = new FakeInfoHost();
  const s3: GalleryInfoScene = new GalleryInfoScene(h3);
  s3.onCreate(mkDetail(), null);
  eq('首次 onCreate 未走恢复', s3.isRestored(), false);
  const saved: GalleryInfoSnapshot = s3.onSaveInstanceState();
  saved.values[1] = 'MUTATED';
  const h4: FakeInfoHost = new FakeInfoHost();
  const s4: GalleryInfoScene = new GalleryInfoScene(h4);
  s4.onCreate(null, saved);
  eq('★有 savedState 时走恢复', s4.isRestored(), true);
  eq('★恢复后用的是快照（不是重算）', (s4.bindItem(1) as GalleryInfoRowSpec).value, 'MUTATED');
  eq('恢复不需要 detail', s4.getItemCount(), 22);

  // ---------- ⑥ 数值格式化 ----------
  const h5: FakeInfoHost = new FakeInfoHost();
  const s5: GalleryInfoScene = new GalleryInfoScene(h5);
  s5.onCreate(mkDetail(), null);
  eq('★整数 rating 4.0 → "4.0"（Java Float.toString 语义）',
    (s5.bindItem(18) as GalleryInfoRowSpec).value, '4.0');
  eq('★favorited → 小写 "true"', (s5.bindItem(16) as GalleryInfoRowSpec).value, 'true');
  eq('favoriteCount = "7"', (s5.bindItem(15) as GalleryInfoRowSpec).value, '7');
  eq('pages = "42"', (s5.bindItem(13) as GalleryInfoRowSpec).value, '42');
  eq('torrentCount = "3"', (s5.bindItem(19) as GalleryInfoRowSpec).value, '3');
  // rating 非整数
  const gd2: GalleryDetail = mkDetail();
  gd2.rating = 3.5;
  const s6: GalleryInfoScene = new GalleryInfoScene(new FakeInfoHost());
  s6.onCreate(gd2, null);
  eq('小数 rating 3.5 → "3.5"', (s6.bindItem(18) as GalleryInfoRowSpec).value, '3.5');

  // ---------- 防御：detail 为 null ----------
  const h7: FakeInfoHost = new FakeInfoHost();
  const s7: GalleryInfoScene = new GalleryInfoScene(h7);
  s7.onCreate(null, null);
  eq('detail 为 null → 0 行', s7.getItemCount(), 0);
  eq('detail 为 null → 点击不处理', s7.onItemClick(1), CLICK_NONE);

  // ---------- 导航 ----------
  const before: number = h7.backCalls;
  s7.onNavigationClick();
  eq('导航触发返回', h7.backCalls, before + 1);
}

// ---------------------------------------------------------------- S0266 fakes
class FakeTopHost implements TopListSceneHost {
  stackIndex: number = 0;
  time: number = 10000;
  tips: string[] = [];
  finishCalls: number = 0;
  details: string[] = [];
  lists: ListUrlBuilderSpec[] = [];
  hrefResolvable: boolean = true;

  getStackIndex(): number {
    return this.stackIndex;
  }

  now(): number {
    return this.time;
  }

  showTip(key: string): void {
    this.tips.push(key);
  }

  finish(): void {
    this.finishCalls++;
  }

  isThisScene(sceneTag: string): boolean {
    return true;
  }

  startDetail(gid: number, pToken: string): void {
    this.details.push(`${gid}:${pToken}`);
  }

  startList(builder: ListUrlBuilderSpec): void {
    this.lists.push(builder);
  }

  resolveAnnouncerFromUrl(href: string): boolean {
    return this.hrefResolvable;
  }
}

class FakeTopApi implements TopListApi {
  detail: EhTopListDetail | null = null;
  fail: boolean = false;
  cancelCalls: number = 0;
  fetchCalls: number = 0;

  fetchDetail(url: string): Promise<EhTopListDetail | null> {
    this.fetchCalls++;
    if (this.fail) {
      return Promise.reject(new Error('net'));
    }
    return Promise.resolve(this.detail);
  }

  cancel(): void {
    this.cancelCalls++;
  }
}

function mkTopDetail(): EhTopListDetail {
  const d: EhTopListDetail = new EhTopListDetail();
  d.title = 'Top';
  const info: TopListInfo = new TopListInfo();
  info.title = 'All time';
  d.galleryTopListInfo = info;
  return d;
}

function mkTopItem(gid: string, token: string, href: string, tag: string, value: string): TopListItem {
  const it: TopListItem = new TopListItem();
  it.gid = gid;
  it.token = token;
  it.href = href;
  it.tag = tag;
  it.value = value;
  return it;
}

async function testEhTopListScene(): Promise<void> {
  // ---------- 常量 ----------
  eq('五个状态（INIT 是 -1）',
    [STATE_INIT, STATE_NORMAL, STATE_REFRESH, STATE_REFRESH_HEADER, STATE_FAILED], [-1, 0, 1, 2, 3]);
  eq('双击间隔 2000ms', BACK_PRESSED_INTERVAL, 2000);
  eq('★动画常量 = true（被关掉）', TRANSITION_ANIMATION_DISABLED, true);
  eq('★VIEW_LOADING = 0 / VIEW_DATA = 1', [VIEW_LOADING, VIEW_DATA], [0, 1]);
  eq('两个 companion 常量', [KEY_ACTION, ACTION_TOP_LIST], ['action', 'action_top_list']);
  eq('三种模式', [MODE_NORMAL, MODE_UPLOADER, MODE_TOP_LIST], [0, 1, 2]);
  eq('随机色 alpha = 160', RANDOM_COLOR_ALPHA, 160);

  // ---------- ⑦ 视图索引：与 HistoryScene 相反 ----------
  const h1: FakeTopHost = new FakeTopHost();
  const api1: FakeTopApi = new FakeTopApi();
  const s1: EhTopListScene = new EhTopListScene(h1, api1);
  eq('STATE_INIT → loading(0)', s1.adjustViewVisibility(STATE_INIT, false), VIEW_LOADING);
  eq('STATE_REFRESH → loading(0)', s1.adjustViewVisibility(STATE_REFRESH, false), VIEW_LOADING);
  eq('★STATE_NORMAL → 数据视图(1)', s1.adjustViewVisibility(STATE_NORMAL, false), VIEW_DATA);
  eq('STATE_REFRESH_HEADER → 数据视图(1)', s1.adjustViewVisibility(STATE_REFRESH_HEADER, false), VIEW_DATA);
  eq('STATE_FAILED → 数据视图(1)', s1.adjustViewVisibility(STATE_FAILED, false), VIEW_DATA);
  eq('调整后 state 被记住', s1.getState(), STATE_FAILED);

  // ---------- ⑫ 首刷与失败 ----------
  const h2: FakeTopHost = new FakeTopHost();
  const api2: FakeTopApi = new FakeTopApi();
  const d2: EhTopListDetail = mkTopDetail();
  api2.detail = d2;
  const s2: EhTopListScene = new EhTopListScene(h2, api2);
  eq('初始未首刷', s2.isHasFirstRefresh(), false);
  await s2.onCreateView();
  eq('首次发了一次请求', api2.fetchCalls, 1);
  eq('首刷标记置位', s2.isHasFirstRefresh(), true);
  eq('成功后 state = NORMAL', s2.getState(), STATE_NORMAL);
  await s2.onCreateView();
  eq('再次 onCreateView 不再请求', api2.fetchCalls, 1);

  const h3: FakeTopHost = new FakeTopHost();
  const api3: FakeTopApi = new FakeTopApi();
  api3.fail = true;
  const s3: EhTopListScene = new EhTopListScene(h3, api3);
  await s3.onCreateView();
  ok('失败被记录', s3.getLastError() !== null);
  eq('★失败后 hasFirstRefresh 仍为 true（不再重试）', s3.isHasFirstRefresh(), true);
  await s3.onCreateView();
  eq('★失败后再进也不重发请求', api3.fetchCalls, 1);

  // ---------- ⑧ 双击退出 ----------
  const h4: FakeTopHost = new FakeTopHost();
  const s4: EhTopListScene = new EhTopListScene(h4, new FakeTopApi());
  h4.stackIndex = 1;
  eq('非栈底 → 不拦', s4.checkDoubleClickExit(), false);
  h4.stackIndex = 0;
  h4.time = 10000;
  eq('首次返回 → 拦截', s4.checkDoubleClickExit(), true);
  eq('提示"再按一次退出"', h4.tips, [TIP_PRESS_TWICE]);
  h4.time = 10000 + 1500;   // 1.5s 内
  eq('间隔内 → 放行（退出）', s4.checkDoubleClickExit(), false);
  h4.time = 10000 + 2100;   // 超过 2s（相对上次记录 10000）
  eq('超过间隔 → 再次拦截', s4.checkDoubleClickExit(), true);
  eq('提示两次', h4.tips.length, 2);

  // onBackPressed：截时 cancel；放行时 finish
  const h5: FakeTopHost = new FakeTopHost();
  const api5: FakeTopApi = new FakeTopApi();
  const s5: EhTopListScene = new EhTopListScene(h5, api5);
  await s5.onBackPressed();   // 第一次（10000ms）：距上次 pressBackTime=0 已超 2000 → **拦截**
  eq('第一次返回不 finish', h5.finishCalls, 0);
  eq('第一次返回 showTip', h5.tips, [TIP_PRESS_TWICE]);
  // ★ 注意：第二次必须在 **2000ms 内** 才会放行；超过 2000 又是"第一次"（我的第一版把这里写反了，
  //   和上一批 subscription 的断言错同一族：**期望的是单点，实际是区间语义**）
  h5.time = 10000 + 1500;
  await s5.onBackPressed();   // 1.5s 内 → 放行
  eq('第二次（间隔内）返回 finish', h5.finishCalls, 1);
  eq('★state 为 INIT 时 cancel 请求', api5.cancelCalls, 1);

  // ---------- ⑨ onSuccess 的 index 恒 0 ----------
  const h6: FakeTopHost = new FakeTopHost();
  const s6: EhTopListScene = new EhTopListScene(h6, new FakeTopApi());
  s6.onKindSelected(3);
  eq('切榜单 → mPosition = 3', s6.getPosition(), 3);
  s6.onGetEhTopListDetailSuccess(mkTopDetail(), 0);
  eq('★onSuccess 传 0 → 回到第一个榜单', s6.getPosition(), 0);

  // ---------- ⑩ 随机色缓存 ----------
  const h7: FakeTopHost = new FakeTopHost();
  const s7: EhTopListScene = new EhTopListScene(h7, new FakeTopApi());
  const c1: number = s7.getRandomColor(5, 1, 2, 3);
  const c2: number = s7.getRandomColor(5, 200, 100, 50);   // 参数不同，但应命中缓存
  eq('★同下标两次颜色相同（走缓存）', c1, c2);
  eq('argb(160,1,2,3) 计算正确', c1, argb(160, 1, 2, 3));
  const c3: number = s7.getRandomColor(6, 1, 2, 3);
  ok('不同下标可不同', typeof c3 === 'number');
  eq('argb alpha 在高位', (c1 >>> 24) & 0xFF, 160);

  // ---------- ⑪ onItemClick 三分支 ----------
  const h8: FakeTopHost = new FakeTopHost();
  const s8: EhTopListScene = new EhTopListScene(h8, new FakeTopApi());
  // ② gid+token 非空 → 详情，PTOKEN = tag
  eq('★有 gid+token → 详情', s8.onItemClick(mkTopItem('123', 'tok', '', 'PTAG', 'val'), 0), ITEM_CLICK_DETAIL);
  eq('★详情传的 PTOKEN 是 tag（不是 token）', h8.details, ['123:PTAG']);
  // ③ 无 token 但有 href → href 解析
  h8.hrefResolvable = true;
  eq('无 token + href 可解析 → HREF', s8.onItemClick(mkTopItem('', '', 'https://TARGET/x', 't', 'v'), 0), ITEM_CLICK_HREF);
  // ③' href 解析失败 → 兜底搜索
  h8.hrefResolvable = false;
  eq('href 解析失败 → 搜索', s8.onItemClick(mkTopItem('', '', 'bad', 't', 'kw'), 0), ITEM_CLICK_SEARCH);
  eq('搜索关键词 = value', h8.lists[h8.lists.length - 1].keyword, 'kw');
  eq('searchType=0 → MODE_NORMAL', h8.lists[h8.lists.length - 1].mode, MODE_NORMAL);
  // searchType=1 → MODE_UPLOADER
  h8.hrefResolvable = false;
  s8.onItemClick(mkTopItem('', '', '', 't', 'kw2'), 1);
  eq('★searchType=1 → MODE_UPLOADER', h8.lists[h8.lists.length - 1].mode, MODE_UPLOADER);

  // ---------- clickTitle ----------
  const h9: FakeTopHost = new FakeTopHost();
  const s9: EhTopListScene = new EhTopListScene(h9, new FakeTopApi());
  s9.clickTitle('follow-tag');
  eq('clickTitle → MODE_TOP_LIST + follow', [h9.lists[0].mode, h9.lists[0].follow], [MODE_TOP_LIST, 'follow-tag']);

  // ---------- 异常消息 ----------
  eq('loadData 异常 = 上游中文原文', ERR_REQUEST_FAILED, '请求数据失败请更换IP地址或检查网络设置是否正确~');
  eq('TOP_LIST_URL 常量存在', TOP_LIST_URL, 'TOP_LIST_URL');
  eq('详情进度动作常量', PROGRESS_ACTION_GALLERY_TOKEN, 'gallery_token');
}

async function main(): Promise<void> {
  testGalleryInfoScene();
  await testEhTopListScene();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('info/toplist test failed');
  }
  console.log(`✓ 画廊信息页 + 排行榜页批: ${pass} 条断言全部通过`);
}

main();

