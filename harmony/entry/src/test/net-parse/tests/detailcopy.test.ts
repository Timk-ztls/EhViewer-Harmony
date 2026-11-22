// GalleryDetail.copy() / getNewGalleryDetail() 测试（DataUtils 判 na 后的替代实现）
//
// 上游 `DataUtils.copy` 走 Parcel → **深拷**。所以重点断言"改拷贝不影响原件"：
//   - 数组（simpleTags / tgList / newVersions）必须是独立数组
//   - Parcelable 子对象（tags / comments / previewSet）必须是独立实例
// 以及 getNewGalleryDetail 的三条分支：newVersions 为 null / 正常切换 / 异常回退 this

import { GalleryDetail } from './GalleryDetail';
import { GalleryTagGroup } from './GalleryTagGroup';
import { GalleryComment } from './GalleryComment';
import { GalleryCommentList } from './GalleryCommentList';
import { NewVersion } from './NewVersion';
import { NormalPreviewSet } from './NormalPreviewSet';

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

function makeDetail(): GalleryDetail {
  const d = new GalleryDetail();
  d.gid = 42;
  d.token = 'aaaaaaaaaa';
  d.title = 'T';
  d.titleJpn = 'TJ';
  d.thumb = 'https://ehgt.org/t.jpg';
  d.category = 0x100;
  d.posted = '2020-01-02 03:04';
  d.uploader = 'u';
  d.rating = 4.5;
  d.simpleLanguage = 'chinese';
  d.rated = true;
  d.simpleTags = ['f:yaoi', 'm:solemale'];
  d.pages = 20;
  d.thumbWidth = 250;
  d.thumbHeight = 350;
  d.favoriteSlot = 3;
  d.favoriteName = 'fav';
  d.tgList = ['t1', 't2'];
  d.postedAt = 1234567890;

  d.apiUid = -1;
  d.apiKey = 'key';
  d.torrentCount = 2;
  d.torrentUrl = 'https://e-hentai.org/torrents.php';
  d.archiveUrl = 'https://e-hentai.org/archiver.php';
  d.parent = 'p';
  d.visible = 'vis';
  d.language = 'chinese';
  d.size = '1.2 GB';
  d.SpiderInfoPages = 20;
  d.favoriteCount = 7;
  d.isFavorited = true;
  d.ratingCount = 9;
  d.previewPages = 2;
  d.SpiderInfoPreviewPages = 2;

  const tag = new GalleryTagGroup();
  tag.groupName = 'female';
  tag.addTag('f:yaoi');
  d.tags = [tag];

  const cm = new GalleryComment();
  cm.id = 1;
  cm.comment = 'hello';
  d.comments = new GalleryCommentList([cm], true);

  const ps = new NormalPreviewSet();
  ps.addItem(0, 'https://ehgt.org/p1.jpg', 0, 0, 250, 350, 'https://e-hentai.org/s/p1');
  d.previewSet = ps;

  const nv = new NewVersion();
  nv.versionName = 'English';
  nv.versionUrl = 'https://e-hentai.org/g/777/bbbbbbbbbb/';
  d.newVersions = [nv];
  return d;
}

// ---------- 1. copy()：全字段相等 + 深拷 ----------
{
  const src = makeDetail();
  const n = src.copy();

  eq('gid', n.gid, 42);
  eq('token', n.token, 'aaaaaaaaaa');
  eq('titleJpn', n.titleJpn, 'TJ');
  eq('category', n.category, 0x100);
  eq('postedAt（派生字段一并复制）', n.postedAt, 1234567890);
  eq('favoriteSlot', n.favoriteSlot, 3);
  eq('favoriteName', n.favoriteName, 'fav');
  eq('apiKey', n.apiKey, 'key');
  eq('isFavorited', n.isFavorited, true);
  eq('SpiderInfoPreviewPages', n.SpiderInfoPreviewPages, 2);

  // 深拷：数组独立
  ok('simpleTags 不是同一个数组', n.simpleTags !== src.simpleTags);
  ok('tgList 不是同一个数组', n.tgList !== src.tgList);
  (n.simpleTags as string[]).push('x:extra');
  eq('改拷贝的 simpleTags 不影响原件', (src.simpleTags as string[]).length, 2);

  // 深拷：Parcelable 子对象独立
  ok('tags[0] 不是同一个对象', (n.tags as GalleryTagGroup[])[0] !== (src.tags as GalleryTagGroup[])[0]);
  ok('comments 不是同一个对象', n.comments !== src.comments);
  ok('previewSet 不是同一个对象', n.previewSet !== src.previewSet);
  ok('newVersions[0] 不是同一个对象',
    (n.newVersions as NewVersion[])[0] !== (src.newVersions as NewVersion[])[0]);

  // 改拷贝的嵌套对象，原件不受影响
  ((n.comments as GalleryCommentList).comments[0]).comment = 'changed';
  eq('改拷贝的评论不影响原件', (((src.comments as GalleryCommentList).comments[0])).comment, 'hello');
  ((n.newVersions as NewVersion[])[0]).versionUrl = 'changed';
  eq('改拷贝的版本 URL 不影响原件',
    ((src.newVersions as NewVersion[])[0]).versionUrl, 'https://e-hentai.org/g/777/bbbbbbbbbb/');

  // previewSet 内容也复制了
  eq('previewSet.size 一致', (n.previewSet as NormalPreviewSet).size(), 1);
  eq('previewSet pageUrl 一致',
    (n.previewSet as NormalPreviewSet).getPageUrlAt(0), 'https://e-hentai.org/s/p1');
}

