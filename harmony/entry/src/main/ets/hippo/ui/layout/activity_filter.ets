/*
 * 上游：app/src/main/res/layout/activity_filter.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_filter.ets（inventory S0550）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - com.hippo.easyrecyclerview.EasyRecyclerView → @BuilderParam recyclerViewBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct ActivityFilterLayout {
  @Prop tip: ResourceStr = $r('app.string.no_filter');

  @BuilderParam recyclerViewBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Column() {
        this.recyclerViewBuilder()
      }.id('recyclerView').width('100%').height('100%').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
      Text(this.tip).id('tip').width(228).textAlign(TextAlign.Center).align(Alignment.Center)
    }.width('100%').height('100%')
  }
}
