/*
 * 上游：app/src/main/res/layout-land/activity_set_security.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/land/activity_set_security.ets（inventory S0682）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center_horizontal（Stack 内对齐，已按 Alignment 近似）
 *   - android:layout_weight=1（ArkUI 用 .layoutWeight()，需按父容器主轴重算）
 *   - com.hippo.widget.lockpattern.LockPatternView → @BuilderParam patternViewBuilder（自定义控件，属性由 ui-widget 负责）
 *   - layout_width/height=0dp：上游靠 weight 撑开，ArkUI 需 layoutWeight 或固定值
 */

@Component
export struct ActivitySetSecurityLayout {
  @Prop cancel: string = '@android:string/cancel';
  @Prop set: ResourceStr = $r('app.string.set');
  @Prop fingerprintVisibility: Visibility = Visibility.None;

  @BuilderParam patternViewBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Row() {
      Column() {
        Text($r('app.string.set_pattern_protection_tip')).width('100%').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') }).textAlign(TextAlign.Center)
        Column().width('100%').height(0).layoutWeight(1)
        Checkbox({ name: 'checkbox' }).id('fingerprintCheckbox').visibility(this.fingerprintVisibility)
        Row() {
          Button(this.cancel).id('cancel').width(0).layoutWeight(1)
          Button(this.set).id('set').width(0).layoutWeight(1)
        }.id('buttonpanel').width('100%')
      }.width(0).height('100%').layoutWeight(1)
      Stack() {
        Column() {
          this.patternViewBuilder()
        }.id('patternView')
      }.width(0).height('100%').layoutWeight(1)
    }.width('100%').height('100%')
  }
}
