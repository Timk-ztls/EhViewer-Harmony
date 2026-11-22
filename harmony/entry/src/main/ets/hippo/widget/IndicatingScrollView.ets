/**
 * 迁移自 app/src/main/java/com/hippo/widget/IndicatingScrollView.java（inventory S0525，上游 79 行）
 *
 * 上游逻辑（draw 里手绘两条指示条）：
 *   needShowTopIndicator()    = canScrollVertically(-1)    → 还能往上滚 ⇒ 顶部指示条
 *   needShowBottomIndicator() = canScrollVertically(1)     → 还能往下滚 ⇒ 底部指示条
 *   fillTopIndicatorDrawRect()    = Rect(0, 0, w, mIndicatorHeight)
 *   fillBottomIndicatorDrawRect() = Rect(0, h - mIndicatorHeight, w, h)
 *   mIndicatorHeight 默认 1px（R.styleable.Indicating_indicatorHeight）
 *   mIndicatorColor  默认 Color.BLACK（R.styleable.Indicating_indicatorColor）
 *
 * ArkUI 对位：
 *   draw()+canvas.drawRect → 两个 @Builder 叠层（.overlay）：顶部对齐 + 底部对齐，纯色填充、高度/颜色可配
 *   canScrollVertically(-1) → 滚动偏移 yOffset > 0（onScroll 里读 Scroller.currentOffset()）
 *   canScrollVertically(1)  → 未到末尾：onReachEnd 置 false，任意 onScroll 且未到末尾置 true
 *
 * 差异（已在 MR「平台差异」登记）：ArkUI 没有"内容尺寸 - 视口尺寸 > 0"的同步查询，
 *   底部指示条初值靠 onAreaChange 置为 true（可滚动）再被 onReachEnd 纠正；
 *   若内容不足一屏，首帧可能出现一次底条闪烁，需在 P5 双端截图复核时确认。
 */
@Component
export struct IndicatingScrollView {
  /** R.styleable.Indicating_indicatorHeight，默认 1 */
  @Prop indicatorHeight: number = 1;
  /** R.styleable.Indicating_indicatorColor，默认 Color.BLACK */
  @Prop indicatorColor: ResourceColor = '#FF000000';
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
      Scroll(this.scroller) {
        Column() {
          this.content()
        }
        .width('100%')
      }
      .align(Alignment.TopStart)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .onScroll(() => {
        const offset: OffsetResult = this.scroller.currentOffset();
        this.showTop = offset.yOffset > 0;
      })
      .onScrollStart(() => {
      })
      .onReachStart(() => {
        this.showTop = false;
      })
      .onReachEnd(() => {
        this.showBottom = false;
      })
      .onAreaChange(() => {
        // 初值：默认可滚动，由 onReachEnd 纠偏（见文件头「差异」）
        this.showBottom = true;
      })
    }
    .width('100%')
    .height('100%')
    .overlay(this.topIndicator(), { align: Alignment.TopStart })
    .overlay(this.bottomIndicator(), { align: Alignment.BottomStart })
  }
}
