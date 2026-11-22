// GalleryDetailParser 金样本测试
//
// 样本来源声明：**构造样本，非抓取页面**。全部按上游代码的 DOM 契约手工构造
// （gdd 的 table>tbody>tr 三层、taglist 的 table>tbody>tr、cdiv 的 .c1 结构、
//  gdtm/gdtl 的 title 属性格式），目的是精确覆盖每条解析分支。
//
// 覆盖：
//   1) 四种「非正常页」：offensive / pining / unavailable / #d>p 错误信息
//   2) parseDetail 主字段：gid/token/apiUid/apiKey、torrent、archive、封面、标题、分类、上传者
//   3) #gdd 的 7 类 key-value（Posted/Parent/Visible/Language/File Size/Length/Favorited×3）
//   4) 评分三态（Not Yet Rated → -1；无空格 → 0；Average: 4.5 → 4.5）+ 评分人数 + 收藏状态
//   5) 新版本列表（#gnd：有链接/无 gnd）
//   6) 标签组：DOM 版 + 正则版（含 `tag|alias` 取竖线前）
//   7) 评论：DOM 版（Vote+/Vote-/Edit/score/voteState/lastEdited 的上游 bug）+ 正则版 + 黑名单 hook warn
//   8) 预览页数：DOM 版 + 正则版（含 ≤0 → ParseException）
//   9) 预览集：small/normal 两套正则 + 空 → new NormalPreviewSet()
//  10) 失败行为：PATTERN_DETAIL 不匹配 → ParseException；parsePages 失败 → ParseException
//  11) C-7 补充第 3 条：parse() 完成后 postedAt 已刷新

import { GalleryDetailParser, GalleryDetailParserConfig, BlackListHook } from '../parser/GalleryDetailParser';
import { GalleryDetail } from './GalleryDetail';
import { ParseException } from '../exception/ParseException';
import {
  GalleryUnavailableException,
  OffensiveException,
  PiningException
} from '../exception/MarkerExceptions';
import { EhException } from '../exception/EhException';
import { NormalPreviewSet } from './NormalPreviewSet';
import { LargePreviewSet } from './LargePreviewSet';

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

function throwsType(name: string, fn: () => void, ctor: Function): void {
  try {
    fn();
    fail++;
    failures.push(name + '（未抛异常）');
  } catch (e) {
    if (e instanceof ctor) {
      pass++;
    } else {
      fail++;
      failures.push(name + `（抛的是 ${(e as Error).name}）`);
    }
  }
}

const warns: string[] = [];
const origWarn = console.warn;
console.warn = (...args: unknown[]): void => {
  warns.push(args.map((a) => String(a)).join(' '));
};

// ---------- 样本 ----------
const HEAD = `<script type="text/javascript">` +
  `var gid = 1234567;\nvar token = "abcdef0123";\nvar apiuid = -1;\nvar apikey = "deadbeef";` +
  `</script>`;

function gmHtml(opts?: {
  title?: string; titleJpn?: string; category?: string; uploader?: string;
  cover?: string; detailRows?: string; ratingLabel?: string; ratingCount?: string;
  gdf?: string;
}): string {
  const rows = opts?.detailRows ?? '';
  const cover: string = opts?.cover ?? 'https://ehgt.org/c/1_250.jpg';
  return `<div class="gm">` +
    // PATTERN_COVER 要求 width/height 出现在 url(...) 之前（上游真实页面的 style 就是先尺寸后 url）
    `<div id="gd1"><div style="width:100px; height:200px; background:transparent url(${cover}) 0 0 no-repeat"></div></div>` +
    `<h1 id="gn">${opts?.title ?? 'Title Here'}</h1>` +
    `<h1 id="gj">${opts?.titleJpn ?? 'タイトル'}</h1>` +
    `<div id="gdc"><div class="${opts?.category === 'unknown' ? 'cn' : 'cs'}">${opts?.category ?? 'Manga'}</div></div>` +
    `<div id="gdn">${opts?.uploader ?? 'upname'}</div>` +
    `<div id="gdd"><table><tbody>${rows}</tbody></table></div>` +
    `<div id="rating_count">${opts?.ratingCount ?? '123'}</div>` +
    `<div id="rating_label">${opts?.ratingLabel ?? 'Average: 4.5'}</div>` +
    `<div id="gdf">${opts?.gdf ?? 'Add to Favorites'}</div>` +
    `</div>`;
}

