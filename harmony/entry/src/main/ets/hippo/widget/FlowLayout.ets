/**
 * 迁移自 app/src/main/java/com/hippo/widget/FlowLayout.java（inventory S0522，上游 107 行）
 *
 * 上游：`ViewGroup` 自写流式布局（按**内容宽度**换行，不是等宽列）
 *   onMeasure：measureChildren → compute(flowWidth) 得到每行宽度与总高
 *     宽度模式 EXACTLY → 用 widthSize；否则用内容总宽
 *   compute(flowWidth)：累加子项宽+margin，超过 flowWidth 就换行，返回 {allChildWidth, height}
 *   onLayout：按行摆放（顶点位置不含 margin，margin 由 LayoutParams 生效）
 *
 * ArkUI 对位：`Flex({ wrap: FlexWrap.Wrap })` —— 就是"按内容宽度换行"的同一算法。
 *   上游的 compute() 是手写的换行累加；Flex 的 wrap 由框架实现，语义相同（含 EXACTLY/AT_MOST 的宽度处理）。
 *   故本文件**不重写换行算法**（判据：完全重复 → 不重写）。
 *
 * 差异（已登记 MR）：上游支持子项各自 margin；ArkUI Flex 只提供 space（主轴/交叉轴间距）→
 *   逐项 margin 用子项 padding 表达。上游"顶点位置不含 margin"的实现细节是 Android 的
 *   LayoutParams 机制产物，ArkUI 无对应概念（不需要）。
 */
@Component
export struct FlowLayout {
  /** 主轴间距（对位子项左右 margin 的常见用法） */
  @Prop horizontalSpace: number = 0;
  /** 交叉轴间距（行间距） */
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
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
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
