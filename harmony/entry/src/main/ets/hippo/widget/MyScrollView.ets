/**
 * 迁移自 app/src/main/java/com/hippo/widget/MyScrollView.java（inventory S0532，上游 22 行）
 *
 * 上游只做一件事：
 *   onInterceptTouchEvent(ev) { getParent().requestDisallowInterceptTouchEvent(true); return super...; }
 *   目的：让内层 ScrollView 的滑动手势不被外层（ViewPager 之类）抢走。
 *
 * ArkUI 对位：没有 requestDisallowInterceptTouchEvent（那是 View 树的事件拦截模型），
 *   等价手段是 Scroll 的嵌套滚动策略 `nestedScroll`：
 *   内层优先（SELF_FIRST）⇒ 手势先给内层滚动，滚到边界再交给外层 —— 与上游"禁止父容器拦截"意图一致。
 *   上游是"永远不许父亲抢"，ArkUI 的 SELF_FIRST 在边界处会交棒；这是平台能力差异，
 *   实际表现更接近 Android 的 NestedScrollView 而非 requestDisallowInterceptTouchEvent，已登记 MR。
 */
@Component
export struct MyScrollView {
  /** 滚动条可见性，上游 ScrollView 默认 auto */
  @Prop showScrollbar: boolean = true;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent(): void {
  }

  build() {
    Scroll() {
      Column() {
        this.content()
      }
      .width('100%')
    }
    .align(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .scrollBar(this.showScrollbar ? BarState.Auto : BarState.Off)
    // 内层优先消费手势：对位上游 getParent().requestDisallowInterceptTouchEvent(true)
    .nestedScroll({
      scrollForward: NestedScrollMode.SELF_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }
}
