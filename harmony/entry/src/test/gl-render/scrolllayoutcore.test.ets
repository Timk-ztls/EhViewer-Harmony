/*
 * ScrollLayoutCore 单测 —— 纯几何，不依赖 GalleryView / 画布 / 动画
 *
 * 断言点全部来自上游 `ScrollLayoutManager.scrollInternal`（1095 行里最容易错的那几个数）：
 *   ① 横向只有放大后才可拖，且夹在 [-margin, 0]
 *   ② 向上滚动的 limit：index>0 时是 -height*RESERVATION+interval，index=0 时是 0
 *   ③ 向下滚动的 limit：hasNext 时 height*(1+RESERVATION)-interval，否则 height；最后与 bottom 取 min
 *   ④ 被挡住时 index>0 走「偏 1 像素 + forceFill」，index=0 走「越界效果 + remain 清零」
 */

import {
  RESERVATION, bottomLimit, canScrollUp, clampUp, reservation, scrollHorizontal, topLimit, tryScrollY,
  HorizontalScroll, VerticalClamp, VerticalStep
} from '../../main/ets/hippo/lib/glgallery/ScrollLayoutCore';

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

// ---------------------------------------------------------------- 0. 常量与 getReservation
{
  eq('RESERVATION = 1（上游 1f，这是**基值**）', RESERVATION, 1);

  // V-01 修复：上游 getReservation() = max(1, ((1+2*1)*scale-1)/2)
  eq('scale=1 → 1.0', reservation(1), 1);
  eq('scale=1.5 → 1.75', reservation(1.5), 1.75);
  eq('scale=2 → 2.5', reservation(2), 2.5);
  eq('scale=0.5 → 取基值 1（max 保底）', reservation(0.5), 1);

  // limit 必须随 reservation 变化 —— 这是 V-01 的核心
  eq('topLimit scale=1', topLimit(1, 1000, 8, reservation(1)), -1000 + 8);
  eq('topLimit scale=2 → 露出 2.5 屏', topLimit(1, 1000, 8, reservation(2)), -2500 + 8);
  eq('bottomLimit scale=2', bottomLimit(true, 1000, 8, 99999, reservation(2)), 3500 - 8);
}

// ---------------------------------------------------------------- 1. 横向：未放大不可拖
{
  // 页面宽 == 视口宽 → margin = 0 → 恒 0，且 changed = false
  const r: HorizontalScroll = scrollHorizontal(0, 50, 1080, 1080);
  eq('未放大 → offsetX 恒 0', r.offsetX, 0);
  eq('未放大 → changed=false', r.changed, false);
  eq('未放大 → margin=0', r.margin, 0);

  // 页面比视口窄（理论上不该出现）→ margin 负数，仍恒 0
  eq('页面比视口窄 → offsetX 仍 0', scrollHorizontal(-10, 30, 500, 1080).offsetX, 0);
}

// ---------------------------------------------------------------- 2. 横向：放大后的夹紧
{
  // 视口 1000，页面 2000 → margin = 1000，offsetX ∈ [-1000, 0]
  const view = 1000;
  const page = 2000;

  const a = scrollHorizontal(0, 100, page, view);   // 手指右移 100 → 内容左移
  eq('右移 → offsetX 变负', a.offsetX, -100);
  eq('右移 → changed', a.changed, true);
  eq('margin = 页面宽 - 视口宽', a.margin, 1000);

  const b = scrollHorizontal(0, -100, page, view);  // 手指左移 → 想露出左边，已到 0 则不动
  eq('已在 0 继续左移 → 夹到 0', b.offsetX, 0);
  eq('夹住 → changed=false', b.changed, false);

  const c = scrollHorizontal(-900, 200, page, view); // 想再往右拖 200，但只到 -1000
  eq('超过 -margin → 夹到 -1000', c.offsetX, -1000);
  eq('夹住但位置变了 → changed=true', c.changed, true);

  const d = scrollHorizontal(-1000, -50, page, view); // 往左拖 50 回到 -950
  eq('从 -margin 往左拖 → -950', d.offsetX, -950);

  const e = scrollHorizontal(-500, 0, page, view);
  eq('dx=0 → 不动', e.offsetX, -500);
  eq('dx=0 → changed=false', e.changed, false);
}

// ---------------------------------------------------------------- 3. 向上滚动的 limit
{
  eq('index=0 → limit 0（不能露空白）', topLimit(0, 2000, 8), 0);
  eq('index>0 → -height*RESERVATION + interval', topLimit(1, 2000, 8), -2000 + 8);
  eq('index>0 且 interval=0', topLimit(3, 1500, 0), -1500);
}

// ---------------------------------------------------------------- 4. 向下滚动的 limit
{
  // hasNext：height*(1+1) - interval，再与 bottom 取 min
  eq('hasNext → 2*height - interval（bottom 足够大时）',
    bottomLimit(true, 1000, 10, 99999), 2000 - 10);
  eq('!hasNext → height（bottom 足够大时）', bottomLimit(false, 1000, 10, 99999), 1000);
  // 页没填满：bottom 比 limit 小 → 取 bottom（上游注释 "Fix limit for page not fill screen"）
  eq('hasNext 但 bottom 更小 → 取 bottom', bottomLimit(true, 1000, 10, 600), 600);
  eq('!hasNext 且 bottom 更小 → 取 bottom', bottomLimit(false, 1000, 10, 300), 300);
}

// ---------------------------------------------------------------- 5. 能否容纳位移
{
  ok('剩余位移能被容纳', canScrollUp(-100, -50, 0));       // 目标 -50 > 0? 否：-100-(-50) = -50 <= 0 → true
  ok('恰好到 limit', canScrollUp(-50, -50, 0));           // -50+50 = 0 <= 0 → true
  ok('超出 limit → false', !canScrollUp(0, -50, 0));      // 0+50 = 50 > 0 → false
}

