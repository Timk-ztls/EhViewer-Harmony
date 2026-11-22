/*
 * EhTopListAdapter 纯逻辑单测
 *
 * 这个适配器在 ArkUI 侧只剩三件事可独立断言：
 * 1. `timeInfoId(index)` —— 时间段标题键（`default` 与 `case 3` 合并，index>=4 与负数都落到"全部时间"）
 * 2. `urlFollow(index)` —— **tl 取值不是按索引递增**（0→15, 1→13, 2→12, 3→11），最容易被"顺手整理"
 * 3. `toRow/toRows/itemAt` —— 数据映射与越界行为（`TopListInfo.get()` 越界返回 null）
 */

import {
  TopListItem,
  TopListItemArray,
  TopListInfo,
  TopListType
} from '../../main/ets/hippo/ehviewer/client/data/TopList';
import {
  EhTopListAdapter,
  EhTopListRow
} from '../../main/ets/hippo/ehviewer/ui/scene/topList/EhTopListAdapter';

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}

/** 具体化抽象适配器（三个抽象方法给空实现）。 */
class ProbeAdapter extends EhTopListAdapter {
  clickTitle(urlFollow: string): void {}
  getRandomColor(position: number): number { return 0xFF000000; }
  onItemClick(topListItem: TopListItem, searchType: number): void {}
}

function makeItem(value: string): TopListItem {
  const item = new TopListItem();
  item.value = value;
  return item;
}

function makeArray(values: string[]): TopListItemArray {
  const arr = new TopListItemArray();
  const items: TopListItem[] = [];
  for (const v of values) {
    items.push(makeItem(v));
  }
  arr.itemArray = items;
  return arr;
}

function makeInfo(type: number): TopListInfo {
  const info = new TopListInfo();
  info.type = type;
  info.yesterdayTopList = makeArray(['y0', 'y1']);
  info.pastMonthTopList = makeArray(['m0']);
  info.pastYearTopList = makeArray(['r0', 'r1', 'r2']);
  info.allTimeTopList = makeArray(['a0']);
  return info;
}

// ---------- 1) timeInfoId ----------
{
  eq('index 0 → yesterday', EhTopListAdapter.timeInfoId(0), 'yesterday_top_list');
  eq('index 1 → past month', EhTopListAdapter.timeInfoId(1), 'past_month_top_list');
  eq('index 2 → past year', EhTopListAdapter.timeInfoId(2), 'past_year_top_list');
  eq('index 3 → all time', EhTopListAdapter.timeInfoId(3), 'all_time_top_list');
  // 上游 default 与 case 3 合并 → 越界/负数 = 全部时间
  eq('index 4 → all time (default)', EhTopListAdapter.timeInfoId(4), 'all_time_top_list');
  eq('index -1 → all time (default)', EhTopListAdapter.timeInfoId(-1), 'all_time_top_list');
}

// ---------- 2) urlFollow（tl 非递增，防"顺手整理"） ----------
{
  eq('index 0 → tl=15', EhTopListAdapter.urlFollow(0), 'tl=15');
  eq('index 1 → tl=13', EhTopListAdapter.urlFollow(1), 'tl=13');
  eq('index 2 → tl=12', EhTopListAdapter.urlFollow(2), 'tl=12');
  eq('index 3 → tl=11', EhTopListAdapter.urlFollow(3), 'tl=11');
  eq('index 9 → tl=11 (default)', EhTopListAdapter.urlFollow(9), 'tl=11');
  ok('tl values are NOT ascending by index',
    !(parseInt(EhTopListAdapter.urlFollow(0).substring(3))
      < parseInt(EhTopListAdapter.urlFollow(3).substring(3))));
}

// ---------- 3) size / itemCount / itemAt ----------
{
  const a = new ProbeAdapter(makeInfo(TopListType.GALLERY), 7);
  eq('size is always 4 (four time ranges)', a.size(), 4);
  eq('itemCount(0)', a.itemCount(0), 2);
  eq('itemCount(1)', a.itemCount(1), 1);
  eq('itemCount(2)', a.itemCount(2), 3);
  eq('itemCount(3)', a.itemCount(3), 1);
  eq('itemCount(out of range) → 0', a.itemCount(4), 0);
  eq('itemAt(0,1).value', a.itemAt(0, 1)?.value, 'y1');
  eq('itemAt out of range → null', a.itemAt(0, 5), null);
  eq('itemAt bad position → null', a.itemAt(99, 0), null);
  eq('searchType preserved', a.getSearchType(), 7);
}

// ---------- 4) toRow / toRows（GALLERY 才可点标题） ----------
{
  const gallery = new ProbeAdapter(makeInfo(TopListType.GALLERY), 0);
  const row0 = gallery.toRow(0);
  ok('gallery row0 exists', row0 !== null);
  eq('row0 timeInfoId', row0?.timeInfoId, 'yesterday_top_list');
  eq('row0 item count', row0?.items.length, 2);
  eq('row0 titleClickable (GALLERY)', row0?.titleClickable, true);
  eq('row0 urlFollow', row0?.urlFollow, 'tl=15');

  const rows = gallery.toRows();
  eq('toRows length', rows.length, 4);
  eq('toRows[3] is all time', rows[3].timeInfoId, 'all_time_top_list');

  // 非 GALLERY：标题不可点，urlFollow 为空
  const uploader = new ProbeAdapter(makeInfo(TopListType.UPLOADER), 0);
  const uRow = uploader.toRow(0);
  eq('non-gallery titleClickable', uRow?.titleClickable, false);
  eq('non-gallery urlFollow empty', uRow?.urlFollow, '');
}

// ---------- 5) 空数组 / null 时间段 ----------
{
  const info = new TopListInfo();
  info.type = TopListType.GALLERY;
  info.yesterdayTopList = makeArray([]);
  // pastMonth / pastYear / allTime 保持 null
  const a = new ProbeAdapter(info, 0);
  eq('empty array → itemCount 0', a.itemCount(0), 0);
  eq('null array → itemCount 0', a.itemCount(1), 0);
  eq('null array → toRow null', a.toRow(1), null);
  const rows = a.toRows();
  eq('toRows skips null rows', rows.length, 1);
  eq('kept row is the empty one', rows[0].items.length, 0);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
