/*
 * 上游：app/src/main/res/layout/activity_tag_selector.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_tag_selector.ets（inventory S0558）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_weight=1（ArkUI 用 .layoutWeight()，需按父容器主轴重算）
 *   - androidx.appcompat.widget.Toolbar（未识别节点，未生成）
 *   - layout_width/height=0dp：上游靠 weight 撑开，ArkUI 需 layoutWeight 或固定值
 *   - RecyclerView → List：itemAnimator/ItemDecoration/LayoutManager 无对应物，由 SceneDataSource + LazyForEach 承担
 */

@Component
export struct ActivityTagSelectorLayout {
  @Prop btnConfirmSearch: ResourceStr = $r('app.string.search');
  @Prop tvSelectedEmpty: string = '';
  @Prop tvSelectedSectionTitle: string = '';
  @Prop selectedEmptyVisibility: Visibility = Visibility.None;
  @Prop selectedByGroupVisibility: Visibility = Visibility.None;


  build() {
    Column() {
      // androidx.appcompat.widget.Toolbar 未识别
      Column() {
      }.width('100%').margin({ left: 12, right: 12, top: 12, bottom: 12 }).borderRadius(2).shadow({ radius: 2, color: '#26000000', offsetY: 1 })
      Column() {
        Column() {
          Text(this.tvSelectedSectionTitle).id('tvSelectedSectionTitle').width('100%').fontSize(16)
          Text(this.tvSelectedEmpty).id('tvSelectedEmpty').visibility(this.selectedEmptyVisibility).width('100%').fontSize(14)
          List() {
          }.id('rvSelectedByGroup').visibility(this.selectedByGroupVisibility).width('100%')
        }.width('100%').padding({ left: 12, right: 12, top: 12, bottom: 12 })
      }.id('cardSelectedTags').width('100%').borderRadius(2).shadow({ radius: 2, color: '#26000000', offsetY: 1 })
      List() {
      }.id('rvTagList').width('100%').layoutWeight(1)
      Column() {
        Button(this.btnConfirmSearch).id('btnConfirmSearch').width('100%').height(50).fontSize(16)
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }.width('100%').height('100%')
  }
}