// ---------------------------------------------------------------- 6. 被挡住时的两种处理
{
  // index > 0：偏 1 像素避免死循环 + forceFill
  const up: VerticalClamp = clampUp(1, -1990, -100, -1992, false);
  eq('index>0 → offsetY = limit + 1', up.offsetY, -1991);
  eq('index>0 → remainY 加 1（避免死循环）', up.remainY, -99);
  eq('index>0 → forceFill', up.forceFill, true);
  eq('index>0 → 不越界', up.overScroll, false);

  // index == 0：越界效果，remain 清零
  const top: VerticalClamp = clampUp(0, -10, -100, 0, false);
  eq('index=0 → offsetY = limit', top.offsetY, 0);
  eq('index=0 → remainY 清零', top.remainY, 0);
  eq('index=0 且非 fling → 越界效果', top.overScroll, true);
  eq('index=0 → forceFill=false', top.forceFill, false);

  // fling 时不触发越界效果（上游 `if (!fling)`）
  eq('fling 时不越界', clampUp(0, -10, -100, 0, true).overScroll, false);
}

// ---------------------------------------------------------------- 7. tryScrollY 两步
{
  // 向上 **index>0**：limit = -2000+8 = -1992。判据是 `offsetY - remainY <= limit`，
  // 而"向上滚"让 offsetY 变**大**（趋近 0）→ 永远 > limit → **恒走 else 分支**
  // （上游那里调 forceFill()：不是"滚动"，是"上面要补内容然后重排"）。
  const a: VerticalStep = tryScrollY(-100, -50, 1, 2000, 8, true, 5000);
  eq('index>0 的向上位移不走"直接滚"分支', a.done, false);
  eq('index>0 → offsetY 原样交给 clampUp 处理', a.offsetY, -100);

  // 向上 **index=0**：limit = 0 → 目标 -50 <= 0 → 可以滚
  const a0: VerticalStep = tryScrollY(-100, -50, 0, 2000, 8, true, 5000);
  eq('index=0 向上可滚 → done', a0.done, true);
  eq('index=0 向上可滚 → offsetY 减 remainY', a0.offsetY, -50);

  // 向上：位于 limit 附近，再往上就超了
  const b: VerticalStep = tryScrollY(-1990, -10, 1, 2000, 8, true, 5000);
  eq('向上到顶 → done=false', b.done, false);
  eq('向上到顶 → offsetY 原样', b.offsetY, -1990);

  // 向下：hasNext，bottom 足够 → limit = 2000-8 = 1992；bottom - remainY = 5000-100 = 4900 >= 1992 → 可滚
  const c: VerticalStep = tryScrollY(0, 100, 0, 2000, 8, true, 5000);
  eq('向下可滚 → done', c.done, true);
  eq('向下可滚 → offsetY 减 remainY', c.offsetY, -100);

  // 向下：!hasNext 且 bottom 小 → limit=min(bottom,height)；bottom=300, remainY=100 → 300-100=200 >= 300? 否 → 挡住
  const d: VerticalStep = tryScrollY(0, 100, 0, 2000, 8, false, 300);
  eq('到底 → done=false', d.done, false);
  eq('到底 → offsetY 原样', d.offsetY, 0);
  // V-02：!hasNext 被挡住 → 回吸 offsetY -= (bottom-limit) = 0-(300-300)=0
  eq('到底 → clampedOffsetY 回吸', d.clampedOffsetY, 0);

  // V-02 补充用例（auditor 指出我漏的那条）：index==0 且 offsetY<0 的向上被挡住
  // limit = 0（index=0）→ offsetY - remainY = -100+300 = 200 > 0 → 挡住 → 回吸到 limit = 0
  const e: VerticalStep = tryScrollY(-100, -300, 0, 2000, 8, true, 5000);
  eq('index=0 向上被挡住 → done=false', e.done, false);
  eq('index=0 向上被挡住 → offsetY 原样', e.offsetY, -100);
  eq('index=0 向上被挡住 → **回吸到 limit=0**', e.clampedOffsetY, 0);

  // index>0 向上被挡住 → 回吸到 limit+1（偏 1 像素防死循环）
  const f: VerticalStep = tryScrollY(-1990, -10, 1, 2000, 8, true, 5000);
  eq('index>0 向上被挡住 → 回吸到 limit+1', f.clampedOffsetY, -1992 + 1);

  // 向下 hasNext 被挡住 → 回吸后再偏 1 像素
  // limit = min(1000, 2000-8)=1000；bottom=1000, remainY=100 → 900 >= 1000? 否 → 挡住
  const g: VerticalStep = tryScrollY(0, 100, 0, 2000, 8, true, 1000);
  eq('hasNext 向下被挡住 → done=false', g.done, false);
  eq('hasNext 向下被挡住 → 回吸并偏 1 像素', g.clampedOffsetY, (0 - (1000 - 1000)) - 1);
}


// W-07 反证（auditor-logic）：上游 `(int)` 是**向零截断**，不是 floor。
// 乘积非整数时才暴露差异：h=1001, r=1.75 → -1751.75 → trunc=-1751 / floor=-1752
eq('topLimit 非整数乘积按向零截断（上游 (int) 语义）', topLimit(1, 1001, 8, 1.75), -1751 + 8);
eq('topLimit scale=1.5 且 h=1001 仍是截断', topLimit(1, 1001, 8, reservation(1.5)), Math.trunc(-1001 * reservation(1.5)) + 8);

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('ScrollLayoutCore 断言失败：' + fails.length);
}
