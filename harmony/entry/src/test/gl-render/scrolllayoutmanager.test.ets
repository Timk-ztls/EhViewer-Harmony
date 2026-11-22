/*
 * ScrollLayoutManager 几何单测
 *
 * 这个 1095 行的文件此前**只有编译级验证**。这里锁住四个"改一行就翻页错位"的点
 * （Lead 给的四条判据）：
 *   ① `getReservation()` 随 scale 变化，且**接线对的**（不是 `reservation(1)`、也不是 `reservation(mScale)`）
 *   ② `isInScreen` 的三个条件**各自**都能单独让结果变 false
 *   ③ `getBottomState` 的累加（空集合 / 单页 / 多页）—— 累加的是"页高之和 + 间隔"，不是"页数 × 高度"
 *   ④ `getPageForIndex` 的移除语义 —— **不存在时返回 null 且不改动集合**
 *
 * 判据 ①②③④ 都打在**生产实现的同一份逻辑**上（实例方法委托给 static，static 是判定本体）。
 */

import { GalleryViewBuilder, GalleryAdapter, GalleryView } from '../../main/ets/hippo/lib/glgallery/GalleryView';
import { GalleryPageView } from '../../main/ets/hippo/lib/glgallery/GalleryPageView';
import { ScrollLayoutManager } from '../../main/ets/hippo/lib/glgallery/ScrollLayoutManager';
import { reservation } from '../../main/ets/hippo/lib/glgallery/ScrollLayoutCore';

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

class EmptyAdapter extends GalleryAdapter {
  onBind(view: GalleryPageView, index: number): void {}
  onUnbind(view: GalleryPageView, index: number): void {}
  getError(): string | null { return null; }
  size(): number { return 0; }
}

/** 造一个管理器（GalleryView 尺寸为 0，几何断言不依赖它）。 */
function makeManager(interval: number): ScrollLayoutManager {
  const galleryView: GalleryView = new GalleryViewBuilder(new EmptyAdapter()).build();
  return new ScrollLayoutManager(galleryView, interval);
}

// ============================================================ ① getReservation
{
  const m = makeManager(8);

  // 初始 mScale = 0.5 → reservation(0.5) = max(1, (3*0.5-1)/2 = 0.25) = 1
  eq('默认 mScale=0.5 → reserve=1（下界 clamp）', m.getReservationValue(), 1);

  m.setScaleForTest(1.0);
  eq('scale=1 → reserve=1', m.getReservationValue(), 1);

  m.setScaleForTest(1.5);
  eq('scale=1.5 → reserve=1.75', m.getReservationValue(), 1.75);

  m.setScaleForTest(2.0);
  eq('scale=2 → reserve=2.5', m.getReservationValue(), 2.5);

  // ★ 反证（Lead 判据①）：接线若写成 reservation(1) 或 reservation(mScale) 直接传，
  //   下面两条会红：
  //   ① 若写成常量 1 → scale=2 时 reserve 会是 1，而不是 2.5
  //   ② 若把 mScale 自己传进去当"reserve"→ scale=2 时 reserve 会是 2，而不是 2.5
  ok('反证：reserve 不是常量 1（scale=2 时 ≠ 1）', m.getReservationValue() !== 1);
  ok('反证：reserve 不等于 mScale 本身（scale=2 时 ≠ 2）', m.getReservationValue() !== 2.0);
  // 正证：与 Core 的公式逐点一致（接线正确 + Core 公式正确，一次验两件事）
  for (const s of [0.5, 1.0, 1.25, 1.5, 1.75, 2.0]) {
    m.setScaleForTest(s);
    eq(`与 Core 的 reservation(${s}) 一致`, m.getReservationValue(), reservation(s));
  }
}

