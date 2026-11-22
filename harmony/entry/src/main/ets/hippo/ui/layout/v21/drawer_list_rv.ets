/*
 * 上游：app/src/main/res/layout-v21/drawer_list_rv.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/v21/drawer_list_rv.ets（inventory S0683）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - android:layout_weight=1（ArkUI 用 .layoutWeight()，需按父容器主轴重算）
 *   - androidx.appcompat.widget.Toolbar（未识别节点，未生成）
 *   - com.hippo.easyrecyclerview.EasyRecyclerView → @BuilderParam recyclerViewDrawerBuilder（自定义控件，属性由 ui-widget 负责）
 *   - layout_width/height=0dp：上游靠 weight 撑开，ArkUI 需 layoutWeight 或固定值
 */

@Component
export struct DrawerListRvLayout {
  @Prop tip: string = '';
  @Prop tipVisibility: Visibility = Visibility.None;

  @BuilderParam recyclerViewDrawerBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      // androidx.appcompat.widget.Toolbar 未识别
      Stack() {
        Text(this.tip).id('tip').visibility(this.tipVisibility).align(Alignment.Center)
        Column() {
          this.recyclerViewDrawerBuilder()
        }.id('recyclerViewDrawer').width('100%').height('100%')
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%')
  }
}
