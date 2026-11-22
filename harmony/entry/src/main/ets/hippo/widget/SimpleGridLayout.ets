/**
 * 迁移自 app/src/main/java/com/hippo/widget/SimpleGridLayout.java（inventory S0545，上游 222 行）
 *
 * 上游：`ViewGroup` 自写网格布局
 *   setColumnCount(n) / setItemMargin(px)：列数与子项间距
 *   onMeasure：按列数把可用宽度切成等宽列，逐行量高（含 margin）
 *   onLayout ：按 (row, column) 摆放，列宽 = 可用宽/列数
 *   内部有"布局缓存"（mLastWidthSize/mLastTotalSpace）避免重复计算
 *
 * ArkUI 对位：`Grid` + `columnsTemplate('1fr 1fr …')` 就是"等宽列网格"，`columnsGap/rowsGap` 对位 itemMargin。
 *   **不需要手写 onMeasure/onLayout** —— ArkUI 的 Grid 已实现同一算法（等分可用宽度、逐行排布）。
 *   上游的布局缓存是性能优化（避免重复计算），ArkUI 由框架内部维护，故不移植（无行为差异）。
 *
 * 差异（已登记 MR）：上游 onMeasure 支持子项各自的 margin；ArkUI 的 Grid 只提供统一的
 *   columnsGap/rowsGap，**逐项 margin 需由子项自己用 padding 表达**（视觉可等价，写法不同）。
 */
@Component
export struct SimpleGridLayout {
  /** 上游 setColumnCount(n) */
  /** 上游 SimpleGridLayout.java:37 的 DEFAULT_COLUMN_COUNT = 3（原误写 2） */
  @Prop columnCount: number = 3;
  /** 上游 setItemMargin(px) → 列间距/行间距 */
  @Prop itemMargin: number = 0;
  /** 子项数量 */
  @Prop itemCount: number = 0;
  /** 子项渲染（index → 内容） */
  @BuilderParam item: (index: number) => void = this.emptyItem;

  @Builder
  emptyItem(index: number): void {
  }

  private template(): string {
    const parts: string[] = [];
    const n: number = this.columnCount > 0 ? this.columnCount : 1;
    for (let i = 0; i < n; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private indices(): number[] {
    const arr: number[] = [];
    for (let i = 0; i < this.itemCount; i++) {
      arr.push(i);
    }
    return arr;
  }

  build() {
    Grid() {
      ForEach(this.indices(), (index: number) => {
        GridItem() {
          this.item(index)
        }
      }, (index: number) => `${index}`)
    }
    .columnsTemplate(this.template())
    .columnsGap(this.itemMargin)
    .rowsGap(this.itemMargin)
    .width('100%')
  }
}