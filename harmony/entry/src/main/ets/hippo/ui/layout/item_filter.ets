/*
 * 上游：app/src/main/res/layout/item_filter.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_filter.ets（inventory S0612）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - com.hippo.widget.ShadowLinearLayout → @BuilderParam slot2Builder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct ItemFilterLayout {
  @BuilderParam slot2Builder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Column() {
        this.slot2Builder()
      }.id('slot2').width('100%')
    }.width('100%')
  }
}
