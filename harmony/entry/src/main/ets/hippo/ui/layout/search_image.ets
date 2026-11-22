/**
 * SearchImageLayout slot container aligned with Android res/layout/search_image.xml.
 */

@Component
export struct SearchImageLayout {
  @BuilderParam searchImageBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot(): void {
    Column().width(0).height(0)
  }

  build(): void {
    Column() {
      this.searchImageBuilder()
    }
    .id('searchImage')
    .width('100%')
  }
}
