/*
 * 上游：app/src/main/res/layout/activity_hosts.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_hosts.ets（inventory S0553）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - com.hippo.easyrecyclerview.EasyRecyclerView → @BuilderParam recyclerViewBuilder（自定义控件，属性由 ui-widget 负责）
 *   - com.hippo.widget.FabLayout → @BuilderParam fabLayoutBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct ActivityHostsLayout {
  @Prop tip: ResourceStr = $r('app.string.hosts_tip');
  @Prop tipColor: ResourceColor = '#8A000000';
  @Prop listVisible: boolean = false;
  @Prop tipVisible: boolean = true;

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
      }
      .id('recyclerView')
      .width('100%')
      .height('100%')
      .visibility(this.listVisible ? Visibility.Visible : Visibility.None)

      Text(this.tip)
        .id('tip')
        .fontSize($r('app.float.text_super_large'))
        .fontColor(this.tipColor)
        .textAlign(TextAlign.Center)
        .align(Alignment.Center)
        .visibility(this.tipVisible ? Visibility.Visible : Visibility.None)

      Column() {
        this.fabLayoutBuilder()
      }
      .id('fabLayout')
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%')
  }
}
