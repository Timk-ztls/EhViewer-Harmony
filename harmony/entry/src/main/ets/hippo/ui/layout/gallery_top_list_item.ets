/*
 * 上游：app/src/main/res/layout/gallery_top_list_item.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_top_list_item.ets（inventory S0599）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   （无）
 */

@Component
export struct GalleryTopListItemLayout {
  @Prop listItem: string = '';


  build() {
    Column() {
      Text(this.listItem).id('listItem').width('100%').margin({ left: 8, right: 8, top: 8, bottom: 8 })
    }.width('100%')
  }
}
