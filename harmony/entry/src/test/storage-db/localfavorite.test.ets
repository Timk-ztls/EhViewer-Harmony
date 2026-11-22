/*
 * `LocalFavoriteInfo.fromGalleryInfo` 单测
 *
 * 与 `HistoryInfo.fromGalleryInfo` 是**同类但不同列集**：
 *   HISTORY         = 12 列（含 MODE）
 *   LOCAL_FAVORITES = 11 列（**没有 MODE**，多一个 TIME）
 * 所以这里**不能照 HistoryInfo 抄**（lead 明确提醒）。断言的目的就是把"拷哪 11 列、不拷哪些"
 * 钉死：多拷一列静默丢弃、少拷一列历史/收藏列表缺字段，两者都不报错。
 */

import { LocalFavoriteInfo } from '../../main/ets/hippo/ehviewer/dao/LocalFavoriteInfo';
import { LocalFavoritesDao } from '../../main/ets/hippo/ehviewer/dao/LocalFavoritesDao';
import { QuickSearch } from '../../main/ets/hippo/ehviewer/dao/QuickSearch';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';
import { QuickSearchLike } from '../../main/ets/hippo/ehviewer/client/data/ListUrlBuilder';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import relationalStore from '@ohos.data.relationalStore';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
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
    fails.push(name);
  }
}

function makeFullGalleryInfo(): GalleryInfo {
  const g: GalleryInfo = new GalleryInfo();
  g.gid = 987654;
  g.token = 't0k3n';
  g.title = 'Title';
  g.titleJpn = 'タイトル';
  g.thumb = 'https://example.invalid/t.jpg';
  g.category = 5;
  g.posted = '2024-02-03 04:05';
  g.uploader = 'uploader';
  g.rating = 2.75;
  g.simpleLanguage = 'japanese';
  g.rated = true;
  g.simpleTags = ['tagA', 'tagB'];
  // 以下字段在 LOCAL_FAVORITES 里**没有列**，必须保持默认
  g.pages = 42;
  g.thumbWidth = 1280;
  g.thumbHeight = 1810;
  g.spanSize = 6;
  g.spanIndex = 3;
  g.spanGroupIndex = 1;
  g.favoriteSlot = 3;
  g.favoriteName = 'my-favorite';
  g.tgList = ['group:artist$foo'];
  g.postedAt = 1700000000000;
  return g;
}

// ================================================================ 1) 拷贝的 11 个字段

{
  const h: LocalFavoriteInfo = LocalFavoriteInfo.fromGalleryInfo(makeFullGalleryInfo());
  eq('gid', h.gid, 987654);
  eq('token', h.token, 't0k3n');
  eq('title', h.title, 'Title');
  eq('titleJpn（非 ASCII 不丢）', h.titleJpn, 'タイトル');
  eq('thumb', h.thumb, 'https://example.invalid/t.jpg');
  eq('category', h.category, 5);
  eq('posted（字符串原样，不做 Date 转换）', h.posted, '2024-02-03 04:05');
  eq('uploader', h.uploader, 'uploader');
  eq('rating（REAL 列，保留小数）', h.rating, 2.75);
  eq('simpleLanguage', h.simpleLanguage, 'japanese');
  eq('simpleTags（共享引用，与上游同）', h.simpleTags, ['tagA', 'tagB']);
}

// ================================================================ 2) 不拷贝的字段（LOCAL_FAVORITES 无此列）

{
  const h: LocalFavoriteInfo = LocalFavoriteInfo.fromGalleryInfo(makeFullGalleryInfo());
  eq('pages 未拷贝', h.pages, 0);
  eq('thumbWidth 未拷贝', h.thumbWidth, 0);
  eq('thumbHeight 未拷贝', h.thumbHeight, 0);
  eq('spanSize 未拷贝', h.spanSize, 0);
  eq('spanIndex 未拷贝', h.spanIndex, 0);
  eq('spanGroupIndex 未拷贝', h.spanGroupIndex, 0);
  eq('favoriteSlot 未拷贝（基类默认 -2）', h.favoriteSlot, -2);
  eq('favoriteName 未拷贝', h.favoriteName, null);
  eq('tgList 未拷贝', h.tgList, null);
  eq('postedAt 未拷贝', h.postedAt, -1);
  eq('rated 未拷贝', h.rated, false);
}