function row(key: string, value: string): string {
  return `<tr><td class="gdt1">${key}</td><td class="gdt2">${value}</td></tr>`;
}

const FULL_ROWS = row('Posted:', '2020-01-02 03:04') +
  row('Parent:', '<a href="https://e-hentai.org/g/1/aaaaaaaaaa/">parent</a>') +
  row('Visible:', 'Yes') +
  row('Language:', 'English') +
  row('File Size:', '100 MB') +
  row('Length:', '42 pages') +
  row('Favorited:', '3 times');

function fullPage(extra?: string, gmOpts?: Parameters<typeof gmHtml>[0], withPtt?: boolean): string {
  const ptt = withPtt === false ? '' :
    `<table class="ptt"><tbody><tr><td><div>1</div><div>2</div></td><td>2</td><td><a href="?p=1">next</a></td></tr></tbody></table>`;
  return `<html><head></head><body>${extra ?? ''}${HEAD}${gmHtml(gmOpts)}` +
    `${ptt}<div id="taglist"><table><tbody>` +
    `<tr><td class="tc">language:</td><td class="tc"><div><a>english</a></div><div><a>chinese</a></div></td></tr>` +
    `<tr><td class="tc">artist:</td><td class="tc"><div><a>someone|alias</a></div></td></tr>` +
    `</tbody></table></div>` +
    `<div id="cdiv"></div>` +
    // 真实详情页的预览页数标记（parsePreviewPages 的正则版依赖它）
    `<table><tr><td class="ptdd"><a href="?p=0">1</a></td><td class="ptdd2">&gt;</td></tr></table>` +
    `</body></html>`;
}

// ---------- 1. 四种非正常页 ----------
throwsType('offensive → OffensiveException',
  () => GalleryDetailParser.parse('<p>(And if you choose to ignore this warning, you lose all rights to complain about it in the future.)</p>'),
  OffensiveException);
throwsType('pining → PiningException',
  () => GalleryDetailParser.parse('<p>This gallery is pining for the fjords.</p>'),
  PiningException);
throwsType('unavailable → GalleryUnavailableException',
  () => GalleryDetailParser.parse('<div>This gallery is unavailable</div>'),
  GalleryUnavailableException);
throwsType('#d>p 错误 → EhException 且带消息',
  () => GalleryDetailParser.parse('<div class="d">\n<p>Some custom error</p>'),
  EhException);

