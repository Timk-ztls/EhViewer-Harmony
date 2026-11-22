/*
 * PagerLayoutManager 可断言面（M-01 最小可交付的第二半）
 *
 * ## 范围（Lead 裁定：4~6 条"能确定"的断言，其余显式标"属真机验收"）
 * 这里只断言**不需要真实页池/画布**就能确定的性质：
 *   ① `setMode` / `getMode` 的状态机（含"同值不重排"的早退）
 *   ② `setInterval` / `getInterval`（含"同值早退"）
 *   ③ 未 fill 时的 `canScale()` / `getCurrentIndex()` / `getInternalCurrentIndex()`
 *   ④ `setCurrentIndex` 越界不崩
 *   ⑤ `findPageByIndex` 空池返回 null
 *   ⑥ mode 常量与 `PagerLayoutCore.isLeftPagePrevious` 的语义一致性
 *
 * ## 明确**不在**单测范围（属真机验收）
 * - 三页池（`mPagerPrevious/mPagerCurrent/mPagerNext`）的 obtain/release **配对时序**
 * - `scrollInternal` 里 `snapDx` 的守卫（`if (mOffset != 0)`）与 smooth scroller 启动
 * - 边视图 `GLEdgeView` 的 pull/release/absorb 时序
 * 这些在真机上一眼可见（视觉错位/闪烁），比在 Node 里模拟更可靠。
 *
 * ## ⚠️ T-01 复述
 * 所有 `class` 声明写在执行块之前 —— TS/CJS 类声明不提升（TDZ），
 * 且抛出的异常会被生产 `try/catch + hilog.warn` 吞掉，症状只剩"断言莫名不过"。
 */

import { GalleryViewBuilder, GalleryAdapter, GalleryView } from '../../main/ets/hippo/lib/glgallery/GalleryView';
import { GalleryPageView } from '../../main/ets/hippo/lib/glgallery/GalleryPageView';
import { PagerLayoutManager } from '../../main/ets/hippo/lib/glgallery/PagerLayoutManager';
import {
  MODE_LEFT_TO_RIGHT, MODE_RIGHT_TO_LEFT, isLeftPagePrevious, isRightPagePrevious
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

class StubAdapter extends GalleryAdapter {
  total: number;
  constructor(total: number) { super(); this.total = total; }
  onBind(view: GalleryPageView, index: number): void {}
  onUnbind(view: GalleryPageView, index: number): void {}
  getError(): string | null { return null; }
  size(): number { return this.total; }
}

/** 造一个"已装配但未 fill"的 PagerLayoutManager（用 M-01 的 setSizeForTest）。 */
function makeManager(total: number): PagerLayoutManager {
  const adapter = new StubAdapter(total);
  const gv: GalleryView = new GalleryViewBuilder(adapter).build();
  gv.setSizeForTest(1080, 1920);
  // 构造签名：galleryView, scaleMode, startPosition, scaleValue, interval
  const manager = new PagerLayoutManager(gv, 0, 0, 1.0, 8);
  manager.onAttach(adapter);
  return manager;
}

// ============================================================ ① mode 状态机
{
  const m = makeManager(5);
  // ★ 默认是 RIGHT_TO_LEFT（**反直觉，但上游如此**）：
  //   `PagerLayoutManager.java: private int mMode = MODE_RIGHT_TO_LEFT;`
  //   实际运行时 `GalleryView` 会按 `mLayoutMode` 显式 `setMode(...)`，所以这个默认值
  //   只在"直接 new 而未 setMode"时可见 —— 单测正好锁住它，避免有人"顺手改成 LTR"。
  eq('初始 mode = RIGHT_TO_LEFT（上游默认值）', m.getMode(), MODE_RIGHT_TO_LEFT);

  m.setMode(MODE_LEFT_TO_RIGHT);
  eq('setMode 后 getMode 生效', m.getMode(), MODE_LEFT_TO_RIGHT);

  // 同值早退：再设一次不应改变任何状态
  m.setMode(MODE_LEFT_TO_RIGHT);
  eq('同值 setMode 幂等', m.getMode(), MODE_LEFT_TO_RIGHT);

  m.setMode(MODE_RIGHT_TO_LEFT);
  eq('可切回 RIGHT_TO_LEFT', m.getMode(), MODE_RIGHT_TO_LEFT);
}

// ============================================================ ② interval
{
  const m = makeManager(3);
  eq('构造时注入的 interval', m.getInterval(), 8);

  m.setInterval(16);
  eq('setInterval 生效', m.getInterval(), 16);

  // 同值早退（**关键**：不早退会在已 attach 时重建三页 → 无谓的页池抖动）
  m.setInterval(16);
  eq('同值 setInterval 幂等', m.getInterval(), 16);
}

// ============================================================ ③ 未 fill 时的空态
{
  const m = makeManager(4);
  eq('未 fill → 不可缩放', m.canScale(), false);
  eq('未 fill → getCurrentIndex = INVALID_INDEX', m.getCurrentIndex(),
    GalleryPageView.INVALID_INDEX);
  // getInternalCurrentIndex 在"无可见页"时回落到内部索引（构造时 = startPage）
  eq('未 fill → getInternalCurrentIndex 回落到内部索引', m.getInternalCurrentIndex(), 0);
  eq('未 fill → findPageByIndex 返回 null', m.findPageByIndex(0), null);
  eq('未 fill → getIndexUnder 返回 INVALID_INDEX', m.getIndexUnder(10, 10),
    GalleryPageView.INVALID_INDEX);
}

// ============================================================ ④ setCurrentIndex 越界不崩
{
  const m = makeManager(3);
  let threw = false;
  try {
    m.setCurrentIndex(-1);
    m.setCurrentIndex(99);
  } catch (e) {
    threw = true;
  }
  eq('setCurrentIndex 越界不抛', threw, false);
  // 越界被拒后内部索引不变（构造时 0）
  eq('越界被拒后内部索引不变', m.getInternalCurrentIndex(), 0);
}

// ============================================================ ⑤ mode 常量与 Core 语义一致
{
  // 断言"管理器用的 mode 常量"与"Core 的方向判定"是同一套语义：
  //   LTR：左页是上一张；RTL：右页是上一张
  ok('LTR：左页 = 上一张', isLeftPagePrevious(MODE_LEFT_TO_RIGHT));
  ok('LTR：右页 ≠ 上一张', !isRightPagePrevious(MODE_LEFT_TO_RIGHT));
  ok('RTL：右页 = 上一张', isRightPagePrevious(MODE_RIGHT_TO_LEFT));
  ok('RTL：左页 ≠ 上一张', !isLeftPagePrevious(MODE_RIGHT_TO_LEFT));

  // 管理器接受的就是这两个值（不是别的枚举）：切 mode 后 getMode 原样返回
  const m = makeManager(2);
  m.setMode(MODE_RIGHT_TO_LEFT);
  ok('管理器 mode 值域与 Core 一致', m.getMode() === MODE_RIGHT_TO_LEFT);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