// ================================================================ 3) 专有列 time（LOCAL_FAVORITES 有、HISTORY 也有但语义不同）

{
  const h: LocalFavoriteInfo = LocalFavoriteInfo.fromGalleryInfo(makeFullGalleryInfo());
  eq('time 默认 0（由调用方 setTime）', h.time, 0);
  h.setTime(1700000000000);
  eq('setTime 生效', h.getTime(), 1700000000000);
  // 关键：LOCAL_FAVORITES **没有 MODE 列**，所以本类没有 mode 字段可拷 ——
  // 若以后有人从 HistoryInfo 抄一行 `info.mode = ...`，编译会失败（这里无法在运行时断言，
  // 但 check-migration.ps1 的列集合断言与这条 DDL 证据形成双重保护）。
}

// ================================================================ 4) 边界与独立性

{
  const empty: GalleryInfo = new GalleryInfo();
  const h: LocalFavoriteInfo = LocalFavoriteInfo.fromGalleryInfo(empty);
  eq('空对象 gid', h.gid, 0);
  eq('空对象 title', h.title, '');
  eq('空对象 simpleLanguage（基类是 |null）', h.simpleLanguage, null);
  eq('空对象 simpleTags', h.simpleTags, null);
  eq('空对象 rating', h.rating, 0);
}

{
  const src: GalleryInfo = makeFullGalleryInfo();
  const h: LocalFavoriteInfo = LocalFavoriteInfo.fromGalleryInfo(src);
  h.title = 'Changed';
  h.gid = 1;
  eq('改结果不影响源 gid', src.gid, 987654);
  eq('改结果不影响源 title', src.title, 'Title');
}

// ================================================================ 5) QuickSearchLike + QuickSearch JSON + DownloadInfo JSON 全字段往返 + LocalFavoritesDao QueryBuilder

{
  const qs: QuickSearch = new QuickSearch(12, 'My Search', 3, 255, 'artist:foo', 1, 4, 2, 10, 998877);
  const qsLike: QuickSearchLike = qs;
  eq('QuickSearchLike.getMode', qsLike.getMode(), 3);
  eq('QuickSearchLike.getCategory', qsLike.getCategory(), 255);
  eq('QuickSearchLike.getKeyword', qsLike.getKeyword(), 'artist:foo');
  eq('QuickSearchLike.getAdvanceSearch', qsLike.getAdvanceSearch(), 1);
  eq('QuickSearchLike.getMinRating', qsLike.getMinRating(), 4);
  eq('QuickSearchLike.getPageFrom', qsLike.getPageFrom(), 2);
  eq('QuickSearchLike.getPageTo', qsLike.getPageTo(), 10);
  qsLike.setKeyword('bar');
  eq('QuickSearchLike.setKeyword 生效', qs.getKeyword(), 'bar');
  eq('QuickSearch.toString() 返回 name', qs.toString(), 'My Search');
  eq('QuickSearch.toString() name=null 时返回空串', new QuickSearch().toString(), '');

  const qsJson: string = qs.toJson();
  ok('QuickSearch.toJson 不含主键 id', qsJson.indexOf('"id"') < 0);
  const qsBack: QuickSearch = QuickSearch.quickSearchFromJson(qsJson);
  eq('QuickSearch JSON name 往返', qsBack.getName(), 'My Search');
  eq('QuickSearch JSON mode 往返', qsBack.getMode(), 3);
  eq('QuickSearch JSON category 往返', qsBack.getCategory(), 255);
  eq('QuickSearch JSON keyword 往返', qsBack.getKeyword(), 'bar');
  eq('QuickSearch JSON advanceSearch 往返', qsBack.getAdvanceSearch(), 1);
  eq('QuickSearch JSON minRating 往返', qsBack.getMinRating(), 4);
  eq('QuickSearch JSON pageFrom 往返', qsBack.getPageFrom(), 2);
  eq('QuickSearch JSON pageTo 往返', qsBack.getPageTo(), 10);
  eq('QuickSearch JSON time 往返', qsBack.getTime(), 998877);
}

