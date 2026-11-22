/*
 * ui-scene 纯逻辑单测：接手批 6 个 ported 文件（C-10：harmony/entry/src/test/<module>/）
 *
 * 定位：这批文件是 native-image 从 ui-scene 接手移植的（Lead 分派），全部是**纯逻辑**或
 * **载体重写**类型，正好可以用断言把"我在文件头写下的那些平台差异判断"钉住 ——
 * 文件头里的注释是给人看的，断言是给回归用的。ui-scene 此前 **0 断言**，本文件是第一批。
 *
 * 覆盖的 6 个文件与"钉住什么"：
 *   1. TransitionNameFactory(S0267)       —— 4 个前缀**逐字一致**（`thumb:`/`title:`/`uploader:`/`category:`）
 *  2. GalleryHolder(S0250)                —— 10 个字段的载体语义（`posted` 是**字符串**、`rating` 是 number）
 *  3. SelectItemWithIconAdapter(S0193)    —— `Length conflict` 抛错 + 越界抛错 + getItemId === position
 *  4. SubscriptionItemAdapter(S0246)      —— hidden/watched **两个独立 if 的覆盖顺序**、getItemId === UserTag.getId()
 *  5. EnterGalleryDetailTransaction(S0238)—— **无 sharedElement 也 takeOver=true**、非详情页 tag → false
 *   6. GalleryUpdateDialog(S0233)         —— `reusedExisting`（上游"没有 return"的语义）、按钮回调的 url 传递
 *
 * 为什么值得写：第 5 条的 `return true` 位置如果写反，表现是"转场偶尔生效、偶尔不生效"；
 * 第 4 条的 if 顺序如果写成 else-if，hidden+watched 同时为真时图标会错 —— 两者都很难靠肉眼发现。
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import { TransitionNameFactory, GID_SAFE_MAX } from '../../main/ets/hippo/ehviewer/ui/scene/TransitionNameFactory';
import { GalleryHolder, GalleryHolderData } from '../../main/ets/hippo/ehviewer/ui/scene/GalleryHolder';
import { SelectItemWithIconAdapter } from '../../main/ets/hippo/ehviewer/ui/dialog/SelectItemWithIconAdapter';
import {
  SubscriptionItemAdapter, ICON_VISIBILITY, ICON_VISIBILITY_OFF
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/SubscriptionItemAdapter';
import {
  EnterGalleryDetailTransaction, TRANSITION_MOVE, TRANSITION_FADE
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/EnterGalleryDetailTransaction';
import { GalleryUpdateDialog, GalleryDetailSceneHost } from '../../main/ets/hippo/ehviewer/ui/scene/gallery/detail/GalleryUpdateDialog';
import { GalleryDetail } from '../../main/ets/hippo/ehviewer/client/data/GalleryDetail';
import { NewVersion } from '../../main/ets/hippo/ehviewer/client/data/NewVersion';
import { UserTag, UserTagList, UserTagConfig } from '../../main/ets/hippo/ehviewer/client/data/UserTag';
import { Announcer } from '../../main/ets/hippo/scene/Announcer';
import { SettingsHeaders, SettingsHeader } from '../../main/ets/hippo/ehviewer/ui/fragment/SettingsHeaders';
import {
  SettingsActivity, SettingsScreenSpec, EhActivityHost,
  THEME_LIGHT, THEME_DARK, THEME_BLACK,
  STYLE_SETTINGS, STYLE_SETTINGS_DARK, STYLE_SETTINGS_BLACK,
  REQUEST_CODE_FRAGMENT, RESULT_OK
} from '../../main/ets/hippo/ehviewer/ui/SettingsActivity';
import {
  SplashActivity, SplashNavigation, SplashParams, PageScheduler, NewsFetcher, NewsCallback,
  EventPaneShower, SplashNewsCallback, setShowEhEventsProvider, SPLASH_PAGE_ID, STYLE_SPLASH, KEY_RESTART
} from '../../main/ets/hippo/ehviewer/ui/splash/SplashActivity';
import { EhActivity } from '../../main/ets/hippo/ehviewer/ui/EhActivity';
import { EhNewsDetail } from '../../main/ets/hippo/ehviewer/client/data/EhNewsDetail';
import {
  GetGalleryDetailListener, GalleryDetailCallbackHost, GalleryDetailSceneCallbacks,
  RESULT_DETAIL, RESULT_UPDATE
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/detail/GetGalleryDetailListener';

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

function throws(name: string, fn: () => void, expectSubstring: string): void {
  try {
    fn();
    fails.push(`${name}\n    期望抛出包含「${expectSubstring}」的错误，但没有抛`);
  } catch (e) {
    const msg: string = (e as Error).message;
    if (msg.indexOf(expectSubstring) >= 0) {
      pass++;
    } else {
      fails.push(`${name}\n    抛出了，但消息不含「${expectSubstring}」：${msg}`);
    }
  }
}

// ============================================================ 1) TransitionNameFactory
function testTransitionNameFactory(): void {
  // 前缀逐字一致（上游：`"thumb:" + gid` 等 4 个）
  eq('thumb 前缀', TransitionNameFactory.getThumbTransitionName(1234567), 'thumb:1234567');
  eq('title 前缀', TransitionNameFactory.getTitleTransitionName(1234567), 'title:1234567');
  eq('uploader 前缀', TransitionNameFactory.getUploaderTransitionName(1234567), 'uploader:1234567');
  eq('category 前缀', TransitionNameFactory.getCategoryTransitionName(1234567), 'category:1234567');

  // 4 个名字必须互不相同（否则共享元素会串台）
  const a: string = TransitionNameFactory.getThumbTransitionName(42);
  const b: string = TransitionNameFactory.getTitleTransitionName(42);
  ok('同一 gid 的 4 个转场名互不相同', a !== b &&
    b !== TransitionNameFactory.getUploaderTransitionName(42) &&
    TransitionNameFactory.getUploaderTransitionName(42) !== TransitionNameFactory.getCategoryTransitionName(42));

  // 不同 gid 产生不同名字（这是共享元素的配对前提）
  ok('不同 gid 的 thumb 名不同',
    TransitionNameFactory.getThumbTransitionName(1) !== TransitionNameFactory.getThumbTransitionName(2));

  // 数字字符串化：不能出现小数点/千分位/科学计数法（上游是 Java long 的十进制）
  const big: string = TransitionNameFactory.getThumbTransitionName(1234567);
  ok('整数 gid 的字符串形态不含小数点', big.indexOf('.') < 0);
  ok('整数 gid 的字符串形态不含逗号', big.indexOf(',') < 0);
  ok('整数 gid 的字符串形态不含科学计数法', big.indexOf('e') < 0 && big.indexOf('E') < 0);
  eq('边界常量 GID_SAFE_MAX = 2^53-1', GID_SAFE_MAX, 9007199254740991);
  eq('安全上限内仍能精确字符串化', TransitionNameFactory.getThumbTransitionName(GID_SAFE_MAX),
    'thumb:9007199254740991');
}

// ============================================================ 2) GalleryHolder
function testGalleryHolder(): void {
  const h: GalleryHolder = new GalleryHolder();
  // 默认值：等价"控件存在但未绑定数据"
  eq('默认 thumbUrl 为空串', h.data.thumbUrl, '');
  eq('默认 rating 为 0（number，不是字符串）', h.data.rating, 0);
  eq('默认 favourited=false', h.data.favourited, false);
  eq('默认 downloaded=false', h.data.downloaded, false);

  // 10 个 setter 都要真的写进 data（对应上游 10 个 findViewById 字段）
  h.setThumb('https://TARGET/thumb.jpg');
  h.setTitle('title');
  h.setUploader('uploader');
  h.setRating(4.5);
  h.setCategory('DOUJINSHI');
  h.setPosted('2026-01-02 03:04');
  h.setPages('42');
  h.setSimpleLanguage('CH');
  h.setFavourited(true);
  h.setDownloaded(true);

  eq('setThumb', h.data.thumbUrl, 'https://TARGET/thumb.jpg');
  eq('setTitle', h.data.title, 'title');
  eq('setUploader', h.data.uploader, 'uploader');
  eq('setRating 支持小数', h.data.rating, 4.5);
  eq('setCategory', h.data.category, 'DOUJINSHI');
  // C-7：posted 是**字符串**（上游 GalleryInfo.posted 是 String），不能画成时间戳
  eq('setPosted 保持字符串原样', h.data.posted, '2026-01-02 03:04');
  eq('setPages', h.data.pages, '42');
  eq('setSimpleLanguage', h.data.simpleLanguage, 'CH');
  eq('setFavourited', h.data.favourited, true);
  eq('setDownloaded', h.data.downloaded, true);

  // 传入既有 data 时不应复制（上游是把 itemView 里的引用直接持有）
  const d: GalleryHolderData = new GalleryHolderData();
  d.title = 'preset';
  const h2: GalleryHolder = new GalleryHolder(d);
  eq('构造传入 data 时直接持有该对象', h2.data.title, 'preset');
  h2.setTitle('changed');
  eq('写入反映到同一 data 对象', d.title, 'changed');
}

// ============================================================ 3) SelectItemWithIconAdapter
function testSelectItemWithIconAdapter(): void {
  // 正常构造
  const a: SelectItemWithIconAdapter = new SelectItemWithIconAdapter(['甲', '乙'], ['ic_a', 'ic_b']);
  eq('getCount', a.getCount(), 2);
  eq('getTextAt(0)', a.getTextAt(0), '甲');
  eq('getTextAt(1)', a.getTextAt(1), '乙');
  eq('getIconNameAt(1)', a.getIconNameAt(1), 'ic_b');
  // 上游 getItemId = position.toLong()
  eq('getItemId(0)', a.getItemId(0), 0);
  eq('getItemId(1)', a.getItemId(1), 1);

  // 长度不一致 → 上游 require(count == icons.size) { "Length conflict" }
  throws('长度不一致必须抛 Length conflict', () => {
    new SelectItemWithIconAdapter(['甲'], []);
  }, 'Length conflict');

  // 越界 → 上游 Kotlin Array 越界会抛；这里必须显式抛，不能静默返回空串
  throws('getTextAt 越界抛错', () => { a.getTextAt(2); }, 'out of bounds');
  throws('getTextAt 负数抛错', () => { a.getTextAt(-1); }, 'out of bounds');
  throws('getIconNameAt 越界抛错', () => { a.getIconNameAt(5); }, 'out of bounds');

  // 空列表：count=0 但不应抛
  const empty: SelectItemWithIconAdapter = new SelectItemWithIconAdapter([], []);
  eq('空列表 getCount=0', empty.getCount(), 0);
}

// ============================================================ 4) SubscriptionItemAdapter
function mkUserTag(id: string, name: string, watched: boolean, hidden: boolean): UserTag {
  const t: UserTag = new UserTag();
  t.userTagId = id;
  t.tagName = name;
  t.watched = watched;
  t.hidden = hidden;
  return t;
}

function testSubscriptionItemAdapter(): void {
  const list: UserTagList = new UserTagList();
  const t0: UserTag = mkUserTag('usertag_100', 'full_color', false, false);
  const t1: UserTag = mkUserTag('usertag_200', 'female', true, false);
  const t2: UserTag = mkUserTag('usertag_300', 'male', false, true);
  const t3: UserTag = mkUserTag('usertag_400', 'mixed', true, true);
  list.userTags = [t0, t1, t2, t3];

  const a: SubscriptionItemAdapter = new SubscriptionItemAdapter(list, null, new UserTagConfig());
  eq('getCount', a.getCount(), 4);

  // 上游 getItemId = Long.decode(userTagId.substring(8)) —— 必须与 UserTag.getId() 一致
  eq('getItemId(0) == UserTag.getId()', a.getItemId(0), t0.getId());
  eq('getItemId(0) 实际值', a.getItemId(0), 100);
  eq('getItemId(3) 实际值', a.getItemId(3), 400);

  // 图标：上游是**两个独立 if**（hidden 先设、watched 后设覆盖）
  eq('都不满足 → null', a.resolveStateIconName(0), null);
  eq('仅 watched → 可见图标', a.resolveStateIconName(1), ICON_VISIBILITY);
  eq('仅 hidden → 不可见图标', a.resolveStateIconName(2), ICON_VISIBILITY_OFF);
  // ★ 关键：hidden + watched 同时为真 → **watched 覆盖 hidden**（写成 else-if 就会得到 off，这是回归点）
  eq('hidden 与 watched 同时为真 → watched 覆盖 hidden', a.resolveStateIconName(3), ICON_VISIBILITY);

  // 未开启翻译时 getName 返回原名（UserTagConfig 默认 getShowTagTranslations()=false）
  eq('getLabel 默认不翻译', a.getLabel(1), 'female');
  // 含冒号但翻译关闭 → 仍原名
  const t5: UserTag = mkUserTag('usertag_500', 'language:chinese', false, false);
  const list2: UserTagList = new UserTagList();
  list2.userTags = [t5];
  const a2: SubscriptionItemAdapter = new SubscriptionItemAdapter(list2, null);
  eq('含冒号但翻译关闭 → 原名', a2.getLabel(0), 'language:chinese');

  throws('getItem 越界抛错', () => { a.getItem(9); }, 'out of bounds');
}

// ============================================================ 5) EnterGalleryDetailTransaction
class FakeSceneHost implements GalleryDetailSceneHost {
  scenes: Announcer[] = [];
  asNewUrls: string[] = [];
  updateUrls: string[] = [];

  startScene(announcer: Announcer): void {
    this.scenes.push(announcer);
  }

  startDownloadAsNew(url: string): void {
    this.asNewUrls.push(url);
  }

  startUpdateDownload(url: string): void {
    this.updateUrls.push(url);
  }
}

function testEnterGalleryDetailTransaction(): void {
  // 有缩略图 + 目标是详情页 → 接管，且四套动画齐备
  const t1: EnterGalleryDetailTransaction = new EnterGalleryDetailTransaction('thumb:123');
  const spec1 = t1.buildSpec('GalleryDetailScene');
  ok('有缩略图 + 详情页 → takeOver', spec1.takeOver);
  eq('共享元素名透传', spec1.sharedElementName, 'thumb:123');
  eq('exit 共享元素动画 = trans_move', spec1.exitSharedElementTransition, TRANSITION_MOVE);
  eq('exit 退出动画 = trans_fade', spec1.exitTransition, TRANSITION_FADE);
  eq('enter 共享元素动画 = trans_move', spec1.enterSharedElementTransition, TRANSITION_MOVE);
  eq('enter 进入动画 = trans_fade', spec1.enterTransition, TRANSITION_FADE);

  // ★ 关键回归点：没有缩略图 → 不接管（上游 mThumb == null → return false）
  const t2: EnterGalleryDetailTransaction = new EnterGalleryDetailTransaction('');
  const spec2 = t2.buildSpec('GalleryDetailScene');
  eq('无缩略图 → takeOver=false', spec2.takeOver, false);

  // ★ 关键回归点：目标不是详情页 → 不接管（上游 !(enter instanceof GalleryDetailScene)）
  const spec3 = t1.buildSpec('GalleryListScene');
  eq('非详情页 tag → takeOver=false', spec3.takeOver, false);

  // 自定义 tag 可注入（平台差异：instanceof → tag 判断）
  const t3: EnterGalleryDetailTransaction = new EnterGalleryDetailTransaction('thumb:1', 'MyDetailScene');
  eq('自定义详情页 tag 生效', t3.buildSpec('MyDetailScene').takeOver, true);
  eq('默认 tag 在自定义后失效', t3.buildSpec('GalleryDetailScene').takeOver, false);
}

// ============================================================ 6) GalleryUpdateDialog
function mkGalleryDetail(names: string[], urls: string[]): GalleryDetail {
  const gd: GalleryDetail = new GalleryDetail();
  const arr: NewVersion[] = [];
  for (let i = 0; i < names.length; i++) {
    const v: NewVersion = new NewVersion(names[i], urls[i]);
    arr.push(v);
  }
  gd.newVersions = arr;
  return gd;
}

let announcerCalls: string[] = [];

function mkDialog(host: GalleryDetailSceneHost): GalleryUpdateDialog {
  announcerCalls = [];
  return new GalleryUpdateDialog(host, (url: string): Announcer => {
    announcerCalls.push(url);
    const an: Announcer = new Announcer('GalleryDetailScene');
    return an;
  });
}

function testGalleryUpdateDialog(): void {
  const host: FakeSceneHost = new FakeSceneHost();
  const dlg: GalleryUpdateDialog = mkDialog(host);
  const gd: GalleryDetail = mkGalleryDetail(['v1', 'v2'], ['/u/1', '/u/2']);

  // ① 首次打开：不标 reusedExisting（上游 dialog == null）
  const spec1 = dlg.showSelectDialog(gd);
  eq('单选项文本来自 newVersions[i].versionName', spec1.items, ['v1', 'v2']);
  eq('默认选中项 = -1（上游传 -1）', spec1.checkedIndex, -1);
  eq('首次打开不标 reusedExisting', spec1.reusedExisting, false);

  // ② 同一对象再打开：上游"没有 return" → **先 show 已存在，再照常重建**
  const spec2 = dlg.showSelectDialog(gd);
  eq('同一对象再打开 → reusedExisting=true（上游没写 return）', spec2.reusedExisting, true);
  eq('重建后选项依然完整（说明确实重建了）', spec2.items, ['v1', 'v2']);

  // ③ 选中某项 → dismiss + 解析 announcer + startScene
  eq('selectVersion(1) 返回 true', dlg.selectVersion(1), true);
  eq('被解析的 versionUrl 正确', announcerCalls, ['/u/2']);
  eq('startScene 被调用 1 次', host.scenes.length, 1);

  // 越界 index → 返回 false（不静默、不抛）
  eq('selectVersion 越界返回 false', dlg.selectVersion(5), false);
  eq('selectVersion 负数返回 false', dlg.selectVersion(-1), false);

  // ④ 三按钮对话框
  const choose1 = dlg.showChooseDialog('/d/1');
  eq('取消按钮文案键存在', typeof choose1.neutralButtonText !== 'undefined', true);
  eq('首次打开 choose 不标 reusedExisting', choose1.reusedExisting, false);
  const choose2 = dlg.showChooseDialog('/d/2');
  eq('再次打开 choose → reusedExisting=true（上游没写 return）', choose2.reusedExisting, true);

  // ⑤ autoDownload 只在"另存为新"置 true，且不重置
  eq('初始 autoDownload=false', dlg.autoDownload, false);
  dlg.onChooseDownloadAsNew();
  eq('另存为new → autoDownload=true', dlg.autoDownload, true);
  eq('另存为new → startDownloadAsNew 收到最近一次 url', host.asNewUrls, ['/d/2']);
  dlg.onChooseOverrideOld();
  eq('覆盖旧 → startUpdateDownload 收到最近一次 url', host.updateUrls, ['/d/2']);
  eq('覆盖旧**不重置** autoDownload（上游如此）', dlg.autoDownload, true);

  // 取消：不触发任何 scene 方法
  const beforeAsNew: number = host.asNewUrls.length;
  const beforeUpdate: number = host.updateUrls.length;
  dlg.onChooseCancel();
  eq('取消不触发 startDownloadAsNew', host.asNewUrls.length, beforeAsNew);
  eq('取消不触发 startUpdateDownload', host.updateUrls.length, beforeUpdate);
}


/** SettingsActivity 的测试宿主（记录调用，便于断言） */
class FakeActivityHost implements EhActivityHost {
  titles: TitleCall[] = [];
  upIndicators: string[] = [];
  backCalls: number = 0;
  results: number[] = [];

