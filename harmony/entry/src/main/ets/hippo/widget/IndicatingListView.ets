/**
 * 迁移自 app/src/main/java/com/hippo/widget/IndicatingListView.java（inventory S0524，上游 79 行）
 *
 * 上游与 IndicatingScrollView 是同一套绘制逻辑，只是宿主由 ScrollView 换成 ListView：
 *   draw() → super.draw() 之后 translate(getScrollX(), getScrollY())，
 *   上/下各画一条 Rect(0, 0, w, h_ind) / Rect(0, h-h_ind, w, h)，
 *   显隐条件 = canScrollVertically(∓1)。
 *
 * ArkUI 对位：宿主换成 `List`（ListView 的声明式等价物），其余与 IndicatingScrollView 完全一致
 *   （指示条用 .overlay 叠层；显隐由 Scroller.currentOffset() / onReachStart / onReachEnd 驱动）。
 *
 * 差异：
 *   1) ListView 的 draw() 会随滚动被反复调用（自带"每帧重绘"），ArkUI 里指示条是状态驱动的叠层，
 *      滚动中更新频率取决于 onScroll 回调频率 —— 视觉上等价，但底条纠偏时机见 IndicatingScrollView 的说明。
 *   2) ListView 的 getScrollX/getScrollY 平移在 ArkUI 无对应（List 内部滚动由框架接管），
 *      指示条本就在组件坐标系内，不需要平移，绘制结果一致。
 */
@Component
export struct IndicatingListView {
  /** R.styleable.Indicating_indicatorHeight，默认 1 */
  @Prop indicatorHeight: number = 1;
  /** R.styleable.Indicating_indicatorColor，默认 Color.BLACK */
  @Prop indicatorColor: ResourceColor = '#FF000000';
  /** 列表内容（调用方用 ListItem 包裹条目） */
  @BuilderParam content: () => void = this.empty;

  private scroller: Scroller = new Scroller();
  @State showTop: boolean = false;
  @State showBottom: boolean = true;

  @Builder
  empty(): void {
  }

  @Builder
  topIndicator(): void {
    Column()
      .width('100%')
      .height(this.showTop ? this.indicatorHeight : 0)
      .backgroundColor(this.indicatorColor)
  }

  @Builder
  bottomIndicator(): void {
    Column()
      .width('100%')
      .height(this.showBottom ? this.indicatorHeight : 0)
      .backgroundColor(this.indicatorColor)
  }

  build() {
    Stack() {
      List({ scroller: this.scroller }) {
        this.content()
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .onScroll(() => {
        const offset: OffsetResult = this.scroller.currentOffset();
        this.showTop = offset.yOffset > 0;
      })
      .onReachStart(() => {
        this.showTop = false;
      })
      .onReachEnd(() => {
        this.showBottom = false;
      })
      .onAreaChange(() => {
        this.showBottom = true;
      })
    }
    .width('100%')
    .height('100%')
    .overlay(this.topIndicator(), { align: Alignment.TopStart })
    .overlay(this.bottomIndicator(), { align: Alignment.BottomStart })
  }
}
