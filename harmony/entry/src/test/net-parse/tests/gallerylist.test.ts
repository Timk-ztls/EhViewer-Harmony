// GalleryListParser 金样本测试
//
// 样本来源声明：**构造样本，非抓取页面**。
// 每个样本都是按上游代码的 DOM 契约手工构造的（ptt 的 cell 布局、glname 的层级、
// glthumb 的 div 嵌套），目的是精确覆盖 parser 的每个分支，而不是模拟真实页面的全部噪声。
//
// 覆盖分支（Lead 要求 6 类）：
//   1) 正常列表项（全字段有值）
//   2) 缺字段项（无 rating / 无 posted / 无 glthumb → 走 gl1e 兜底）
//   3) 语言标签 4 变体（[Chinese] / [漢化] / [中国翻訳] / 无标签）
//   4) 分页信息（ptt 存在：pages + nextPage；searchnav 存在：first/prev/next/last + resultCount）
//   5) 空结果页（"No hits found</p>"）
//   6) 被删画廊（glname 无 <a> → gid/token 保持 0，标题仍是文本，**不跳过**）
// 另加：解析失败行为（parse 吞异常返回空 Result / parseDocument 抛 ParseException 且带 body）
//      + D-025 的「TagSyncHook 未注入必须打 warn」可断言验证

import { GalleryListParser, ListResult, TagSyncHook } from '../parser/GalleryListParser';
import { GalleryInfo } from './GalleryInfo';
import { ParseException } from '../exception/ParseException';
import { GalleryDetailUrlParser } from '../parser/GalleryDetailUrlParser';
import { Jsoup } from '../../../jsoup/index';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

// ---------- warn 捕获（D-025：默认 TagSyncHook 的 warn 必须可断言） ----------
const warns: string[] = [];
const origWarn = console.warn;
console.warn = (...args: unknown[]): void => {
  warns.push(args.map((a) => String(a)).join(' '));
};

// ---------- 样本构造 ----------
function item(opts: {
  gid?: string; token?: string; title: string; withLink?: boolean;
  thumb?: boolean; thumbFallback?: boolean; rating?: string; rated?: boolean;
  posted?: string; slotStyle?: string; uploader?: string; pages?: string;
  category?: string; tags?: string[];
}): string {
  const withLink = opts.withLink !== false;
  const href = `https://e-hentai.org/g/${opts.gid ?? '1234567'}/${opts.token ?? 'abcdef0123'}/`;
  const titleInner = withLink ? `<a href="${href}">${opts.title}</a>` : opts.title;

  let thumbHtml = '';
  if (opts.thumb !== false && !opts.thumbFallback) {
    thumbHtml = `<div class="glthumb"><div><img src="https://ehgt.org/t/1_250.jpg" ` +
      `style="height:350px;width:250px" /></div>` +
      `<div><div><div>${opts.pages ?? '42'} pages</div></div></div></div>`;
  }

  let fallbackHtml = '';
  if (opts.thumbFallback) {
    fallbackHtml = `<div class="gl1e"><img src="https://ehgt.org/f/2_250.jpg" ` +
      `style="height:200px;width:150px" /></div>`;
  }

  const ratingHtml = opts.rating === undefined ? '' :
    `<div class="ir ${opts.rated ? 'irr' : ''}" style="${opts.rating}"></div>`;

  const postedHtml = opts.posted === undefined ? '' :
    `<div id="posted_${opts.gid ?? '1234567'}" style="${opts.slotStyle ?? ''}">${opts.posted}</div>`;

  const uploaderHtml = opts.uploader === undefined ? '' :
    `<div class="glhide"><div><div><a href="/uploader/x">${opts.uploader}</a></div></div>` +
    `<div>${opts.pages ?? '42'} pages</div></div>`;

  const categoryHtml = opts.category === undefined ? '' :
    `<div class="cn">${opts.category}</div>`;

  const tagsHtml = opts.tags === undefined ? '' :
    opts.tags.map((t) => `<div class="gt" title="${t}"></div>`).join('');

  return `<div class="gl1e">${thumbHtml}${fallbackHtml}` +
    `<div class="glink glname">${titleInner}</div>` +
    `${categoryHtml}${postedHtml}${ratingHtml}${uploaderHtml}${tagsHtml}</div>`;
}

function page(ptItems: string[], opts?: { ptt?: boolean; pages?: string; nextPage?: string }): string {
  const withPtt = opts?.ptt !== false;
  const pttHtml = withPtt
    ? `<table class="ptt"><tbody><tr><td><div>1</div><div>2</div><div>3</div></td>` +
      `<td>${opts?.pages ?? '3'}</td>` +
      `<td class="ptdd"><a href="?page=${opts?.nextPage ?? '1'}">next</a></td></tr></tbody></table>`
    : '';
  return `<html><head><title>t</title></head><body>${pttHtml}` +
    `<div class="itg gld">${ptItems.join('')}</div></body></html>`;
}

