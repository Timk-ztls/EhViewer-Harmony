/*
 * 上游：app/src/main/res/layout/gallery_list_jump_selector.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_list_jump_selector.ets（inventory S0597）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - com.hippo.ehviewer.widget.MyRadioGroup → @BuilderParam jumpDatePickerGroupBuilder（自定义控件，属性由 ui-widget 负责）
 *   - DatePicker（未识别节点，未生成）
 */

@Component
export struct GalleryListJumpSelectorLayout {
  @Prop foundMessage: string = '';
  @Prop gotoJump: ResourceStr = $r('app.string.gallery_list_jump_now');
  @Prop pickerDate: ResourceStr = $r('app.string.gallery_list_select_jump_date');

  @BuilderParam jumpDatePickerGroupBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      Text($r('app.string.gallery_list_time_jump_dialog_title')).width('100%').padding({ left: $r('app.float.title_text_top_padding'), right: $r('app.float.title_text_top_padding'), top: $r('app.float.title_text_top_padding'), bottom: $r('app.float.title_text_top_padding') }).textAlign(TextAlign.Center)
      Text(this.foundMessage).id('foundMessage').width('100%').padding({ left: $r('app.float.title_text_top_padding'), right: $r('app.float.title_text_top_padding'), top: $r('app.float.title_text_top_padding'), bottom: $r('app.float.title_text_top_padding') }).textAlign(TextAlign.Center)
      Column() {
        this.jumpDatePickerGroupBuilder()
      }.id('jumpDatePickerGroup').width('100%').padding({ left: $r('app.float.title_text_top_padding'), right: $r('app.float.title_text_top_padding'), top: $r('app.float.title_text_top_padding'), bottom: $r('app.float.title_text_top_padding') })
      // DatePicker 未识别
      Row() {
        Button(this.pickerDate).id('pickerDate')
        Column().width($r('app.float.button_space_between'))
        Button(this.gotoJump).id('gotoJump')
      }.width('100%')
    }.width('100%').padding({ left: $r('app.float.title_text_top_padding'), right: $r('app.float.title_text_top_padding'), top: $r('app.float.title_text_top_padding'), bottom: $r('app.float.title_text_top_padding') })
  }
}