  setActionBarUpIndicator(drawableComponent: string, descriptionRes: number): void {
    this.upIndicators.push(drawableComponent);
  }

  setTitle(title: string, isResource: boolean): void {
    this.titles.push(new TitleCall(title, isResource));
  }

  onBackPressed(): void {
    this.backCalls++;
  }

  setResult(resultCode: number): void {
    this.results.push(resultCode);
  }
}

class TitleCall {
  title: string;
  isResource: boolean;

  constructor(title: string, isResource: boolean) {
    this.title = title;
    this.isResource = isResource;
  }
}

// ============================================================ 7) SettingsHeaders + SettingsActivity（S0207 / S0270）
function testSettingsHeaders(): void {
  const headers: SettingsHeaders = new SettingsHeaders(null);
  const table: SettingsHeader[] = headers.onCreatePreferences();

  // ① 表项数与上游一致：settings_headers.xml 有 6 个 BasePreference
  eq('表项数 = 6（上游 settings_headers.xml 6 项）', table.length, 6);

  // ③ 顺序与上游一致（设置页分组顺序）
  eq('顺序：eh → read → download → privacy → advanced → about',
    table.map((h: SettingsHeader): string => h.titleKey),
    ['app.string.settings_eh', 'app.string.settings_read', 'app.string.settings_download',
      'app.string.settings_privacy', 'app.string.settings_advanced', 'app.string.settings_about']);

  // 图标组件名与上游 drawable 一一对应（本仓库已迁成组件）
  eq('图标：6 项各有独立组件名',
    table.map((h: SettingsHeader): string => h.iconComponent),
    ['v_sad_panda_primary_x24', 'v_book_open_primary_x24', 'v_download_primary_x24',
      'v_sec_primary_x24', 'v_adb_primary_x24', 'v_info_primary_x24']);

  // allowDividerAbove：第 1 项 false，其余 true（上游 XML 差异）
  eq('第 1 项 allowDividerAbove=false', table[0].allowDividerAbove, false);
  ok('第 2–6 项 allowDividerAbove=true',
    table.slice(1).every((h: SettingsHeader): boolean => h.allowDividerAbove));

  // fragment 全类名（分组标识）
  eq('第 1 项 fragment = EhFragment',
    table[0].fragmentClass, 'com.hippo.ehviewer.ui.fragment.EhFragment');
  ok('6 项 fragment 互不相同',
    new Set(table.map((h: SettingsHeader): string => h.fragmentClass)).size === 6);

  // ② 资源键形态（能否解析由 scripts/check_resource_keys.ps1 校验 strings.json，见该脚本注释）
  ok('6 个 titleKey 都是 app.string. 前缀',
    table.every((h: SettingsHeader): boolean => h.titleKey.indexOf('app.string.') === 0));
}