// ---------- 1. 正常列表项 ----------
{
  const html = page([
    item({
      title: 'Normal Title', rating: 'width:16px;height:16px;background-position:0px -1px;',
      posted: '2020-01-02 03:04', slotStyle: 'background-color:rgba(240,0,0,0.5)',
      uploader: 'up1', pages: '42', category: 'Doujinshi', tags: ['a:b', 'c:d']
    })
  ]);
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('normal.pages', r.pages, 3);
  eq('normal.nextPage', r.nextPage, 1);
  eq('normal.count', r.galleryInfoList.length, 1);
  const gi: GalleryInfo = r.galleryInfoList[0];
  eq('normal.gid', gi.gid, 1234567);
  eq('normal.token', gi.token, 'abcdef0123');
  eq('normal.title', gi.title, 'Normal Title');
  eq('normal.category', gi.category, 0x2); // Doujinshi
  eq('normal.thumbWidth', gi.thumbWidth, 250);
  eq('normal.thumbHeight', gi.thumbHeight, 350);
  eq('normal.pages', gi.pages, 42);
  eq('normal.posted', gi.posted, '2020-01-02 03:04');
  eq('normal.postedAt>0', gi.postedAt > 0, true);
  eq('normal.favoriteSlot（rgba(240,0,0) → slot 1）', gi.favoriteSlot, 1);
  eq('normal.rating（16px → 5-1=4）', gi.rating, 4);
  eq('normal.rated', gi.rated, false);
  eq('normal.uploader', gi.uploader, 'up1');
  eq('normal.tgList', gi.tgList, ['a:b', 'c:d']);
  eq('normal.simpleLanguage（无标签 → null）', gi.simpleLanguage, null);
}

// ---------- 2. 缺字段项（无 rating / 无 posted / 无 glthumb → gl1e 兜底） ----------
{
  const html = page([item({ title: 'Sparse', thumbFallback: true })]);
  const r: ListResult = GalleryListParser.parse(html, 0);
  const gi: GalleryInfo = r.galleryInfoList[0];
  eq('sparse.count', r.galleryInfoList.length, 1);
  eq('sparse.thumb（gl1e 兜底）', gi.thumb, 'https://ehgt.org/f/2_250.jpg');
  eq('sparse.thumbWidth', gi.thumbWidth, 150);
  eq('sparse.thumbHeight', gi.thumbHeight, 200);
  eq('sparse.rating 默认 0', gi.rating, 0);
  eq('sparse.posted 默认空串', gi.posted, '');
  eq('sparse.pages 默认 0', gi.pages, 0);
  eq('sparse.favoriteSlot 默认 -2（本地收藏 hook 返回 false）', gi.favoriteSlot, -2);
  ok('sparse：LocalFavoriteHook 未注入时打了 warn',
    warns.some((w) => w.indexOf('LocalFavoriteHook 未注入') >= 0));
}

// ---------- 3. 语言标签 4 变体 ----------
{
  const html = page([
    item({ gid: '1', token: 'aaaaaaaaaa', title: 'A [Chinese]' }),
    item({ gid: '2', token: 'bbbbbbbbbb', title: 'B [漢化]' }),
    item({ gid: '3', token: 'cccccccccc', title: 'C [中国翻訳]' }),
    item({ gid: '4', token: 'dddddddddd', title: 'D plain' })
  ]);
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('lang.count', r.galleryInfoList.length, 4);
  eq('lang.[Chinese] → ZH', r.galleryInfoList[0].simpleLanguage, 'ZH');
  eq('lang.[漢化] → ZH', r.galleryInfoList[1].simpleLanguage, 'ZH');
  eq('lang.[中国翻訳] → ZH', r.galleryInfoList[2].simpleLanguage, 'ZH');
  eq('lang.无标签 → null', r.galleryInfoList[3].simpleLanguage, null);
}

// ---------- 4a. 分页：ptt 不存在但 searchnav 存在 ----------
{
  const html = `<html><body>` +
    `<div class="searchnav"><a id="uFirst" href="?page=0">first</a>` +
    `<a id="uprev" href="?page=1">prev</a><a id="unext" href="?page=3">next</a>` +
    `<a id="ulast" href="?page=9">last</a></div>` +
    `<div class="searchtext">Found about 1,234 results</div>` +
    `<div class="itg gld">${item({ title: 'Nav Item' })}</div></body></html>`;
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('nav.pages=-1', r.pages, -1);
  eq('nav.nextPage=-1', r.nextPage, -1);
  eq('nav.firstHref', r.firstHref, '?page=0');
  eq('nav.prevHref', r.prevHref, '?page=1');
  eq('nav.nextHref', r.nextHref, '?page=3');
  eq('nav.lastHref', r.lastHref, '?page=9');
  eq('nav.resultCount（about → N+）', r.resultCount, '1,234+');
  eq('nav.count', r.galleryInfoList.length, 1);
}

