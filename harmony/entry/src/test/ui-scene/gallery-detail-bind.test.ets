/*
 * 单测：GalleryDetailScene Part 2（S0232）的绑定判据
 *
 * 钉住的六条（都是"写错也能编译、但详情页数字/标签/更多按钮会错"）：
 *   ① pages 两个分支不能合并（startPage=-1 与 startPage=0 结果同为 0/N，来源不同）
 *   ② favoredTimes / torrent 计数 0 → **整行隐藏**
 *   ③ 标签组名翻译键是 `n:<group>`，标签翻译键是 `prefix + tag`（**两套键**）
 *   ④ namespaceToPrefix 返回 null → 回落**空串**
 *   ⑤ 标签显示串 vs 点击串不同（点击是全串 group:tag）
 *   ⑥ 评论三态：空→NONE / `<=max`→ALL_SHOWN / >max→MORE_AVAILABLE
 */

import {
  GalleryDetailBind, KeyValueField, TagGroupView, TagChip, MoreState,
  MAX_SHOW_COMMENTS, stripTagNamespace
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/detail/GalleryDetailBind';
import { GalleryTagGroup } from '../../main/ets/hippo/ehviewer/client/data/GalleryTagGroup';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}\n    got  ${g}\n    want ${w}`); }
}

function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(`${name}  (want true)`); }
}

function group(name: string, tags: string[]): GalleryTagGroup {
  const g: GalleryTagGroup = new GalleryTagGroup();
  g.groupName = name;
  for (const t of tags) { g.addTag(t); }
  return g;
}

// ---------------------------------------------------------------- ① pages

function testPages(): void {
  eq('未读（startPage=-1）→ 0/N', GalleryDetailBind.pagesText(-1, 20), '0/20P');
  eq('第 0 页（startPage=0）→ 1/N', GalleryDetailBind.pagesText(0, 20), '1/20P');
  eq('第 5 页 → 6/N', GalleryDetailBind.pagesText(5, 20), '6/20P');
  // 关键：两个分支结果不同（合并实现会让 -1 也变 1/N 或 0 变 0/N）
  ok('两个分支结果不同（不可合并）',
    GalleryDetailBind.pagesText(-1, 20) !== GalleryDetailBind.pagesText(0, 20));
}

// ---------------------------------------------------------------- ② 计数 0 → 隐藏

function testCounts(): void {
  eq('收藏数 0 → 隐藏', GalleryDetailBind.favoredTimesField(0, '1 次').visible, false);
  eq('收藏数 0 → 文案为空', GalleryDetailBind.favoredTimesField(0, '1 次').text, '');
  eq('收藏数 3 → 可见', GalleryDetailBind.favoredTimesField(3, '3 次').visible, true);
  eq('收藏数 3 → 文案透传', GalleryDetailBind.favoredTimesField(3, '3 次').text, '3 次');

  eq('种子数 0 → 隐藏', GalleryDetailBind.torrentField(0, '1 个').visible, false);
  eq('种子数 2 → 可见', GalleryDetailBind.torrentField(2, '2 个').visible, true);
  eq('字段 id 是 favoredTimes', GalleryDetailBind.favoredTimesField(1, 'x').id, 'favoredTimes');
  eq('字段 id 是 torrent', GalleryDetailBind.torrentField(1, 'x').id, 'torrent');

  const plain: KeyValueField[] = GalleryDetailBind.plainFields('Chinese', '12 MB', '2024-01-01');
  eq('plainFields 4 格', plain.length, 4);
  eq('language 文案', plain[0].text, 'Chinese');
  eq('全部可见', plain.every((f: KeyValueField): boolean => f.visible), true);
}

// ---------------------------------------------------------------- ③④⑤ 标签组

function testTagGroups(): void {
  const groups: GalleryTagGroup[] = [group('female', ['swimsuit', 'glasses'])];

  // 有翻译：组名键 n:female，标签键 prefix+tag（prefix 由 prefixOf 注入，这里模拟 "f:"）
  const translate = (key: string): string | null => {
    if (key === 'n:female') { return '女性'; }
    if (key === 'f:swimsuit') { return '泳装'; }
    return null;
  };
  const prefixOf = (g: string): string | null => (g === 'female' ? 'f:' : null);

  const views: TagGroupView[] = GalleryDetailBind.buildTagGroups(groups, translate, prefixOf);
  eq('一组', views.length, 1);
  eq('组名用翻译', views[0].displayName, '女性');
  eq('组内 2 个标签', views[0].tags.length, 2);
  eq('标签用翻译', views[0].tags[0].display, '泳装');
  eq('标签无翻译则回落原名', views[0].tags[1].display, 'glasses');
  eq('点击串是全串（有翻译时也不同）', views[0].tags[0].fullTag, 'female:swimsuit');

  // prefixOf 返回 null → 回落空串（键变成 tag 本身）
  const seen: string[] = [];
  const translateSpy = (key: string): string | null => { seen.push(key); return null; };
  GalleryDetailBind.buildTagGroups([group('male', ['netorare'])], translateSpy,
    (_g: string): string | null => null);
  ok('prefix=null 时标签键是裸 tag（不是 n: 也不是 null+tag）',
    seen.indexOf('netorare') >= 0);

  // translate=null（未启用翻译）→ 全部原名
  const raw: TagGroupView[] = GalleryDetailBind.buildTagGroups(groups, null, prefixOf);
  eq('未启用翻译：组名原名', raw[0].displayName, 'female');
  eq('未启用翻译：标签原名', raw[0].tags[0].display, 'swimsuit');
  eq('未启用翻译：点击串仍全串', raw[0].tags[0].fullTag, 'female:swimsuit');

  // 可见性互斥
  eq('有标签 → tags visible', GalleryDetailBind.tagsVisible(groups), true);
  eq('有标签 → noTags 不显示', GalleryDetailBind.noTagsVisible(groups), false);
  eq('null → noTags 显示', GalleryDetailBind.noTagsVisible(null), true);
  eq('空数组 → noTags 显示', GalleryDetailBind.noTagsVisible([]), true);
  eq('空数组 → 渲染 0 组', GalleryDetailBind.buildTagGroups([], null, prefixOf).length, 0);
}

// ---------------------------------------------------------------- ⑥ 三态

function testMoreState(): void {
  eq('0 条 → NONE', GalleryDetailBind.moreStateOf(0, MAX_SHOW_COMMENTS), MoreState.NONE);
  eq('1 条 → ALL_SHOWN', GalleryDetailBind.moreStateOf(1, 2), MoreState.ALL_SHOWN);
  eq('**正好 2 条 → ALL_SHOWN**（是 <= 不是 <）',
    GalleryDetailBind.moreStateOf(2, 2), MoreState.ALL_SHOWN);
  eq('3 条 → MORE_AVAILABLE', GalleryDetailBind.moreStateOf(3, 2), MoreState.MORE_AVAILABLE);

  eq('评论 NONE 文案', GalleryDetailBind.commentStateRes(MoreState.NONE), 'no_comments');
  eq('评论 ALL_SHOWN 文案', GalleryDetailBind.commentStateRes(MoreState.ALL_SHOWN), 'no_more_comments');
  eq('评论 MORE 文案', GalleryDetailBind.commentStateRes(MoreState.MORE_AVAILABLE), 'more_comment');

  eq('预览 NONE 文案（键不同）', GalleryDetailBind.previewStateRes(MoreState.NONE), 'no_previews');
  eq('预览 ALL_SHOWN 文案', GalleryDetailBind.previewStateRes(MoreState.ALL_SHOWN), 'no_more_previews');
  eq('预览 MORE 文案', GalleryDetailBind.previewStateRes(MoreState.MORE_AVAILABLE), 'more_previews');
  ok('评论与预览文案不共用键',
    GalleryDetailBind.commentStateRes(MoreState.NONE) !== GalleryDetailBind.previewStateRes(MoreState.NONE));

  eq('显示条数 min(2,5)', GalleryDetailBind.shownCount(5, 2), 2);
  eq('显示条数 min(2,1)', GalleryDetailBind.shownCount(1, 2), 1);
  eq('MAX_SHOW_COMMENTS 是 2', MAX_SHOW_COMMENTS, 2);

  eq('stripTagNamespace 剥离 female:sole female', stripTagNamespace('female:sole female'), 'sole female');
  eq('stripTagNamespace 剥离 reclass:manga', stripTagNamespace('reclass:manga'), 'manga');
  eq('stripTagNamespace 无前缀原样返回', stripTagNamespace('plain_tag'), 'plain_tag');
  eq('stripTagNamespace 保留第二个冒号后的内容', stripTagNamespace('foo:bar:baz'), 'bar:baz');
}

function main(): void {
  testPages();
  testCounts();
  testTagGroups();
  testMoreState();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) { console.error('  - ' + f); }
    throw new Error('gallery detail bind test failed');
  }
  console.log(`✓ download-sync 详情页 Part2 批: ${pass} 条断言全部通过`);
}

main();