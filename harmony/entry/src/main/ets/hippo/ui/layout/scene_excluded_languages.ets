/*
 * 上游：app/src/main/res/layout/scene_excluded_languages.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_excluded_languages.ets（inventory S0649）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:background=?attr/dividerColor（资源未落盘/需重绘）
 *   - com.hippo.easyrecyclerview.EasyRecyclerView → @BuilderParam recyclerViewBuilder（自定义控件，属性由 ui-widget 负责）
 *   - layout_weight=1 已按 layoutWeight 直传（父容器主轴为横时即等价）
 */

@Component
export struct SceneExcludedLanguagesLayout {
  @Prop cancel: string = '@android:string/cancel';
  @Prop deselectAll: ResourceStr = $r('app.string.deselect_all');
  @Prop invertSelection: ResourceStr = $r('app.string.invert_selection');
  @Prop ok: string = '@android:string/ok';
  @Prop selectAll: ResourceStr = $r('app.string.select_all');

  @BuilderParam recyclerViewBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      Row() {
        Text(this.cancel).id('cancel').layoutWeight(1).textAlign(TextAlign.Center)
        Column().width(1).height('100%')
        Text(this.ok).id('ok').layoutWeight(1).textAlign(TextAlign.Center)
      }.width('100%')
      Row() {
        Text(this.selectAll).id('selectAll').layoutWeight(1).textAlign(TextAlign.Center)
        Column().width(1).height('100%')
        Text(this.deselectAll).id('deselectAll').layoutWeight(1).textAlign(TextAlign.Center)
        Column().width(1).height('100%')
        Text(this.invertSelection).id('invertSelection').layoutWeight(1).textAlign(TextAlign.Center)
      }.width('100%')
      Row() {
        Text($r('app.string.language')).layoutWeight(1)
        Text($r('app.string.original')).layoutWeight(1)
        Text($r('app.string.translated')).layoutWeight(1)
        Text($r('app.string.rewrite')).layoutWeight(1)
      }.width('100%')
      Column().width('100%').height(1)
      Column() {
        this.recyclerViewBuilder()
      }.id('recyclerView').width('100%').layoutWeight(1)
    }.width('100%').height('100%')
  }
}