// ---------- 4b. 分页：无 ptt 无 searchnav → catch 分支 pages=1 ----------
{
  const html = `<html><body><div class="itg gld">${item({ title: 'NoNav' })}</div></body></html>`;
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('nonav.pages=1（上游 catch 分支）', r.pages, 1);
  eq('nonav.count', r.galleryInfoList.length, 1);
  eq('nonav.firstHref 空', r.firstHref, '');
}

// ---------- 5. 空结果页 ----------
{
  const html = `<html><body><p>No hits found</p></body></html>`;
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('empty.pages=0', r.pages, 0);
  eq('empty.count=0', r.galleryInfoList.length, 0);
}

// ---------- 5b. 未关注标签提示 ----------
{
  const html = `<html><body><p>You do not have any watched tags</p>` +
    `<p>No hits found</p></body></html>`;
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('watched.noWatchedTags', r.noWatchedTags, true);
  eq('watched.pages=0', r.pages, 0);
}

// ---------- 6. 被删画廊（glname 无 <a>） ----------
{
  const html = page([item({ title: 'This gallery has been removed', withLink: false })]);
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('removed.count（不跳过）', r.galleryInfoList.length, 1);
  eq('removed.gid=0', r.galleryInfoList[0].gid, 0);
  eq('removed.token 空', r.galleryInfoList[0].token, '');
  eq('removed.title 保留文本', r.galleryInfoList[0].title, 'This gallery has been removed');
}

// ---------- 6b. glname 缺失 → 该项被跳过（title === null） ----------
{
  const html = page([
    `<div class="gl1e"><div class="glthumb"><div><img src="x.jpg" style="height:1px;width:1px" /></div></div></div>`,
    item({ gid: '9', token: 'eeeeeeeeee', title: 'Kept' })
  ]);
  const r: ListResult = GalleryListParser.parse(html, 0);
  eq('nogname.count（跳过无标题项）', r.galleryInfoList.length, 1);
  eq('nogname.kept', r.galleryInfoList[0].title, 'Kept');
}

// ---------- 7. 解析失败行为 ----------
// 7a. 列表区结构性失败（有 ptt 无 itg、无 gltc）→ parseDocument 抛 ParseException 且带 body
{
  const html = `<html><body><table class="ptt"><tbody><tr><td><div>1</div></td><td>1</td>` +
    `<td><a href="?page=1">next</a></td></tr></tbody></table></body></html>`;
  let caught: Error | null = null;
  try {
    GalleryListParser.parseDocument(
      // 直接复用 parse 的 Jsoup 结果不可得，故这里用 parse 验证「吞异常」路径
      Jsoup.parse(html), html, 0);
  } catch (e) {
    caught = e as Error;
  }
  ok('fail.parseDocument 抛异常', caught !== null);
  ok('fail.类型是 ParseException', caught instanceof ParseException);
  ok('fail.带 body', caught !== null && (caught as ParseException).getBody() === html);

  // 7b. parse(String) 吞掉异常 → 空 Result（不抛）
  let threw = false;
  let r: ListResult | null = null;
  try {
    r = GalleryListParser.parse(html, 0);
  } catch (e) {
    threw = true;
  }
  ok('fail.parse 不抛', !threw);
  ok('fail.parse 返回空 Result', r !== null && (r as ListResult).galleryInfoList.length === 0);
}

// ---------- 8. D-025：TagSyncHook 默认实现必须打 warn（可断言） ----------
{
  warns.length = 0;
  const html = page([item({ title: 'Warn Probe' })]);
  GalleryListParser.parse(html, 0);
  ok('D-025：默认 TagSyncHook 打了 warn',
    warns.some((w) => w.indexOf('TagSyncHook 未注入') >= 0 && w.indexOf('D-025') >= 0));
}

// ---------- 9. TagSyncHook 注入后不再 warn ----------
{
  warns.length = 0;
  const seen: number[] = [];
  const hook: TagSyncHook = {
    syncTags: (list: GalleryInfo[]): void => {
      seen.push(list.length);
    }
  };
  GalleryListParser.setTagSyncHook(hook);
  GalleryListParser.parse(page([item({ title: 'Hook Probe' })]), 0);
  eq('hook 被调用一次', seen.length, 1);
  eq('hook 收到 1 项', seen[0], 1);
  ok('hook 注入后无 TagSyncHook warn', warns.every((w) => w.indexOf('TagSyncHook 未注入') < 0));
}