// ---------- 2/3/4/5/11. 主字段 ----------
{
  const body = fullPage('', { detailRows: FULL_ROWS },
    true);
  // 注入 torrent / archive
  const withLinks = body.replace('</body>',
    `<a href="#" onclick="return popUp('https://e-hentai.org/torrent/1?t=aa&amp;x=1',480,320)">Torrent Download (7)</a>` +
    `<a href="#" onclick="return popUp('https://e-hentai.org/archiver.php?gid=1',480,320)">Archive Download</a>` +
    `<div id="gnd"><a href="https://e-hentai.org/g/1/aaaaaaaaaa/">v2</a>, 2020-02-03 04:05</div>` +
    `</body>`);
  const gd: GalleryDetail = GalleryDetailParser.parse(withLinks);

  eq('gid', gd.gid, 1234567);
  eq('token', gd.token, 'abcdef0123');
  eq('apiUid', gd.apiUid, -1);
  eq('apiKey', gd.apiKey, 'deadbeef');
  eq('torrentCount', gd.torrentCount, 7);
  eq('torrentUrl（XML 反转义）', gd.torrentUrl, 'https://e-hentai.org/torrent/1?t=aa&x=1');
  eq('archiveUrl', gd.archiveUrl, 'https://e-hentai.org/archiver.php?gid=1');
  eq('title', gd.title, 'Title Here');
  eq('titleJpn', gd.titleJpn, 'タイトル');
  eq('category（cs=Manga → 0x4）', gd.category, 0x4);
  eq('uploader', gd.uploader, 'upname');
  eq('thumb（cover url，250 档不改）', gd.thumb, 'https://ehgt.org/c/1_250.jpg');
  eq('posted', gd.posted, '2020-01-02 03:04');
  ok('postedAt 已刷新（C-7 第 3 条）', gd.postedAt > 0);
  eq('parent（取 href）', gd.parent, 'https://e-hentai.org/g/1/aaaaaaaaaa/');
  eq('visible', gd.visible, 'Yes');
  eq('language', gd.language, 'English');
  eq('size', gd.size, '100 MB');
  eq('pages（Length 行）', gd.pages, 42);
  eq('favoriteCount（3 times → 3）', gd.favoriteCount, 3);
  eq('ratingCount', gd.ratingCount, 123);
  eq('rating（Average: 4.5）', gd.rating, 4.5);
  eq('isFavorited（Add to Favorites → false）', gd.isFavorited, false);
  eq('favoriteName（Add to Favorites → null）', gd.favoriteName, null);
  ok('newVersions 有 1 项', gd.newVersions !== null && (gd.newVersions as unknown[]).length === 1);
  eq('newVersions[0].versionUrl', (gd.newVersions as { versionUrl: string }[])[0].versionUrl,
    'https://e-hentai.org/g/1/aaaaaaaaaa/');
}

// 评分三态 + 收藏态
{
  const gd1: GalleryDetail = GalleryDetailParser.parse(
    fullPage('', { detailRows: FULL_ROWS, ratingLabel: 'Not Yet Rated' }));
  eq('rating Not Yet Rated → -1', gd1.rating, -1);
  const gd2: GalleryDetail = GalleryDetailParser.parse(
    fullPage('', { detailRows: FULL_ROWS, ratingLabel: 'Average:4.5' }));
  eq('rating 无空格 → 0', gd2.rating, 0);
  const gd3: GalleryDetail = GalleryDetailParser.parse(
    fullPage('', { detailRows: FULL_ROWS, gdf: 'My Favorites' }));
  eq('isFavorited（非 Add → true）', gd3.isFavorited, true);
  eq('favoriteName', gd3.favoriteName, 'My Favorites');
}

// Favorited 的 Never / Once
{
  const gdNever: GalleryDetail = GalleryDetailParser.parse(
    fullPage('', { detailRows: FULL_ROWS.replace('3 times', 'Never') }));
  eq('favoriteCount Never → 0', gdNever.favoriteCount, 0);
  const gdOnce: GalleryDetail = GalleryDetailParser.parse(
    fullPage('', { detailRows: FULL_ROWS.replace('3 times', 'Once') }));
  eq('favoriteCount Once → 1', gdOnce.favoriteCount, 1);
}

// ---------- 6. 标签组 ----------
{
  const gd: GalleryDetail = GalleryDetailParser.parse(fullPage('', { detailRows: FULL_ROWS }));
  const tags = gd.tags as { groupName: string; size(): number; getTagAt(i: number): string }[];
  ok('标签组 2 个', tags !== null && tags.length === 2);
  eq('标签组[0].name', tags[0].groupName, 'language');
  eq('标签组[0].size', tags[0].size(), 2);
  eq('标签组[0].tag0', tags[0].getTagAt(0), 'english');
  eq('标签组[1].name', tags[1].groupName, 'artist');
  eq('标签组[1].tag0（竖线前）', tags[1].getTagAt(0), 'someone');

  // 正则版（注意：PATTERN_TAG_GROUP 要求第二个 <td> 无属性、<div>/<a> 带属性 —— 上游真实页面如此）
  const groups = GalleryDetailParser.parseTagGroupsFromBody(
    `<tr><td class="tc">female:</td><td>` +
    `<div class="gt"><a href="?t=1">girl</a></div>` +
    `<div class="gt"><a href="?t=2">woman</a></div></td></tr>`);
  eq('正则版 1 组', groups.length, 1);
  eq('正则版 name', groups[0].groupName, 'female');
  eq('正则版 tags', groups[0].size(), 2);
}

