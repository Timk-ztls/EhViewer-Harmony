/*
 * 上游：app/src/main/res/layout/scene_gallery_top_list.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_gallery_top_list.ets（inventory S0656）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - com.hippo.widget.ProgressView → @BuilderParam dataLoadingViewBuilder（自定义控件，属性由 ui-widget 负责）
 *   - RecyclerView → List：itemAnimator/ItemDecoration/LayoutManager 无对应物，由 SceneDataSource + LazyForEach 承担
 *   - Spinner（未识别节点，未生成）
 */

@Component
export struct SceneGalleryTopListLayout {
  @BuilderParam dataLoadingViewBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Column() {
        this.dataLoadingViewBuilder()
      }.id('dataLoadingView')
      Stack() {
        // Spinner 未识别
        Scroll() {
          List() {
          }.id('topListRecyclerView').width('100%')
        }.align(Alignment.TopStart).width('100%').height('100%')
      }.id('pageDetailView').width('100%').height('100%')
    }.id('mainLayout').width('100%').height('100%')
  }
}
