/*
 * 上游：app/src/main/res/layout/scene_security.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_security.ets（inventory S0661）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - com.hippo.widget.MaxSizeContainer → @BuilderParam slot2Builder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct SceneSecurityLayout {
  @BuilderParam slot2Builder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Column() {
        this.slot2Builder()
      }.id('slot2').margin({ left: 32, right: 32, top: 32, bottom: 32 })
    }.width('100%').height('100%')
  }
}
