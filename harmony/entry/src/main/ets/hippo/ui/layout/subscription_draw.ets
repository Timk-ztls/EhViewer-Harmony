/*
 * 上游：app/src/main/res/layout/subscription_draw.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/subscription_draw.ets（inventory S0673）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:background=@drawable/shadow_bottom → 已迁组件 ShadowBottom()，需手工改为子元素叠加或 .background()
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - android:layout_weight=1（ArkUI 用 .layoutWeight()，需按父容器主轴重算）
 *   - androidx.appcompat.widget.Toolbar（未识别节点，未生成）
 *   - com.hippo.widget.ProgressView → @BuilderParam tagListViewProgressBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct SubscriptionDrawLayout {
  @Prop notLoginText: ResourceStr = $r('app.string.settings_eh_identity_cookies_tourist');
  @Prop tip: string = '';
  @Prop tipVisibility: Visibility = Visibility.None;
  @Prop notLoginVisibility: Visibility = Visibility.None;

  @BuilderParam tagListViewProgressBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      // androidx.appcompat.widget.Toolbar 未识别
      Stack() {
        Stack() {
          Column().width('100%').height(8)
          Text(this.tip).id('tip').visibility(this.tipVisibility).align(Alignment.Center)
          List() {
          }.id('listView').width('100%').height('100%')
        }.id('tagListParent').width('100%').height('100%')
        Column() {
          this.tagListViewProgressBuilder()
        }.id('tagListViewProgress')
        Text(this.notLoginText).id('notLoginText').visibility(this.notLoginVisibility).width('100%').height('100%').fontSize($r('app.float.text_super_large')).textAlign(TextAlign.Center)
      }.width('100%').height('100%')
    }.width('100%').height('100%')
  }
}
