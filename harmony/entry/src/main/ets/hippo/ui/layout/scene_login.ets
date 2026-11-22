/*
 * 上游：app/src/main/res/layout/scene_login.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_login.ets（inventory S0659）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=center_horizontal（Stack 内对齐，已按 Alignment 近似）
 *   - android:textColor=?attr/colorAccent（主题属性，需 ThemeManager 注入）
 *   - android:textColor=?attr/colorPrimary（主题属性，需 ThemeManager 注入）
 *   - android:textColor=?attr/textColorThemeAccent（主题属性，需 ThemeManager 注入）
 *   - com.hippo.widget.ProgressView → @BuilderParam slot3Builder（自定义控件，属性由 ui-widget 负责）
 */

@Component
export struct SceneLoginLayout {
  @Prop guestMode: ResourceStr = $r('app.string.guest_mode');
  @Prop register: ResourceStr = $r('app.string.register');
  @Prop signIn: ResourceStr = $r('app.string.sign_in');
  @Prop signInViaCookies: ResourceStr = $r('app.string.sign_in_via_cookies');
  @Prop signInViaWebview: ResourceStr = $r('app.string.sign_in_via_webview');
  @Prop progressVisibility: Visibility = Visibility.None;

  @BuilderParam slot3Builder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          Image('').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
          TextInput({ text: '' }).id('usernameLayout')
          TextInput({ text: '' }).id('passwordLayout')
          Column().layoutWeight(1)
          Row() {
            Button(this.register).id('register').layoutWeight(1)
            Button(this.signIn).id('signIn').layoutWeight(1)
          }.id('buttonpanel').width('100%')
          Text(this.signInViaWebview).id('signInViaWebview')
          Text(this.signInViaCookies).id('signInViaCookies')
          Text(this.guestMode).id('guestMode')
        }.width('100%').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
      }.id('loginForm').align(Alignment.TopStart).width('100%').height('100%')
      Stack() {
        Column() {
          this.slot3Builder()
        }.id('slot3')
      }.id('progress').visibility(this.progressVisibility).width('100%').height('100%')
    }.width('100%').height('100%')
  }
}
