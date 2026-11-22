// net-parse 往返测试（GalleryInfo/Detail 的 toJson/fromJson + toCSV/fromCSV + parsePosted）
// 说明：本文件把 .ets 源码机械转成 .ts（仅去掉 @Observed 装饰器、扩展名换 ts），
// 用 SDK 自带的 tsc 4.9.5 编译后用 node 执行 —— 被测逻辑与仓库里的 .ets 完全同源。
import { GalleryInfo } from './GalleryInfo';
import { GalleryDetail } from './GalleryDetail';
import { GalleryTagGroup } from './GalleryTagGroup';
import { GalleryComment } from './GalleryComment';
import { GalleryCommentList } from './GalleryCommentList';

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
    failures.push(`${name}: actual=${a} expected=${e}`);
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

// ---------- 1. parsePosted 六种形态 ----------
eq('parsePosted 秒', GalleryInfo.parsePosted('1287964800'), 1287964800000);
eq('parsePosted 毫秒', GalleryInfo.parsePosted('1287964800000'), 1287964800000);
const d1 = new Date(2010, 9, 25, 0, 0, 0).getTime();
eq('parsePosted 日期串带时间', GalleryInfo.parsePosted('2010-10-25 00:00'), d1);
eq('parsePosted 纯日期', GalleryInfo.parsePosted('2010-10-25'), d1);
eq('parsePosted 空串', GalleryInfo.parsePosted(''), -1);
eq('parsePosted unknown', GalleryInfo.parsePosted('unknown'), -1);
eq('parsePosted N/A', GalleryInfo.parsePosted('N/A'), -1);

// ---------- 2. GalleryInfo toJson -> fromJson 全字段 ----------
const gi = new GalleryInfo();
gi.gid = 1234567;
gi.token = 'a1b2c3';
gi.title = 'Test [Chinese]';
gi.titleJpn = 'テスト';
gi.thumb = 'https://ehgt.org/t/1.jpg';
gi.category = 2;
gi.posted = '2010-10-25 00:00';
gi.uploader = 'uploader1';
gi.rating = 4.5;
gi.simpleLanguage = 'ZH';
gi.rated = true;
gi.simpleTags = ['language:chinese', 'full color'];
gi.pages = 42;
gi.thumbWidth = 250;
gi.thumbHeight = 350;
gi.spanSize = 3;
gi.spanIndex = 1;
gi.spanGroupIndex = 0;
gi.favoriteSlot = 3;
gi.favoriteName = 'My Fav';
gi.tgList = ['tag1', 'tag2'];
gi.postedAt = GalleryInfo.parsePosted(gi.posted);

const json = gi.toJson();
const gi2 = GalleryInfo.fromJson(json);
eq('info.gid', gi2.gid, gi.gid);
eq('info.token', gi2.token, gi.token);
eq('info.title', gi2.title, gi.title);
eq('info.titleJpn', gi2.titleJpn, gi.titleJpn);
eq('info.thumb', gi2.thumb, gi.thumb);
eq('info.category', gi2.category, gi.category);
eq('info.posted', gi2.posted, gi.posted);
eq('info.uploader', gi2.uploader, gi.uploader);
eq('info.rating', gi2.rating, gi.rating);
eq('info.rated', gi2.rated, gi.rated);
eq('info.simpleLanguage', gi2.simpleLanguage, gi.simpleLanguage);
eq('info.simpleTags', gi2.simpleTags, gi.simpleTags);
eq('info.pages', gi2.pages, gi.pages);
eq('info.thumbWidth', gi2.thumbWidth, gi.thumbWidth);
eq('info.thumbHeight', gi2.thumbHeight, gi.thumbHeight);
eq('info.spanSize', gi2.spanSize, gi.spanSize);
eq('info.spanIndex', gi2.spanIndex, gi.spanIndex);
eq('info.spanGroupIndex', gi2.spanGroupIndex, gi.spanGroupIndex);
eq('info.favoriteSlot', gi2.favoriteSlot, gi.favoriteSlot);
eq('info.favoriteName', gi2.favoriteName, gi.favoriteName);
eq('info.tgList', gi2.tgList, gi.tgList);
eq('info.postedAt', gi2.postedAt, gi.postedAt);

// null 字段往返
const giNull = new GalleryInfo();
giNull.gid = 1;
const giNull2 = GalleryInfo.fromJson(giNull.toJson());
eq('info.null.simpleLanguage', giNull2.simpleLanguage, null);
eq('info.null.simpleTags', giNull2.simpleTags, null);
eq('info.null.favoriteName', giNull2.favoriteName, null);
eq('info.null.tgList', giNull2.tgList, null);
eq('info.null.favoriteSlot 默认 -2', giNull2.favoriteSlot, -2);

// ---------- 3. toCSV -> fromCSV ----------
// 注意：上游 toCSV/fromCSV 用 ',' 分隔，而 simpleTags 渲染成 "[a, b]" 本身含逗号，
// 所以**多标签**的条目在两端都无法往返（上游同样如此）。这里用单标签验证正常路径，
// 多标签的缺陷单独断言（见 3b），保持与上游行为一致。
const giCsv = new GalleryInfo();
giCsv.gid = 1234567;
giCsv.token = 'a1b2c3';
giCsv.title = 'Test';
giCsv.titleJpn = 'テスト';
giCsv.thumb = 'https://ehgt.org/t/1.jpg';
giCsv.category = 2;
giCsv.posted = '2010-10-25 00:00';
giCsv.uploader = 'uploader1';
giCsv.rating = 4.5;
giCsv.rated = true;
giCsv.simpleLanguage = 'ZH';
giCsv.simpleTags = ['language:chinese'];
giCsv.pages = 42;
giCsv.thumbWidth = 250;
giCsv.thumbHeight = 350;
giCsv.spanSize = 3;
giCsv.spanIndex = 1;
giCsv.spanGroupIndex = 0;
giCsv.favoriteSlot = 3;
giCsv.favoriteName = 'MyFav';
const csv = giCsv.toCSV();
const gi3 = GalleryInfo.fromCSV(csv)!;
ok('csv 非空解析', gi3 !== null);
eq('csv.gid', gi3.gid, giCsv.gid);
eq('csv.posted', gi3.posted, giCsv.posted);
eq('csv.rating', gi3.rating, giCsv.rating);
eq('csv.simpleTags', gi3.simpleTags, giCsv.simpleTags);
eq('csv.favoriteSlot', gi3.favoriteSlot, giCsv.favoriteSlot);
eq('csv.pages', gi3.pages, giCsv.pages);
eq('csv.字段数 <20 返回 null', GalleryInfo.fromCSV('1,2,3'), null);