function testSettingsActivity(): void {
  const host: FakeActivityHost = new FakeActivityHost();
  const act: SettingsActivity = new SettingsActivity(host);

  // 主题映射（纯函数）
  eq('THEME_LIGHT → AppTheme_Settings', act.getThemeResId(THEME_LIGHT), STYLE_SETTINGS);
  eq('THEME_DARK → AppTheme_Settings_Dark', act.getThemeResId(THEME_DARK), STYLE_SETTINGS_DARK);
  eq('THEME_BLACK → AppTheme_Settings_Black', act.getThemeResId(THEME_BLACK), STYLE_SETTINGS_BLACK);
  eq('未知主题走 default（= LIGHT，上游如此）', act.getThemeResId(999), STYLE_SETTINGS);

  // onCreate：首次创建挂首屏
  const spec1: SettingsScreenSpec = act.onCreate(true);
  eq('布局名 = activity_settings', spec1.layoutName, 'activity_settings');
  eq('up indicator 组件 = v_arrow_left_dark_x24', spec1.upIndicatorComponent, 'v_arrow_left_dark_x24');
  eq('首屏 header 表 6 项', spec1.headers.length, 6);
  eq('首次创建后 headersAttached=true', act.isHeadersAttached(), true);
  ok('onCreate 设置了标题（settings 键，资源形态）',
    host.titles.length > 0 && host.titles[0].title === 'app.string.settings' && host.titles[0].isResource);
  eq('onCreate 传了 up indicator',
    host.upIndicators.length, 1);

  // onCreate：重建（savedInstanceState != null）不重挂，但表仍然渲染
  const act2: SettingsActivity = new SettingsActivity(host);
  const spec2: SettingsScreenSpec = act2.onCreate(false);
  eq('重建后 headersAttached=false（不重挂）', act2.isHeadersAttached(), false);
  eq('重建后仍渲染 6 项（表是常量）', spec2.headers.length, 6);

  // onOptionsItemSelected：home → back + true；其它 → false（交给 super）
  const backBefore: number = host.backCalls;
  eq('home 返回 true', act.onOptionsItemSelected('android.R.id.home'), true);
  eq('home 触发 onBackPressed', host.backCalls, backBefore + 1);
  eq('其它菜单项返回 false（交给 super）', act.onOptionsItemSelected('menu_settings'), false);
  eq('其它菜单项不触发 back', host.backCalls, backBefore + 1);

  // onActivityResult：requestCode=0 + RESULT_OK → 上抛 RESULT_OK；requestCode=0 其它 → **什么都不做也不调 super**
  const resBefore: number = host.results.length;
  eq('requestCode=0 + RESULT_OK → 已处理', act.onActivityResult(REQUEST_CODE_FRAGMENT, RESULT_OK), true);
  eq('上抛 RESULT_OK', host.results[host.results.length - 1], RESULT_OK);
  eq('requestCode=0 + 非 OK → 仍算已处理（不调 super）',
    act.onActivityResult(REQUEST_CODE_FRAGMENT, 0), true);
  eq('非 OK 时不再 setResult', host.results.length, resBefore + 1);
  eq('其它 requestCode → 交给 super', act.onActivityResult(9, RESULT_OK), false);

  // setSettingsTitle 两个重载：结果一致（只是作用对象不同，见文件头「关键行为」1）
  act.setSettingsTitle('app.string.settings_about', true);
  act.setSettingsTitle('纯文本标题', false);
  const last: TitleCall = host.titles[host.titles.length - 1];
  eq('CharSequence 重载透传文本', last.title, '纯文本标题');
  eq('CharSequence 重载 isResource=false', last.isResource, false);
}

