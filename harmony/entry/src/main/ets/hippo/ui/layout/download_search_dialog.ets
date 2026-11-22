/*
 * 上游：app/src/main/res/layout/download_search_dialog.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/download_search_dialog.ets（inventory S0584）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - com.hippo.ehviewer.widget.SearchBar → @BuilderParam downloadSearchBarBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct DownloadSearchDialogLayout {
  @BuilderParam downloadSearchBarBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      Column() {
        this.downloadSearchBarBuilder()
      }.id('downloadSearchBar').width('100%')
    }.width('100%')
  }
}
