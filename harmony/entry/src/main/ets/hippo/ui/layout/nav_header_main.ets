/*
 * 上游：app/src/main/res/layout/nav_header_main.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/nav_header_main.ets（inventory S0637）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - android:textColor=@android:color/white（主题属性，需 ThemeManager 注入）
 *   - com.hippo.widget.AvatarImageView → @BuilderParam avatarBuilder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct NavHeaderMainLayout {
  @Prop displayName: string = '';
  @Prop headerBackgroundSrc: ResourceStr = '';

  @BuilderParam avatarBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Image(this.headerBackgroundSrc).id('headerBackground').width('100%').height('100%')
      Column() {
        Column() {
          this.avatarBuilder()
        }.id('avatar').width(64).height(64)
        Text(this.displayName).id('displayName').fontSize($r('app.float.text_small')).align(Alignment.Center)
      }
    }.width('100%').height(160)
  }
}