// ============================================================ ② isInScreen 三条件
{
  const H = 1000;

  // 条件 1：页顶在屏内（0 <= top < H）
  eq('条件1：top 在屏内 → true', ScrollLayoutManager.isInScreenRect(100, 400, H), true);
  eq('条件1 反：top == H（刚好在屏下）→ 条件2/3 都不成立 → false',
    ScrollLayoutManager.isInScreenRect(H, 1400, H), false);
  eq('条件1 反：top < 0 且 bottom <= H（页在屏上方）→ false',
    ScrollLayoutManager.isInScreenRect(-400, -100, H), false);

  // 条件 2：页底在屏内（0 < bottom <= H）
  eq('条件2：bottom 在屏内（top 也在屏上方之内但 top>=0）→ true',
    ScrollLayoutManager.isInScreenRect(900, 950, H), true);
  // 条件 1 独立成立：top 在屏内时，即使 bottom 远超屏底也可见（长页）
  //   —— 这正是"条件 1"存在的理由；若只写 `top<H && bottom>0` 的简化判定，这里仍是 true，
  //      但 top=-100/bottom=1100 那种"完全覆盖"就会漏（见条件 3）
  eq('条件1 独立成立：top 在屏内、bottom 超屏底 → true',
    ScrollLayoutManager.isInScreenRect(100, 1200, H), true);
  // 三个条件**全不满足**的唯一形态：top >= H（在屏下方）
  eq('条件2 反：top >= H 且 bottom > H → 三条件全不满足 → false',
    ScrollLayoutManager.isInScreenRect(1200, 1500, H), false);

  // 条件 3：页完全覆盖屏幕（top < 0 && bottom > H）
  eq('条件3：完全覆盖 → true', ScrollLayoutManager.isInScreenRect(-100, 1100, H), true);
  eq('条件3 反：top < 0 但 bottom 不到屏底 → 由条件2 决定（bottom>0 且 <=H）→ true',
    ScrollLayoutManager.isInScreenRect(-100, 500, H), true);

  // 三个条件**各自**能单独成立的组合（缺任一条都会漏判）
  ok('三条判定的并集覆盖：上边缘露一部分', ScrollLayoutManager.isInScreenRect(-50, 100, H));
  ok('三条判定的并集覆盖：跨屏', ScrollLayoutManager.isInScreenRect(-50, 1050, H));
  ok('三条判定的并集覆盖：屏内小页', ScrollLayoutManager.isInScreenRect(200, 300, H));

  // 边界：top == 0（条件1 成立）；bottom == H（条件2 成立）
  eq('边界 top=0 → 条件1 成立', ScrollLayoutManager.isInScreenRect(0, 500, H), true);
  eq('边界 bottom=H → 条件2 成立', ScrollLayoutManager.isInScreenRect(500, H, H), true);
  eq('边界 bottom=0 → 条件2 不成立（要求 >0）', ScrollLayoutManager.isInScreenRect(0, 0, H), true);
}

// ============================================================ ③ getBottomState 累加
{
  const interval = 8;
  // 空集合：bottom 就是起点，不再加任何东西
  eq('空页集合 → bottom = startTop', ScrollLayoutManager.computeBottom([], 0, interval), 0);
  eq('空页集合（startTop=-100）', ScrollLayoutManager.computeBottom([], -100, interval), -100);

  // 单页：bottom = startTop + 页高（**不加 interval**）
  eq('单页 → startTop + 高（无 interval）',
    ScrollLayoutManager.computeBottom([500], 0, interval), 500);
  eq('单页 startTop=-50', ScrollLayoutManager.computeBottom([500], -50, interval), 450);

  // 多页：n 页只有 (n-1) 个 interval
  eq('两页 → 高之和 + 1 个 interval',
    ScrollLayoutManager.computeBottom([500, 600], 0, interval), 500 + 8 + 600);
  eq('三页 → 高之和 + 2 个 interval',
    ScrollLayoutManager.computeBottom([300, 400, 500], 0, interval), 300 + 8 + 400 + 8 + 500);

  // ★ 反证：不是"页数 × 高度"也不是"页数 × (高度 + interval)"
  ok('反证：不等于 页数×(高+interval)',
    ScrollLayoutManager.computeBottom([300, 400, 500], 0, interval) !== 3 * (400 + 8));
  ok('反证：不等于 页高之和 + 页数个 interval',
    ScrollLayoutManager.computeBottom([300, 400, 500], 0, interval) !== 1200 + 3 * 8);
}

// ============================================================ ④ getPageForIndex 移除语义
{
  const m = makeManager(8);

  // 用真实 GalleryPageView 做集合（`obtainPage()` 会走池化；索引用 setIndex 注入）
  const p0: GalleryPageView = m.obtainPageViewForTest();
  const p1: GalleryPageView = m.obtainPageViewForTest();
  const p2: GalleryPageView = m.obtainPageViewForTest();
  p0.setIndex(0);
  p1.setIndex(1);
  p2.setIndex(2);

  const pages: GalleryPageView[] = [p0, p1, p2];
  eq('indexOfPage(1) = 1', ScrollLayoutManager.indexOfPage(pages, 1), 1);
  eq('indexOfPage(99) = -1', ScrollLayoutManager.indexOfPage(pages, 99), -1);

  // 存在 → 移除并返回
  const removed = m.pageForIndexOfTest(pages, 1, true);
  ok('存在 → 返回该页', removed === p1);
  eq('存在 → 集合长度减一', pages.length, 2);
  eq('存在 → 剩余索引顺序', pages.map((p: GalleryPageView) => p.getIndex()), [0, 2]);

  // 不存在 → 返回 null 且**不改动集合**（这是"移除语义"的真判据）
  const before = pages.length;
  const missing = m.pageForIndexOfTest(pages, 42, true);
  eq('不存在 → 返回 null', missing, null);
  eq('不存在 → 集合长度不变', pages.length, before);
  eq('不存在 → 集合内容不变', pages.map((p: GalleryPageView) => p.getIndex()), [0, 2]);

  // remove=false → 找到但不移除
  const kept = m.pageForIndexOfTest(pages, 0, false);
  ok('remove=false → 找到该页', kept === p0);
  eq('remove=false → 集合长度不变', pages.length, 2);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
