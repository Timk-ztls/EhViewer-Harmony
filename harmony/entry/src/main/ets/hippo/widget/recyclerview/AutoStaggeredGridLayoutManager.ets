/**
 * 迁移自 app/src/main/java/com/hippo/widget/recyclerview/AutoStaggeredGridLayoutManager.java
 * （inventory S0538，上游 109 行）
 *
 * 上游：`extends StaggeredGridLayoutManager`，与 `AutoGridLayoutManager` **同一个思路**（按目标列宽算 spanCount），
 * 但有两处实质差异：
 *   ① **重算时机在 `onMeasure` 而不是 `onLayoutChildren`**
 *      原因：StaggeredGridLayoutManager 在**测量阶段**就需要知道 spanCount（要算子项跨距），
 *      晚到 layout 阶段会先按旧 spanCount 测一遍 → 首帧布局跳变。
 *      ⇒ 这条差异必须保留：ArkUI 侧对应"在 `onAreaChange`（测量后拿尺寸）里重算"，而不是"首帧后再改"。
 *   ② 两个静态 span 算法与 `AutoGridLayoutManager` **逐字符相同**（同源复制）：
 *      `getSpanCountForSuitableSize` = 相对偏差式（含 `total/span` 整数除法截断）
 *      `getSpanCountForMinSize`     = `Math.max(1, total/single)`
 *
 * 其余（setColumnSize / setStrategy 的"值未变则早退"、mColumnSizeChanged 脏标记、
 * OnUpdateSpanCountListener 的增删与通知）与 AutoGridLayoutManager 一致。
 *
 * ============================ 全项目 span 算法的第三处副本 ============================
 * 至此确认三处：`SimpleGridAutoSpanLayout`（交叉相乘，精确）／`AutoGridLayoutManager`（相对偏差）／
 * **本类**（相对偏差，与②逐字符相同）。②③ 与 ① 代数等价但②③含整数除法截断。
 * 本批用网格断言实测 ② 与 ① 的差异（见 AutoGridLayoutManager.ets 的对照实现），
 * **不合并实现**：三处调用点分属不同层（组件 / GridLayoutManager / StaggeredGridLayoutManager），
 * 合并会跨模块耦合；记 D 编号留待统一。
 *
 * ArkUI 对位：StaggeredGridLayoutManager 属 EasyRecyclerView 体系，受 D-022 约束**不移植**；
 * 本文件只保留 span 计算 + 脏标记/通知 + **"必须在测量阶段算"这条时序约束**。
 *
 * 差异（已登记 MR）：
 *   1) 继承 StaggeredGridLayoutManager → 不移植（D-022）
 *   2) `onMeasure` → ArkUI 侧挂在 `onAreaChange`（尺寸可用时立即算），语义等价于"测量阶段"
 *   3) 两个静态方法与 AutoGridLayoutManager 重复 —— 保持各自独立（不在模块内互相 import，
 *      避免"两个 LayoutManager 互相依赖"的假耦合）
 */
import { SpanConst, SpanMath, OnUpdateSpanCountListener } from './AutoGridLayoutManager';

export { SpanConst, SpanMath, OnUpdateSpanCountListener };

export class AutoStaggeredGridLayoutManagerState {
  columnSize: number = -1;
  columnSizeChanged: boolean = true;
  strategy: number = SpanConst.STRATEGY_MIN_SIZE;
  spanCount: number = 1;
  private listeners: OnUpdateSpanCountListener[] = [];

  setColumnSize(columnSize: number): void {
    if (columnSize === this.columnSize) {
      return;
    }
    this.columnSize = columnSize;
    this.columnSizeChanged = true;
  }

  setStrategy(strategy: number): void {
    if (strategy === this.strategy) {
      return;
    }
    this.strategy = strategy;
    this.columnSizeChanged = true;
  }

  addOnUpdateSpanCountListener(listener: OnUpdateSpanCountListener): void {
    this.listeners.push(listener);
  }

  removeOnUpdateSpanCountListener(listener: OnUpdateSpanCountListener): void {
    this.listeners = this.listeners.filter((l: OnUpdateSpanCountListener) => l !== listener);
  }

  /** 上游 onMeasure 的 totalSpace：Staggered 用的是"可用宽度/高度"（同 AutoGrid 的 onLayoutChildren） */
  totalSpace(orientation: number, width: number, height: number,
             padLeft: number, padTop: number, padRight: number, padBottom: number): number {
    return orientation === SpanConst.VERTICAL
      ? width - padRight - padLeft
      : height - padTop - padBottom;
  }

  /**
   * 上游 onMeasure 的重算部分。
   * **时序约束（本类存在的意义）**：必须在"测量阶段"调用（ArkUI 的 onAreaChange），
   * 否则首帧会按旧 spanCount 布局一次再纠正。
   */
  recomputeSpanOnMeasure(orientation: number, width: number, height: number,
                         padLeft: number, padTop: number, padRight: number, padBottom: number): boolean {
    if (!this.columnSizeChanged || this.columnSize <= 0) {
      return false;
    }
    const total: number = this.totalSpace(orientation, width, height, padLeft, padTop, padRight, padBottom);
    const spanCount: number = SpanMath.compute(total, this.columnSize, this.strategy);
    this.spanCount = spanCount;
    this.columnSizeChanged = false;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onUpdateSpanCount(spanCount);
    }
    return true;
  }
}
