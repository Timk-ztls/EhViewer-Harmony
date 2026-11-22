/*
 * 上游：app/src/main/res/layout/scene_download.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_download.ets（inventory S0648）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - com.hippo.easyrecyclerview.FastScroller → @BuilderParam fastScrollerBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.hippo.ehviewer.widget.MyEasyRecyclerView → @BuilderParam recyclerViewBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.hippo.widget.FabLayout → @BuilderParam fabLayoutBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.hippo.widget.ProgressView → @BuilderParam downloadProgressViewBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.sxj.paginationlib.PaginationIndicator → @BuilderParam indicatorBuilder（自定义控件，属性由 ui-widget 负责）
 *   - layout_weight=1 已按 layoutWeight 直传（父容器主轴为横时即等价）
 *   - layout_weight=5 已按 layoutWeight 直传（父容器主轴为横时即等价）
 *   - Spinner（未识别节点，未生成）
 */

@Component
export struct SceneDownloadLayout {
  @Prop tip: ResourceStr = $r('app.string.no_download_info');
  @Prop downloadProgressVisibility: Visibility = Visibility.None;
  @Prop indicatorVisibility: Visibility = Visibility.None;
  @Prop tipVisibility: Visibility = Visibility.None;

  @BuilderParam downloadProgressViewBuilder: () => void = this.emptySlot;
  @BuilderParam fabLayoutBuilder: () => void = this.emptySlot;
  @BuilderParam fastScrollerBuilder: () => void = this.emptySlot;
  @BuilderParam indicatorBuilder: () => void = this.emptySlot;
  @BuilderParam recyclerViewBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      // Spinner 未识别
      Stack() {
        Column() {
          this.downloadProgressViewBuilder()
        }.id('downloadProgressView').visibility(this.downloadProgressVisibility)
        Stack() {
          Column() {
            Column() {
              this.recyclerViewBuilder()
            }.id('recyclerView').width('100%').height('100%').layoutWeight(5)
            Column() {
              this.indicatorBuilder()
            }.id('indicator').visibility(this.indicatorVisibility).width('100%').height(40).layoutWeight(1)
          }.width('100%').height('100%')
          Column() {
            this.fastScrollerBuilder()
          }.id('fastScroller').width(30).height('100%')
        }.id('content').width('100%').height('100%')
        Text(this.tip).id('tip').visibility(this.tipVisibility).width(228).textAlign(TextAlign.Center).align(Alignment.Center)
        Column() {
          this.fabLayoutBuilder()
        }.id('fabLayout').width('100%').height('100%')
      }.width('100%').height('100%')
    }.width('100%').height('100%')
  }
}
