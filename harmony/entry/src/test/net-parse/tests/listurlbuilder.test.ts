// ListUrlBuilder golden URL 测试 —— 给定 builder 状态 → 断言期望 URL 串
// 覆盖 7 种 mode + f_cats 位运算 + 关键词编码 + 翻页 + 高级搜索位组合 + 上游怪异行为
import { ListUrlBuilder } from './ListUrlBuilder';
import { AdvanceSearchFlags, CategoryFlags } from './Flags';
import { EhUrl } from '../EhUrl';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: string, expected: string): void {
  if (actual === expected) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${actual}\n    expected= ${expected}`);
  }
}

function eqNum(name: string, actual: number, expected: number): void {
  if (actual === expected) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}: actual=${actual} expected=${expected}`);
  }
}

// ---------- 0. 站点常量（SITE_E 默认） ----------
eq('host', EhUrl.getHost(), 'https://e-hentai.org/');
eq('referer', EhUrl.getReferer(), 'https://e-hentai.org');
eq('origin', EhUrl.getOrigin(), 'https://e-hentai.org');
eq('apiUrl', EhUrl.getApiUrl(), 'https://e-hentai.org/api.php');
eq('favorites', EhUrl.getFavoritesUrl(), 'https://e-hentai.org/favorites.php');
eq('watched', EhUrl.getWatchedUrl(), 'https://e-hentai.org/watched');
eq('mytags', EhUrl.getMyTagsUrl(), 'https://e-hentai.org/mytags');
eq('uconfig', EhUrl.getUConfigUrl(), 'https://e-hentai.org/uconfig.php');
eq('popular', EhUrl.getPopularUrl(), 'https://e-hentai.org/popular');
eq('toplist（恒 E 站）', EhUrl.getTopListUrl(), 'https://e-hentai.org/toplist.php');
eq('imageSearch', EhUrl.getImageSearchUrl(), 'https://upld.e-hentai.org/image_lookup.php');
eq('thumbPrefix（恒 ehgt）', EhUrl.getThumbUrlPrefix(), 'https://ehgt.org/');

// ---------- 1. MODE_NORMAL 基础 ----------
{
  const b = new ListUrlBuilder();
  eq('normal 空状态', b.build(), 'https://e-hentai.org/');
}

{
  const b = new ListUrlBuilder();
  b.setCategory(CategoryFlags.DOUJINSHI | CategoryFlags.MANGA);
  // f_cats = (~category) & ALL_CATEGORY = (~0x6) & 0x3ff = 0x3f9 = 1017
  eq('normal 分类位取反', b.build(), 'https://e-hentai.org/?f_cats=1017');
}

{
  const b = new ListUrlBuilder();
  b.setKeyword('love live');
  // Java URLEncoder：空格 → '+'
  eq('normal 关键词编码（空格→+）', b.build(), 'https://e-hentai.org/?f_search=love+live');
}

{
  const b = new ListUrlBuilder();
  b.setKeyword('中文');
  eq('normal 关键词编码（UTF-8）', b.build(), 'https://e-hentai.org/?f_search=%E4%B8%AD%E6%96%87');
}

{
  const b = new ListUrlBuilder();
  b.setKeyword('   ');
  eq('normal 空白关键词被丢弃', b.build(), 'https://e-hentai.org/');
}

{
  const b = new ListUrlBuilder();
  b.setPageIndex(3);
  eq('normal 翻页', b.build(), 'https://e-hentai.org/?page=3');
}

{
  const b = new ListUrlBuilder();
  b.setCategory(CategoryFlags.NONE); // -1 → 不输出 f_cats
  b.setPageIndex(1);
  eq('normal NONE 不输出 f_cats', b.build(), 'https://e-hentai.org/?page=1');
}

// ---------- 2. 高级搜索位 ----------
{
  const b = new ListUrlBuilder();
  b.setAdvanceSearch(AdvanceSearchFlags.SNAME | AdvanceSearchFlags.STAGS); // 默认 0x3
  eq('advsearch 默认两项',
    b.build(),
    'https://e-hentai.org/?advsearch=1&f_sname=on&f_stags=on');
}

