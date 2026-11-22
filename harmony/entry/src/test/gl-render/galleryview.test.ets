/*
 * GalleryView 测试装配入口（M-01 最小可交付）
 *
 * 目的：让布局管理器（尤其是 `PagerLayoutManager`）能在 Node 里被推到"可驱动"状态，
 * 而不是只靠类型级编译保证。
 *
 * ## 范围（Lead 裁定：最小可交付）
 * 做：`replaceAdapterForTest` / `setSizeForTest` / `debugSnapshot` / `componentIndexOfTest` /
 *     `attachLayoutManagerForTest` + 21 条断言
 * 不做：`IGalleryView` 接口化 + `FakeGalleryView`（收益真实但不该现在付 —— 黑屏类缺陷更紧急）
 *
 * ## 明确**不在**单测范围（属真机验收）
 * - 三页池的 obtain/release **配对**时序（要真实 `bind`/`unbind` 与画布）
 * - 边视图 `GLEdgeView` 的 pull/release/absorb 时序
 * - 布局管理器 `scrollInternal` 四路分支里的**重排副作用**（`forceFill`/`requestLayout`）
 *
 * ## ⚠️ T-01：写测试文件时的陷阱（本文件踩过）
 * **所有 `class` 声明必须写在执行块之前。** TS/CJS 的类声明**不提升**（TDZ），
 * "块里 `new` 一个后文才声明的类"会抛 `Cannot access 'X' before initialization`；
 * 如果该调用被生产的 `try/catch + hilog.warn` 包住（`ensurePagerLayoutManager` 正是这样），
 * **错误会被吞掉**，症状只剩"断言莫名不过"。
 * 本文件把 `StubAdapter` / `NoopLayoutManager` 提到最前面，就是为了不再撞这个坑。
 */

import {
  GalleryViewBuilder, GalleryAdapter, GalleryView, GalleryLayoutManager,
  GalleryLayoutManagerFactory
} from '../../main/ets/hippo/lib/glgallery/GalleryView';
import { GalleryPageView } from '../../main/ets/hippo/lib/glgallery/GalleryPageView';

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

// ---------------------------------------------------------------- 辅助类（必须在执行块之前）
class StubAdapter extends GalleryAdapter {
  bound: number[] = [];
  unbound: number[] = [];
  total: number;
  constructor(total: number) { super(); this.total = total; }
  onBind(view: GalleryPageView, index: number): void { this.bound.push(index); }
  onUnbind(view: GalleryPageView, index: number): void { this.unbound.push(index); }
  getError(): string | null { return null; }
  size(): number { return this.total; }
}

/** 最小布局管理器：每个方法都空转（验证接线，不驱动渲染）。 */
class NoopLayoutManager extends GalleryLayoutManager {
  constructor(galleryView: GalleryView) { super(galleryView); }
  onAttach(adapter: GalleryAdapter): void {}
  onDetach(): GalleryAdapter { return new StubAdapter(0); }
  onFill(): void {}
  onDown(): void {}
  onUp(): void {}
  onDoubleTapConfirmed(x: number, y: number): void {}
  onLongPress(x: number, y: number): void {}
  onScroll(dx: number, dy: number, totalX: number, totalY: number, x: number, y: number): void {}
  onFling(velocityX: number, velocityY: number): void {}
  canScale(): boolean { return false; }
  onScale(focusX: number, focusY: number, scale: number): void {}
  onUpdateAnimation(time: number): boolean { return false; }
  onDataChanged(): void {}
  onPageLeft(): void {}
  onPageRight(): void {}
  isTapOrPressEnable(): boolean { return false; }
  findPageByIndex(index: number): GalleryPageView | null { return null; }
  getCurrentIndex(): number { return GalleryPageView.INVALID_INDEX; }
  setCurrentIndex(index: number): void {}
  getIndexUnder(x: number, y: number): number { return GalleryPageView.INVALID_INDEX; }
  getInternalCurrentIndex(): number { return 0; }
}

function makeView(adapter: GalleryAdapter): GalleryView {
  return new GalleryViewBuilder(adapter).build();
}

