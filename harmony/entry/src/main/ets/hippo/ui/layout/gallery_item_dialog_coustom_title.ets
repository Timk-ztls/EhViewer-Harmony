/*
 * 上游：app/src/main/res/layout/gallery_item_dialog_coustom_title.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_item_dialog_coustom_title.ets（inventory S0595）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:textColor=?android:attr/textColorAlertDialogListItem（主题属性，需 ThemeManager 注入）
 *   - com.google.android.material.chip.ChipGroup → @BuilderParam tabTagFlowBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.hippo.ehviewer.widget.FixedThumbNew → @BuilderParam dialogThumbBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct GalleryItemDialogCoustomTitleLayout {
  @Prop titleText: string = '';

  @BuilderParam dialogThumbBuilder: () => void = this.emptySlot;
  @BuilderParam tabTagFlowBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      Text(this.titleText).id('titleText').width('100%').fontSize($r('app.float.text_medium')).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
      Row() {
        Column() {
          this.dialogThumbBuilder()
        }.id('dialogThumb').width($r('app.float.gallery_list_thumb_width')).height($r('app.float.gallery_list_thumb_height'))
        Scroll() {
          Column() {
            this.tabTagFlowBuilder()
          }.id('tabTagFlow').width('100%')
        }.align(Alignment.TopStart).width('100%').height($r('app.float.gallery_list_thumb_height'))
      }.width('100%')
    }.width('100%')
  }
}