{
  const di: DownloadInfo = new DownloadInfo(556677);
  di.token = 'tok_full';
  di.title = 'Main Title';
  di.titleJpn = '日本語タイトル';
  di.thumb = 'https://example.invalid/cover.jpg';
  di.category = 4;
  di.posted = '2024-05-06 07:08';
  di.uploader = 'up_user';
  di.rating = 4.25;
  di.rated = true;
  di.simpleLanguage = 'EN';
  di.simpleTags = ['tag1', 'tag2'];
  di.pages = 33;
  di.thumbWidth = 250;
  di.thumbHeight = 350;
  di.spanSize = 8;
  di.spanIndex = 2;
  di.spanGroupIndex = 1;
  di.favoriteSlot = 5;
  di.favoriteName = 'Fav5';
  di.tgList = ['g:foo', 'g:bar'];
  di.finished = 12;
  di.legacy = 3;
  di.label = 'DL_Label';
  di.downloaded = 12;
  di.remaining = 21;
  di.speed = 4096;
  di.state = DownloadInfo.STATE_FINISH;
  di.time = 1712345678901;
  di.total = 33;
  di.archiveUri = 'file://media/archive.zip';

  const json: string = di.toJson();
  const parsed: DownloadInfo = DownloadInfo.downloadInfoFromJson(json);
  eq('DownloadInfo JSON gid', parsed.gid, 556677);
  eq('DownloadInfo JSON rated', parsed.rated, true);
  eq('DownloadInfo JSON pages', parsed.pages, 33);
  eq('DownloadInfo JSON thumbWidth', parsed.thumbWidth, 250);
  eq('DownloadInfo JSON thumbHeight', parsed.thumbHeight, 350);
  eq('DownloadInfo JSON spanSize', parsed.spanSize, 8);
  eq('DownloadInfo JSON spanIndex', parsed.spanIndex, 2);
  eq('DownloadInfo JSON spanGroupIndex', parsed.spanGroupIndex, 1);
  eq('DownloadInfo JSON favoriteSlot', parsed.favoriteSlot, 5);
  eq('DownloadInfo JSON favoriteName', parsed.favoriteName, 'Fav5');
  eq('DownloadInfo JSON simpleTags', parsed.simpleTags, ['tag1', 'tag2']);
  eq('DownloadInfo JSON tgList', parsed.tgList, ['g:foo', 'g:bar']);
  ok('DownloadInfo JSON postedAt 已刷新 (>0)', parsed.postedAt > 0);
  eq('DownloadInfo JSON finished', parsed.finished, 12);
  eq('DownloadInfo JSON legacy', parsed.legacy, 3);
  eq('DownloadInfo JSON label', parsed.label, 'DL_Label');
  eq('DownloadInfo JSON downloaded', parsed.downloaded, 12);
  eq('DownloadInfo JSON remaining', parsed.remaining, 21);
  eq('DownloadInfo JSON speed', parsed.speed, 4096);
  eq('DownloadInfo JSON state', parsed.state, DownloadInfo.STATE_FINISH);
  eq('DownloadInfo JSON time', parsed.time, 1712345678901);
  eq('DownloadInfo JSON total', parsed.total, 33);
  eq('DownloadInfo JSON archiveUri', parsed.archiveUri, 'file://media/archive.zip');
}

{
  const fakeStore: relationalStore.RdbStore = {} as unknown as relationalStore.RdbStore;
  const lfDao: LocalFavoritesDao = new LocalFavoritesDao(fakeStore);
  const qb1 = lfDao.queryBuilder().where(LocalFavoritesDao.Properties.Gid.eq(1)).limit(5);
  const qb2 = lfDao.queryBuilder();
  ok('LocalFavoritesDao.queryBuilder() 返回新实例', qb1 !== qb2);
  eq('LocalFavoritesDao 新建 builder 无残留条件', qb2.sql(), 'SELECT * FROM "LOCAL_FAVORITES"');
  eq('LocalFavoritesDao limit(0) 产出 LIMIT 0', lfDao.queryBuilder().limit(0).sql(),
    'SELECT * FROM "LOCAL_FAVORITES" LIMIT 0');
}

// ================================================================ 汇总

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
