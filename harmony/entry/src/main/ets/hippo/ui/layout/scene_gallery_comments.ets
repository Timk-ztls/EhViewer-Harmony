/*
 * 上游：app/src/main/res/layout/scene_gallery_comments.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_gallery_comments.ets（inventory S0651）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - com.hippo.easyrecyclerview.EasyRecyclerView → @BuilderParam recyclerViewBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.hippo.reveal.RevealLinearLayout → @BuilderParam editPanelBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.hippo.widget.FabLayout → @BuilderParam fabLayoutBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct SceneGalleryCommentsLayout {
  @Prop tip: ResourceStr = $r('app.string.no_one_comments_gallery');

  @BuilderParam editPanelBuilder: () => void = this.emptySlot;
  @BuilderParam fabLayoutBuilder: () => void = this.emptySlot;
  @BuilderParam recyclerViewBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Column() {
        this.recyclerViewBuilder()
      }.id('recyclerView').width('100%').height('100%')
      Text(this.tip).id('tip').width(228).textAlign(TextAlign.Center).align(Alignment.Center)
      Column() {
        this.editPanelBuilder()
      }.id('editPanel').width('100%')
      Column() {
        this.fabLayoutBuilder()
      }.id('fabLayout').width('100%').height('100%')
    }.width('100%').height('100%')
  }
}
