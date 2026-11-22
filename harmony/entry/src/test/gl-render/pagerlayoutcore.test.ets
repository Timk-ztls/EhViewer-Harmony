/*
 * PagerLayoutCore 单测 —— 纯几何，不依赖 GalleryView / 画布 / 动画
 *
 * 断言点全部来自上游 `PagerLayoutManager.onFill()` 的布局段与 `onUp()` 的回弹段：
 *   ① offset 夹紧：两侧是否有页决定 min/max，且带 ±1 像素补偿
 *   ② 三页的位置公式（current / left / right）
 *   ③ 方向映射：MODE_LEFT_TO_RIGHT ↔ 默认（RIGHT_TO_LEFT）左右互换
 *   ④ 抬手位移：判据是 |offset| >= interval 且对侧有页 —— **不是半屏阈值**
 */

import {
  MODE_LEFT_TO_RIGHT, MODE_RIGHT_TO_LEFT, PagerRect, clampPagerOffset, isLeftPagePrevious,
  isRightPagePrevious, placeCurrentPage, placeLeftPage, placeRightPage, scrollBetweenPages, snapDx,
  snapDuration, ScrollBetweenResult
} from '../../main/ets/hippo/lib/glgallery/PagerLayoutCore';

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

// ---------------------------------------------------------------- 1. 常量
{
  eq('MODE_LEFT_TO_RIGHT = 0', MODE_LEFT_TO_RIGHT, 0);
  eq('MODE_RIGHT_TO_LEFT = 1（上游默认）', MODE_RIGHT_TO_LEFT, 1);
}

// ---------------------------------------------------------------- 2. offset 夹紧
{
  const w = 1000;
  const i = 8;

  // 两侧都有页：[-1000-8+1, 1000+8-1] = [-1007, 1007]
  eq('两侧都有页 → 上界', clampPagerOffset(5000, true, true, w, i), 1007);
  eq('两侧都有页 → 下界', clampPagerOffset(-5000, true, true, w, i), -1007);
  eq('区间内不变', clampPagerOffset(123, true, true, w, i), 123);

  // 第一页（无**上一页**）：默认模式（RIGHT_TO_LEFT）下 left = 下一页、right = 上一页，
  // 所以"没有上一页"= rightPage 为 null → **min = 0**（不能向负方向露空白），
  // 但 max 仍可到 +1007（向正方向露出"下一页"）。
  eq('第一页 → 不能小于 0', clampPagerOffset(-50, true, false, w, i), 0);
  eq('第一页 → 可以到 +1007', clampPagerOffset(5000, true, false, w, i), 1007);

  // 最后一页（无**下一页**）：leftPage 为 null → **max = 0**，但 min 可到 -1007。
  eq('最后一页 → 不能大于 0', clampPagerOffset(50, false, true, w, i), 0);
  eq('最后一页 → 可以到 -1007', clampPagerOffset(-5000, false, true, w, i), -1007);

  // 单页（两侧都无）：恒 0
  eq('只有一页 → 恒 0', clampPagerOffset(-999, false, false, w, i), 0);
  eq('只有一页 → 恒 0（正方向）', clampPagerOffset(999, false, false, w, i), 0);

  // ±1 补偿的意义：夹到边界后仍 != 0，所以"翻页中"可判定
  ok('边界值仍非 0（±1 补偿的意义）', clampPagerOffset(-5000, true, true, w, i) !== 0);
}

// ---------------------------------------------------------------- 3. 三页位置
{
  const w = 1000;
  const h = 2000;
  const i = 8;

  const cur: PagerRect = placeCurrentPage(0, w, h);
  eq('当前页 left', cur.left, 0);
  eq('当前页 right', cur.right, 1000);

  const cur2: PagerRect = placeCurrentPage(-300, w, h);
  eq('偏移 -300 → left', cur2.left, -300);
  eq('偏移 -300 → right', cur2.right, 700);

  const left: PagerRect = placeLeftPage(0, w, h, i);
  eq('左页 left = -interval-width', left.left, -8 - 1000);
  eq('左页 right = -interval', left.right, -8);
  eq('左页宽度仍是 width', left.right - left.left, w);

  const right: PagerRect = placeRightPage(0, w, h, i);
  eq('右页 left = width+interval', right.left, 1000 + 8);
  eq('右页 right = width+interval+width', right.right, 1000 + 8 + 1000);
  eq('右页宽度仍是 width', right.right - right.left, w);

  // 有偏移时三页整体平移
  const leftShifted: PagerRect = placeLeftPage(-100, w, h, i);
  eq('偏移 -100 → 左页整体平移', leftShifted.left, -8 - 1000 - 100);
}

// ---------------------------------------------------------------- 4. 方向映射
{
  eq('LEFT_TO_RIGHT：左侧是上一页', isLeftPagePrevious(MODE_LEFT_TO_RIGHT), true);
  eq('LEFT_TO_RIGHT：右侧是下一页', isRightPagePrevious(MODE_LEFT_TO_RIGHT), false);
  eq('RIGHT_TO_LEFT（默认）：左侧是下一页', isLeftPagePrevious(MODE_RIGHT_TO_LEFT), false);
  eq('RIGHT_TO_LEFT（默认）：右侧是上一页', isRightPagePrevious(MODE_RIGHT_TO_LEFT), true);
}