// ---------- 7. 评论 ----------
{
  const commentHtml = `<div id="cdiv">` +
    `<a name="c42"></a>` +
    `<div class="c1">` +
    `<div class="c3">Posted on 02 January 2020, 03:04 by: &nbsp; <a href="#">someone</a></div>` +
    `<div class="c5"><span>7</span></div>` +
    `<div class="c6">hello <b>world</b></div>` +
    `<div class="c4"><div>Vote+</div><div style="visibility:hidden">Vote-</div><div>Edit</div></div>` +
    `<div class="c7">Vote +7</div>` +
    `<div class="c8"><div>edited</div></div>` +
    `</div></div>`;
  const gd: GalleryDetail = GalleryDetailParser.parse(fullPage(commentHtml, { detailRows: FULL_ROWS }, true));
  const cl = gd.comments as { comments: { id: number; user: string; comment: string; score: number; voteUpAble: boolean; voteUpEd: boolean; voteDownAble: boolean; voteDownEd: boolean; editable: boolean; voteState: string; time: number; lastEdited: number }[]; hasMore: boolean };
  ok('评论 1 条', cl !== null && cl.comments.length === 1);
  const c = cl.comments[0];
  eq('comment.id（name=c42 → 42）', c.id, 42);
  eq('comment.user', c.user, 'someone');
  eq('comment.comment（innerHTML）', c.comment, 'hello <b>world</b>');
  eq('comment.score', c.score, 7);
  eq('voteUpAble', c.voteUpAble, true);
  eq('voteUpEd（无 style → false）', c.voteUpEd, false);
  eq('voteDownAble', c.voteDownAble, true);
  eq('voteDownEd（有 style → true）', c.voteDownEd, true);
  eq('editable', c.editable, true);
  eq('voteState', c.voteState, 'Vote +7');
  eq('comment.time（UTC 02 Jan 2020 03:04）', c.time, Date.UTC(2020, 0, 2, 3, 4));
  eq('lastEdited（上游 bug：等于评论时间）', c.lastEdited, c.time);

  // 正则版
  const cs = GalleryDetailParser.parseCommentsFromBody(
    `<div class="c3">Posted on 02 January 2020, 03:04 by: &nbsp; <a href="#">u1</a>xx<div class="c6" style="x">body</div><div class="c7">`);
  eq('正则版评论 1 条', cs.length, 1);
  eq('正则版 user', cs[0].user, 'u1');
  eq('正则版 comment', cs[0].comment, 'body');
  eq('正则版 time', cs[0].time, Date.UTC(2020, 0, 2, 3, 4));

  // 黑名单 hook 未注入 → warn（只打一次，避免刷屏）
  ok('BlackListHook 未注入时打了 warn（C-14）',
    warns.some((w) => w.indexOf('BlackListHook 未注入') >= 0));
  warns.length = 0;
  GalleryDetailParser.parse(fullPage(commentHtml, { detailRows: FULL_ROWS }, true));
  ok('warn 只打一次（第二次解析不再刷屏）',
    warns.filter((w) => w.indexOf('BlackListHook 未注入') >= 0).length === 0);

  // 注入 hook → 过滤
  const hook: BlackListHook = { inBlackList: (user: string): boolean => user === 'someone' };
  GalleryDetailParser.setBlackListHook(hook);
  const gd2: GalleryDetail = GalleryDetailParser.parse(fullPage(commentHtml, { detailRows: FULL_ROWS }, true));
  eq('黑名单命中 → 评论被过滤', (gd2.comments as { comments: unknown[] }).comments.length, 0);
}

