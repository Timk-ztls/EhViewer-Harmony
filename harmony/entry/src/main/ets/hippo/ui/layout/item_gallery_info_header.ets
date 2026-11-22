/*
 * 上游：app/src/main/res/layout/item_gallery_info_header.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_info_header.ets（inventory S0619）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:textColor=?android:attr/textColorSecondary（主题属性，需 ThemeManager 注入）
 */

@Component
export struct ItemGalleryInfoHeaderLayout {
  @Prop fgKey: string = '';
  @Prop fgValue: string = '';


  build() {
    Row() {
      Text(this.fgKey).id('fgKey').width(90).padding({ left: 8, right: 8, top: 8, bottom: 8 })
      Text(this.fgValue).id('fgValue').padding({ left: 8, right: 8, top: 8, bottom: 8 })
    }.width('100%')
  }
}