// 3b. 多标签 → CSV 往返失败（上游同样失败，行为一致）
eq('csv 多标签往返失败(与上游一致)', GalleryInfo.fromCSV(gi.toCSV()), null);

// ---------- 4. generateSLang ----------
const gl = new GalleryInfo();
gl.title = 'Some Title (English)';
gl.generateSLang();
eq('sLang from title', gl.simpleLanguage, 'EN');
const gl2 = new GalleryInfo();
gl2.title = 'テスト [中国翻訳]';
gl2.generateSLang();
eq('sLang 中文', gl2.simpleLanguage, 'ZH');
const gl3 = new GalleryInfo();
gl3.simpleTags = ['language:korean'];
gl3.title = 'x';
gl3.generateSLang();
eq('sLang from tags 优先', gl3.simpleLanguage, 'KO');
const gl4 = new GalleryInfo();
gl4.title = 'no language here';
gl4.generateSLang();
eq('sLang 无匹配 null', gl4.simpleLanguage, null);

// ---------- 5. GalleryDetail.toJson 覆写：详情字段必须保住 ----------
const gd = new GalleryDetail();
gd.gid = 999;
gd.title = 'Detail Title';
gd.token = 'tok';
gd.apiUid = 42;
gd.apiKey = 'key-xyz';
gd.torrentCount = 7;
gd.torrentUrl = 'https://e-hentai.org/torrent/999';
gd.archiveUrl = 'https://e-hentai.org/archiver.php?gid=999';
gd.parent = 'https://e-hentai.org/g/998/abc/';
gd.visible = 'Yes';
gd.language = 'Translated';
gd.size = '123 MB';
gd.SpiderInfoPages = 42;
gd.favoriteCount = 5;
gd.isFavorited = true;
gd.ratingCount = 11;
gd.previewPages = 40;
gd.SpiderInfoPreviewPages = 40;

const djson = gd.toJson();
ok('detail json 是合法 JSON', (() => { try { JSON.parse(djson); return true; } catch (e) { return false; } })());
const parsed = JSON.parse(djson) as Record<string, unknown>;
eq('detail.json.gid', parsed['gid'], 999);
eq('detail.json.title', parsed['title'], 'Detail Title');
eq('detail.json.apiUid', parsed['apiUid'], 42);
eq('detail.json.apiKey', parsed['apiKey'], 'key-xyz');
eq('detail.json.torrentCount', parsed['torrentCount'], 7);
eq('detail.json.torrentUrl', parsed['torrentUrl'], gd.torrentUrl);
eq('detail.json.archiveUrl', parsed['archiveUrl'], gd.archiveUrl);
eq('detail.json.parent', parsed['parent'], gd.parent);
eq('detail.json.visible', parsed['visible'], 'Yes');
eq('detail.json.language', parsed['language'], 'Translated');
eq('detail.json.size', parsed['size'], '123 MB');
eq('detail.json.SpiderInfoPages', parsed['SpiderInfoPages'], 42);
eq('detail.json.favoriteCount', parsed['favoriteCount'], 5);
eq('detail.json.isFavorited', parsed['isFavorited'], true);
eq('detail.json.ratingCount', parsed['ratingCount'], 11);
eq('detail.json.previewPages', parsed['previewPages'], 40);
eq('detail.json.SpiderInfoPreviewPages', parsed['SpiderInfoPreviewPages'], 40);

// 详情 JSON 用父类 fromJson 读回后，父类字段必须全对（详情字段由调用方另取）
const gdBack = GalleryInfo.fromJson(djson);
eq('detail.back.gid', gdBack.gid, 999);
eq('detail.back.title', gdBack.title, 'Detail Title');
eq('detail.back.token', gdBack.token, 'tok');

// 空详情对象也要合法
const gdEmpty = new GalleryDetail();
ok('detail 空对象 json 合法', (() => { try { JSON.parse(gdEmpty.toJson()); return true; } catch (e) { return false; } })());

// ---------- 6. GalleryCommentList.deleteComment ----------
const c1 = new GalleryComment();
c1.id = 1;
const c2 = new GalleryComment();
c2.id = 2;
const c3 = new GalleryComment();
c3.id = 3;
const list = new GalleryCommentList([c1, c2, c3], false);
list.deleteComment(1);
eq('commentList 删除后长度', list.comments.length, 2);
eq('commentList 删除后首项', list.comments[0].id, 1);
eq('commentList 删除后次项', list.comments[1].id, 3);

// ---------- 7. GalleryTagGroup ----------
const tg = new GalleryTagGroup();
tg.groupName = 'language';
tg.addTag('chinese');
tg.addTag('english');
eq('tagGroup.size', tg.size(), 2);
eq('tagGroup.getTagAt(1)', tg.getTagAt(1), 'english');

// ---------- 汇总 ----------
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('round-trip failed: ' + failures.length);
}
