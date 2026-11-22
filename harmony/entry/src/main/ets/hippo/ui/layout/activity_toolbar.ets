/*
 * 上游：app/src/main/res/layout/activity_toolbar.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_toolbar.ets（inventory S0559）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - include（未识别节点，未生成）
 */

@Component
export struct ActivityToolbarLayout {

  build() {
    Stack() {
      // include 未识别
    }
  }
}
