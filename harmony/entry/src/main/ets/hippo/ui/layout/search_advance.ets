/**
 * SearchAdvanceLayout slot container aligned with Android res/layout/search_advance.xml.
 */

@Component
export struct SearchAdvanceLayout {
  @BuilderParam searchAdvanceSearchTableBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot(): void {
    Column().width(0).height(0)
  }

  build(): void {
    Column() {
      this.searchAdvanceSearchTableBuilder()
    }
    .id('searchAdvanceSearchTable')
    .width('100%')
  }
}
