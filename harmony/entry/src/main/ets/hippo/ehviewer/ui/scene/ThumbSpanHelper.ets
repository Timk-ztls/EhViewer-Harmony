/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/ThumbSpanHelper.java（231 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/ThumbSpanHelper.ets（S0263）
 *
 * 上游常量（读源码确认）：
 *   MIN_ARRAY_LENGTH = 50   ← cells 初始长度（按需扩容）
 *   MAX_ROW_INTERVAL = 3    ← 同一"行组"最多连续几行，用于把大图凑成整行
 * 字段：mData(List<GalleryInfo>) / mCells(boolean[]) / mNextIndex / mNextGroupIndex / mNearSpaceIndex
 *
 * 作用：给瀑布流/网格布局算每格的 span —— 连续的"大图"占多列，并把同一组限制在
 * MAX_ROW_INTERVAL 行内，避免出现半空行。调用方按 nextSpan(galleryInfo) 逐个取值。
 *
 * Part 1（本批）：cells 扩容、span 计算主循环、按 group 的行数限制、reset。
 * Part 2 待补：与具体布局（Grid 的 columnsTemplate）对接的适配层。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 上游 mData 元素的所需子集（真实模型 GalleryInfo） */
export interface SpanDataSourceLike {
  getItemCount(): number;
  /** 上游判据：这一项是否"大图"（多列） */
  isLarge(index: number): boolean;
}

export class ThumbSpanHelper {
  static readonly MIN_ARRAY_LENGTH: number = 50;
  static readonly MAX_ROW_INTERVAL: number = 3;

  private readonly data: SpanDataSourceLike;
  private readonly span: number;
  /** 上游 mCells：记录已占用的列位（按需扩容到 MIN_ARRAY_LENGTH 的整数倍） */
  private cells: boolean[] = new Array<boolean>(ThumbSpanHelper.MIN_ARRAY_LENGTH).fill(false);
  private nextIndex: number = 0;
  private nextGroupIndex: number = 0;
  private nearSpaceIndex: number = 0;

  constructor(data: SpanDataSourceLike, span: number) {
    this.data = data;
    this.span = span > 0 ? span : 1;
  }

  /** 上游 cells 扩容：不足时按 MIN_ARRAY_LENGTH 的倍数扩 */
  private ensureCapacity(need: number): void {
    if (need <= this.cells.length) {
      return;
    }
    let size: number = this.cells.length;
    while (size < need) {
      size = size + ThumbSpanHelper.MIN_ARRAY_LENGTH;
    }
    const grown: boolean[] = new Array<boolean>(size).fill(false);
    for (let i = 0; i < this.cells.length; i++) {
      grown[i] = this.cells[i];
    }
    this.cells = grown;
  }

  /**
   * 上游 nextSpan(position)：返回该位置应跨的列数。
   * 规则（读上游主循环归纳）：
   *   1. 大图且右侧剩余空间放得下 → 占满剩余列；
   *   2. 同一 group 的行数达到 MAX_ROW_INTERVAL → 强制收束为 1 列，保证换行；
   *   3. 小图 → 1 列。
   */
  nextSpan(position: number): number {
    if (position >= this.data.getItemCount()) {
      hilog.warn(0x0000, 'ThumbSpanHelper', 'nextSpan 越界: position=%{public}d count=%{public}d；后果：按 1 列处理',
        position, this.data.getItemCount());
      return 1;
    }
    this.ensureCapacity(position + this.span + 1);
    this.nextIndex = position;

    if (!this.data.isLarge(position)) {
      return 1;
    }
    const col: number = position % this.span;
    const remain: number = this.span - col;
    if (remain <= 1) {
      return 1;
    }
    this.nextGroupIndex = this.nextGroupIndex + 1;
    if (this.nextGroupIndex > ThumbSpanHelper.MAX_ROW_INTERVAL) {
      this.nextGroupIndex = 0;
      return 1;
    }
    this.nearSpaceIndex = position + remain;
    return remain;
  }

  /** 上游 reset：换数据源或换列数时重置全部游标 */
  reset(): void {
    this.cells = new Array<boolean>(ThumbSpanHelper.MIN_ARRAY_LENGTH).fill(false);
    this.nextIndex = 0;
    this.nextGroupIndex = 0;
    this.nearSpaceIndex = 0;
  }

  getSpan(): number {
    return this.span;
  }
}
