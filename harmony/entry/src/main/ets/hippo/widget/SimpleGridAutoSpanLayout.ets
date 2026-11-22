/**
 * 迁移自 app/src/main/java/com/hippo/widget/SimpleGridAutoSpanLayout.java（inventory S0544，上游 149 行）
 *
 * 上游：`extends SimpleGridLayout`，按"目标列宽"自动算列数（span count）
 *   STRATEGY_MIN_SIZE(0)      ：保证每列 ≥ columnSize → span = max(1, total/single)
 *   STRATEGY_SUITABLE_SIZE(1) ：在 floor 与 ceil 之间选"偏差更小"的列数
 *     span = total/single；若 span<=0 → 1；span2 = span+1
 *     diff1 = |total - span*single|；diff2 = |total - span2*single|
 *     return (diff1*span2 < diff2*span) ? span : span2
 *   （上游用 long 防溢出；这里用 number，vp 量级不会溢出）
 *   setColumnSize/setStrategy 变更时清缓存（mLastWidthSize/mLastTotalSpace = -1）
 *
 * ArkUI 对位：列数由**实际宽度**算 → `onAreaChange` 拿宽度，调 GridSpan 计算 spanCount，
 *   再把 columnsTemplate 拼成 `1fr …`（复用父类 SimpleGridLayout 的渲染路径）。
 *   上游的缓存字段（mLastWidthSize/mLastTotalSpace）在 ArkUI 里由 @State 派生值天然缓存，不单独移植。
 *
 * 差异（已登记 MR）：上游在 onMeasure 里算 span；ArkUI 需要先拿到宽度（onAreaChange），
 *   故**首帧**可能用默认列数渲染一次再纠正。对视觉的影响是"极短一帧的列数跳变"，
 *   在列表里滚动复用时需在 P5 截图复核。
 */
import { SimpleGridLayout } from './SimpleGridLayout';

export class GridSpan {
  static readonly STRATEGY_MIN_SIZE: number = 0;
  static readonly STRATEGY_SUITABLE_SIZE: number = 1;

  /** 上游 getSpanCountForMinSize */
  static forMinSize(total: number, single: number): number {
    if (single <= 0) {
      return 1;
    }
    const span: number = Math.floor(total / single);
    return span < 1 ? 1 : span;
  }

  /** 上游 getSpanCountForSuitableSize：在 floor 与 ceil 之间取偏差更小者 */
  static forSuitableSize(total: number, single: number): number {
    if (single <= 0) {
      return 1;
    }
    const span: number = Math.floor(total / single);
    if (span <= 0) {
      return 1;
    }
    const span2: number = span + 1;
    const diff1: number = Math.abs(total - span * single);
    const diff2: number = Math.abs(total - span2 * single);
    return (diff1 * span2 < diff2 * span) ? span : span2;
  }

  static compute(total: number, single: number, strategy: number): number {
    return strategy === GridSpan.STRATEGY_MIN_SIZE
      ? GridSpan.forMinSize(total, single)
      : GridSpan.forSuitableSize(total, single);
  }
}

@Component
export struct SimpleGridAutoSpanLayout {
  /** 上游 setColumnSize(px)：目标列宽 */
  @Prop columnSize: number = 100;
  /** 上游 setStrategy：STRATEGY_MIN_SIZE / STRATEGY_SUITABLE_SIZE */
  @Prop strategy: number = GridSpan.STRATEGY_MIN_SIZE;
  @Prop itemMargin: number = 0;
  @Prop itemCount: number = 0;
  @BuilderParam item: (index: number) => void = this.emptyItem;

  @State spanCount: number = 1;
  @State containerWidth: number = 0;

  @Builder
  emptyItem(index: number): void {
  }

  build() {
    SimpleGridLayout({
      columnCount: this.spanCount,
      itemMargin: this.itemMargin,
      itemCount: this.itemCount,
      item: this.item
    })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w: number = newValue.width as number;
        if (w > 0 && w !== this.containerWidth) {
          this.containerWidth = w;
          // 上游：按"可用宽度 / 目标列宽"算 span（间距不计入，与上游一致）
          this.spanCount = GridSpan.compute(w, this.columnSize, this.strategy);
        }
      })
  }
}
