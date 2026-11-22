/**
 * 迁移自 app/src/main/java/com/hippo/widget/AutoWrapLayout.java（inventory S0510，上游 222 行）
 *
 * 上游：`ViewGroup` 流式换行 + **逐行的垂直对齐策略**
 *   enum Alignment { TOP(0), CENTER(1), BOTTOM(2) }
 *   sBaseLineArray = { TOP, CENTER, BOTTOM }（XML 属性按索引取值）
 *   onMeasure：先按内容宽度换行，记录每行 lineHeight 与各子项 rect
 *   onLayout：逐行摆放，再 adjustBaseLine(lineHeight, startIndex, endIndex)：
 *     TOP    → 子项顶对齐（不加偏移）
 *     CENTER → offset = (lineHeight - h - margins) / 2
 *     BOTTOM → offset = lineHeight - h - margins
 *
 * ArkUI 对位：`Flex({ wrap: Wrap, alignItems: <映射> })` —— Flex 的 alignItems 正是**逐行的交叉轴对齐**，
 *   与上游 adjustBaseLine 的三分支一一对应：
 *     TOP(0)    → ItemAlign.Start
 *     CENTER(1) → ItemAlign.Center
 *     BOTTOM(2) → ItemAlign.End
 *   故不重写换行/基线调整算法（判据：完全重复 → 不重写）；只把 Alignment 的索引→ItemAlign 映射写成纯函数并断言。
 *
 * 差异（已登记 MR）：
 *   1) 上游 `generateLayoutParams` 系列返回 MarginLayoutParams（Android 的 margin 机制）；
 *      ArkUI 无 LayoutParams，逐项 margin 用子项 padding 表达。
 *   2) 上游 `setAlignment(null)` 回退到默认值；ArkTS 枚举无 null，改用 -1 表达"未设置"→ 默认 TOP。
 */
export class AutoWrapAlignment {
  static readonly TOP: number = 0;
  static readonly CENTER: number = 1;
  static readonly BOTTOM: number = 2;
  /** 上游 sBaseLineArray 的索引顺序（XML 属性按 0/1/2 取） */
  static readonly BASE_LINE_ARRAY: number[] = [AutoWrapAlignment.TOP, AutoWrapAlignment.CENTER, AutoWrapAlignment.BOTTOM];

  /** XML 属性索引 → Alignment（越界回退 TOP，对位上游 setAlignment(null) 的默认值行为） */
  static fromIndex(index: number): number {
    if (index < 0 || index >= AutoWrapAlignment.BASE_LINE_ARRAY.length) {
      return AutoWrapAlignment.TOP;
    }
    return AutoWrapAlignment.BASE_LINE_ARRAY[index];
  }

  /** Alignment → ArkUI ItemAlign（逐行交叉轴对齐） */
  static toItemAlign(alignment: number): ItemAlign {
    if (alignment === AutoWrapAlignment.CENTER) {
      return ItemAlign.Center;
    }
    if (alignment === AutoWrapAlignment.BOTTOM) {
      return ItemAlign.End;
    }
    return ItemAlign.Start;
  }
}

@Component
export struct AutoWrapLayout {
  /** 上游 setAlignment(Alignment)；用 0/1/2 表达，-1 = 未设置（默认 TOP） */
  @Prop alignment: number = AutoWrapAlignment.TOP;
  @Prop horizontalSpace: number = 0;
  @Prop verticalSpace: number = 0;
  @Prop itemCount: number = 0;
  @BuilderParam item: (index: number) => void = this.emptyItem;

  @Builder
  emptyItem(index: number): void {
  }

  private indices(): number[] {
    const arr: number[] = [];
    for (let i = 0; i < this.itemCount; i++) {
      arr.push(i);
    }
    return arr;
  }

  build() {
    Flex({
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Start,
      alignItems: AutoWrapAlignment.toItemAlign(this.alignment)
    }) {
      ForEach(this.indices(), (index: number) => {
        Column() {
          this.item(index)
        }
        .margin({ right: this.horizontalSpace, bottom: this.verticalSpace })
      }, (index: number) => `${index}`)
    }
    .width('100%')
  }
}