// ---------- 8/9. 预览 ----------
{
  const gd: GalleryDetail = GalleryDetailParser.parse(fullPage('', { detailRows: FULL_ROWS }, true));
  eq('previewPages（DOM 版，ptt 倒数第二格）', gd.previewPages, 2);
}

{
  const body = fullPage('', { detailRows: FULL_ROWS }, false) +
    `<td class="ptdd"><a href="?p=0">1</a></td><td class="ptdd2">&gt;</td>`;
  eq('previewPages 正则版', GalleryDetailParser.parsePreviewPages(body), 1);
  throwsType('previewPages 正则版失败 → ParseException',
    () => GalleryDetailParser.parsePreviewPages('<html></html>'), ParseException);
}

{
  // small preview：title="Page N: ... width:W height:H (...) -Xpx"
  const body = `<a href="https://e-hentai.org/s/aaaaaaaaaa/1234567-1">` +
    `<div title="Page 1: https://exhentai.org/t/aa/bb/x-250.jpg width:250 height:350 (x.jpg) -250px"></div></a>`;
  const ps = GalleryDetailParser.parsePreviewSet(body);
  ok('previewSet 是 NormalPreviewSet', ps instanceof NormalPreviewSet);
  eq('previewSet.size', ps.size(), 1);
  eq('previewSet.position', ps.getPosition(0), 0);
  eq('previewSet.pageUrl', ps.getPageUrlAt(0), 'https://e-hentai.org/s/aaaaaaaaaa/1234567-1');
}

{
  // large preview：new 格式
  const body = `<a href="https://e-hentai.org/s/bbbbbbbbbb/1234567-2"><div title="Page 2: ` +
    `https://exhentai.org/t/cc/dd/y.jpg (y.jpg) 0 0"></div></a>`;
  const ps = GalleryDetailParser.parsePreviewSet(body);
  ok('large previewSet 是 LargePreviewSet', ps instanceof LargePreviewSet);
  eq('large previewSet.size', ps.size(), 1);
  eq('large previewSet.position', ps.getPosition(0), 1);
}

{
  // 空 → 返回空 NormalPreviewSet（上游吞掉 ParseException）
  const ps = GalleryDetailParser.parsePreviewSet('<html><body>nothing</body></html>');
  ok('空预览 → NormalPreviewSet 空集合', ps instanceof NormalPreviewSet && ps.size() === 0);
}

// ---------- 10. 失败行为 ----------
throwsType('PATTERN_DETAIL 不匹配 → ParseException',
  () => GalleryDetailParser.parse('<html><body>no script here</body></html>'), ParseException);
throwsType('parsePages 失败 → ParseException',
  () => GalleryDetailParser.parsePages('<html></html>'), ParseException);
eq('parsePages 成功', GalleryDetailParser.parsePages(
  '<tr><td>Length:</td><td>1,234 pages</td></tr>'), 1234);

// PATTERN_DETAIL 匹配但 gid=-1 → ParseException
{
  const body = fullPage('', {}, true).replace('var gid = 1234567;', 'var gid = -1;');
  throwsType('gid=-1 → ParseException', () => GalleryDetailParser.parse(body), ParseException);
}

// parseWebCommentDate 边界
eq('parseWebCommentDate 非法 → 0', GalleryDetailParser.parseWebCommentDate('garbage'), 0);
eq('parseWebCommentDate 未知月份 → 0',
  GalleryDetailParser.parseWebCommentDate('02 Foo 2020, 03:04'), 0);

