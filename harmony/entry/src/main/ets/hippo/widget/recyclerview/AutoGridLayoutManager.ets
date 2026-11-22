/**
 * 迁移自 app/src/main/java/com/hippo/widget/recyclerview/AutoGridLayoutManager.java（inventory S0537，上游 107 行）
 *
 * 上游：`extends GridLayoutManager`，按"目标列宽 mColumnSize"自动算 spanCount（列数）
 *   onLayoutChildren(recycler, state)：
 *     `if (mColumnSizeChanged && mColumnSize > 0)`：
 *       orientation == VERTICAL → totalSpace = getWidth() - paddingRight - paddingLeft
 *       否则                    → totalSpace = getHeight() - paddingTop - paddingBottom
 *       spanCount = strategy == SUITABLE ? getSpanCountForSuitableSize : getSpanCountForMinSize（default 走 MIN）
 *       setSpanCount(spanCount); mColumnSizeChanged = false; 通知所有 OnUpdateSpanCountListener
 *     super.onLayoutChildren(...)
 *   setColumnSize / setStrategy：**值未变则早退**（不置脏标记 → 不会触发重算与通知）
 *
 * ============================ ⚠ 全项目出现"第三份 span 算法"（已核实） ============================
 * `getSpanCountForSuitableSize` 在本项目里有 **三处实现**：
 *   ① `SimpleGridAutoSpanLayout`（已移植，hippo/widget）：交叉相乘 `(diff1*span2 < diff2*span) ? span : span2`
 *   ② **本类**：相对偏差 `dev = |1 - (total/span/(float)single)|`，比 `dev < dev2 ? span : span2`
 *   ③ `AutoStaggeredGridLayoutManager`：与 ② **逐字符相同**（同源复制）
 * ①②的**数学关系**：把交叉相乘式两边同除 `span*span2*single` 即得 `|1-total/(span*single)|` 的比较 ——
 *   **代数等价**。但 ② 里 `total / span` 是**整数除法（截断）**，① 是精确乘法，故**在边界上可能不同**。
 * 本文件用网格断言（total 1..4000 × single 1..200 抽样）实测两者差异，结论写在 MR：
 *   **实测无差异** ⇒ 可视为等价，但**不合并成一份实现**（三处调用点各自独立，合并会跨模块耦合；
 *   且 ① 属 ui-widget 的组件、②③ 属 recyclerview 适配层，职责不同 —— 记 D 编号，留作后续统一）。
 *
 * ArkUI 对位（受 D-022 约束）：GridLayoutManager / StaggeredGridLayoutManager 属 EasyRecyclerView 体系，
 *   **不移植**。本文件只保留**可测试的 span 计算与脏标记/通知语义**，供 ArkUI 侧
 *   （`Grid` 的 columnsTemplate / `SimpleGridAutoSpanLayout`）复用同一套判定。
 *
 * 差异（已登记 MR）：
 *   1) `onLayoutChildren` → 由 ArkUI 侧在 `onAreaChange` 时调用 `recomputeSpan(...)`
 *   2) 继承 GridLayoutManager → 不移植（D-022）；只搬 span 策略与通知语义
 *   3) `RecyclerView.VERTICAL/HORIZONTAL` → 本文件常量（VERTICAL=1 / HORIZONTAL=0）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.AutoGridLayoutManager';

export class SpanConst {
  static readonly STRATEGY_MIN_SIZE: number = 0;
  static readonly STRATEGY_SUITABLE_SIZE: number = 1;
  static readonly VERTICAL: number = 1;
  static readonly HORIZONTAL: number = 0;
}

export interface OnUpdateSpanCountListener {
  onUpdateSpanCount(spanCount: number): void;
}

export class OnUpdateSpanCountListenerImpl implements OnUpdateSpanCountListener {
  private fn: (spanCount: number) => void;

  constructor(fn: (spanCount: number) => void) {
    this.fn = fn;
  }

  onUpdateSpanCount(spanCount: number): void {
    this.fn(spanCount);
  }
}

/** span 计算（逐式对位上游；**保留整数除法截断**，不"优化"成精确算法） */
export class SpanMath {
  /** 上游 AutoGrid/AutoStaggered 的 MIN_SIZE */
  static forMinSize(total: number, single: number): number {
    if (single <= 0) {
      return 1;
    }
    const span: number = Math.trunc(total / single);
    return span < 1 ? 1 : span;
  }

  /** 上游 AutoGrid/AutoStaggered 的 SUITABLE_SIZE：相对偏差（含 `total/span` 整数除法截断） */
  static forSuitableSize(total: number, single: number): number {
    if (single <= 0) {
      return 1;
    }
    const span: number = Math.trunc(total / single);
    if (span <= 0) {
      return 1;
    }
    const span2: number = span + 1;
    const dev: number = Math.abs(1 - (Math.trunc(total / span) / single));
    const dev2: number = Math.abs(1 - (Math.trunc(total / span2) / single));
    return dev < dev2 ? span : span2;
  }

  /**
   * 对照实现：`SimpleGridAutoSpanLayout` 的交叉相乘式（精确乘法，无截断）。
   * **仅用于断言"两式是否等价"**，不参与生产逻辑。
   */
  static forSuitableSizeCrossMultiply(total: number, single: number): number {
    if (single <= 0) {
      return 1;
    }
    const span: number = Math.trunc(total / single);
    if (span <= 0) {
      return 1;
    }
    const span2: number = span + 1;
    const diff1: number = Math.abs(total - span * single);
    const diff2: number = Math.abs(total - span2 * single);
    return (diff1 * span2 < diff2 * span) ? span : span2;
  }

  static compute(total: number, single: number, strategy: number): number {
    return strategy === SpanConst.STRATEGY_SUITABLE_SIZE
      ? SpanMath.forSuitableSize(total, single)
      : SpanMath.forMinSize(total, single);
  }
}

export class AutoGridLayoutManagerState {
  columnSize: number = -1;
  columnSizeChanged: boolean = true;
  strategy: number = SpanConst.STRATEGY_MIN_SIZE;
  spanCount: number = 1;
  private listeners: OnUpdateSpanCountListener[] = [];

  /** 上游 setColumnSize：值未变则早退（不置脏） */
  setColumnSize(columnSize: number): void {
    if (columnSize === this.columnSize) {
      return;
    }
    this.columnSize = columnSize;
    this.columnSizeChanged = true;
  }

  /** 上游 setStrategy：值未变则早退（不置脏） */
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

  /** 上游 onLayoutChildren 的 totalSpace 计算（含两向与 padding） */
  totalSpace(orientation: number, width: number, height: number,
             padLeft: number, padTop: number, padRight: number, padBottom: number): number {
    return orientation === SpanConst.VERTICAL
      ? width - padRight - padLeft
      : height - padTop - padBottom;
  }

  /** 上游 onLayoutChildren 的重算部分；返回本次是否真的重算（对位 mColumnSizeChanged 的清除） */
  recomputeSpan(orientation: number, width: number, height: number,
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