// ---------- 2. copy()：null 字段保持 null ----------
{
  const d = new GalleryDetail();
  const n = d.copy();
  eq('simpleTags 仍为 null', n.simpleTags, null);
  eq('tgList 仍为 null', n.tgList, null);
  eq('tags 仍为 null', n.tags, null);
  eq('comments 仍为 null', n.comments, null);
  eq('previewSet 仍为 null', n.previewSet, null);
  eq('newVersions 仍为 null', n.newVersions, null);
  eq('gid 默认 0', n.gid, 0);
}

// ---------- 3. getNewGalleryDetail：newVersions 为 null → 返回拷贝 ----------
{
  const d = makeDetail();
  d.newVersions = null;
  const n = d.getNewGalleryDetail(0);
  ok('newVersions=null 时返回的是**拷贝**（不是 this）', n !== d);
  eq('token 不变', n.token, 'aaaaaaaaaa');
  eq('gid 不变', n.gid, 42);
}

// ---------- 4. getNewGalleryDetail：正常切换 ----------
{
  const d = makeDetail();
  const nv = new NewVersion();
  // 真实 versionUrl 末尾**没有**斜杠（带斜杠时 split 的末段是空串，会落进异常分支）
  nv.versionUrl = 'https://e-hentai.org/g/777/bbbbbbbbbb';
  d.newVersions = [nv];

  const n = d.getNewGalleryDetail(0);
  eq('切换后 token 取自最后一段', n.token, 'bbbbbbbbbb');
  eq('切换后 gid 取自倒数第二段', n.gid, 777);
  eq('切换后 newVersions 被清空', n.newVersions, null);
  eq('原件 token 不变', d.token, 'aaaaaaaaaa');
  eq('原件 gid 不变', d.gid, 42);
  eq('原件 newVersions 不变', (d.newVersions as NewVersion[]).length, 1);

  // URL 末尾带斜杠：split 末段是空串、倒数第二段是 token → gid 解析得 NaN → 回退 this
  const d2 = makeDetail();
  const nv2 = new NewVersion();
  nv2.versionUrl = 'https://e-hentai.org/g/888/cccccccccc/';
  d2.newVersions = [nv2];
  const n2 = d2.getNewGalleryDetail(0);
  ok('尾斜杠 → gid 解析失败 → 返回 this', n2 === d2);
  eq('尾斜杠 → 原 token 不变', n2.token, 'aaaaaaaaaa');
}

// ---------- 5. getNewGalleryDetail：异常回退 this ----------
{
  const d = makeDetail();
  // index 越界 → 上游 catch 后 return this
  const n = d.getNewGalleryDetail(5);
  ok('index 越界 → 返回 this（上游 catch 行为）', n === d);

  // gid 段不是数字 → Number() 得 NaN → 回退 this
  const d3 = makeDetail();
  const nv = new NewVersion();
  nv.versionUrl = 'https://e-hentai.org/g/NOTANUMBER/tok';
  d3.newVersions = [nv];
  const n3 = d3.getNewGalleryDetail(0);
  ok('gid 非数字 → 返回 this（Long.parseLong 会抛）', n3 === d3);
}

console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('GalleryDetail copy 断言失败：' + fail);
}
