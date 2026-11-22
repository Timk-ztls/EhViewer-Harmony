/*
 * 上游：app/src/main/res/layout/activity_gallery_fallback.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_gallery_fallback.ets（inventory S0551）
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
export struct ActivityGalleryFallbackLayout {
  @Prop glFallbackClose: ResourceStr = $r('app.string.gallery_gl_fallback_action_close');


  build() {
    Stack() {
      Column() {
        Text($r('app.string.gallery_gl_fallback_title')).textAlign(TextAlign.Center)
        Text($r('app.string.gallery_gl_fallback_message')).textAlign(TextAlign.Center)
        Button(this.glFallbackClose).id('glFallbackClose')
      }.width('100%').height('100%')
    }.id('main').width('100%').height('100%').padding({ left: 24, right: 24, top: 24, bottom: 24 })
  }
}