// ---------------------------------------------------------------- 5. 抬手位移（判据是 interval，不是半屏）
{
  const w = 1000;
  const i = 8;

  // 未越过中缝：回弹到 0（dx = offset 本身）
  eq('offset 小于 interval → 回弹', snapDx(5, w, i, true, true), 5);
  eq('offset 为负但未到 -interval → 回弹', snapDx(-5, w, i, true, true), -5);

  // 越过左侧：dx = offset - width - interval（对齐左页起点）
  eq('越过左侧且有左页 → 翻到左页', snapDx(900, w, i, true, true), 900 - 1000 - 8);
  // 越过左侧但**没有左页** → 仍然回弹
  eq('越过左侧但没有左页 → 回弹', snapDx(900, w, i, false, true), 900);

  // 越过右侧
  eq('越过右侧且有右页 → 翻到右页', snapDx(-900, w, i, true, true), -900 + 1000 + 8);
  eq('越过右侧但没有右页 → 回弹', snapDx(-900, w, i, true, false), -900);

  // 恰好等于 ±interval 时就算"越过"（>= / <=）
  eq('恰好 +interval 且有左页 → 翻页', snapDx(i, w, i, true, true), i - w - i);
  eq('恰好 -interval 且有右页 → 翻页', snapDx(-i, w, i, true, true), -i + w + i);
}

// ---------------------------------------------------------------- 6. 回弹时长
{
  const w = 1000;
  const i = 8;
  // offset=0 → pageDelta=0 → duration=100
  eq('offset=0 → 100ms 基础时长', snapDuration(0, w, i), 100);
  // |offset|=504 → 7*504/1008 = 3.5 → (3.5+1)*100 = 450
  eq('半屏 → 450ms', snapDuration(-504, w, i), 450);
  // 取绝对值：正负对称
  eq('正负对称', snapDuration(504, w, i), snapDuration(-504, w, i));
  // 满屏：7*1008/1008=7 → 800
  eq('满一屏 → 800ms', snapDuration(1008, w, i), 800);
}

// ---------------------------------------------------------------- 7. 页间滚动（scrollBetweenPages）
{
  const w = 1000;
  const i = 8;

  // ① dx<0 且在页内推进：offset 只是加 dx，不翻页（remain=0, flip=0）
  //    limit = 1008（有左页）；判据 dx > offset-limit → -100 > 0-1008 = -1008 → 成立 → 只推进
  const a: ScrollBetweenResult = scrollBetweenPages(-100, 0, w, i, true, true);
  eq('页内推进（dx<0）→ remain 0', a.remain, 0);
  eq('页内推进（dx<0）→ offset -= dx（上游写法）', a.offset, 100);
  eq('页内推进（dx<0）→ 不翻页', a.flip, 0);

  // ② dx<0 越过一页：limit=1008，dx=-2000 → -2000 > -1008? 否 → 翻左页
  const b: ScrollBetweenResult = scrollBetweenPages(-2000, 0, w, i, true, true);
  eq('越过左页 → remain = dx+limit-offset', b.remain, -2000 + 1008 - 0);
  eq('越过左页 → offset 归零', b.offset, 0);
  eq('越过左页 → flip=-1（pageLeft）', b.flip, -1);

  // ③ dx<0 但没有左页：limit=0 → 判据 dx > offset-0 = 0 → -100 > 0? 否 → 走翻页分支但 flip=0
  const c: ScrollBetweenResult = scrollBetweenPages(-100, 0, w, i, false, true);
  eq('没有左页 → flip=0（不翻）但 remain 按公式给', c.flip, 0);
  eq('没有左页 → remain = dx + 0 - 0', c.remain, -100);
  eq('没有左页 → offset 归零', c.offset, 0);

  // ④ dx>0 在页内推进：limit = -1008（有右页）；判据 dx < offset-limit → 100 < 0+1008 → 成立
  const d: ScrollBetweenResult = scrollBetweenPages(100, 0, w, i, true, true);
  eq('页内推进（dx>0）→ remain 0', d.remain, 0);
  eq('页内推进（dx>0）→ offset -= dx（上游写法）', d.offset, -100);
  eq('页内推进（dx>0）→ 不翻页', d.flip, 0);

  // ⑤ dx>0 越过一页：dx=2000 → 2000 < 1008? 否 → 翻右页
  const e: ScrollBetweenResult = scrollBetweenPages(2000, 0, w, i, true, true);
  eq('越过右页 → remain = dx-limit-offset', e.remain, 2000 - 1008 - 0);
  eq('越过右页 → flip=+1（pageRight）', e.flip, 1);

  // ⑥ **反证**：若把 dx>0 分支的 limit 写成 +width+interval（方向写反 → 1008）
  //    判据变成 dx < offset-1008 = -1008 → 100 < -1008 为假 → **每一帧都翻页**（症状：疯狂跳页）
  const wrongLimit = 1008;
  const wouldFlipEveryFrame: boolean = !(100 < 0 - wrongLimit);
  ok('反证：limit 方向写反 → 页内推进会误判为翻页（每帧跳页）', wouldFlipEveryFrame);

  // ⑦ 反证：dx<0 分支若漏掉 `hasLeftPage ? width+interval : 0` 里的宽度项（limit=0）
  //    → 判据 -100 > 0 恒假 → **永远进翻页分支**，即使只想挪 100px
  const wouldAlwaysFlip: boolean = !(-100 > 0);
  ok('反证：漏掉 width 项 → 任何负向位移都误翻页', wouldAlwaysFlip);
}
console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('PagerLayoutCore 断言失败：' + fails.length);
}