// ============================================================ ① 装配入口本身
{
  const adapter = new StubAdapter(5);
  const gv = makeView(adapter);

  eq('初始快照：adapter 已由 Builder 注入', gv.debugSnapshot().indexOf('adapter=true') >= 0, true);
  eq('初始快照：无布局管理器（未注入工厂）', gv.debugSnapshot().indexOf('layout=false') >= 0, true);

  eq('初始尺寸为 0（未布局）', gv.getWidth(), 0);
  gv.setSizeForTest(1080, 1920);
  eq('setSizeForTest → getWidth', gv.getWidth(), 1080);
  eq('setSizeForTest → getHeight', gv.getHeight(), 1920);

  const other = new StubAdapter(9);
  gv.replaceAdapterForTest(other);
  eq('replaceAdapterForTest 后 snapshot 仍 adapter=true',
    gv.debugSnapshot().indexOf('adapter=true') >= 0, true);
  gv.replaceAdapterForTest(null);
  eq('replaceAdapterForTest(null) → adapter=false',
    gv.debugSnapshot().indexOf('adapter=false') >= 0, true);
}

// ============================================================ ② 画序断言（身份比较，不用反射）
{
  const gv = makeView(new StubAdapter(1));
  const page: GalleryPageView = gv.obtainPage();
  const progress = gv.obtainProgress();

  gv.addComponent(page);
  gv.addComponent(progress);

  eq('先加的页在下（下标 0）', gv.componentIndexOfTest(page), 0);
  eq('后加的进度圈在上（下标 1）', gv.componentIndexOfTest(progress), 1);
  ok('画序：进度圈在页之上', gv.componentIndexOfTest(progress) > gv.componentIndexOfTest(page));

  const stranger: GalleryPageView = gv.obtainPage();
  eq('未加入 → -1', gv.componentIndexOfTest(stranger), -1);

  gv.removeComponent(progress);
  eq('移除后 → -1', gv.componentIndexOfTest(progress), -1);
  eq('移除后 snapshot comps=1', gv.debugSnapshot().indexOf('comps=1') >= 0, true);
}

// ============================================================ ③ 页池：obtain/release 复用
{
  const gv = makeView(new StubAdapter(1));
  const p1: GalleryPageView = gv.obtainPage();
  gv.releasePage(p1);
  const p2: GalleryPageView = gv.obtainPage();
  ok('release 后再 obtain 复用同一实例', p1 === p2);

  // ⚠️ 不在单测范围（属真机）：obtain 与 bind/unbind 的**配对时序**
}

// ============================================================ ④ 注入工厂后的管理器接线
{
  const gv = makeView(new StubAdapter(3));
  gv.setSizeForTest(1080, 1920);

  let created = 0;
  const factory: GalleryLayoutManagerFactory = {
    createPagerLayoutManager: (view: GalleryView, scaleMode: number, startPosition: number,
      pagerInterval: number): GalleryLayoutManager => {
      created++;
      return new NoopLayoutManager(view);
    },
    createScrollLayoutManager: (view: GalleryView, scrollInterval: number): GalleryLayoutManager => {
      created++;
      return new NoopLayoutManager(view);
    }
  };

  GalleryView.setLayoutManagerFactory(factory);
  try {
    // 不变式：requestFill() 本身**不** attach（attach 只发生在 root attach 那一跳）
    gv.requestFill();
    eq('requestFill() 不 attach 管理器（attach 由 root attach 触发）', created, 0);

    gv.attachLayoutManagerForTest();
    ok('注入工厂 + adapter 后能创建管理器', created > 0);
    eq('attach 后 snapshot layout=true', gv.debugSnapshot().indexOf('layout=true') >= 0, true);
    // attachLayoutManager 会把 adapter 所有权移交管理器（mAdapter = null）
    eq('attach 后 adapter 所有权移交（adapter=false）',
      gv.debugSnapshot().indexOf('adapter=false') >= 0, true);
  } finally {
    GalleryView.setLayoutManagerFactory(null);
  }
}

// ============================================================ ⑤ 未注入工厂时的降级
{
  const gv = makeView(new StubAdapter(2));
  gv.setSizeForTest(1080, 1920);
  GalleryView.setLayoutManagerFactory(null);
  let threw = false;
  try {
    gv.requestFill();
    gv.attachLayoutManagerForTest();
  } catch (e) {
    threw = true;
  }
  eq('工厂为 null 时 attach 不抛（降级为无管理器）', threw, false);
  eq('工厂为 null 时 snapshot layout=false', gv.debugSnapshot().indexOf('layout=false') >= 0, true);
}

// ============================================================ ⑥ 生产不变式：入口无隐式副作用
{
  const gv = makeView(new StubAdapter(2));
  eq('未调用 setSizeForTest → 尺寸仍为 0', gv.getWidth(), 0);
  eq('未加入组件 → comps=0', gv.debugSnapshot().indexOf('comps=0') >= 0, true);
  eq('默认无布局管理器', gv.debugSnapshot().indexOf('layout=false') >= 0, true);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