// ---------- 11. 真实 E-Hentai 省略 <tbody> 的 #gdd / #taglist / .ptt + fixThumbUrl 默认 false ----------
{
  const noTbodyHtml = `<html><head></head><body>${HEAD}` +
    `<div class="gm">` +
    `<div id="gd1"><div style="width:100px; height:200px; background:transparent url(https://ehgt.org/c/1_250.jpg) 0 0 no-repeat"></div></div>` +
    `<h1 id="gn">No Tbody Detail</h1><h1 id="gj"></h1>` +
    `<div id="gdc"><div class="cs">Manga</div></div><div id="gdn">up</div>` +
    `<div id="gdd"><table>${FULL_ROWS}</table></div>` +
    `<div id="rating_count">5</div><div id="rating_label">Average: 4.0</div><div id="gdf">Add to Favorites</div>` +
    `</div>` +
    `<table class="ptt"><tr><td><div>1</div><div>3</div></td><td>3</td><td><a href="?p=1">next</a></td></tr></table>` +
    `<div id="taglist"><table>` +
    `<tr><td class="tc">parody:</td><td><div><a>touhou | 东方</a></div></td></tr>` +
    `<tr><td class="tc">language:</td><td><div><a>chinese</a></div></td></tr>` +
    `</table></div>` +
    `<div id="cdiv"></div>` +
    `<table><tr><td class="ptdd"><a href="?p=0">1</a></td><td class="ptdd2">&gt;</td></tr></table>` +
    `</body></html>`;
  const gd: GalleryDetail = GalleryDetailParser.parse(noTbodyHtml);
  eq('无 tbody #gdd posted', gd.posted, '2020-01-02 03:04');
  eq('无 tbody #gdd pages', gd.pages, 42);
  eq('无 tbody .ptt previewPages', gd.previewPages, 3);
  const tags = gd.tags as { groupName: string; getTagAt(i: number): string }[];
  eq('无 tbody #taglist 2 组', tags.length, 2);
  eq('无 tbody #taglist[0]', [tags[0].groupName, tags[0].getTagAt(0)], ['parody', 'touhou']);
  eq('无 tbody #taglist[1]', [tags[1].groupName, tags[1].getTagAt(0)], ['language', 'chinese']);

  // GalleryDetailParserConfig 默认 getFixThumbUrl() === false（对齐上游 Settings.DEFAULT_FIX_THUMB_URL = false）
  const previewHtml = `<a href="https://e-hentai.org/s/cccccccccc/1234567-1"><div title="Page 1: a.jpg" ` +
    `style="background:transparent url(https://exhentai.org/t/aa/bb/aabb1234-250.jpg) 0 0 no-repeat"></div></a>`;
  const psDefault = GalleryDetailParser.parsePreviewSet(previewHtml) as LargePreviewSet;
  eq('fixThumbUrl 默认 false → 保留原 exhentai 缩略图前缀',
    psDefault.getGalleryPreview(1234567, 0).imageUrl,
    'https://exhentai.org/t/aa/bb/aabb1234-250.jpg');

  class FixOnConfig extends GalleryDetailParserConfig {
    getFixThumbUrl(): boolean {
      return true;
    }
  }
  GalleryDetailParser.setConfig(new FixOnConfig());
  const psFixed = GalleryDetailParser.parsePreviewSet(previewHtml) as LargePreviewSet;
  eq('fixThumbUrl=true → 修正为 ehgt.org 前缀',
    psFixed.getGalleryPreview(1234567, 0).imageUrl,
    'https://ehgt.org/aa/bb/aabb1234-250.jpg');
  GalleryDetailParser.setConfig(new GalleryDetailParserConfig());

  // #gj 日文标题解析（.gm 内及文档兜底）
  const jpnHtml = `<html><head></head><body>${HEAD}` +
    `<div class="gm">` +
    `<div id="gd1"><div style="width:100px; height:200px; background:transparent url(https://ehgt.org/c/1_250.jpg) 0 0 no-repeat"></div></div>` +
    `<h1 id="gn">English Title Sample</h1><h1 id="gj">日本語タイトルテスト</h1>` +
    `<div id="gdc"><div class="cs">Manga</div></div><div id="gdn">up</div>` +
    `<div id="gdd"><table>${FULL_ROWS}</table></div>` +
    `<div id="rating_count">5</div><div id="rating_label">Average: 4.0</div><div id="gdf">Add to Favorites</div>` +
    `</div>` +
    `<table class="ptt"><tr><td><div>1</div><div>3</div></td><td>3</td><td><a href="?p=1">next</a></td></tr></table>` +
    `<div id="taglist"><table></table></div><div id="cdiv"></div>` +
    `<table><tr><td class="ptdd"><a href="?p=0">1</a></td><td class="ptdd2">&gt;</td></tr></table>` +
    `</body></html>`;
  const gdJpn: GalleryDetail = GalleryDetailParser.parse(jpnHtml);
  eq('detail #gn title', gdJpn.title, 'English Title Sample');
  eq('detail #gj titleJpn', gdJpn.titleJpn, '日本語タイトルテスト');

  const fallbackGjHtml = `<html><head></head><body>${HEAD}` +
    `<div class="gm">` +
    `<div id="gd1"><div style="width:100px; height:200px; background:transparent url(https://ehgt.org/c/1_250.jpg) 0 0 no-repeat"></div></div>` +
    `<h1 id="gn">English Only In Gm</h1>` +
    `<div id="gdc"><div class="cs">Manga</div></div><div id="gdn">up</div>` +
    `<div id="gdd"><table>${FULL_ROWS}</table></div>` +
    `<div id="rating_count">5</div><div id="rating_label">Average: 4.0</div><div id="gdf">Add to Favorites</div>` +
    `</div>` +
    `<h1 id="gj">文档兜底日本語</h1>` +
    `<table class="ptt"><tr><td><div>1</div><div>3</div></td><td>3</td><td><a href="?p=1">next</a></td></tr></table>` +
    `<div id="taglist"><table></table></div><div id="cdiv"></div>` +
    `<table><tr><td class="ptdd"><a href="?p=0">1</a></td><td class="ptdd2">&gt;</td></tr></table>` +
    `</body></html>`;
  const gdFallbackJpn: GalleryDetail = GalleryDetailParser.parse(fallbackGjHtml);
  eq('detail fallback #gj titleJpn', gdFallbackJpn.titleJpn, '文档兜底日本語');

  // #rating_image 高亮类解析（ir vs irg/irb/irr）
  const unratedImgHtml = `<html><head></head><body>${HEAD}` +
    `<div class="gm">` +
    `<div id="gd1"><div style="width:100px; height:200px; background:transparent url(https://ehgt.org/c/1_250.jpg) 0 0 no-repeat"></div></div>` +
    `<h1 id="gn">Unrated Gallery</h1><h1 id="gj"></h1>` +
    `<div id="gdc"><div class="cs">Manga</div></div><div id="gdn">up</div>` +
    `<div id="gdd"><table>${FULL_ROWS}</table></div>` +
    `<div id="rating_image" class="ir"></div>` +
    `<div id="rating_count">5</div><div id="rating_label">Average: 4.0</div><div id="gdf">Add to Favorites</div>` +
    `</div>` +
    `<table class="ptt"><tr><td><div>1</div><div>3</div></td><td>3</td><td><a href="?p=1">next</a></td></tr></table>` +
    `<div id="taglist"><table></table></div><div id="cdiv"></div>` +
    `<table><tr><td class="ptdd"><a href="?p=0">1</a></td><td class="ptdd2">&gt;</td></tr></table>` +
    `</body></html>`;
  eq('detail #rating_image class="ir" → rated=false', GalleryDetailParser.parse(unratedImgHtml).rated, false);

  const ratedImgHtml = unratedImgHtml.replace('class="ir"', 'class="ir irg"');
  eq('detail #rating_image class="ir irg" → rated=true', GalleryDetailParser.parse(ratedImgHtml).rated, true);

  const ratedBlueHtml = unratedImgHtml.replace('class="ir"', 'class="ir irb"');
  eq('detail #rating_image class="ir irb" → rated=true', GalleryDetailParser.parse(ratedBlueHtml).rated, true);
}

console.warn = origWarn;
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('GalleryDetailParser 断言失败：' + fail);
}
