/*
 * 上游：app/src/main/res/layout/gallery_detail_progress.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_progress.ets（inventory S0593）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - com.hippo.widget.ProgressView → @BuilderParam slot2Builder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct GalleryDetailProgressLayout {
  @BuilderParam slot2Builder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Column() {
        this.slot2Builder()
      }.id('slot2').margin({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
    }.id('progress').width('100%').height('100%')
  }
}