{
  const b = new ListUrlBuilder();
  b.setAdvanceSearch(AdvanceSearchFlags.SNAME | AdvanceSearchFlags.SDT1 | AdvanceSearchFlags.SDT2 | AdvanceSearchFlags.SFT);
  b.setMinRating(3);
  eq('advsearch 全位组合 + 最低评分',
    b.build(),
    'https://e-hentai.org/?advsearch=1&f_sname=on&f_sdt1=on&f_sdt2=on&f_sft=on&f_sr=on&f_srdd=3');
}

{
  const b = new ListUrlBuilder();
  b.setAdvanceSearch(AdvanceSearchFlags.SNAME);
  b.setPageFrom(2);
  b.setPageTo(10);
  eq('advsearch 页数区间',
    b.build(),
    'https://e-hentai.org/?advsearch=1&f_sname=on&f_sp=on&f_spf=2&f_spt=10');
}

{
  const b = new ListUrlBuilder();
  b.setAdvanceSearch(AdvanceSearchFlags.SNAME);
  b.setPageFrom(5);
  b.setPageTo(-1);
  eq('advsearch 只有下界（f_spt 为空串）',
    b.build(),
    'https://e-hentai.org/?advsearch=1&f_sname=on&f_sp=on&f_spf=5&f_spt=');
}

// ---------- 3. MODE_UPLOADER / MODE_TAG（页码是路径段） ----------
{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_UPLOADER);
  b.setKeyword('some uploader');
  eq('uploader 无翻页',
    b.build(),
    'https://e-hentai.org/uploader/some+uploader');
}

{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_UPLOADER);
  b.setKeyword('some uploader');
  b.setPageIndex(2);
  eq('uploader 有翻页（路径段）',
    b.build(),
    'https://e-hentai.org/uploader/some+uploader/2');
}

{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_TAG);
  b.setKeyword('language:chinese$');
  eq('tag 关键词',
    b.build(),
    'https://e-hentai.org/tag/language%3Achinese%24');
}

// ---------- 4. MODE_FILTER（先 '?' 再拼） ----------
{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_FILTER);
  b.setKeyword('a b');
  eq('filter 无翻页',
    b.build(),
    'https://e-hentai.org/?f_search=a+b');
}

{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_FILTER);
  b.setKeyword('a b');
  b.setPageIndex(2);
  eq('filter 有翻页（page 在 f_search 之前）',
    b.build(),
    'https://e-hentai.org/?page=2&f_search=a+b');
}

// ---------- 5. MODE_WHATS_HOT / MODE_IMAGE_SEARCH ----------
{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_WHATS_HOT);
  eq('whats hot', b.build(), 'https://e-hentai.org/popular');
}

{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_IMAGE_SEARCH);
  eq('image search', b.build(), 'https://upld.e-hentai.org/image_lookup.php');
}

// ---------- 6. MODE_TOP_LIST（含上游哨兵值 127.0.0.1:8888） ----------
{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_TOP_LIST);
  b.setFollow('tl=15');
  eq('toplist 首页', b.build(), 'https://e-hentai.org/toplist.php?tl=15');
}

{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_TOP_LIST);
  b.setFollow('tl=15');
  b.setPageIndex(3);
  eq('toplist 翻页', b.build(), 'https://e-hentai.org/toplist.php?tl=15&p=3');
}

{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_TOP_LIST);
  b.setFollow('tl=15');
  b.setPageIndex(200);
  eq('toplist 越界返回哨兵值（上游行为）', b.build(), '127.0.0.1:8888');
}

// ---------- 7. MODE_SUBSCRIPTION（watched） ----------
{
  const b = new ListUrlBuilder();
  b.setMode(ListUrlBuilder.MODE_SUBSCRIPTION);
  b.setKeyword('x');
  eq('subscription 走 watched',
    b.build(),
    'https://e-hentai.org/watched?f_search=x');
}