// ============================================================ 8) SplashActivity（S0271）
class FakeScheduler implements PageScheduler {
  ranWork: boolean = false;
  doneCalls: number = 0;

  runThenOnUiThread(work: () => void, done: () => void): void {
    work();
    this.ranWork = true;
    done();
    this.doneCalls++;
  }
}

class FakeNewsFetcher implements NewsFetcher {
  callbacks: NewsCallback[] = [];
  fetchCalls: number = 0;

  fetch(callback: NewsCallback): void {
    this.fetchCalls++;
    this.callbacks.push(callback);
  }
}

class FakeEventPane implements EventPaneShower {
  shown: number = 0;

  showEventPane(detail: EhNewsDetail): void {
    this.shown++;
  }
}

function testSplashActivity(): void {
  // ① getThemeResId 忽略参数，恒 SplashTheme
  const fetcher0: FakeNewsFetcher = new FakeNewsFetcher();
  const pane0: FakeEventPane = new FakeEventPane();
  const act0: SplashActivity = new SplashActivity(fetcher0, pane0);
  eq('THEME 0 → SplashTheme', act0.getThemeResId(0), STYLE_SPLASH);
  eq('THEME 1 → 仍 SplashTheme（忽略参数）', act0.getThemeResId(1), STYLE_SPLASH);
  eq('THEME 2 → 仍 SplashTheme', act0.getThemeResId(2), STYLE_SPLASH);

  // ② 普通启动：不清栈、透传 restart=false、跳转后 finish 自己
  setShowEhEventsProvider(() => false);   // 先关新闻，聚焦跳转
  const fetcher: FakeNewsFetcher = new FakeNewsFetcher();
  const pane: FakeEventPane = new FakeEventPane();
  const act: SplashActivity = new SplashActivity(fetcher, pane);
  const sch: FakeScheduler = new FakeScheduler();
  const nav: SplashNavigation = act.onCreate(new SplashParams(false), sch);
  eq('目标页 = MainActivity', nav.targetPage, 'MainActivity');
  eq('非 restart → 不清栈', nav.clearTask, false);
  eq('非 restart → 不透传 restart', nav.passRestart, false);
  eq('跳转后 finish 自己', nav.finishSelf, true);
  eq('调度器执行了耗时任务', sch.ranWork, true);
  eq('调度器回到 UI 线程一次', sch.doneCalls, 1);
  eq('已完成跳转', act.isNavigated(), true);
  eq('页面已注册（D-051）', EhActivity.isPageAlive(SPLASH_PAGE_ID), true);
  // 关闭事件 → 不拉新闻
  eq('关闭 showEhEvents → 不拉新闻', fetcher.fetchCalls, 0);
  eq('未尝试拉新闻', act.isNewsAttempted(), false);

  // ③ restart=true → 清栈 + 透传
  const act2: SplashActivity = new SplashActivity(new FakeNewsFetcher(), new FakeEventPane());
  const nav2: SplashNavigation = act2.onCreate(new SplashParams(true), new FakeScheduler());
  eq('restart → 清栈', nav2.clearTask, true);
  eq('restart → 透传 restart', nav2.passRestart, true);

  // ④ 打开事件 → 拉新闻；成功非 null → showEventPane
  setShowEhEventsProvider(() => true);
  const fetcher3: FakeNewsFetcher = new FakeNewsFetcher();
  const pane3: FakeEventPane = new FakeEventPane();
  const act3: SplashActivity = new SplashActivity(fetcher3, pane3);
  act3.onCreate(new SplashParams(false), new FakeScheduler());
  eq('打开 showEhEvents → 拉新闻一次', fetcher3.fetchCalls, 1);
  eq('拉新闻后仍未标记（等回调）', act3.isNewsAttempted(), false);
  const detail: EhNewsDetail = new EhNewsDetail();
  fetcher3.callbacks[0].onSuccess(detail);
  eq('onSuccess 标记已尝试', act3.isNewsAttempted(), true);
  eq('onSuccess 非 null → 显示事件', pane3.shown, 1);

  // ⑤ onSuccess(null) → 也标记"已尝试"，但不显示
  const fetcher4: FakeNewsFetcher = new FakeNewsFetcher();
  const pane4: FakeEventPane = new FakeEventPane();
  const act4: SplashActivity = new SplashActivity(fetcher4, pane4);
  act4.onCreate(new SplashParams(false), new FakeScheduler());
  fetcher4.callbacks[0].onSuccess(null);
  eq('onSuccess(null) 仍标记已尝试（顺序不能反）', act4.isNewsAttempted(), true);
  eq('onSuccess(null) 不显示事件', pane4.shown, 0);

  // ⑥ 失败/取消 → 也标记"已尝试"（上游三条回调都置位）
  const act5: SplashActivity = new SplashActivity(fetcher4, pane4);
  fetcher4.callbacks.length = 0;
  setShowEhEventsProvider(() => true);
  act5.onCreate(new SplashParams(false), new FakeScheduler());
  fetcher4.callbacks[fetcher4.callbacks.length - 1].onFailure(new Error('x'));
  eq('onFailure 标记已尝试', act5.isNewsAttempted(), true);
  const act6: SplashActivity = new SplashActivity(fetcher4, pane4);
  act6.onCreate(new SplashParams(false), new FakeScheduler());
  fetcher4.callbacks[fetcher4.callbacks.length - 1].onCancel();
  eq('onCancel 标记已尝试', act6.isNewsAttempted(), true);

  // ⑦ onDestroy → 注销页面
  act.onDestroy();
  eq('onDestroy 后页面不再存活', EhActivity.isPageAlive(SPLASH_PAGE_ID), false);
}

