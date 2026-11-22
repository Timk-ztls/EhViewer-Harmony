/*
 * 上游：app/src/main/res/layout/gallery_list_date_jump_dialog.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_list_date_jump_dialog.ets（inventory S0596）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - com.hippo.ehviewer.widget.JumpDateSelector → @BuilderParam galleryListJumpDateBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct GalleryListDateJumpDialogLayout {
  @BuilderParam galleryListJumpDateBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      Column() {
        this.galleryListJumpDateBuilder()
      }.id('galleryListJumpDate').width('100%')
    }.width('100%').height('100%')
  }
}