// ---------- 8. setQuery 反解析 ----------
{
  const b = new ListUrlBuilder();
  b.setQuery('f_cats=1017&f_search=love+live&page=2');
  eqNum('setQuery category', b.getCategory(), CategoryFlags.DOUJINSHI | CategoryFlags.MANGA);
  eq('setQuery keyword', b.getKeyword() as string, 'love live');
  // setQuery 不解析 page（上游 TODO page），故 pageIndex 仍为 0
  eqNum('setQuery 不恢复 page（上游 TODO）', b.getPageIndex(), 0);
}

{
  const b = new ListUrlBuilder();
  b.setQuery('advsearch=1&f_sname=on&f_stags=on&f_sr=on&f_srdd=4&f_sp=on&f_spf=1&f_spt=9');
  eqNum('setQuery advanceSearch', b.getAdvanceSearch(), AdvanceSearchFlags.SNAME | AdvanceSearchFlags.STAGS);
  eqNum('setQuery minRating', b.getMinRating(), 4);
  eqNum('setQuery pageFrom', b.getPageFrom(), 1);
  eqNum('setQuery pageTo', b.getPageTo(), 9);
}

{
  const b = new ListUrlBuilder();
  b.setQuery('f_search=%E4%B8%AD%E6%96%87');
  eq('setQuery 关键词解码', b.getKeyword() as string, '中文');
}

{
  const b = new ListUrlBuilder();
  b.setQuery('advsearch=0');
  eqNum('setQuery 未开高级搜索 → -1', b.getAdvanceSearch(), -1);
}

// ---------- 9. 往返：setQuery(build() 的 query) 应还原关键状态 ----------
{
  const b = new ListUrlBuilder();
  b.setCategory(CategoryFlags.MISC | CategoryFlags.WESTERN);
  b.setKeyword('a b');
  b.setAdvanceSearch(AdvanceSearchFlags.STAGS);
  const url = b.build();
  const q = url.substring(url.indexOf('?') + 1);
  const b2 = new ListUrlBuilder();
  b2.setQuery(q);
  eqNum('往返 category', b2.getCategory(), b.getCategory());
  eq('往返 keyword', b2.getKeyword() as string, 'a b');
  eqNum('往返 advanceSearch', b2.getAdvanceSearch(), b.getAdvanceSearch());
}

// ---------- 10. jumpHrefBuild ----------
{
  const b = new ListUrlBuilder();
  eq('jump 替换 seek',
    b.jumpHrefBuild('https://e-hentai.org/?seek=2020-01-02&x=1', 'seek=2021-03-04'),
    'https://e-hentai.org/?seek=2021-03-04&x=1');
  eq('jump 替换 jump',
    b.jumpHrefBuild('https://e-hentai.org/watched?jump=3m', 'jump=5d'),
    'https://e-hentai.org/watched?jump=5d');
  eq('jump 追加',
    b.jumpHrefBuild('https://e-hentai.org/watched', 'jump=1w'),
    'https://e-hentai.org/watched&jump=1w');
}

// ---------- 11. clone / copyFrom / equalKeyWord ----------
{
  const b = new ListUrlBuilder();
  b.setKeyword('k');
  b.setPageIndex(5);
  const c = b.cloneBuilder();
  eq('clone 后 URL 相同', c.build(), b.build());
  c.setPageIndex(6);
  eq('clone 是深拷贝（改副本不影响原件）', b.build(), 'https://e-hentai.org/?f_search=k&page=5');
}

{
  const b = new ListUrlBuilder();
  b.setKeyword('abc');
  eq('equalKeyWord true', '' + b.equalKeyWord('abc'), 'true');
  eq('equalKeyWord false', '' + b.equalKeyWord('abd'), 'false');
  b.setKeyword(null);
  eq('equalKeyWord null 关键词 → false', '' + b.equalKeyWord('abc'), 'false');
}

// ---------- 汇总 ----------
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('golden URL 断言失败：' + fail);
}