// ============================================================ 9) GetGalleryDetailListener（S0234）
class FakeDetailHost implements GalleryDetailCallbackHost {
  removed: number = 0;
  cachedGids: number[] = [];
  historyCalls: number = 0;
  tagsSyncCalls: number = 0;

  removeGlobalStuff(listener: Object): void {
    this.removed++;
  }

  putGalleryDetailCache(gid: number, detail: GalleryDetail): void {
    this.cachedGids.push(gid);
  }

  putHistoryInfo(detail: GalleryDetail): Promise<void> {
    this.historyCalls++;
    return Promise.resolve();
  }

  startTagsSync(detail: GalleryDetail): void {
    this.tagsSyncCalls++;
  }
}

class FakeDetailScene implements GalleryDetailSceneCallbacks {
  successCalls: number = 0;
  failureCalls: number = 0;
  updateFailureCalls: number = 0;
  lastError: string = '';

  onGetGalleryDetailSuccess(result: GalleryDetail): void {
    this.successCalls++;
  }

  onGetGalleryDetailFailure(error: Error): void {
    this.failureCalls++;
    this.lastError = error.message;
  }

  onGetGalleryDetailUpdateFailure(error: Error): void {
    this.updateFailureCalls++;
    this.lastError = error.message;
  }
}

function testGetGalleryDetailListener(): void {
  // RESULT_DETAIL = 1 / RESULT_UPDATE = 0（上游反直觉，断言钉住）
  eq('RESULT_DETAIL = 1', RESULT_DETAIL, 1);
  eq('RESULT_UPDATE = 0', RESULT_UPDATE, 0);

  // ① onSuccess 正常路径：清理 → 缓存 → 历史 → 标签同步 → 通知
  const host: FakeDetailHost = new FakeDetailHost();
  const scene: FakeDetailScene = new FakeDetailScene();
  const l1: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_DETAIL, 'detail');
  const gd: GalleryDetail = new GalleryDetail();
  gd.gid = 1234567;
  gd.title = 'Some Title';
  gd.titleJpn = '';
  l1.onSuccess(gd, host, scene);
  eq('onSuccess 清理全局登记 1 次', host.removed, 1);
  eq('onSuccess 写缓存（gid）', host.cachedGids, [1234567]);
  eq('onSuccess 加历史 1 次', host.historyCalls, 1);
  eq('onSuccess 起标签同步 1 次', host.tagsSyncCalls, 1);
  eq('onSuccess 通知场景 1 次', scene.successCalls, 1);

  // ② onSuccess(null)：**仍清理**，但其余四步都不做（顺序不能反）
  const host2: FakeDetailHost = new FakeDetailHost();
  const scene2: FakeDetailScene = new FakeDetailScene();
  const l2: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_DETAIL, 'detail');
  l2.onSuccess(null, host2, scene2);
  eq('onSuccess(null) 仍清理（清理在 null 判断之前）', host2.removed, 1);
  eq('onSuccess(null) 不写缓存', host2.cachedGids.length, 0);
  eq('onSuccess(null) 不加历史', host2.historyCalls, 0);
  eq('onSuccess(null) 不起标签同步', host2.tagsSyncCalls, 0);
  eq('onSuccess(null) 不通知场景', scene2.successCalls, 0);

  // ③ onSuccess 且 scene 为 null：前四步照做，只跳过通知
  const host3: FakeDetailHost = new FakeDetailHost();
  const l3: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_DETAIL, 'detail');
  l3.onSuccess(gd, host3, null);
  eq('scene=null 时仍写缓存', host3.cachedGids, [1234567]);
  eq('scene=null 时仍加历史', host3.historyCalls, 1);
  eq('scene=null 时仍起标签同步', host3.tagsSyncCalls, 1);

  // ④ onFailure + RESULT_DETAIL → onGetGalleryDetailFailure（不碰 updateFailure）
  const host4: FakeDetailHost = new FakeDetailHost();
  const scene4: FakeDetailScene = new FakeDetailScene();
  const l4: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_DETAIL, 'detail');
  l4.onFailure(new Error('boom'), host4, scene4);
  eq('onFailure 清理 1 次', host4.removed, 1);
  eq('RESULT_DETAIL → onGetGalleryDetailFailure', scene4.failureCalls, 1);
  eq('RESULT_DETAIL → 不走 updateFailure', scene4.updateFailureCalls, 0);
  eq('错误消息透传', scene4.lastError, 'boom');

  // ⑤ onFailure + RESULT_UPDATE → onGetGalleryDetailUpdateFailure
  const host5: FakeDetailHost = new FakeDetailHost();
  const scene5: FakeDetailScene = new FakeDetailScene();
  const l5: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_UPDATE, 'detail');
  l5.onFailure(new Error('upd'), host5, scene5);
  eq('RESULT_UPDATE → onGetGalleryDetailUpdateFailure', scene5.updateFailureCalls, 1);
  eq('RESULT_UPDATE → 不走 failure', scene5.failureCalls, 0);

  // ⑥ onFailure 且 scene 为 null → 只清理
  const host6: FakeDetailHost = new FakeDetailHost();
  const l6: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_DETAIL, 'detail');
  l6.onFailure(new Error('x'), host6, null);
  eq('scene=null 的 onFailure 仍清理', host6.removed, 1);

  // ⑦ onCancel → 仅清理
  const host7: FakeDetailHost = new FakeDetailHost();
  const l7: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_DETAIL, 'detail');
  l7.onCancel(host7);
  eq('onCancel 清理 1 次', host7.removed, 1);
  eq('onCancel 不做其它副作用', host7.cachedGids.length + host7.historyCalls + host7.tagsSyncCalls, 0);

  // ⑧ isInstance：null → false；匹配 tag → true；不匹配 → false
  eq('isInstance(null) = false', l1.isInstance(null), false);
  eq('isInstance(详情页 tag) = true', l1.isInstance('GalleryDetailScene'), true);
  eq('isInstance(其它 tag) = false', l1.isInstance('GalleryListScene'), false);
  const l8: GetGalleryDetailListener = new GetGalleryDetailListener(RESULT_DETAIL, 'x', 'MyDetail');
  eq('自定义详情页 tag 生效', l8.isInstance('MyDetail'), true);
  eq('默认详情页 tag 在自定义后失效', l8.isInstance('GalleryDetailScene'), false);

  // ⑨ newPath 纯函数：gid + "-" + 合适标题，经 sanitizeFilename
  const gd9: GalleryDetail = new GalleryDetail();
  gd9.gid = 987654;
  gd9.title = 'Hello World';
  gd9.titleJpn = '';
  eq('newPath 基本形态', l1.newPath(gd9), '987654-Hello World');
  // 非法文件名字符会被 sanitizeFilename 处理（具体替换规则由 FileUtils 决定，这里只断言"不含斜杠"）
  const gd10: GalleryDetail = new GalleryDetail();
  gd10.gid = 1;
  gd10.title = 'a/b:c';
  gd10.titleJpn = '';
  const p10: string = l1.newPath(gd10);
  ok('newPath 结果不含路径分隔符', p10.indexOf('/') < 0);
  ok('newPath 以 gid 开头', p10.indexOf('1-') === 0 || p10.indexOf('1') === 0);
}
// ============================================================ 入口
function main(): void {
  testTransitionNameFactory();
  testGalleryHolder();
  testSelectItemWithIconAdapter();
  testSubscriptionItemAdapter();
  testEnterGalleryDetailTransaction();
  testGalleryUpdateDialog();
  testSettingsHeaders();
  testSettingsActivity();
  testSplashActivity();
  testGetGalleryDetailListener();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('ui-scene batch test failed');
  }
  console.log(`✓ ui-scene 接手批: ${pass} 条断言全部通过`);
}

main();