// ---------- 10. parseRating / parseFavoriteSlot 纯函数 ----------
{
  eq('rating 0px → 5', GalleryListParser.parseRating('width:0px;height:16px;width:0px'), '5');
  // 上游公式：rate = 5 - num1/16；num2 == 21 时再 rate-- 并拼 ".5"
  // 16px → rate=4；num2=21 → rate=3 → "3.5"
  eq('rating 16px+21px → 3.5', GalleryListParser.parseRating('width:16px;height:21px;width:16px'), '3.5');
  eq('rating 缺第二个 px → null', GalleryListParser.parseRating('width:16px'), null);
  eq('slot rgba(0,128,0) → 4', GalleryListParser.parseFavoriteSlot('background-color:rgba(0,128,0,0.5)'), 4);
  eq('slot 未知色 → -2', GalleryListParser.parseFavoriteSlot('background-color:rgba(1,2,3,0.5)'), -2);
  eq('slot 无 rgba → -2', GalleryListParser.parseFavoriteSlot('color:red'), -2);
}

// ---------- 11. GalleryDetailUrlParser ----------
{
  const r = GalleryDetailUrlParser.parse('https://exhentai.org/g/1234567/a1b2c3d4e5/');
  ok('detailUrl 解析成功', r !== null);
  eq('detailUrl.gid', r?.gid, 1234567);
  eq('detailUrl.token', r?.token, 'a1b2c3d4e5');
  eq('detailUrl.mpv', GalleryDetailUrlParser.parse('https://e-hentai.org/mpv/42/0123456789/')?.gid, 42);
  eq('detailUrl.非画廊 URL → null', GalleryDetailUrlParser.parse('https://e-hentai.org/tag/x'), null);
  eq('detailUrl.null → null', GalleryDetailUrlParser.parse(null), null);
  eq('detailUrl 宽松模式',
    GalleryDetailUrlParser.parseWithStrict('g/777/aaaaaaaaaa/', false)?.gid, 777);
}

// ---------- 12. 真实 E-Hentai 省略 <tbody> 的 table.itg / table.ptt / glname 标签表 ----------
{
  const realTableHtml = `<html><body>` +
    `<table class="ptt"><tr><td class="ptds"><a href="?page=0">1</a></td><td><a href="?page=1">2</a></td><td class="ptdd"><a href="?page=1">&gt;</a></td></tr></table>` +
    `<table class="itg gltc">` +
    `<tr><th></th><th>Name</th><th>Tags</th><th>Published</th></tr>` +
    `<tr>` +
    `<td class="gl1c glcat"><div class="cn">Doujinshi</div></td>` +
    `<td class="gl2c"><div class="glthumb"><div><img src="https://ehgt.org/t/9_250.jpg" style="height:300px;width:210px" /></div><div><div><div>24 pages</div></div></div></div></td>` +
    `<td class="gl3c glname"><a href="https://e-hentai.org/g/7654321/0123456789/">` +
    `<div class="glink">No Tbody Gallery [Chinese]</div>` +
    `<div><table>` +
    `<tr><td class="tc">artist:</td><td><div class="gt">alice | 爱丽丝</div><div class="gt">bob</div></td></tr>` +
    `<tr><td class="tc">female:</td><td><div class="gt">glasses</div></td></tr>` +
    `</table></div></a></td>` +
    `<td class="gl4c"><div id="posted_7654321" style="">2021-05-06 07:08</div></td>` +
    `</tr>` +
    `</table>` +
    `</body></html>`;
  const r: ListResult = GalleryListParser.parse(realTableHtml, 0);
  eq('无 tbody table.ptt pages=2', r.pages, 2);
  eq('无 tbody table.ptt nextPage=1', r.nextPage, 1);
  eq('无 tbody table.itg 跳过表头解析出 1 项', r.galleryInfoList.length, 1);
  const gi: GalleryInfo = r.galleryInfoList[0];
  eq('无 tbody table.itg gid', gi.gid, 7654321);
  eq('无 tbody table.itg title', gi.title, 'No Tbody Gallery [Chinese]');
  eq('无 tbody glname 标签组（tc + 去冒号 + 去竖线翻译）', gi.simpleTags,
    ['artist:alice', 'artist:bob', 'female:glasses']);
}

// ---------- 汇总 ----------
console.warn = origWarn;
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('GalleryListParser 断言失败：' + fail);
}
