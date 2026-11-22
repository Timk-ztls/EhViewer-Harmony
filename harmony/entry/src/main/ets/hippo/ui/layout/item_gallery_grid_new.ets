/*
 * 上游：app/src/main/res/layout/item_gallery_grid_new.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_grid_new.ets（inventory S0616）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=top|right（Stack 内对齐，已按 Alignment 近似）
 *   - android:textColor=@android:color/white（主题属性，需 ThemeManager 注入）
 *   - android:textSize=10dp
 *   - com.hippo.ehviewer.widget.TileThumbNew → @BuilderParam thumbNewBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct ItemGalleryGridNewLayout {
  @Prop category: string = '';
  @Prop simpleLanguage: string = '';

  @BuilderParam thumbNewBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      Column() {
        this.thumbNewBuilder()
      }.id('thumbNew').width('100%')
      Text(this.category).id('category').width(32).height(24).align(Alignment.End)
      Text(this.simpleLanguage).id('simpleLanguage').align(Alignment.End)
    }.width('100%').margin({ left: 2, right: 2, top: 2, bottom: 2 }).borderRadius(2).shadow({ radius: 2, color: '#26000000', offsetY: 1 })
  }
}
